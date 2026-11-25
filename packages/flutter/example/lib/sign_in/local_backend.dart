import 'dart:convert';
import 'dart:io';

Future<void> exchangeWithLocalBackend(String code) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..findProxy = (_) => 'DIRECT';

  Future<void> exchange() async {
    final request = await client.postUrl(
      Uri.http('127.0.0.1:8787', '/auth/uaepass'),
    );
    request
      ..followRedirects = false
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'code': code}));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw const HttpException('The local backend rejected the exchange.');
    }
    final result = jsonDecode(await utf8.decoder.bind(response).join());
    if (result is! Map<String, Object?> || result['ok'] != true) {
      throw const FormatException('Unexpected local backend response.');
    }
  }

  try {
    await exchange().timeout(const Duration(seconds: 12));
  } finally {
    client.close(force: true);
  }
}
