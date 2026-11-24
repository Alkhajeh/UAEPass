import 'package:material_ui/material_ui.dart';
import 'package:uaepass/uaepass.dart';

import 'sandbox_sign_in.dart';

class OutcomePreview extends StatelessWidget {
  const OutcomePreview({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final ar = locale.languageCode == 'ar';
    final outcomes = <(String, UaePassResult<void>)>[
      (ar ? 'الإلغاء' : 'Cancellation', const UaePassCancelled()),
      (
        ar ? 'خطأ تقني' : 'Technical failure',
        const UaePassFailure(UaePassFailureReason.authorizationFailed),
      ),
      (
        ar ? 'حساب غير مؤهل' : 'Ineligible account',
        const UaePassFailure(UaePassFailureReason.ineligibleAccount),
      ),
      (
        ar ? 'للمستخدمين المسجلين' : 'Registered users only',
        const UaePassFailure(UaePassFailureReason.registeredUsersOnly),
      ),
      (
        ar ? 'لمواطني دولة الإمارات' : 'UAE nationals only',
        const UaePassFailure(UaePassFailureReason.uaeNationalsOnly),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(ar ? 'معاينة النتائج' : 'Preview outcomes')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  ar
                      ? 'معاينة دون الاتصال بالهوية الرقمية.'
                      : 'Preview the SDK messages offline.',
                ),
                const SizedBox(height: 12),
                for (final (label, outcome) in outcomes)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            UaePassSignInMessages.forResult(
                              outcome,
                              locale: locale,
                              serviceProviderName: demoServiceName(locale),
                            )!,
                          ),
                        ],
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
