-- The tent listing query (GET /api/v1/tents) joins bookings on tent_id and
-- filters by status to compute live availability. Without a matching index
-- this was a full sequential scan on bookings for every request, which is
-- the main reason the endpoint collapsed under concurrent load testing.
CREATE INDEX IF NOT EXISTS idx_bookings_tent_status ON bookings(tent_id, status);
CREATE INDEX IF NOT EXISTS idx_tents_is_active ON tents(is_active);
