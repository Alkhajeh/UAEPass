import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'home/demo_home.dart';
import 'sign_in/local_backend.dart'
    if (dart.library.js_interop) 'sign_in/browser_web.dart'
    show exchangeWithLocalBackend;
import 'sign_in/sandbox_sign_in.dart';
import 'signing/staging_signing.dart';
import 'staging_config.dart';

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
  late bool _useLocalBackend;

  @override
  void initState() {
    super.initState();
    _locale = widget.webSandbox?.savedLocale;
    _useLocalBackend =
        localBackendAvailable && (widget.webSandbox?.backendEnabled ?? false);
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
    initialRoute:
        _useLocalBackend &&
            kIsWeb &&
            Uri.base.queryParameters['signing'] == 'return'
        ? StagingSigning.returnRouteName
        : _useLocalBackend && widget.webSandbox?.resumeSigning == true
        ? StagingSigning.routeName
        : widget.webSandbox?.hasCompletion == true
        ? SandboxSignIn.routeName
        : null,
    routes: {
      SandboxSignIn.routeName: (_) => SandboxSignIn(
        webSandbox: widget.webSandbox,
        exchangeCode: _useLocalBackend ? exchangeWithLocalBackend : null,
      ),
      if (_useLocalBackend)
        StagingSigning.routeName: (_) =>
            StagingSigning(webSandbox: widget.webSandbox),
      if (_useLocalBackend && kIsWeb)
        StagingSigning.returnRouteName: (_) => StagingSigning(
          webSandbox: widget.webSandbox,
          approvalReturnId: Uri.base.queryParameters['transaction'],
        ),
    },
    home: DemoHome(
      useLocalBackend: _useLocalBackend,
      onBackendChanged: localBackendAvailable
          ? (enabled) {
              widget.webSandbox?.saveBackendEnabled(enabled);
              setState(() => _useLocalBackend = enabled);
            }
          : null,
      onSignOut: widget.webSandbox == null || widget.webSandbox!.client != null
          ? (context) => signOutOfUaePass(context, widget.webSandbox)
          : null,
      onLocaleChanged: (locale) {
        widget.webSandbox?.saveLocale(locale);
        setState(() => _locale = locale);
      },
    ),
  );
}
