import 'dart:convert';
import 'package:charset/charset.dart';
import '../domain/live_models.dart';

const livePlaylistMaxBytes = 8 * 1024 * 1024;
const liveMaxChannels = 10000;
const liveMaxLinesPerChannel = 64;
const liveMaxLines = 50000;

String decodeLiveText(List<int> bytes) {
  if (bytes.length > 1 &&
      ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
          (bytes[0] == 0xfe && bytes[1] == 0xff))) {
    if (bytes.length.isOdd) throw const FormatException('UTF-16 文件不完整');
    final littleEndian = bytes[0] == 0xff;
    return String.fromCharCodes([
      for (var i = 2; i + 1 < bytes.length; i += 2)
        littleEndian
            ? bytes[i] | bytes[i + 1] << 8
            : bytes[i] << 8 | bytes[i + 1]
    ]);
  }
  try {
    return utf8.decode(bytes).replaceFirst('\uFEFF', '');
  } on FormatException {
    return gbk.decode(bytes);
  }
}

class LivePlaylist {
  const LivePlaylist(this.channels, this.epgUrl);
  final List<LiveChannel> channels;
  final String epgUrl;
}

bool isLiveHttpUrl(String text) {
  if (RegExp(r'[\x00-\x20\x7f]').hasMatch(text)) return false;
  final u = Uri.tryParse(text);
  return u != null &&
      const {'http', 'https'}.contains(u.scheme) &&
      u.host.isNotEmpty &&
      u.userInfo.isEmpty;
}

Map<String, String> _attributes(String text) => {
      for (final m
          in RegExp(r'''([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s,]+))''')
              .allMatches(text))
        m[1]!.toLowerCase(): (m[2] ?? m[3] ?? m[4] ?? '').trim()
    };

LivePlaylist parseLivePlaylist(String text, String sourceId,
    {String baseUrl = ''}) {
  if (text.length > livePlaylistMaxBytes) {
    throw const FormatException('频道列表超过 8 MiB');
  }
  if (RegExp(r'^\s*#EXT-X-', multiLine: true)
      .hasMatch(text.replaceFirst('\uFEFF', ''))) {
    throw const FormatException('这是媒体播放清单，请导入频道列表或使用 TXT 添加该地址');
  }
  final channels = <String, LiveChannel>{};
  final lineKeys = <String, Set<String>>{};
  var lineCount = 0;
  var name = '', group = '', logo = '', epgId = '', epgUrl = '';
  var identity = '';
  var headers = <String, String>{};
  String resolve(String url) {
    if (url.trim().isEmpty) return '';
    final u = Uri.tryParse(url.trim());
    if (u == null) return '';
    final result = u.hasScheme
        ? u.toString()
        : Uri.tryParse(baseUrl)?.resolveUri(u).toString() ?? '';
    return isLiveHttpUrl(result) ? result : '';
  }

  void add(String title, String raw) {
    final parts = raw.split('|');
    final url = resolve(parts.first);
    if (url.isEmpty || title.trim().isEmpty) return;
    final lineHeaders = <String, String>{...headers};
    if (parts.length > 1) {
      try {
        final options = Uri.splitQueryString(parts.sublist(1).join('|'));
        for (final e in options.entries) {
          final key = const {
            'user-agent': 'User-Agent',
            'referer': 'Referer',
            'origin': 'Origin'
          }[e.key.toLowerCase()];
          if (key != null && !e.value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
            lineHeaders[key] = e.value;
          }
        }
      } on FormatException {/* Ignore malformed optional headers. */}
    }
    // Identity excludes volatile URLs; names/groups disambiguate shared EPG IDs.
    final id = liveId(jsonEncode([sourceId, epgId, group, title.trim()]));
    final old = channels[id];
    final lines = old?.lines ?? <LiveLine>[];
    final keys = lineHeaders.keys.toList()..sort();
    final signature = jsonEncode([
      url,
      {for (final k in keys) k: lineHeaders[k]}
    ]);
    if (lineKeys.putIfAbsent(id, () => {}).add(signature)) {
      if (lines.length >= liveMaxLinesPerChannel ||
          ++lineCount > liveMaxLines) {
        throw const FormatException('频道线路数量超过限制');
      }
      lines.add(LiveLine(url, headers: lineHeaders));
    }
    channels[id] = LiveChannel(
        id: id,
        sourceId: sourceId,
        name: title.trim(),
        group: group,
        epgId: epgId,
        identity: identity,
        logo: resolve(logo).isEmpty ? old?.logo ?? '' : resolve(logo),
        lines: lines);
    if (channels.length > liveMaxChannels) {
      throw const FormatException('频道数超过 10000');
    }
  }

  for (final raw
      in const LineSplitter().convert(text.replaceFirst('\uFEFF', ''))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTM3U')) {
      final a = _attributes(line);
      epgUrl = resolve((a['x-tvg-url'] ?? a['url-tvg'] ?? '').split(',').first);
    } else if (line.startsWith('#EXTINF:')) {
      // Commas inside quoted attributes do not delimit the display name.
      var quote = '', comma = -1;
      for (var i = 0; i < line.length; i++) {
        final c = line[i];
        if (quote.isNotEmpty) {
          if (c == quote) quote = '';
        } else if (c == '"' || c == "'") {
          quote = c;
        } else if (c == ',') {
          comma = i;
          break;
        }
      }
      final a = _attributes(comma < 0 ? line : line.substring(0, comma));
      name = comma < 0 ? a['tvg-name'] ?? '' : line.substring(comma + 1).trim();
      if (name.isEmpty) name = a['tvg-name'] ?? '';
      group = a['group-title'] ?? '';
      identity = a['tvg-id'] ?? '';
      logo = a['tvg-logo'] ?? '';
      epgId = [a['tvg-id'], a['tvg-name'], name]
          .whereType<String>()
          .firstWhere((s) => s.isNotEmpty, orElse: () => '');
      headers = {};
    } else if (line.startsWith('#EXTGRP:')) {
      group = line.substring(8).trim();
    } else if (line.startsWith('#EXTVLCOPT:')) {
      final option = line.substring(11);
      final eq = option.indexOf('=');
      if (eq > 0) {
        final key = {
          'http-user-agent': 'User-Agent',
          'http-referrer': 'Referer'
        }[option.substring(0, eq)];
        final value = option.substring(eq + 1);
        if (key != null && !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
          headers[key] = value;
        }
      }
    } else if (!line.startsWith('#')) {
      if (name.isNotEmpty) {
        add(name, line);
        name = '';
        headers = {};
      } else {
        final comma = line.indexOf(',');
        if (comma < 1) continue;
        final title = line.substring(0, comma).trim(),
            value = line.substring(comma + 1).trim();
        if (value == '#genre#') {
          group = title;
          continue;
        }
        epgId = title;
        identity = '';
        logo = '';
        headers = {};
        // Common TXT multi-line syntax; a URL's literal fragment is preserved.
        for (final url in value.split(RegExp(r'#(?=https?://)'))) {
          add(title, url);
        }
      }
    }
  }
  if (channels.isEmpty) throw const FormatException('未找到可播放的 HTTP/HTTPS 频道');
  final counts = <String, int>{};
  for (final c in channels.values) {
    if (c.identity.isNotEmpty) {
      counts.update(c.identity, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  return LivePlaylist([
    for (final c in channels.values)
      LiveChannel.fromJson({
        ...c.toJson(),
        if (counts[c.identity] == 1)
          'id': liveId(jsonEncode(['live-channel-v2', sourceId, c.identity])),
      }),
  ], epgUrl);
}
