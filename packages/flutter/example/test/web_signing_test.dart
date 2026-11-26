@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

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

@JS('Storage.prototype')
external JSObject get _storagePrototype;

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
  expect(backend.rememberApprovalTransaction(_attempt), isTrue);
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

BackendResponse _signingResponse(Map<String, Object?> response) =>
    BackendResponse(200, Uint8List.fromList(utf8.encode(jsonEncode(response))));

BackendResponse _pendingApproval() => _signingResponse({
  'transactionId': _attempt.id,
  'status': 'pending',
  // Fail URL validation to keep the test in this document.
  'approvalUri': 'https://example.test/approval',
  'finishCallbackUri': 'http://localhost:8787/signing/finish',
});

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
                      return _signingResponse({
                        'status': ++checks == 1 ? 'pending' : 'signed',
                        'signatureLevel': _attempt.level.name,
                      });
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

  testWidgets('web approval can retry when saving the credential fails', (
    tester,
  ) async {
    _stageReturn();
    var starts = 0;
    var checks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StagingSigning(
          approvalReturnId: _attempt.id,
          requestBackend: (path, {required method, body, transactionToken}) async {
            expect(transactionToken, _attempt.token);
            expect(body, isNull);
            if (method == 'PUT') {
              expect(
                path,
                '/signing/app/transactions/${_attempt.id}?level=advanced&return=web',
              );
              starts++;
              return _pendingApproval();
            }
            expect(path, '/signing/app/transactions/${_attempt.id}/check');
            checks++;
            return _signingResponse({'status': 'pending'});
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    backend.clearSigningReturn();

    final resume = find.text('Return to UAE PASS');
    final method = 'setItem'.toJS;
    final original = _storagePrototype.getProperty<JSFunction>(method);
    void denyStorage(String _, String _) => throw StateError('Storage blocked');
    _storagePrototype.setProperty(method, denyStorage.toJS);
    try {
      await tester.tap(resume);
      await tester.pumpAndSettle();
      expect(starts, 1);
      expect(checks, 1);
      expect(find.textContaining('Allow site storage'), findsOneWidget);
      expect(resume, findsOneWidget);
      expect(backend.readApprovalTransaction(_attempt.id), isNull);
    } finally {
      _storagePrototype.setProperty(method, original);
    }

    await tester.tap(resume);
    await tester.pumpAndSettle();
    expect(starts, 2);
    expect(checks, 2);
    expect(find.textContaining('Allow site storage'), findsNothing);
    expect(backend.readApprovalTransaction(_attempt.id)?.token, _attempt.token);
  });

  testWidgets('returning home discards an in-flight approval response', (
    tester,
  ) async {
    _stageReturn();
    final approval = Completer<BackendResponse>();
    var resumes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(body: Text('Home')),
        initialRoute: StagingSigning.returnRouteName,
        routes: {
          StagingSigning.returnRouteName: (_) => StagingSigning(
            approvalReturnId: _attempt.id,
            requestBackend:
                (_, {required method, body, transactionToken}) async {
                  if (method == 'PUT') {
                    resumes++;
                    return approval.future;
                  }
                  return _signingResponse({'status': 'pending'});
                },
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
    final page = tester.state(find.byType(StagingSigning));
    await tester.tap(find.text('Return to UAE PASS'));
    await tester.pump();
    expect(resumes, 1);

    await tester.pageBack();
    // The outgoing route stays mounted while its pop transition animates.
    expect(page.mounted, isTrue);
    _expectReturnCleared();
    approval.complete(_pendingApproval());
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    _expectReturnCleared();
  });
}
