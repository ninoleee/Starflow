import 'package:starflow/features/discovery/domain/douban_models.dart';

enum DoubanBrowseSort { comprehensive, trending, release, rating }

enum DoubanBrowseCategory { movie, series, variety }

extension DoubanBrowseCategoryX on DoubanBrowseCategory {
  String get value => name;
  String get label => switch (this) {
        DoubanBrowseCategory.movie => '电影',
        DoubanBrowseCategory.series => '电视剧',
        DoubanBrowseCategory.variety => '综艺',
      };
  DoubanSuggestionMediaType get mediaType => this == DoubanBrowseCategory.movie
      ? DoubanSuggestionMediaType.movie
      : DoubanSuggestionMediaType.tv;
  String get tvTag => switch (this) {
        DoubanBrowseCategory.movie => '',
        DoubanBrowseCategory.series => '电视剧',
        DoubanBrowseCategory.variety => '综艺',
      };
}

extension DoubanBrowseSortX on DoubanBrowseSort {
  String get code => switch (this) {
        DoubanBrowseSort.comprehensive => 'T',
        DoubanBrowseSort.trending => 'U',
        DoubanBrowseSort.release => 'R',
        DoubanBrowseSort.rating => 'S',
      };

  String get label => switch (this) {
        DoubanBrowseSort.comprehensive => '综合排序',
        DoubanBrowseSort.trending => '近期热度',
        DoubanBrowseSort.release => '首映时间',
        DoubanBrowseSort.rating => '高分优先',
      };

  String labelFor(DoubanSuggestionMediaType type) =>
      this == DoubanBrowseSort.release && type == DoubanSuggestionMediaType.tv
          ? '首播时间'
          : label;
}

List<int> doubanBrowseYearOptions({int? selectedYear, int? currentYear}) {
  final latest = currentYear ?? DateTime.now().year;
  final years = <int>[
    for (var year = latest; year > 2020; year--) year,
    for (var year = 2020; year >= 2000; year -= 5) year,
    for (var year = 1990; year >= 1890; year -= 10) year,
  ];
  if (selectedYear != null &&
      selectedYear >= 1888 &&
      selectedYear <= latest &&
      !years.contains(selectedYear)) {
    years.add(selectedYear);
    years.sort((a, b) => b.compareTo(a));
  }
  return years;
}

class DoubanBrowseQuery {
  const DoubanBrowseQuery({
    this.category = DoubanBrowseCategory.movie,
    this.year,
    this.region = '',
    this.genre = '',
    this.minRating = 0,
    this.minRatingCount = 0,
    this.sort = DoubanBrowseSort.rating,
  });

  final DoubanBrowseCategory category;
  DoubanSuggestionMediaType get mediaType => category.mediaType;
  final int? year;
  final String region;
  final String genre;
  final int minRating;
  final int minRatingCount;
  final DoubanBrowseSort sort;

  DoubanBrowseQuery copyWith({
    DoubanBrowseCategory? category,
    int? year,
    bool clearYear = false,
    String? region,
    String? genre,
    int? minRating,
    int? minRatingCount,
    DoubanBrowseSort? sort,
  }) =>
      DoubanBrowseQuery(
        category: category ?? this.category,
        year: clearYear ? null : year ?? this.year,
        region: region ?? this.region,
        genre: genre ?? this.genre,
        minRating: minRating ?? this.minRating,
        minRatingCount: minRatingCount ?? this.minRatingCount,
        sort: sort ?? this.sort,
      );

  void validate() {
    if (year != null && (year! < 1888 || year! > DateTime.now().year)) {
      throw const FormatException('无效年份');
    }
    if (minRating != 0 && (minRating < 6 || minRating > 9)) {
      throw const FormatException('无效评分范围');
    }
    if (minRatingCount != 0 &&
        !const [5000, 10000, 30000, 60000, 100000].contains(minRatingCount)) {
      throw const FormatException('无效评分人数范围');
    }
  }

  String get cacheKey =>
      '${category.value}|${year ?? ''}|$region|$genre|$minRating|$minRatingCount|${sort.code}';

  Map<String, dynamic> toJson() => {
        'type': mediaType.value,
        'category': category.value,
        'year': year,
        'region': region,
        'genre': genre,
        'rating': minRating,
        'ratingCount': minRatingCount,
        'sort': sort.code,
      };

  factory DoubanBrowseQuery.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    final category = json['category'];
    final sort = json['sort'];
    final query = DoubanBrowseQuery(
      category: category == 'variety'
          ? DoubanBrowseCategory.variety
          : category == 'series' || type == 'tv'
              ? DoubanBrowseCategory.series
              : DoubanBrowseCategory.movie,
      year: json['year'] is int ? json['year'] as int : null,
      region: json['region'] is String ? json['region'] as String : '',
      genre: json['genre'] is String ? json['genre'] as String : '',
      minRating: json['rating'] is int ? json['rating'] as int : 0,
      minRatingCount:
          json['ratingCount'] is int ? json['ratingCount'] as int : 0,
      sort: DoubanBrowseSort.values.firstWhere(
        (value) => value.code == sort,
        orElse: () => DoubanBrowseSort.rating,
      ),
    );
    query.validate();
    return query;
  }
}

class DoubanBrowsePageData {
  const DoubanBrowsePageData({
    required this.entries,
    required this.start,
    required this.rawCount,
    this.total,
    this.genres = const [],
    this.regions = const [],
  });

  final List<DoubanEntry> entries;
  final int start;
  final int rawCount;
  final int? total;
  final List<String> genres;
  final List<String> regions;

  bool get hasNext =>
      rawCount > 0 &&
      (total == null ? rawCount >= 20 : start + rawCount < total!);
}
