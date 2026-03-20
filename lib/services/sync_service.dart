import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../database/database_service.dart';
import '../models/paper.dart';
import '../models/tag.dart';
import 'supabase_service.dart';

/// Handles unidirectional sync from local SQLite to Supabase.
class SyncService {
  final DatabaseService _db;

  SyncService(this._db);

  /// Run a full sync cycle. [onProgress] reports (current, total, phase).
  Future<SyncResult> sync({void Function(int current, int total, String phase)? onProgress}) async {
    if (!SupabaseService.isLoggedIn) return SyncResult.notLoggedIn();

    final userId = SupabaseService.currentUser!.id;
    int papersSynced = 0;
    int tagsSynced = 0;
    int deletionsSynced = 0;

    try {
      onProgress?.call(0, 0, 'Syncing tags...');
      tagsSynced = await _syncTags(userId);
      onProgress?.call(0, 0, 'Syncing papers...');
      papersSynced = await _syncPapers(userId, onProgress: onProgress);
      onProgress?.call(0, 0, 'Syncing deletions...');
      deletionsSynced = await _syncDeletions(userId);
      onProgress?.call(0, 0, 'Syncing tag associations...');
      await _syncPaperTagAssociations(userId);

      return SyncResult(
        success: true,
        papersSynced: papersSynced,
        tagsSynced: tagsSynced,
        deletionsSynced: deletionsSynced,
      );
    } catch (e) {
      debugPrint('Sync error: $e');
      return SyncResult(success: false, error: e.toString());
    }
  }

  Future<int> _syncTags(String userId) async {
    final dirtyTags = await _db.getDirtyTags();
    if (dirtyTags.isEmpty) return 0;

    final sorted = _topologicalSortTags(dirtyTags);
    int count = 0;

    for (final tag in sorted) {
      int? parentRemoteId;
      if (tag.parentId != null) {
        final parentMap = await _db.getTagRemoteIdMap();
        parentRemoteId = parentMap[tag.parentId];
      }

      final data = {
        'user_id': userId,
        'name': tag.name,
        'parent_id': parentRemoteId,
        'updated_at': DateTime.now().toIso8601String(),
      };

      try {
        if (tag.remoteId != null) {
          await SupabaseService.client
              .from('user_tags')
              .update(data)
              .eq('id', tag.remoteId!);
          await _db.markTagSynced(tag.id!, tag.remoteId!);
        } else {
          final response = await SupabaseService.client
              .from('user_tags')
              .upsert(data, onConflict: 'user_id,name,parent_id')
              .select('id')
              .single();
          await _db.markTagSynced(tag.id!, response['id'] as int);
        }
        count++;
      } catch (e) {
        debugPrint('Failed to sync tag ${tag.name}: $e');
      }
    }

    return count;
  }

  Future<int> _syncPapers(String userId, {void Function(int current, int total, String phase)? onProgress}) async {
    final dirtyPapers = await _db.getDirtyPapers();
    if (dirtyPapers.isEmpty) return 0;

    int count = 0;
    final total = dirtyPapers.length;
    for (int i = 0; i < dirtyPapers.length; i += 50) {
      final batch = dirtyPapers.skip(i).take(50).toList();

      for (final paper in batch) {
        onProgress?.call(count + 1, total, 'Syncing papers...');
        try {
          final tagNames = await _db.getTagNamesForPaper(paper.id!);
          final titleHash = paper.syncKey?.startsWith('title:') == true
              ? paper.syncKey!.substring(6)
              : null;

          final data = {
            'user_id': userId,
            'arxiv_id': paper.arxivId,
            'title': paper.title,
            'authors': paper.authors,
            'abstract': paper.abstract,
            'bibtex': paper.bibtex,
            'sync_key': paper.syncKey,
            'updated_at': (paper.updatedAt ?? DateTime.now()).toIso8601String(),
          };

          final response = await SupabaseService.client
              .from('user_papers')
              .upsert(data, onConflict: 'user_id,sync_key')
              .select('id')
              .single();

          final remoteId = response['id'] as int;
          await _db.markPaperSynced(paper.id!, remoteId);

          // Contribute to shared catalog
          await _contributeToSharedCatalog(paper, tagNames, titleHash);
          count++;
        } catch (e) {
          debugPrint('Failed to sync paper ${paper.title}: $e');
        }
      }
    }

    return count;
  }

  Future<int> _syncDeletions(String userId) async {
    final deletedPapers = await _db.getDeletedPapers();
    if (deletedPapers.isEmpty) return 0;

    int count = 0;
    for (final paper in deletedPapers) {
      try {
        if (paper.remoteId != null) {
          await SupabaseService.client
              .from('user_papers')
              .update({'deleted_at': paper.deletedAt!.toIso8601String()})
              .eq('id', paper.remoteId!);
        }
        await _db.markPaperSynced(paper.id!, paper.remoteId ?? 0);
        count++;
      } catch (e) {
        debugPrint('Failed to sync deletion: $e');
      }
    }

    return count;
  }

  Future<void> _syncPaperTagAssociations(String userId) async {
    final allPapers = await _db.getDirtyPapers();
    final tagRemoteIds = await _db.getTagRemoteIdMap();

    for (final paper in allPapers) {
      if (paper.remoteId == null) continue;

      final tags = await _db.getTagsForPaper(paper.id!);
      final remoteTagIds = <int>[];
      for (final tag in tags) {
        final remoteTagId = tagRemoteIds[tag.id];
        if (remoteTagId != null) remoteTagIds.add(remoteTagId);
      }

      try {
        // Delete existing associations then re-insert
        await SupabaseService.client
            .from('user_paper_tags')
            .delete()
            .eq('user_paper_id', paper.remoteId!);

        if (remoteTagIds.isNotEmpty) {
          final associations = remoteTagIds.map((tagId) => {
            'user_paper_id': paper.remoteId!,
            'user_tag_id': tagId,
          }).toList();

          await SupabaseService.client
              .from('user_paper_tags')
              .insert(associations);
        }
      } catch (e) {
        debugPrint('Failed to sync paper-tag associations for ${paper.title}: $e');
      }
    }
  }

  Future<void> _contributeToSharedCatalog(Paper paper, List<String> tagNames, String? titleHash) async {
    // Always compute a title_hash fallback so the CHECK constraint is satisfied
    final effectiveTitleHash = titleHash ?? _computeTitleHash(paper.title, paper.authors ?? '');

    try {
      await SupabaseService.client.rpc('upsert_shared_catalog', params: {
        'p_arxiv_id': paper.arxivId,
        'p_title_hash': effectiveTitleHash,
        'p_title': paper.title,
        'p_authors': paper.authors,
        'p_abstract': paper.abstract,
        'p_tag_names': tagNames,
      });
    } catch (e) {
      debugPrint('Shared catalog contribution failed: $e');
    }
  }

  String _computeTitleHash(String title, String authors) {
    final input = '${title.toLowerCase()}${authors.toLowerCase()}';
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// Topological sort: parents before children.
  List<Tag> _topologicalSortTags(List<Tag> tags) {
    final tagMap = {for (final t in tags) t.id!: t};
    final sorted = <Tag>[];
    final visited = <int>{};

    void visit(Tag tag) {
      if (visited.contains(tag.id!)) return;
      visited.add(tag.id!);
      if (tag.parentId != null && tagMap.containsKey(tag.parentId)) {
        visit(tagMap[tag.parentId!]!);
      }
      sorted.add(tag);
    }

    for (final tag in tags) {
      visit(tag);
    }
    return sorted;
  }
}

class SyncResult {
  final bool success;
  final int papersSynced;
  final int tagsSynced;
  final int deletionsSynced;
  final String? error;

  SyncResult({
    required this.success,
    this.papersSynced = 0,
    this.tagsSynced = 0,
    this.deletionsSynced = 0,
    this.error,
  });

  factory SyncResult.notLoggedIn() => SyncResult(success: false, error: 'Not logged in');

  int get totalSynced => papersSynced + tagsSynced + deletionsSynced;
}
