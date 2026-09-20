import 'package:xml/xml.dart';
import '../domain/live_models.dart';

const liveEpgMaxBytes = 32 * 1024 * 1024;
const liveEpgMaxEntries = 100000;

DateTime? parseXmltvTime(String value) {
  final m =
      RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*(Z|[+-]\d{4})?$')
          .firstMatch(value.trim());
  if (m == null) return null;
  final date = DateTime.utc(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
      int.parse(m[4]!),
      int.parse(m[5]!),
      int.parse(m[6] ?? '0'));
  if (date.month != int.parse(m[2]!) ||
      date.day != int.parse(m[3]!) ||
      int.parse(m[4]!) > 23 ||
      int.parse(m[5]!) > 59 ||
      int.parse(m[6] ?? '0') > 59) {
    return null;
  }
  final zone = m[7] ?? 'Z';
  if (zone == 'Z') return date;
  if (int.parse(zone.substring(1, 3)) > 23 ||
      int.parse(zone.substring(3)) > 59) {
    return null;
  }
  final offset =
      int.parse(zone.substring(1, 3)) * 60 + int.parse(zone.substring(3));
  return date.subtract(Duration(minutes: zone[0] == '-' ? -offset : offset));
}

class LiveEpg {
  const LiveEpg(this.programmes, this.logos);
  final List<LiveProgramme> programmes;
  final Map<String, String> logos;
}

LiveEpg parseLiveEpg(String text, {DateTime? now}) {
  if (text.length > liveEpgMaxBytes ||
      RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(text)) {
    throw const FormatException('节目单过大或包含不支持的 XML 声明');
  }
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(text);
  } catch (_) {
    // XML parser exceptions can contain subscription content and credentials.
    throw const FormatException('XMLTV 格式无效');
  }
  if (doc.rootElement.name.local != 'tv') {
    throw const FormatException('不是 XMLTV 节目单');
  }
  final time = now ?? DateTime.now();
  final min = time.subtract(const Duration(days: 1)),
      max = time.add(const Duration(days: 7));
  final programmes = <LiveProgramme>[];
  var entries = 0;
  for (final p in doc.rootElement.findElements('programme')) {
    if (++entries > liveEpgMaxEntries) {
      throw const FormatException('节目条目超过 100000');
    }
    final start = parseXmltvTime(p.getAttribute('start') ?? ''),
        end = parseXmltvTime(p.getAttribute('stop') ?? '');
    final channel = (p.getAttribute('channel') ?? '').trim();
    if (start == null ||
        end == null ||
        !end.isAfter(start) ||
        !end.isAfter(min) ||
        !start.isBefore(max) ||
        channel.isEmpty) {
      continue;
    }
    programmes.add(LiveProgramme(
        channel: channel,
        title: p.getElement('title')?.innerText ?? '',
        start: start,
        end: end,
        description: p.getElement('desc')?.innerText ?? ''));
  }
  programmes.sort((a, b) {
    final start = a.start.compareTo(b.start);
    return start != 0 ? start : a.channel.compareTo(b.channel);
  });
  final logos = <String, String>{};
  var channels = 0;
  for (final c in doc.rootElement.findElements('channel')) {
    if (++channels > liveEpgMaxEntries) {
      throw const FormatException('节目单频道超过 100000');
    }
    final id = (c.getAttribute('id') ?? '').trim();
    final logo = (c.getElement('icon')?.getAttribute('src') ?? '').trim();
    if (id.isNotEmpty && logo.isNotEmpty) logos[id] = logo;
  }
  return LiveEpg(programmes, logos);
}
