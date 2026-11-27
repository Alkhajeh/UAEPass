import 'dart:convert';
import 'dart:math';

import '../staging_config.dart';

class SigningTransaction {
  const SigningTransaction(
    this.id,
    this.token,
    this.level, {
    this.locale = 'en',
  });

  factory SigningTransaction.start(
    DemoSignatureLevel level, {
    String locale = 'en',
  }) {
    final random = Random.secure();
    String nonce() =>
        base64UrlEncode(List.generate(24, (_) => random.nextInt(256)));
    return SigningTransaction(nonce(), nonce(), level, locale: locale);
  }

  final String id;
  final String token;
  final DemoSignatureLevel level;
  final String locale;

  static final _nonce = RegExp(r'^[a-zA-Z0-9_-]{32}$');

  String encode() => jsonEncode([id, token, level.name, locale]);

  static SigningTransaction? decode(String? value) {
    if (value == null) return null;
    try {
      final fields = switch (jsonDecode(value)) {
        [String id, String token, String level] => (id, token, level, 'en'),
        [String id, String token, String level, String locale]
            when locale == 'en' || locale == 'ar' =>
          (id, token, level, locale),
        _ => null,
      };
      if (fields case (final id, final token, final level, final locale)) {
        final parsed = DemoSignatureLevel.parse(level);
        if (_nonce.hasMatch(id) && _nonce.hasMatch(token) && parsed != null) {
          return SigningTransaction(id, token, parsed, locale: locale);
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}
