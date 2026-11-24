import 'package:flutter/widgets.dart';

import '../authorization/result.dart';

/// The localized UAE PASS authentication messages for sign-in UI.
abstract final class UaePassSignInMessages {
  /// Returns the message for a completed, unsuccessful attempt.
  ///
  /// A successful result has no message.
  static String? forResult(
    UaePassResult<Object?> result, {
    required Locale locale,
    required String serviceProviderName,
  }) {
    final ar = locale.languageCode == 'ar';

    return switch (result) {
      UaePassSuccess() => null,
      UaePassCancelled() =>
        ar ? 'قام المستخدم بإلغاء تسجيل الدخول' : 'User cancelled the login',
      UaePassFailure(reason: UaePassFailureReason.ineligibleAccount) =>
        ar
            ? 'أنت غير مؤهل للوصول إلى هذه الخدمة. إما أن حسابك لم تتم ترقيته أو لديك حساب زائر. يرجى الاتصال بـ $serviceProviderName لتتمكن من الوصول إلى الخدمة.'
            : 'You are not eligible to access this service. Your account is either not upgraded or you have a visitor account. Please contact $serviceProviderName to access the services.',
      UaePassFailure(reason: UaePassFailureReason.registeredUsersOnly) =>
        ar
            ? 'هذه الخدمة مخصصة فقط للمستخدمين المسجلين، يرجى التواصل مع $serviceProviderName لتتمكن من الوصول إلى الخدمات'
            : 'This service is only for registered users, please contact $serviceProviderName in order to access the services',
      UaePassFailure(reason: UaePassFailureReason.uaeNationalsOnly) =>
        ar
            ? 'هذه الخدمة متاحة فقط لمواطني دولة الإمارات العربية المتحدة.'
            : 'This service is only accessible to UAE Nationals',
      UaePassFailure() =>
        ar
            ? 'حدث خطأ ما أثناء تسجيل الدخول، يرجى المحاولة مرة أخرى لاحقًا!'
            : 'Something went wrong during the login, please try again later!',
    };
  }
}
