import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/data/search_repository.dart';
import 'package:starflow/features/search/domain/search_models.dart';

class SearchOperation {
  const SearchOperation({required this.label, required this.run});

  final String label;
  final Future<SearchFetchResult> Function() run;
}

/// A captured request: later settings/selection changes cannot alter its jobs.
class SearchRequest {
  SearchRequest({required Iterable<SearchOperation> operations})
      : operations = List.unmodifiable(operations);

  factory SearchRequest.fromSelection({
    required SearchRepository repository,
    required String keyword,
    required Set<String> selectedTargetIds,
    required List<MediaSourceConfig> localSources,
    required List<SearchProviderConfig> providers,
  }) {
    final query = keyword.trim();
    final all = selectedTargetIds.contains('all');
    return SearchRequest(operations: [
      if (query.isNotEmpty) ...[
        for (final source in localSources)
          if (all || selectedTargetIds.contains('source:${source.id}'))
            SearchOperation(
              label: source.name,
              run: () =>
                  repository.searchLocal(query, sourceId: source.id, limit: 80),
            ),
        for (final provider in providers)
          if (all || selectedTargetIds.contains('provider:${provider.id}'))
            SearchOperation(
              label: provider.name,
              run: () => repository.searchOnline(query, provider: provider),
            ),
      ],
    ]);
  }

  final List<SearchOperation> operations;
}
