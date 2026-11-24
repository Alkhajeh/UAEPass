import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../localization/locale.dart';
import 'button_asset_aliases.dart';

/// The official artwork to display when starting UAE PASS authentication.
enum UaePassSignInButtonContent {
  signIn(UaePassButtonLabel.signIn),
  login(UaePassButtonLabel.login),
  registerAccount(UaePassButtonLabel.registerAccount),
  signUp(UaePassButtonLabel.signUp),
  authorize(UaePassButtonLabel.authorize),

  /// Displays the UAE PASS logo with a localized sign-in accessibility label.
  logoOnly(null);

  const UaePassSignInButtonContent(this._label);

  final UaePassButtonLabel? _label;
}

UaePassButtonLabel? signInButtonLabel(UaePassSignInButtonContent content) =>
    content._label;

/// The button wordings provided by the UAE PASS artwork.
enum UaePassButtonLabel {
  signIn(
    'sign_in',
    264,
    304,
    'Sign in with UAE PASS',
    'تسجيل الدخول بالهوية الرقمية',
  ),
  login(
    'login',
    253,
    304,
    'Login with UAE PASS',
    'تسجيل الدخول بالهوية الرقمية',
  ),
  registerAccount(
    'register_account',
    356,
    284,
    'Register Account with UAE PASS',
    'إنشاء حساب بالهوية الرقمية',
  ),
  signUp(
    'sign_up',
    270,
    284,
    'Sign up with UAE PASS',
    'إنشاء حساب بالهوية الرقمية',
  ),
  authorize(
    'authorize',
    301.75,
    323.75,
    'Authorize Using UAE PASS',
    'طلب المشاركة عبر الهوية الرقمية',
  );

  const UaePassButtonLabel(
    this._directory,
    this._englishWidth,
    this._arabicWidth,
    this._english,
    this._arabic,
  );

  final String _directory;
  final double _englishWidth;
  final double _arabicWidth;
  final String _english;
  final String _arabic;

  /// The label as it appears in the corresponding artwork.
  String localizedLabel(Locale locale) =>
      locale.languageCode == 'ar' ? _arabic : _english;

  double? get _assetScale => this == authorize ? 4 : null;
}

/// The shapes provided by the official UAE PASS artwork.
enum UaePassButtonShape {
  rounded('rounded'),
  fullyRounded('fully_rounded'),
  squareCorners('square_corners');

  const UaePassButtonShape(this._assetName);

  final String _assetName;
}

/// The styles provided by the official UAE PASS artwork.
enum UaePassButtonStyle {
  white('white'),
  whiteOutline('white_outline'),
  black('black');

  const UaePassButtonStyle(this._assetName);

  final String _assetName;
}

UaePassButtonStyle resolveUaePassButtonStyle(
  BuildContext context,
  UaePassButtonStyle? style,
) =>
    style ??
    (Theme.of(context).brightness == Brightness.dark
        ? UaePassButtonStyle.white
        : UaePassButtonStyle.whiteOutline);

/// The interaction states available for an artwork preview.
enum UaePassButtonState { active, focused, pressed, disabled }

/// A static preview of official UAE PASS artwork.
class UaePassButtonArtwork extends StatelessWidget {
  const UaePassButtonArtwork.text({
    super.key,
    this.label = UaePassButtonLabel.signIn,
    this.locale,
    this.shape = UaePassButtonShape.rounded,
    this.style,
    this.state = UaePassButtonState.active,
  }) : _icon = false;

  /// Previews logo-only artwork.
  const UaePassButtonArtwork.icon({
    super.key,
    this.shape = UaePassButtonShape.rounded,
    this.style,
    this.state = UaePassButtonState.active,
  }) : _icon = true,
       label = UaePassButtonLabel.signIn,
       locale = null;

  final UaePassButtonLabel label;
  final Locale? locale;
  final UaePassButtonShape shape;

  /// When omitted, follows the surrounding light or dark theme.
  final UaePassButtonStyle? style;
  final UaePassButtonState state;
  final bool _icon;

  @override
  Widget build(BuildContext context) {
    final language = resolveUaePassLocale(context, locale).languageCode;
    final resolvedStyle = resolveUaePassButtonStyle(context, style);
    return UaePassArtworkLayout(
      language: language,
      label: label,
      icon: _icon,
      builder: (context, width, height) => UaePassArtworkImage(
        language: language,
        label: label,
        icon: _icon,
        shape: shape,
        style: resolvedStyle,
        state: state,
        width: width,
        height: height,
      ),
    );
  }
}

class UaePassArtworkLayout extends StatelessWidget {
  const UaePassArtworkLayout({
    super.key,
    required this.language,
    required this.label,
    required this.icon,
    required this.builder,
  });

  final String language;
  final UaePassButtonLabel label;
  final bool icon;
  final Widget Function(BuildContext context, double width, double height)
  builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (icon) {
        final side = math.min(50.0, constraints.biggest.shortestSide);
        return Center(
          widthFactor: 1,
          heightFactor: 1,
          child: builder(context, side, side),
        );
      }

      final naturalWidth = language == 'ar'
          ? label._arabicWidth
          : label._englishWidth;
      final aspectRatio = naturalWidth / 50;
      // UAE PASS requires clear space of one tenth of the artwork height.
      final width = math.min(
        naturalWidth,
        constraints.maxWidth * aspectRatio / (aspectRatio + 0.2),
      );
      final height = width / aspectRatio;

      return Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Padding(
          padding: EdgeInsets.all(height / 10),
          child: builder(context, width, height),
        ),
      );
    },
  );
}

class UaePassArtworkImage extends StatelessWidget {
  const UaePassArtworkImage({
    super.key,
    required this.language,
    required this.label,
    required this.icon,
    required this.shape,
    required this.style,
    required this.state,
    required this.width,
    required this.height,
  });

  final String language;
  final UaePassButtonLabel label;
  final bool icon;
  final UaePassButtonShape shape;
  final UaePassButtonStyle style;
  final UaePassButtonState state;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final directory = icon ? 'icon' : '${label._directory}/$language';
    final path =
        '$directory/${shape._assetName}_${style._assetName}_${state.name}';
    final asset = buttonAssetAliases[path] ?? path;
    return Image.asset(
      'assets/buttons/$asset.png',
      package: 'uaepass',
      scale: icon ? null : label._assetScale,
      width: width,
      height: height,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      gaplessPlayback: true,
    );
  }
}
