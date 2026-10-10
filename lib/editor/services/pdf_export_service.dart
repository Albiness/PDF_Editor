import 'dart:io';
import 'dart:ui';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/annotation.dart';

class PdfExportService {

  static Future export(
      String path,
      List<Annotation> annotations) async {

    final doc = PdfDocument(
        inputBytes: await File(path).readAsBytes());

    final page = doc.pages[0];

    for (final a in annotations) {
      if (a.type == AnnotationType.text) {
        page.graphics.drawString(
          a.text ?? "",
          PdfStandardFont(
              PdfFontFamily.helvetica, 18),
          bounds: Rect.fromLTWH(
              a.position.dx,
              a.position.dy,
              200,
              50),
        );
      }
    }

    final bytes = await doc.save();

    await File(path).writeAsBytes(bytes);

    doc.dispose();
  }
}