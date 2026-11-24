import 'package:material_ui/material_ui.dart';
import 'package:uaepass/uaepass.dart';

import 'sandbox_exchange.dart';

String demoServiceName(Locale locale) =>
    locale.languageCode == 'ar' ? 'التطبيق التجريبي' : 'the demo app';

class SandboxSignIn extends StatefulWidget {
  const SandboxSignIn({super.key});

  @override
  State<SandboxSignIn> createState() => _SandboxSignInState();
}

class _SandboxSignInState extends State<SandboxSignIn> {
  static final _client = UaePassClient(
    UaePassConfiguration(
      environment: UaePassEnvironment.staging,
      clientId: sandboxClientId,
      callbackScheme: 'poc',
      redirectUri: Uri.parse('https://localhost:8000'),
    ),
  );

  UaePassResult<SandboxSession>? _result;

  void _handleResult(UaePassResult<SandboxSession> result) {
    if (result case UaePassSuccess(:final value)) {
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(builder: (_) => _SignedInPage(session: value)),
      );
      return;
    }
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final ar = locale.languageCode == 'ar';
    final serviceName = demoServiceName(locale);
    final result = _result;
    final message = result == null
        ? null
        : UaePassSignInMessages.forResult(
            result,
            locale: locale,
            serviceProviderName: serviceName,
          );
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
                        UaePassSignInButton<SandboxSession>(
                          client: _client,
                          exchangeCode: exchangeSandboxCode,
                          onResult: _handleResult,
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

class _SignedInPage extends StatelessWidget {
  const _SignedInPage({required this.session});

  final SandboxSession session;

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final name = ar
        ? session.arabicName ?? session.englishName
        : session.englishName ?? session.arabicName;
    final title = ar ? 'تم تسجيل الدخول' : 'Signed in';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.check_circle_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              name ?? title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
