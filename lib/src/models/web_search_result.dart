class WebSearchResult {
  const WebSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
    this.source = 'DuckDuckGo',
    this.content,
  });

  final String title;
  final String url;
  final String snippet;
  final String source;
  final String? content;
}
