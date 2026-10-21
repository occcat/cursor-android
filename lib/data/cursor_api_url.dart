/// Builds a Cursor web API URL by appending [segments] and [query].
///
/// Mirrors OkHttp `addPathSegment` / `addQueryParameter` in Kotlin 0.1.5:
/// each segment is percent-encoded as one segment (`unsafe/id` becomes
/// `unsafe%2Fid`), an empty trailing base segment is replaced, a literal `.`
/// is skipped and `..` removes the previous segment. Query names and values
/// are percent-encoded, with `%20` for spaces and `%2B` for `+`.
Uri buildApiUrl({
  required Uri webBase,
  required List<String> segments,
  Map<String, String> query = const <String, String>{},
}) {
  final String basePath = webBase.path.isEmpty ? '/' : webBase.path;
  final List<String> path = basePath.substring(1).split('/');
  for (final String segment in segments) {
    if (segment == '.') {
      continue;
    }
    if (segment == '..') {
      _pop(path);
      continue;
    }
    final String encoded = Uri.encodeComponent(segment);
    if (path.last.isEmpty) {
      path[path.length - 1] = encoded;
    } else {
      path.add(encoded);
    }
  }
  final List<String> pairs = <String>[
    if (webBase.query.isNotEmpty) webBase.query,
    for (final MapEntry<String, String> entry in query.entries)
      '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
  ];
  return webBase.replace(
    path: '/${path.join('/')}',
    query: pairs.isEmpty ? null : pairs.join('&'),
  );
}

void _pop(List<String> path) {
  final String removed = path.removeLast();
  if (removed.isEmpty && path.isNotEmpty) {
    path[path.length - 1] = '';
  } else {
    path.add('');
  }
}
