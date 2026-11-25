import 'package:flutter/widgets.dart';

import '../authorization/client.dart';
import '../authorization/result.dart';
import '../branding/button_artwork.dart';
import '../localization/locale.dart';
import 'branded_button.dart';

/// Starts UAE PASS authorization and hands the result back to the app.
///
/// All artwork choices start the same authorization flow. The button is
/// disabled during authorization. The host owns the backend exchange and
/// signed-in session.
class UaePassSignInButton extends StatefulWidget {
  const UaePassSignInButton({
    super.key,
    required this.client,
    required this.onResult,
    this.content = UaePassSignInButtonContent.signIn,
    this.enabled = true,
    this.locale,
    this.shape = UaePassButtonShape.rounded,
    this.style,
  });

  final UaePassClient client;

  /// Receives a grant, cancellation, or failure while the button is mounted.
  final ValueChanged<UaePassResult<UaePassAuthorizationGrant>> onResult;

  final UaePassSignInButtonContent content;

  /// Whether the host allows the user to start an attempt.
  final bool enabled;
  final Locale? locale;
  final UaePassButtonShape shape;
  final UaePassButtonStyle? style;

  @override
  State<UaePassSignInButton> createState() => _UaePassSignInButtonState();
}

class _UaePassSignInButtonState extends State<UaePassSignInButton> {
  bool _authorizing = false;

  Future<void> _authorize(Locale locale) async {
    if (_authorizing || !widget.enabled) return;
    setState(() => _authorizing = true);

    final UaePassResult<UaePassAuthorizationGrant> result;
    try {
      result = await widget.client.authorize(context, locale: locale);
    } finally {
      if (mounted) setState(() => _authorizing = false);
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
      liveRegion: _authorizing,
      value: _authorizing ? progress : null,
      child: BrandedButton(
        label: label ?? UaePassButtonLabel.signIn,
        icon: label == null,
        locale: locale,
        shape: widget.shape,
        style: widget.style,
        onPressed: widget.enabled && !_authorizing
            ? () => _authorize(locale)
            : null,
      ),
    );
  }
}
