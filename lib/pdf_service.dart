import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfService {
  /// Gera os bytes do documento PDF formatado para serem exibidos na tela
  static Future<Uint8List> generateSummaryPdf(PdfPageFormat format, String summaryText) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
                level: 0,
                child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                          'Resumo de Estudo',
                          style: pw.TextStyle(
                              fontSize: 24,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.indigo900
                          )
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                          'Gerado por ScanLearn.ai',
                          style: const pw.TextStyle(
                              fontSize: 12,
                              color: PdfColors.grey700
                          )
                      ),
                    ]
                )
            ),
            pw.SizedBox(height: 16),
            pw.Paragraph(
              text: summaryText,
              style: const pw.TextStyle(fontSize: 12, lineSpacing: 1.5),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }
}