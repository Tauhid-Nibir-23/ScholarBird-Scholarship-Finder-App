import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> savePdf(Uint8List bytes, String filename) async {
  final url = html.Url.createObjectUrlFromBlob(
    html.Blob(<Object>[bytes], 'application/pdf'),
  );
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  Timer(const Duration(seconds: 1), () => html.Url.revokeObjectUrl(url));
}
