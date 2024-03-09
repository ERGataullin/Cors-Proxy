import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

final http.Client _client = http.Client();

void main() async {
  final FutureOr<Response> Function(Request) handler =
      const Pipeline().addMiddleware(logRequests()).addHandler(_handleRequest);

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

Future<Response> _handleRequest(Request request) async {
  final Uri remoteUri = Uri.parse(
    Uri.decodeComponent(request.url.path),
  ).replace(
    query: request.url.hasQuery ? request.url.query : null,
    fragment: request.url.hasFragment ? request.url.fragment : null,
  );
  final http.BaseRequest remoteRequest = http.Request(request.method, remoteUri)
    ..followRedirects = false;

  final remoteResponse = await _client.send(remoteRequest);

  return Response.ok(
    remoteResponse.stream,
    headers: remoteResponse.headersSplitValues,
  );
}
