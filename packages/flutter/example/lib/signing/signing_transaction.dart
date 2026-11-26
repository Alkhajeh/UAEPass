import 'dart:convert';
import 'dart:math';

import '../staging_config.dart';

class SigningTransaction {
  const SigningTransaction(this.id, this.token, this.level);

  factory SigningTransaction.start(DemoSignatureLevel level) {
    final random = Random.secure();
    String nonce() =>
        base64UrlEncode(List.generate(24, (_) => random.nextInt(256)));
    return SigningTransaction(nonce(), nonce(), level);
  }

  final String id;
  final String token;
  final DemoSignatureLevel level;

  static final _nonce = RegExp(r'^[a-zA-Z0-9_-]{32}$');

  String encode() => jsonEncode([id, token, level.name]);

  static SigningTransaction? decode(String? value) {
    if (value == null) return null;
    try {
      if (jsonDecode(value) case [String id, String token, String level]) {
        final parsed = DemoSignatureLevel.parse(level);
        if (_nonce.hasMatch(id) && _nonce.hasMatch(token) && parsed != null) {
          return SigningTransaction(id, token, parsed);
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}
