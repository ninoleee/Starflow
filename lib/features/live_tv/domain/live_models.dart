import 'dart:convert';
import 'package:crypto/crypto.dart';

String liveId(String value) => sha256.convert(utf8.encode(value)).toString();

class LiveSource {
  const LiveSource(
      {required this.id,
      required this.name,
      this.url = '',
      this.epgUrl = '',
      this.discoveredEpgUrl = '',
      this.enabled = true,
      this.refreshHours = 24,
      this.updatedAt = 0,
      this.epgUpdatedAt = 0});
  final String id, name, url, epgUrl, discoveredEpgUrl;
  String get effectiveEpgUrl => epgUrl.isEmpty ? discoveredEpgUrl : epgUrl;
  final bool enabled;
  final int refreshHours, updatedAt, epgUpdatedAt;
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'epgUrl': epgUrl,
        'discoveredEpgUrl': discoveredEpgUrl,
        'enabled': enabled,
        'refreshHours': refreshHours,
        'updatedAt': updatedAt,
        'epgUpdatedAt': epgUpdatedAt
      };
  factory LiveSource.fromJson(Map<String, dynamic> j) => LiveSource(
      id: j['id'] as String,
      name: j['name'] as String,
      url: j['url'] as String? ?? '',
      epgUrl: j['epgUrl'] as String? ?? '',
      discoveredEpgUrl: j['discoveredEpgUrl'] as String? ?? '',
      enabled: j['enabled'] != false,
      refreshHours: (j['refreshHours'] as int? ?? 24).clamp(1, 168),
      updatedAt: j['updatedAt'] as int? ?? 0,
      epgUpdatedAt: j['epgUpdatedAt'] as int? ?? 0);
}

class LiveLine {
  const LiveLine(this.url, {this.headers = const {}});
  final String url;
  final Map<String, String> headers;
  Map<String, dynamic> toJson() => {'url': url, 'headers': headers};
  factory LiveLine.fromJson(Map<String, dynamic> j) =>
      LiveLine(j['url'] as String,
          headers: Map<String, String>.from(j['headers'] as Map? ?? {}));
}

class LiveChannel {
  const LiveChannel(
      {required this.id,
      required this.sourceId,
      required this.name,
      required this.lines,
      this.group = '',
      this.logo = '',
      this.identity = '',
      this.epgId = ''});
  final String id, sourceId, name, group, logo, epgId, identity;
  final List<LiveLine> lines;
  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceId': sourceId,
        'name': name,
        'group': group,
        'logo': logo,
        'epgId': epgId,
        'identity': identity,
        'lines': lines.map((l) => l.toJson()).toList()
      };
  factory LiveChannel.fromJson(Map<String, dynamic> j) => LiveChannel(
      id: j['id'] as String,
      sourceId: j['sourceId'] as String,
      name: j['name'] as String,
      group: j['group'] as String? ?? '',
      logo: j['logo'] as String? ?? '',
      epgId: j['epgId'] as String? ?? '',
      identity: j['identity'] as String? ?? '',
      lines: (j['lines'] as List)
          .map((l) => LiveLine.fromJson(Map<String, dynamic>.from(l as Map)))
          .toList());
}

class LivePreference {
  const LivePreference(
      {this.favorite = false,
      this.hidden = false,
      this.order = -1,
      this.name = '',
      this.group = '',
      this.logo = '',
      this.epgId = '',
      this.line = 0});
  final bool favorite, hidden;
  final int order, line;
  final String name, group, logo, epgId;
  Map<String, dynamic> toJson() => {
        'favorite': favorite,
        'hidden': hidden,
        'order': order,
        'name': name,
        'group': group,
        'logo': logo,
        'epgId': epgId,
        'line': line
      };
  factory LivePreference.fromJson(Map<String, dynamic> j) => LivePreference(
      favorite: j['favorite'] == true,
      hidden: j['hidden'] == true,
      order: j['order'] as int? ?? -1,
      line: j['line'] as int? ?? 0,
      name: j['name'] as String? ?? '',
      group: j['group'] as String? ?? '',
      logo: j['logo'] as String? ?? '',
      epgId: j['epgId'] as String? ?? '');
  LivePreference patch(Map<String, dynamic> values) =>
      LivePreference.fromJson({...toJson(), ...values});
}

class LiveProgramme {
  const LiveProgramme(
      {required this.channel,
      required this.title,
      required this.start,
      required this.end,
      this.description = ''});
  final String channel, title, description;
  final DateTime start, end;
  bool contains(DateTime time) => !time.isBefore(start) && time.isBefore(end);
  Map<String, dynamic> toJson() => {
        'channel': channel,
        'title': title,
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'description': description
      };
  factory LiveProgramme.fromJson(Map<String, dynamic> j) => LiveProgramme(
      channel: j['channel'] as String,
      title: j['title'] as String,
      start:
          DateTime.fromMillisecondsSinceEpoch(j['start'] as int, isUtc: true),
      end: DateTime.fromMillisecondsSinceEpoch(j['end'] as int, isUtc: true),
      description: j['description'] as String? ?? '');
}

class LiveSnapshot {
  const LiveSnapshot(
      {this.sources = const [],
      this.channels = const [],
      this.preferences = const {},
      this.lastChannel = '',
      this.engine = 'mpv'});
  final List<LiveSource> sources;
  final List<LiveChannel> channels;
  final Map<String, LivePreference> preferences;
  final String lastChannel, engine;
  LivePreference preference(LiveChannel c) =>
      preferences[c.id] ?? const LivePreference();
  String name(LiveChannel c) =>
      preference(c).name.isEmpty ? c.name : preference(c).name;
  String group(LiveChannel c) =>
      preference(c).group.isEmpty ? c.group : preference(c).group;
  String logo(LiveChannel c) =>
      preference(c).logo.isEmpty ? c.logo : preference(c).logo;
  String epgId(LiveChannel c) =>
      preference(c).epgId.isEmpty ? c.epgId : preference(c).epgId;
  List<LiveChannel> visible({bool includeHidden = false}) {
    final indices = {
      for (var i = 0; i < channels.length; i++) channels[i].id: i
    };
    final enabled = sources.where((s) => s.enabled).map((s) => s.id).toSet();
    final result = channels
        .where((c) =>
            enabled.contains(c.sourceId) &&
            c.lines.isNotEmpty &&
            (includeHidden || !preference(c).hidden))
        .toList();
    result.sort((a, b) {
      final aOrdered = preference(a).order >= 0;
      final bOrdered = preference(b).order >= 0;
      if (aOrdered != bOrdered) return aOrdered ? -1 : 1;
      final order = preference(a).order.compareTo(preference(b).order);
      return order != 0 ? order : indices[a.id]!.compareTo(indices[b.id]!);
    });
    return result;
  }
}
