import 'dart:convert';

import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';

enum HlsResourceKind { playlist, segment, encryptedSegment, key }

/// A bounded HLS subset, not a general-purpose HLS parser.
/// Unknown extension tags fail closed so new URL-bearing syntax cannot bypass
/// the relay. LL-HLS is served as full segments: hints and blocking/delta reload
/// advertisements are removed, so engines never fetch unregistered part URLs.
String rewritePlaybackHls(
    String source, String Function(String uri, HlsResourceKind kind) register) {
  final lines = const LineSplitter().convert(source.replaceFirst('\uFEFF', ''));
  if (lines.isEmpty || lines.first.trim() != '#EXTM3U') {
    throw unsupportedRelayMedia;
  }
  final output = <String>['#EXTM3U'];
  var variant = false;
  var master = false;
  var media = false;
  var ended = false;
  var targetDuration = 0;
  var fullSegments = 0;
  var encrypted = false;
  var resources = 0;
  for (final raw in lines.skip(1)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (!line.startsWith('#')) {
      if (line.contains('{') || RegExp(r'[\x00-\x20\x7f]').hasMatch(line)) {
        throw unsupportedRelayMedia;
      }
      output.add(register(
          line,
          variant
              ? HlsResourceKind.playlist
              : encrypted
                  ? HlsResourceKind.encryptedSegment
                  : HlsResourceKind.segment));
      master |= variant;
      media |= !variant;
      if (!variant) fullSegments++;
      variant = false;
      resources++;
      continue;
    }
    if (!line.startsWith('#EXT')) continue;
    final colon = line.indexOf(':');
    final tag = colon < 0 ? line : line.substring(0, colon);
    final value = colon < 0 ? '' : line.substring(colon + 1);
    if (const {
      '#EXTINF',
      '#EXT-X-VERSION',
      '#EXT-X-TARGETDURATION',
      '#EXT-X-MEDIA-SEQUENCE',
      '#EXT-X-DISCONTINUITY-SEQUENCE',
      '#EXT-X-BYTERANGE',
      '#EXT-X-DISCONTINUITY',
      '#EXT-X-PROGRAM-DATE-TIME',
      '#EXT-X-PLAYLIST-TYPE',
      '#EXT-X-ENDLIST',
      '#EXT-X-INDEPENDENT-SEGMENTS',
      '#EXT-X-I-FRAMES-ONLY',
      '#EXT-X-GAP'
    }.contains(tag)) {
      ended |= tag == '#EXT-X-ENDLIST';
      if (tag == '#EXT-X-TARGETDURATION') {
        targetDuration = int.tryParse(value) ?? 0;
        if (targetDuration <= 0) throw unsupportedRelayMedia;
      }
      output.add(line);
      continue;
    }
    final allowed = _attributes[tag];
    if (allowed == null) throw unsupportedRelayMedia;
    final attrs = _parseAttributes(value);
    if (attrs.keys.any((key) => !allowed.contains(key))) {
      throw unsupportedRelayMedia;
    }
    // These LL extensions are advisory for a client using full segments.
    // SKIP is intentionally unsupported: a delta response is not complete.
    if (_lowLatencyTags.contains(tag)) continue;
    if (tag == '#EXT-X-KEY' || tag == '#EXT-X-SESSION-KEY') {
      final method = attrs['METHOD']?.value;
      if ((method != 'NONE' && method != 'AES-128') ||
          (attrs.containsKey('KEYFORMAT') &&
              attrs['KEYFORMAT']!.value != 'identity') ||
          (attrs.containsKey('KEYFORMATVERSIONS') &&
              attrs['KEYFORMATVERSIONS']!.value != '1') ||
          (method == 'AES-128' && !attrs.containsKey('URI'))) {
        throw unsupportedRelayMedia;
      }
      if (tag == '#EXT-X-KEY') encrypted = method == 'AES-128';
    }
    if (tag == '#EXT-X-STREAM-INF') {
      if (variant) throw unsupportedRelayMedia;
      variant = true;
    }
    if (tag == '#EXT-X-MEDIA' || tag == '#EXT-X-I-FRAME-STREAM-INF') {
      master = true;
    }
    final uri = attrs['URI'];
    if (uri != null) {
      if (!uri.quoted || uri.value.contains('{')) throw unsupportedRelayMedia;
      final kind = tag == '#EXT-X-KEY' || tag == '#EXT-X-SESSION-KEY'
          ? HlsResourceKind.key
          : tag == '#EXT-X-MAP'
              ? encrypted
                  ? HlsResourceKind.encryptedSegment
                  : HlsResourceKind.segment
              : HlsResourceKind.playlist;
      attrs['URI'] = _Attribute(register(uri.value, kind), true);
      resources++;
    } else if (tag == '#EXT-X-MAP' || tag == '#EXT-X-I-FRAME-STREAM-INF') {
      throw unsupportedRelayMedia;
    }
    output.add(
        '$tag:${attrs.entries.map((e) => '${e.key}=${e.value.quoted ? '"${e.value.value}"' : e.value.value}').join(',')}');
  }
  if (variant ||
      resources == 0 ||
      (master && media) ||
      (!master && (fullSegments == 0 || (!ended && targetDuration == 0)))) {
    throw unsupportedRelayMedia;
  }
  return '${output.join('\n')}\n';
}

const _attributes = <String, Set<String>>{
  '#EXT-X-SERVER-CONTROL': {
    'CAN-SKIP-UNTIL',
    'CAN-SKIP-DATERANGES',
    'HOLD-BACK',
    'PART-HOLD-BACK',
    'CAN-BLOCK-RELOAD'
  },
  '#EXT-X-PART-INF': {'PART-TARGET'},
  '#EXT-X-PART': {'URI', 'DURATION', 'INDEPENDENT', 'BYTERANGE', 'GAP'},
  '#EXT-X-PRELOAD-HINT': {'TYPE', 'URI', 'BYTERANGE-START', 'BYTERANGE-LENGTH'},
  '#EXT-X-RENDITION-REPORT': {'URI', 'LAST-MSN', 'LAST-PART'},
  '#EXT-X-STREAM-INF': {
    'BANDWIDTH',
    'AVERAGE-BANDWIDTH',
    'CODECS',
    'RESOLUTION',
    'FRAME-RATE',
    'HDCP-LEVEL',
    'AUDIO',
    'VIDEO',
    'SUBTITLES',
    'CLOSED-CAPTIONS'
  },
  '#EXT-X-I-FRAME-STREAM-INF': {
    'URI',
    'BANDWIDTH',
    'AVERAGE-BANDWIDTH',
    'CODECS',
    'RESOLUTION',
    'HDCP-LEVEL',
    'VIDEO'
  },
  '#EXT-X-MEDIA': {
    'TYPE',
    'URI',
    'GROUP-ID',
    'LANGUAGE',
    'ASSOC-LANGUAGE',
    'NAME',
    'DEFAULT',
    'AUTOSELECT',
    'FORCED',
    'INSTREAM-ID',
    'CHARACTERISTICS',
    'CHANNELS'
  },
  '#EXT-X-KEY': {'METHOD', 'URI', 'IV', 'KEYFORMAT', 'KEYFORMATVERSIONS'},
  '#EXT-X-SESSION-KEY': {
    'METHOD',
    'URI',
    'IV',
    'KEYFORMAT',
    'KEYFORMATVERSIONS'
  },
  '#EXT-X-MAP': {'URI', 'BYTERANGE'},
  '#EXT-X-START': {'TIME-OFFSET', 'PRECISE'},
};

const _lowLatencyTags = {
  '#EXT-X-SERVER-CONTROL',
  '#EXT-X-PART-INF',
  '#EXT-X-PART',
  '#EXT-X-PRELOAD-HINT',
  '#EXT-X-RENDITION-REPORT'
};

class _Attribute {
  const _Attribute(this.value, this.quoted);
  final String value;
  final bool quoted;
}

Map<String, _Attribute> _parseAttributes(String source) {
  final result = <String, _Attribute>{};
  var offset = 0;
  while (offset < source.length) {
    final match = RegExp(r'([A-Z0-9-]+)=').matchAsPrefix(source, offset);
    if (match == null || result.containsKey(match[1])) {
      throw unsupportedRelayMedia;
    }
    offset = match.end;
    final quoted = offset < source.length && source[offset] == '"';
    if (quoted) offset++;
    final start = offset;
    if (quoted) {
      offset = source.indexOf('"', start);
      if (offset < 0) throw unsupportedRelayMedia;
    } else {
      final comma = source.indexOf(',', start);
      offset = comma < 0 ? source.length : comma;
    }
    final value = source.substring(start, offset);
    if (value.isEmpty ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value) ||
        (!quoted && (value.contains('"') || value.contains(' ')))) {
      throw unsupportedRelayMedia;
    }
    result[match[1]!] = _Attribute(value, quoted);
    if (quoted) offset++;
    if (offset == source.length) break;
    if (source[offset] != ',' || ++offset == source.length) {
      throw unsupportedRelayMedia;
    }
  }
  if (result.isEmpty) throw unsupportedRelayMedia;
  return result;
}
