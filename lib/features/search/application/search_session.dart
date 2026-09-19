import 'dart:async';

import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/scheduling/async_work_pool.dart';
import 'package:starflow/features/search/application/search_request.dart';
import 'package:starflow/features/search/application/search_share_validator.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/search/domain/share_link_validation.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

enum SearchValidationState { pending, valid, unavailable }

class SearchPresentationState {
  SearchPresentationState({
    this.generation = 0,
    Iterable<SearchResult> results = const [],
    Map<String, SearchValidationState> validations = const {},
    this.isSearching = false,
    this.totalCount = 0,
    this.completedCount = 0,
    this.filteredCount = 0,
    this.errorMessage,
  })  : results = List.unmodifiable(results),
        validations = Map.unmodifiable(validations);

  final int generation;
  final List<SearchResult> results;
  final Map<String, SearchValidationState> validations;
  final bool isSearching;
  final int totalCount;
  final int completedCount;
  final int filteredCount;
  final String? errorMessage;

  SearchValidationState? validationFor(SearchResult result) =>
      validations[searchResultDeduplicationKey(result)];
}

/// Owns request generations, aggregation and validation, independently of UI.
/// Pools survive cancellation so obsolete in-flight IO still occupies a slot.
class SearchSession {
  SearchSession({
    required this.onChanged,
    this.commitInterval = const Duration(milliseconds: 120),
  });

  final void Function(SearchPresentationState) onChanged;
  final Duration commitInterval;
  final _searchPool = AsyncWorkPool(1);
  final _validationPool = AsyncWorkPool(1);
  SearchPresentationState _state = SearchPresentationState();
  SearchPresentationState get state => _state;
  int _generation = 0;
  bool _disposed = false;
  Timer? _commitTimer;
  _SearchRun? _run;

  bool isCurrent(int generation) => !_disposed && generation == _generation;

  /// Reserve before any asynchronous UI preparation (e.g. history writes).
  int begin() {
    cancel(clearResults: true);
    return _generation;
  }

  void start({
    required int generation,
    required SearchRequest request,
    required SearchValidationResolver resolveValidation,
    required int maxConcurrency,
    String? emptyMessage,
  }) {
    if (!isCurrent(generation) || _run != null) return;
    final capacity =
        maxConcurrency.clamp(kTaskMaxConcurrencyMin, kTaskMaxConcurrencyMax);
    _searchPool.capacity = capacity;
    _validationPool.capacity = capacity;
    final run = _SearchRun(generation, request, resolveValidation);
    _run = run;
    if (request.operations.isEmpty) {
      _publish(SearchPresentationState(
          generation: generation, errorMessage: emptyMessage));
      return;
    }
    _commit(run);
    for (final operation in request.operations) {
      unawaited(_searchPool.run(() => _fetch(run, operation)));
    }
  }

  void cancel({bool clearResults = false}) {
    if (_disposed) return;
    _generation++;
    _run = null;
    _commitTimer?.cancel();
    _commitTimer = null;
    _publish(SearchPresentationState(
      generation: _generation,
      results: clearResults ? const [] : _state.results,
      filteredCount: clearResults ? 0 : _state.filteredCount,
      errorMessage: clearResults ? null : _state.errorMessage,
    ));
  }

  void dispose() {
    _disposed = true;
    _run = null;
    _commitTimer?.cancel();
    _commitTimer = null;
  }

  bool _current(_SearchRun run) =>
      isCurrent(run.generation) && identical(run, _run);

  Future<void> _fetch(_SearchRun run, SearchOperation operation) async {
    if (!_current(run)) return;
    try {
      final response = await operation.run();
      if (!_current(run)) return;
      run.filtered += response.filteredCount;
      final changed = <_SearchCandidate>{};
      for (final item in response.items) {
        final key = searchResultDeduplicationKey(item);
        final previous = run.candidates[key];
        if (previous != null) {
          run.filtered++;
          final merged =
              mergeSearchResultShareCredentials(previous.result, item);
          if (!identical(merged, previous.result)) {
            previous.result = merged;
            previous.visible = false;
            if (previous.invalid) {
              previous.invalid = false;
              run.filtered--;
            }
            if (!previous.validating) changed.add(previous);
          }
        } else {
          final candidate = _SearchCandidate(
              prepareSearchResultShareCredentials(item), run.candidates.length);
          run.candidates[key] = candidate;
          changed.add(candidate);
        }
      }
      // Merge the entire provider batch before admitting any validations.
      for (final candidate in changed) {
        _validate(run, candidate);
      }
    } catch (error) {
      if (_current(run)) run.errors.add('${operation.label}: $error');
    } finally {
      if (_current(run)) {
        run.completed++;
        _scheduleCommit(run,
            force: run.completed == run.request.operations.length);
      }
    }
  }

  void _validate(_SearchRun run, _SearchCandidate candidate) {
    final item = candidate.result;
    final key = searchResultDeduplicationKey(item);
    final job = run.resolveValidation(item);
    if (job == null) {
      candidate.visible = true;
      return;
    }
    candidate.validating = true;
    run.validations[key] = SearchValidationState.pending;
    unawaited(_validationPool.run(() async {
      if (!_current(run)) return;
      ShareLinkValidationResult validation;
      try {
        validation = await job();
      } catch (_) {
        validation = const ShareLinkValidationResult.unavailable('验证未完成');
      }
      if (!_current(run)) return;
      candidate.validating = false;
      // Later credentials supersede the answer, not the request's first title.
      if (!identical(candidate.result, item)) {
        _validate(run, candidate);
        _scheduleCommit(run);
        return;
      }
      if (validation.isInvalid) {
        candidate.invalid = true;
        run.filtered++;
        run.validations.remove(key);
      } else {
        candidate.visible = true;
        run.validations[key] = validation.isValid
            ? SearchValidationState.valid
            : SearchValidationState.unavailable;
      }
      _logValidation(item, validation);
      _scheduleCommit(run);
    }));
  }

  void _logValidation(SearchResult item, ShareLinkValidationResult validation) {
    final type = detectSearchCloudTypeFromUrl(item.resourceUrl);
    if (type == null || validation.isValid) return;
    final label = type == SearchCloudType.quark ? 'Quark' : '115';
    final fields = {'providerId': item.providerId, 'reason': validation.reason};
    if (validation.isInvalid) {
      appLogInfo('search.${type.code}-validation',
          'Invalid $label search result filtered',
          fields: fields);
    } else {
      appLogWarning('search.${type.code}-validation',
          '$label search result could not be validated',
          fields: fields);
    }
  }

  void _scheduleCommit(_SearchRun run, {bool force = false}) {
    if (!_current(run)) return;
    if (force) {
      _commitTimer?.cancel();
      _commitTimer = null;
      _commit(run);
    } else {
      _commitTimer ??= Timer(commitInterval, () {
        _commitTimer = null;
        if (_current(run)) _commit(run);
      });
    }
  }

  void _commit(_SearchRun run) {
    final candidates = run.candidates.values.where((c) => c.visible).toList();
    candidates.sort((left, right) {
      final local = (right.result.detailTarget != null ? 1 : 0) -
          (left.result.detailTarget != null ? 1 : 0);
      if (local != 0) return local;
      final title = left.result.title.compareTo(right.result.title);
      return title != 0 ? title : left.order.compareTo(right.order);
    });
    final finished = run.completed == run.request.operations.length &&
        !run.candidates.values.any((c) => c.validating);
    _publish(SearchPresentationState(
      generation: run.generation,
      results: candidates.map((c) => c.result),
      validations: run.validations,
      isSearching: !finished,
      totalCount: run.request.operations.length,
      completedCount: run.completed,
      filteredCount: run.filtered,
      errorMessage: finished && candidates.isEmpty && run.errors.isNotEmpty
          ? run.errors.join('\n')
          : null,
    ));
  }

  void _publish(SearchPresentationState state) {
    _state = state;
    onChanged(state);
  }
}

class _SearchRun {
  _SearchRun(this.generation, this.request, this.resolveValidation);
  final int generation;
  final SearchRequest request;
  final SearchValidationResolver resolveValidation;
  final candidates = <String, _SearchCandidate>{};
  final validations = <String, SearchValidationState>{};
  final errors = <String>[];
  int completed = 0;
  int filtered = 0;
}

class _SearchCandidate {
  _SearchCandidate(this.result, this.order);
  SearchResult result;
  final int order;
  bool visible = false;
  bool validating = false;
  bool invalid = false;
}
