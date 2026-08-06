/// Provides access to the bundled user guide PDF download flow.
import 'package:flutter/services.dart';

import 'pdf_download.dart';

/// Loads the packaged guide asset and hands it to the platform-specific saver.
class PdfService {
  static const _guideAsset = 'assets/pdfs/ScholarBird-User-Guide.pdf';
  static const _downloadName = 'ScholarBird-User-Guide.pdf';

  /// Downloads the professionally prepared guide bundled with the app.
  ///
  /// The guide is loaded from assets and saved through the web/native adapter.
  static Future<void> downloadUserGuide() async {
    final asset = await rootBundle.load(_guideAsset);
    await savePdf(asset.buffer.asUint8List(), _downloadName);
  }
}
