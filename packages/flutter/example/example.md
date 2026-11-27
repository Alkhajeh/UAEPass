# uaepass examples

These examples show the smallest sign-in setup for each platform. `AppSession` and `exchangeOnBackend` are placeholders for your app's session type and backend call. The widgets come from `package:material_ui`. Your backend exchanges the code with UAE PASS. Complete the platform callback setup in the [integration guide](https://pub.dev/packages/uaepass#android-and-ios-quick-start) first.

## Android and iOS

```dart
import 'package:material_ui/material_ui.dart';
import 'package:uaepass/uaepass.dart';

final client = UaePassClient(
  UaePassConfiguration(
    environment: UaePassEnvironment.staging,
    clientId: 'your-client-id',
    callbackScheme: 'com.example.yourapp',
    redirectUri: Uri.parse('https://service.example/uaepass/callback'),
  ),
);

class SignInPage extends StatelessWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: UaePassSignInButton(
          client: client,
          onResult: (result) => handleResult(context, result),
        ),
      ),
    );
  }
}

Future<void> handleResult(
  BuildContext context,
  UaePassResult<UaePassAuthorizationGrant> result,
) async {
  UaePassResult<Object?> outcome = result;
  if (result case UaePassSuccess(:final value)) {
    try {
      outcome = await exchangeOnBackend(value);
    } catch (_) {
      outcome = const UaePassFailure(UaePassFailureReason.exchangeFailed);
    }
  }
  if (outcome case UaePassSuccess()) {
    // Store the app session and continue into the app.
    return;
  }
  if (!context.mounted) return;
  final message = UaePassSignInMessages.forResult(
    outcome,
    locale: Localizations.localeOf(context),
    serviceProviderName: 'Your service',
  );
  if (message != null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

Future<UaePassResult<AppSession>> exchangeOnBackend(
  UaePassAuthorizationGrant grant,
) async {
  // POST grant.code over HTTPS to your backend, which exchanges it at
  // UAE PASS and returns your app session.
  throw UnimplementedError();
}
```

## Flutter Web

```dart
import 'package:material_ui/material_ui.dart';
import 'package:uaepass/uaepass.dart';

final webClient = UaePassWebClient(
  UaePassWebConfiguration(
    environment: UaePassEnvironment.staging,
    clientId: 'your-web-client-id',
    redirectUri: Uri.parse('https://service.example/uaepass/callback'),
  ),
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolves to null on a regular page load, or to the exchange result
  // after UAE PASS redirects back to the app. The SDK reports an exchange
  // exception as UaePassFailureReason.exchangeFailed.
  final signIn = webClient.completeLogin(exchangeCode: exchangeOnBackend);

  runApp(MaterialApp(home: SignInPage(signIn: signIn)));
}

class SignInPage extends StatelessWidget {
  const SignInPage({super.key, required this.signIn});

  final Future<UaePassResult<AppSession>?> signIn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FutureBuilder(
          future: signIn,
          builder: (context, snapshot) {
            final outcome = snapshot.data;
            if (outcome case UaePassSuccess()) {
              // Store the app session and continue into the app.
              return const Text('Signed in');
            }
            final message = outcome == null
                ? null
                : messageFor(context, outcome);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                UaePassWebSignInButton(
                  client: webClient,
                  enabled: snapshot.connectionState == ConnectionState.done,
                  onStart: (result) {
                    final message = messageFor(context, result);
                    if (message != null) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(message)));
                    }
                  },
                ),
                if (message != null) Text(message),
              ],
            );
          },
        ),
      ),
    );
  }
}

String? messageFor(BuildContext context, UaePassResult<Object?> result) =>
    UaePassSignInMessages.forResult(
      result,
      locale: Localizations.localeOf(context),
      serviceProviderName: 'Your service',
    );
```

## Full demo

The [example app](https://github.com/Alkhajeh/UAEPass/tree/main/packages/flutter/example) shows staging sign-in, document signing, sign-out, localized outcomes, and every button variant in English and Arabic.
