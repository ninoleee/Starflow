## Performance Baseline Runbook

`tool/perf/run_perf_baselines.dart` is the centralized script for capturing the five core performance baselines our teams are tracking: startup, home feed, detail screen, playback warm launch, and index refresh latency. Run it any time you change shared data layers (especially the library stack) or adjust the rendering/animation budget, so regressions are caught before a release.

### When to run
* After modifying performance-sensitive controllers (e.g., playback startup, home feed orchestration, or retained async controllers) that were part of the P0/P1 efforts.
* After touching detail presentation hot paths such as `detail_page_providers.dart`, `detail_resource_info_section.dart`, or `detail_subtitle_section.dart`, because they directly affect `detail_first_screen` and detail interaction regressions.
* Before merging large refactors that could affect the timeline between user interaction and the first frame (detail/home/playback/indices).
* Whenever you update the media cache/indexing behavior so that the refresh or home feed timing may drift.

### Command
```
dart tool/perf/run_perf_baselines.dart
```
Common variants:
```
dart tool/perf/run_perf_baselines.dart --runs 3
dart tool/perf/run_perf_baselines.dart --scenario player_open --runs 1
dart tool/perf/run_perf_baselines.dart --runs 1 --output tool/perf/perf_baselines.json
```
It will run the selected baseline scenarios and write JSON output to `tool/perf/perf_baselines.json` by default, unless `--output` is provided. The script assumes Flutter is available via `flutter` in the path and runs on the host OS (mac/linux/windows).

### Output and validation
Review the generated report for regressions in the five baseline IDs: `startup`, `home_first_screen`, `detail_first_screen`, `player_open`, and `index_refresh`. The JSON contains `generatedAt`, `runsPerScenario`, and a `results` array with `runsMs`, `p50Ms`, and `p95Ms` for each scenario. If runtime shifts significantly, capture the new numbers together with the relevant diff and scenario id.

### Tips
* Run under the same system load you plan to ship under (quiet desktop, airplane mode) so the numbers stay comparable.
* Re-run the script after applying the fix if the regression was real; this rewrites the baseline JSON, which you can commit alongside the change when the new numbers are expected.
