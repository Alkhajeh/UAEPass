@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uaepass_example/main.dart';
import 'package:uaepass_example/sign_in/backend_response.dart';
import 'package:uaepass_example/sign_in/browser_web.dart' as backend;
import 'package:uaepass_example/sign_in/sandbox_sign_in.dart';
import 'package:uaepass_example/signing/signing_transaction.dart';
import 'package:uaepass_example/signing/staging_signing.dart';
import 'package:uaepass_example/staging_config.dart';
import 'package:web/web.dart' as web;

const _attempt = SigningTransaction(
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  DemoSignatureLevel.advanced,
);

void _setLocation(Uri uri) => web.window.history.replaceState(
  web.window.history.state,
  '',
  uri.toString(),
);

void _stageReturn() {
  final original = Uri.base;
  addTearDown(() {
    backend.clearSigningReturn();
    _setLocation(original);
  });
  backend.rememberApprovalTransaction(_attempt);
  _setLocation(
    original.replace(
      queryParameters: {
        ...original.queryParametersAll,
        'signing': 'return',
        'transaction': _attempt.id,
        'fixture': ['one', 'two'],
      },
    ),
  );
}

void _expectReturnCleared() {
  expect(backend.readApprovalTransaction(_attempt.id), isNull);
  expect(Uri.base.queryParameters, isNot(contains('signing')));
  expect(Uri.base.queryParameters, isNot(contains('transaction')));
  expect(Uri.base.queryParametersAll['fixture'], ['one', 'two']);
}

void main() {
  testWidgets(
    'web signing can reload the return before and after verification',
    (tester) async {
      _stageReturn();
      final webSandbox = WebSandbox(null);
      final wasEnabled = webSandbox.backendEnabled;
      webSandbox.saveBackendEnabled(true);
      addTearDown(() => webSandbox.saveBackendEnabled(wasEnabled));

      var checks = 0;
      Future<void> loadReturn() async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: const Scaffold(body: Text('Home')),
            initialRoute: StagingSigning.returnRouteName,
            routes: {
              StagingSigning.returnRouteName: (_) => StagingSigning(
                approvalReturnId: Uri.base.queryParameters['transaction'],
                requestBackend:
                    (path, {required method, body, transactionToken}) async {
                      expect(method, 'POST');
                      expect(
                        path,
                        '/signing/app/transactions/${_attempt.id}/check',
                      );
                      expect(transactionToken, _attempt.token);
                      return BackendResponse(
                        200,
                        Uint8List.fromList(
                          utf8.encode(
                            jsonEncode({
                              'status': ++checks == 1 ? 'pending' : 'signed',
                              'signatureLevel': _attempt.level.name,
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
      _expectReturnCleared();

      await tester.pumpWidget(UaePassDemo(webSandbox: webSandbox));
      await tester.pumpAndSettle();
      expect(find.text('UAE PASS example'), findsOneWidget);
      expect(find.byType(StagingSigning), findsNothing);
    },
  );

  testWidgets('changing level abandons an unavailable approval return', (
    tester,
  ) async {
    _stageReturn();
    await tester.pumpWidget(
      MaterialApp(
        home: StagingSigning(
          approvalReturnId: _attempt.id,
          requestBackend: (_, {required method, body, transactionToken}) async {
            throw const BackendConnectionException();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Qualified'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    _expectReturnCleared();
  });
}
