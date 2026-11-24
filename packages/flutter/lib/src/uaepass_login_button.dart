import 'package:material_ui/material_ui.dart';

import '../uaepass.dart';
import 'model/uaepass_buttons.dart';

/// A UAE PASS sign-in button with official English and Arabic artwork.
class UaepassLoginButton extends StatelessWidget {
  const UaepassLoginButton({
    super.key,
    this.height = 50,
    this.onCallback,
    this.onResult,
    this.exchangeCode,
    this.lang = UaepassLang.en,
    this.type = UaepassButtonType.normal,
    this.theme = UaePassButtonTheme.outline,
  }) : _onAuthorizationResult = null;

  /// Returns the authorization outcome for the app to handle.
  const UaepassLoginButton.authorize({
    required ValueChanged<UaepassAuthorizationResult> onResult,
    super.key,
    this.height = 50,
    this.lang = UaepassLang.en,
    this.type = UaepassButtonType.normal,
    this.theme = UaePassButtonTheme.outline,
  }) : _onAuthorizationResult = onResult,
       onCallback = null,
       onResult = null,
       exchangeCode = null;

  /// Runs after a sign-in attempt finishes.
  final VoidCallback? onCallback;

  /// Receives the outcome after the code exchange completes or the attempt ends.
  final ValueChanged<UaepassLoginResult>? onResult;

  /// Exchanges a successful grant through the app's backend.
  ///
  /// The public sandbox can use the built-in exchange.
  final UaepassCodeExchange? exchangeCode;

  final ValueChanged<UaepassAuthorizationResult>? _onAuthorizationResult;

  final double height;
  final UaepassLang lang;
  final UaepassButtonType type;
  final UaePassButtonTheme theme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: lang == UaepassLang.ar
          ? 'تسجيل الدخول باستخدام الهوية الرقمية'
          : 'Sign in with UAE PASS',
      child: InkWell(
        onTap: () async {
          final client = Uaepass.instance;
          final onAuthorizationResult = _onAuthorizationResult;
          if (onAuthorizationResult != null) {
            final result = await client.authorize(context);
            if (context.mounted) onAuthorizationResult(result);
            return;
          }

          final result = await client.login(
            context,
            exchangeCode: exchangeCode,
          );
          if (!context.mounted) return;
          onResult?.call(result);
          onCallback?.call();
        },
        child: Ink.image(
          image: AssetImage(
            UaepassButtons.signInButton(lang: lang, theme: theme, type: type),
            package: 'uaepass',
          ),
          fit: BoxFit.fitWidth,
          width: height * 5.74,
          height: height,
        ),
      ),
    );
  }
}
