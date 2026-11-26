import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uaepass/src/platform/browser.dart';
import 'package:uaepass/uaepass.dart';

const _path = '/trustedx-resources/esignsp/v2/ui';
final _staging = Uri.https('stg-id.uaepass.ae', _path, {
  'signerProcessId': 'sample-1',
});
const _client = UaePassSigningClient(environment: UaePassEnvironment.staging);

void main() {
  tearDown(() => UaePassBrowser.instance = null);

  Future<BuildContext> host(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (value) {
          context = value;
          return const SizedBox();
        },
      ),
    );
    return context;
  }

  final returnUri = Uri.https('service.example', '/signing/return');

  testWidgets('validates the environment, origin, route and process ID', (
    tester,
  ) async {
    final context = await host(tester);
    final browser = _Browser();
    UaePassBrowser.instance = browser;
    await _client.openApproval(context, _staging, finishCallbackUri: returnUri);
    expect(browser.destination, _staging);
    final production = _staging.replace(host: 'id.uaepass.ae');
    await const UaePassSigningClient(environment: UaePassEnvironment.production)
        .openApproval(context, production, finishCallbackUri: returnUri);
    expect(browser.destination, production);

    for (final invalid in [
      production,
      _staging.replace(scheme: 'http'),
      _staging.replace(host: 'stg-id.uaepass.ae.example'),
      _staging.replace(port: 8443),
      _staging.replace(userInfo: 'unexpected'),
      _staging.replace(fragment: 'unexpected'),
      _staging.replace(path: '$_path/other'),
      _staging.replace(query: ''),
      _staging.replace(query: 'signerProcessId='),
      _staging.replace(query: 'signerProcessId=first&signerProcessId=second'),
      _staging.replace(queryParameters: {'signerProcessId': 'x/y'}),
    ]) {
      await expectLater(
        _client.openApproval(context, invalid, finishCallbackUri: returnUri),
        throwsA(_launchFailure(UaePassSigningLaunchFailure.invalidApprovalUri)),
      );
    }
    expect(browser.destination, production);
  });

  testWidgets('validates the return URL and sanitizes navigation failures', (
    tester,
  ) async {
    final context = await host(tester);
    final browser = _Browser();
    UaePassBrowser.instance = browser;
    for (final invalid in [
      returnUri.replace(scheme: 'http'),
      returnUri.replace(userInfo: 'unexpected'),
      returnUri.replace(fragment: 'unexpected'),
      returnUri.replace(query: 'status=finished'),
    ]) {
      await expectLater(
        _client.openApproval(context, _staging, finishCallbackUri: invalid),
        throwsA(
          _launchFailure(UaePassSigningLaunchFailure.invalidFinishCallbackUri),
        ),
      );
    }
    expect(browser.destination, isNull);
    browser.fail = true;
    await expectLater(
      _client.openApproval(context, _staging, finishCallbackUri: returnUri),
      throwsA(
        _launchFailure(UaePassSigningLaunchFailure.launchFailed).having(
          (error) => error.toString(),
          'message',
          isNot(contains('sample-1')),
        ),
      ),
    );
  });
}

TypeMatcher<UaePassSigningLaunchException> _launchFailure(
  UaePassSigningLaunchFailure reason,
) => isA<UaePassSigningLaunchException>().having(
  (error) => error.reason,
  'reason',
  reason,
);

class _Browser implements UaePassBrowser {
  Uri? destination;
  bool fail = false;

  @override
  void navigate(Uri uri) {
    if (fail) throw StateError(uri.toString());
    destination = uri;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
