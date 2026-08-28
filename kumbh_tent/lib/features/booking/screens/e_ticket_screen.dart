import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:kumbh_tent/core/theme/app_colors.dart';
import 'package:kumbh_tent/shared/widgets/premium_badge.dart';
import 'package:kumbh_tent/shared/widgets/premium_button.dart';

class ETicketScreen extends StatefulWidget {
  final Map<String, dynamic> booking;
  const ETicketScreen({super.key, required this.booking});

  @override
  State<ETicketScreen> createState() => _ETicketScreenState();
}

class _ETicketScreenState extends State<ETicketScreen> {
  final GlobalKey _ticketKey = GlobalKey();
  bool _isDownloading = false;
  bool _isSharing = false;

  Future<File?> _captureTicket() async {
    try {
      final boundary =
          _ticketKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/kumbh_ticket_${widget.booking['ref']}.png',
      );
      await file.writeAsBytes(bytes);
      return file;
    } catch (e) {
      return null;
    }
  }

  Future<void> _downloadTicket() async {
    setState(() => _isDownloading = true);
    try {
      final file = await _captureTicket();
      if (file == null) throw Exception('Failed to capture ticket');
      await Gal.putImage(file.path);
      if (mounted) _snack('Ticket saved to gallery!', AppColors.success);
    } catch (e) {
      if (mounted) _snack('Error: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _shareTicket() async {
    setState(() => _isSharing = true);
    try {
      final file = await _captureTicket();
      if (file == null) throw Exception('Failed to capture ticket');
      final ref = widget.booking['ref'] ?? '';
      final tent = widget.booking['tent'] ?? '';
      final checkIn = widget.booking['check_in'] ?? '';
      final checkOut = widget.booking['check_out'] ?? '';
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text:
              'My Kumbh Tent Booking\nRef: $ref\n$tent\n$checkIn to $checkOut\nNashik Kumbh 2027',
          subject: 'Kumbh Tent Booking - $ref',
        ),
      );
    } catch (e) {
      if (mounted) _snack('Error sharing: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  void _snack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final String qrData =
        'KUMBH2027|${widget.booking['ref']}|${widget.booking['tent']}'
        '|${widget.booking['check_in']}|${widget.booking['check_out']}'
        '|${widget.booking['guests']}';

    final status = widget.booking['status'] ?? 'pending';
    final isConfirmed = status == 'confirmed';
    final isPending = status == 'pending';
    final isCancelled = status == 'cancelled';
    final badgeStyle = isConfirmed
        ? PremiumBadgeStyle.success
        : isPending
        ? PremiumBadgeStyle.gold
        : isCancelled
        ? PremiumBadgeStyle.danger
        : PremiumBadgeStyle.dark;
    final statusLabel = isConfirmed
        ? 'BOOKING CONFIRMED'
        : isPending
        ? 'PAYMENT PENDING - PAY AT TENT'
        : isCancelled
        ? 'BOOKING CANCELLED'
        : 'COMPLETED';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'E-Ticket',
          style: GoogleFonts.poppins(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          _isSharing
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: AppColors.saffron,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.share_outlined),
                  onPressed: _shareTicket,
                ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          children: [
            // ── Status banner ─────────────────────────────────
            Align(
              alignment: Alignment.center,
              child: PremiumBadge(label: statusLabel, style: badgeStyle),
            ),

            const SizedBox(height: 20),

            // ── Ticket card ───────────────────────────────────
            RepaintBoundary(
              key: _ticketKey,
              child: Container(
                color: AppColors.background,
                child: Stack(
                  children: [
                    Opacity(
                      opacity: isCancelled ? 0.55 : 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      // Ticket header
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.saffron, AppColors.saffronDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Text(
                                  '⛺',
                                  style: TextStyle(fontSize: 32),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Kumbh Tent Booking',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                      Text(
                                        'Nashik Kumbh 2027',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(
                                      alpha: 0.2,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '⛺ ${widget.booking['class']?.toString().toUpperCase() ?? 'TENT'}',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              widget.booking['tent'] ?? '',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  color: Colors.white70,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  widget.booking['location'] ?? '',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const _DashedDivider(),

                      // Booking details
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _detailItem(
                                  'Check-in',
                                  widget.booking['check_in'] ?? '-',
                                ),
                                Container(
                                  width: 1,
                                  height: 40,
                                  color: AppColors.border,
                                ),
                                _detailItem(
                                  'Check-out',
                                  widget.booking['check_out'] ?? '-',
                                ),
                                Container(
                                  width: 1,
                                  height: 40,
                                  color: AppColors.border,
                                ),
                                _detailItem(
                                  'Nights',
                                  '${widget.booking['nights'] ?? '-'}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Divider(color: AppColors.border, height: 1),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _detailItem(
                                  'Guests',
                                  '${widget.booking['guests'] ?? '-'}',
                                ),
                                _detailItem(
                                  'Total',
                                  '₹${widget.booking['total'] ?? '-'}',
                                ),
                              ],
                            ),

                            if (_hasGstBreakdown) ...[
                              const SizedBox(height: 16),
                              const Divider(
                                color: AppColors.border,
                                height: 1,
                              ),
                              const SizedBox(height: 16),
                              _gstBreakdown(),
                            ],

                            const SizedBox(height: 16),
                            const Divider(color: AppColors.border, height: 1),
                            const SizedBox(height: 16),

                            // Booking ref box
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.softSurface,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Booking Reference',
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                      Text(
                                        widget.booking['ref'] ?? '',
                                        style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.saffronDark,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      Clipboard.setData(
                                        ClipboardData(
                                          text: widget.booking['ref'] ?? '',
                                        ),
                                      );
                                      _snack(
                                        'Booking ref copied!',
                                        AppColors.success,
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            AppColors.saffron,
                                            AppColors.saffronDark,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          10,
                                        ),
                                      ),
                                      child: Text(
                                        'Copy',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const _DashedDivider(),

                      // QR Code
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Text(
                              isCancelled
                                  ? 'Ticket Void'
                                  : 'Scan at Entry Gate',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isCancelled
                                    ? AppColors.error
                                    : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Opacity(
                                  opacity: isCancelled ? 0.25 : 1,
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AppColors.cardBorder,
                                        width: 2,
                                      ),
                                    ),
                                    child: QrImageView(
                                      data: qrData,
                                      version: QrVersions.auto,
                                      size: 200,
                                      backgroundColor: Colors.white,
                                      eyeStyle: const QrEyeStyle(
                                        eyeShape: QrEyeShape.square,
                                        color: AppColors.saffronDark,
                                      ),
                                      dataModuleStyle:
                                          const QrDataModuleStyle(
                                            dataModuleShape:
                                                QrDataModuleShape.square,
                                            color: AppColors.textPrimary,
                                          ),
                                    ),
                                  ),
                                ),
                                if (isCancelled)
                                  Icon(
                                    Icons.block_rounded,
                                    color: AppColors.error.withValues(
                                      alpha: 0.85,
                                    ),
                                    size: 72,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isCancelled
                                  ? 'This ticket has been cancelled and is not valid for entry.'
                                  : 'Show this QR code at the camp entrance',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: isCancelled
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isCancelled
                                    ? AppColors.error
                                    : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Footer
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: const BoxDecoration(
                          color: AppColors.softSurface,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              '⛺',
                              style: TextStyle(fontSize: 14),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Kumbh Tent Booking - Nashik Kumbh 2027',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                    ),
                    if (isCancelled)
                      Positioned.fill(
                        child: Center(
                          child: Transform.rotate(
                            angle: -0.45,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.error,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: 0.25,
                                    ),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                              child: Text(
                                'CANCELLED',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Action buttons ────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.saffron,
                      side: const BorderSide(color: AppColors.saffron),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _isSharing ? null : _shareTicket,
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PremiumButton(
                    label: _isDownloading ? 'Saving...' : 'Download',
                    icon: _isDownloading ? null : Icons.download_rounded,
                    verticalPadding: 14,
                    onPressed: _isDownloading ? null : _downloadTicket,
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  bool get _hasGstBreakdown {
    final taxable = widget.booking['taxable_amount'];
    final tax = widget.booking['tax'];
    return taxable is num && tax is num && taxable > 0;
  }

  Widget _gstBreakdown() {
    final taxable = (widget.booking['taxable_amount'] as num).toDouble();
    final tax = (widget.booking['tax'] as num).toDouble();
    final cgst = tax / 2;
    final sgst = tax / 2;
    final ratePercent = taxable > 0 ? (tax / taxable * 100) : 0;
    final halfRate = (ratePercent / 2).toStringAsFixed(1);

    Widget row(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: bold ? AppColors.textPrimary : AppColors.textMuted,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: bold ? AppColors.textPrimary : AppColors.textMuted,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GST BREAKUP',
          style: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.saffronDark,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        row('Taxable Amount', '₹${taxable.toStringAsFixed(0)}'),
        row('CGST ($halfRate%)', '₹${cgst.toStringAsFixed(0)}'),
        row('SGST ($halfRate%)', '₹${sgst.toStringAsFixed(0)}'),
        row(
          'Total GST (${ratePercent.toStringAsFixed(0)}%)',
          '₹${tax.toStringAsFixed(0)}',
          bold: true,
        ),
      ],
    );
  }

  Widget _detailItem(String label, String value) => Column(
    children: [
      Text(
        label,
        style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textMuted),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    ],
  );
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(10),
            ),
            border: const Border(
              top: BorderSide(color: AppColors.border),
              right: BorderSide(color: AppColors.border),
              bottom: BorderSide(color: AppColors.border),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const dashWidth = 6.0;
              const dashSpace = 4.0;
              final dashCount = (constraints.maxWidth / (dashWidth + dashSpace))
                  .floor();
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  dashCount,
                  (_) => Container(
                    width: dashWidth,
                    height: 1,
                    color: AppColors.border,
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(10),
            ),
            border: const Border(
              top: BorderSide(color: AppColors.border),
              left: BorderSide(color: AppColors.border),
              bottom: BorderSide(color: AppColors.border),
            ),
          ),
        ),
      ],
    );
  }
}
