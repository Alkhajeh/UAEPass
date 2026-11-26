import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uaepass_example/sign_in/backend_response.dart';
import 'package:uaepass_example/sign_in/local_backend.dart'
    if (dart.library.js_interop) 'package:uaepass_example/sign_in/browser_web.dart'
    as backend;
import 'package:uaepass_example/signing/signing_transaction.dart';
import 'package:uaepass_example/signing/staging_signing.dart';
import 'package:uaepass_example/staging_config.dart';

void main() {
  testWidgets(
    'web signing can reload the return before and after verification',
    (tester) async {
      const attempt = SigningTransaction(
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        DemoSignatureLevel.advanced,
      );
      addTearDown(backend.clearSigningReturn);
      backend.rememberApprovalTransaction(attempt);

      var checks = 0;
      Future<void> loadReturn() async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: const Scaffold(body: Text('Home')),
            initialRoute: StagingSigning.returnRouteName,
            routes: {
              StagingSigning.returnRouteName: (_) => StagingSigning(
                approvalReturnId: attempt.id,
                requestBackend:
                    (path, {required method, body, transactionToken}) async {
                      expect(method, 'POST');
                      expect(
                        path,
                        '/signing/app/transactions/${attempt.id}/check',
                      );
                      expect(transactionToken, attempt.token);
                      return BackendResponse(
                        200,
                        Uint8List.fromList(
                          utf8.encode(
                            jsonEncode({
                              'status': ++checks == 1 ? 'pending' : 'signed',
                              'signatureLevel': attempt.level.name,
                            }),
                          ),
                        ),
                      );
                    },
              ),
            },
          ),
        );
        await tester.pumpAndSettle();
      }

      await loadReturn();
      expect(find.text('Check signing result'), findsOneWidget);
      await loadReturn();
      expect(find.text('View signed PDF'), findsOneWidget);
      await loadReturn();
      expect(find.text('View signed PDF'), findsOneWidget);
      expect(checks, 3);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(backend.readApprovalTransaction(attempt.id), isNull);
    },
    skip: !kIsWeb,
  );
}
