class SubtitleTrack {
  final String id;
  final String url;
  final String? language;
  final String? title;

  SubtitleTrack({required this.id, required this.url, this.language, this.title});

  factory SubtitleTrack.no() => SubtitleTrack(id: 'no', url: '');

  factory SubtitleTrack.uri(String uri) => SubtitleTrack(id: uri, url: uri);
}
