import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uaepass/uaepass.dart';

import 'local_backend.dart';

const _useLocalBackend =
    kDebugMode && bool.fromEnvironment('UAEPASS_LOCAL_BACKEND');

String demoServiceName(Locale locale) =>
    locale.languageCode == 'ar' ? 'التطبيق التجريبي' : 'the demo app';

class SandboxSignIn extends StatefulWidget {
  const SandboxSignIn({
    super.key,
    this.exchangeCode = _useLocalBackend ? exchangeWithLocalBackend : null,
  });

  final Future<void> Function(String code)? exchangeCode;

  @override
  State<SandboxSignIn> createState() => _SandboxSignInState();
}

class _SandboxSignInState extends State<SandboxSignIn> {
  static final _client = UaePassClient(
    UaePassConfiguration(
      environment: UaePassEnvironment.staging,
      clientId: 'sandbox_stage',
      callbackScheme: 'com.example.uaepass.flutterdemo',
      redirectUri: Uri.parse('https://localhost:8000'),
    ),
  );

  String? _message;
  bool _exchanging = false;

  Future<void> _handleResult(
    UaePassResult<UaePassAuthorizationGrant> result,
  ) async {
    if (_exchanging) return;
    final locale = Localizations.localeOf(context);
    final ar = locale.languageCode == 'ar';
    final serviceName = demoServiceName(locale);
    final exchangeCode = widget.exchangeCode;

    if (result case UaePassSuccess(:final value) when exchangeCode != null) {
      setState(() {
        _message = ar ? 'جارٍ التحقق من التفويض' : 'Verifying authorization';
        _exchanging = true;
      });
      String? message;
      try {
        await exchangeCode(value.code);
        message = ar ? 'اكتمل التحقق من التفويض' : 'Backend exchange complete';
      } catch (_) {
        message = UaePassSignInMessages.forResult(
          const UaePassFailure<void>(UaePassFailureReason.exchangeFailed),
          locale: locale,
          serviceProviderName: serviceName,
        );
      }
      if (!mounted) return;
      setState(() {
        _message = message;
        _exchanging = false;
      });
      return;
    }

    setState(() {
      _message = switch (result) {
        UaePassSuccess() => ar ? 'اكتمل التفويض' : 'Authorization complete',
        _ => UaePassSignInMessages.forResult(
          result,
          locale: locale,
          serviceProviderName: serviceName,
        ),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final ar = locale.languageCode == 'ar';
    final serviceName = demoServiceName(locale);
    final message = _message;
    return Scaffold(
      appBar: AppBar(title: Text(ar ? 'تسجيل الدخول' : 'Sign in')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ar
                              ? 'تسجيل الدخول إلى $serviceName'
                              : 'Sign in to $serviceName',
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: UaePassSignInButton(
                            client: _client,
                            enabled: !_exchanging,
                            onResult: _handleResult,
                          ),
                        ),
                        if (message != null) ...[
                          const SizedBox(height: 16),
                          Semantics(
                            liveRegion: true,
                            child: Text(message, textAlign: TextAlign.center),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
