import 'package:material_ui/material_ui.dart';
import 'package:uaepass/uaepass.dart';

void main() {
  Uaepass.initSandbox(appScheme: 'poc', showMessages: false);
  runApp(const MaterialApp(home: SignInExample()));
}

class SignInExample extends StatefulWidget {
  const SignInExample({super.key});

  @override
  State<SignInExample> createState() => _SignInExampleState();
}

class _SignInExampleState extends State<SignInExample> {
  UaepassLoginResult? _result;

  @override
  Widget build(BuildContext context) {
    final message = switch (_result) {
      UaepassLoginSuccess(:final session) =>
        'Signed in as ${session.user.fullnameEN ?? 'UAE PASS user'}',
      UaepassLoginCancelled() => 'Sign-in cancelled.',
      UaepassLoginFailure() => 'Could not complete UAE PASS sign-in.',
      null => 'Sign in with your UAE PASS staging account.',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('UAE PASS')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              UaepassLoginButton(
                onResult: (result) => setState(() => _result = result),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
