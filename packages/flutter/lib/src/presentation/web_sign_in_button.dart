import 'package:flutter/widgets.dart';

import '../authorization/result.dart';
import '../authorization/web_client.dart';
import '../branding/button_artwork.dart';
import '../localization/locale.dart';
import 'branded_button.dart';

/// Starts UAE PASS authorization by navigating the current browser tab.
class UaePassWebSignInButton extends StatelessWidget {
  const UaePassWebSignInButton({
    super.key,
    required this.client,
    this.onStart,
    this.content = UaePassSignInButtonContent.signIn,
    this.enabled = true,
    this.locale,
    this.shape = UaePassButtonShape.rounded,
    this.style,
  });

  final UaePassWebClient client;

  /// Reports whether navigation was requested. Complete the flow at startup.
  final ValueChanged<UaePassResult<void>>? onStart;
  final UaePassSignInButtonContent content;
  final bool enabled;
  final Locale? locale;
  final UaePassButtonShape shape;
  final UaePassButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final language = resolveUaePassLocale(context, locale);
    final label = signInButtonLabel(content);
    return BrandedButton(
      label: label ?? UaePassButtonLabel.signIn,
      icon: label == null,
      locale: language,
      shape: shape,
      style: style,
      onPressed: enabled
          ? () {
              final result = client.startAuthorization(locale: language);
              onStart?.call(result);
            }
          : null,
    );
  }
}
