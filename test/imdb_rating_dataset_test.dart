import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/metadata/data/imdb_rating_dataset.dart';

Uint8List _zip(String value) => GZipEncoder().encodeBytes(utf8.encode(value));
const _header = 'tconst\taverageRating\tnumVotes\n';

void main() {
  test('indexes unsorted variable-length IDs and parses only matched rows', () {
    final text = '${_header}tt20000000\t8.2\t100\n'
        'tt0000002\t6.1\t20\r\n\n'
        'tt1000000\t7.5\t300\n'
        'tt10000000\t9.0\t400';
    final dataset = decodeImdbRatingDataset(_zip(text));
    expect(dataset.rowCount, 4);
    expect(dataset.storageBytes, utf8.encode(text).length + 4 * 4);
    expect(dataset.lookup('tt0000002'), (averageRating: 6.1, voteCount: 20));
    expect(dataset.lookup('tt1000000'), (averageRating: 7.5, voteCount: 300));
    expect(dataset.lookup('tt10000000'), (averageRating: 9.0, voteCount: 400));
    expect(dataset.lookup('tt20000000'), (averageRating: 8.2, voteCount: 100));
    expect(dataset.lookup('tt100000'), isNull);
    expect(dataset.lookup('tt99999999'), isNull);
  });

  test('empty dataset and invalid rating fields do not create ratings', () {
    expect(decodeImdbRatingDataset(_zip(_header)).lookup('tt1'), isNull);
    final dataset = decodeImdbRatingDataset(_zip('${_header}tt1\tbad\t2\n'
        'tt2\t8.0\tbad\ntt3\tNaN\t20\ntt4\t8.0'));
    for (final id in ['tt1', 'tt2', 'tt3', 'tt4']) {
      expect(dataset.lookup(id), isNull);
    }
  });

  test('rejects invalid headers, corrupt gzip and oversized lines', () {
    expect(() => decodeImdbRatingDataset(_zip('html error')),
        throwsFormatException);
    final corrupt = _zip('${_header}tt1\t8.0\t20\n');
    corrupt[corrupt.length - 8] ^= 1;
    expect(() => decodeImdbRatingDataset(corrupt), throwsFormatException);
    expect(() => decodeImdbRatingDataset(Uint8List(4)), throwsFormatException);
    expect(() => decodeImdbRatingDataset(_zip('$_header${'a' * 257}')),
        throwsFormatException);
  });

  test('large dataset retains bytes and offsets instead of per-row objects',
      () {
    final text = StringBuffer(_header);
    for (var index = 9999; index >= 0; index--) {
      text.writeln('tt${index.toString().padLeft(7, '0')}\t8.0\t$index');
    }
    final source = text.toString();
    final dataset = decodeImdbRatingDataset(_zip(source));
    expect(dataset.rowCount, 10000);
    expect(dataset.storageBytes, utf8.encode(source).length + 40000);
    for (var index = 0; index < 10000; index += 37) {
      expect(dataset.lookup('tt${index.toString().padLeft(7, '0')}')?.voteCount,
          index);
    }
  });
}
