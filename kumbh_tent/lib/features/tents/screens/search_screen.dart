import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';
import 'package:kumbh_tent/features/tents/screens/tent_detail_screen.dart';
import 'package:kumbh_tent/features/tents/screens/browse_screen.dart';
import 'package:kumbh_tent/shared/widgets/premium_badge.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _allTents = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  List<String> _recentSearches = [];

  final List<Map<String, dynamic>> _popularFilters = [
    {'label': 'Premium', 'icon': Icons.workspace_premium_rounded, 'key': 'premium'},
    {'label': 'Luxury', 'icon': Icons.diamond_rounded, 'key': 'luxury'},
    {'label': 'Regular', 'icon': Icons.holiday_village_rounded, 'key': 'standard'},
    {'label': 'Godavari View', 'icon': Icons.water_rounded, 'key': 'godavari'},
    {'label': 'Near Trimbakeshwar', 'icon': Icons.location_on_rounded, 'key': 'trimbak'},
  ];

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    _loadAllTents();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Recent searches are scoped per logged-in account (keyed by phone),
  // not one shared list for the device — otherwise switching accounts
  // on the same phone leaked the previous account's search history
  // into the new one's "Recent Searches".
  Future<String> _recentSearchesKey() async {
    final phone = await ApiService.getStoredPhone();
    return 'recent_searches_${phone ?? 'guest'}';
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _recentSearchesKey();
    setState(() => _recentSearches = prefs.getStringList(key) ?? []);
  }

  Future<void> _saveRecentSearch(String query) async {
    if (query.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = await _recentSearchesKey();
    final searches = prefs.getStringList(key) ?? [];
    searches.remove(query);
    searches.insert(0, query);
    if (searches.length > 10) searches.removeLast();
    await prefs.setStringList(key, searches);
    setState(() => _recentSearches = searches);
  }

  Future<void> _clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _recentSearchesKey();
    await prefs.remove(key);
    setState(() => _recentSearches = []);
  }

  Future<void> _loadAllTents() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getTents();
      setState(() {
        _allTents = data
            .map(
              (t) => {
                'id': t['id'],
                'name': t['name'],
                'class': t['class'],
                'location': t['location'],
                'distance': t['distance'],
                'rating': t['rating'],
                'reviews': t['reviews'],
                'price': t['price'],
                'base_price': t['base_price'],
                'is_surge': t['is_surge'],
                'surge': t['surge'],
                'amenities': List<String>.from(t['amenities']),
                'images': List<String>.from(t['images'] ?? []),
                'color': kColorForClass(t['class']),
              },
            )
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // `save` defaults to false so every keystroke (onChanged still
  // needs to live-filter results) doesn't get written to recent
  // searches as its own entry — that previously flooded the list
  // with every prefix of what was typed ("k", "ku", "kum", ...),
  // which then displayed as if sorted alphabetically. Only a
  // committed search (submit, tapping a suggestion/filter/date)
  // should be remembered.
  void _search(String query, {bool save = false}) {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }
    setState(() => _hasSearched = true);
    final q = query.toLowerCase();
    setState(() {
      _results = _allTents.where((tent) {
        final name = tent['name'].toString().toLowerCase();
        final location = tent['location'].toString().toLowerCase();
        final cls = tent['class'].toString().toLowerCase();
        final amenities = (tent['amenities'] as List<String>)
            .join(' ')
            .toLowerCase();
        return name.contains(q) ||
            location.contains(q) ||
            cls.contains(q) ||
            amenities.contains(q);
      }).toList();
    });
    if (save) _saveRecentSearch(query);
  }

  void _applyFilter(String key) {
    _searchController.text = key;
    _search(key, save: true);
  }

  // A Kumbh date isn't text that appears anywhere on a tent (name,
  // location, class, amenities) — running it through _search() as a
  // substring match always returned zero results. Tapping a date is
  // really asking "what can I book for this Kumbh date", and since
  // every listed tent is generically bookable (day-specific sold-out
  // is enforced later, at booking time, by the availability check),
  // that means: show all tents, labeled by the date tapped.
  void _searchByKumbhDate(String date) {
    _searchController.text = date;
    setState(() {
      _hasSearched = true;
      _results = List<Map<String, dynamic>>.from(_allTents);
    });
    _saveRecentSearch(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.saffron,
                      ),
                    )
                  : _hasSearched
                  ? _buildResults()
                  : _buildSuggestions(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 20, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary,
              size: 18,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.softSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                onChanged: _search,
                onSubmitted: (q) => _search(q, save: true),
                textInputAction: TextInputAction.search,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Search tents, location, class...',
                  hintStyle: GoogleFonts.poppins(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.saffron,
                    size: 20,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            _search('');
                          },
                          child: const Icon(
                            Icons.close_rounded,
                            color: AppColors.textMuted,
                            size: 18,
                          ),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Popular searches ────────────────────────────────
          _label('Popular Searches'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _popularFilters
                .map(
                  (f) => GestureDetector(
                    onTap: () => _applyFilter(f['key'] as String),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.cardBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            f['icon'] as IconData,
                            size: 15,
                            color: AppColors.saffron,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            f['label'] as String,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 28),

          // ── Recent searches ──────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _label('Recent Searches'),
              if (_recentSearches.isNotEmpty)
                GestureDetector(
                  onTap: _clearRecentSearches,
                  child: Text(
                    'Clear',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.saffron,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_recentSearches.isEmpty)
            Text(
              'No recent searches',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: _recentSearches.asMap().entries.map((entry) {
                  final isLast = entry.key == _recentSearches.length - 1;
                  final s = entry.value;
                  return GestureDetector(
                    onTap: () {
                      _searchController.text = s;
                      _search(s, save: true);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        border: isLast
                            ? null
                            : const Border(
                                bottom: BorderSide(color: AppColors.border),
                              ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.softSurface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.history_rounded,
                              color: AppColors.textMuted,
                              size: 15,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              s,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.north_west_rounded,
                            color: AppColors.textMuted,
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

          const SizedBox(height: 28),

          // ── Kumbh dates ───────────────────────────────────────
          _label('Search by Kumbh Date'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: kKumbhDates.asMap().entries.map((entry) {
                final isLast = entry.key == kKumbhDates.length - 1;
                final d = entry.value;
                return GestureDetector(
                  onTap: () => _searchByKumbhDate(d['date']!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: isLast
                          ? null
                          : const Border(
                              bottom: BorderSide(color: AppColors.border),
                            ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.saffron.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            d['date']!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.saffronDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            d['name']!,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        PremiumBadge(
                          label: d['surge']!,
                          style: PremiumBadgeStyle.gold,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: GoogleFonts.poppins(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
  );

  Widget _buildResults() {
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.softSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 40,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No tents found',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try a different search term',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Text(
            '${_results.length} tent${_results.length == 1 ? '' : 's'} found',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            itemCount: _results.length,
            separatorBuilder: (context, i) => const SizedBox(height: 12),
            itemBuilder: (context, i) => TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 250 + (i * 50)),
              curve: Curves.easeOut,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1 - value) * 12),
                  child: child,
                ),
              ),
              child: _SearchResultCard(tent: _results[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final Map<String, dynamic> tent;
  const _SearchResultCard({required this.tent});

  @override
  Widget build(BuildContext context) {
    final bool isSurge = tent['is_surge'] == true;
    final images = tent['images'] as List<String>? ?? [];

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TentDetailScreen(tent: tent)),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 68,
                height: 68,
                child: buildTentImage(images.isNotEmpty ? images.first : ''),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tent['name'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (isSurge) ...[
                        const SizedBox(width: 6),
                        PremiumBadge(
                          label: '${tent['surge']}',
                          style: PremiumBadgeStyle.danger,
                          icon: Icons.local_fire_department_rounded,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tent['location'],
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: AppColors.goldWarm,
                            size: 14,
                          ),
                          Text(
                            ' ${tent['rating']}',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            ' · ${tent['distance']} km',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '₹${tent['price']}/night',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isSurge
                              ? AppColors.error
                              : AppColors.saffronDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
