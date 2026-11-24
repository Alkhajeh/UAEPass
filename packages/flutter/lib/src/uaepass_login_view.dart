import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'helper.dart';

class UaepassLoginView extends StatefulWidget {
  const UaepassLoginView({
    required this.flow,
    required this.callbacks,
    super.key,
  });

  final UaepassAuthFlow flow;
  final Stream<String> callbacks;

  @override
  State<UaepassLoginView> createState() => _UaepassLoginViewState();
}

class _UaepassLoginViewState extends State<UaepassLoginView> {
  static const _failed = (status: UaepassWebViewStatus.failed, code: null);

  late final String _state;
  late final StreamSubscription<String> _callbackSubscription;
  WebViewController? _webView;
  UaepassAppHandoff? _pendingHandoff;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    final random = Random.secure();
    _state = base64UrlEncode(List.generate(32, (_) => random.nextInt(256)));
    _callbackSubscription = widget.callbacks.listen(_resumeAuthentication);
    unawaited(_start());
  }

  @override
  void dispose() {
    unawaited(_callbackSubscription.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final url = await widget.flow.getLoginUrl(_state);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;

      final webView = WebViewController();
      await webView.setJavaScriptMode(JavaScriptMode.unrestricted);
      await webView.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _handleNavigation,
          onPageStarted: (url) => _handleRedirect(Uri.tryParse(url)),
          onWebResourceError: (error) {
            final url = Uri.tryParse(error.url ?? '');
            if (error.isForMainFrame == true &&
                _pendingHandoff == null &&
                (url == null || !widget.flow.isUaePassHandoff(url))) {
              _finish(_failed);
            }
          },
        ),
      );
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      setState(() => _webView = webView);
      await webView.loadRequest(url);
    } on Exception {
      _finish(_failed);
    }
  }

  Future<NavigationDecision> _handleNavigation(
    NavigationRequest request,
  ) async {
    if (!request.isMainFrame) return NavigationDecision.navigate;
    if (_finished || !mounted) return NavigationDecision.prevent;

    final url = Uri.tryParse(request.url);
    if (url == null || _handleRedirect(url)) return NavigationDecision.prevent;
    if (widget.flow.isUaePassHandoff(url)) {
      await _launchUaePass(url);
      return NavigationDecision.prevent;
    }

    if (url.scheme == 'https' &&
        url.port == 443 &&
        url.userInfo.isEmpty &&
        (url.host == 'uaepass.ae' || url.host.endsWith('.uaepass.ae'))) {
      return NavigationDecision.navigate;
    }
    _finish(_failed);
    return NavigationDecision.prevent;
  }

  bool _handleRedirect(Uri? url) {
    if (url == null) return false;
    final result = widget.flow.authorizationResult(url, _state);
    if (result == null) return false;
    _finish(result);
    return true;
  }

  Future<void> _launchUaePass(Uri url) async {
    if (_pendingHandoff != null) return;
    final handoff = widget.flow.appHandoff(url, _state);
    if (handoff != null) {
      _pendingHandoff = handoff;
      try {
        if (await launchUrl(
          handoff.appUrl,
          mode: LaunchMode.externalApplication,
        )) {
          return;
        }
      } on Exception {
        // The attempt failed to launch the UAE PASS app.
      }
    }
    _finish(_failed);
  }

  Future<void> _resumeAuthentication(String callback) async {
    final handoff = _pendingHandoff;
    final webView = _webView;
    if (_finished || handoff == null || webView == null) return;

    final url = Uri.tryParse(callback);
    if (url == null ||
        url.scheme != widget.flow.appScheme ||
        url.userInfo.isNotEmpty ||
        url.hasPort ||
        (url.path.isNotEmpty && url.path != '/') ||
        url.hasFragment) {
      return;
    }
    final state = url.queryParametersAll['state'];
    if (state == null || state.length != 1 || state.single != _state) return;
    final destination = switch (url.host) {
      'success' => handoff.successUrl,
      'failure' => handoff.failureUrl,
      _ => null,
    };
    if (destination == null) return;
    _pendingHandoff = null;
    try {
      await webView.loadRequest(destination);
    } on Exception {
      _finish(_failed);
    }
  }

  void _finish(UaepassWebViewResult result) {
    if (_finished || !mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _finished = true;
    _pendingHandoff = null;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final webView = _webView;
    return Scaffold(
      appBar: AppBar(title: const Text('UAE PASS')),
      body: webView == null
          ? const Center(child: CircularProgressIndicator())
          : WebViewWidget(controller: webView),
    );
  }
}
