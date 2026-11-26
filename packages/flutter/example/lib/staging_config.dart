import 'package:flutter/foundation.dart';
import 'package:uaepass/uaepass.dart';

const stagingEnvironment = UaePassEnvironment.staging;
const stagingClientId = 'sandbox_stage';
const stagingCallbackScheme = 'com.example.uaepass.flutterdemo';
const localBackendAvailable = kIsWeb || kDebugMode;

enum DemoSignatureLevel {
  qualified,
  advanced;

  static DemoSignatureLevel? parse(Object? value) => switch (value) {
    'qualified' => qualified,
    'advanced' => advanced,
    _ => null,
  };
}

final stagingMobileClient = UaePassClient(
  UaePassConfiguration(
    environment: stagingEnvironment,
    clientId: stagingClientId,
    callbackScheme: stagingCallbackScheme,
    redirectUri: Uri.parse(
      const String.fromEnvironment(
        'UAEPASS_MOBILE_REDIRECT_URI',
        defaultValue: 'https://localhost:8000',
      ),
    ),
  ),
);
