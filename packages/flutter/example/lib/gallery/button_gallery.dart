import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
// The first-party gallery uses the SDK's internal renderer for static previews.
// ignore: implementation_imports
import 'package:uaepass/src/branding/button_artwork.dart'
    show
        UaePassButtonArtwork,
        UaePassButtonLabel,
        UaePassButtonState,
        signInButtonLabel;
import 'package:uaepass/uaepass.dart';

class ButtonGallery extends StatefulWidget {
  const ButtonGallery({super.key});

  @override
  State<ButtonGallery> createState() => _ButtonGalleryState();
}

class _ButtonGalleryState extends State<ButtonGallery> {
  Object _content = UaePassSignInButtonContent.signIn;
  var _shape = UaePassButtonShape.rounded;
  UaePassButtonStyle? _style;
  var _background = Brightness.light;

  String _snippet(Locale locale) => [
    if (_content case final UaePassSignInButtonContent content) ...[
      'UaePassSignInButton(',
      '  client: client,',
      '  onResult: handleAuthorizationResult,',
      '  content: UaePassSignInButtonContent.${content.name},',
    ] else ...[
      'UaePassSigningButton(',
      '  onPressed: startSigning,',
    ],
    "  locale: const Locale('${locale.languageCode}'),",
    '  shape: UaePassButtonShape.${_shape.name},',
    if (_style case final style?) '  style: UaePassButtonStyle.${style.name},',
    ')',
  ].join('\n');

  String _wording(UaePassButtonLabel label, Locale locale) {
    final artwork = label.localizedLabel(locale);
    if (locale.languageCode != 'ar') return artwork;
    // Two pairs of English variants have identical Arabic wording.
    return switch (label) {
      UaePassButtonLabel.signIn => '$artwork (Sign in)',
      UaePassButtonLabel.login => '$artwork (Login)',
      UaePassButtonLabel.registerAccount => '$artwork (Register account)',
      UaePassButtonLabel.signUp => '$artwork (Sign up)',
      UaePassButtonLabel.authorize || UaePassButtonLabel.sign => artwork,
    };
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final ar = locale.languageCode == 'ar';
    final theme = Theme.of(context);
    final label = switch (_content) {
      final UaePassSignInButtonContent content => signInButtonLabel(content),
      _ => UaePassButtonLabel.sign,
    };
    final snippet = _snippet(locale);
    final dark = _background == Brightness.dark;
    final boardColor = dark ? const Color(0xFF242825) : const Color(0xFFF4F6F5);
    final previewTheme = ThemeData(brightness: _background);

    Widget preview(UaePassButtonState state) => label == null
        ? UaePassButtonArtwork.icon(shape: _shape, style: _style, state: state)
        : UaePassButtonArtwork.text(
            label: label,
            locale: locale,
            shape: _shape,
            style: _style,
            state: state,
          );

    return Scaffold(
      appBar: AppBar(title: Text(ar ? 'استعرض الأزرار' : 'Explore buttons')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    Text(
                      ar ? 'خلفية المعاينة' : 'Preview background',
                      style: theme.textTheme.titleSmall,
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final brightness in const [
                          Brightness.light,
                          Brightness.dark,
                        ])
                          ChoiceChip(
                            label: Text(switch (brightness) {
                              Brightness.light => ar ? 'فاتحة' : 'Light',
                              Brightness.dark => ar ? 'داكنة' : 'Dark',
                            }),
                            selected: brightness == _background,
                            onSelected: (_) =>
                                setState(() => _background = brightness),
                          ),
                      ],
                    ),
                  ],
                ),
                Theme(
                  data: previewTheme,
                  child: Card(
                    color: boardColor,
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                          child: preview(UaePassButtonState.active),
                        ),
                        ExpansionTile(
                          shape: const Border(),
                          collapsedShape: const Border(),
                          title: Text(
                            ar ? 'حالات التفاعل' : 'Interaction states',
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            16,
                          ),
                          children: [
                            for (final (state, name) in [
                              (
                                UaePassButtonState.focused,
                                ar ? 'في حالة التركيز' : 'Focused',
                              ),
                              (
                                UaePassButtonState.pressed,
                                ar ? 'تم الضغط' : 'Pressed',
                              ),
                              (
                                UaePassButtonState.disabled,
                                ar ? 'معطّل' : 'Disabled',
                              ),
                            ]) ...[
                              Text(
                                name,
                                style: previewTheme.textTheme.labelLarge,
                              ),
                              preview(state),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  ar ? 'محتوى الزر' : 'Button content',
                  style: theme.textTheme.titleSmall,
                ),
                DropdownButton<Object>(
                  value: _content,
                  isExpanded: true,
                  itemHeight: null,
                  items: [
                    for (final content in UaePassSignInButtonContent.values)
                      DropdownMenuItem(
                        value: content,
                        child: Text(switch (signInButtonLabel(content)) {
                          final wording? => _wording(wording, locale),
                          null => ar ? 'شعار فقط' : 'Logo only',
                        }),
                      ),
                    DropdownMenuItem(
                      value: UaePassButtonLabel.sign,
                      child: Text(_wording(UaePassButtonLabel.sign, locale)),
                    ),
                  ],
                  onChanged: (content) {
                    if (content != null) setState(() => _content = content);
                  },
                ),
                const SizedBox(height: 12),
                Text(ar ? 'الشكل' : 'Shape', style: theme.textTheme.titleSmall),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final shape in UaePassButtonShape.values)
                      ChoiceChip(
                        label: Text(switch ((shape, label == null)) {
                          (UaePassButtonShape.rounded, false) =>
                            ar ? 'زوايا مستديرة' : 'Rounded corners',
                          (UaePassButtonShape.fullyRounded, false) =>
                            ar ? 'كبسولة' : 'Pill',
                          (UaePassButtonShape.squareCorners, false) =>
                            ar ? 'زوايا قائمة' : 'Square corners',
                          (UaePassButtonShape.rounded, true) =>
                            ar ? 'مربع بزوايا مستديرة' : 'Rounded square',
                          (UaePassButtonShape.fullyRounded, true) =>
                            ar ? 'دائرة' : 'Circle',
                          (UaePassButtonShape.squareCorners, true) =>
                            ar ? 'مربع' : 'Square',
                        }),
                        selected: shape == _shape,
                        onSelected: (_) => setState(() => _shape = shape),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(ar ? 'النمط' : 'Style', style: theme.textTheme.titleSmall),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final style in [null, ...UaePassButtonStyle.values])
                      ChoiceChip(
                        label: Text(switch (style) {
                          null => ar ? 'حسب السمة' : 'Theme default',
                          UaePassButtonStyle.white =>
                            ar ? 'أبيض سادة' : 'Solid white',
                          UaePassButtonStyle.whiteOutline =>
                            ar ? 'أبيض بإطار' : 'White with outline',
                          UaePassButtonStyle.black =>
                            ar ? 'أسود سادة' : 'Solid black',
                        }),
                        selected: style == _style,
                        onSelected: (_) => setState(() => _style = style),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    icon: const Icon(Icons.copy),
                    label: Text(
                      ar ? 'نسخ كود Flutter' : 'Copy Flutter snippet',
                    ),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: snippet));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ar ? 'تم النسخ' : 'Snippet copied'),
                          ),
                        );
                      }
                    },
                  ),
                ),
                SelectableText(
                  snippet,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
