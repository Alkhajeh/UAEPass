String? readLocale() => null;

void saveLocale(String languageCode) {}

bool readBackendEnabled() => false;

void saveBackendEnabled(bool enabled) {}

void navigate(Uri uri) => throw UnsupportedError('A browser is required.');

String? takeSigningIntent() => null;

void saveSigningIntent(String transaction) =>
    throw UnsupportedError('A browser is required.');

void clearSigningReturn() {}
