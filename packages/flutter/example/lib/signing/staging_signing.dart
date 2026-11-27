import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uaepass/uaepass.dart';

import '../sign_in/backend_response.dart';
import '../sign_in/local_backend.dart'
    if (dart.library.js_interop) '../sign_in/browser_web.dart'
    as backend;
import '../sign_in/sandbox_sign_in.dart';
import '../staging_config.dart';
import 'signed_pdf_page.dart';
import 'signing_transaction.dart';

const _app = '/signing/app';

class StagingSigning extends StatefulWidget {
  const StagingSigning({
    super.key,
    this.webSandbox,
    this.approvalReturnId,
    this.requestBackend = backend.requestBackend,
    this.authorize,
  });

  static const routeName = '/sign-document';
  static const returnRouteName = '/sign-document-return';

  final WebSandbox? webSandbox;
  final String? approvalReturnId;
  final BackendRequest requestBackend;
  final Future<UaePassResult<UaePassAuthorizationGrant>> Function(BuildContext)?
  authorize;

  @override
  State<StagingSigning> createState() => _StagingSigningState();
}

class _StagingSigningState extends State<StagingSigning> {
  static const _signing = UaePassSigningClient(environment: stagingEnvironment);

  DemoSignatureLevel _signatureLevel = DemoSignatureLevel.qualified;
  SigningTransaction? _attempt;
  String? _status;
  String? _error;
  VoidCallback? _retry;
  UaePassResult<void>? _signInResult;
  bool _busy = false;
  bool _popped = false;

  bool get _active => mounted && !_popped;

  @override
  void initState() {
    super.initState();
    final web = widget.webSandbox;
    if (widget.approvalReturnId case final id?) {
      _attempt = backend.readApprovalTransaction(id);
      if (_attempt case final attempt?) {
        _signatureLevel = attempt.level;
        unawaited(_check());
      }
    } else if (web?.signingIntent case final attempt?) {
      _attempt = attempt;
      _signatureLevel = attempt.level;
      if (web?.takeAuthorization() case final authorization?) {
        unawaited(
          _run(() => _submitAuthorization(authorization), retry: _retryStart),
        );
      }
    } else {
      backend.clearSigningReturn();
    }
  }

  Future<void> _run(
    Future<void> Function() operation, {
    required VoidCallback retry,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _retry = null;
      _signInResult = null;
    });
    try {
      await operation();
    } on BackendConnectionException {
      if (_active) _showConnectionError(retry);
    } catch (_) {
      if (_active) setState(() => _error = 'unavailable');
    } finally {
      if (_active) setState(() => _busy = false);
    }
  }

  void _showConnectionError(VoidCallback retry) {
    setState(() => _retry = retry);
  }

  void _clearTransaction() {
    backend.clearSigningReturn();
    setState(() {
      _attempt = null;
      _status = null;
    });
  }

  void _showBackendError(BackendResponse response) {
    final error = response.json['error'] as String? ?? 'unavailable';
    if (response.status == 401 ||
        response.status == 404 ||
        error == 'invalid_authorization' ||
        error == 'ineligible') {
      _clearTransaction();
    }
    setState(() => _error = error);
  }

  Future<void> _start() => _run(_authorize, retry: _retryStart);

  Future<void> _retryStart() => _run(_requestSigning, retry: _retryStart);

  Future<void> _startAgain() => _run(() {
    _clearTransaction();
    return _authorize();
  }, retry: _retryStart);

  Future<void> _authorize() async {
    final attempt = _attempt ??= SigningTransaction.start(
      _signatureLevel,
      locale: Localizations.localeOf(context).languageCode == 'ar'
          ? 'ar'
          : 'en',
    );
    if (kIsWeb) {
      final result =
          widget.webSandbox?.startSigningAuthorization(
            Locale(attempt.locale),
            attempt,
          ) ??
          const UaePassFailure<void>(UaePassFailureReason.authorizationFailed);
      if (result is! UaePassSuccess<void>) {
        setState(() => _signInResult = result);
      }
      return;
    }
    final result = await (widget.authorize ?? stagingMobileClient.authorize)(
      context,
    );
    if (_active) await _submitAuthorization(result);
  }

  Future<void> _submitAuthorization(
    UaePassResult<UaePassAuthorizationGrant> result,
  ) async {
    if (result case UaePassSuccess(value: final grant)) {
      await _requestSigning(code: grant.code);
    } else {
      _clearTransaction();
      final message = await completeStagingSignIn(result, null);
      if (_active) setState(() => _signInResult = message);
    }
  }

  Future<void> _requestSigning({String? code}) async {
    final attempt = _attempt;
    if (attempt == null) return;
    final query =
        '?level=${attempt.level.name}&locale=${attempt.locale}'
        '${kIsWeb ? '&return=web' : ''}';
    final response = await widget.requestBackend(
      '$_app/transactions/${attempt.id}$query',
      method: 'PUT',
      body: code == null ? null : {'code': code},
      transactionToken: attempt.token,
    );
    if (!mounted || _popped) return;
    if (code == null &&
        response.status == 404 &&
        response.json['error'] == 'authorization_required' &&
        _status == null) {
      await _authorize();
      return;
    }
    if (response.status != 200) {
      _showBackendError(response);
      return;
    }
    final data = response.json;
    final id = data['transactionId'];
    if (id != attempt.id) {
      throw const FormatException('Invalid signing transaction.');
    }
    setState(() {
      _status = data['status'] as String?;
      _signatureLevel =
          DemoSignatureLevel.parse(data['signatureLevel']) ?? _signatureLevel;
    });
    final approvalUri = data['approvalUri'];
    var launchFailed = false;
    if (approvalUri is String) {
      final finishCallbackUri = data['finishCallbackUri'];
      if (finishCallbackUri is! String) {
        throw const FormatException('Missing signing return URL.');
      }
      if (kIsWeb && !backend.rememberApprovalTransaction(attempt)) {
        setState(() => _error = 'storage_unavailable');
        return;
      }
      try {
        await _signing.openApproval(
          context,
          Uri.parse(approvalUri),
          finishCallbackUri: Uri.parse(finishCallbackUri),
          callbackScheme: stagingCallbackScheme,
        );
      } on UaePassSigningLaunchException {
        launchFailed = true;
      }
    }
    if (_active && (!kIsWeb || launchFailed)) {
      try {
        await _refresh();
      } on BackendConnectionException {
        if (_active) _showConnectionError(_check);
      }
    }
    if (_active && launchFailed && _error == null && _status == 'pending') {
      setState(() => _error = 'unavailable');
    }
  }

  Future<void> _check() => _run(_refresh, retry: _check);

  Future<void> _refresh() async {
    final attempt = _attempt;
    if (attempt == null) return;
    final response = await widget.requestBackend(
      '$_app/transactions/${attempt.id}/check',
      method: 'POST',
      transactionToken: attempt.token,
    );
    if (!_active) return;
    if (response.status != 200) {
      _showBackendError(response);
      return;
    }
    final data = response.json;
    setState(() {
      _status = data['status'] as String?;
      _signatureLevel =
          DemoSignatureLevel.parse(data['signatureLevel']) ?? _signatureLevel;
    });
  }

  Future<void> _viewSignedPdf() => _run(() async {
    final attempt = _attempt;
    if (attempt == null) return;
    final response = await widget.requestBackend(
      '$_app/transactions/${attempt.id}/pdf',
      method: 'GET',
      transactionToken: attempt.token,
    );
    if (!mounted || _popped) return;
    if (response.status != 200) {
      _showBackendError(response);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            SignedPdfPage(bytes: response.bytes, transactionId: attempt.id),
      ),
    );
  }, retry: _viewSignedPdf);

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final ar = locale.languageCode == 'ar';
    String tr(String english, String arabic) => ar ? arabic : english;
    final signInResult = _signInResult;
    final message = _retry != null
        ? backendUnavailableMessage(ar)
        : switch (_error) {
            'invalid_authorization' => tr(
              'Authorization could not be completed. Select Sign with UAE PASS to try again.',
              'تعذّر إكمال التفويض. اختر التوقيع بالهوية الرقمية للمحاولة مرة أخرى.',
            ),
            'ineligible' => switch (_signatureLevel) {
              DemoSignatureLevel.qualified => tr(
                'Qualified signing requires an SOP3 staging account with a qualified certificate.',
                'يتطلب التوقيع المؤهل حسابًا تجريبيًا من المستوى الثالث (SOP3) وشهادة توقيع مؤهلة.',
              ),
              DemoSignatureLevel.advanced => tr(
                'Advanced signing requires an SOP2 or SOP3 staging account with an advanced certificate.',
                'يتطلب التوقيع المتقدم حسابًا تجريبيًا من المستوى الثاني أو الثالث (SOP2 أو SOP3) وشهادة توقيع متقدمة.',
              ),
            },
            'start-uncertain' => tr(
              'The signing request could not be confirmed.',
              'تعذّر تأكيد طلب التوقيع.',
            ),
            'storage_unavailable' => tr(
              'Allow site storage in your browser, then select Return to UAE PASS.',
              'اسمح بتخزين بيانات الموقع في المتصفح، ثم اختر العودة إلى الهوية الرقمية.',
            ),
            'unavailable' ||
            'start-failed' ||
            'level_conflict' ||
            'invalid_level' ||
            'locale_conflict' ||
            'invalid_locale' => tr(
              'The request could not be completed. Try again.',
              'تعذّر إكمال الطلب. حاول مرة أخرى.',
            ),
            _ => switch (_status) {
              'pending' || 'processing' => tr(
                'Waiting for the signing result.',
                'بانتظار نتيجة التوقيع.',
              ),
              'signed' => tr(
                'Signed PDF verified.',
                'تم التحقّق من المستند الموقّع.',
              ),
              'canceled' => tr('Signing was canceled.', 'تم إلغاء التوقيع.'),
              'failed' => tr(
                'Signing did not produce a verified PDF.',
                'لم ينتج عن التوقيع مستند تم التحقّق منه.',
              ),
              _ =>
                signInResult == null
                    ? null
                    : UaePassSignInMessages.forResult(
                        signInResult,
                        locale: locale,
                        serviceProviderName: demoServiceName(locale),
                      ),
            },
          };
    final page = Scaffold(
      appBar: AppBar(title: Text(tr('Sign a document', 'وقّع مستندًا'))),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (_status == null) ...[
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        tr(
                          'Open the document in UAE PASS before approving.',
                          'افتح المستند في الهوية الرقمية قبل الموافقة.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SegmentedButton<DemoSignatureLevel>(
                      segments: [
                        ButtonSegment(
                          value: DemoSignatureLevel.qualified,
                          label: Text(tr('Qualified', 'مؤهل')),
                        ),
                        ButtonSegment(
                          value: DemoSignatureLevel.advanced,
                          label: Text(tr('Advanced', 'متقدم')),
                        ),
                      ],
                      selected: {_signatureLevel},
                      onSelectionChanged: _busy || _error == 'start-uncertain'
                          ? null
                          : (selection) {
                              backend.clearSigningReturn();
                              setState(() {
                                _signatureLevel = selection.single;
                                _attempt = null;
                                _error = null;
                                _retry = null;
                                _signInResult = null;
                              });
                            },
                    ),
                    const SizedBox(height: 16),
                    if (_retry == null && _error != 'start-failed')
                      UaePassSigningButton(
                        onPressed: _busy || _error == 'start-uncertain'
                            ? null
                            : _start,
                      ),
                  ],
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Semantics(liveRegion: true, child: Text(message)),
                    ),
                  if (_retry case final retry?)
                    TextButton(
                      onPressed: _busy ? null : retry,
                      child: Text(tr('Retry', 'إعادة المحاولة')),
                    ),
                  if (_error == 'start-failed')
                    TextButton(
                      onPressed: _busy ? null : _retryStart,
                      child: Text(tr('Retry', 'إعادة المحاولة')),
                    ),
                  if (_retry == null &&
                      _attempt != null &&
                      _status == 'pending')
                    FilledButton(
                      onPressed: _busy ? null : _retryStart,
                      child: Text(
                        tr('Return to UAE PASS', 'العودة إلى الهوية الرقمية'),
                      ),
                    ),
                  if (_retry == null &&
                      _attempt != null &&
                      (_status != null || widget.approvalReturnId != null) &&
                      (_status == null ||
                          _status == 'pending' ||
                          _status == 'processing'))
                    TextButton(
                      onPressed: _busy ? null : _check,
                      child: Text(
                        tr('Check signing result', 'تحقّق من نتيجة التوقيع'),
                      ),
                    ),
                  if (_retry == null &&
                      _status == 'canceled' &&
                      _error != 'start-uncertain')
                    FilledButton(
                      onPressed: _busy ? null : _startAgain,
                      child: Text(tr('Start again', 'ابدأ من جديد')),
                    ),
                  if (_retry == null && _status == 'signed')
                    FilledButton(
                      onPressed: _busy ? null : _viewSignedPdf,
                      child: Text(tr('View signed PDF', 'عرض المستند الموقّع')),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        _popped = true;
        backend.clearSigningReturn();
      },
      child: page,
    );
  }
}
