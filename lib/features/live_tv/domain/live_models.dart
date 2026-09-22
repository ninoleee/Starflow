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

class LiveGroupPreference {
  const LiveGroupPreference({this.hidden = false, this.order = -1});

  final bool hidden;
  final int order;

  Map<String, dynamic> toJson() => {'hidden': hidden, 'order': order};

  factory LiveGroupPreference.fromJson(Map<String, dynamic> json) {
    final rawOrder = json['order'];
    if (rawOrder != null && rawOrder is! int) {
      throw const FormatException('直播分组排序无效');
    }
    return LiveGroupPreference(
        hidden: json['hidden'] == true, order: rawOrder as int? ?? -1);
  }

  LiveGroupPreference patch(Map<String, dynamic> values) =>
      LiveGroupPreference.fromJson({...toJson(), ...values});
}

String encodeLiveGroupPreferences(
        Map<String, LiveGroupPreference> preferences) =>
    jsonEncode({
      for (final entry in preferences.entries) entry.key: entry.value.toJson()
    });

Map<String, LiveGroupPreference> parseLiveGroupPreferences(String? encoded) {
  if (encoded == null || encoded.isEmpty) return {};
  final decoded = jsonDecode(encoded);
  if (decoded is! Map) throw const FormatException('直播分组偏好无效');
  final result = <String, LiveGroupPreference>{};
  for (final entry in decoded.entries) {
    if (entry.key is! String ||
        (entry.key as String).isEmpty ||
        entry.value is! Map) {
      throw const FormatException('直播分组偏好无效');
    }
    final preference = LiveGroupPreference.fromJson(
        Map<String, dynamic>.from(entry.value as Map));
    if (preference.order < -1) {
      throw const FormatException('直播分组排序无效');
    }
    result[entry.key as String] = preference;
  }
  return result;
}

Map<String, LiveGroupPreference> decodeLiveGroupPreferences(String? encoded) {
  try {
    return parseLiveGroupPreferences(encoded);
  } catch (_) {
    return {};
  }
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
      this.groupPreferences = const {},
      this.lastChannel = '',
      this.engine = 'mpv'});
  final List<LiveSource> sources;
  final List<LiveChannel> channels;
  final Map<String, LivePreference> preferences;
  final Map<String, LiveGroupPreference> groupPreferences;
  final String lastChannel, engine;
  LivePreference preference(LiveChannel c) =>
      preferences[c.id] ?? const LivePreference();
  LiveGroupPreference groupPreference(String group) =>
      groupPreferences[group] ?? const LiveGroupPreference();
  bool groupHidden(String group) => groupPreference(group).hidden;
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
            (includeHidden ||
                (!preference(c).hidden && !groupHidden(group(c)))))
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

  List<String> groups({bool includeHidden = false}) {
    final enabled = sources.where((s) => s.enabled).map((s) => s.id).toSet();
    final result = <String>{};
    for (final channel in channels) {
      if (!enabled.contains(channel.sourceId) || channel.lines.isEmpty) {
        continue;
      }
      final groupName = group(channel);
      if (groupName.isEmpty ||
          (!includeHidden &&
              (preference(channel).hidden || groupHidden(groupName)))) {
        continue;
      }
      result.add(groupName);
    }
    final groups = result.toList();
    groups.sort((a, b) {
      final aPreference = groupPreference(a);
      final bPreference = groupPreference(b);
      final aOrdered = aPreference.order >= 0;
      final bOrdered = bPreference.order >= 0;
      if (aOrdered != bOrdered) return aOrdered ? -1 : 1;
      final order = aPreference.order.compareTo(bPreference.order);
      return order != 0 ? order : a.compareTo(b);
    });
    return groups;
  }
}
