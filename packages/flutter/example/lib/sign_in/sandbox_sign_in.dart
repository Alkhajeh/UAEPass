import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:uaepass/uaepass.dart';

import '../signing/signing_transaction.dart';
import '../staging_config.dart';
import 'backend_response.dart';
import 'browser_stub.dart'
    if (dart.library.js_interop) 'browser_web.dart'
    as browser;

const _webRedirectUrl = String.fromEnvironment('UAEPASS_WEB_REDIRECT_URI');

String demoServiceName(Locale locale) =>
    locale.languageCode == 'ar' ? 'التطبيق التجريبي' : 'the demo app';

class WebSandbox {
  WebSandbox(this.client, [this._authorization, this._signingIntent]);

  factory WebSandbox.restore({String redirectUrl = _webRedirectUrl}) {
    final signingIntent = SigningTransaction.decode(
      browser.takeSigningIntent(),
    );
    if (redirectUrl.isEmpty) return WebSandbox(null);

    final UaePassWebClient client;
    try {
      client = UaePassWebClient(
        UaePassWebConfiguration(
          environment: stagingEnvironment,
          clientId: stagingClientId,
          redirectUri: Uri.parse(redirectUrl),
        ),
      );
    } on FormatException {
      return WebSandbox(null);
    } on ArgumentError {
      return WebSandbox(null);
    }

    final authorization = client.completeAuthorization();
    final useLocalBackend = browser.readBackendEnabled();
    return WebSandbox(
      client,
      authorization,
      useLocalBackend && authorization != null ? signingIntent : null,
    );
  }

  final UaePassWebClient? client;
  final SigningTransaction? _signingIntent;
  UaePassResult<UaePassAuthorizationGrant>? _authorization;

  bool get hasCompletion => _authorization != null;
  SigningTransaction? get signingIntent =>
      hasCompletion ? _signingIntent : null;
  bool get resumeSigning => signingIntent != null;
  bool get backendEnabled => browser.readBackendEnabled();

  void saveBackendEnabled(bool enabled) => browser.saveBackendEnabled(enabled);

  UaePassResult<UaePassAuthorizationGrant>? takeAuthorization() {
    final authorization = _authorization;
    _authorization = null;
    return authorization;
  }

  UaePassResult<void> startSigningAuthorization(
    Locale locale,
    SigningTransaction transaction,
  ) {
    final client = this.client;
    const failure = UaePassFailure<void>(
      UaePassFailureReason.authorizationFailed,
    );
    if (client == null) return failure;
    try {
      browser.saveSigningIntent(transaction.encode());
    } catch (_) {
      return failure;
    }
    final result = client.startAuthorization(locale: locale);
    if (result is! UaePassSuccess<void>) browser.takeSigningIntent();
    return result;
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
    browser.clearSigningReturn();
    browser.navigate(
      client.logoutUri(redirectUri: client.configuration.redirectUri),
    );
  }
}

Future<void> signOutOfUaePass(
  BuildContext context,
  WebSandbox? webSandbox,
) async {
  if (webSandbox != null) {
    webSandbox.logout();
  } else if (context.mounted && !await stagingMobileClient.logout(context)) {
    throw StateError('UAE PASS sign-out failed.');
  }
}

Future<UaePassResult<void>> completeStagingSignIn(
  UaePassResult<UaePassAuthorizationGrant> authorization,
  Future<void> Function(String code)? exchangeCode,
) async {
  switch (authorization) {
    case UaePassSuccess(:final value):
      try {
        await exchangeCode?.call(value.code);
        return const UaePassSuccess(null);
      } on BackendConnectionException {
        rethrow;
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
  const SandboxSignIn({super.key, this.exchangeCode, this.webSandbox});

  static const routeName = '/sign-in';

  final Future<void> Function(String code)? exchangeCode;
  final WebSandbox? webSandbox;

  @override
  State<SandboxSignIn> createState() => _SandboxSignInState();
}

class _SandboxSignInState extends State<SandboxSignIn> {
  UaePassResult<void>? _result;
  bool _exchanging = false;
  bool _connectionFailed = false;

  @override
  void initState() {
    super.initState();
    browser.takeSigningIntent();
    final authorization = widget.webSandbox?.takeAuthorization();
    if (authorization != null) {
      unawaited(_handleResult(authorization));
    }
  }

  Future<void> _showCompletion(Future<UaePassResult<void>> completion) async {
    UaePassResult<void>? result;
    var connectionFailed = false;
    try {
      result = await completion;
    } on BackendConnectionException {
      connectionFailed = true;
    }
    if (!mounted) return;
    setState(() {
      _result = result;
      _exchanging = false;
      _connectionFailed = connectionFailed;
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
    await _showCompletion(completeStagingSignIn(result, exchangeCode));
  }

  void _handleWebStart(UaePassResult<void> result) {
    browser.takeSigningIntent();
    setState(() {
      _connectionFailed = false;
      _result = result is UaePassSuccess ? null : result;
    });
  }

  Future<void> _retrySignIn() async {
    if (_exchanging) return;
    final locale = Localizations.localeOf(context);
    final webClient = widget.webSandbox?.client;
    if (webClient != null) {
      _handleWebStart(webClient.startAuthorization(locale: locale));
      return;
    }
    setState(() {
      _connectionFailed = false;
      _exchanging = true;
    });
    // A request may have reached the server before its response was lost.
    // Start a new authorization instead of exchanging the same code again.
    await _showCompletion(
      stagingMobileClient
          .authorize(context, locale: locale)
          .then((result) => completeStagingSignIn(result, widget.exchangeCode)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final ar = locale.languageCode == 'ar';
    final serviceName = demoServiceName(locale);
    final webSandbox = widget.webSandbox;
    final message = _exchanging
        ? (ar ? 'جارٍ التحقق من التفويض' : 'Verifying authorization')
        : _connectionFailed
        ? backendUnavailableMessage(ar)
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
                        if (!_connectionFailed)
                          Center(
                            child: switch (webSandbox) {
                              null => UaePassSignInButton(
                                client: stagingMobileClient,
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
                        if (_connectionFailed)
                          TextButton(
                            onPressed: _retrySignIn,
                            child: Text(ar ? 'إعادة المحاولة' : 'Retry'),
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
