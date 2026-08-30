## Performance Baseline Runbook

> This document describes the lightweight host-side smoke timer. For real
> profile-mode FrameTiming, slow-frame, and RSS baselines on hardware, use
> [`run_device_perf.dart`](../tool/perf/run_device_perf.dart) and follow
> [the device baseline guide](performance-baseline.md).

`tool/perf/run_perf_baselines.dart` is the centralized script for capturing the five core performance baselines we are tracking: startup, home feed, detail screen, playback warm launch, and index refresh latency. Run it any time you change shared data layers, split hot UI files, or adjust the rendering/animation budget, so regressions are caught before a release.

### 2026-08-27 sync
The latest architecture pass moved several hot paths out of single large files:

* Home presentation is now split between `home_page.dart`, `home_page_hero.dart`, and `home_page_sections.dart`.
* Home application wiring is now split between `home_controller.dart`, `home_controller_models.dart`, and `home_feed_repository.dart`.
* Playback presentation is now split between `player_page.dart` and `presentation/widgets/player_page_*.part.dart` plus shared overlay/dialog widgets.
* Playback network-speed labels reuse existing player telemetry: Exo is event-driven through its `DefaultBandwidthMeter`, while non-Web MPV reads the local `cache-speed` property once per second. Neither path launches an additional network probe; include the visible control chrome when comparing playback UI frame cost.
* NAS indexing is now split across `nas_media_indexer.dart` and the `nas_media_indexer_*` part files (`grouping`, `refresh_flow`, `storage_access`, `indexing`, `refresh_support`).
* Recent playback ordering now depends on the monotonic `updatedAt` behavior in `playback_memory_repository.dart`, which matters most on Windows where multiple saves can happen in the same millisecond.
* Home source loading and metadata prefetching retain separate schedulers but share one persisted maximum-concurrency value with Emby and NAS/WebDAV work. Record that value, initial batch sizes, continuation delays, and foreground resume delay with every comparable baseline.
* A single Home navigation tap is the explicit soft-recovery boundary: it removes scheduler-owned batch/quiet waits and cancels background library refreshes without zeroing active counters or duplicating in-flight requests. The TV exit dialog only holds new metadata prefetch starts while visible and resumes them immediately when cancelled.
* Lifecycle and memory-pressure admission are lease-based and stack safely. Backgrounding pauses new Home and metadata work; foreground resume waits for the first frame plus 400 ms. Memory pressure adds a separate two-second quiet window and cancels background library refreshes without clearing persistent caches or active counters.
* Queue diagnostics warn once per continuous queue period after 5 seconds for Home/metadata and 4 seconds for TV raster images. Compare `oldestWaitMs`, active/pending counts, pause holds, and the configured maximum before treating a long wall-clock wait as a performance regression.
* Explicit user refreshes may consume one half-open probe per currently open Douban/metadata host circuit. Automated baseline startup does not arm probes, so keep manual refreshes outside a comparable run.
* The default shared maximum is `2`; Home starts `2` modules in the first batch with a `350ms` continuation delay, while metadata starts `12` items with a `300ms` continuation delay. Scrolling, focus movement, and page transitions defer new metadata starts for `400ms` by default.
* NAS/WebDAV source, collection, and enrichment-item budgets all read the shared maximum, with internal caps of `2` sources and `4` collections/items. Every online enrichment item additionally passes through the global metadata limiter.
* Structure-inferred episodes resolve online series metadata with the parent series title. Provider in-flight/result caches are therefore shared across a season instead of issuing one title search per episode filename; optional episode still requests remain separate.
* NAS/WebDAV series and season hierarchies are materialized into the source cache once and indexed per section. Detail child reads therefore avoid regrouping the full source for every series open or season switch.
* Large episode rows remain lazily built. TV artwork uses a shared four-request raster-load gate whose permits carry an eight-second self-healing lease, so an offstage widget cannot permanently stall Hero and poster loading. Image HTTP work times out after 15 seconds and retries after 1, 4, and 12 seconds; inactive detail routes still unload deferred sections and release queued work.
* Emby section refreshes enter the same global limiter as NAS metadata items. Maintenance sections have priority, so a large Emby library no longer launches every section request alongside NAS enrichment.
* Emby library persistence uses the current small manifest plus a source summary and source/section shards. Root-library and collection-only reads share a newest-400-item summary, section-scoped Home loads decode only the requested shard, and full-library matching decodes at most two shards concurrently. Identical snapshot and shard reads share in-flight work. Fallback payloads exclude items already represented by section shards, and large JSON work runs on a background isolate. Loads slower than `500ms` emit an info-level `storage.emby-cache` record. Legacy single-payload caches are not read or migrated.
* Concurrent detail-cache updates arriving within 16 ms are merged into one serialized persistence operation. Byte-identical encoded payloads skip the preferences write, avoiding back-to-back writes of the roughly 500–600 KB detail payload seen in TV diagnostics.
* NAS/WebDAV section reads now apply `sourceId + sectionId` in the Sembast finder instead of loading a whole source into Dart before filtering.
* Bootstrap and the navigation shell share cold-start refresh completion state, so a baseline should contain at most one automatic Home refresh cycle.
* Structured logging and the frame monitor are active by default. Keep the same recorded log levels across comparison runs because trace-heavy diagnostics add some I/O.
* Successful metadata cache hits, joins of already in-flight requests, and empty sidecar contexts no longer emit one `TRACE` record per item. Keep comparing warning/error counts, but do not treat the lower trace volume as missing work.
* Movie version-folder recognition and the migration fingerprint run locally during NAS/WebDAV indexing. The library emits one representative movie while retaining the real files for detail playback choices, so compare both `media_index` duration and final record/card counts after this change.
* Detail source selection and playback-version selection are now separate derived views over the same retained candidate state. The source selector deduplicates providers, while the Hero-adjacent version selector only builds the selected source's playable files; include a multi-source, multi-version detail sample when investigating `detail_first_screen` or interaction regressions.

### When to run
* After modifying performance-sensitive controllers such as `HomePageController`, `HomeFeedRepository`, playback startup coordinators/resolvers, or retained async controllers that were part of the P0/P1 efforts.
* After touching `home_page.dart`, `home_page_hero.dart`, or `home_page_sections.dart`, because they directly affect the `home_first_screen` baseline.
* After touching detail presentation hot paths such as `detail_page_providers.dart`, `detail_resource_info_section.dart`, or `media_detail_page.dart`, because they directly affect `detail_first_screen` and detail interaction regressions.
* After touching `player_page.dart`, `presentation/widgets/player_page_*.part.dart`, `player_network_speed_label.dart`, `player_playback_options_dialog.dart`, or playback startup routing/execution, because they directly affect `player_open`.
* After touching `nas_media_indexer.dart` or any `nas_media_indexer_*` part file, because those changes can shift both `index_refresh` and any home/detail path that depends on index freshness.
* After changing `playback_memory_repository.dart`, because recent playback ordering changes can indirectly affect home feed stability and smoke expectations.
* After changing `home_feed_load_scheduler.dart`, `metadata_prefetch_concurrency_limiter.dart`, network guards, startup refresh settings, or structured logging.
* Before merging large refactors that could affect the timeline between user interaction and the first frame.

### Command
```bash
dart tool/perf/run_perf_baselines.dart
```

Common variants:

```bash
dart tool/perf/run_perf_baselines.dart --runs 3
dart tool/perf/run_perf_baselines.dart --scenario player_open --runs 1
dart tool/perf/run_perf_baselines.dart --runs 1 --output tool/perf/perf_baselines.json
```

It runs the selected baseline scenarios and writes JSON output to `tool/perf/perf_baselines.json` by default, unless `--output` is provided. The script assumes Flutter is available via `flutter` in the path and runs on the host OS.

### Output and validation
Review the generated report for regressions in the five baseline IDs: `startup`, `home_first_screen`, `detail_first_screen`, `player_open`, and `index_refresh`. The JSON contains `generatedAt`, `runsPerScenario`, and a `results` array with `runsMs`, `p50Ms`, and `p95Ms` for each scenario. If runtime shifts significantly, capture the new numbers together with the relevant diff and scenario id.

### Suggested focused verification
For this repo, the perf baseline run is usually paired with a few focused checks so we can tell whether a regression is functional, orchestration-related, or purely performance-related:

```bash
dart analyze lib/features/home/application/home_controller.dart lib/features/home/application/home_controller_models.dart lib/features/home/application/home_feed_repository.dart
flutter test test/home_controller_test.dart test/home_settings_slices_test.dart

dart analyze lib/features/playback/presentation/player_page.dart lib/features/playback/presentation/widgets lib/features/playback/data/playback_memory_repository.dart
flutter test test/playback_memory_repository_test.dart test/features/playback/application/playback_startup_routing_test.dart test/playback_target_resolver_test.dart test/playback_mpv_policy_test.dart

dart analyze lib/features/library/data/nas_media_indexer.dart lib/features/library/data/nas_media_indexer_grouping.dart lib/features/library/data/nas_media_indexer_refresh_flow.dart lib/features/library/data/nas_media_indexer_refresh_support.dart
flutter test test/nas_media_indexer_test.dart

dart analyze lib/core/network lib/core/logging lib/features/home/application/home_feed_load_scheduler.dart lib/features/metadata/application/metadata_prefetch_concurrency_limiter.dart
flutter test test/network_failure_test.dart test/network_request_guard_test.dart test/starflow_http_client_test.dart test/metadata_prefetch_concurrency_limiter_test.dart
```

### Tips
* Run under the same system load you plan to ship under so the numbers stay comparable.
* Re-run the script after applying the fix if the regression was real; this rewrites the baseline JSON, which you can commit alongside the change when the new numbers are expected.
* If a baseline regresses right after a file split, verify the focused tests first. In this codebase, regressions after refactors are often caused by wiring/state-order changes rather than the split itself.
* Keep the independent visual/playback switches, both startup refresh switches, the shared concurrency value, scheduler batch/delay values, and log levels identical when comparing two runs. TV-fixed protections are platform rules rather than comparison-time switches.
