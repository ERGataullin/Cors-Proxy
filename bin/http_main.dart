import 'dart:io';

import 'package:http/http.dart';

final Client _client = Client();

void main() async {
  final SecurityContext securityContext = SecurityContext.defaultContext
    ..useCertificateChain(r'')
    ..usePrivateKey(r'');
  final HttpServer server = await HttpServer.bindSecure(
    InternetAddress.anyIPv4,
    443,
    securityContext,
  );

  server.forEach(_onRequest);
}

Future<void> _onRequest(HttpRequest request) async {
  final Uri remoteUri = Uri.parse(
    Uri.decodeComponent(
      request.uri.path.substring(1),
    ),
  ).replace(
    query: request.uri.hasQuery ? request.uri.query : null,
    fragment: request.uri.hasFragment ? request.uri.fragment : null,
  );
  final BaseRequest remoteRequest = Request(request.method, remoteUri)
    ..followRedirects = false;

  final remoteResponse = await _client.send(remoteRequest);

  final HttpResponse response = request.response;
  await remoteResponse.stream.pipe(response);
  await response.flush();
  await response.close();
}
