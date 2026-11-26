import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../authorization/flow.dart';
import '../localization/locale.dart';
import '../signing/review_document_page.dart';
import 'native_bridge.dart';

bool _webViewInProgress = false;

// UAE PASS uses one native callback channel for the WebViews on this isolate.
Future<T?> openUaePassWebView<T extends Object>(
  BuildContext context, {
  required UaePassAppFlow flow,
  required FutureOr<Uri> Function(String state, UaePassPlatform platform)
  initialUri,
  required T? Function(Uri uri, String state) onRedirect,
  required T failure,
  bool Function(Uri uri)? isReviewDocument,
  Locale? locale,
}) async {
  if (!context.mounted) return null;
  if (_webViewInProgress) return failure;
  final language = resolveUaePassLocale(context, locale).languageCode;
  _webViewInProgress = true;
  final platform = UaePassPlatform();
  final events = StreamController<UaePassPlatformEvent>();

  try {
    final state = generateUaePassState();
    platform.setEventHandler(events.add);
    await platform.setCallbackScheme(flow.callbackScheme);
    final uri = await initialUri(state, platform);
    if (!context.mounted) return null;

    final route = MaterialPageRoute<T>(
      fullscreenDialog: true,
      builder: (_) => _UaePassWebViewPage(
        flow: flow,
        state: state,
        initialUri: uri,
        events: events.stream,
        platform: platform,
        language: language,
        onRedirect: onRedirect,
        failure: failure,
        isReviewDocument: isReviewDocument,
      ),
    );
    return await Future.any([
      Navigator.of(context).push(route),
      route.completed,
    ]);
  } on Exception {
    return failure;
  } finally {
    platform.setEventHandler(null);
    unawaited(events.close());
    try {
      await platform.setCallbackScheme(null);
    } on PlatformException {
      // The platform may have detached before the route closed.
    } on MissingPluginException {
      // The platform may not support UAE PASS.
    } finally {
      _webViewInProgress = false;
    }
  }
}

class _UaePassWebViewPage<T extends Object> extends StatefulWidget {
  const _UaePassWebViewPage({
    required this.flow,
    required this.state,
    required this.initialUri,
    required this.events,
    required this.platform,
    required this.language,
    required this.onRedirect,
    required this.failure,
    required this.isReviewDocument,
  });

  final UaePassAppFlow flow;
  final String state;
  final Uri initialUri;
  final Stream<UaePassPlatformEvent> events;
  final UaePassPlatform platform;
  final String language;
  final T? Function(Uri uri, String state) onRedirect;
  final T failure;
  final bool Function(Uri uri)? isReviewDocument;

  @override
  State<_UaePassWebViewPage<T>> createState() => _UaePassWebViewPageState<T>();
}

class _UaePassWebViewPageState<T extends Object>
    extends State<_UaePassWebViewPage<T>> {
  late final StreamSubscription<UaePassPlatformEvent> _subscription;
  WebViewController? _webView;
  Uri? _loadingPage;
  UaePassAppHandoff? _pendingHandoff;
  bool _finished = false;
  bool _reviewOpen = false;

  ModalRoute<dynamic>? get _activeRoute {
    if (!mounted || _finished) return null;
    final route = ModalRoute.of(context);
    return route != null && route.isActive ? route : null;
  }

  @override
  void initState() {
    super.initState();
    _subscription = widget.events.listen(_handlePlatformEvent);
    // A synchronous setup failure must finish after the route's first build.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    if (_activeRoute == null) return;
    try {
      final webView = WebViewController();
      final webKit = webView.platform is WebKitWebViewController;
      await webView.setJavaScriptMode(JavaScriptMode.unrestricted);
      await webView.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _handleNavigation,
          onPageStarted: (url) {
            final uri = Uri.tryParse(url);
            if (_handleRedirect(uri)) return;
            _loadingPage = uri?.removeFragment();
          },
          onPageFinished: (url) {
            if (Uri.tryParse(url)?.removeFragment() == _loadingPage) {
              _loadingPage = null;
            }
          },
          onHttpError: webKit ? null : _handleHttpError,
          onWebResourceError: (error) {
            final uri = Uri.tryParse(error.url ?? '');
            if (error.isForMainFrame == true &&
                _pendingHandoff == null &&
                (uri == null || !widget.flow.isAppHandoff(uri))) {
              _finish(widget.failure);
            }
          },
        ),
      );
      if (_activeRoute == null) return;
      if (webView.platform case final WebKitWebViewController controller) {
        await widget.platform.observeMainFrameHttpErrors(
          controller.webViewIdentifier,
          widget.state,
        );
        if (_activeRoute == null) return;
      }
      setState(() => _webView = webView);
      await _loadPage(webView, widget.initialUri);
    } catch (_) {
      _finish(widget.failure);
    }
  }

  Future<void> _loadPage(WebViewController webView, Uri uri) {
    _loadingPage = uri.removeFragment();
    return webView.loadRequest(uri);
  }

  void _handleHttpError(HttpResponseError error) {
    final status = error.response?.statusCode;
    final uri = error.request?.uri ?? error.response?.uri;
    // Android's Flutter delegate provides the request URL without a frame flag.
    if (status != null &&
        status >= 400 &&
        status < 600 &&
        uri != null &&
        uri.removeFragment() == _loadingPage) {
      _finish(widget.failure);
    }
  }

  void _handlePlatformEvent(UaePassPlatformEvent event) {
    switch (event) {
      case UaePassAppCallback(:final uri):
        unawaited(_resumeAuthentication(uri));
      case UaePassMainFrameHttpError(:final state) when state == widget.state:
        _finish(widget.failure);
      case UaePassMainFrameHttpError():
        break;
    }
  }

  Future<NavigationDecision> _handleNavigation(
    NavigationRequest request,
  ) async {
    if (_activeRoute == null) return NavigationDecision.prevent;
    final uri = Uri.tryParse(request.url);
    if (uri != null && widget.isReviewDocument?.call(uri) == true) {
      unawaited(_openReview(uri));
      return NavigationDecision.prevent;
    }
    if (!request.isMainFrame) return NavigationDecision.navigate;

    if (uri != null) {
      if (_handleRedirect(uri)) return NavigationDecision.prevent;
      if (widget.flow.isAppHandoff(uri)) {
        await _launchUaePass(uri);
        return NavigationDecision.prevent;
      }
      if (widget.flow.isProviderPage(uri)) {
        _loadingPage = uri.removeFragment();
        return NavigationDecision.navigate;
      }
    }

    _finish(widget.failure);
    return NavigationDecision.prevent;
  }

  Future<void> _openReview(Uri uri) async {
    final webView = _webView;
    if (_reviewOpen || webView == null) return;
    _reviewOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReviewDocumentPage(
            language: widget.language,
            loadDocument: () =>
                fetchApprovalPdf(webView, uri, widget.initialUri),
          ),
        ),
      );
    } finally {
      _reviewOpen = false;
    }
  }

  bool _handleRedirect(Uri? uri) {
    if (uri == null) return false;
    final result = widget.onRedirect(uri, widget.state);
    if (result == null) return false;
    _finish(result);
    return true;
  }

  Future<void> _launchUaePass(Uri uri) async {
    if (_pendingHandoff != null) return;
    final handoff = widget.flow.appHandoff(uri, widget.state);
    if (handoff != null) {
      _pendingHandoff = handoff;
      try {
        if (await widget.platform.launchApp(handoff.appUri)) return;
      } on Exception {
        // Treat an app launch error like a rejected launch.
      }
    }
    _finish(widget.failure);
  }

  Future<void> _resumeAuthentication(String callback) async {
    final handoff = _pendingHandoff;
    final webView = _webView;
    if (handoff == null || webView == null || _activeRoute == null) return;

    final uri = Uri.tryParse(callback);
    if (uri == null || uri.scheme != widget.flow.callbackScheme) {
      return;
    }

    // An unsolicited intent without the attempt state cannot end the flow.
    final state = readUaePassQuery(uri)?['state'];
    if (state == null || !state.contains(widget.state)) return;
    if (state.length != 1 ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasFragment) {
      _finish(widget.failure);
      return;
    }

    final destination = switch (uri.host) {
      'success' => handoff.successUri,
      'failure' => handoff.failureUri,
      _ => null,
    };
    if (destination == null) {
      _finish(widget.failure);
      return;
    }

    _pendingHandoff = null;
    try {
      await _loadPage(webView, destination);
    } on Exception {
      _finish(widget.failure);
    }
  }

  void _finish(T result) {
    final route = _activeRoute;
    if (route == null) return;

    _finished = true;
    _pendingHandoff = null;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop(result);
    } else {
      navigator.removeRoute(route, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final webView = _webView;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.language == 'ar' ? 'الهوية الرقمية' : 'UAE PASS'),
      ),
      body: webView == null
          ? const Center(child: CircularProgressIndicator())
          : WebViewWidget(controller: webView),
    );
  }
}
