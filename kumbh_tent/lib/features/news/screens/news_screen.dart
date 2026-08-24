import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/core/constants/kumbh_content.dart';
import 'package:kumbh_tent/core/constants/snan_calendar.dart';
import 'package:kumbh_tent/core/network/news_service.dart';

/// News tab — Kumbh Mela updates and advisories.
class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  String _filter = 'All';
  List<NewsItem> _liveNews = const [];
  bool _loadingLive = true;

  static const _filters = [
    'All',
    'Live',
    'Kumbh 2027',
    'Kumbh 2026',
    'Advisory',
  ];

  @override
  void initState() {
    super.initState();
    _loadLiveNews();
  }

  Future<void> _loadLiveNews() async {
    final items = await NewsService.fetchLiveNews();
    if (!mounted) return;
    setState(() {
      _liveNews = items;
      _loadingLive = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final allItems = [..._liveNews, ...kKumbhNews];
    final items = _filter == 'All'
        ? allItems
        : allItems.where((n) => n.tag == _filter).toList();

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
                        'Kumbh News',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Updates for Simhastha 2027',
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

          // ── Next Snan countdown ─────────────────────────────
          SliverToBoxAdapter(child: _nextSnanCard()),

          // ── Filters ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final sel = _filters[i] == _filter;
                  return GestureDetector(
                    onTap: () => setState(() => _filter = _filters[i]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? kTrueSaffron : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel ? kTrueSaffron : kLuxBorder,
                        ),
                      ),
                      child: Text(
                        _filters[i],
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          color: sel ? Colors.white : kLuxMuted,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          if (_loadingLive)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: kTrueSaffron,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Checking for live updates…',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: kLuxMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (items.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 40, 16, 40),
                child: Column(
                  children: [
                    const Text('📰', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 10),
                    Text(
                      'No news under "$_filter" yet.',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: kLuxMuted,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _newsCard(items[i]),
                childCount: items.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _nextSnanCard() {
    final upcoming = kUpcomingSnans;
    if (upcoming.isEmpty) return const SizedBox.shrink();
    final next = upcoming.first;
    final days = snanDaysUntil(next.date);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kTrueSaffronDark, kTrueSaffron],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NEXT SNAN',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  next.name,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  snanLongDate(next.date),
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text(
                '$days',
                style: GoogleFonts.poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              Text(
                'days',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _newsCard(NewsItem n) {
    return GestureDetector(
      onTap: n.url == null
          ? null
          : () => launchUrl(
              Uri.parse(n.url!),
              mode: LaunchMode.externalApplication,
            ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kLuxBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (n.imageUrl != null)
              CachedNetworkImage(
                imageUrl: n.imageUrl!,
                width: double.infinity,
                height: 170,
                fit: BoxFit.cover,
                placeholder: (_, __) => Shimmer.fromColors(
                  baseColor: kLuxBorder,
                  highlightColor: kLuxCream,
                  child: Container(height: 170, color: kLuxBorder),
                ),
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kLuxDark,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    n.summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: kLuxMuted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Icon(Icons.access_time, size: 12, color: kLuxMuted),
                      Text(
                        n.date,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: kLuxMuted,
                        ),
                      ),
                      if (n.source != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: kTrueSaffron.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            n.source!,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: kTrueSaffronDark,
                            ),
                          ),
                        ),
                      if (n.url != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Read more',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: kTrueSaffron,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward,
                              size: 14,
                              color: kTrueSaffron,
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
