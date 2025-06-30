import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf/src/message.dart';
import 'package:shelf_proxy/shelf_proxy.dart';

abstract class _CustomHeaders {
  static const link = 'link';

  static const kaki = 'kaki';

  static const setKaki = 'set-kaki';
}

void main() async {
  final FutureOr<Response> Function(Request) handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_mutateHeaders())
      .addHandler(_handleRequest);

  // final SecurityContext securityContext = SecurityContext.defaultContext
  //   ..useCertificateChain(r'/etc/letsencrypt/live/aniway.su/fullchain.pem')
  //   ..usePrivateKey(r'/etc/letsencrypt/live/aniway.su/privkey.pem');
  final HttpServer server = await shelf_io.serve(
    handler,
    // InternetAddress.anyIPv4,
    '192.168.31.7',
    443,
    // securityContext: securityContext,
  );

  // Enable content compression
  server.autoCompress = true;

  print('Serving at http://${server.address.host}:${server.port}');
}

Middleware _mutateHeaders() {
  return (Handler handler) {
    return (Request request) async {
      final Request mutatedRequest = request.change(headers: {
        ...request.headersAll,
        if (request.headersAll[_CustomHeaders.kaki] case final Object cookie)
          HttpHeaders.cookieHeader: cookie,
        _CustomHeaders.kaki: null,
        HttpHeaders.locationHeader: null,
        HttpHeaders.hostHeader: null,
      });

      final Response response = await handler(mutatedRequest);

      return response.change(headers: {
        ...response.headers,
        if (response.headersAll[HttpHeaders.setCookieHeader]
            case final Object setCookie)
          _CustomHeaders.setKaki: setCookie,
        HttpHeaders.accessControlAllowOriginHeader: '*',
        HttpHeaders.accessControlAllowMethodsHeader: '*',
        HttpHeaders.accessControlAllowHeadersHeader: 'authorization,*',
        HttpHeaders.accessControlAllowCredentialsHeader: 'true',
        HttpHeaders.accessControlExposeHeadersHeader: 'authorization,*',
        _CustomHeaders.link: null,
        HttpHeaders.setCookieHeader: null,
        HttpHeaders.locationHeader: null,
      });
    };
  };
}

Future<Response> _handleRequest(Request request) async {
  if (request.method.toUpperCase() == 'OPTIONS' &&
      request.headers[HttpHeaders.accessControlRequestMethodHeader] != null) {
    return Response.ok(null);
  }

  Uri? targetUri = Uri.tryParse(Uri.decodeComponent(request.url.path));
  if (targetUri == null ||
      targetUri.hasScheme != true ||
      targetUri.hasAuthority != true) {
    return Response.badRequest(body: 'No URL provided.');
  }

  final Request targetRequest = Request(
    request.method,
    targetUri,
    protocolVersion: request.protocolVersion,
    headers: request.headersAll,
    handlerPath: '/',
    url: Uri(
      path: targetUri.path.substring(1),
      queryParameters: targetUri.hasQuery ? targetUri.queryParameters : null,
      fragment: targetUri.hasFragment ? targetUri.fragment : null,
    ),
    body: extractBody(request),
    encoding: request.encoding,
    context: request.context,
  );

  final Response response = await proxyHandler(targetUri.origin)(targetRequest);

  return response;
}
