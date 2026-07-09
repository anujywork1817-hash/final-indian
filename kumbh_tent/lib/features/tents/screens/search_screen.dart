import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/features/tents/screens/tent_detail_screen.dart';
import 'package:kumbh_tent/features/tents/screens/browse_screen.dart';

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

  final List<Map<String, String>> _popularFilters = [
    {'label': '⭐ Premium', 'key': 'premium'},
    {'label': '💎 Luxury', 'key': 'luxury'},
    {'label': '💰 Regular', 'key': 'standard'},
    {'label': '🌊 Godavari View', 'key': 'godavari'},
    {'label': '📍 Near Trimbakeshwar', 'key': 'trimbak'},
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

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    setState(
      () => _recentSearches = prefs.getStringList('recent_searches') ?? [],
    );
  }

  Future<void> _saveRecentSearch(String query) async {
    if (query.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final searches = prefs.getStringList('recent_searches') ?? [];
    searches.remove(query);
    searches.insert(0, query);
    if (searches.length > 10) searches.removeLast();
    await prefs.setStringList('recent_searches', searches);
    setState(() => _recentSearches = searches);
  }

  Future<void> _clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recent_searches');
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

  void _search(String query) {
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
    _saveRecentSearch(query);
  }

  void _applyFilter(String key) {
    _searchController.text = key;
    _search(key);
  }

  @override
  Widget build(BuildContext context) {
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
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: kLuxGoldSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _focusNode,
            onChanged: _search,
            style: GoogleFonts.poppins(fontSize: 14, color: kDark),
            decoration: InputDecoration(
              hintText: 'Search tents, location, class...',
              hintStyle: GoogleFonts.poppins(color: kLuxMuted, fontSize: 13),
              prefixIcon: Icon(Icons.search, color: kTrueSaffron, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        _search('');
                      },
                      child: const Icon(
                        Icons.close,
                        color: kLuxMuted,
                        size: 18,
                      ),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kTrueSaffron))
          : _hasSearched
          ? _buildResults()
          : _buildSuggestions(),
    );
  }

  Widget _buildSuggestions() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Popular searches
          Text(
            'Popular Searches',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: kDark,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _popularFilters
                .map(
                  (f) => GestureDetector(
                    onTap: () => _applyFilter(f['key']!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: kLuxGoldSoft,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: kTrueSaffron.withOpacity(0.25),
                        ),
                      ),
                      child: Text(
                        f['label']!,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: kDark,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 24),

          // Recent searches
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Searches',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: kDark,
                ),
              ),
              if (_recentSearches.isNotEmpty)
                GestureDetector(
                  onTap: _clearRecentSearches,
                  child: Text(
                    'Clear',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: kTrueSaffron,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_recentSearches.isEmpty)
            Text(
              'No recent searches',
              style: GoogleFonts.poppins(fontSize: 13, color: kLuxMuted),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: kLuxGoldSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kTrueSaffron.withOpacity(0.2)),
              ),
              child: Column(
                children: _recentSearches
                    .map(
                      (s) => GestureDetector(
                        onTap: () {
                          _searchController.text = s;
                          _search(s);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: kTrueSaffron.withOpacity(0.1),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.history, color: kLuxMuted, size: 18),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  s,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: kDark,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.north_west,
                                color: kLuxMuted,
                                size: 14,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

          const SizedBox(height: 24),

          // Kumbh dates
          Text(
            'Search by Kumbh Date',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: kDark,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kTrueSaffron.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kTrueSaffron.withOpacity(0.25)),
            ),
            child: Column(
              children: kKumbhDates
                  .map(
                    (d) => GestureDetector(
                      onTap: () {
                        _searchController.text = d['date']!;
                        _search(d['date']!);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 52,
                              child: Text(
                                d['date']!,
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: kTrueSaffron,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                d['name']!,
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: kDark,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: kTrueSaffron.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: kTrueSaffron.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                d['surge']!,
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: kTrueSaffronDark,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🔍', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 16),
            Text(
              'No tents found',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: kDark,
              ),
            ),
            Text(
              'Try a different search term',
              style: GoogleFonts.poppins(fontSize: 13, color: kLuxMuted),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            '${_results.length} tent${_results.length == 1 ? '' : 's'} found',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: kLuxMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _results.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _SearchResultCard(tent: _results[i]),
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kLuxGoldSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kTrueSaffron.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: kTrueSaffron.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 56,
                height: 56,
                child: buildTentImage(images.isNotEmpty ? images.first : ''),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tent['name'],
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: kDark,
                          ),
                        ),
                      ),
                      if (isSurge)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '🔥 ${tent['surge']}',
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tent['location'],
                    style: GoogleFonts.poppins(fontSize: 11, color: kLuxMuted),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.star_rounded,
                            color: kTrueSaffron,
                            size: 13,
                          ),
                          Text(
                            ' ${tent['rating']}',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: kDark,
                            ),
                          ),
                          Text(
                            ' · ${tent['distance']} km',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: kLuxMuted,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '₹${tent['price']}/night',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isSurge ? Colors.red.shade700 : kTrueSaffron,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios, size: 14, color: kLuxMuted),
          ],
        ),
      ),
    );
  }
}
