import 'dart:async';
import 'dart:io';

const Set<String> _defaultAllowedHosts = <String>{
  'api.duckduckgo.com',
  'html.duckduckgo.com',
  'ollama.com',
  'api.openai.com',
  'openrouter.ai',
  'api.groq.com',
  'api.together.xyz',
  'api.deepseek.com',
};

final Set<String> _allowedHosts = _resolveAllowedHosts();

Future<void> main(List<String> args) async {
  final int port = int.tryParse(
        Platform.environment['OPENCHAT_PROXY_PORT'] ?? '',
      ) ??
      8081;
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    port,
  );

  stdout.writeln(
    'OpenChat web proxy listening on http://${server.address.address}:$port',
  );

  await for (final HttpRequest request in server) {
    unawaited(_handleRequest(request));
  }
}

Future<void> _handleRequest(HttpRequest request) async {
  _writeCorsHeaders(request.response);

  if (request.method == 'OPTIONS') {
    request.response
      ..statusCode = HttpStatus.noContent
      ..close();
    return;
  }

  if (request.uri.path != '/proxy') {
    await _writeTextResponse(
      request.response,
      HttpStatus.notFound,
      'Not found.',
    );
    return;
  }

  final String? rawTargetUrl = request.uri.queryParameters['url'];
  if (rawTargetUrl == null || rawTargetUrl.trim().isEmpty) {
    await _writeTextResponse(
      request.response,
      HttpStatus.badRequest,
      'Missing url query parameter.',
    );
    return;
  }

  final Uri? targetUri = Uri.tryParse(rawTargetUrl);
  if (targetUri == null ||
      !targetUri.hasScheme ||
      (targetUri.scheme != 'https' && targetUri.scheme != 'http')) {
    await _writeTextResponse(
      request.response,
      HttpStatus.badRequest,
      'Invalid target URL.',
    );
    return;
  }

   if (!_allowedHosts.contains(targetUri.host) &&
       !_isAllowedPublicWebTarget(targetUri)) {
     await _writeTextResponse(
       request.response,
       HttpStatus.forbidden,
       'Target host is not allowlisted or is not a safe public web target. Add it with OPENCHAT_PROXY_ALLOWED_HOSTS if needed.',
     );
     return;
   }

  final HttpClient client = HttpClient();
  client.autoUncompress = true;

  try {
    final HttpClientRequest upstreamRequest = await client.openUrl(
      request.method,
      targetUri,
    );

    request.headers.forEach((String name, List<String> values) {
      final String normalizedName = name.toLowerCase();
      if (_shouldForwardRequestHeader(normalizedName)) {
        for (final String value in values) {
          upstreamRequest.headers.add(normalizedName, value);
        }
      }
    });

    await request.cast<List<int>>().pipe(upstreamRequest);
    final HttpClientResponse upstreamResponse = await upstreamRequest.close();

    request.response.statusCode = upstreamResponse.statusCode;
    upstreamResponse.headers.forEach((String name, List<String> values) {
      final String normalizedName = name.toLowerCase();
      if (_shouldForwardResponseHeader(normalizedName)) {
        for (final String value in values) {
          request.response.headers.add(normalizedName, value);
        }
      }
    });

    await upstreamResponse.cast<List<int>>().pipe(request.response);
  } on SocketException catch (error) {
    await _writeTextResponse(
      request.response,
      HttpStatus.badGateway,
      'Proxy connection failed: ${error.message}',
    );
  } finally {
    client.close(force: true);
  }
}

Set<String> _resolveAllowedHosts() {
  final String rawExtraHosts =
      Platform.environment['OPENCHAT_PROXY_ALLOWED_HOSTS'] ?? '';
  final Set<String> extraHosts = rawExtraHosts
      .split(',')
      .map((String host) => host.trim().toLowerCase())
      .where((String host) => host.isNotEmpty)
      .toSet();
  return <String>{..._defaultAllowedHosts, ...extraHosts};
}

bool _isAllowedPublicWebTarget(Uri targetUri) {
  final String host = targetUri.host.toLowerCase();
  if (host.isEmpty ||
      host == 'localhost' ||
      host.endsWith('.local') ||
      host.endsWith('.internal')) {
    return false;
  }

  final InternetAddress? address = InternetAddress.tryParse(host);
  if (address == null) {
    return host.contains('.');
  }

  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return false;
  }

  final List<int> bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    final int first = bytes[0];
    final int second = bytes[1];
    if (first == 10 ||
        first == 127 ||
        (first == 169 && second == 254) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168)) {
      return false;
    }
  } else {
    if ((bytes[0] & 0xfe) == 0xfc || (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80)) {
      return false;
    }
  }

  return true;
}

bool _shouldForwardRequestHeader(String name) {
  return name == 'authorization' ||
      name == 'content-type' ||
      name == 'accept' ||
      name == 'accept-language';
}

bool _shouldForwardResponseHeader(String name) {
  return name != 'transfer-encoding' &&
      name != 'connection' &&
      name != 'content-encoding' &&
      name != 'content-length' &&
      name != 'access-control-allow-origin' &&
      name != 'access-control-allow-methods' &&
      name != 'access-control-allow-headers';
}

void _writeCorsHeaders(HttpResponse response) {
  response.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    ..set(
      'Access-Control-Allow-Headers',
      'Authorization, Content-Type, Accept, Accept-Language',
    );
}

Future<void> _writeTextResponse(
  HttpResponse response,
  int statusCode,
  String message,
) async {
  response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.text
    ..write(message);
  await response.close();
}
