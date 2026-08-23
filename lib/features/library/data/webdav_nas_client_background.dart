part of 'webdav_nas_client.dart';

const int _webDavXmlBackgroundThreshold = 32 * 1024;

Future<List<_WebDavEntry>> _parseWebDavXmlInBackground({
  required String body,
  required Uri requestUri,
  required String fallbackName,
  required bool useBackgroundIsolate,
}) async {
  final requestUriText = requestUri.toString();
  final parsed = useBackgroundIsolate
      ? await Isolate.run(
          () => _parseWebDavXmlPayload(
            body: body,
            requestUriText: requestUriText,
            fallbackName: fallbackName,
          ),
          debugName: 'starflow-webdav-xml',
        )
      : _parseWebDavXmlPayload(
          body: body,
          requestUriText: requestUriText,
          fallbackName: fallbackName,
        );

  return parsed
      .map(
        (entry) => _WebDavEntry(
          uri: Uri.parse(entry['uri']! as String),
          name: entry['name']! as String,
          isCollection: entry['isCollection']! as bool,
          contentType: entry['contentType']! as String,
          sizeBytes: entry['sizeBytes']! as int,
          modifiedAt: (entry['modifiedAt'] as String?)?.isNotEmpty == true
              ? DateTime.tryParse(entry['modifiedAt']! as String)
              : null,
          isSelf: entry['isSelf']! as bool,
        ),
      )
      .toList(growable: false);
}

Future<List<_PendingWebDavScannedItem>> _applyStructureInferenceInBackground(
  List<_PendingWebDavScannedItem> items, {
  required MediaSourceConfig source,
}) {
  if (kIsWeb || items.length < 32) {
    return Future<List<_PendingWebDavScannedItem>>.value(
      applyExternalDirectoryStructureInference(items, source: source),
    );
  }
  return Isolate.run(
    () => applyExternalDirectoryStructureInference(items, source: source),
    debugName: 'starflow-webdav-structure',
  );
}

List<Map<String, Object?>> _parseWebDavXmlPayload({
  required String body,
  required String requestUriText,
  required String fallbackName,
}) {
  final requestUri = Uri.parse(requestUriText);
  final document = XmlDocument.parse(body);
  final responses = document.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'response');
  final normalizedSelf = _normalizeParsedWebDavUri(requestUri);

  return responses.map((node) {
    final href = _parsedWebDavChildText(node, 'href');
    final resolvedUri = _resolveParsedWebDavHref(requestUri, href);
    final prop = node.descendants.whereType<XmlElement>().firstWhere(
          (element) => element.name.local == 'prop',
          orElse: () => XmlElement(XmlName('prop')),
        );
    final isCollection = prop.descendants
        .whereType<XmlElement>()
        .any((element) => element.name.local == 'collection');
    final displayName = _parsedWebDavChildText(prop, 'displayname');
    final modifiedAt = _parseWebDavModifiedAt(
      _parsedWebDavChildText(prop, 'getlastmodified'),
    );

    return <String, Object?>{
      'uri': resolvedUri.toString(),
      'name': displayName.trim().isEmpty
          ? _parsedWebDavDisplayName(resolvedUri, fallback: fallbackName)
          : displayName.trim(),
      'isCollection': isCollection,
      'contentType': _parsedWebDavChildText(prop, 'getcontenttype').trim(),
      'sizeBytes': int.tryParse(
            _parsedWebDavChildText(prop, 'getcontentlength').trim(),
          ) ??
          0,
      'modifiedAt': modifiedAt?.toIso8601String() ?? '',
      'isSelf': _normalizeParsedWebDavUri(resolvedUri) == normalizedSelf,
    };
  }).toList(growable: false);
}

Uri _resolveParsedWebDavHref(Uri requestUri, String href) {
  final trimmed = href.trim();
  if (trimmed.isEmpty) {
    return requestUri;
  }
  final normalized = _escapeInvalidParsedWebDavHref(
    trimmed.replaceAll('#', '%23'),
  );
  final parsed = Uri.tryParse(normalized);
  if (parsed != null && parsed.hasScheme) {
    return parsed;
  }
  return requestUri.resolve(normalized);
}

String _escapeInvalidParsedWebDavHref(String value) {
  final buffer = StringBuffer();
  for (var index = 0; index < value.length; index++) {
    final character = value[index];
    if (character != '%') {
      buffer.write(character);
      continue;
    }
    final hasValidEscape = index + 2 < value.length &&
        _isParsedWebDavHexDigit(value.codeUnitAt(index + 1)) &&
        _isParsedWebDavHexDigit(value.codeUnitAt(index + 2));
    buffer.write(hasValidEscape ? '%' : '%25');
  }
  return buffer.toString();
}

bool _isParsedWebDavHexDigit(int codeUnit) {
  return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x46) ||
      (codeUnit >= 0x61 && codeUnit <= 0x66);
}

String _parsedWebDavChildText(XmlElement node, String localName) {
  final match = node.children.whereType<XmlElement>().firstWhere(
        (element) => element.name.local == localName,
        orElse: () => XmlElement(XmlName(localName)),
      );
  return match.innerText.trim();
}

String _parsedWebDavDisplayName(Uri uri, {required String fallback}) {
  final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
  if (segments.isEmpty) {
    return fallback;
  }
  final raw = segments.last;
  try {
    return Uri.decodeComponent(raw);
  } catch (_) {
    return raw;
  }
}

String _normalizeParsedWebDavUri(Uri uri) {
  final path = uri.path.endsWith('/') && uri.path.length > 1
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  return uri.replace(path: path, query: null, fragment: null).toString();
}

DateTime? _parseWebDavModifiedAt(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  final iso = DateTime.tryParse(text);
  if (iso != null) {
    return iso;
  }
  final match = RegExp(
    r'^[A-Za-z]{3},\s+(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+'
    r'(\d{2}):(\d{2}):(\d{2})\s+GMT$',
  ).firstMatch(text);
  if (match == null) {
    return null;
  }
  final month = _parsedWebDavMonthIndex(match.group(2)!);
  if (month == null) {
    return null;
  }
  return DateTime.utc(
    int.parse(match.group(3)!),
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}

int? _parsedWebDavMonthIndex(String value) {
  const months = <String, int>{
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };
  return months[value.toLowerCase()];
}
