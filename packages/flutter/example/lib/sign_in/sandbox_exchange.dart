import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uaepass/uaepass.dart';

const sandboxClientId = 'sandbox_stage';
const _sandboxHost = 'stg-id.uaepass.ae';
const _timeout = Duration(seconds: 20);

final class SandboxSession {
  const SandboxSession({required this.englishName, required this.arabicName});

  final String? englishName;
  final String? arabicName;
}

// The public sandbox is designed for proofs of concept. Real integrations
// exchange the grant on their own backend.
Future<UaePassResult<SandboxSession>> exchangeSandboxCode(
  UaePassAuthorizationGrant grant,
) async {
  final credentials = base64Encode(
    utf8.encode('$sandboxClientId:$sandboxClientId'),
  );
  final client = http.Client();
  try {
    final tokenResponse = await client
        .post(
          Uri.https(_sandboxHost, '/idshub/token', {
            'grant_type': 'authorization_code',
            'redirect_uri': grant.redirectUri.toString(),
            'code': grant.code,
          }),
          headers: {'Authorization': 'Basic $credentials'},
        )
        .timeout(_timeout);
    final token = _jsonObject(tokenResponse)['access_token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('Missing sandbox access token.');
    }

    final userResponse = await client
        .get(
          Uri.https(_sandboxHost, '/idshub/userinfo'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_timeout);
    final user = _jsonObject(userResponse);
    if (_string(user['sub']) == null && _string(user['uuid']) == null) {
      throw const FormatException('Missing sandbox user identifier.');
    }

    return UaePassSuccess(
      SandboxSession(
        englishName: _string(user['fullnameEN']),
        arabicName: _string(user['fullnameAR']),
      ),
    );
  } finally {
    client.close();
  }
}

Map<String, Object?> _jsonObject(http.Response response) {
  if (response.statusCode != 200) {
    throw const FormatException('The UAE PASS sandbox request failed.');
  }

  final data = jsonDecode(utf8.decode(response.bodyBytes));
  if (data is! Map<String, Object?>) {
    throw const FormatException('Invalid UAE PASS sandbox response.');
  }
  return data;
}

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
