import 'package:media_kit/media_kit.dart';

bool isBitmapSubtitle({bool? image, String? codec}) =>
    image == true ||
    const {
      'pgs',
      'sup',
      'idx',
      'application/pgs',
      'application/vobsub',
      'application/dvbsubs',
      's_hdmv/pgs',
      's_vobsub',
      's_dvbsub',
      'hdmv_pgs_subtitle',
      'dvd_subtitle',
      'dvb_subtitle',
      'vobsub',
      'xsub'
    }.contains(codec?.trim().toLowerCase());

SubtitleTrack? resolveMpvSubtitleTrack({
  required SubtitleTrack selected,
  required Iterable<SubtitleTrack> tracks,
  required String sid,
}) {
  final nativeId = sid.trim();
  if (nativeId == 'no') return null;
  final id = nativeId.isNotEmpty && nativeId != 'auto' ? nativeId : selected.id;
  for (final track in tracks) {
    if (track.id == id && id != 'auto' && id != 'no') return track;
  }
  return selected.id == id && id != 'auto' && id != 'no' ? selected : null;
}
