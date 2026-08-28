import 'dart:ui';

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

  test('configured language is preferred over system locale', () {
    expect(
      scorePreferredSubtitleText(
        'English',
        configuredLanguages: const ['en'],
        systemLocale: const Locale('zh', 'CN'),
      ),
      greaterThan(0),
    );
    expect(
      scorePreferredSubtitleText(
        '简体中文',
        configuredLanguages: const ['en'],
        systemLocale: const Locale('zh', 'CN'),
      ),
      0,
    );
  });

  test('automatic subtitle priority is language then forced then default', () {
    const preferred = AutomaticSubtitleCandidate<String>(
      value: 'preferred',
      searchableText: 'English',
    );
    const forced = AutomaticSubtitleCandidate<String>(
      value: 'forced',
      searchableText: 'Japanese',
      isForced: true,
    );
    const defaultTrack = AutomaticSubtitleCandidate<String>(
      value: 'default',
      searchableText: 'French',
      isDefault: true,
    );

    expect(
      selectAutomaticSubtitleTrack(
        const [defaultTrack, forced, preferred],
        configuredLanguages: const ['en'],
      ),
      'preferred',
    );
    expect(
      selectAutomaticSubtitleTrack(
        const [defaultTrack, forced],
        configuredLanguages: const ['en'],
      ),
      'forced',
    );
    expect(
      selectAutomaticSubtitleTrack(
        const [defaultTrack],
        configuredLanguages: const ['en'],
      ),
      'default',
    );
  });

  test('detects forced subtitle labels', () {
    expect(isForcedSubtitleText('English Forced'), isTrue);
    expect(isForcedSubtitleText('中文强制字幕'), isTrue);
    expect(isForcedSubtitleText('English SDH'), isFalse);
  });
}
