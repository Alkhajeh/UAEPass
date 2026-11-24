import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../uaepass.dart';
import 'helper.dart';

class UaepassLoginView extends StatefulWidget {
  const UaepassLoginView({super.key});

  @override
  State<UaepassLoginView> createState() => _UaepassLoginViewState();
}

class _UaepassLoginViewState extends State<UaepassLoginView> {
  final _channel = MethodChannel(
    '${Uaepass.instance.appScheme}.uaepass/channel',
  );
  late final String _state;
  late final Future<Uri> _loginUrl;
  InAppWebViewController? _webView;
  UaePassAuthUrl? _pendingHandoff;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    final random = Random.secure();
    _state = base64UrlEncode(List.generate(32, (_) => random.nextInt(256)));
    _loginUrl = Helper.getLoginUrl(_state);
    _channel.setMethodCallHandler(_resumeAuthentication);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _resumeAuthentication(MethodCall call) async {
    final handoff = _pendingHandoff;
    final webView = _webView;
    final arguments = call.arguments;
    if (_finished ||
        handoff == null ||
        webView == null ||
        call.method != 'didRecieveTranscript' ||
        arguments is! String) {
      return;
    }

    final url = Uri.tryParse(arguments);
    if (url == null ||
        url.scheme != Uaepass.instance.appScheme ||
        url.queryParameters['state'] != _state) {
      return;
    }

    final destination = switch (url.host) {
      'success' => handoff.successUrl,
      'failure' => handoff.failureUrl,
      _ => null,
    };
    if (destination == null) return;
    _pendingHandoff = null;
    await webView.loadUrl(urlRequest: URLRequest(url: WebUri.uri(destination)));
  }

  bool _completeAuthorization(Uri url) {
    if (!Helper.isAuthorizationRedirect(url)) return false;
    if (_finished || !mounted) return true;
    _finished = true;

    final parameters = url.queryParameters;
    final code = parameters['code'];
    final validState = parameters['state'] == _state;
    if (validState && code != null && code.isNotEmpty) {
      Navigator.pop(context, code);
    } else {
      _showMessage(
        validState && parameters['error'] == 'access_denied'
            ? 'UAE PASS sign-in was cancelled.'
            : 'UAE PASS returned an invalid sign-in response.',
      );
      Navigator.pop(context);
    }
    return true;
  }

  void _showMessage(String message) {
    if (Uaepass.instance.showMessages && mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _launchUaePass(Uri url) async {
    if (_pendingHandoff != null) return;
    final handoff = Helper.getUaePassOpenUrl(url, _state);
    if (handoff != null) {
      _pendingHandoff = handoff;
      try {
        if (await launchUrl(
          handoff.appUrl,
          mode: LaunchMode.externalApplication,
        )) {
          return;
        }
      } on PlatformException {
        // Show the same message for a platform failure or a rejected launch.
      }
      _pendingHandoff = null;
    }
    _showMessage('Could not open the UAE PASS app.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF55C9B2),
        foregroundColor: Colors.black,
        title: const Text('UAE Pass'),
      ),
      body: FutureBuilder<Uri>(
        future: _loginUrl,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Could not start UAE PASS sign-in.'),
            );
          }
          final url = snapshot.data;
          if (url == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri.uri(url)),
            initialSettings: InAppWebViewSettings(
              cacheEnabled: false,
              transparentBackground: true,
              useShouldOverrideUrlLoading: true,
              supportZoom: false,
            ),
            onWebViewCreated: (controller) => _webView = controller,
            onLoadStart: (controller, url) {
              if (url != null && _completeAuthorization(url)) {
                controller.stopLoading();
              }
            },
            shouldOverrideUrlLoading: (controller, action) async {
              final url = action.request.url;
              if (!action.isForMainFrame || url == null) {
                return NavigationActionPolicy.ALLOW;
              }
              if (_completeAuthorization(url)) {
                return NavigationActionPolicy.CANCEL;
              }
              if (Helper.isUaePassHandoff(url)) {
                await _launchUaePass(url);
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
            onReceivedError: (controller, request, error) {
              if (request.isForMainFrame == true && !_finished) {
                _showMessage('Could not load the UAE PASS sign-in page.');
              }
            },
          );
        },
      ),
    );
  }
}
