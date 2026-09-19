import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/search/application/search_request.dart';
import 'package:starflow/features/search/application/search_session.dart';
import 'package:starflow/features/search/application/search_share_validator.dart';
import 'package:starflow/features/search/data/search_repository.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/search/domain/share_link_validation.dart';

SearchResult _item(String id, {String password = '', String? url}) =>
    SearchResult(
      id: id,
      title: 'Same title',
      posterUrl: '',
      providerId: 'test',
      providerName: 'Test',
      quality: '',
      sizeLabel: '',
      seeders: 0,
      summary: '',
      resourceUrl: url ?? 'https://115.com/s/$id',
      password: password,
    );

SearchFetchResult _batch(List<SearchResult> items) =>
    SearchFetchResult(items: items, filteredCount: 0);

SearchOperation _operation(String label, Future<SearchFetchResult> future) =>
    SearchOperation(label: label, run: () => future);

Future<void> _flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void _start(SearchSession session, List<SearchOperation> operations,
    {SearchValidationResolver? validate, int concurrency = 1}) {
  session.start(
    generation: session.begin(),
    request: SearchRequest(operations: operations),
    resolveValidation: validate ?? (_) => null,
    maxConcurrency: concurrency,
  );
}

void main() {
  test('fetch and validation pools each obey configured capacity', () async {
    final session =
        SearchSession(onChanged: (_) {}, commitInterval: Duration.zero);
    addTearDown(session.dispose);
    final fetches = List.generate(4, (_) => Completer<SearchFetchResult>());
    final checks =
        List.generate(4, (_) => Completer<ShareLinkValidationResult>());
    final startedFetches = <int>[];
    final startedChecks = <int>[];
    _start(
        session,
        [
          for (var i = 0; i < 4; i++)
            SearchOperation(
                label: '$i',
                run: () {
                  startedFetches.add(i);
                  return fetches[i].future;
                }),
        ],
        concurrency: 2,
        validate: (item) => () {
              final index = int.parse(item.id);
              startedChecks.add(index);
              return checks[index].future;
            });
    await _flush();
    expect(startedFetches, [0, 1]);
    fetches[0].complete(_batch([_item('0')]));
    fetches[1].complete(_batch([_item('1')]));
    await _flush();
    expect(startedFetches, [0, 1, 2, 3]);
    expect(startedChecks, [0, 1]);
    fetches[2].complete(_batch([_item('2')]));
    fetches[3].complete(_batch([_item('3')]));
    await _flush();
    expect(startedChecks, [0, 1]);
    expect(session.state.completedCount, 4);
    expect(session.state.isSearching, isTrue);
    checks[0].complete(const ShareLinkValidationResult.valid());
    checks[1].complete(const ShareLinkValidationResult.valid());
    await _flush();
    expect(startedChecks, [0, 1, 2, 3]);
    checks[2].complete(const ShareLinkValidationResult.valid());
    checks[3].complete(const ShareLinkValidationResult.valid());
    await _flush();
    expect(session.state.results, hasLength(4));
    expect(session.state.isSearching, isFalse);
    session.cancel();
    expect(session.state.results, hasLength(4));
    expect(session.state.validations, isEmpty);
    expect(session.state.totalCount, 0);
    session.cancel(clearResults: true);
    expect(session.state.results, isEmpty);
  });

  test('request generation ignores obsolete asynchronous preparation',
      () async {
    final session = SearchSession(onChanged: (_) {});
    addTearDown(session.dispose);
    final old = session.begin();
    final latest = session.begin();
    var calls = 0;
    final request = SearchRequest(operations: [
      SearchOperation(
          label: 'test',
          run: () async {
            calls++;
            return _batch([]);
          }),
    ]);
    session.start(
        generation: old,
        request: request,
        resolveValidation: (_) => null,
        maxConcurrency: 1);
    expect(calls, 0);
    session.start(
        generation: latest,
        request: request,
        resolveValidation: (_) => null,
        maxConcurrency: 1);
    await _flush();
    expect(calls, 1);
  });

  test('fetch slots survive cancellation and skip obsolete queued jobs',
      () async {
    final session =
        SearchSession(onChanged: (_) {}, commitInterval: Duration.zero);
    addTearDown(session.dispose);
    final old = Completer<SearchFetchResult>();
    var obsoleteCalls = 0;
    var newCalls = 0;
    _start(session, [
      _operation('old', old.future),
      SearchOperation(
          label: 'obsolete',
          run: () async {
            obsoleteCalls++;
            return _batch([]);
          }),
    ]);
    _start(session, [
      SearchOperation(
          label: 'new',
          run: () async {
            newCalls++;
            return _batch([_item('new')]);
          })
    ]);
    await _flush();
    expect(newCalls, 0);
    old.complete(_batch([_item('old')]));
    await _flush();
    expect(obsoleteCalls, 0);
    expect(newCalls, 1);
    expect(session.state.results.single.id, 'new');
    expect(session.state.isSearching, isFalse);
  });

  for (final finished in [false, true]) {
    test('credential upgrade revalidates exactly once, finished=$finished',
        () async {
      final session =
          SearchSession(onChanged: (_) {}, commitInterval: Duration.zero);
      addTearDown(session.dispose);
      final second = Completer<SearchFetchResult>();
      final validation = Completer<ShareLinkValidationResult>();
      final passwords = <String>[];
      _start(
          session,
          [
            _operation('first', Future.value(_batch([_item('share')]))),
            _operation('second', second.future),
          ],
          validate: (item) => () {
                passwords.add(item.password);
                return item.password.isEmpty
                    ? validation.future
                    : Future.value(const ShareLinkValidationResult.valid());
              });
      await _flush();
      expect(session.state.isSearching, isTrue);
      if (finished) {
        validation.complete(const ShareLinkValidationResult.invalid('code'));
        await _flush();
      }
      second.complete(_batch([
        _item('later', url: 'https://anxia.com/s/share', password: 'abcd'),
        _item('third', url: 'https://115cdn.com/s/share', password: 'abcd'),
      ]));
      await _flush();
      if (!finished) {
        validation.complete(const ShareLinkValidationResult.invalid('code'));
      }
      await _flush();
      expect(passwords, ['', 'abcd']);
      expect(session.state.results.single.id, 'share');
      expect(session.state.results.single.password, 'abcd');
      expect(session.state.filteredCount, 2);
      expect(session.state.isSearching, isFalse);
    });
  }

  test('validation failure is unavailable and never leaves progress pending',
      () async {
    final session =
        SearchSession(onChanged: (_) {}, commitInterval: Duration.zero);
    addTearDown(session.dispose);
    _start(
        session,
        [
          _operation('test', Future.value(_batch([_item('one')])))
        ],
        validate: (_) => () async => throw StateError('network'));
    await _flush();
    expect(session.state.results.single.id, 'one');
    expect(session.state.validationFor(session.state.results.single),
        SearchValidationState.unavailable);
    expect(session.state.isSearching, isFalse);
  });

  test(
      'validation slots are shared across generations; stale checks cannot publish',
      () async {
    final snapshots = <SearchPresentationState>[];
    final session =
        SearchSession(onChanged: snapshots.add, commitInterval: Duration.zero);
    addTearDown(session.dispose);
    final pending = Completer<ShareLinkValidationResult>();
    final calls = <String>[];
    SearchValidationJob resolve(SearchResult item) => () {
          calls.add(item.id);
          return item.id == 'old'
              ? pending.future
              : Future.value(const ShareLinkValidationResult.valid());
        };
    _start(
        session,
        [
          _operation(
              'old', Future.value(_batch([_item('old'), _item('queued')])))
        ],
        validate: resolve);
    await _flush();
    final prior = session.state;
    _start(
        session,
        [
          _operation('new', Future.value(_batch([_item('new')])))
        ],
        validate: resolve);
    await _flush();
    expect(calls, ['old']);
    pending.complete(const ShareLinkValidationResult.valid());
    await _flush();
    expect(calls, ['old', 'new']);
    expect(session.state.results.single.id, 'new');
    expect(prior.results, isEmpty);
    expect(
        prior.validations.values
            .every((v) => v == SearchValidationState.pending),
        isTrue);
    expect(() => session.state.results.clear(), throwsUnsupportedError);
  });

  test('dispose cancels publication and queued validation', () async {
    var changes = 0;
    var calls = 0;
    final session = SearchSession(
        onChanged: (_) => changes++, commitInterval: Duration.zero);
    final pending = Completer<ShareLinkValidationResult>();
    _start(
        session,
        [
          _operation('test', Future.value(_batch([_item('one'), _item('two')])))
        ],
        validate: (_) => () {
              calls++;
              return pending.future;
            });
    await _flush();
    session.dispose();
    final before = changes;
    pending.complete(const ShareLinkValidationResult.valid());
    await _flush();
    expect(calls, 1);
    expect(changes, before);
  });

  test('equal titles keep insertion order; failures only replace empty results',
      () async {
    final session =
        SearchSession(onChanged: (_) {}, commitInterval: Duration.zero);
    addTearDown(session.dispose);
    _start(session, [
      _operation('test', Future.value(_batch([_item('b'), _item('a')]))),
      SearchOperation(
          label: 'broken', run: () async => throw StateError('offline')),
    ]);
    await _flush();
    expect(session.state.results.map((r) => r.id), ['b', 'a']);
    expect(session.state.errorMessage, isNull);
    _start(session, [
      SearchOperation(
          label: 'broken', run: () async => throw StateError('offline'))
    ]);
    await _flush();
    expect(session.state.errorMessage, contains('broken:'));
    expect(session.state.completedCount, 1);
    expect(session.state.isSearching, isFalse);
  });

  test('selection creates one operation per selected source and trims query',
      () async {
    final repository = _Repository();
    final request = SearchRequest.fromSelection(
      repository: repository,
      keyword: '  keyword  ',
      selectedTargetIds: {'all', 'provider:p'},
      localSources: [],
      providers: const [
        SearchProviderConfig(
            id: 'p',
            name: 'P',
            kind: SearchProviderKind.panSou,
            endpoint: 'https://example.test',
            enabled: true)
      ],
    );
    expect(request.operations, hasLength(1));
    await request.operations.single.run();
    expect(repository.queries, ['keyword']);
  });
}

class _Repository implements SearchRepository {
  final queries = <String>[];
  @override
  Future<SearchFetchResult> searchOnline(String query,
      {required SearchProviderConfig provider}) async {
    queries.add(query);
    return _batch([]);
  }

  @override
  Future<SearchFetchResult> searchLocal(String query,
          {String? sourceId, String? sectionId, int limit = 60}) async =>
      _batch([]);
}
