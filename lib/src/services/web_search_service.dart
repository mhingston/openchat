import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/web_search_result.dart';

const String _defaultWebSearchProxyUrl = 'http://127.0.0.1:8081';

class WebSearchService {
  WebSearchService({
    http.Client? httpClient,
    bool? isWebOverride,
    String webProxyUrl = _defaultWebSearchProxyUrl,
    this.exaApiKey,
    this.tavilyApiKey,
    this.braveSearchApiKey,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _isWeb = isWebOverride ?? kIsWeb,
        _webProxyUrl = webProxyUrl;

  final http.Client _httpClient;
  final bool _ownsClient;
  final bool _isWeb;
  final String _webProxyUrl;
  final String? exaApiKey;
  final String? tavilyApiKey;
  final String? braveSearchApiKey;

  Future<List<WebSearchResult>> search(
    String query, {
    int maxResults = 5,
    String searchType = 'auto',
  }) async {
    final String normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const <WebSearchResult>[];
    }

    if (exaApiKey != null && exaApiKey!.isNotEmpty) {
      return _searchExa(normalizedQuery, maxResults: maxResults, searchType: searchType);
    }

    if (tavilyApiKey != null && tavilyApiKey!.isNotEmpty) {
      return _searchTavily(normalizedQuery, maxResults: maxResults);
    }

    if (braveSearchApiKey != null && braveSearchApiKey!.isNotEmpty) {
      return _searchBrave(normalizedQuery, maxResults: maxResults);
    }

    return _searchDuckDuckGo(normalizedQuery, maxResults: maxResults);
  }

  /// Runs [queries] in parallel and returns deduplicated results ordered by
  /// query index (earlier queries take priority in deduplication).
  Future<List<WebSearchResult>> searchAll(
    List<String> queries, {
    int maxResultsPerQuery = 5,
    String searchType = 'auto',
  }) async {
    if (queries.isEmpty) {
      return const <WebSearchResult>[];
    }
    final List<List<WebSearchResult>> perQueryResults = await Future.wait(
      queries.map(
        (String q) => search(q, maxResults: maxResultsPerQuery, searchType: searchType),
      ),
    );
    final Set<String> seenUrls = <String>{};
    final List<WebSearchResult> combined = <WebSearchResult>[];
    for (final List<WebSearchResult> batch in perQueryResults) {
      for (final WebSearchResult result in batch) {
        if (seenUrls.add(result.url)) {
          combined.add(result);
        }
      }
    }
    return combined;
  }

  static final RegExp _urlPattern = RegExp(
    r'https?://[^\s<>"{}|\\^`\[\]]+',
    caseSensitive: false,
  );

  Uri? extractDirectUrl(String input) {
    final String trimmed = input.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final Match? match = _urlPattern.firstMatch(trimmed);
    if (match == null) {
      return null;
    }
    final String url = match.group(0)!;
    final Uri? parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return null;
    }
    return parsed;
  }

  Future<List<WebSearchResult>> _searchExa(
    String query, {
    required int maxResults,
    required String searchType,
  }) async {
    try {
      final http.Response response = await _httpClient.post(
        Uri.parse('https://api.exa.ai/search'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'x-api-key': exaApiKey!,
        },
        body: jsonEncode(<String, dynamic>{
          'query': query,
          'type': searchType,
          'contents': <String, dynamic>{
            'highlights': <String, dynamic>{
              'maxCharacters': 4000,
            },
          },
          'numResults': maxResults,
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const <WebSearchResult>[];
      }
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> rawResults =
          data['results'] as List<dynamic>? ?? <dynamic>[];
      return rawResults.map((dynamic item) {
        final Map<String, dynamic> r = item as Map<String, dynamic>;
        final Map<String, dynamic>? highlight =
            r['highlight'] as Map<String, dynamic>?;
        final List<dynamic>? highlights =
            highlight?['highlights'] as List<dynamic>?;
        final String snippet = highlights != null && highlights.isNotEmpty
            ? (highlights.take(2).map((dynamic h) {
                final String s = h as String;
                return s.length > 500 ? s.substring(0, 500) : s;
              }).join(' | '))
            : '';
        final String? content = highlights != null && highlights.isNotEmpty
            ? highlights.map((dynamic h) => h as String).join('\n\n')
            : null;
        return WebSearchResult(
          title: r['title'] as String? ?? '',
          url: r['url'] as String? ?? '',
          snippet: snippet,
          source: 'Exa',
          content: content,
        );
      }).toList();
    } catch (_) {
      return const <WebSearchResult>[];
    }
  }

  Future<List<WebSearchResult>> _searchTavily(
    String query, {
    required int maxResults,
  }) async {
    try {
      final http.Response response = await _httpClient.post(
        Uri.parse('https://api.tavily.com/search'),
        headers: const <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'api_key': tavilyApiKey,
          'query': query,
          'max_results': maxResults,
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const <WebSearchResult>[];
      }
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> rawResults =
          data['results'] as List<dynamic>? ?? <dynamic>[];
      return rawResults.map((dynamic item) {
        final Map<String, dynamic> r = item as Map<String, dynamic>;
        return WebSearchResult(
          title: r['title'] as String? ?? '',
          url: r['url'] as String? ?? '',
          snippet: r['content'] as String? ?? '',
          source: 'Tavily',
          content: r['content'] as String?,
        );
      }).toList();
    } catch (_) {
      return const <WebSearchResult>[];
    }
  }

  Future<List<WebSearchResult>> _searchBrave(
    String query, {
    required int maxResults,
  }) async {
    try {
      final Uri uri = Uri.https(
        'api.search.brave.com',
        '/res/v1/web/search',
        <String, String>{'q': query, 'count': '$maxResults'},
      );
      final http.Response response = await _httpClient.get(
        uri,
        headers: <String, String>{
          'Accept': 'application/json',
          'Accept-Encoding': 'gzip',
          'X-Subscription-Token': braveSearchApiKey!,
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const <WebSearchResult>[];
      }
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic>? web =
          data['web'] as Map<String, dynamic>?;
      final List<dynamic> rawResults =
          web?['results'] as List<dynamic>? ?? <dynamic>[];
      return rawResults.map((dynamic item) {
        final Map<String, dynamic> r = item as Map<String, dynamic>;
        return WebSearchResult(
          title: r['title'] as String? ?? '',
          url: r['url'] as String? ?? '',
          snippet: r['description'] as String? ?? '',
          source: 'Brave',
        );
      }).toList();
    } catch (_) {
      return const <WebSearchResult>[];
    }
  }

  Future<List<WebSearchResult>> _searchDuckDuckGo(
    String query, {
    required int maxResults,
  }) async {
    try {
      final Uri upstreamUri = Uri.https(
        'html.duckduckgo.com',
        '/html/',
        <String, String>{'q': query},
      );
      final Uri requestUri = _isWeb ? _proxyUri(upstreamUri) : upstreamUri;

      final http.Response response = await _httpClient.get(
        requestUri,
        headers: const <String, String>{
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const <WebSearchResult>[];
      }

      return _parseHtmlResults(response.body, maxResults: maxResults);
    } catch (_) {
      return const <WebSearchResult>[];
    }
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
