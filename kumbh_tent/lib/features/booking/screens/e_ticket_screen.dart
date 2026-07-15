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
import 'package:kumbh_tent/core/constants/constants.dart';

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
      if (mounted) _snack('Ticket saved to gallery!', Colors.green);
    } catch (e) {
      if (mounted) _snack('Error: $e', Colors.red);
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
      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            'My Kumbh Tent Booking\nRef: $ref\n$tent\n$checkIn to $checkOut\nNashik Kumbh 2027',
        subject: 'Kumbh Tent Booking - $ref',
      );
    } catch (e) {
      if (mounted) _snack('Error sharing: $e', Colors.red);
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
    final statusColor = isConfirmed
        ? Colors.green
        : isPending
        ? Colors.orange
        : isCancelled
        ? Colors.red
        : Colors.blue;
    final statusLabel = isConfirmed
        ? 'Booking Confirmed'
        : isPending
        ? 'Payment Pending - Pay at Tent'
        : isCancelled
        ? 'Booking Cancelled'
        : 'Completed';

    return Scaffold(
      backgroundColor: kTrueSaffronPale,
      appBar: AppBar(
        backgroundColor: kTrueSaffron,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'E-Ticket',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w700,
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
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.share_outlined, color: Colors.white),
                  onPressed: _shareTicket,
                ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Status banner ─────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withOpacity(0.3)),
              ),
              child: Center(
                child: Text(
                  statusLabel,
                  style: GoogleFonts.poppins(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Ticket card ───────────────────────────────────
            RepaintBoundary(
              key: _ticketKey,
              child: Container(
                color: kTrueSaffronPale,
                child: Container(
                  decoration: BoxDecoration(
                    color: kLuxGoldSoft,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: kTrueSaffron.withOpacity(0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: kTrueSaffron.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Ticket header
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [kTrueSaffronDark, kTrueSaffron],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Text(
                                  '\u26fa',
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
                                          fontWeight: FontWeight.w800,
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
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '\u26fa ${widget.booking['class']?.toString().toUpperCase() ?? 'TENT'}',
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
                                fontWeight: FontWeight.w700,
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
                                  color: kLuxBorder,
                                ),
                                _detailItem(
                                  'Check-out',
                                  widget.booking['check_out'] ?? '-',
                                ),
                                Container(
                                  width: 1,
                                  height: 40,
                                  color: kLuxBorder,
                                ),
                                _detailItem(
                                  'Nights',
                                  '${widget.booking['nights'] ?? '-'}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Divider(color: kLuxBorder, height: 1),
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
                                  'Rs.${widget.booking['total'] ?? '-'}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Divider(color: kLuxBorder, height: 1),
                            const SizedBox(height: 16),

                            // Booking ref box
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: kTrueSaffron.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: kTrueSaffron.withOpacity(0.2),
                                ),
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
                                          color: kLuxMuted,
                                        ),
                                      ),
                                      Text(
                                        widget.booking['ref'] ?? '',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: kTrueSaffronDark,
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
                                        Colors.green,
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: kTrueSaffron,
                                        borderRadius: BorderRadius.circular(8),
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
                              'Scan at Entry Gate',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: kLuxMuted,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: kTrueSaffron.withOpacity(0.2),
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
                                  color: kTrueSaffronDark,
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.square,
                                  color: kDark,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Show this QR code at the camp entrance',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: kLuxMuted,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Footer
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: kTrueSaffron.withOpacity(0.06),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(24),
                          ),
                        ),

                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              '\u26fa',
                              style: TextStyle(fontSize: 14),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Kumbh Tent Booking - Nashik Kumbh 2027',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: kLuxMuted,
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
            ),

            const SizedBox(height: 24),

            // ── Action buttons ────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: kTrueSaffron),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _isSharing ? null : _shareTicket,
                    icon: Icon(
                      Icons.share_outlined,
                      color: kTrueSaffron,
                      size: 18,
                    ),
                    label: Text(
                      'Share',
                      style: GoogleFonts.poppins(
                        color: kTrueSaffron,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kTrueSaffron,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    onPressed: _isDownloading ? null : _downloadTicket,
                    icon: _isDownloading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.download_rounded,
                            color: Colors.white,
                          ),
                    label: Text(
                      _isDownloading ? 'Saving...' : 'Download',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _detailItem(String label, String value) => Column(
    children: [
      Text(label, style: GoogleFonts.poppins(fontSize: 10, color: kLuxMuted)),
      const SizedBox(height: 4),
      Text(
        value,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: kDark,
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
            color: kTrueSaffronPale,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(10),
            ),
            border: Border(
              top: BorderSide(color: kLuxBorder),
              right: BorderSide(color: kLuxBorder),
              bottom: BorderSide(color: kLuxBorder),
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
                  (_) =>
                      Container(width: dashWidth, height: 1, color: kLuxBorder),
                ),
              );
            },
          ),
        ),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: kTrueSaffronPale,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(10),
            ),
            border: Border(
              top: BorderSide(color: kLuxBorder),
              left: BorderSide(color: kLuxBorder),
              bottom: BorderSide(color: kLuxBorder),
            ),
          ),
        ),
      ],
    );
  }
}
