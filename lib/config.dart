import 'dart:io';

import 'package:dotenv/dotenv.dart';

class Config {
  Config._({
    required this.local,
    this.proxy,
    this.certificateChainPath,
    this.certificatePrivateKeyPath,
    this.certificatePrivateKeyPassword,
  }) : assert(
          local.scheme != 'https' ||
              certificateChainPath != null && certificatePrivateKeyPath != null,
          'The local URI scheme is HTTPS, but no certificate chain and private key paths provided',
        );

  factory Config.load(String? path) {
    if (path != null && File(path).existsSync())
      dotenv.load([
        path,
      ]);

    final proxy = getUri('HTTP_PROXY');
    final local = getUri('LOCAL') ?? Uri.http('127.0.0.1:8080');
    final certificateChainPath = getString('CERTIFICATE_CHAIN_PATH');
    final certificatePrivateKeyPath = getString('CERTIFICATE_PRIVATE_KEY_PATH');
    final certificatePrivateKeyPassword = getString(
      'CERTIFICATE_PRIVATE_KEY_PASSWORD',
    );

    return Config._(
      proxy: proxy,
      local: local,
      certificateChainPath: certificateChainPath,
      certificatePrivateKeyPath: certificatePrivateKeyPath,
      certificatePrivateKeyPassword: certificatePrivateKeyPassword,
    );
  }

  final Uri? proxy;
  final Uri local;
  final String? certificateChainPath;
  final String? certificatePrivateKeyPath;
  final String? certificatePrivateKeyPassword;

  bool get secure => local.scheme == 'https';

  static final dotenv = DotEnv();

  /// Returns environment variable or `.env` variable
  static String? getString(String variable) =>
      Platform.environment[variable] ?? dotenv[variable];

  static T? getNum<T extends num>(String variable) =>
      switch (getString(variable)) {
        final String value => switch (T) {
            double => double.tryParse(value),
            int => int.tryParse(value),
            _ => null,
          } as T?,
        _ => null,
      };

  static Uri? getUri(String prefix) =>
      getFullUri('${prefix}_URI') ?? getExplodedUri(prefix);

  static Uri? getFullUri(String variable) => switch (getString(variable)) {
        final String value => Uri.tryParse(value),
        _ => null,
      };

  static Uri? getExplodedUri(String prefix) => switch ((
        getString('${prefix}_SCHEME'),
        getString('${prefix}_HOST'),
      )) {
        (final scheme?, final host?) => Uri(
            scheme: scheme,
            userInfo: switch ((
              getString('${prefix}_USERNAME'),
              getString('${prefix}_PASSWORD'),
            )) {
              (final username?, final password?) => '$username:$password',
              _ => null,
            },
            host: host,
            port: getNum('${prefix}_PORT') ??
                switch (scheme) {
                  'https' => 443,
                  'http' => 80,
                  _ => null,
                },
          ),
        _ => null,
      };
}
