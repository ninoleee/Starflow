import 'package:flutter_riverpod/legacy.dart';

final nasMediaIndexRevisionProvider = StateProvider<int>((ref) => 0);

final nasMediaIndexGlobalInvalidationRevisionProvider =
    StateProvider<int>((ref) => 0);

final nasMediaIndexSourceInvalidationRevisionsProvider =
    StateProvider<Map<String, int>>((ref) => const <String, int>{});
