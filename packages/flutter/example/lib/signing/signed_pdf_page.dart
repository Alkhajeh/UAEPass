import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

class SignedPdfPage extends StatelessWidget {
  const SignedPdfPage({
    super.key,
    required this.bytes,
    required this.transactionId,
  });

  final Uint8List bytes;
  final String transactionId;

  Future<void> _share(BuildContext context, String errorMessage) async {
    final box = context.findRenderObject() as RenderBox?;
    final bounds = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
          fileNameOverrides: const ['signed-staging-test.pdf'],
          sharePositionOrigin: bounds,
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Scaffold(
      appBar: AppBar(
        title: Text(ar ? 'المستند الموقّع' : 'Signed PDF'),
        actions: [
          Builder(
            builder: (buttonContext) => IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: ar ? 'حفظ أو مشاركة المستند' : 'Save or share PDF',
              onPressed: () => _share(
                buttonContext,
                ar
                    ? 'تعذّر حفظ المستند أو مشاركته.'
                    : 'The PDF could not be saved or shared.',
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: PdfViewer.data(
          bytes,
          sourceName: 'signed-$transactionId.pdf',
          params: PdfViewerParams(
            errorBannerBuilder: (_, _, _, _) => Center(
              child: Text(
                ar
                    ? 'تعذّر فتح المستند الموقّع.'
                    : 'The signed PDF could not be opened.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
