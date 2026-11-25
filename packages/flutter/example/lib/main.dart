import 'package:material_ui/material_ui.dart';

import 'home/demo_home.dart';

void main() => runApp(const UaePassDemo());

class UaePassDemo extends StatefulWidget {
  const UaePassDemo({super.key});

  @override
  State<UaePassDemo> createState() => _UaePassDemoState();
}

class _UaePassDemoState extends State<UaePassDemo> {
  Locale? _locale;

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) =>
        Localizations.localeOf(context).languageCode == 'ar'
        ? 'مثال الهوية الرقمية'
        : 'UAE PASS example',
    locale: _locale,
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF147461)),
    darkTheme: ThemeData(
      colorSchemeSeed: const Color(0xFF147461),
      brightness: Brightness.dark,
    ),
    home: DemoHome(
      onLocaleChanged: (locale) => setState(() => _locale = locale),
    ),
  );
}
