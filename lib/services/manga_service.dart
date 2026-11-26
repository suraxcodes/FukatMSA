import 'dart:convert';
import 'package:http/http.dart' as http;

class MangaService {
  static const String anilistUrl = 'https://graphql.anilist.co';
  static const String mangadexApiUrl = 'https://api.mangadex.org';

  // Fetch Trending Manga from Anilist
  static Future<List<dynamic>> getTrendingManga() async {
    final query = '''
      query {
        Page(page: 1, perPage: 20) {
          media(type: MANGA, sort: TRENDING_DESC) {
            id
            title {
              romaji
              english
            }
            coverImage {
              large
            }
            description
            genres
          }
        }
      }
    ''';
    try {
      final res = await http.post(
        Uri.parse(anilistUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        },
        body: json.encode({'query': query}),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return data['data']['Page']['media'] ?? [];
      }
    } catch (e) {
      print("MangaService Trending Error: $e");
    }
    return [];
  }

  // Fetch Manga Search from Anilist
  static Future<List<dynamic>> searchManga(String queryStr) async {
    final query = '''
      query (\$search: String) {
        Page(page: 1, perPage: 20) {
          media(search: \$search, type: MANGA, sort: SEARCH_MATCH) {
            id
            title {
              romaji
              english
            }
            coverImage {
              large
            }
            description
            genres
          }
        }
      }
    ''';

    try {
      final res = await http.post(
        Uri.parse(anilistUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        },
        body: json.encode({
          'query': query,
          'variables': {'search': queryStr}
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return data['data']['Page']['media'] ?? [];
      }
    } catch (e) {
      print("MangaService Search Error: $e");
    }
    return [];
  }

  // Find Manga on MangaDex by Title
  static Future<String?> getMangadexIdByTitle(String title) async {
    try {
      final encodedTitle = Uri.encodeComponent(title);
      final url = Uri.parse('$mangadexApiUrl/manga?title=$encodedTitle&limit=1');
      final res = await http.get(
        url,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        },
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final results = data['data'] as List<dynamic>? ?? [];
        if (results.isNotEmpty) {
          return results.first['id'];
        }
      }
    } catch (e) {
      print("MangaService Mangadex Search Error: $e");
    }
    return null;
  }

  // Fetch Chapters for MangaDex ID
  static Future<List<dynamic>> getMangaChapters(String mangadexId) async {
    try {
      // Fetch English chapters, sorted by chapter ascending
      final url = Uri.parse(
          '$mangadexApiUrl/manga/$mangadexId/feed?translatedLanguage[]=en&order[chapter]=asc&limit=500');
      final res = await http.get(
        url,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        },
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final chapters = data['data'] as List<dynamic>? ?? [];
        final now = DateTime.now();
        
        return chapters.where((chapter) {
          try {
            final externalUrl = chapter['attributes']?['externalUrl'];
            final pages = chapter['attributes']?['pages'] ?? 0;
            // We now ALLOW externalUrl chapters to be shown in the UI

            final publishAtStr = chapter['attributes']?['publishAt'] ?? chapter['attributes']?['readableAt'];
            if (publishAtStr == null) return true; // fallback
            final publishAt = DateTime.parse(publishAtStr);
            return publishAt.isBefore(now) || publishAt.isAtSameMomentAs(now);
          } catch (_) {
            return true;
          }
        }).toList();
      }
    } catch (e) {
      print("MangaService Chapter Fetch Error: $e");
    }
    return [];
  }

  // Fetch Image URLs for a Chapter
  static Future<List<String>> getChapterPages(String chapterId) async {
    try {
      final url = Uri.parse('$mangadexApiUrl/at-home/server/$chapterId');
      final res = await http.get(
        url,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        },
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        
        // We bypass the dynamic '@Home' node (baseUrl) because many nodes block direct
        // external requests or return 404s. Instead, we use the main uploads server directly.
        final baseUrl = 'https://uploads.mangadex.org';
        final chapterHash = data['chapter']['hash'];
        
        // Use 'data' instead of 'dataSaver' for high-quality images
        final dataList = data['chapter']['data'] as List<dynamic>? ?? [];
        
        // Construct full URLs
        return dataList.map((filename) {
          return '$baseUrl/data/$chapterHash/$filename';
        }).toList();
      }
    } catch (e) {
      print("MangaService Page Fetch Error: $e");
    }
    return [];
  }
}
