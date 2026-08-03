import 'dart:typed_data';
import 'package:printing/printing.dart';

Future<void> savePdf(Uint8List bytes, String filename) =>
    Printing.sharePdf(bytes: bytes, filename: filename);
