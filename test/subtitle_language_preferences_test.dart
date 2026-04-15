import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/subtitle_language_preferences.dart';

void main() {
  test('formats subtitle preferred language labels with common names', () {
    expect(formatSubtitlePreferredLanguageLabel('zh-cn'), '简体中文');
    expect(formatSubtitlePreferredLanguageLabel('english'), '英语');
    expect(formatSubtitlePreferredLanguageLabel('ja'), '日语');
  });

  test('orders common subtitle preferred languages with canonical values', () {
    expect(
      orderCommonSubtitlePreferredLanguages(['english', 'zh-CN', 'ko', 'xx']),
      ['zh-cn', 'en', 'ko'],
    );
  });

  test('formats subtitle preferred language summary with display labels', () {
    expect(
      formatSubtitlePreferredLanguageSummary(['zh-cn', 'en']),
      '简体中文 / 英语',
    );
    expect(formatSubtitlePreferredLanguageSummary(const <String>[]), '未限制');
  });
}
