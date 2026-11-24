import '../enums.dart';

abstract final class UaepassButtons {
  static String signInButton({
    UaepassButtonType type = UaepassButtonType.normal,
    UaePassButtonTheme theme = UaePassButtonTheme.outline,
    UaepassLang lang = UaepassLang.en,
  }) => 'images/sign_in/${type.name}_${theme.name}_${lang.name}.png';
}
