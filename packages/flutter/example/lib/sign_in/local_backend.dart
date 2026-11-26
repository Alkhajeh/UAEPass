import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../signing/signing_transaction.dart';
import 'backend_response.dart';

SigningTransaction? takeApprovalTransaction(String id) => null;

void rememberApprovalTransaction(String id) {}

void clearSigningReturn() {}

void navigate(Uri uri) => throw UnsupportedError('A browser is required.');

Future<void> exchangeWithLocalBackend(String code) async {
  final result = await requestBackend(
    '/auth/uaepass',
    method: 'POST',
    body: {'code': code},
  );
  result.requireExchangeSuccess();
}

Future<BackendResponse> requestBackend(
  String path, {
  String method = 'GET',
  Map<String, String>? body,
  String? transactionToken,
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..findProxy = (_) => 'DIRECT';

  Future<BackendResponse> send() async {
    final request = await client.openUrl(
      method,
      Uri.http('127.0.0.1:8787').resolve(path),
    );
    request.followRedirects = false;
    if (transactionToken != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $transactionToken',
      );
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
    }
    return BackendResponse(response.statusCode, bytes.takeBytes());
  }

  try {
    return await send().timeout(const Duration(seconds: 30));
  } on IOException {
    throw const BackendConnectionException();
  } on TimeoutException {
    throw const BackendConnectionException();
  } finally {
    client.close(force: true);
  }
}
