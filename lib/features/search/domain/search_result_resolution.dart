import 'package:starflow/features/search/domain/search_models.dart';

enum SearchResultResolution {
  ultra8k('8K'),
  ultra4k('4K'),
  qhd('2K'),
  fullHd('1080P'),
  hd('720P'),
  sd('标清'),
  unknown('未标注');

  const SearchResultResolution(this.label);

  final String label;
}

final _resolutionPatterns = <SearchResultResolution, RegExp>{
  SearchResultResolution.ultra8k: _resolutionPattern(r'8\s*k|4320\s*p'),
  SearchResultResolution.ultra4k:
      _resolutionPattern(r'4\s*k|2160\s*p|uhd|ultra[ ._-]*hd'),
  SearchResultResolution.qhd: _resolutionPattern(r'2\s*k|1440\s*p|qhd'),
  SearchResultResolution.fullHd:
      _resolutionPattern(r'1080\s*[pi]|fhd|full[ ._-]*hd'),
  SearchResultResolution.hd: _resolutionPattern(r'720\s*p'),
  SearchResultResolution.sd: _resolutionPattern(r'(?:480|576)\s*[pi]|sd'),
};

RegExp _resolutionPattern(String pattern) => RegExp(
      '(?<![a-z0-9])(?:$pattern)(?![a-z0-9])',
      caseSensitive: false,
    );

final _resolutionUrlPattern =
    RegExp(r'(?:https?://|magnet:|ed2k://)\S+', caseSensitive: false);

/// Labels describe advertised resolutions, not probed video properties.
/// A collection can explicitly advertise several resolutions.
Set<SearchResultResolution> searchResultResolutions(SearchResult result) {
  Set<SearchResultResolution> parse(String text) {
    final withoutUrls = text.replaceAll(_resolutionUrlPattern, ' ');
    return {
      for (final entry in _resolutionPatterns.entries)
        if (entry.value.hasMatch(withoutUrls)) entry.key,
    };
  }

  final primary = parse('${result.title}\n${result.quality}');
  if (primary.isNotEmpty) return primary;

  // Providers prepend channel and publication metadata to the description.
  var summary = result.summary;
  for (final metadata in [result.source, result.publishedAt]) {
    if (metadata.trim().isNotEmpty) {
      summary = summary.replaceAll(metadata, ' ');
    }
  }
  final fallback = parse(summary);
  return fallback.isEmpty ? {SearchResultResolution.unknown} : fallback;
}
