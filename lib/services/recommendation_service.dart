import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A paper recommended by the Supabase recommendation engine.
class RecommendedPaper {
  final String catalogId;
  final String? arxivId;
  final String title;
  final String? authors;
  final String? abstract_;
  final int readerCount;
  final double score;

  RecommendedPaper({
    required this.catalogId,
    this.arxivId,
    required this.title,
    this.authors,
    this.abstract_,
    required this.readerCount,
    required this.score,
  });

  factory RecommendedPaper.fromMap(Map<String, dynamic> map) {
    return RecommendedPaper(
      catalogId: map['catalog_id'] as String,
      arxivId: map['arxiv_id'] as String?,
      title: map['title'] as String? ?? 'Untitled',
      authors: map['authors'] as String?,
      abstract_: map['abstract'] as String?,
      readerCount: (map['reader_count'] as num?)?.toInt() ?? 0,
      score: (map['match_score'] ?? map['tag_relevance'] ?? map['trending_score'] ?? 0)
          .toDouble(),
    );
  }
}

/// Container for all recommendation types.
class Recommendations {
  final List<RecommendedPaper> collaborative;
  final List<RecommendedPaper> tagBased;
  final List<RecommendedPaper> trending;

  Recommendations({
    this.collaborative = const [],
    this.tagBased = const [],
    this.trending = const [],
  });

  bool get isEmpty =>
      collaborative.isEmpty && tagBased.isEmpty && trending.isEmpty;
}

/// Fetches paper recommendations from Supabase RPC functions.
class RecommendationService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<List<RecommendedPaper>> _fetchSafe(String rpcName, String userId) async {
    try {
      final data = await _client.rpc(rpcName, params: {
        'p_user_id': userId,
        'p_limit': 20,
      });
      return (data as List)
          .cast<Map<String, dynamic>>()
          .map(RecommendedPaper.fromMap)
          .toList();
    } catch (e) {
      debugPrint('$rpcName failed: $e');
      return [];
    }
  }

  Future<Recommendations> fetchAll() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return Recommendations();

    final collaborative = await _fetchSafe('get_collaborative_recommendations', userId);
    final tagBased = await _fetchSafe('get_tag_recommendations', userId);
    final trending = await _fetchSafe('get_trending_recommendations', userId);

    return Recommendations(
      collaborative: collaborative,
      tagBased: tagBased,
      trending: trending,
    );
  }
}
