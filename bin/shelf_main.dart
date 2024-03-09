import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

void main() async {
  var handler =
      const Pipeline().addMiddleware(logRequests()).addHandler(_echoRequest);

  final SecurityContext securityContext = SecurityContext.defaultContext
    ..useCertificateChain(r'')
    ..usePrivateKey(r'');
  var server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    443,
    securityContext: securityContext,
  );

  // Enable content compression
  server.autoCompress = true;

  print('Serving at http://${server.address.host}:${server.port}');
}

Response _echoRequest(Request request) =>
    Response.ok('Request for "${request.url}"');
