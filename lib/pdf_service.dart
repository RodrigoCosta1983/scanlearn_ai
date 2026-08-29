/*
|--------------------------------------------------------------------------
| EDUCA+.AI — SERVIÇO DE GERAÇÃO DE PDF
|--------------------------------------------------------------------------
|
| Arquivo responsável por transformar o resumo estruturado produzido
| pela Inteligência Artificial em um material de estudo em PDF.
|
| Principais responsabilidades:
|
| • Criar o documento PDF.
| • Renderizar título e visão geral.
| • Organizar as seções do resumo.
| • Exibir pontos-chave.
| • Inserir imagens reaproveitadas do material.
| • Renderizar os recortes preparados pelo sistema.
| • Criar visualmente:
|     - linhas do tempo;
|     - tabelas comparativas;
|     - hierarquias;
|     - fluxos;
|     - cards educacionais.
| • Manter título + visual + legenda juntos na paginação.
| • Gerar a seção de revisão rápida.
| • Utilizar fontes compatíveis com caracteres Unicode.
| • Aplicar identidade visual consistente ao material.
|
| Objetivo:
|
| Transformar o conteúdo enviado pelo aluno em uma apostila de estudo
| clara, organizada e visualmente didática, evitando imagens meramente
| decorativas e priorizando recursos que facilitem a compreensão.
|
| Versão atual:
| Resumo Visual V2-B.1
|
|--------------------------------------------------------------------------
*/



import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'study_summary.dart';

class PdfService {
  // V2-B.1 — fonte Unicode real. Noto Sans preserva acentos, travessões,
  // símbolos e demais caracteres do resumo sem depender das fontes base do PDF.
  static Future<pw.ThemeData> _loadPdfTheme() async {
    try {
      final regular = await PdfGoogleFonts.notoSansRegular();
      final bold = await PdfGoogleFonts.notoSansBold();
      return pw.ThemeData.withFont(base: regular, bold: bold);
    } catch (_) {
      // Fallback defensivo: o PDF continua sendo gerado mesmo se a fonte remota
      // estiver temporariamente indisponível.
      return pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      );
    }
  }

  /// Mantém compatibilidade com telas que ainda enviam texto puro,
  /// como o Guia para os Pais nesta fase do projeto.
  static Future<Uint8List> generateSummaryPdf(
    PdfPageFormat format,
    String summaryText,
  ) async {
    final pdf = pw.Document();
    final pdfTheme = await _loadPdfTheme();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        theme: pdfTheme,
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
                      color: PdfColors.indigo900,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Gerado por Educa+.ai',
                    style: const pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Paragraph(
              text: summaryText,
              style: const pw.TextStyle(fontSize: 16, lineSpacing: 1.5),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static String _pdfSafe(String value) {
    // Com Noto Sans, não precisamos degradar travessões, setas ou aspas.
    // Remove somente NUL, que não possui utilidade textual no resumo.
    return value.replaceAll('\u0000', '');
  }

  static String _cleanHeading(String value) {
    var result = value.trim();
    final prefix = RegExp(r'^\d+(?:\.\d+)*[\.)]\s*');
    while (prefix.hasMatch(result)) {
      result = result.replaceFirst(prefix, '').trimLeft();
    }
    return _pdfSafe(result);
  }

  /// V2-B.1 — bloco visual atômico. O Container externo não é um widget
  /// paginável; assim título + visual + legenda + procedência avançam juntos
  /// para a próxima página quando não houver espaço suficiente.
  static pw.Widget _visualTitleAndCaption(
    SummarySection section,
    pw.Widget content, {
    String footerNote = '',
  }) {
    return pw.Container(
      width: double.infinity,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (section.visualTitle.trim().isNotEmpty) ...[
            pw.Text(
              _pdfSafe(section.visualTitle),
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue900,
              ),
            ),
            pw.SizedBox(height: 6),
          ],
          content,
          if (section.visualCaption.trim().isNotEmpty) ...[
            pw.SizedBox(height: 5),
            pw.Text(
              _pdfSafe(section.visualCaption),
              style: const pw.TextStyle(
                fontSize: 9.5,
                color: PdfColors.grey800,
                lineSpacing: 1.2,
              ),
            ),
          ],
          if (footerNote.trim().isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              _pdfSafe(footerNote),
              style: const pw.TextStyle(
                fontSize: 8.5,
                color: PdfColors.grey600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _timelineVisual(SummarySection section) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.blue200),
      ),
      child: pw.Column(
        children: List<pw.Widget>.generate(
          section.generatedVisualElements.length,
          (index) {
            final item = section.generatedVisualElements[index];
            return pw.Padding(
              padding: pw.EdgeInsets.only(
                bottom: index == section.generatedVisualElements.length - 1 ? 0 : 8,
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 25,
                    height: 25,
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.indigo100,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColors.indigo300),
                    ),
                    child: pw.Text(
                      '${index + 1}',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.indigo900,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          _pdfSafe(item.label),
                          style: pw.TextStyle(
                            fontSize: 10.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if (item.description.trim().isNotEmpty)
                          pw.Text(
                            _pdfSafe(item.description),
                            style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 1.2),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static pw.Widget _comparisonVisual(SummarySection section) {
    final left = section.generatedVisualLeftTitle.trim().isEmpty
        ? 'A'
        : _pdfSafe(section.generatedVisualLeftTitle);
    final right = section.generatedVisualRightTitle.trim().isEmpty
        ? 'B'
        : _pdfSafe(section.generatedVisualRightTitle);

    pw.Widget cell(String text, {bool header = false}) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(6),
        color: header ? PdfColors.indigo50 : null,
        child: pw.Text(
          _pdfSafe(text),
          style: pw.TextStyle(
            fontSize: header ? 9.5 : 9,
            fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
            lineSpacing: 1.15,
          ),
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.indigo100, width: 0.7),
      columnWidths: const {
        0: pw.FlexColumnWidth(0.9),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(1.4),
      },
      children: [
        pw.TableRow(
          children: [cell('Critério', header: true), cell(left, header: true), cell(right, header: true)],
        ),
        ...section.generatedVisualElements.map(
          (item) => pw.TableRow(
            children: [
              cell(item.label),
              cell(item.leftValue),
              cell(item.rightValue),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _flowVisual(SummarySection section) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.blue200),
      ),
      child: pw.Column(
        children: List<pw.Widget>.generate(
          section.generatedVisualElements.length,
          (index) {
            final item = section.generatedVisualElements[index];
            return pw.Column(
              children: [
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(6),
                    border: pw.Border.all(color: PdfColors.blue300),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        _pdfSafe(item.label),
                        style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
                      ),
                      if (item.description.trim().isNotEmpty)
                        pw.Text(
                          _pdfSafe(item.description),
                          style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 1.2),
                        ),
                    ],
                  ),
                ),
                if (index != section.generatedVisualElements.length - 1)
                  pw.Container(
                    width: 2,
                    height: 9,
                    color: PdfColors.blue300,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static pw.Widget _hierarchyVisual(SummarySection section) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.indigo50,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.indigo200),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: section.generatedVisualElements.map((item) {
          final indent = (item.level.clamp(0, 4) * 18).toDouble();
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(width: indent),
                pw.Container(
                  width: 7,
                  height: 7,
                  margin: const pw.EdgeInsets.only(top: 4),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.indigo300,
                    borderRadius: pw.BorderRadius.circular(2),
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: _pdfSafe(item.label),
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                        ),
                        if (item.description.trim().isNotEmpty)
                          pw.TextSpan(
                            text: ' - ${_pdfSafe(item.description)}',
                            style: const pw.TextStyle(fontSize: 9.5),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  static pw.Widget _cardsVisual(SummarySection section) {
    return pw.Wrap(
      spacing: 8,
      runSpacing: 8,
      children: section.generatedVisualElements.map((item) {
        return pw.Container(
          width: 225,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.green50,
            borderRadius: pw.BorderRadius.circular(7),
            border: pw.Border.all(color: PdfColors.green200),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _pdfSafe(item.label),
                style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
              ),
              if (item.description.trim().isNotEmpty) ...[
                pw.SizedBox(height: 3),
                pw.Text(
                  _pdfSafe(item.description),
                  style: const pw.TextStyle(fontSize: 9.3, lineSpacing: 1.15),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  static pw.Widget? _buildGeneratedVisual(SummarySection section) {
    if (section.generatedVisualElements.isEmpty) return null;

    final kind = section.generatedVisualKind.trim().toLowerCase();
    pw.Widget visual;

    switch (kind) {
      case 'timeline':
        visual = _timelineVisual(section);
        break;
      case 'comparison':
        visual = _comparisonVisual(section);
        break;
      case 'flow':
        visual = _flowVisual(section);
        break;
      case 'hierarchy':
        visual = _hierarchyVisual(section);
        break;
      case 'cards':
        visual = _cardsVisual(section);
        break;
      default:
        return null;
    }

    return _visualTitleAndCaption(
      section,
      visual,
      footerNote: 'Visual didático estruturado pelo Educa+.ai a partir do material enviado.',
    );
  }

  /// Resumo V2-B.1 — Inteligência Visual Completa.
  ///
  /// Mantém a reutilização/recorte da V2-A e cria, sem uma segunda chamada à
  /// API, linhas do tempo, comparações, fluxos, hierarquias e cards a partir
  /// de dados estruturados já devolvidos pelo Gemini no JSON do resumo.
  static Future<Uint8List> generateStructuredSummaryPdf(
    PdfPageFormat format,
    StudySummary summary, {
    List<Uint8List> sourceBytes = const <Uint8List>[],
    List<String> sourceMimeTypes = const <String>[],
    Map<int, Uint8List> preparedSourceVisuals = const <int, Uint8List>{},
  }) async {
    final pdf = pw.Document();
    final pdfTheme = await _loadPdfTheme();

    final Map<int, pw.MemoryImage> sectionVisualImages = {};
    for (final entry in preparedSourceVisuals.entries) {
      try {
        sectionVisualImages[entry.key] = pw.MemoryImage(entry.value);
      } catch (_) {
        // Um recorte inválido não impede o restante do PDF.
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        theme: pdfTheme,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 42),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 12),
          child: pw.Text(
            'Educa+.ai - Pagina ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (pw.Context context) {
          final widgets = <pw.Widget>[
            pw.Text(
              _pdfSafe(summary.title.isEmpty ? 'Resumo de Estudo' : summary.title),
              style: pw.TextStyle(
                fontSize: 26,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo900,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Resumo estruturado - Inteligência Visual V2-B.1 - Educa+.ai',
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 18),
          ];

          if (summary.overview.trim().isNotEmpty) {
            widgets.add(
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: PdfColors.indigo50,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColors.indigo100),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Visao geral',
                      style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.indigo900,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      _pdfSafe(summary.overview),
                      style: const pw.TextStyle(fontSize: 13, lineSpacing: 1.4),
                    ),
                  ],
                ),
              ),
            );
            widgets.add(pw.SizedBox(height: 20));
          }

          for (int i = 0; i < summary.sections.length; i++) {
            final section = summary.sections[i];

            widgets.add(
              pw.Text(
                '${i + 1}. ${_cleanHeading(section.heading)}',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.indigo800,
                ),
              ),
            );
            widgets.add(pw.SizedBox(height: 8));
            widgets.add(
              pw.Text(
                _pdfSafe(section.content),
                style: const pw.TextStyle(fontSize: 13, lineSpacing: 1.45),
              ),
            );

            if (section.keyPoints.isNotEmpty) {
              widgets.add(pw.SizedBox(height: 10));
              widgets.add(
                pw.Text(
                  'Pontos-chave',
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                ),
              );
              widgets.add(pw.SizedBox(height: 4));

              for (final point in section.keyPoints) {
                widgets.add(
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 3),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('- ', style: const pw.TextStyle(fontSize: 12)),
                        pw.Expanded(
                          child: pw.Text(
                            _pdfSafe(point),
                            style: const pw.TextStyle(fontSize: 12, lineSpacing: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
            }

            if (section.needsVisual) {
              widgets.add(pw.SizedBox(height: 12));
              final preparedImage = sectionVisualImages[i];

              if (section.useSourceVisual && preparedImage != null) {
                widgets.add(
                  _visualTitleAndCaption(
                    section,
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.blue50,
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(color: PdfColors.blue200),
                      ),
                      child: pw.Container(
                        width: double.infinity,
                        constraints: const pw.BoxConstraints(maxHeight: 190),
                        alignment: pw.Alignment.center,
                        child: pw.Image(preparedImage, fit: pw.BoxFit.contain),
                      ),
                    ),
                    footerNote: 'Visual recortado do arquivo ${section.sourceFileIndex} enviado pelo aluno.',
                  ),
                );
              } else if (section.useSourceVisual) {
                widgets.add(
                  pw.Text(
                    'Apoio visual identificado no material, mas o recorte automatico nao pode ser preparado nesta geracao.',
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      color: PdfColors.grey700,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                );
              } else {
                final generated = _buildGeneratedVisual(section);
                if (generated != null) {
                  widgets.add(generated);
                } else {
                  widgets.add(
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.all(9),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.amber50,
                        borderRadius: pw.BorderRadius.circular(7),
                        border: pw.Border.all(color: PdfColors.amber200),
                      ),
                      child: pw.Text(
                        _pdfSafe(
                          section.visualCaption.trim().isEmpty
                              ? 'Esta secao se beneficia de apoio visual, mas ele nao pode ser representado com seguranca pelo motor grafico atual.'
                              : section.visualCaption,
                        ),
                        style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey800),
                      ),
                    ),
                  );
                }
              }
            }

            widgets.add(pw.SizedBox(height: 22));
          }

          if (summary.finalReview.isNotEmpty) {
            widgets.add(
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: PdfColors.green50,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColors.green200),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Revisao rapida',
                      style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green900,
                      ),
                    ),
                    pw.SizedBox(height: 7),
                    ...summary.finalReview.map(
                      (item) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 4),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('- ', style: const pw.TextStyle(fontSize: 12)),
                            pw.Expanded(
                              child: pw.Text(
                                _pdfSafe(item),
                                style: const pw.TextStyle(fontSize: 12, lineSpacing: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return widgets;
        },
      ),
    );

    return pdf.save();
  }
}
