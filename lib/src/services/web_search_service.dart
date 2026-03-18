import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/web_search_result.dart';

const String _defaultWebSearchProxyUrl = 'http://127.0.0.1:8081';

class WebSearchService {
  WebSearchService({
    http.Client? httpClient,
    bool? isWebOverride,
    String webProxyUrl = _defaultWebSearchProxyUrl,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _isWeb = isWebOverride ?? kIsWeb,
        _webProxyUrl = webProxyUrl;

  final http.Client _httpClient;
  final bool _ownsClient;
  final bool _isWeb;
  final String _webProxyUrl;

  Future<List<WebSearchResult>> search(
    String query, {
    int maxResults = 5,
  }) async {
    final String normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const <WebSearchResult>[];
    }

    final Uri upstreamUri = Uri.https(
      'html.duckduckgo.com',
      '/html/',
      <String, String>{'q': normalizedQuery},
    );
    final Uri requestUri = _isWeb ? _proxyUri(upstreamUri) : upstreamUri;

    final http.Response response = await _httpClient.get(
      requestUri,
      headers: const <String, String>{
        'Accept': 'text/html',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Web search failed (${response.statusCode}): ${response.body}',
      );
    }

    return _parseHtmlResults(response.body, maxResults: maxResults);
  }

  String formatResultsForContext(
    String query,
    List<WebSearchResult> results,
  ) {
    if (results.isEmpty) {
      return '';
    }

    final StringBuffer buffer = StringBuffer()
      ..writeln('Web search results for: $query')
      ..writeln()
      ..writeln(
        'Use these results only when they are relevant. Prefer them for current facts, and cite them inline like [1] or [2]. End with a short "Sources" list.',
      )
      ..writeln();

    for (int index = 0; index < results.length; index += 1) {
      final WebSearchResult result = results[index];
      buffer
        ..writeln('[${index + 1}] ${result.title}')
        ..writeln('URL: ${result.url}')
        ..writeln('Snippet: ${result.snippet}')
        ..writeln();
    }

    return buffer.toString().trim();
  }

  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }

  List<WebSearchResult> _parseHtmlResults(
    String html, {
    required int maxResults,
  }) {
    final List<WebSearchResult> results = <WebSearchResult>[];
    final List<RegExpMatch> titleMatches = RegExp(
      r'<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>',
      dotAll: true,
    ).allMatches(html).toList(growable: false);
    final List<RegExpMatch> snippetMatches = RegExp(
      r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>|<div[^>]*class="result__snippet"[^>]*>(.*?)</div>',
      dotAll: true,
    ).allMatches(html).toList(growable: false);

    for (int index = 0; index < titleMatches.length; index += 1) {
      if (results.length >= maxResults) {
        break;
      }
      final RegExpMatch titleMatch = titleMatches[index];
      final RegExpMatch? snippetMatch =
          index < snippetMatches.length ? snippetMatches[index] : null;

      String url = titleMatch.group(1) ?? '';
      if (url.startsWith('//')) {
        url = 'https:$url';
      }
      url = _normalizeResultUrl(url);
      final String title = _stripHtml(titleMatch.group(2) ?? '');
      final String snippet = _stripHtml(
        snippetMatch?.group(1) ?? snippetMatch?.group(2) ?? '',
      );
      if (title.isEmpty || url.isEmpty) {
        continue;
      }

      results.add(
        WebSearchResult(
          title: title,
          url: url,
          snippet: snippet.isEmpty ? 'No description available' : snippet,
        ),
      );
    }

    return results;
  }

  String _normalizeResultUrl(String url) {
    final Uri? parsedUri = Uri.tryParse(url);
    if (parsedUri == null) {
      return url;
    }

    final String? uddg = parsedUri.queryParameters['uddg'];
    if (uddg != null && uddg.trim().isNotEmpty) {
      return Uri.decodeFull(uddg);
    }

    return url;
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Uri _proxyUri(Uri upstreamUri) {
    final Uri proxyBase = Uri.parse(_webProxyUrl);
    return proxyBase.replace(
      path: '/proxy',
      queryParameters: <String, String>{'url': upstreamUri.toString()},
    );
  }
}
