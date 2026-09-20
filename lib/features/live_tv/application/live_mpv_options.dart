const liveMpvProtocols = ['http', 'https', 'tcp', 'tls', 'crypto'];

Map<String, String> liveMediaHeaders(Map<String, String> headers) => {
      if (!headers.keys.any((key) => key.toLowerCase() == 'user-agent'))
        'User-Agent': 'Starflow',
      ...headers,
    };

// FFmpeg 6 already accepts arbitrary HTTP segment suffixes. Keep its file
// extension guard and exclude local protocols instead of allowing all files.
final liveMpvDemuxerOptions = [
  'seg_max_retry=1',
  'strict=experimental',
  'http_persistent=0',
  'protocol_whitelist=[${liveMpvProtocols.join(',')}]',
].join(',');
