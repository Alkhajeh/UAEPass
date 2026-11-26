import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _maxPdfBytes = 10 * 1024 * 1024;

Future<Uint8List> fetchApprovalPdf(
  WebViewController webView,
  Uri documentUri,
  Uri approvalUri,
) async {
  final client = http.Client();
  try {
    return await (() async {
      final cookies = await WebViewCookieManager().getCookies(
        domain: documentUri,
      );
      final matchingCookies = cookies.where((cookie) {
        final path = cookie.path;
        return documentUri.path == path ||
            documentUri.path.startsWith(path.endsWith('/') ? path : '$path/');
      }).toList()..sort((a, b) => b.path.length.compareTo(a.path.length));
      final userAgent = await webView.getUserAgent();
      final request = http.Request('GET', documentUri)
        ..followRedirects = false
        ..headers.addAll({
          'Accept': 'application/pdf',
          'Referer': approvalUri.toString(),
          'User-Agent': ?userAgent,
          if (matchingCookies.isNotEmpty)
            'Cookie': matchingCookies
                .map((cookie) => '${cookie.name}=${cookie.value}')
                .join('; '),
        });
      final response = await client.send(request);
      final mime = response.headers['content-type']?.split(';').first.trim();
      if (response.statusCode != 200 ||
          mime?.toLowerCase() != 'application/pdf' ||
          (response.contentLength ?? 0) > _maxPdfBytes) {
        throw const FormatException('Invalid UAE PASS PDF response.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (chunk.length > _maxPdfBytes - bytes.length) {
          throw const FormatException(
            'The UAE PASS PDF exceeds the size limit.',
          );
        }
        bytes.add(chunk);
      }
      final pdf = bytes.takeBytes();
      if (pdf.length < 5 || String.fromCharCodes(pdf.take(5)) != '%PDF-') {
        throw const FormatException('Invalid UAE PASS PDF.');
      }
      return pdf;
    })().timeout(const Duration(seconds: 20));
  } finally {
    client.close();
  }
}

class ReviewDocumentPage extends StatefulWidget {
  const ReviewDocumentPage({
    super.key,
    required this.loadDocument,
    required this.language,
  });

  final Future<Uint8List> Function() loadDocument;
  final String language;

  @override
  State<ReviewDocumentPage> createState() => _ReviewDocumentPageState();
}

class _ReviewDocumentPageState extends State<ReviewDocumentPage> {
  late final _document = widget.loadDocument();

  @override
  Widget build(BuildContext context) {
    final ar = widget.language == 'ar';
    final error = Center(
      child: Text(
        ar ? 'تعذّر فتح المستند.' : 'The document could not be opened.',
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(ar ? 'مراجعة المستند' : 'Review document')),
      body: SafeArea(
        child: FutureBuilder<Uint8List>(
          future: _document,
          builder: (context, snapshot) {
            if (snapshot.hasError) return error;
            final bytes = snapshot.data;
            if (bytes == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return PdfViewer.data(
              bytes,
              sourceName: 'UAE PASS document',
              params: PdfViewerParams(
                errorBannerBuilder: (_, _, _, _) => error,
              ),
            );
          },
        ),
      ),
    );
  }
}
