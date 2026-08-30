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
      ['zh-cn', 'en'],
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

  test('missing configured language falls back to system language', () {
    const english = AutomaticSubtitleCandidate<String>(
      value: 'english',
      searchableText: 'English',
    );
    const japanese = AutomaticSubtitleCandidate<String>(
      value: 'japanese',
      searchableText: '日本語',
    );

    expect(
      selectSubtitleTrackWithSystemFallback(
        const [english, japanese],
        preferredLanguages: const ['ko'],
        systemLocale: const Locale('ja', 'JP'),
      ),
      'japanese',
    );
  });

  test('forced and default tracks remain the final fallback', () {
    const forced = AutomaticSubtitleCandidate<String>(
      value: 'forced',
      searchableText: 'French Forced',
      isForced: true,
    );
    expect(
      selectSubtitleTrackWithSystemFallback(
        const [forced],
        preferredLanguages: const ['ko'],
        systemLocale: const Locale('ja', 'JP'),
      ),
      'forced',
    );
  });

  test('recognizes common language codes and title abbreviations', () {
    for (final text in const [
      'zh-Hans',
      'chs',
      'chn',
      'cn',
      'sc',
      'chi',
      'zho',
      '简中'
    ]) {
      expect(
        scorePreferredSubtitleText(
          text,
          configuredLanguages: const ['zh-cn'],
        ),
        greaterThan(0),
        reason: text,
      );
    }
    for (final text in const ['zh-Hant', 'cht', 'tc', 'big5', '繁中']) {
      expect(
        scorePreferredSubtitleText(
          text,
          configuredLanguages: const ['zh-tw'],
        ),
        greaterThan(0),
        reason: text,
      );
    }
    for (final text in const ['eng', 'English', '英字']) {
      expect(
        scorePreferredSubtitleText(
          text,
          configuredLanguages: const ['en'],
        ),
        greaterThan(0),
        reason: text,
      );
    }
    for (final text in const ['jp', 'jpn', 'Japanese', '日字']) {
      expect(
        scorePreferredSubtitleText(
          text,
          configuredLanguages: const ['ja'],
        ),
        greaterThan(0),
        reason: text,
      );
    }
  });
}
