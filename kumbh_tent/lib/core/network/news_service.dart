import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:kumbh_tent/core/constants/kumbh_content.dart';

/// Fetches live Kumbh/Simhastha news for the News tab.
///
/// Tries NewsData.io first, then falls back to GNews if NewsData.io
/// errors or reports its quota exhausted. Both are free-tier keys
/// with low daily limits, so the fallback exists to keep the tab
/// populated when one runs dry — not for redundancy against outages.
class NewsService {
  static const _newsDataIoKey = 'pub_5ba07400ecd54540a7f26d46c44de9df';
  static const _gNewsKey = 'eec55e4be6d35a86a5b6283e1f8414ff';

  static const _query = 'Kumbh Mela OR Simhastha OR Nashik Kumbh';
  static const _timeout = Duration(seconds: 10);

  /// Returns live articles tagged 'Live', or an empty list if both
  /// providers fail — callers should fall back to [kKumbhNews].
  static Future<List<NewsItem>> fetchLiveNews() async {
    try {
      final items = await _fetchNewsDataIo();
      if (items.isNotEmpty) return items;
    } catch (_) {
      // Quota exhausted or provider error — fall through to GNews.
    }
    try {
      return await _fetchGNews();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<NewsItem>> _fetchNewsDataIo() async {
    final uri = Uri.parse('https://newsdata.io/api/1/news').replace(
      queryParameters: {
        'apikey': _newsDataIoKey,
        'q': _query,
        'language': 'en',
      },
    );
    final res = await http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('newsdata.io ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['status'] != 'success') {
      throw Exception('newsdata.io error: ${body['results']}');
    }
    final results = (body['results'] as List?) ?? const [];
    return results
        .map((r) {
          final m = r as Map<String, dynamic>;
          return NewsItem(
            title: (m['title'] as String?)?.trim() ?? '',
            summary:
                (m['description'] as String?)?.trim() ??
                (m['content'] as String?)?.trim() ??
                '',
            date: _formatDate(m['pubDate'] as String?),
            tag: 'Live',
            url: m['link'] as String?,
            imageUrl: m['image_url'] as String?,
            source: (m['source_name'] as String?) ?? (m['source_id'] as String?),
          );
        })
        .where((n) => n.title.isNotEmpty)
        .toList();
  }

  static Future<List<NewsItem>> _fetchGNews() async {
    final uri = Uri.parse('https://gnews.io/api/4/search').replace(
      queryParameters: {'q': _query, 'lang': 'en', 'token': _gNewsKey},
    );
    final res = await http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('gnews ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final articles = (body['articles'] as List?) ?? const [];
    return articles
        .map((a) {
          final m = a as Map<String, dynamic>;
          final source = m['source'] as Map<String, dynamic>?;
          return NewsItem(
            title: (m['title'] as String?)?.trim() ?? '',
            summary: (m['description'] as String?)?.trim() ?? '',
            date: _formatDate(m['publishedAt'] as String?),
            tag: 'Live',
            url: m['url'] as String?,
            imageUrl: m['image'] as String?,
            source: source?['name'] as String?,
          );
        })
        .where((n) => n.title.isNotEmpty)
        .toList();
  }

  static String _formatDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}
