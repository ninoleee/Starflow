import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

// System interface notifications only, never an Internet reachability probe.
final liveProbeNetworkProvider = Provider<Stream<bool>>((ref) => Connectivity()
    .onConnectivityChanged
    .map((interfaces) => interfaces.toSet())
    .distinct(setEquals)
    .map((interfaces) =>
        interfaces.any((value) => value != ConnectivityResult.none)));
