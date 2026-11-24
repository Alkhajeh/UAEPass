import 'package:flutter/widgets.dart';

import '../authorization/client.dart';
import '../authorization/result.dart';
import '../branding/button_artwork.dart';
import '../localization/locale.dart';
import 'branded_button.dart';

/// Starts UAE PASS sign-in and completes the app's backend exchange.
///
/// All artwork choices start the same UAE PASS authentication flow. The button
/// is disabled while sign-in is in progress. The host handles the result and
/// owns the signed-in session.
class UaePassSignInButton<T> extends StatefulWidget {
  const UaePassSignInButton({
    super.key,
    required this.client,
    required this.exchangeCode,
    required this.onResult,
    this.content = UaePassSignInButtonContent.signIn,
    this.enabled = true,
    this.locale,
    this.shape = UaePassButtonShape.rounded,
    this.style,
  });

  final UaePassClient client;
  final UaePassCodeExchange<T> exchangeCode;

  /// Receives the outcome of each completed attempt while the button is mounted.
  final ValueChanged<UaePassResult<T>> onResult;

  final UaePassSignInButtonContent content;

  /// Whether the host allows the user to start an attempt.
  final bool enabled;
  final Locale? locale;
  final UaePassButtonShape shape;
  final UaePassButtonStyle? style;

  @override
  State<UaePassSignInButton<T>> createState() => _UaePassSignInButtonState<T>();
}

class _UaePassSignInButtonState<T> extends State<UaePassSignInButton<T>> {
  bool _signingIn = false;

  Future<void> _signIn(Locale locale) async {
    if (_signingIn || !widget.enabled) return;
    setState(() => _signingIn = true);

    final UaePassResult<T> result;
    try {
      result = await widget.client.login(
        context,
        exchangeCode: widget.exchangeCode,
        locale: locale,
      );
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
    if (mounted) widget.onResult(result);
  }

  @override
  Widget build(BuildContext context) {
    final locale = resolveUaePassLocale(context, widget.locale);
    final label = signInButtonLabel(widget.content);
    final progress = locale.languageCode == 'ar'
        ? 'جارٍ تسجيل الدخول'
        : 'Signing in';

    return Semantics(
      liveRegion: _signingIn,
      value: _signingIn ? progress : null,
      child: BrandedButton(
        label: label ?? UaePassButtonLabel.signIn,
        icon: label == null,
        locale: locale,
        shape: widget.shape,
        style: widget.style,
        onPressed: widget.enabled && !_signingIn ? () => _signIn(locale) : null,
      ),
    );
  }
}
