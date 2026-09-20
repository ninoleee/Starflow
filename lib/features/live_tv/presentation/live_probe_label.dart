import 'package:flutter/material.dart';

import '../application/live_channel_probe_controller.dart';
import '../data/live_channel_probe.dart';
import 'live_widgets.dart';

class LiveProbeLabel extends StatelessWidget {
  const LiveProbeLabel({super.key, required this.entry});

  final LiveProbeEntry? entry;

  @override
  Widget build(BuildContext context) {
    final result = entry?.result;
    final refreshing = entry?.checking == true && result != null;
    final color = result == null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : result.status == LiveProbeStatus.responded
            ? Colors.greenAccent.shade200
            : Theme.of(context).colorScheme.error;
    final message = entry == null
        ? '尚未检测当前首选线路'
        : '线路 ${entry!.lineIndex + 1} · ${entry!.label}${refreshing ? ' · 刷新中' : ''}'
            '${result == null ? '' : ' · ${liveTime(result.checkedAt)}'}\n'
            '仅检测首包响应，不代表可解码播放或持续网速';
    return Tooltip(
      message: message,
      child: Semantics(
        label: message,
        child: SizedBox(
          width: 76,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: Row(children: [
              if (refreshing) ...[
                const Icon(Icons.refresh, size: 12),
                const SizedBox(width: 2),
              ],
              Expanded(
                  child: Text(entry?.label ?? '未测',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.left,
                      style: TextStyle(fontSize: 11, color: color))),
            ]),
          ),
        ),
      ),
    );
  }
}
