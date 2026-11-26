import 'package:flutter/widgets.dart';

import '../branding/button_artwork.dart';
import '../localization/locale.dart';
import 'branded_button.dart';

/// The official **Sign with UAE PASS** button for a document the user reviewed.
///
/// Start the signing transaction in [onPressed]. While starting the request,
/// pass null to disable the button.
class UaePassSigningButton extends StatelessWidget {
  const UaePassSigningButton({
    super.key,
    required this.onPressed,
    this.locale,
    this.shape = UaePassButtonShape.rounded,
    this.style,
  });

  final VoidCallback? onPressed;
  final Locale? locale;
  final UaePassButtonShape shape;
  final UaePassButtonStyle? style;

  @override
  Widget build(BuildContext context) => BrandedButton(
    onPressed: onPressed,
    label: UaePassButtonLabel.sign,
    locale: resolveUaePassLocale(context, locale),
    shape: shape,
    style: style,
  );
}
