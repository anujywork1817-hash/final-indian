package main

import (
	"context"
	"fmt"
)

// runIfLeader gates a scheduled job body behind a Postgres session
// advisory lock so that only one running instance of this service
// actually executes it per tick.
//
// BUG (distributed cron lock): startReminderScheduler,
// startRefundRetryWorker, startNoShowSweeper and startNewsPoller are
// each a `for { doWork(); time.Sleep(interval) }` loop started in
// every process — fine with one instance, but this service runs
// behind an autoscaling group and every replica was running every
// job on its own clock. The per-notification unique-key dedup in
// notifications.go and the ON CONFLICT DO NOTHING on news_articles
// already stop a user from being double-notified, so nothing was
// silently broken — but every extra instance meant an extra full
// table scan per tick and, worse, an extra hit against NewsData's
// rate-limited API for every poll, scaling with instance count
// instead of staying constant.
//
// A session-level advisory lock (pg_try_advisory_lock) is held for
// the duration of one job run on a single dedicated *sql.Conn — a
// losing instance's pg_try_advisory_lock returns false immediately
// (never blocks) and just skips this tick, trying again next
// interval.
func runIfLeader(lockKey string, fn func()) {
	ctx := context.Background()
	conn, err := db.Conn(ctx)
	if err != nil {
		fmt.Printf("cron lock (%s): could not get a connection: %v — running anyway\n", lockKey, err)
		fn()
		return
	}
	defer conn.Close()

	var acquired bool
	if err := conn.QueryRowContext(ctx,
		`SELECT pg_try_advisory_lock(hashtext($1))`, lockKey,
	).Scan(&acquired); err != nil {
		// Can't confirm we're the leader — fail open rather than
		// silently never running the job on any instance. Duplicate
		// side effects, if any, are already deduped at the row level.
		fmt.Printf("cron lock (%s): acquire failed: %v — running anyway\n", lockKey, err)
		fn()
		return
	}
	if !acquired {
		fmt.Printf("cron lock (%s): held by another instance, skipping this tick\n", lockKey)
		return
	}
	defer conn.ExecContext(ctx, `SELECT pg_advisory_unlock(hashtext($1))`, lockKey)

	fn()
}
