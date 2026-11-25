import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../platform/native_bridge.dart';
import 'flow.dart';
import 'result.dart';

class UaePassAuthorizationPage extends StatefulWidget {
  const UaePassAuthorizationPage({
    required this.flow,
    required this.state,
    required this.initialUri,
    required this.events,
    required this.platform,
    super.key,
  });

  final UaePassAuthorizationFlow flow;
  final String state;
  final Uri initialUri;
  final Stream<UaePassPlatformEvent> events;
  final UaePassPlatform platform;

  @override
  State<UaePassAuthorizationPage> createState() =>
      _UaePassAuthorizationPageState();
}

class _UaePassAuthorizationPageState extends State<UaePassAuthorizationPage> {
  static const _failed = UaePassFailure<UaePassAuthorizationGrant>(
    UaePassFailureReason.authorizationFailed,
  );

  late final StreamSubscription<UaePassPlatformEvent> _subscription;
  WebViewController? _webView;
  Uri? _loadingPage;
  UaePassAppHandoff? _pendingHandoff;
  bool _finished = false;

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
              _finish(_failed);
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
      _finish(_failed);
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
      _finish(_failed);
    }
  }

  void _handlePlatformEvent(UaePassPlatformEvent event) {
    switch (event) {
      case UaePassAppCallback(:final uri):
        unawaited(_resumeAuthentication(uri));
      case UaePassMainFrameHttpError(:final state) when state == widget.state:
        _finish(_failed);
      case UaePassMainFrameHttpError():
        break;
    }
  }

  Future<NavigationDecision> _handleNavigation(
    NavigationRequest request,
  ) async {
    if (_activeRoute == null) return NavigationDecision.prevent;
    if (!request.isMainFrame) return NavigationDecision.navigate;

    final uri = Uri.tryParse(request.url);
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

    _finish(_failed);
    return NavigationDecision.prevent;
  }

  bool _handleRedirect(Uri? uri) {
    if (uri == null) return false;
    final result = widget.flow.authorizationResult(uri, widget.state);
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
    _finish(_failed);
  }

  Future<void> _resumeAuthentication(String callback) async {
    final handoff = _pendingHandoff;
    final webView = _webView;
    if (handoff == null || webView == null || _activeRoute == null) return;

    final uri = Uri.tryParse(callback);
    if (uri == null || uri.scheme != widget.flow.configuration.callbackScheme) {
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
      _finish(_failed);
      return;
    }

    final destination = switch (uri.host) {
      'success' => handoff.successUri,
      'failure' => handoff.failureUri,
      _ => null,
    };
    if (destination == null) {
      _finish(_failed);
      return;
    }

    _pendingHandoff = null;
    try {
      await _loadPage(webView, destination);
    } on Exception {
      _finish(_failed);
    }
  }

  void _finish(UaePassResult<UaePassAuthorizationGrant> result) {
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
        title: Text(
          widget.flow.language == 'ar' ? 'الهوية الرقمية' : 'UAE PASS',
        ),
      ),
      body: webView == null
          ? const Center(child: CircularProgressIndicator())
          : WebViewWidget(controller: webView),
    );
  }
}
