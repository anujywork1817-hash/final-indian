import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';
import 'package:kumbh_tent/features/booking/screens/e_ticket_screen.dart';
import 'package:kumbh_tent/features/booking/screens/review_screen.dart';
import 'package:kumbh_tent/features/tents/screens/browse_screen.dart';
import 'package:kumbh_tent/shared/widgets/premium_badge.dart';
import 'package:kumbh_tent/shared/widgets/shimmer_tent_card.dart';
import 'package:kumbh_tent/shared/widgets/premium_button.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => MyBookingsScreenState();
}

class MyBookingsScreenState extends State<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<dynamic> _bookings = [];
  bool _loading = true;
  String? _error;

  // Guards against double-cancellation from spamming the Cancel
  // button (or the confirm dialog) before the previous request
  // for the same booking has returned. The server is already the
  // real guard (a row lock plus a status check reject a second
  // cancel outright), but this avoids firing duplicate requests
  // and duplicate confirmation dialogs from the client at all.
  final Set<String> _cancelling = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  /// Re-fetches the booking list. HomeScreen holds a GlobalKey to this
  /// state and calls this whenever the Bookings tab is selected —
  /// this screen sits in an IndexedStack alongside the other tabs, so
  /// it is built once and kept alive for the lifetime of the app;
  /// without an explicit refresh, initState()'s one-time _load() is
  /// the only fetch that ever happens, and a booking made after that
  /// (or completed just now, straight from the payment flow) would
  /// only show up after a manual pull-to-refresh.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token') ?? '';
      final phone = await storage.read(key: 'user_phone') ?? '';
      final res = await http.get(
        Uri.parse('$kBaseUrl/bookings'),
        headers: {'Authorization': 'Bearer $token', 'X-User-Phone': phone},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _bookings = (data['bookings'] ?? data) as List;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Could not load bookings';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Something went wrong loading your bookings';
        _loading = false;
      });
    }
  }

  Future<void> _cancel(String ref) async {
    if (_cancelling.contains(ref)) return; // already in flight — ignore the extra tap
    _cancelling.add(ref);
    try {
      await _doCancel(ref);
    } finally {
      _cancelling.remove(ref);
    }
  }

  Future<void> _doCancel(String ref) async {
    // Ask the backend what this cancellation actually returns,
    // so the dialog states a real number instead of leaving the
    // user to guess. Null means the quote couldn't be fetched —
    // we then fall back to a message that promises nothing.
    final quote = await ApiService.getRefundQuote(ref);
    if (!mounted) return;

    final refundAmount = (quote?['refund_amount'] as num?)?.toDouble();
    final quoteMessage = quote?['message'] as String?;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Cancel Booking',
          style: GoogleFonts.poppins(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to cancel this booking?',
              style: GoogleFonts.poppins(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            if (quoteMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (refundAmount != null && refundAmount > 0)
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (refundAmount != null && refundAmount > 0)
                        ? Colors.green.shade200
                        : Colors.orange.shade200,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      (refundAmount != null && refundAmount > 0)
                          ? Icons.account_balance_wallet_outlined
                          : Icons.info_outline,
                      size: 16,
                      color: (refundAmount != null && refundAmount > 0)
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        quoteMessage,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: (refundAmount != null && refundAmount > 0)
                              ? Colors.green.shade900
                              : Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'No',
              style: GoogleFonts.poppins(
                color: AppColors.saffron,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Yes, Cancel',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token') ?? '';
      final phone = await storage.read(key: 'user_phone') ?? '';
      final res = await http.put(
        Uri.parse('$kBaseUrl/bookings/$ref/cancel'),
        headers: {'Authorization': 'Bearer $token', 'X-User-Phone': phone},
      );
      if (!mounted) return;

      // Previously the response was discarded entirely and every
      // failure was swallowed, so a rejected cancellation looked
      // identical to a successful one.
      final body = res.body.isNotEmpty
          ? jsonDecode(res.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (res.statusCode == 200) {
        _snack(
          (body['message'] as String?) ?? 'Booking cancelled',
          AppColors.success,
        );
      } else {
        _snack(
          (body['error'] as String?) ?? 'Could not cancel booking',
          AppColors.error,
        );
      }
      _load();
    } catch (e) {
      if (mounted) _snack('Could not cancel booking', AppColors.error);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _clear(String ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Remove Booking?',
          style: GoogleFonts.poppins(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Remove this booking from your list?',
          style: GoogleFonts.poppins(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'No',
              style: GoogleFonts.poppins(color: AppColors.saffron),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Remove',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token') ?? '';
      final phone = await storage.read(key: 'user_phone') ?? '';
      await http.delete(
        Uri.parse('$kBaseUrl/bookings/$ref'),
        headers: {'Authorization': 'Bearer $token', 'X-User-Phone': phone},
      );
      setState(
        () => _bookings.removeWhere(
          (b) => (b['booking_ref'] ?? b['id'])?.toString() == ref,
        ),
      );
    } catch (_) {}
  }

  Future<void> _clearAll() async {
    final cancelled = _bookings
        .where(
          (b) => (b['status'] ?? '').toString().toLowerCase() == 'cancelled',
        )
        .toList();
    if (cancelled.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clear All Cancelled?',
          style: GoogleFonts.poppins(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Remove all ${cancelled.length} cancelled booking(s)?',
          style: GoogleFonts.poppins(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'No',
              style: GoogleFonts.poppins(color: AppColors.saffron),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Clear All',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token') ?? '';
      final phone = await storage.read(key: 'user_phone') ?? '';
      for (final b in cancelled) {
        final ref = (b['booking_ref'] ?? b['id'])?.toString() ?? '';
        await http.delete(
          Uri.parse('$kBaseUrl/bookings/$ref'),
          headers: {'Authorization': 'Bearer $token', 'X-User-Phone': phone},
        );
      }
      setState(
        () => _bookings.removeWhere(
          (b) => (b['status'] ?? '').toString().toLowerCase() == 'cancelled',
        ),
      );
    } catch (_) {}
  }

  List<dynamic> _filtered(String filter) {
    if (filter == 'all') return _bookings;
    return _bookings
        .where((b) => (b['status'] ?? '').toString().toLowerCase() == filter)
        .toList();
  }

  bool get _hasCancelled => _bookings.any(
    (b) => (b['status'] ?? '').toString().toLowerCase() == 'cancelled',
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'My Bookings',
          style: GoogleFonts.poppins(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
          if (_hasCancelled)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clearAll,
              tooltip: 'Clear All Cancelled',
            ),
        ],
      ),
      body: Column(
        children: [
          _segmentedTabs(),
          Expanded(
            child: _loading
                ? ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: 3,
                    itemBuilder: (context, i) => const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: SizedBox(height: 260, child: ShimmerTentCard()),
                    ),
                  )
                : _error != null
                ? _errorState(_error!)
                : TabBarView(
                    controller: _tab,
                    children: [
                      _list('all'),
                      _list('confirmed'),
                      _list('completed'),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static const _tabLabels = ['All', 'Active', 'Completed'];

  Widget _segmentedTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: AnimatedBuilder(
        animation: _tab.animation ?? _tab,
        builder: (context, _) {
          final position =
              _tab.animation?.value ?? _tab.index.toDouble();
          return Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.softSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Stack(
              children: [
                AnimatedAlign(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  alignment: Alignment(
                    -1 + (position.clamp(0, 2) / 1),
                    0,
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 1 / _tabLabels.length,
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: List.generate(_tabLabels.length, (i) {
                    final selected = _tab.index == i;
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _tab.animateTo(i),
                        child: SizedBox(
                          height: 36,
                          child: Center(
                            child: Text(
                              _tabLabels[i],
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: selected
                                    ? AppColors.saffron
                                    : AppColors.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _list(String filter) {
    final items = _filtered(filter);
    if (items.isEmpty) return _emptyState();
    return RefreshIndicator(
      color: AppColors.saffron,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final ref =
              (items[i]['booking_ref'] ?? items[i]['id'])?.toString() ?? '';
          return _BookingCard(
            booking: items[i],
            onCancel: () => _cancel(ref),
            onClear: () => _clear(ref),
            onTicket: () {
              final b = items[i];
              String fmtDate(dynamic iso) {
                if (iso == null) return '-';
                try {
                  final d = DateTime.parse(iso.toString());
                  return '${['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month]} ${d.day}, ${d.year}';
                } catch (_) {
                  return iso.toString();
                }
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ETicketScreen(
                    booking: {
                      'ref': b['booking_ref'] ?? b['id']?.toString() ?? '',
                      'tent': b['tent_name'] ?? '',
                      'location': b['location'] ?? '',
                      'class': b['class'] ?? '',
                      'check_in': fmtDate(b['check_in']),
                      'check_out': fmtDate(b['check_out']),
                      'nights': b['nights'] ?? 0,
                      'guests': b['guests'] ?? 1,
                      'total': (b['total_amount'] ?? b['total_price'] ?? 0)
                          .toString(),
                      'taxable_amount':
                          ((b['base_amount'] ?? 0) as num).toDouble() -
                          ((b['discount'] ?? 0) as num).toDouble(),
                      'tax': ((b['tax'] ?? 0) as num).toDouble(),
                      'status': b['status'] ?? 'pending',
                      'payment_id': b['payment_id'] ?? '',
                    },
                  ),
                ),
              );
            },
            onReview: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReviewScreen(booking: items[i]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeInOut,
            builder: (context, value, child) => Transform.translate(
              offset: Offset(0, -6 * (0.5 - (value - 0.5).abs()) * 2),
              child: child,
            ),
            child: const Text('🏕️', style: TextStyle(fontSize: 64)),
          ),
          const SizedBox(height: 20),
          Text(
            'No stays booked yet',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your next memorable Kumbh experience\nis waiting for you.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: AppColors.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 200,
            child: PremiumButton(
              label: 'Explore Tents',
              icon: Icons.explore_rounded,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BrowseScreen()),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _errorState(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            'Something went wrong',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 160,
            child: PremiumButton(label: 'Try Again', onPressed: _load),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }
}

class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback onCancel;
  final VoidCallback onClear;
  final VoidCallback onTicket;
  final VoidCallback onReview;

  const _BookingCard({
    required this.booking,
    required this.onCancel,
    required this.onClear,
    required this.onTicket,
    required this.onReview,
  });

  String _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final d = DateTime.parse(iso);
      return '${['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month]} ${d.day}, ${d.year}';
    } catch (_) {
      return iso;
    }
  }

  String get _status =>
      (booking['status'] ?? 'pending').toString().toLowerCase();

  PremiumBadgeStyle get _badgeStyle {
    switch (_status) {
      case 'confirmed':
        return PremiumBadgeStyle.success;
      case 'cancelled':
        return PremiumBadgeStyle.danger;
      case 'pending':
        return PremiumBadgeStyle.gold;
      case 'no_show':
        return PremiumBadgeStyle.dark;
      default:
        return PremiumBadgeStyle.dark;
    }
  }

  Color get _accentColor {
    switch (_status) {
      case 'confirmed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      case 'pending':
        return AppColors.goldWarm;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tentName = booking['tent_name'] ?? 'Tent';
    final location = booking['location'] ?? booking['tent_location'] ?? '';
    final checkIn = _fmt(booking['check_in']);
    final checkOut = _fmt(booking['check_out']);
    final ref = booking['booking_ref'] ?? booking['id'] ?? '—';
    final total = booking['total_price'] ?? booking['total_amount'] ?? 0;
    final cancelled = _status == 'cancelled';
    final noShow = _status == 'no_show';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: _accentColor),
            Expanded(child: _cardBody(tentName, location, checkIn, checkOut, ref, total, cancelled, noShow)),
          ],
        ),
      ),
    );
  }

  Widget _cardBody(
    dynamic tentName,
    dynamic location,
    String checkIn,
    String checkOut,
    dynamic ref,
    dynamic total,
    bool cancelled,
    bool noShow,
  ) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.saffron.withValues(alpha: 0.15),
                        AppColors.goldWarm.withValues(alpha: 0.15),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.holiday_village_rounded,
                    color: AppColors.saffron,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tentName,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (location.isNotEmpty)
                        Text(
                          location,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                PremiumBadge(
                  label: _status.toUpperCase(),
                  style: _badgeStyle,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // Dates
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              children: [
                Expanded(child: _col('CHECK-IN', checkIn)),
                Expanded(child: _col('CHECK-OUT', checkOut, end: true)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Divider(color: AppColors.border, thickness: 1),
          ),

          // Ref + Total
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Booking ID',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: AppColors.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        ref.toString(),
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Total paid',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: AppColors.textMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      '₹${total.toString()}',
                      style: GoogleFonts.poppins(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: AppColors.saffronDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // No-show explanation — the guest never checked in and
          // the booking has moved past user control; there is no
          // cancel/clear action, just the fact and (if applicable)
          // the refund state, which the API already returns for
          // no-show bookings via the same refunds join.
          if (noShow)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.softSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.event_busy,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (booking['refund_message'] as String?) ??
                            'This booking was marked as a no-show — check-in was not recorded before the cutoff.',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onTicket,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('E-Ticket'),
                      ),
                    ),
                    if (!noShow) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: cancelled ? onClear : onCancel,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: BorderSide(
                              color: AppColors.error.withValues(alpha: 0.4),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(cancelled ? 'Clear' : 'Cancel'),
                        ),
                      ),
                    ],
                  ],
                ),
                if (!cancelled && !noShow) ...[
                  const SizedBox(height: 8),
                  PremiumButton(
                    label: 'Rate & review your stay',
                    icon: Icons.star_rounded,
                    onPressed: onReview,
                    verticalPadding: 12,
                  ),
                ],
              ],
            ),
          ),
        ],
      );
  }

  Widget _col(String label, String value, {bool end = false}) => Column(
    crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 10,
          color: AppColors.textMuted,
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    ],
  );
}
