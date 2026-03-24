import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openchat/src/models/web_search_result.dart';
import 'package:openchat/src/services/web_search_service.dart';

void main() {
  test('parses DuckDuckGo instant answer and related topics', () async {
    late Uri requestedUri;
    final WebSearchService service = WebSearchService(
      isWebOverride: false,
      httpClient: MockClient((http.Request request) async {
        requestedUri = request.url;
        return http.Response(
          '''
<html><body>
  <div class="result results_links results_links_deep web-result">
    <div class="links_main links_deep result__body">
      <h2 class="result__title">
        <a class="result__a" href="https://example.com/openchat">OpenChat</a>
      </h2>
      <a class="result__snippet">OpenChat is a chat client.</a>
    </div>
  </div>
  <div class="result results_links results_links_deep web-result">
    <div class="links_main links_deep result__body">
      <h2 class="result__title">
        <a class="result__a" href="https://github.com/example/openchat">OpenChat GitHub</a>
      </h2>
      <a class="result__snippet">Source repository.</a>
    </div>
  </div>
</body></html>
''',
          200,
        );
      }),
    );

    final results = await service.search('OpenChat');

    expect(requestedUri.host, 'html.duckduckgo.com');
    expect(results, hasLength(2));
    expect(results.first.title, 'OpenChat');
    expect(results.first.url, 'https://example.com/openchat');
    expect(results.last.title, 'OpenChat GitHub');
  });

  test('formats context with numbered sources', () {
    final WebSearchService service = WebSearchService(isWebOverride: false);

    final String formatted = service.formatResultsForContext(
      'OpenChat',
      const [
        // ignore: prefer_const_constructors
        WebSearchResult(
          title: 'OpenChat',
          url: 'https://example.com/openchat',
          snippet: 'OpenChat is a chat client.',
        ),
      ],
    );

    expect(formatted, contains('Web search results for: OpenChat'));
    expect(formatted, contains('[1] OpenChat'));
    expect(formatted, contains('https://example.com/openchat'));
  });

  test('decodes DuckDuckGo redirect URLs to their real targets', () async {
    final WebSearchService service = WebSearchService(
      isWebOverride: false,
      httpClient: MockClient((http.Request request) async {
        return http.Response(
          '''
<html><body>
  <div class="result results_links results_links_deep web-result">
    <div class="links_main links_deep result__body">
      <h2 class="result__title">
        <a class="result__a" href="https://duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.bbc.com%2Fnews%2Farticles%2Fckg123&rut=abc">BBC story</a>
      </h2>
      <a class="result__snippet">Latest BBC story.</a>
    </div>
  </div>
</body></html>
''',
          200,
        );
      }),
    );

    final List<WebSearchResult> results = await service.search('BBC headlines');

    expect(results, hasLength(1));
    expect(results.single.title, 'BBC story');
    expect(results.single.url, 'https://www.bbc.com/news/articles/ckg123');
  });

  group('extractDirectUrl', () {
    test('returns URI when input is a bare URL', () {
      final WebSearchService service = WebSearchService(isWebOverride: false);
      final uri = service.extractDirectUrl('https://example.com/article');
      expect(uri?.toString(), 'https://example.com/article');
    });

    test('returns URI when URL is wrapped in text', () {
      final WebSearchService service = WebSearchService(isWebOverride: false);
      final uri = service.extractDirectUrl('check this https://example.com/page out');
      expect(uri?.toString(), 'https://example.com/page');
    });

    test('returns URI with path and query params', () {
      final WebSearchService service = WebSearchService(isWebOverride: false);
      final uri = service.extractDirectUrl('https://example.com/article?id=123&ref=abc');
      expect(uri?.toString(), 'https://example.com/article?id=123&ref=abc');
    });

    test('returns null for plain text without URL', () {
      final WebSearchService service = WebSearchService(isWebOverride: false);
      final uri = service.extractDirectUrl('what is quantum computing');
      expect(uri, isNull);
    });

    test('returns null for empty input', () {
      final WebSearchService service = WebSearchService(isWebOverride: false);
      expect(service.extractDirectUrl(''), isNull);
      expect(service.extractDirectUrl('   '), isNull);
    });

    test('handles http URLs', () {
      final WebSearchService service = WebSearchService(isWebOverride: false);
      final uri = service.extractDirectUrl('http://example.com/test');
      expect(uri?.toString(), 'http://example.com/test');
    });

    test('returns first URL when multiple present', () {
      final WebSearchService service = WebSearchService(isWebOverride: false);
      final uri = service.extractDirectUrl('https://first.com and https://second.com');
      expect(uri?.toString(), 'https://first.com');
    });

    test('rejects URLs with invalid structure', () {
      final WebSearchService service = WebSearchService(isWebOverride: false);
      expect(service.extractDirectUrl('https://'), isNull);
      expect(service.extractDirectUrl('not a url at all'), isNull);
    });
  });
}
