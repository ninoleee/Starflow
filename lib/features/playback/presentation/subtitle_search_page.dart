import 'package:starflow/core/logging/app_logger.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/playback/application/online_subtitle_search_request_builder.dart';
import 'package:starflow/features/playback/data/online_subtitle_repository.dart';
import 'package:starflow/features/playback/data/subtitle_search_host_bridge.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/playback/domain/subtitle_operation.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';

class SubtitleSearchPage extends ConsumerStatefulWidget {
  const SubtitleSearchPage({
    super.key,
    required this.request,
  });

  final SubtitleSearchRequest request;

  @override
  ConsumerState<SubtitleSearchPage> createState() => _SubtitleSearchPageState();
}

class _SubtitleSearchPageState extends ConsumerState<SubtitleSearchPage> {
  late final TextEditingController _controller;
  late final List<OnlineSubtitleSource> _availableSources;
  late List<OnlineSubtitleSource> _selectedSources;
  List<SubtitleSearchResult> _results = const [];
  Map<String, SubtitleSearchSelection> _validatedSelectionsByResultId =
      const <String, SubtitleSearchSelection>{};
  Map<String, ValidatedSubtitleCandidate> _structuredCandidatesByResultId =
      const <String, ValidatedSubtitleCandidate>{};
  bool _isSearching = false;
  String? _errorMessage;
  String? _busyResultId;
  int _searchGeneration = 0;
  SubtitleOperation? _operation;

  void _cancelOperation() {
    _operation?.cancel();
    _operation = null;
    _searchGeneration++;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _resolveInitialInput(widget.request),
    );
    _availableSources =
        ref.read(appSettingsProvider).effectiveOnlineSubtitleSources;
    _selectedSources = _availableSources.toList(growable: false);
  }

  @override
  void didUpdateWidget(covariant SubtitleSearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request == widget.request) {
      return;
    }
    _cancelOperation();
    _busyResultId = null;
    _isSearching = false;
    _results = const [];
    _validatedSelectionsByResultId = const {};
    _structuredCandidatesByResultId = const {};
    final nextInput = _resolveInitialInput(widget.request);
    if (_controller.text == nextInput) {
      return;
    }
    _controller.value = TextEditingValue(
      text: nextInput,
      selection: TextSelection.collapsed(offset: nextInput.length),
    );
  }

  @override
  void dispose() {
    _cancelOperation();
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _handleClose() async {
    _cancelOperation();
    if (!widget.request.standalone) {
      return true;
    }
    final handled = await SubtitleSearchHostBridge.cancel();
    return !handled;
  }

  String _resolveInitialInput(SubtitleSearchRequest request) {
    final initialInput = request.initialInput.trim();
    if (initialInput.isNotEmpty) {
      return initialInput;
    }
    final title = request.title.trim();
    if (title.isNotEmpty) {
      return title;
    }
    final query = request.query.trim();
    return query;
  }

  Future<void> _performSearch() async {
    if (_isSearching || _busyResultId != null) return;
    _cancelOperation();
    final operation = _operation = SubtitleOperation();
    final generation = _searchGeneration;
    final query = _controller.text.trim();
    if (query.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _results = const [];
        _validatedSelectionsByResultId =
            const <String, SubtitleSearchSelection>{};
        _structuredCandidatesByResultId =
            const <String, ValidatedSubtitleCandidate>{};
        _isSearching = false;
        _errorMessage = '请先输入要搜索的字幕关键词';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _results = const [];
      _validatedSelectionsByResultId =
          const <String, SubtitleSearchSelection>{};
      _structuredCandidatesByResultId =
          const <String, ValidatedSubtitleCandidate>{};
      _errorMessage = null;
    });

    try {
      final settings = ref.read(appSettingsProvider);
      final availableSources = settings.effectiveOnlineSubtitleSources;
      final sources = _selectedSources
          .where(availableSources.contains)
          .toSet()
          .toList(growable: false);
      if (sources.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _results = const [];
          _isSearching = false;
          _errorMessage = _availableSources.isEmpty
              ? '请先在设置里启用至少一个在线字幕来源'
              : '请先在当前页面选择至少一个在线字幕来源';
        });
        return;
      }
      final repository = ref.read(onlineSubtitleRepositoryProvider);
      final structuredSources = sources
          .where(settings.configuredStructuredSubtitleSources.contains)
          .toList(growable: false);

      final nextResultsById = <String, SubtitleSearchResult>{};
      final validatedSelections = <String, SubtitleSearchSelection>{};
      final structuredCandidatesByResultId =
          <String, ValidatedSubtitleCandidate>{};

      if (structuredSources.isNotEmpty) {
        final manuallyEdited = query != _resolveInitialInput(widget.request);
        final structuredRequest =
            await buildOnlineSubtitleSearchRequestForRoute(
          SubtitleSearchRequest(
            query: query,
            title: manuallyEdited ? '' : widget.request.title,
            originalTitle: manuallyEdited ? '' : widget.request.originalTitle,
            initialInput: widget.request.initialInput,
            year: manuallyEdited ? null : widget.request.year,
            imdbId: manuallyEdited ? '' : widget.request.imdbId,
            tmdbId: manuallyEdited ? '' : widget.request.tmdbId,
            seasonNumber: manuallyEdited ? null : widget.request.seasonNumber,
            episodeNumber: manuallyEdited ? null : widget.request.episodeNumber,
            filePath: manuallyEdited ? '' : widget.request.filePath,
            applyMode: widget.request.applyMode,
            standalone: widget.request.standalone,
          ),
          languages: settings.subtitlePreferredLanguages,
        );
        if (!mounted || generation != _searchGeneration) return;
        final candidates = await repository.searchStructured(
          structuredRequest,
          sources: structuredSources,
          maxResults: settings.subtitleSearchMaxValidatedCandidates * 4,
          maxValidated: settings.subtitleSearchMaxValidatedCandidates,
          operation: operation,
        );
        for (final candidate in candidates) {
          final result = candidate.toSearchResult();
          nextResultsById.putIfAbsent(result.id, () => result);
          structuredCandidatesByResultId[result.id] = candidate;
          if (candidate.canApply) {
            validatedSelections[result.id] = SubtitleSearchSelection(
              cachedPath: candidate.cachedPath,
              displayName: candidate.displayName,
              subtitleFilePath: candidate.subtitleFilePath,
            );
          }
        }
      }
      final nextResults = nextResultsById.values.toList(growable: false);
      if (!mounted || generation != _searchGeneration) {
        return;
      }
      setState(() {
        _results = nextResults;
        _validatedSelectionsByResultId = validatedSelections;
        _structuredCandidatesByResultId = structuredCandidatesByResultId;
        _isSearching = false;
        _errorMessage = nextResults.isEmpty ? '没有找到可用字幕结果' : null;
      });
    } catch (error, stackTrace) {
      if (!mounted || generation != _searchGeneration) {
        return;
      }
      appLogError('subtitle', 'page.search.failed',
          fields: {
            'query': query,
            'selectedSources':
                _selectedSources.map((item) => item.name).join('/'),
          },
          error: error,
          stackTrace: stackTrace);
      setState(() {
        _results = const [];
        _validatedSelectionsByResultId =
            const <String, SubtitleSearchSelection>{};
        _structuredCandidatesByResultId =
            const <String, ValidatedSubtitleCandidate>{};
        _isSearching = false;
        _errorMessage = '$error';
      });
    }
  }

  Future<void> _handleDownload(SubtitleSearchResult result) async {
    final generation = _searchGeneration;
    if (_busyResultId != null || _isSearching) {
      return;
    }
    final validatedSelection = _validatedSelectionsByResultId[result.id];
    if (validatedSelection != null) {
      await _finishSelection(
        result: result,
        selection: validatedSelection,
      );
      return;
    }
    if (widget.request.applyMode == SubtitleSearchApplyMode.downloadAndApply &&
        !result.canAutoLoad) {
      _showMessage('当前先支持自动加载 ZIP / SRT / ASS / SSA / VTT 字幕');
      return;
    }

    setState(() {
      _busyResultId = result.id;
    });
    _operation?.cancel();
    final operation = _operation = SubtitleOperation();
    SubtitleDownloadResult? downloadResult;
    var accepted = false;
    try {
      downloadResult = await ref
          .read(onlineSubtitleRepositoryProvider)
          .download(result, operation: operation);
      if (!mounted || generation != _searchGeneration) return;
      final selection = SubtitleSearchSelection(
        cachedPath: downloadResult.cachedPath,
        displayName: downloadResult.displayName,
        subtitleFilePath: downloadResult.subtitleFilePath,
      );
      accepted = await _finishSelection(result: result, selection: selection);
    } catch (error, stackTrace) {
      if (operation.isCancelled) return;
      appLogError('subtitle', 'page.download.failed',
          fields: {
            'resultId': result.id,
            'source': result.source.name,
          },
          error: error,
          stackTrace: stackTrace);
      if (mounted && generation == _searchGeneration) _showMessage('$error');
    } finally {
      if (!accepted) {
        try {
          await downloadResult?.discard?.call();
        } catch (error, stackTrace) {
          appLogError('subtitle', 'page.download.cleanup.failed',
              error: error, stackTrace: stackTrace);
        }
      }
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _busyResultId = null;
        });
      }
    }
  }

  Future<bool> _finishSelection({
    required SubtitleSearchResult result,
    required SubtitleSearchSelection selection,
  }) async {
    if (widget.request.applyMode == SubtitleSearchApplyMode.downloadAndApply &&
        !selection.canApply) {
      _showMessage('字幕已缓存，但当前结果暂不能直接挂载播放');
      return false;
    }
    if (!mounted) {
      return false;
    }
    if (widget.request.standalone) {
      final generation = _searchGeneration;
      final handled = await SubtitleSearchHostBridge.finishSelection(selection);
      if (handled) return true;
      if (mounted && generation == _searchGeneration) {
        Navigator.of(context).pop(selection);
        return true;
      }
      return false;
    }
    Navigator.of(context).pop(selection);
    return true;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final applyMode = request.applyMode;
    final title = request.title.trim().isEmpty ? '在线字幕' : request.title.trim();
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;

    return PopScope<Object?>(
      canPop: !request.standalone,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          _cancelOperation();
          return;
        }
        if (!request.standalone) {
          return;
        }
        await _handleClose();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !isTelevision,
          leadingWidth: isTelevision ? null : 64,
          title: Text(applyMode == SubtitleSearchApplyMode.downloadOnly
              ? '下载字幕'
              : '搜索并加载字幕'),
          leading: isTelevision
              ? null
              : SizedBox(
                  width: 56,
                  height: 56,
                  child: IconButton(
                    padding: const EdgeInsets.all(16),
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      if (await _handleClose()) {
                        navigator.maybePop();
                      }
                    },
                  ),
                ),
        ),
        body: AppPageBackground(
          child: SafeArea(
            child: TvPageFocusScope(
              isTelevision: isTelevision,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: _SearchHeader(
                      isTelevision: isTelevision,
                      controller: _controller,
                      title: title,
                      applyMode: applyMode,
                      availableSources: _availableSources,
                      selectedSources: _selectedSources,
                      onSourceChanged: (source, selected) {
                        setState(() {
                          final next = _selectedSources.toSet();
                          if (selected) {
                            next.add(source);
                          } else {
                            next.remove(source);
                          }
                          _selectedSources = next.toList(growable: false);
                        });
                      },
                      onSearch: _performSearch,
                      isBusy: _isSearching || _busyResultId != null,
                    ),
                  ),
                  Expanded(
                    child: _buildBody(applyMode, isTelevision),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(SubtitleSearchApplyMode applyMode, bool isTelevision) {
    if (_isSearching && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _results.isEmpty) {
      return _SubtitleSearchEmptyState(message: _errorMessage!);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemBuilder: (context, index) {
        final result = _results[index];
        return _SubtitleResultTile(
          key: ValueKey(result.id),
          isTelevision: isTelevision,
          result: result,
          validationCandidate: _structuredCandidatesByResultId[result.id],
          hasValidatedSelection:
              _validatedSelectionsByResultId.containsKey(result.id),
          applyMode: applyMode,
          isBusy: _busyResultId == result.id,
          onPressed: () => _handleDownload(result),
        );
      },
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemCount: _results.length,
    );
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.isTelevision,
    required this.controller,
    required this.title,
    required this.applyMode,
    required this.availableSources,
    required this.selectedSources,
    required this.onSourceChanged,
    required this.onSearch,
    required this.isBusy,
  });

  final TextEditingController controller;
  final bool isTelevision;
  final String title;
  final SubtitleSearchApplyMode applyMode;
  final List<OnlineSubtitleSource> availableSources;
  final List<OnlineSubtitleSource> selectedSources;
  final void Function(OnlineSubtitleSource source, bool selected)
      onSourceChanged;
  final Future<void> Function() onSearch;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            applyMode == SubtitleSearchApplyMode.downloadOnly
                ? '在应用内搜索字幕并下载到本地缓存。'
                : '在应用内搜索字幕，下载后直接挂到当前播放器。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          if (isTelevision)
            Row(
              children: [
                Expanded(
                  child: SettingsTextInputField(
                    controller: controller,
                    labelText: '字幕关键词',
                    hintText: '片名、剧名、S01E01、年份等',
                    autofocus: true,
                    focusId: 'subtitle-search:query',
                  ),
                ),
                const SizedBox(width: 12),
                StarflowIconButton(
                  icon: Icons.search_rounded,
                  tooltip: '搜索字幕',
                  focusId: 'subtitle-search:submit',
                  focusableWhenDisabled: true,
                  onPressed: isBusy ? null : () => unawaited(onSearch()),
                ),
              ],
            )
          else
            TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: isBusy ? null : (_) => unawaited(onSearch()),
              decoration: InputDecoration(
                labelText: '字幕关键词',
                hintText: '片名、剧名、S01E01、年份等',
                filled: true,
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search_rounded),
                  onPressed: isBusy ? null : () => unawaited(onSearch()),
                ),
              ),
            ),
          if (availableSources.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '字幕来源',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final source in availableSources)
                  StarflowChipButton(
                    label: source.label,
                    selected: selectedSources.contains(source),
                    onPressed: () => onSourceChanged(
                      source,
                      !selectedSources.contains(source),
                    ),
                    focusId: 'subtitle-search:source:${source.name}',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SubtitleResultTile extends StatelessWidget {
  const _SubtitleResultTile({
    super.key,
    required this.isTelevision,
    required this.result,
    required this.validationCandidate,
    required this.hasValidatedSelection,
    required this.applyMode,
    required this.isBusy,
    required this.onPressed,
  });

  final SubtitleSearchResult result;
  final bool isTelevision;
  final ValidatedSubtitleCandidate? validationCandidate;
  final bool hasValidatedSelection;
  final SubtitleSearchApplyMode applyMode;
  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = hasValidatedSelection ||
        (result.canDownload &&
            (applyMode == SubtitleSearchApplyMode.downloadOnly ||
                result.canAutoLoad));
    final buttonLabel = _resolveButtonLabel(enabled);

    return TvFocusableAction(
      focusId: 'subtitle-search:result:${result.id}',
      focusableWhenDisabled: enabled,
      onPressed: enabled && !isBusy ? onPressed : null,
      borderRadius: BorderRadius.circular(24),
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (result.providerLabel.trim().isNotEmpty) ...[
                          Text(
                            result.providerLabel,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          result.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (result.detailLine.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            result.detailLine,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _SubtitleKindBadge(
                    label: result.packageKind.label,
                    enabled: enabled,
                  ),
                ],
              ),
              if (result.summaryLine.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  result.summaryLine,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (validationCandidate != null) ...[
                const SizedBox(height: 8),
                Text(
                  validationCandidate!.statusDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _validationTextColor(theme),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (result.packageName.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  result.packageName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary.withValues(alpha: 0.88),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: ExcludeFocus(
                  excluding: isTelevision,
                  child: StarflowButton(
                    label: isBusy ? '处理中...' : buttonLabel,
                    onPressed: enabled && !isBusy ? onPressed : null,
                    variant: enabled
                        ? StarflowButtonVariant.secondary
                        : StarflowButtonVariant.ghost,
                    compact: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _resolveButtonLabel(bool enabled) {
    if (applyMode == SubtitleSearchApplyMode.downloadOnly) {
      return hasValidatedSelection ? '使用已缓存' : '下载到缓存';
    }
    if (hasValidatedSelection) {
      return '直接加载';
    }
    if (enabled) {
      return '下载并加载';
    }
    return '暂不支持';
  }

  Color _validationTextColor(ThemeData theme) {
    return switch (validationCandidate?.status) {
      SubtitleValidationStatus.validated => theme.colorScheme.primary,
      SubtitleValidationStatus.failed => theme.colorScheme.error,
      SubtitleValidationStatus.skipped => theme.colorScheme.onSurfaceVariant,
      _ => theme.colorScheme.onSurfaceVariant,
    };
  }
}

class _SubtitleKindBadge extends StatelessWidget {
  const _SubtitleKindBadge({
    required this.label,
    required this.enabled,
  });

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: enabled
            ? theme.colorScheme.primary.withValues(alpha: 0.16)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: enabled
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SubtitleSearchEmptyState extends StatelessWidget {
  const _SubtitleSearchEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
