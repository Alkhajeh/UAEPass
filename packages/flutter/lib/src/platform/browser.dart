/// Browser operations used by the redirect flow and installed on Flutter Web.
abstract interface class UaePassBrowser {
  static UaePassBrowser? instance;

  Uri get location;

  String? readSession(String key);
  void writeSession(String key, String value);
  void removeSession(String key);

  void navigate(Uri uri);
  void replaceUrl(Uri uri);
}
