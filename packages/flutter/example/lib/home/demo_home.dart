import 'package:material_ui/material_ui.dart';

import '../gallery/button_gallery.dart';
import '../sign_in/outcome_preview.dart';
import '../sign_in/sandbox_sign_in.dart';
import '../signing/staging_signing.dart';

class DemoHome extends StatefulWidget {
  const DemoHome({
    super.key,
    required this.onLocaleChanged,
    this.useLocalBackend = false,
    this.onBackendChanged,
    this.onSignOut,
  });

  final ValueChanged<Locale> onLocaleChanged;
  final bool useLocalBackend;
  final ValueChanged<bool>? onBackendChanged;
  final Future<void> Function(BuildContext context)? onSignOut;

  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  bool _signingOut = false;

  Future<void> _signOut(Future<void> Function(BuildContext) signOut) async {
    setState(() => _signingOut = true);
    var success = false;
    try {
      await signOut(context);
      success = true;
    } catch (_) {
      // Show a generic message for other sign-out failures.
    }
    if (!mounted) return;
    setState(() => _signingOut = false);
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final message = success
        ? (ar
              ? 'تم تسجيل الخروج من الهوية الرقمية.'
              : 'Signed out of UAE PASS.')
        : (ar
              ? 'تعذّر تسجيل الخروج. حاول مرة أخرى.'
              : 'Could not sign out. Try again.');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final theme = Theme.of(context);

    void open(Widget page) =>
        Navigator.of(context)
            .push<void>(MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      appBar: AppBar(
        title: Text(ar ? 'مثال الهوية الرقمية' : 'UAE PASS example'),
        actions: [
          TextButton(
            onPressed: () => widget.onLocaleChanged(Locale(ar ? 'en' : 'ar')),
            child: Text(ar ? 'English' : 'العربية'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  ar ? 'تسجيل الدخول بالهوية الرقمية' : 'UAE PASS sign-in',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  ar
                      ? 'جرّب تسجيل الدخول في البيئة التجريبية، أو استعرض أشكال الأزرار.'
                      : 'Try the staging sign-in flow or browse the official button styles.',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.login),
                    title: Text(ar ? 'جرّب تسجيل الدخول' : 'Try sign-in'),
                    subtitle: Text(
                      ar
                          ? 'يتطلب حسابًا تجريبيًا'
                          : 'Uses a UAE PASS staging account',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _signingOut
                        ? null
                        : () =>
                              Navigator.of(context)
                                  .pushNamed(SandboxSignIn.routeName),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.widgets_outlined),
                    title: Text(ar ? 'استعرض الأزرار' : 'Explore buttons'),
                    subtitle: Text(
                      ar
                          ? 'المحتوى والأشكال والأنماط'
                          : 'Content, shapes, and styles',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => open(const ButtonGallery()),
                  ),
                ),
                if (widget.onBackendChanged case final changeBackend?)
                  SwitchListTile(
                    title: Text(
                      ar ? 'استخدم الخادم المحلي' : 'Use local backend',
                    ),
                    value: widget.useLocalBackend,
                    onChanged: _signingOut
                        ? null
                        : (enabled) {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            changeBackend(enabled);
                          },
                  ),
                if (widget.onBackendChanged != null)
                  Card(
                    child: ListTile(
                      enabled: widget.useLocalBackend && !_signingOut,
                      leading: const Icon(Icons.draw_outlined),
                      title: Text(ar ? 'وقّع مستندًا' : 'Sign a document'),
                      subtitle: widget.useLocalBackend
                          ? null
                          : Text(
                              ar ? 'فعّل الخادم المحلي لتوقيع مستند.' : 'Enable the local backend to sign a document.',
                            ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _signingOut || !widget.useLocalBackend
                          ? null
                          : () =>
                                Navigator.of(context)
                                    .pushNamed(StagingSigning.routeName),
                    ),
                  ),
                if (widget.onSignOut case final signOut?)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: _signingOut ? null : () => _signOut(signOut),
                      child: Text(
                        ar
                            ? 'تسجيل الخروج من الهوية الرقمية'
                            : 'Sign out of UAE PASS',
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => open(const OutcomePreview()),
                    child: Text(
                      ar
                          ? 'معاينة نتائج تسجيل الدخول'
                          : 'Preview sign-in outcomes',
                    ),
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
