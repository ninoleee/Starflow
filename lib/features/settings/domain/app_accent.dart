enum AppAccent {
  bone,
  teal,
  indigo,
  coral,
  amber,
  rose,
  lime,
  violet;

  static AppAccent fromJson(Object? value) {
    return AppAccent.values.firstWhere(
      (accent) => accent.name == value,
      orElse: () => AppAccent.teal,
    );
  }
}
