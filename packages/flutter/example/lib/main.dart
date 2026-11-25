import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'home/demo_home.dart';
import 'sign_in/sandbox_sign_in.dart';

void main() {
  final webSandbox = kIsWeb ? WebSandbox.restore() : null;
  runApp(UaePassDemo(webSandbox: webSandbox));
}

class UaePassDemo extends StatefulWidget {
  const UaePassDemo({super.key, this.webSandbox});

  final WebSandbox? webSandbox;

  @override
  State<UaePassDemo> createState() => _UaePassDemoState();
}

class _UaePassDemoState extends State<UaePassDemo> {
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    _locale = widget.webSandbox?.savedLocale;
  }

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
    initialRoute: widget.webSandbox?.hasCompletion == true
        ? SandboxSignIn.routeName
        : null,
    routes: {
      SandboxSignIn.routeName: (_) =>
          SandboxSignIn(webSandbox: widget.webSandbox),
    },
    home: DemoHome(
      onLocaleChanged: (locale) {
        widget.webSandbox?.saveLocale(locale);
        setState(() => _locale = locale);
      },
    ),
  );
}
