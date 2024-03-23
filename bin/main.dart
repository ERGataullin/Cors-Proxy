import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

final http.Client _client = http.Client();

void main() async {
  final FutureOr<Response> Function(Request) handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_mapKakiHeader())
      .addHandler(_handleRequest);

  final SecurityContext securityContext = SecurityContext.defaultContext
    ..useCertificateChain(r'/root/certificate/zerossl_certificate.crt')
    ..usePrivateKey(r'/root/certificate/private.key');
  final HttpServer server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    443,
    securityContext: securityContext,
  );

  // Enable content compression
  server.autoCompress = true;

  print('Serving at http://${server.address.host}:${server.port}');
}

Middleware _mapKakiHeader() {
  return (Handler handler) {
    return (Request request) async {
      final Request mappedRequest = request.change(
        headers: request.headers.map(
          (key, value) => MapEntry(
            switch (key) {
              'kaki' => 'cookie',
              'host' => '',
              _ => key,
            },
            value,
          ),
        ),
      );
      final Response originalResponse = await handler(mappedRequest);

      return originalResponse.change(
        headers: originalResponse.headers.map(
          (key, value) => MapEntry(
            switch (key) {
              'set-kaki' => 'set-cookie',
              _ => key,
            },
            value,
          ),
        ),
      );
    };
  };
}

Future<Response> _handleRequest(Request request) async {
  Uri? uri = Uri.tryParse(
    Uri.decodeComponent(request.url.path),
  );

  if (uri != null && uri.hasScheme && uri.hasAuthority) {
    uri = uri.replace(
      query: request.url.hasQuery ? request.url.query : null,
      fragment: request.url.hasFragment ? request.url.fragment : null,
    );
  } else {
    return Response.badRequest(body: 'No URL provided.');
  }

  return await _proxy(request, uri: uri);
}

/// Copied from shelf_proxy package
Future<Response> _proxy(
  Request serverRequest, {
  Uri? uri,
  String? proxyName,
}) async {
  // TODO(nweiz): Support WebSocket requests.

  // TODO(nweiz): Handle TRACE requests correctly. See
  // http://www.w3.org/Protocols/rfc2616/rfc2616-sec9.html#sec9.8
  final Uri requestUrl = uri ?? serverRequest.url;
  final clientRequest = http.StreamedRequest(serverRequest.method, requestUrl)
    ..followRedirects = false
    ..headers.addAll(serverRequest.headers)
    ..headers['Host'] = uri?.authority ?? serverRequest.requestedUri.authority;

  // Add a Via header. See
  // http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.45
  _addHeader(
    clientRequest.headers,
    'via',
    '${serverRequest.protocolVersion} $proxyName',
  );

  serverRequest
      .read()
      .forEach(clientRequest.sink.add)
      .catchError(clientRequest.sink.addError)
      .whenComplete(clientRequest.sink.close)
      .ignore();
  final clientResponse = await _client.send(clientRequest);
  // Add a Via header. See
  // http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.45
  _addHeader(clientResponse.headers, 'via', '1.1 $proxyName');

  // Remove the transfer-encoding since the body has already been decoded by
  // [client].
  clientResponse.headers.remove('transfer-encoding');

  // If the original response was gzipped, it will be decoded by [client]
  // and we'll have no way of knowing its actual content-length.
  if (clientResponse.headers['content-encoding'] == 'gzip') {
    clientResponse.headers.remove('content-encoding');
    clientResponse.headers.remove('content-length');

    // Add a Warning header. See
    // http://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html#sec13.5.2
    _addHeader(
      clientResponse.headers,
      'warning',
      '214 $proxyName "GZIP decoded",',
    );
  }

  // Make sure the Location header is pointing to the proxy server rather
  // than the destination server, if possible.
  if (clientResponse.isRedirect &&
      clientResponse.headers.containsKey('location')) {
    final location =
        requestUrl.resolve(clientResponse.headers['location']!).toString();
    if (p.url.isWithin(uri.toString(), location)) {
      clientResponse.headers['location'] =
          '/${p.url.relative(location, from: uri.toString())}';
    } else {
      clientResponse.headers['location'] = location;
    }
  }

  return Response(
    clientResponse.statusCode,
    body: clientResponse.stream,
    headers: clientResponse.headers,
  );
}

// TODO(nweiz): use built-in methods for this when http and shelf support them.
/// Add a header with [name] and [value] to [headers], handling existing headers
/// gracefully.
void _addHeader(Map<String, String> headers, String name, String value) {
  final existing = headers[name];
  headers[name] = existing == null ? value : '$existing, $value';
}
