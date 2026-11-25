import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uaepass/uaepass.dart';

import 'browser_stub.dart'
    if (dart.library.js_interop) 'browser_web.dart'
    as browser;
import 'local_backend.dart'
    if (dart.library.js_interop) 'browser_web.dart'
    show exchangeWithLocalBackend;

const _useBackend =
    (kIsWeb || kDebugMode) && bool.fromEnvironment('UAEPASS_LOCAL_BACKEND');
const _sandboxClientId = 'sandbox_stage';
const _mobileRedirectUrl = String.fromEnvironment(
  'UAEPASS_MOBILE_REDIRECT_URI',
  defaultValue: 'https://localhost:8000',
);
const _webRedirectUrl = String.fromEnvironment('UAEPASS_WEB_REDIRECT_URI');

String demoServiceName(Locale locale) =>
    locale.languageCode == 'ar' ? 'التطبيق التجريبي' : 'the demo app';

class WebSandbox {
  WebSandbox(this.client, [this._completion]);

  factory WebSandbox.restore({String redirectUrl = _webRedirectUrl}) {
    if (redirectUrl.isEmpty) return WebSandbox(null);

    final UaePassWebClient client;
    try {
      client = UaePassWebClient(
        UaePassWebConfiguration(
          environment: UaePassEnvironment.staging,
          clientId: _sandboxClientId,
          redirectUri: Uri.parse(redirectUrl),
        ),
      );
    } on FormatException {
      return WebSandbox(null);
    } on ArgumentError {
      return WebSandbox(null);
    }

    final authorization = client.completeAuthorization();
    return WebSandbox(
      client,
      authorization == null
          ? null
          : _completeSignIn(
              authorization,
              _useBackend ? exchangeWithLocalBackend : null,
            ),
    );
  }

  final UaePassWebClient? client;
  Future<UaePassResult<void>>? _completion;

  bool get hasCompletion => _completion != null;

  Future<UaePassResult<void>>? takeCompletion() {
    final completion = _completion;
    _completion = null;
    return completion;
  }

  Locale? get savedLocale => switch (browser.readLocale()) {
    'ar' => const Locale('ar'),
    'en' => const Locale('en'),
    _ => null,
  };

  void saveLocale(Locale locale) => browser.saveLocale(locale.languageCode);

  void logout() {
    final client = this.client;
    if (client == null) return;
    browser.navigate(
      client.logoutUri(redirectUri: client.configuration.redirectUri),
    );
  }
}

Future<UaePassResult<void>> _completeSignIn(
  UaePassResult<UaePassAuthorizationGrant> authorization,
  Future<void> Function(String code)? exchangeCode,
) async {
  switch (authorization) {
    case UaePassSuccess(:final value):
      try {
        await exchangeCode?.call(value.code);
        return const UaePassSuccess(null);
      } catch (_) {
        return const UaePassFailure(UaePassFailureReason.exchangeFailed);
      }
    case UaePassCancelled():
      return const UaePassCancelled();
    case UaePassFailure(:final reason):
      return UaePassFailure(reason);
  }
}

class SandboxSignIn extends StatefulWidget {
  const SandboxSignIn({
    super.key,
    this.exchangeCode = _useBackend ? exchangeWithLocalBackend : null,
    this.webSandbox,
  });

  static const routeName = '/sign-in';

  final Future<void> Function(String code)? exchangeCode;
  final WebSandbox? webSandbox;

  @override
  State<SandboxSignIn> createState() => _SandboxSignInState();
}

class _SandboxSignInState extends State<SandboxSignIn> {
  static final _client = UaePassClient(
    UaePassConfiguration(
      environment: UaePassEnvironment.staging,
      clientId: _sandboxClientId,
      callbackScheme: 'com.example.uaepass.flutterdemo',
      redirectUri: Uri.parse(_mobileRedirectUrl),
    ),
  );

  UaePassResult<void>? _result;
  bool _exchanging = false;

  @override
  void initState() {
    super.initState();
    final completion = widget.webSandbox?.takeCompletion();
    if (completion != null) {
      _exchanging = widget.exchangeCode != null;
      unawaited(_showCompletion(completion));
    }
  }

  Future<void> _showCompletion(Future<UaePassResult<void>> completion) async {
    final result = await completion;
    if (!mounted) return;
    setState(() {
      _result = result;
      _exchanging = false;
    });
  }

  Future<void> _handleResult(
    UaePassResult<UaePassAuthorizationGrant> result,
  ) async {
    if (_exchanging) return;
    final exchangeCode = widget.exchangeCode;
    if (result is UaePassSuccess && exchangeCode != null) {
      setState(() => _exchanging = true);
    }
    await _showCompletion(_completeSignIn(result, exchangeCode));
  }

  void _handleWebStart(UaePassResult<void> result) {
    setState(() => _result = result is UaePassSuccess ? null : result);
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final ar = locale.languageCode == 'ar';
    final serviceName = demoServiceName(locale);
    final webSandbox = widget.webSandbox;
    final message = _exchanging
        ? (ar ? 'جارٍ التحقق من التفويض' : 'Verifying authorization')
        : switch (_result) {
            null => null,
            UaePassSuccess() when widget.exchangeCode != null =>
              ar ? 'اكتمل التحقق من التفويض' : 'Backend exchange complete',
            UaePassSuccess() => ar ? 'اكتمل التفويض' : 'Authorization complete',
            final result => UaePassSignInMessages.forResult(
              result,
              locale: locale,
              serviceProviderName: serviceName,
            ),
          };
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
                          child: switch (webSandbox) {
                            null => UaePassSignInButton(
                              client: _client,
                              enabled: !_exchanging,
                              onResult: _handleResult,
                            ),
                            WebSandbox(client: final client?) =>
                              UaePassWebSignInButton(
                                client: client,
                                enabled: !_exchanging,
                                onStart: _handleWebStart,
                              ),
                            _ => Text(
                              ar
                                  ? 'اضبط UAEPASS_WEB_REDIRECT_URI على عنوان HTTPS أو http://localhost:8000 للاختبار.'
                                  : 'Set UAEPASS_WEB_REDIRECT_URI to an HTTPS callback or http://localhost:8000 for staging.',
                              textAlign: TextAlign.center,
                            ),
                          },
                        ),
                        if (message != null) ...[
                          const SizedBox(height: 16),
                          Semantics(
                            liveRegion: true,
                            child: Text(message, textAlign: TextAlign.center),
                          ),
                        ],
                        if (webSandbox != null &&
                            _result is UaePassSuccess &&
                            !_exchanging)
                          TextButton(
                            onPressed: webSandbox.logout,
                            child: Text(
                              ar
                                  ? 'تسجيل الخروج من الهوية الرقمية'
                                  : 'Sign out of UAE PASS',
                            ),
                          ),
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
