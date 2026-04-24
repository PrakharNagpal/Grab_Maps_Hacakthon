import 'dart:io';

import 'package:friendship_radius_server/friendship_radius_server.dart';

Future<void> main() async {
  final host = Platform.environment['HOST'] ?? '0.0.0.0';
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;

  final server = await serve(host: host, port: port);
  stdout.writeln(
    'Friendship Radius API listening on http://${server.address.host}:${server.port}',
  );
}
