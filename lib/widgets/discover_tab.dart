import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/recommendation_service.dart';

/// Full-height tab showing paper recommendations grouped by type.
class DiscoverTab extends StatelessWidget {
  const DiscoverTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Column(
          children: [
            // Header
            _Header(appState: appState),
            const Divider(height: 1),

            // Body
            Expanded(
              child: _buildBody(context, appState),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, AppState appState) {
    if (appState.isLoadingRecommendations) {
      return const Center(child: CircularProgressIndicator());
    }

    if (appState.recommendations.isEmpty) {
      return _EmptyState();
    }

    final recs = appState.recommendations;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (recs.collaborative.isNotEmpty)
          _RecommendationSection(
            icon: Icons.people_outline,
            title: 'Users like you also read',
            papers: recs.collaborative,
          ),
        if (recs.tagBased.isNotEmpty)
          _RecommendationSection(
            icon: Icons.label_outline,
            title: 'Based on your interests',
            papers: recs.tagBased,
          ),
        if (recs.trending.isNotEmpty)
          _RecommendationSection(
            icon: Icons.trending_up,
            title: 'Trending in your areas',
            papers: recs.trending,
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final AppState appState;

  const _Header({required this.appState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => appState.hideDiscoverTab(),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
          ),
          const SizedBox(width: 4),
          Icon(Icons.explore, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            'Discover',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: appState.isLoadingRecommendations
                ? null
                : () => appState.fetchRecommendations(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh recommendations',
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.explore_outlined, size: 64, color: muted),
          const SizedBox(height: 16),
          Text(
            'No recommendations yet',
            style: theme.textTheme.titleMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 300,
            child: Text(
              'Add papers and sync your library to get personalized recommendations based on your reading interests.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<RecommendedPaper> papers;

  const _RecommendationSection({
    required this.icon,
    required this.title,
    required this.papers,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...papers.map((paper) => _RecommendationCard(paper: paper)),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final RecommendedPaper paper;

  const _RecommendationCard({required this.paper});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              paper.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            // Authors
            if (paper.authors != null && paper.authors!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                paper.authors!,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // Abstract
            if (paper.abstract_ != null && paper.abstract_!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                paper.abstract_!,
                style: theme.textTheme.bodySmall,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // Footer: reader count + arxiv id
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.people_outline, size: 14, color: muted),
                const SizedBox(width: 4),
                Text(
                  '${paper.readerCount} readers',
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
                if (paper.arxivId != null) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.article_outlined, size: 14, color: muted),
                  const SizedBox(width: 4),
                  Text(
                    paper.arxivId!,
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
