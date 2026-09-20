import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const maxImdbDatasetDownloadBytes = 32 * 1024 * 1024;
const _maxDecodedBytes = 128 * 1024 * 1024;
const _maxRows = 4000000;
const _maxLineBytes = 256;

/// Keeps TSV bytes plus four bytes per row instead of millions of Dart maps.
class ImdbRatingDataset {
  ImdbRatingDataset._(this._bytes, this._offsets);

  final Uint8List _bytes;
  final Uint32List _offsets;

  int get rowCount => _offsets.length;
  int get storageBytes => _bytes.length + _offsets.lengthInBytes;

  ({double averageRating, int voteCount})? lookup(String imdbId) {
    var low = 0;
    var high = _offsets.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      final offset = _offsets[middle];
      final comparison = _compareId(offset, imdbId);
      if (comparison < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == _offsets.length || _compareId(_offsets[low], imdbId) != 0) {
      return null;
    }
    final start = _offsets[low];
    var end = start;
    while (end < _bytes.length && _bytes[end] != 10) {
      end++;
    }
    final fields = utf8
        .decode(Uint8List.sublistView(_bytes, start, end), allowMalformed: true)
        .split('\t');
    if (fields.length < 3) return null;
    final rating = double.tryParse(fields[1].trim());
    final votes = int.tryParse(fields[2].trim());
    if (rating == null || !rating.isFinite || votes == null) return null;
    return (averageRating: rating, voteCount: votes);
  }

  int _compareId(int offset, String id) {
    var index = 0;
    while (offset + index < _bytes.length) {
      final byte = _bytes[offset + index];
      if (byte == 9 || byte == 10 || byte == 13) break;
      if (index == id.length) return 1;
      final difference = byte - id.codeUnitAt(index);
      if (difference != 0) return difference;
      index++;
    }
    return index == id.length ? 0 : -1;
  }
}

ImdbRatingDataset decodeImdbRatingDataset(Uint8List compressed) {
  if (compressed.length > maxImdbDatasetDownloadBytes) {
    throw const FormatException('IMDb dataset exceeds download limit');
  }
  if (compressed.length < 18 ||
      compressed[0] != 0x1f ||
      compressed[1] != 0x8b) {
    throw const FormatException('Invalid IMDb gzip header');
  }
  final output = _BoundedDatasetOutput();
  // The archive IO decoder accumulates chunks before forwarding them. Its
  // streaming Dart decoder lets the output limit stop expansion immediately.
  const GZipDecoderWeb().decodeStream(InputMemoryStream(compressed), output);
  final bytes = Uint8List.fromList(output.getBytes());
  final footer = ByteData.sublistView(compressed, compressed.length - 8);
  if (footer.getUint32(0, Endian.little) != getCrc32(bytes) ||
      footer.getUint32(4, Endian.little) != bytes.length) {
    throw const FormatException('Invalid IMDb gzip checksum or size');
  }
  var headerEnd = bytes.indexOf(10);
  if (headerEnd < 0) headerEnd = bytes.length;
  if (utf8.decode(Uint8List.sublistView(bytes, 0, headerEnd)).trim() !=
      'tconst\taverageRating\tnumVotes') {
    throw const FormatException('Invalid IMDb ratings header');
  }
  var rowCount = 0;
  var start = headerEnd + 1;
  for (var index = start; index <= bytes.length; index++) {
    if (index - start > _maxLineBytes) {
      throw const FormatException('IMDb rating row exceeds length limit');
    }
    if (index == bytes.length || bytes[index] == 10) {
      if (index > start && bytes[start] != 13) rowCount++;
      if (rowCount > _maxRows) {
        throw const FormatException('IMDb dataset exceeds row limit');
      }
      start = index + 1;
    }
  }
  final offsets = Uint32List(rowCount);
  var row = 0;
  start = headerEnd + 1;
  for (var index = start; index <= bytes.length; index++) {
    if (index == bytes.length || bytes[index] == 10) {
      if (index > start && bytes[start] != 13) offsets[row++] = start;
      start = index + 1;
    }
  }
  int compareOffsets(int left, int right) {
    while (true) {
      int keyByte(int offset) {
        if (offset >= bytes.length) return 0;
        final byte = bytes[offset];
        return byte == 9 || byte == 10 || byte == 13 ? 0 : byte;
      }

      final a = keyByte(left++);
      final b = keyByte(right++);
      if (a != b) return a - b;
      if (a == 0) return 0;
    }
  }

  // IMDb normally supplies sorted IDs; tolerate an unsorted snapshot as well.
  for (var index = 1; index < offsets.length; index++) {
    if (compareOffsets(offsets[index - 1], offsets[index]) > 0) {
      offsets.sort(compareOffsets);
      break;
    }
  }
  return ImdbRatingDataset._(bytes, offsets);
}

class _BoundedDatasetOutput extends OutputMemoryStream {
  void _check(int count) {
    if (length + count > _maxDecodedBytes) {
      throw const FormatException('IMDb dataset exceeds decompression limit');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }
}
