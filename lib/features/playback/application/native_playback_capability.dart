import 'package:starflow/features/playback/domain/playback_models.dart';

enum NativePlaybackCapability {
  supported,
  opticalMediaImage,
  unsupportedContainer,
}

const _unsupportedNativeContainers = <String>{
  'avi',
  'bdmv',
  'divx',
  'iso',
  'rm',
  'rmvb',
  'wmv',
};

NativePlaybackCapability resolveNativePlaybackCapability(
  PlaybackTarget target,
) {
  if (target.isIsoLike ||
      _looksLikeBdmvResource(target.streamUrl) ||
      _looksLikeBdmvResource(target.actualAddress)) {
    return NativePlaybackCapability.opticalMediaImage;
  }

  final container = _normalizeContainer(target.container);
  if (_unsupportedNativeContainers.contains(container)) {
    return container == 'iso' || container == 'bdmv'
        ? NativePlaybackCapability.opticalMediaImage
        : NativePlaybackCapability.unsupportedContainer;
  }

  final urlContainer = _containerFromUrl(target.streamUrl);
  if (_unsupportedNativeContainers.contains(urlContainer)) {
    return urlContainer == 'iso' || urlContainer == 'bdmv'
        ? NativePlaybackCapability.opticalMediaImage
        : NativePlaybackCapability.unsupportedContainer;
  }
  return NativePlaybackCapability.supported;
}

bool supportsNativePlayback(PlaybackTarget target) {
  return resolveNativePlaybackCapability(target) ==
      NativePlaybackCapability.supported;
}

String _normalizeContainer(String value) {
  return value.trim().toLowerCase().replaceAll('.', '');
}

String _containerFromUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final path =
      Uri.tryParse(trimmed)?.path.toLowerCase() ?? trimmed.toLowerCase();
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == path.length - 1) {
    return '';
  }
  return _normalizeContainer(path.substring(dotIndex + 1));
}

bool _looksLikeBdmvResource(String value) {
  final normalized = value.trim().toLowerCase().replaceAll('\\', '/');
  if (normalized.isEmpty) {
    return false;
  }
  final path = Uri.tryParse(normalized)?.path ?? normalized;
  return path == 'bdmv' || path.endsWith('/bdmv') || path.contains('/bdmv/');
}
