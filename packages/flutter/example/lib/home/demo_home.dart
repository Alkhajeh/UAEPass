import 'package:material_ui/material_ui.dart';

import '../gallery/button_gallery.dart';
import '../sign_in/outcome_preview.dart';
import '../sign_in/sandbox_sign_in.dart';

class DemoHome extends StatelessWidget {
  const DemoHome({super.key, required this.onLocaleChanged});

  final ValueChanged<Locale> onLocaleChanged;

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
            onPressed: () => onLocaleChanged(Locale(ar ? 'en' : 'ar')),
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
                    onTap: () =>
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
