import 'package:flutter/widgets.dart';

Locale resolveUaePassLocale(BuildContext context, Locale? locale) => Locale(
  (locale ?? Localizations.maybeLocaleOf(context))?.languageCode == 'ar'
      ? 'ar'
      : 'en',
);
