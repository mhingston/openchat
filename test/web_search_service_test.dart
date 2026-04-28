import 'dart:convert';

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

  group('Exa search', () {
    test('uses Exa when exaApiKey is set', () async {
      late Uri requestedUri;
      late Map<String, dynamic> requestBody;
      final WebSearchService service = WebSearchService(
        isWebOverride: false,
        exaApiKey: 'test-exa-key',
        httpClient: MockClient((http.Request request) async {
          requestedUri = request.url;
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            '{"results": []}',
            200,
            headers: {'Content-Type': 'application/json'},
          );
        }),
      );

      await service.search('hello world');

      expect(requestedUri.toString(), 'https://api.exa.ai/search');
      expect(requestBody['query'], 'hello world');
      expect(requestBody['type'], 'auto');
      expect(requestBody['numResults'], 5);
      expect(requestBody['contents']['highlights']['maxCharacters'], 4000);
    });

    test('Exa takes priority over Tavily', () async {
      int exaCalled = 0;
      int tavilyCalled = 0;
      final WebSearchService service = WebSearchService(
        isWebOverride: false,
        exaApiKey: 'test-exa-key',
        tavilyApiKey: 'test-tavily-key',
        httpClient: MockClient((http.Request request) async {
          if (request.url.toString() == 'https://api.exa.ai/search') {
            exaCalled++;
            return http.Response(
              '{"results": [{"title": "Exa Result", "url": "https://exa.com", "highlight": {"highlights": ["exa content"], "score": 0.9}}]}',
              200,
              headers: {'Content-Type': 'application/json'},
            );
          }
          tavilyCalled++;
          return http.Response('{"results": []}', 200);
        }),
      );

      final results = await service.search('test');

      expect(exaCalled, 1);
      expect(tavilyCalled, 0);
      expect(results, hasLength(1));
      expect(results.first.source, 'Exa');
    });

    test('parses Exa results correctly', () async {
      final WebSearchService service = WebSearchService(
        isWebOverride: false,
        exaApiKey: 'test-exa-key',
        httpClient: MockClient((http.Request request) async {
          return http.Response(
            '{"results": ['
            '{"title": "Result 1", "url": "https://example.com/1", "highlight": {"highlights": ["first highlight", "second highlight"], "score": 0.9}},'
            '{"title": "Result 2", "url": "https://example.com/2", "highlight": {"highlights": ["single highlight"], "score": 0.5}},'
            '{"title": "Result 3", "url": "https://example.com/3", "highlight": null}'
            ']}',
            200,
            headers: {'Content-Type': 'application/json'},
          );
        }),
      );

      final results = await service.search('test');

      expect(results, hasLength(3));
      expect(results[0].title, 'Result 1');
      expect(results[0].url, 'https://example.com/1');
      expect(results[0].snippet, 'first highlight | second highlight');
      expect(results[0].source, 'Exa');
      expect(results[0].content, 'first highlight\n\nsecond highlight');
      expect(results[1].title, 'Result 2');
      expect(results[1].snippet, 'single highlight');
      expect(results[2].snippet, '');
    });

    test('sends searchType parameter correctly', () async {
      late Map<String, dynamic> requestBody;
      final WebSearchService service = WebSearchService(
        isWebOverride: false,
        exaApiKey: 'test-exa-key',
        httpClient: MockClient((http.Request request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"results": []}', 200);
        }),
      );

      await service.search('news query', searchType: 'news');

      expect(requestBody['type'], 'news');
    });

    test('searchAll passes searchType to search', () async {
      int callCount = 0;
      late Map<String, dynamic> requestBody1;
      late Map<String, dynamic> requestBody2;
      final WebSearchService service = WebSearchService(
        isWebOverride: false,
        exaApiKey: 'test-exa-key',
        httpClient: MockClient((http.Request request) async {
          callCount++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (callCount == 1) {
            requestBody1 = body;
          } else {
            requestBody2 = body;
          }
          return http.Response('{"results": []}', 200);
        }),
      );

      await service.searchAll(
        ['query one', 'query two'],
        searchType: 'news',
      );

      expect(requestBody1['type'], 'news');
      expect(requestBody2['type'], 'news');
    });

    test('searchAll defaults searchType to auto', () async {
      late Map<String, dynamic> requestBody;
      final WebSearchService service = WebSearchService(
        isWebOverride: false,
        exaApiKey: 'test-exa-key',
        httpClient: MockClient((http.Request request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"results": []}', 200);
        }),
      );

      await service.searchAll(['test query']);

      expect(requestBody['type'], 'auto');
    });

    test('defaults searchType to auto', () async {
      late Map<String, dynamic> requestBody;
      final WebSearchService service = WebSearchService(
        isWebOverride: false,
        exaApiKey: 'test-exa-key',
        httpClient: MockClient((http.Request request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"results": []}', 200);
        }),
      );

      await service.search('test');

      expect(requestBody['type'], 'auto');
    });

    test('handles empty Exa results', () async {
      final WebSearchService service = WebSearchService(
        isWebOverride: false,
        exaApiKey: 'test-exa-key',
        httpClient: MockClient((http.Request request) async {
          return http.Response(
            '{"results": []}',
            200,
            headers: {'Content-Type': 'application/json'},
          );
        }),
      );

      final results = await service.search('test');

      expect(results, isEmpty);
    });

    test('handles Exa non-200 response', () async {
      final WebSearchService service = WebSearchService(
        isWebOverride: false,
        exaApiKey: 'test-exa-key',
        httpClient: MockClient((http.Request request) async {
          return http.Response('error', 500);
        }),
      );

      final results = await service.search('test');

      expect(results, isEmpty);
    });
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
