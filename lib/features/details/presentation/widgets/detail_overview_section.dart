import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starflow/core/utils/metadata_text.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/presentation/widgets/detail_television_picker_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

class DetailOverviewSection extends StatefulWidget {
  const DetailOverviewSection({
    super.key,
    required this.title,
    required this.overview,
    required this.isTelevision,
    required this.focusId,
    this.episodeTitle,
    this.sourceLauncher,
  });

  final String title;
  final String overview;
  final bool isTelevision;
  final String focusId;
  final String? episodeTitle;
  final Future<bool> Function(Uri)? sourceLauncher;

  @override
  State<DetailOverviewSection> createState() => _DetailOverviewSectionState();
}

class _DetailOverviewSectionState extends State<DetailOverviewSection> {
  late MetadataOverviewContent _content;
  final _moreFocus = FocusNode(debugLabel: 'detail-overview-more');
  final _expandFocus = FocusNode(debugLabel: 'detail-overview-expand');
  final _bodyFocus = FocusNode(debugLabel: 'detail-overview-body');
  final _bodyScroll = ScrollController();
  bool _expanded = false;
  bool _openingSources = false;

  @override
  void initState() {
    super.initState();
    _content = parseMetadataOverview(widget.overview);
  }

  @override
  void didUpdateWidget(covariant DetailOverviewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.overview != oldWidget.overview ||
        widget.focusId != oldWidget.focusId) {
      _content = parseMetadataOverview(widget.overview);
      _expanded = false;
    }
  }

  @override
  void dispose() {
    _moreFocus.dispose();
    _expandFocus.dispose();
    _bodyFocus.dispose();
    _bodyScroll.dispose();
    super.dispose();
  }

  Future<void> _showMore() async {
    if (_openingSources) {
      return;
    }
    _openingSources = true;
    final overview = widget.overview;
    final sources = _content.sources;
    try {
      final action = await showDetailTelevisionPickerDialog<String>(
        context: context,
        enabled: widget.isTelevision,
        title: '更多',
        options: [
          DetailTelevisionPickerOption(
            value: 'sources',
            title: '视频来源',
            icon: Icons.link_rounded,
            focusId: '${widget.focusId}:sources',
          ),
        ],
        selectedValue: null,
        optionDebugLabelPrefix: 'overview-more',
        closeFocusDebugLabel: 'overview-more-close',
        closeFocusId: '${widget.focusId}:more-close',
      );
      if (!mounted || action != 'sources' || overview != widget.overview) {
        return;
      }
      final uri = await showDetailTelevisionPickerDialog<Uri>(
        context: context,
        enabled: widget.isTelevision,
        title: '视频来源',
        options: [
          for (var i = 0; i < sources.length; i++)
            DetailTelevisionPickerOption(
              value: sources[i],
              title: sources[i].host,
              subtitle: sources[i].toString(),
              icon: Icons.open_in_new_rounded,
              focusId: '${widget.focusId}:source:$i',
            ),
        ],
        selectedValue: null,
        optionDebugLabelPrefix: 'overview-source',
        closeFocusDebugLabel: 'overview-source-close',
        closeFocusId: '${widget.focusId}:source-close',
      );
      if (!mounted || uri == null || overview != widget.overview) {
        return;
      }
      var launched = false;
      try {
        if (resolveMetadataSourceUri(uri.toString()) != null) {
          launched = await (widget.sourceLauncher?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
        }
      } catch (_) {
        launched = false;
      }
      if (mounted && !launched) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开链接')),
        );
      }
    } finally {
      _openingSources = false;
      if (mounted && _moreFocus.canRequestFocus) {
        _moreFocus.requestFocus();
      }
    }
  }

  void _toggleExpanded() {
    if (_bodyFocus.hasFocus) {
      _expandFocus.requestFocus();
    }
    setState(() => _expanded = !_expanded);
    if (!_expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final focusContext = _expandFocus.context;
        if (mounted && focusContext != null) {
          unawaited(Scrollable.ensureVisible(focusContext));
        }
      });
    }
  }

  Widget _buildBody(String text, TextStyle style, {required bool canExpand}) {
    final body = Text(
      text,
      key: const ValueKey('detail-overview-text'),
      style: style,
      maxLines: _expanded ? null : 6,
      overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
    );
    if (!widget.isTelevision) {
      return body;
    }
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (!_expanded || event is KeyUpEvent || !_bodyScroll.hasClients) {
          return KeyEventResult.ignored;
        }
        final direction = switch (event.logicalKey) {
          LogicalKeyboardKey.arrowDown => 1,
          LogicalKeyboardKey.arrowUp => -1,
          _ => 0,
        };
        if (direction == 0) {
          return KeyEventResult.ignored;
        }
        final position = _bodyScroll.position;
        final next =
            (position.pixels + direction * position.viewportDimension * 0.7)
                .clamp(position.minScrollExtent, position.maxScrollExtent);
        if ((next - position.pixels).abs() < 1) {
          return KeyEventResult.ignored;
        }
        _bodyScroll.jumpTo(next);
        return KeyEventResult.handled;
      },
      child: TvFocusableAction(
        focusNode: _bodyFocus,
        focusId: '${widget.focusId}:body',
        onPressed: canExpand ? _toggleExpanded : () {},
        borderRadius: BorderRadius.circular(8),
        visualStyle: TvFocusVisualStyle.subtle,
        child: !_expanded
            ? body
            : ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.55),
                child: Scrollbar(
                  controller: _bodyScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _bodyScroll,
                    primary: false,
                    padding: const EdgeInsets.only(right: 12),
                    child: body,
                  ),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const style =
        TextStyle(color: Color(0xFFDCE6F8), fontSize: 15, height: 1.7);
    final text = _content.text.isEmpty ? '暂无简介' : _content.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (_content.sources.isNotEmpty) ...[
                const SizedBox(width: 8),
                StarflowIconButton(
                  icon: Icons.more_horiz_rounded,
                  tooltip: '更多',
                  focusNode: _moreFocus,
                  focusId: '${widget.focusId}:more',
                  onPressed: () => unawaited(_showMore()),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (widget.episodeTitle != null) ...[
            Text(
              widget.episodeTitle!,
              style: const TextStyle(
                color: Color(0xFFF1F5FF),
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
          ],
          LayoutBuilder(builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(text: text, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 6,
              ellipsis: '...',
            )..layout(maxWidth: constraints.maxWidth);
            final canExpand = painter.didExceedMaxLines;
            painter.dispose();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (canExpand) ...[
                  StarflowButton(
                    label: _expanded ? '收起' : '展开全文',
                    icon: _expanded ? Icons.expand_less : Icons.expand_more,
                    variant: StarflowButtonVariant.ghost,
                    compact: true,
                    focusNode: _expandFocus,
                    focusId: '${widget.focusId}:expand',
                    onPressed: _toggleExpanded,
                  ),
                  const SizedBox(height: 8),
                ],
                _buildBody(text, style, canExpand: canExpand),
              ],
            );
          }),
        ],
      ),
    );
  }
}
