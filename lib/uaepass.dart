// ignore_for_file: prefer_constructors_over_static_methods

import 'package:material_ui/material_ui.dart';

import 'src/configuration.dart';
import 'src/enums.dart';
import 'src/helper.dart';
import 'src/model/uaepass_token.dart';
import 'src/model/uaepass_user.dart';
import 'src/uaepass_login_view.dart';

export 'src/enums.dart';
export 'src/uaepass_login_button.dart';

class Uaepass {
  static Uaepass? _instance;
  Uaepass._({
    required this.env,
    required this.fullscreen,
    required this.showMessages,
    required this.appScheme,
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
  });

  static Uaepass init({
    required UaePassEnv env,
    required String appScheme,
    required String clientId,
    required String clientSecret,
    String redirectUri = Configuration.redirectURL,
    bool fullscreen = true,
    bool showMessages = true,
  }) => _instance = Uaepass._(
    env: env,
    fullscreen: fullscreen,
    showMessages: showMessages,
    appScheme: appScheme,
    clientId: clientId,
    clientSecret: clientSecret,
    redirectUri: Uri.parse(redirectUri),
  );

  static Uaepass get instance {
    if (_instance == null) {
      throw Exception('Initialize UAEPass plugin first.');
    }

    return _instance!;
  }

  final UaePassEnv env;
  final String appScheme;
  final String clientId;
  final String clientSecret;
  final Uri redirectUri;
  final bool showMessages;
  final bool fullscreen;
  String? _code;
  UaepassToken? _token;
  UaepassUser? _user;

  /// Get authorization code
  String? get code => _code;

  /// Get user token
  UaepassToken? get token => _token;

  /// Get user information
  UaepassUser? get user => _user;

  /// Check if user is logged in
  bool isLoggedIn() {
    return _token != null && _user != null;
  }

  /// Initiate UAEPass login
  Future<void> login(BuildContext context) async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (context) => const UaepassLoginView(),
        fullscreenDialog: fullscreen,
      ),
    );

    if (code == null) return;
    try {
      final token = await Helper.getTokenAsync(code);
      final accessToken = token?.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        throw const FormatException('Missing UAE PASS access token');
      }
      final user = await Helper.getUser(accessToken);
      if (user == null) {
        throw const FormatException('Missing UAE PASS profile');
      }
      _code = code;
      _token = token;
      _user = user;
    } on Exception {
      if (showMessages && context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Could not complete UAE PASS sign-in.')),
        );
      }
    }
  }
}
