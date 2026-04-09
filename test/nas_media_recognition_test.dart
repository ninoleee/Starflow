import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/nas_media_recognition.dart';

void main() {
  test('NasMediaRecognizer skips wrapper folders when inferring series title',
      () {
    final result = NasMediaRecognizer.recognize(
      '繁城之下/会员版/Episode 01.mkv',
    );

    expect(result.itemType, 'episode');
    expect(result.episodeNumber, 1);
    expect(result.parentTitle, '繁城之下');
    expect(result.title, '繁城之下');
  });

  test('NasMediaRecognizer recognizes variety issue labels as episodes', () {
    final result = NasMediaRecognizer.recognize(
      '食贫道/第12期 会员版.mp4',
    );

    expect(result.itemType, 'episode');
    expect(result.episodeNumber, 12);
    expect(result.parentTitle, '食贫道');
    expect(result.title, '食贫道');
  });

  test(
      'NasMediaRecognizer keeps leading episode cues when remainder is only a version label',
      () {
    final result = NasMediaRecognizer.recognize(
      '奔跑吧/01 会员版 1080p.mkv',
    );

    expect(result.itemType, 'episode');
    expect(result.episodeNumber, 1);
    expect(result.parentTitle, '奔跑吧');
    expect(result.title, '奔跑吧');
  });

  test('NasMediaRecognizer stops upward series inference at filtered folders',
      () {
    final result = NasMediaRecognizer.recognize(
      '怪奇物语/Stranger.Things.S04.2160p.NF.WEB-DL.x265.10bit.HDR/Stranger.Things.S04E01.2160p.NF.WEB-DL.x265.10bit.HDR.strm',
      seriesTitleFilterKeywords: const ['2160p'],
    );

    expect(result.itemType, 'episode');
    expect(result.parentTitle, 'Stranger Things');
    expect(result.title, 'Stranger Things');
  });
}
