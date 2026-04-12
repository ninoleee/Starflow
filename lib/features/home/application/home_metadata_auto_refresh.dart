import 'package:flutter_riverpod/legacy.dart';

final homeMetadataAutoRefreshRevisionProvider = StateProvider<int>(
  (ref) => 1,
);

final homeExplicitRefreshRevisionProvider = StateProvider<int>(
  (ref) => 0,
);
