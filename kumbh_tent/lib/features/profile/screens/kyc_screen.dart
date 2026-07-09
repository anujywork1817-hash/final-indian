import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/core/network/api_service.dart';

class KYCScreen extends StatefulWidget {
  final String currentStatus;
  final String currentIdType;
  const KYCScreen({
    super.key,
    this.currentStatus = 'not_submitted',
    this.currentIdType = '',
  });

  @override
  State<KYCScreen> createState() => _KYCScreenState();
}

class _KYCScreenState extends State<KYCScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idNumberController = TextEditingController();
  String _selectedIdType = 'Aadhaar';
  bool _loading = false;
  bool _submitted = false;

  final List<Map<String, String>> _idTypes = [
    {
      'value': 'Aadhaar',
      'label': '🪪 Aadhaar Card',
      'hint': 'Enter 12-digit Aadhaar number',
    },
    {
      'value': 'PAN',
      'label': '💳 PAN Card',
      'hint': 'Enter 10-character PAN number',
    },
    {
      'value': 'Passport',
      'label': '📘 Passport',
      'hint': 'Enter passport number',
    },
    {
      'value': 'Voter ID',
      'label': '🗳️ Voter ID',
      'hint': 'Enter Voter ID number',
    },
    {
      'value': 'Driving License',
      'label': '🚗 Driving License',
      'hint': 'Enter driving license number',
    },
  ];

  @override
  void initState() {
    super.initState();
    if (widget.currentIdType.isNotEmpty) _selectedIdType = widget.currentIdType;
    _submitted =
        widget.currentStatus == 'pending' || widget.currentStatus == 'verified';
  }

  @override
  void dispose() {
    _idNumberController.dispose();
    super.dispose();
  }

  String get _currentHint =>
      _idTypes.firstWhere((t) => t['value'] == _selectedIdType)['hint']!;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ApiService.submitKYC(
        _selectedIdType,
        _idNumberController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _submitted = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'KYC submitted successfully!',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to submit KYC. Please try again.',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kTrueSaffronPale,
      appBar: AppBar(
        backgroundColor: kTrueSaffron,
        title: Text(
          'KYC Verification',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusBanner(),
            const SizedBox(height: 24),

            if (!_submitted) ...[
              // Info banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kTrueSaffron.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kTrueSaffron.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: kTrueSaffron, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'KYC verification is required for check-in at Kumbh 2027 as per government guidelines. Your ID is stored securely.',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: kTrueSaffronDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select ID Type',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kTrueSaffron,
                      ),
                    ),
                    const SizedBox(height: 12),

                    ..._idTypes.map(
                      (idType) => GestureDetector(
                        onTap: () =>
                            setState(() => _selectedIdType = idType['value']!),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: _selectedIdType == idType['value']
                                ? kTrueSaffron.withOpacity(0.1)
                                : kLuxGoldSoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _selectedIdType == idType['value']
                                  ? kTrueSaffron
                                  : kLuxBorder,
                              width: _selectedIdType == idType['value'] ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                idType['label']!,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: kDark,
                                ),
                              ),
                              const Spacer(),
                              if (_selectedIdType == idType['value'])
                                Icon(
                                  Icons.check_circle,
                                  color: kTrueSaffron,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Text(
                      'ID Number',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kTrueSaffron,
                      ),
                    ),
                    const SizedBox(height: 8),

                    TextFormField(
                      controller: _idNumberController,
                      textCapitalization: TextCapitalization.characters,
                      style: GoogleFonts.poppins(fontSize: 14, color: kDark),
                      decoration: InputDecoration(
                        hintText: _currentHint,
                        hintStyle: GoogleFonts.poppins(
                          fontSize: 13,
                          color: kLuxMuted,
                        ),
                        filled: true,
                        fillColor: kLuxGoldSoft,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: kLuxBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: kLuxBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: kTrueSaffron,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty)
                          return 'Please enter your ID number';
                        if (val.trim().length < 6)
                          return 'ID number is too short';
                        return null;
                      },
                    ),

                    const SizedBox(height: 20),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_outline,
                            color: Colors.green,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your ID details are encrypted and stored securely. We never share your KYC data.',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kTrueSaffron,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              )
                            : Text(
                                'Submit KYC',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    String status = widget.currentStatus;
    if (_submitted && status == 'not_submitted') status = 'pending';

    Color bgColor, borderColor, textColor;
    IconData icon;
    String title, subtitle;

    switch (status) {
      case 'verified':
        bgColor = Colors.green.shade50;
        borderColor = Colors.green.shade200;
        textColor = Colors.green.shade800;
        icon = Icons.verified;
        title = 'KYC Verified';
        subtitle = 'Your identity has been verified successfully.';
        break;
      case 'pending':
        bgColor = kTrueSaffron.withOpacity(0.08);
        borderColor = kTrueSaffron.withOpacity(0.3);
        textColor = kTrueSaffronDark;
        icon = Icons.hourglass_top;
        title = 'Verification Pending';
        subtitle =
            'Your KYC is under review. This usually takes 1-2 business days.';
        break;
      case 'rejected':
        bgColor = Colors.red.shade50;
        borderColor = Colors.red.shade200;
        textColor = Colors.red.shade800;
        icon = Icons.cancel;
        title = 'KYC Rejected';
        subtitle =
            'Your KYC was rejected. Please resubmit with correct details.';
        break;
      default:
        bgColor = kLuxGoldSoft;
        borderColor = kLuxBorder;
        textColor = kDark;
        icon = Icons.badge_outlined;
        title = 'KYC Not Submitted';
        subtitle =
            'Submit your ID to complete verification for Kumbh 2027 check-in.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 36),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(fontSize: 12, color: textColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
