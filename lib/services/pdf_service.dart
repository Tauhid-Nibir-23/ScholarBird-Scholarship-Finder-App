import 'package:flutter/services.dart';

import 'pdf_download.dart';

class PdfService {
  static const _guideAsset = 'assets/pdfs/ScholarBird-User-Guide.pdf';
  static const _downloadName = 'ScholarBird-User-Guide.pdf';

  /// Downloads the professionally prepared guide bundled with the app.
  static Future<void> downloadUserGuide() async {
    final asset = await rootBundle.load(_guideAsset);
    await savePdf(asset.buffer.asUint8List(), _downloadName);
  }
}
