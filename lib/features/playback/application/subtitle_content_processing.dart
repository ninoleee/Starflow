import 'package:flutter/foundation.dart';
import 'package:starflow/features/playback/application/subtitle_content_decoder.dart';

Future<String> processSubtitleContent(List<int> bytes,
        {String preferredName = ''}) =>
    compute(_process, (bytes: bytes, preferredName: preferredName));

String _process(({List<int> bytes, String preferredName}) input) {
  final text = decodeSubtitleBytes(isSubtitleZipBytes(input.bytes)
      ? extractSubtitleBytesFromZip(input.bytes,
          preferredName: input.preferredName)
      : input.bytes);
  detectSubtitleFormat(text);
  return text;
}
