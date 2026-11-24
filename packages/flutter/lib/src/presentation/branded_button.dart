import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../branding/button_artwork.dart';

/// Renders official artwork and handles the button's interaction states.
class BrandedButton extends StatefulWidget {
  const BrandedButton({
    super.key,
    required this.onPressed,
    required this.label,
    required this.locale,
    this.icon = false,
    this.shape = UaePassButtonShape.rounded,
    this.style,
  });

  /// Handles activation. A null callback displays the disabled state.
  final VoidCallback? onPressed;

  /// The localized action. Text buttons also display it in their artwork.
  final UaePassButtonLabel label;
  final bool icon;
  final Locale locale;
  final UaePassButtonShape shape;

  /// Defaults to white with outline on a light theme and solid white on a dark theme.
  final UaePassButtonStyle? style;

  @override
  State<BrandedButton> createState() => _BrandedButtonState();
}

class _BrandedButtonState extends State<BrandedButton> {
  final _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.locale;
    final style = resolveUaePassButtonStyle(context, widget.style);

    return UaePassArtworkLayout(
      language: locale.languageCode,
      label: widget.label,
      icon: widget.icon,
      builder: (context, width, height) => SizedBox(
        width: math.max(width, 48),
        height: math.max(height, 48),
        child: TextButton(
          style: const ButtonStyle(
            padding: WidgetStatePropertyAll(EdgeInsets.zero),
            minimumSize: WidgetStatePropertyAll(Size.zero),
            maximumSize: WidgetStatePropertyAll(Size.infinite),
            fixedSize: WidgetStatePropertyAll(null),
            side: WidgetStatePropertyAll(BorderSide.none),
            elevation: WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(Colors.transparent),
            overlayColor: WidgetStatePropertyAll(Colors.transparent),
            shadowColor: WidgetStatePropertyAll(Colors.transparent),
            surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          statesController: _states,
          onPressed: widget.onPressed,
          child: Semantics(
            label: widget.label.localizedLabel(locale),
            textDirection: locale.languageCode == 'ar'
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: ListenableBuilder(
              listenable: _states,
              builder: (context, _) {
                final state = switch (_states.value) {
                  _ when widget.onPressed == null =>
                    UaePassButtonState.disabled,
                  final states when states.contains(WidgetState.pressed) =>
                    UaePassButtonState.pressed,
                  final states when states.contains(WidgetState.focused) =>
                    UaePassButtonState.focused,
                  _ => UaePassButtonState.active,
                };
                return UaePassArtworkImage(
                  language: locale.languageCode,
                  label: widget.label,
                  icon: widget.icon,
                  shape: widget.shape,
                  style: style,
                  state: state,
                  width: width,
                  height: height,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
