import 'dart:convert';
import 'dart:typed_data';

final class BackendConnectionException implements Exception {
  const BackendConnectionException();
}

String backendUnavailableMessage(bool arabic) => arabic
    ? 'تعذّر الاتصال بالخادم المحلي. شغّله وحاول مرة أخرى.'
    : 'Can’t reach the local backend. Start it and try again.';

typedef BackendRequest = Future<BackendResponse> Function(
  String path, {
  required String method,
  Map<String, String>? body,
  String? transactionToken,
});

final class BackendResponse {
  const BackendResponse(this.status, this.bytes);

  final int status;
  final Uint8List bytes;

  Map<String, Object?> get json {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is Map<String, Object?>) return value;
    throw const FormatException('Unexpected backend response.');
  }

  void requireExchangeSuccess() {
    if (status != 200 || json['ok'] != true) {
      throw StateError('The local backend rejected the exchange.');
    }
  }
}
