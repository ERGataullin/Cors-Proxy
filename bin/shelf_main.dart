import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_proxy/shelf_proxy.dart';

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
    8080,
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
        headers: {
          for (final String headerName in request.headers.keys)
            headerName == 'kaki' ? 'cookie' : headerName:
                request.headers[headerName],
        },
      );
      final Response originalResponse = await handler(mappedRequest);

      return originalResponse.change(
        headers: {
          for (final String headerName in request.headers.keys)
            headerName == 'set-cookie' ? 'set-kaki' : headerName:
                request.headers[headerName],
        },
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

  return await proxyHandler(
    uri,
    client: _client,
  )(request);
}
