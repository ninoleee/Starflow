Map<String, String>? networkImageHeadersForUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) {
    return null;
  }

  final host = uri.host.toLowerCase();
  if (host.isEmpty) {
    return null;
  }

  if (host == 'img1.doubanio.com' ||
      host == 'img2.doubanio.com' ||
      host == 'img3.doubanio.com' ||
      host == 'img9.doubanio.com' ||
      host.endsWith('.doubanio.com')) {
    return const {
      'Referer': 'https://m.douban.com/',
      'User-Agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    };
  }

  return null;
}
