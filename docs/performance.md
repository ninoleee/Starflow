## Performance Baseline Runbook

`tool/perf/run_perf_baselines.dart` is the centralized script for capturing the five core performance baselines we are tracking: startup, home feed, detail screen, playback warm launch, and index refresh latency. Run it any time you change shared data layers, split hot UI files, or adjust the rendering/animation budget, so regressions are caught before a release.

### 2026-04-11 sync
The latest architecture pass moved several hot paths out of single large files:

* Home presentation is now split between `home_page.dart`, `home_page_hero.dart`, and `home_page_sections.dart`.
* Home application wiring is now split between `home_controller.dart`, `home_controller_models.dart`, and `home_feed_repository.dart`.
* Playback presentation is now split between `player_page.dart` and `presentation/widgets/player_page_*.part.dart` plus shared overlay/dialog widgets.
* NAS indexing is now split across `nas_media_indexer.dart` and the `nas_media_indexer_*` part files (`grouping`, `refresh_flow`, `storage_access`, `indexing`, `refresh_support`).
* Recent playback ordering now depends on the monotonic `updatedAt` behavior in `playback_memory_repository.dart`, which matters most on Windows where multiple saves can happen in the same millisecond.

### When to run
* After modifying performance-sensitive controllers such as `HomePageController`, `HomeFeedRepository`, playback startup coordinators/resolvers, or retained async controllers that were part of the P0/P1 efforts.
* After touching `home_page.dart`, `home_page_hero.dart`, or `home_page_sections.dart`, because they directly affect the `home_first_screen` baseline.
* After touching detail presentation hot paths such as `detail_page_providers.dart`, `detail_resource_info_section.dart`, or `detail_subtitle_section.dart`, because they directly affect `detail_first_screen` and detail interaction regressions.
* After touching `player_page.dart`, `presentation/widgets/player_page_*.part.dart`, `player_mpv_controls_overlay.dart`, `player_playback_options_dialog.dart`, or playback startup routing/execution, because they directly affect `player_open`.
* After touching `nas_media_indexer.dart` or any `nas_media_indexer_*` part file, because those changes can shift both `index_refresh` and any home/detail path that depends on index freshness.
* After changing `playback_memory_repository.dart`, because recent playback ordering changes can indirectly affect home feed stability and smoke expectations.
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
```

### Tips
* Run under the same system load you plan to ship under so the numbers stay comparable.
* Re-run the script after applying the fix if the regression was real; this rewrites the baseline JSON, which you can commit alongside the change when the new numbers are expected.
* If a baseline regresses right after a file split, verify the focused tests first. In this codebase, regressions after refactors are often caused by wiring/state-order changes rather than the split itself.
