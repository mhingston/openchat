import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/web_search_result.dart';

const String _defaultWebBrowseProxyUrl = 'http://127.0.0.1:8081';

class WebPageExcerpt {
  const WebPageExcerpt({
    required this.searchResult,
    required this.url,
    required this.title,
    required this.excerpt,
    this.discoveredFromUrl,
    this.discoveredFromTitle,
  });

  final WebSearchResult searchResult;
  final String url;
  final String title;
  final String excerpt;
  final String? discoveredFromUrl;
  final String? discoveredFromTitle;
}

class WebPageBrowseService {
  WebPageBrowseService({
    http.Client? httpClient,
    bool? isWebOverride,
    String webProxyUrl = _defaultWebBrowseProxyUrl,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _isWeb = isWebOverride ?? kIsWeb,
        _webProxyUrl = webProxyUrl;

  final http.Client _httpClient;
  final bool _ownsClient;
  final bool _isWeb;
  final String _webProxyUrl;

  Future<List<WebPageExcerpt>> browse(
    List<WebSearchResult> results, {
    String? query,
    int maxPages = 3,
    int maxLinksPerPage = 2,
    int maxFollowedPages = 4,
    int maxExcerptLength = 900,
  }) async {
    if (results.isEmpty || maxPages <= 0) {
      return const <WebPageExcerpt>[];
    }

    final List<WebPageExcerpt> excerpts = <WebPageExcerpt>[];
    final Set<String> fetchedUrls = <String>{};
    int followedPages = 0;
    for (final WebSearchResult result in results.take(maxPages)) {
      final Uri? upstreamUri = Uri.tryParse(result.url);
      if (upstreamUri == null || !upstreamUri.hasScheme) {
        continue;
      }

      try {
        // Try Jina Reader first for clean markdown content.
        final String? jinaContent = await _fetchJinaContent(upstreamUri);
        if (jinaContent != null) {
          final WebPageExcerpt? excerpt = _extractExcerptFromMarkdown(
            result,
            jinaContent,
            pageUrl: upstreamUri.toString(),
            maxExcerptLength: maxExcerptLength,
          );
          if (excerpt != null) {
            excerpts.add(excerpt);
            fetchedUrls.add(excerpt.url);
          }
          // Jina provides high-quality content; skip link-following for this result.
          continue;
        }

        // Fall back to HTML scraping with link-following.
        final String? html = await _fetchHtml(upstreamUri);
        if (html == null) {
          continue;
        }

        final WebPageExcerpt? excerpt = _extractExcerpt(
          result,
          html,
          pageUrl: upstreamUri.toString(),
          maxExcerptLength: maxExcerptLength,
        );
        if (excerpt != null) {
          excerpts.add(excerpt);
          fetchedUrls.add(excerpt.url);
        }

        if (followedPages >= maxFollowedPages ||
            !_shouldFollowLinks(upstreamUri, html, query: query)) {
          continue;
        }

        final List<_CandidateLink> candidateLinks = _extractCandidateLinks(
          baseUri: upstreamUri,
          html: html,
          query: query,
        );

        for (final _CandidateLink candidate
            in candidateLinks.take(maxLinksPerPage)) {
          if (followedPages >= maxFollowedPages ||
              fetchedUrls.contains(candidate.url.toString())) {
            continue;
          }

          final String? linkedJinaContent =
              await _fetchJinaContent(candidate.url);
          if (linkedJinaContent != null) {
            final WebPageExcerpt? linkedExcerpt = _extractExcerptFromMarkdown(
              result,
              linkedJinaContent,
              pageUrl: candidate.url.toString(),
              discoveredFromUrl: upstreamUri.toString(),
              discoveredFromTitle: excerpt?.title ?? result.title,
              maxExcerptLength: maxExcerptLength,
            );
            if (linkedExcerpt != null) {
              excerpts.add(linkedExcerpt);
              fetchedUrls.add(linkedExcerpt.url);
              followedPages += 1;
            }
            continue;
          }

          final String? linkedHtml = await _fetchHtml(candidate.url);
          if (linkedHtml == null) {
            continue;
          }

          final WebPageExcerpt? linkedExcerpt = _extractExcerpt(
            result,
            linkedHtml,
            pageUrl: candidate.url.toString(),
            discoveredFromUrl: upstreamUri.toString(),
            discoveredFromTitle: excerpt?.title ?? result.title,
            maxExcerptLength: maxExcerptLength,
          );
          if (linkedExcerpt == null) {
            continue;
          }

          excerpts.add(linkedExcerpt);
          fetchedUrls.add(linkedExcerpt.url);
          followedPages += 1;
        }
      } catch (_) {
        // Ignore page fetch failures so search-based answers can still proceed.
      }
    }

    return excerpts;
  }

  String formatBrowseContext(
    String query,
    List<WebSearchResult> results,
    List<WebPageExcerpt> excerpts,
  ) {
    if (results.isEmpty) {
      return '';
    }

    final Map<String, int> sourceNumbers = <String, int>{};
    int nextSourceNumber = 1;

    for (final WebSearchResult result in results) {
      sourceNumbers[result.url] = nextSourceNumber;
      nextSourceNumber += 1;
    }

    for (final WebPageExcerpt excerpt in excerpts) {
      sourceNumbers.putIfAbsent(excerpt.url, () {
        final int sourceNumber = nextSourceNumber;
        nextSourceNumber += 1;
        return sourceNumber;
      });
    }

    final bool currentEventsQuery = _isCurrentEventsQuery(query);
    final List<WebPageExcerpt> followedExcerpts = excerpts
        .where((WebPageExcerpt excerpt) => excerpt.discoveredFromUrl != null)
        .toList(growable: false);
    final List<WebPageExcerpt> directExcerpts = excerpts
        .where((WebPageExcerpt excerpt) => excerpt.discoveredFromUrl == null)
        .toList(growable: false);

    final StringBuffer buffer = StringBuffer()
      ..writeln('Web browse context for: $query')
      ..writeln()
      ..writeln(
        'Use fetched page excerpts as the primary evidence when they are available. '
        'Use search snippets for discovery or backup only. Cite every web-sourced claim '
        'inline with bracketed source numbers like [1] or [1][2], and finish with a '
        'clear "Sources:" list that includes each cited URL. The browsing has already '
        'been completed for you, so answer directly from the evidence. Do not mention '
        'tools, browsing steps, hidden reasoning, or emit tags like <think>, </think>, '
        'tool_call(...), or tool_calls.',
      )
      ..writeln()
      ..writeln(
        currentEventsQuery
            ? 'If the user is asking for the latest news or headlines, start immediately with 3-6 bullet points of the extracted headlines below. Do not narrate your process or mention fetching, browsing, searching, or embedded context.'
            : 'Answer directly from the evidence below without narrating your process.',
      )
      ..writeln()
      ..writeln('Search results:')
      ..writeln();

    for (int index = 0; index < results.length; index += 1) {
      final WebSearchResult result = results[index];
      buffer
        ..writeln('[${index + 1}] ${result.title}')
        ..writeln('URL: ${result.url}')
        ..writeln('Snippet: ${result.snippet}')
        ..writeln();
    }

    if (followedExcerpts.isNotEmpty) {
      buffer
        ..writeln('Latest extracted headlines:')
        ..writeln();

      for (final WebPageExcerpt excerpt in followedExcerpts.take(6)) {
        final int? sourceNumber = sourceNumbers[excerpt.url];
        final String label = sourceNumber == null ? '[?]' : '[$sourceNumber]';
        buffer.writeln(
          '$label ${excerpt.title} — ${_summarizeExcerpt(excerpt.excerpt)}',
        );
      }

      buffer.writeln();
    }

    if (directExcerpts.isNotEmpty || followedExcerpts.isNotEmpty) {
      buffer
        ..writeln('Fetched page excerpts:')
        ..writeln();

      for (final WebPageExcerpt excerpt in <WebPageExcerpt>[
        ...followedExcerpts,
        ...directExcerpts,
      ]) {
        final int? sourceNumber = sourceNumbers[excerpt.url];
        final String label = sourceNumber == null ? '[?]' : '[$sourceNumber]';
        buffer
          ..writeln('$label ${excerpt.title}')
          ..writeln('URL: ${excerpt.url}')
          ..writeln(
            excerpt.discoveredFromUrl == null
                ? 'Discovery: Direct result'
                : 'Discovery: Followed from ${excerpt.discoveredFromTitle ?? excerpt.discoveredFromUrl}',
          )
          ..writeln('Excerpt: ${excerpt.excerpt}')
          ..writeln();
      }
    }

    buffer
      ..writeln('Sources:')
      ..writeln();

    final Set<String> listedSources = <String>{};
    for (final WebSearchResult result in results) {
      final int? sourceNumber = sourceNumbers[result.url];
      if (sourceNumber == null || !listedSources.add(result.url)) {
        continue;
      }
      buffer.writeln('[$sourceNumber] ${result.url}');
    }
    for (final WebPageExcerpt excerpt in excerpts) {
      final int? sourceNumber = sourceNumbers[excerpt.url];
      if (sourceNumber == null || !listedSources.add(excerpt.url)) {
        continue;
      }
      buffer.writeln('[$sourceNumber] ${excerpt.url}');
    }

    return buffer.toString().trim();
  }

  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }

  WebPageExcerpt? _extractExcerpt(
    WebSearchResult result,
    String html, {
    required String pageUrl,
    String? discoveredFromUrl,
    String? discoveredFromTitle,
    required int maxExcerptLength,
  }) {
    final String excerpt = _extractReadableText(
      html,
      maxExcerptLength: maxExcerptLength,
    );
    if (excerpt.isEmpty) {
      return null;
    }

    final String pageTitle = _extractTitle(html);
    return WebPageExcerpt(
      searchResult: result,
      url: pageUrl,
      title: pageTitle.isEmpty ? result.title : pageTitle,
      excerpt: excerpt,
      discoveredFromUrl: discoveredFromUrl,
      discoveredFromTitle: discoveredFromTitle,
    );
  }

  /// Fetches clean markdown content from the Jina Reader API.
  /// Returns null if the request fails, so callers can fall back to HTML scraping.
  Future<String?> _fetchJinaContent(Uri originalUri) async {
    try {
      final Uri jinaUri = Uri.parse('https://r.jina.ai/${originalUri.toString()}');
      final Uri requestUri = _isWeb ? _proxyUri(jinaUri) : jinaUri;
      final http.Response response = await _httpClient.get(
        requestUri,
        headers: const <String, String>{
          'Accept': 'text/plain,text/markdown',
          'X-Return-Format': 'markdown',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final String body = response.body.trim();
      return body.isEmpty ? null : body;
    } catch (_) {
      return null;
    }
  }

  /// Extracts a [WebPageExcerpt] from Jina Reader markdown output.
  WebPageExcerpt? _extractExcerptFromMarkdown(
    WebSearchResult result,
    String markdown, {
    required String pageUrl,
    String? discoveredFromUrl,
    String? discoveredFromTitle,
    required int maxExcerptLength,
  }) {
    final String title = _extractJinaTitle(markdown);
    final String excerpt = _extractJinaExcerpt(
      markdown,
      maxExcerptLength: maxExcerptLength,
    );
    if (excerpt.isEmpty) {
      return null;
    }
    return WebPageExcerpt(
      searchResult: result,
      url: pageUrl,
      title: title.isEmpty ? result.title : title,
      excerpt: excerpt,
      discoveredFromUrl: discoveredFromUrl,
      discoveredFromTitle: discoveredFromTitle,
    );
  }

  /// Extracts the page title from a Jina Reader markdown response.
  /// Jina prefixes responses with "Title: <title>" on the first non-blank line.
  String _extractJinaTitle(String markdown) {
    for (final String line in markdown.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.toLowerCase().startsWith('title:')) {
        return trimmed.substring(6).trim();
      }
      break;
    }
    return '';
  }

  /// Extracts usable content from a Jina Reader markdown response,
  /// skipping the metadata header lines (Title, URL Source, Published Time).
  String _extractJinaExcerpt(String markdown, {required int maxExcerptLength}) {
    final List<String> lines = markdown.split('\n');
    bool headerDone = false;
    final StringBuffer buffer = StringBuffer();
    for (final String line in lines) {
      final String trimmed = line.trim();
      if (!headerDone) {
        final String lower = trimmed.toLowerCase();
        if (trimmed.isEmpty ||
            lower.startsWith('title:') ||
            lower.startsWith('url source:') ||
            lower.startsWith('published time:') ||
            lower.startsWith('description:') ||
            lower.startsWith('markdown content:')) {
          continue;
        }
        headerDone = true;
      }
      buffer.write('$trimmed ');
      if (buffer.length >= maxExcerptLength * 2) {
        break;
      }
    }

    final String text = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= maxExcerptLength) {
      return text;
    }
    final int preferredCut = text.lastIndexOf('. ', maxExcerptLength);
    final int fallbackCut = text.lastIndexOf(' ', maxExcerptLength);
    final int cutIndex = preferredCut > 200
        ? preferredCut + 1
        : fallbackCut > 200
            ? fallbackCut
            : maxExcerptLength;
    return '${text.substring(0, cutIndex).trim()}…';
  }

  Future<String?> _fetchHtml(Uri upstreamUri) async {
    final Uri requestUri = _isWeb ? _proxyUri(upstreamUri) : upstreamUri;
    final http.Response response = await _httpClient.get(
      requestUri,
      headers: const <String, String>{
        'Accept': 'text/html,application/xhtml+xml',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    return response.body;
  }

  bool _shouldFollowLinks(
    Uri pageUri,
    String html, {
    String? query,
  }) {
    final bool asksForFreshContent = _isCurrentEventsQuery(query ?? '');
    final bool landingPage = pageUri.path.isEmpty ||
        pageUri.path == '/' ||
        pageUri.pathSegments.where((String segment) => segment.isNotEmpty).length <=
            1;
    final int anchorCount = RegExp(
      r'<a\b[^>]*href=',
      caseSensitive: false,
    ).allMatches(html).length;
    return anchorCount >= 1 && (landingPage || asksForFreshContent);
  }

  List<_CandidateLink> _extractCandidateLinks({
    required Uri baseUri,
    required String html,
    String? query,
  }) {
    final bool preferNewsLinks = _isCurrentEventsQuery(query ?? '');
    final Set<String> seenUrls = <String>{};
    final List<_CandidateLink> candidates = <_CandidateLink>[];

    for (final RegExpMatch match in RegExp(
      r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html)) {
      final String rawHref = (match.group(1) ?? '').trim();
      if (rawHref.isEmpty ||
          rawHref.startsWith('#') ||
          rawHref.startsWith('javascript:') ||
          rawHref.startsWith('mailto:') ||
          rawHref.startsWith('tel:')) {
        continue;
      }

      final Uri resolvedUri = baseUri.resolve(rawHref);
      if ((resolvedUri.scheme != 'http' && resolvedUri.scheme != 'https') ||
          resolvedUri.host != baseUri.host ||
          resolvedUri.fragment.isNotEmpty) {
        continue;
      }

      final String normalizedUrl = resolvedUri.toString().split('#').first;
      if (!seenUrls.add(normalizedUrl) || _looksLikeNonArticleUrl(resolvedUri)) {
        continue;
      }

      final String anchorText = _decodeHtmlEntities(_stripHtml(match.group(2) ?? ''));
      if (!_looksLikeHeadline(anchorText)) {
        continue;
      }

      int score = 0;
      if (preferNewsLinks) {
        score += 2;
      }
      if (resolvedUri.pathSegments.length >= 2) {
        score += 2;
      }
      if (resolvedUri.path.contains('-') || RegExp(r'\d').hasMatch(resolvedUri.path)) {
        score += 2;
      }
      if (anchorText.split(RegExp(r'\s+')).length >= 4) {
        score += 1;
      }

      candidates.add(
        _CandidateLink(
          url: Uri.parse(normalizedUrl),
          title: anchorText,
          score: score,
        ),
      );
    }

    candidates.sort((_CandidateLink left, _CandidateLink right) {
      final int scoreComparison = right.score.compareTo(left.score);
      if (scoreComparison != 0) {
        return scoreComparison;
      }
      return left.title.length.compareTo(right.title.length);
    });
    return candidates;
  }

  bool _looksLikeHeadline(String value) {
    final String normalized = value.trim();
    if (normalized.length < 20 || normalized.length > 160) {
      return false;
    }

    final String lowerValue = normalized.toLowerCase();
    const Set<String> bannedPhrases = <String>{
      'home',
      'news',
      'sport',
      'weather',
      'video',
      'audio',
      'live',
      'sign in',
      'register',
      'menu',
      'more',
      'search',
      'skip to content',
    };
    if (bannedPhrases.contains(lowerValue)) {
      return false;
    }

    final int wordCount = normalized.split(RegExp(r'\s+')).length;
    return wordCount >= 4;
  }

  bool _looksLikeNonArticleUrl(Uri uri) {
    final String path = uri.path.toLowerCase();
    return path == '/' ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.gif') ||
        path.endsWith('.svg') ||
        path.endsWith('.pdf') ||
        path.endsWith('.mp4') ||
        path.contains('/live/') ||
        path.contains('/video');
  }

  bool _isCurrentEventsQuery(String query) {
    final String normalizedQuery = query.toLowerCase();
    return normalizedQuery.contains('latest') ||
        normalizedQuery.contains('headline') ||
        normalizedQuery.contains('today') ||
        normalizedQuery.contains('breaking') ||
        normalizedQuery.contains('news');
  }

  String _summarizeExcerpt(String excerpt) {
    final String trimmed = excerpt.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final int sentenceBoundary = trimmed.indexOf('. ');
    if (sentenceBoundary > 0) {
      return trimmed.substring(0, sentenceBoundary + 1).trim();
    }

    if (trimmed.length <= 160) {
      return trimmed;
    }

    final int fallbackCut = trimmed.lastIndexOf(' ', 160);
    final int cutIndex = fallbackCut > 80 ? fallbackCut : 160;
    return '${trimmed.substring(0, cutIndex).trim()}…';
  }

  String _extractTitle(String html) {
    final RegExpMatch? match = RegExp(
      r'<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    return _decodeHtmlEntities(match?.group(1) ?? '');
  }

  String _extractReadableText(
    String html, {
    required int maxExcerptLength,
  }) {
    String text = html
        .replaceAll(
          RegExp(
            r'<(script|style|noscript|template|svg|iframe|head)[^>]*>.*?</\1>',
            caseSensitive: false,
            dotAll: true,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'<br\s*/?>|</p>|</div>|</li>|</section>|</article>',
            caseSensitive: false,
          ),
          '\n',
        )
        .replaceAll(
          RegExp(
            r'</h[1-6]>|</tr>|</td>|</blockquote>|</main>|</aside>',
            caseSensitive: false,
          ),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]*>', dotAll: true), ' ');

    text = _decodeHtmlEntities(text);
    if (text.length <= maxExcerptLength) {
      return text;
    }

    final int preferredCut = text.lastIndexOf('. ', maxExcerptLength);
    final int fallbackCut = text.lastIndexOf(' ', maxExcerptLength);
    final int cutIndex = preferredCut > 200
        ? preferredCut + 1
        : fallbackCut > 200
            ? fallbackCut
            : maxExcerptLength;
    return '${text.substring(0, cutIndex).trim()}…';
  }

  String _decodeHtmlEntities(String value) {
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'&#39;|&apos;', caseSensitive: false), "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>', dotAll: true), ' ');
  }

  Uri _proxyUri(Uri upstreamUri) {
    final Uri proxyBase = Uri.parse(_webProxyUrl);
    return proxyBase.replace(
      path: '/proxy',
      queryParameters: <String, String>{'url': upstreamUri.toString()},
    );
  }
}

class _CandidateLink {
  const _CandidateLink({
    required this.url,
    required this.title,
    required this.score,
  });

  final Uri url;
  final String title;
  final int score;
}
