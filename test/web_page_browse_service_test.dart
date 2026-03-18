import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openchat/src/models/web_search_result.dart';
import 'package:openchat/src/services/web_page_browse_service.dart';

void main() {
  test('browse extracts readable text and strips noisy HTML', () async {
    late Uri requestedUri;
    final WebPageBrowseService service = WebPageBrowseService(
      isWebOverride: false,
      httpClient: MockClient((http.Request request) async {
        requestedUri = request.url;
        return http.Response(
          '''
<html>
  <head>
    <title>Example article</title>
    <style>.hidden { display: none; }</style>
  </head>
  <body>
    <script>console.log("ignore");</script>
    <main>
      <h1>Example article</h1>
      <p>First paragraph with useful detail.</p>
      <p>Second paragraph with more detail.</p>
    </main>
  </body>
</html>
''',
          200,
        );
      }),
    );

    final List<WebPageExcerpt> excerpts = await service.browse(
      const <WebSearchResult>[
        WebSearchResult(
          title: 'Example result',
          url: 'https://example.com/article',
          snippet: 'Snippet',
        ),
      ],
    );

    expect(requestedUri.host, 'example.com');
    expect(excerpts, hasLength(1));
    expect(excerpts.single.title, 'Example article');
    expect(
      excerpts.single.excerpt,
      contains('First paragraph with useful detail.'),
    );
    expect(excerpts.single.excerpt, isNot(contains('console.log')));
    expect(excerpts.single.excerpt, isNot(contains('display: none')));
  });

  test('browse uses the local proxy on web', () async {
    late Uri requestedUri;
    final WebPageBrowseService service = WebPageBrowseService(
      isWebOverride: true,
      webProxyUrl: 'http://127.0.0.1:8081',
      httpClient: MockClient((http.Request request) async {
        requestedUri = request.url;
        return http.Response(
          '<html><head><title>Proxy test</title></head><body>Ok</body></html>',
          200,
        );
      }),
    );

    await service.browse(
      const <WebSearchResult>[
        WebSearchResult(
          title: 'Example result',
          url: 'https://example.com/article',
          snippet: 'Snippet',
        ),
      ],
    );

    expect(requestedUri.host, '127.0.0.1');
    expect(requestedUri.path, '/proxy');
    expect(
      requestedUri.queryParameters['url'],
      'https://example.com/article',
    );
  });

  test('formatBrowseContext includes search results and fetched excerpts', () {
    final WebPageBrowseService service = WebPageBrowseService(
      isWebOverride: false,
    );
    const WebSearchResult result = WebSearchResult(
      title: 'OpenChat',
      url: 'https://example.com/openchat',
      snippet: 'Search snippet',
    );

    final String formatted = service.formatBrowseContext(
      'OpenChat',
      const <WebSearchResult>[result],
      const <WebPageExcerpt>[
        WebPageExcerpt(
          searchResult: result,
          url: 'https://example.com/openchat',
          title: 'OpenChat release notes',
          excerpt: 'Fetched page summary.',
          discoveredFromUrl: 'https://example.com/home',
          discoveredFromTitle: 'OpenChat home',
        ),
      ],
    );

    expect(formatted, contains('Web browse context for: OpenChat'));
    expect(formatted, contains('Search results:'));
    expect(formatted, contains('Latest extracted headlines:'));
    expect(formatted, contains('Fetched page excerpts:'));
    expect(formatted, contains('[1] OpenChat release notes'));
    expect(formatted, contains('Sources:'));
  });

  test('browse follows headline links from landing pages', () async {
    final List<Uri> requestedUris = <Uri>[];
    final WebPageBrowseService service = WebPageBrowseService(
      isWebOverride: false,
      httpClient: MockClient((http.Request request) async {
        requestedUris.add(request.url);
        if (request.url.toString() == 'https://example.com/news') {
          return http.Response(
            '''
<html>
  <head><title>Example News</title></head>
  <body>
    <main>
      <a href="/news/story-1">Major story one shapes the day ahead</a>
      <a href="/news/story-2">Major story two brings another update</a>
      <a href="/weather">Weather</a>
    </main>
  </body>
</html>
''',
            200,
          );
        }

        if (request.url.toString() == 'https://example.com/news/story-1') {
          return http.Response(
            '''
<html>
  <head><title>Story One</title></head>
  <body><main><p>Story one lead paragraph with current details.</p></main></body>
</html>
''',
            200,
          );
        }

        if (request.url.toString() == 'https://example.com/news/story-2') {
          return http.Response(
            '''
<html>
  <head><title>Story Two</title></head>
  <body><main><p>Story two lead paragraph with more details.</p></main></body>
</html>
''',
            200,
          );
        }

        return http.Response('not found', 404);
      }),
    );

    final List<WebPageExcerpt> excerpts = await service.browse(
      const <WebSearchResult>[
        WebSearchResult(
          title: 'Example News',
          url: 'https://example.com/news',
          snippet: 'Top stories and headlines',
        ),
      ],
      query: 'latest news on Example',
    );

    expect(
      requestedUris.map((Uri uri) => uri.toString()),
      containsAll(<String>[
        'https://example.com/news',
        'https://example.com/news/story-1',
        'https://example.com/news/story-2',
      ]),
    );
    expect(excerpts, hasLength(3));
    expect(
      excerpts.any((WebPageExcerpt excerpt) => excerpt.url.endsWith('/story-1')),
      isTrue,
    );
    expect(
      excerpts.any((WebPageExcerpt excerpt) => excerpt.url.endsWith('/story-2')),
      isTrue,
    );
  });
}
