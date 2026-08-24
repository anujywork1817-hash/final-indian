import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/core/constants/kumbh_content.dart';

/// History tab — background on the Kumbh plus video content.
///
/// Videos come from `kHistoryVideos` in core/constants/kumbh_content.dart.
/// That list is intentionally empty until real links are supplied, so
/// the video section renders an explicit placeholder rather than a
/// blank area.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kTrueSaffronPale,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 96,
            collapsedHeight: 96,
            backgroundColor: kTrueSaffron,
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [kTrueSaffronDark, kTrueSaffron],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'History',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'The story of the Kumbh Mela',
                        style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Videos ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Videos',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kLuxDark,
                ),
              ),
            ),
          ),

          if (kHistoryVideos.isEmpty)
            SliverToBoxAdapter(child: _videosComingSoon())
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _videoCard(kHistoryVideos[i]),
                childCount: kHistoryVideos.length,
              ),
            ),

          // ── Written background ──────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                'Background',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kLuxDark,
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _sectionCard(kHistorySections[i]),
              childCount: kHistorySections.length,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _videosComingSoon() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: kLuxBorder),
    ),
    child: Column(
      children: [
        const Text('🎬', style: TextStyle(fontSize: 34)),
        const SizedBox(height: 10),
        Text(
          'Videos coming soon',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: kLuxDark,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'History videos of the Kumbh Mela will appear here.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: kLuxMuted,
            height: 1.5,
          ),
        ),
      ],
    ),
  );

  Widget _videoCard(HistoryVideo v) => GestureDetector(
    onTap: () =>
        launchUrl(Uri.parse(v.url), mode: LaunchMode.externalApplication),
    child: Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLuxBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 170,
                width: double.infinity,
                child: v.thumbnail == null
                    ? Container(color: kTrueSaffron.withOpacity(0.12))
                    : (v.thumbnail!.startsWith('assets/')
                          ? Image.asset(v.thumbnail!, fit: BoxFit.cover)
                          : CachedNetworkImage(
                              imageUrl: v.thumbnail!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                color: kTrueSaffron.withOpacity(0.12),
                              ),
                            )),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              if (v.duration != null)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      v.duration!,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kLuxDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  v.description,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: kLuxMuted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _sectionCard(Map<String, String> s) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: kLuxBorder),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s['image'] != null)
          Image.asset(s['image']!, width: double.infinity, height: 170, fit: BoxFit.cover),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s['title']!,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kTrueSaffronDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s['body']!,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: kLuxDark,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
