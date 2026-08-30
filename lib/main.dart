/*
|--------------------------------------------------------------------------
| EDUCA+.AI — APLICAÇÃO PRINCIPAL
|--------------------------------------------------------------------------
|
| Arquivo responsável pelo fluxo principal do aplicativo Educa+.ai.
|
| Principais responsabilidades:
|
| • Seleção de imagens pela câmera ou galeria.
| • Envio dos materiais de estudo para a API Gemini.
| • Geração de quizzes personalizados.
| • Motor Pedagógico V2.2:
|     - Simples
|     - Intermediário
|     - Avançado
| • Distratores estruturados para questões avançadas.
| • Feedback pedagógico após o quiz.
| • Geração de resumo estruturado.
| • Inteligência Visual do Resumo V2-B.1.
| • Escolha automática entre:
|     - imagem original do material;
|     - timeline;
|     - comparação;
|     - hierarquia;
|     - fluxo;
|     - cards educacionais.
| • Recorte e orientação inteligente de imagens do material.
| • Cadeias de fallback entre modelos Gemini.
| • Tratamento de erros, timeout e indisponibilidade temporária da API.
| • Firebase Analytics V1.0 para acompanhamento de uso do aplicativo.
| • Espelhamento dos eventos do Analytics no debugPrint durante desenvolvimento.
|
| QUIZ:
| gemini-3.5-flash-lite
|        ↓ fallback
| gemini-3.1-flash-lite
|
| RESUMO:
| gemini-3.7-flash
|        ↓
| gemini-3.6-flash
|        ↓
| gemini-3.5-flash-lite
|        ↓
| gemini-3.1-flash-lite
|
| Versão atual:
| Quiz      → Motor Pedagógico V2.2
| Resumo    → Inteligência Visual V2-B.1
| Analytics → Firebase Analytics V1.0
|
|--------------------------------------------------------------------------
*/


import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart'; // Correção: Ponto e vírgula adicionado
import 'dart:io'; // Para ler arquivos do sistema
import 'package:file_picker/file_picker.dart'; // O novo pacote

import 'pdf_service.dart';
import 'study_summary.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

import 'firebase_options.dart';

late final FirebaseAnalytics analytics;

Future<void> _logAnalyticsEvent(
  String name, {
  Map<String, Object>? parameters,
}) async {
  try {
    await analytics.logEvent(
      name: name,
      parameters: parameters,
    );

    debugPrint('📊 ANALYTICS → $name');
    if (parameters != null && parameters.isNotEmpty) {
      debugPrint('   📦 $parameters');
    }
  } catch (e) {
    // Analytics nunca deve interromper Quiz, Resumo ou navegação do app.
    debugPrint('⚠️ ANALYTICS → falha ao registrar $name: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  analytics = FirebaseAnalytics.instance;
  debugPrint('📊 Firebase Analytics inicializado com sucesso.');

  runApp(const ScanLearnApp());
}

class QuizQuestion {
  final String question;
  final List<String> options;
  final String correctAnswer;
  final String explanation;

  QuizQuestion({
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      question: json['question'] ?? '',
      options: List<String>.from(json['options'] ?? []),
      correctAnswer: json['correctAnswer'] ?? '',
      explanation: json['explanation'] ?? '',
    );
  }
}

class GeminiCallResult {
  final http.Response response;
  final String model;
  final int attempt;

  const GeminiCallResult({
    required this.response,
    required this.model,
    required this.attempt,
  });
}

class ScanLearnApp extends StatelessWidget {
  const ScanLearnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Educa+.ai',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const ScanLearnHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ScanLearnHomePage extends StatefulWidget {
  const ScanLearnHomePage({super.key});

  @override
  State<ScanLearnHomePage> createState() => _ScanLearnHomePageState();
}

enum AppState { upload, generating, generatingSummary, generatingTutorGuide, quiz, analyzingResults, results }

class _ScanLearnHomePageState extends State<ScanLearnHomePage> {
  AppState _currentState = AppState.upload;

  // Variável GLOBAL para controlar o modelo ativo (Plano A e Plano B)
  String _currentModel = 'gemini-3.5-flash-lite';

  List<Uint8List> _imageBytesList = [];
  List<String> _mimeTypesList = [];

  List<QuizQuestion> _quizData = [];
  int _currentQuestionIdx = 0;
  Map<int, String> _userAnswers = {};

  String _teacherFeedback = "Parabéns por concluir o quiz! Continue praticando com novos trechos do seu material para aprimorar ainda mais o seu aprendizado.";
  String? _errorMessage;

  // Mensagens dinâmicas exibidas enquanto o Quiz é gerado.
  // Aos 45 s o app informa que continua processando, sem cancelar a chamada.
  // O timeout real é de 60 s por modelo; só então ocorre o fallback.
  String _quizLoadingTitle = 'Analisando o material...';
  String _quizLoadingSubtitle = 'Criando perguntas de nível Intermediário...';

  int _numberOfQuestions = 5;
  String _difficultyLevel = 'Intermediário';

  // Apenas para diagnóstico do Resumo PDF. Não altera o fluxo do quiz.
  String? _lastSummaryModel;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickPdf() async {
    try {
      // Recebemos o resultado na "caixa" FilePickerResult
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
      );

      int addedCount = 0;

      // Verificamos se o usuário não cancelou a seleção
      if (result != null && result.files.isNotEmpty) {
        for (var file in result.files) {
          if (file.path != null) {
            // Lê o PDF e joga para a lista do app
            final bytes = await File(file.path!).readAsBytes();
            setState(() {
              _imageBytesList.add(bytes);
              _mimeTypesList.add('application/pdf');
              _errorMessage = null;
            });
            addedCount++;
          }
        }
      }

      if (addedCount > 0) {
        await _logAnalyticsEvent(
          'material_added',
          parameters: {
            'source': 'pdf',
            'file_count': addedCount,
            'total_files': _imageBytesList.length,
          },
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao selecionar o PDF: $e';
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final List<XFile> images = await _picker.pickMultiImage();
        if (images.isNotEmpty) {
          for (var image in images) {
            final bytes = await image.readAsBytes();
            String mime = 'image/jpeg';
            if (image.name.toLowerCase().endsWith('.png')) {
              mime = 'image/png';
            }
            setState(() {
              _imageBytesList.add(bytes);
              _mimeTypesList.add(mime);
              _errorMessage = null;
            });
          }

          await _logAnalyticsEvent(
            'material_added',
            parameters: {
              'source': 'gallery',
              'file_count': images.length,
              'total_files': _imageBytesList.length,
            },
          );
        }
      } else {
        final XFile? image = await _picker.pickImage(source: source);
        if (image != null) {
          final bytes = await image.readAsBytes();
          String mime = 'image/jpeg';
          if (image.name.toLowerCase().endsWith('.png')) {
            mime = 'image/png';
          }
          setState(() {
            _imageBytesList.add(bytes);
            _mimeTypesList.add(mime);
            _errorMessage = null;
          });

          await _logAnalyticsEvent(
            'material_added',
            parameters: {
              'source': 'camera',
              'file_count': 1,
              'total_files': _imageBytesList.length,
            },
          );
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao selecionar a imagem: $e';
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imageBytesList.removeAt(index);
      _mimeTypesList.removeAt(index);
    });
  }

  void _resetApp() {
    setState(() {
      _currentState = AppState.upload;
      _imageBytesList.clear();
      _mimeTypesList.clear();
      _quizData = [];
      _currentQuestionIdx = 0;
      _userAnswers = {};
      _teacherFeedback = "Parabéns por concluir o quiz! Continue praticando com novos trechos do seu material para aprimorar ainda mais o seu aprendizado.";
      _errorMessage = null;
      _quizLoadingTitle = 'Analisando o material...';
      _quizLoadingSubtitle = 'Criando perguntas de nível $_difficultyLevel...';
    });
  }

  static const List<String> _summaryModels = [
    'gemini-3.7-flash',
    'gemini-3.6-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
  ];

  Future<GeminiCallResult> _callSummaryWithFallback({
    required String apiKey,
    required Map<String, dynamic> payload,
  }) async {
    http.Response? lastResponse;
    String? lastModel;
    Object? lastNetworkError;

    const fallbackStatusCodes = {404, 408, 429, 500, 502, 503, 504};

    debugPrint('');
    debugPrint('════════════════════════════════════════════════════');
    debugPrint('📄 EDUCA+.AI — INÍCIO DA CADEIA DE RESUMO');
    debugPrint('📚 Ordem: ${_summaryModels.join(' → ')}');
    debugPrint('📎 Arquivos enviados: ${_imageBytesList.length}');
    debugPrint('════════════════════════════════════════════════════');

    for (int i = 0; i < _summaryModels.length; i++) {
      final model = _summaryModels[i];
      final attempt = i + 1;
      final apiUrl =
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey';

      debugPrint('');
      debugPrint('────────────────────────────────────────────────────');
      debugPrint('🚀 TENTATIVA $attempt/${_summaryModels.length}');
      debugPrint('🤖 Modelo: $model');
      debugPrint('────────────────────────────────────────────────────');

      final stopwatch = Stopwatch()..start();

      try {
        final response = await http
            .post(
              Uri.parse(apiUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 90));

        stopwatch.stop();
        lastResponse = response;
        lastModel = model;

        debugPrint('📡 HTTP: ${response.statusCode}');
        debugPrint('⏱️ Tempo: ${stopwatch.elapsedMilliseconds} ms');

        if (response.statusCode == 200) {
          debugPrint('✅ MODELO UTILIZADO NO RESUMO: $model');
          debugPrint('📦 Tamanho da resposta: ${response.bodyBytes.length} bytes');
          debugPrint('════════════════════════════════════════════════════');
          return GeminiCallResult(
            response: response,
            model: model,
            attempt: attempt,
          );
        }

        // Em caso de erro, mostramos a resposta da API para sabermos exatamente
        // se foi cota, modelo inexistente, indisponibilidade ou outro motivo.
        debugPrint('❌ Falha no modelo $model');
        debugPrint('📦 Resposta da API: ${response.body}');

        if (fallbackStatusCodes.contains(response.statusCode)) {
          if (attempt < _summaryModels.length) {
            debugPrint('🔄 FALLBACK: tentando ${_summaryModels[i + 1]}...');
          } else {
            debugPrint('⛔ Não existem mais modelos de fallback.');
          }
          continue;
        }

        // 400/401/403 e semelhantes normalmente indicam payload, chave ou
        // permissão. Trocar de modelo pode esconder o erro real, então paramos.
        debugPrint(
          '⛔ Erro não elegível para fallback (${response.statusCode}).',
        );
        return GeminiCallResult(
          response: response,
          model: model,
          attempt: attempt,
        );
      } catch (e) {
        stopwatch.stop();
        lastNetworkError = e;
        lastModel = model;

        debugPrint('🌐 EXCEÇÃO DE REDE/TIMEOUT no modelo $model');
        debugPrint('⏱️ Tempo: ${stopwatch.elapsedMilliseconds} ms');
        debugPrint('📦 Detalhe: ${_sanitizeLogDetail(e, apiKey)}');

        if (attempt < _summaryModels.length) {
          debugPrint('🔄 FALLBACK: tentando ${_summaryModels[i + 1]}...');
          continue;
        }
      }
    }

    debugPrint('');
    debugPrint('════════════════════════════════════════════════════');
    debugPrint('⛔ FIM DA CADEIA: nenhum modelo conseguiu gerar o resumo.');
    if (lastModel != null) debugPrint('🤖 Último modelo tentado: $lastModel');
    if (lastResponse != null) debugPrint('📡 Último HTTP: ${lastResponse.statusCode}');
    if (lastNetworkError != null) debugPrint('🌐 Última exceção: ${_sanitizeLogDetail(lastNetworkError, apiKey)}');
    debugPrint('════════════════════════════════════════════════════');

    if (lastResponse != null && lastModel != null) {
      return GeminiCallResult(
        response: lastResponse,
        model: lastModel,
        attempt: _summaryModels.length,
      );
    }

    throw Exception(
      'Nenhum modelo de resumo pôde ser utilizado. '
      '${lastNetworkError != null ? 'Último erro: $lastNetworkError' : ''}',
    );
  }

  /// V2-B — prepara a região pedagógica indicada pelo Gemini e aplica a rotação sugerida.
  ///
  /// O decoder do Flutter normaliza a orientação da foto antes do recorte,
  /// evitando que o pacote PDF dependa da orientação EXIF do JPEG original.
  Future<Uint8List?> _cropSourceVisualForSummary({
    required Uint8List sourceBytes,
    required SummarySection section,
  }) async {
    ui.Codec? codec;
    ui.Image? decoded;
    ui.Image? cropped;

    try {
      codec = await ui.instantiateImageCodec(sourceBytes);
      final frame = await codec.getNextFrame();
      decoded = frame.image;

      final imageWidth = decoded.width.toDouble();
      final imageHeight = decoded.height.toDouble();

      // O Gemini trabalha em uma grade normalizada 0..1000.
      double nx = section.sourceCropX.clamp(0, 1000).toDouble() / 1000.0;
      double ny = section.sourceCropY.clamp(0, 1000).toDouble() / 1000.0;
      double nw = section.sourceCropWidth.clamp(0, 1000).toDouble() / 1000.0;
      double nh = section.sourceCropHeight.clamp(0, 1000).toDouble() / 1000.0;

      // Região inválida: não cola a página inteira no resumo por engano.
      if (nw < 0.05 || nh < 0.05) return null;

      // Pequena margem de segurança para não cortar bordas/legendas da figura.
      const padding = 0.015;
      nx = (nx - padding).clamp(0.0, 1.0).toDouble();
      ny = (ny - padding).clamp(0.0, 1.0).toDouble();
      nw = (nw + padding * 2).clamp(0.0, 1.0 - nx).toDouble();
      nh = (nh + padding * 2).clamp(0.0, 1.0 - ny).toDouble();

      final srcX = nx * imageWidth;
      final srcY = ny * imageHeight;
      final srcW = nw * imageWidth;
      final srcH = nh * imageHeight;

      if (srcW < 40 || srcH < 40) return null;

      // Redimensiona o recorte para evitar JPEGs de câmera gigantes dentro do PDF.
      const maxOutputSide = 1600.0;
      final largestSide = srcW > srcH ? srcW : srcH;
      final scale = largestSide > maxOutputSide ? maxOutputSide / largestSide : 1.0;
      final outW = (srcW * scale).round().clamp(1, 1600).toInt();
      final outH = (srcH * scale).round().clamp(1, 1600).toInt();

      final rotation = section.sourceRotation;
      final swapsSides = rotation == 90 || rotation == 270;
      final finalW = swapsSides ? outH : outW;
      final finalH = swapsSides ? outW : outH;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final paint = ui.Paint()..filterQuality = ui.FilterQuality.high;

      // O recorte é definido no raster original; a rotação é aplicada depois,
      // porque foi exatamente esse caso que apareceu no teste da ágora.
      if (rotation == 90) {
        canvas.translate(finalW.toDouble(), 0);
        canvas.rotate(math.pi / 2);
      } else if (rotation == 180) {
        canvas.translate(finalW.toDouble(), finalH.toDouble());
        canvas.rotate(math.pi);
      } else if (rotation == 270) {
        canvas.translate(0, finalH.toDouble());
        canvas.rotate(-math.pi / 2);
      }

      canvas.drawImageRect(
        decoded,
        ui.Rect.fromLTWH(srcX, srcY, srcW, srcH),
        ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
        paint,
      );

      final picture = recorder.endRecording();
      cropped = await picture.toImage(finalW, finalH);
      picture.dispose();

      final byteData = await cropped.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      return byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
    } catch (e) {
      debugPrint('⚠️ V2-B: falha ao preparar recorte: $e');
      return null;
    } finally {
      cropped?.dispose();
      decoded?.dispose();
      codec?.dispose();
    }
  }

  Future<Map<int, Uint8List>> _prepareSummarySourceVisuals(
    StudySummary summary,
  ) async {
    final prepared = <int, Uint8List>{};

    debugPrint('');
    debugPrint('════════════════════════════════════════════════════');
    debugPrint('✂️ RESUMO V2-B.1 — RECORTE + ORIENTAÇÃO');

    for (int sectionIndex = 0;
        sectionIndex < summary.sections.length;
        sectionIndex++) {
      final section = summary.sections[sectionIndex];
      if (!section.needsVisual || !section.useSourceVisual) continue;

      final sourceIndex = section.sourceFileIndex;
      if (sourceIndex <= 0 || sourceIndex > _imageBytesList.length) {
        debugPrint('⚠️ ${section.heading}: arquivo de origem inválido ($sourceIndex).');
        continue;
      }

      final mime = _mimeTypesList[sourceIndex - 1].toLowerCase();
      if (mime != 'image/jpeg' && mime != 'image/jpg' && mime != 'image/png') {
        debugPrint('⚠️ ${section.heading}: origem $mime ainda não é recortável na V2-B.');
        continue;
      }

      final cropped = await _cropSourceVisualForSummary(
        sourceBytes: _imageBytesList[sourceIndex - 1],
        section: section,
      );

      if (cropped != null) {
        prepared[sectionIndex] = cropped;
        debugPrint(
          '✅ ${section.heading} → arquivo $sourceIndex | '
          'crop [${section.sourceCropX}, ${section.sourceCropY}, '
          '${section.sourceCropWidth}, ${section.sourceCropHeight}] | '
          'rot=${section.sourceRotation}° | ${cropped.lengthInBytes} bytes',
        );
      } else {
        debugPrint(
          '⚠️ ${section.heading}: recorte não pôde ser preparado; '
          'a página inteira NÃO será inserida.',
        );
      }
    }

    debugPrint('🖼️ Recortes preparados: ${prepared.length}');
    debugPrint('════════════════════════════════════════════════════');
    return prepared;
  }

  Future<void> _generateSummary() async {
    if (_imageBytesList.isEmpty) return;

    setState(() {
      _currentState = AppState.generatingSummary;
      _errorMessage = null;
    });

    await _logAnalyticsEvent(
      'summary_started',
      parameters: {
        'file_count': _imageBytesList.length,
      },
    );

    final String apiKey = (dotenv.env['GEMINI_API_KEY'] ?? '').trim();

    if (apiKey.isEmpty) {
      setState(() {
        _errorMessage = 'API Key não encontrada. Verifique o arquivo .env.';
        _currentState = AppState.upload;
      });
      return;
    }

    try {
      final List<Map<String, dynamic>> promptParts = [];

      for (int i = 0; i < _imageBytesList.length; i++) {
        promptParts.add({
          'inlineData': {
            'mimeType': _mimeTypesList[i],
            'data': base64Encode(_imageBytesList[i]),
          }
        });
      }

      final String sourceCatalog = List<String>.generate(
        _mimeTypesList.length,
        (index) => 'Arquivo ${index + 1}: ${_mimeTypesList[index]}',
      ).join('\n');

      promptParts.add({
        'text': '''
Aja como um professor especialista em criação de material de estudo e design instrucional.

RESUMO V2-B.1 — INTELIGÊNCIA VISUAL COMPLETA
Produza um resumo fiel ao material e decida, seção por seção, qual é a melhor forma de apoio visual.
A prioridade é pedagógica: um visual só deve existir quando tornar relações, sequências,
comparações, hierarquias ou estruturas mais fáceis de compreender.

CATÁLOGO DOS ARQUIVOS (índice usado em sourceFileIndex):
$sourceCatalog

Analise SOMENTE os arquivos anexados. Não invente fatos, datas, definições, relações,
proporções ou exemplos que não estejam sustentados pelo material.

Organize o resumo em seções claras. IMPORTANTE: o campo heading deve conter SOMENTE
o título da seção, SEM números como "1.", "2." ou "3."; a numeração será feita pelo PDF.

Para cada seção:
- dê um título curto e informativo;
- explique o conteúdo com clareza;
- destaque de dois a cinco pontos-chave;
- avalie se um apoio visual realmente melhora a aprendizagem.

DECISÃO VISUAL V2-B.1 — ESCOLHA PELO VALOR DIDÁTICO:
1) Se NÃO houver ganho pedagógico real: needsVisual=false.
2) Se houver ganho pedagógico, NÃO escolha automaticamente a imagem do material só porque ela existe.
3) Compare mentalmente duas alternativas: (A) reaproveitar um visual real do material e
   (B) construir um visual educacional estruturado pelo PDF. Escolha SOMENTE a opção que
   ensina melhor aquela seção, com maior clareza, fidelidade e menor carga visual.
4) Prefira useSourceVisual=true quando o visual original tiver valor próprio difícil de substituir,
   como mapa, gráfico, diagrama, fotografia histórica/científica, obra, esquema original ou
   ilustração cuja forma visual seja parte importante do conteúdo.
5) Prefira useSourceVisual=false + generatedVisualKind quando o aprendizado depender mais de
   sequência, comparação, processo, hierarquia, classificação ou síntese — mesmo que exista
   uma fotografia relacionada no material.
6) Em caso de empate pedagógico, prefira o visual estruturado, por ser mais limpo e focado.
7) Preencha visualDecisionReason com UMA frase curta explicando por que a opção escolhida
   ensina melhor do que a alternativa descartada. Esse campo é apenas diagnóstico.

V2-A — REAPROVEITAMENTO DO PRÓPRIO MATERIAL:
- procure mapas, gráficos, diagramas, tabelas, esquemas, linhas do tempo e ilustrações educativas;
- useSourceVisual=true somente se o elemento ensina algo relevante para aquela seção;
- sourceFileIndex é 1-based;
- não escolha um arquivo apenas porque ele contém o texto resumido;
- sourceVisualReason deve explicar em uma frase por que a figura ajuda.

RECORTE + ORIENTAÇÃO:
- quando useSourceVisual=true, localize a região EXATA da figura útil;
- sourceCropX, sourceCropY, sourceCropWidth e sourceCropHeight são inteiros de 0 a 1000;
- exclua texto corrido, margens, mesa/fundo, espiral, dedos e decoração sempre que possível;
- não selecione a página inteira quando a figura ocupa apenas parte dela;
- sourceRotation informa quantos graus a figura RECORTADA deve girar no sentido HORÁRIO
  para ficar naturalmente legível: use somente 0, 90, 180 ou 270;
- se não houver visual de origem, todos os crops e sourceRotation devem ser 0.

V2-B — VISUAIS GERADOS PELO PRÓPRIO PDF:
Quando needsVisual=true e useSourceVisual=false, tente representar a informação sem criar
uma imagem artística. Escolha UM generatedVisualKind entre:
- timeline: sequência histórica/cronológica;
- comparison: comparação entre dois conceitos, lugares, sistemas ou grupos;
- flow: processo, causa e efeito ou sequência lógica;
- hierarchy: níveis, grupos, classificação ou estrutura social;
- cards: conjunto curto de conceitos relacionados;
- none: somente quando o visual necessário realmente não puder ser representado com segurança.

Use generatedVisualElements para fornecer os dados do visual. Cada elemento possui:
- label: rótulo curto;
- description: explicação curta;
- leftValue e rightValue: usados principalmente em comparison;
- level: 0 a 4, usado principalmente em hierarchy.

REGRAS POR TIPO:
- timeline: cada elemento = label + description; mantenha a ordem correta do material;
- comparison: preencha generatedVisualLeftTitle e generatedVisualRightTitle e, em cada
  elemento, label é o critério, leftValue é o lado esquerdo e rightValue é o lado direito;
- flow: cada elemento = uma etapa ou relação lógica em ordem;
- hierarchy: cada elemento = grupo/nível; level=0 é mais alto, números maiores são mais internos/subordinados;
- cards: cada elemento = conceito curto + explicação.

Não invente percentuais, quantidades, datas, setas causais ou hierarquias que o material não sustente.
Mantenha os textos visuais curtos: o visual deve complementar o resumo, não repetir parágrafos.
Se useSourceVisual=true, generatedVisualKind deve ser "none" e generatedVisualElements deve ser [].
Se needsVisual=true, visualDecisionReason deve explicar a escolha final em uma frase.
Se needsVisual=false, useSourceVisual=false, generatedVisualKind="none", sourceFileIndex=0,
sourceRotation=0, visualDecisionReason="" e todos os campos visuais sem uso devem ficar vazios/zerados.

Ao final, crie uma revisão rápida com os pontos essenciais para memorização.
Retorne estritamente o JSON solicitado pelo schema.
'''
      });

      final Map<String, dynamic> payload = {
        'contents': [
          {'role': 'user', 'parts': promptParts}
        ],
        'generationConfig': {
          'responseMimeType': 'application/json',
          'temperature': 0.25,
          'responseSchema': {
            'type': 'OBJECT',
            'properties': {
              'title': {
                'type': 'STRING',
                'description': 'Título curto e fiel ao assunto principal do material'
              },
              'overview': {
                'type': 'STRING',
                'description': 'Visão geral do conteúdo em um ou dois parágrafos'
              },
              'sections': {
                'type': 'ARRAY',
                'items': {
                  'type': 'OBJECT',
                  'properties': {
                    'heading': {
                      'type': 'STRING',
                      'description': 'Título da seção'
                    },
                    'content': {
                      'type': 'STRING',
                      'description': 'Explicação clara e detalhada da seção'
                    },
                    'keyPoints': {
                      'type': 'ARRAY',
                      'items': {'type': 'STRING'},
                      'description': 'De dois a cinco pontos-chave da seção'
                    },
                    'needsVisual': {
                      'type': 'BOOLEAN',
                      'description': 'True somente se apoio visual melhorar de verdade a compreensão'
                    },
                    'visualType': {
                      'type': 'STRING',
                      'description': 'mapa, linha do tempo, diagrama, quadro comparativo, gráfico, ilustração educativa ou string vazia'
                    },
                    'visualTitle': {
                      'type': 'STRING',
                      'description': 'Título curto do apoio visual ou string vazia'
                    },
                    'visualCaption': {
                      'type': 'STRING',
                      'description': 'Legenda explicando o que o apoio visual mostra ou deveria mostrar, ou string vazia'
                    },
                    'visualDecisionReason': {
                      'type': 'STRING',
                      'description': 'Justificativa curta da escolha pedagógica entre reaproveitar o visual do material ou construir um visual estruturado; string vazia quando needsVisual=false'
                    },
                    'useSourceVisual': {
                      'type': 'BOOLEAN',
                      'description': 'True somente se um visual já existente em um dos arquivos enviados deve ser reaproveitado nesta seção'
                    },
                    'sourceFileIndex': {
                      'type': 'INTEGER',
                      'description': 'Índice 1-based do arquivo que contém o visual reaproveitável; use 0 quando não houver'
                    },
                    'sourceVisualReason': {
                      'type': 'STRING',
                      'description': 'Frase curta explicando por que o visual original ajuda pedagogicamente; string vazia quando não for usado'
                    },
                    'sourceCropX': {
                      'type': 'INTEGER',
                      'description': 'Coordenada X do recorte em escala 0..1000; 0 quando não houver visual de origem'
                    },
                    'sourceCropY': {
                      'type': 'INTEGER',
                      'description': 'Coordenada Y do recorte em escala 0..1000; 0 quando não houver visual de origem'
                    },
                    'sourceCropWidth': {
                      'type': 'INTEGER',
                      'description': 'Largura do recorte em escala 0..1000; 0 quando não houver visual de origem'
                    },
                    'sourceCropHeight': {
                      'type': 'INTEGER',
                      'description': 'Altura do recorte em escala 0..1000; 0 quando não houver visual de origem'
                    },
                    'sourceRotation': {
                      'type': 'INTEGER',
                      'description': 'Rotação horária do recorte para ficar legível: somente 0, 90, 180 ou 270'
                    },
                    'generatedVisualKind': {
                      'type': 'STRING',
                      'description': 'timeline, comparison, flow, hierarchy, cards ou none'
                    },
                    'generatedVisualLeftTitle': {
                      'type': 'STRING',
                      'description': 'Título da coluna esquerda para comparison; string vazia nos demais tipos'
                    },
                    'generatedVisualRightTitle': {
                      'type': 'STRING',
                      'description': 'Título da coluna direita para comparison; string vazia nos demais tipos'
                    },
                    'generatedVisualElements': {
                      'type': 'ARRAY',
                      'description': 'Dados estruturados para o visual nativo V2-B; array vazio quando não houver',
                      'items': {
                        'type': 'OBJECT',
                        'properties': {
                          'label': {
                            'type': 'STRING',
                            'description': 'Rótulo curto do elemento ou critério de comparação'
                          },
                          'description': {
                            'type': 'STRING',
                            'description': 'Explicação curta para timeline, flow, hierarchy e cards'
                          },
                          'leftValue': {
                            'type': 'STRING',
                            'description': 'Valor do lado esquerdo em comparison; vazio nos demais tipos'
                          },
                          'rightValue': {
                            'type': 'STRING',
                            'description': 'Valor do lado direito em comparison; vazio nos demais tipos'
                          },
                          'level': {
                            'type': 'INTEGER',
                            'description': 'Nível de 0 a 4 para hierarchy; use 0 nos demais tipos'
                          }
                        },
                        'required': [
                          'label',
                          'description',
                          'leftValue',
                          'rightValue',
                          'level'
                        ]
                      }
                    },
                  },
                  'required': [
                    'heading',
                    'content',
                    'keyPoints',
                    'needsVisual',
                    'visualType',
                    'visualTitle',
                    'visualCaption',
                    'visualDecisionReason',
                    'useSourceVisual',
                    'sourceFileIndex',
                    'sourceVisualReason',
                    'sourceCropX',
                    'sourceCropY',
                    'sourceCropWidth',
                    'sourceCropHeight',
                    'sourceRotation',
                    'generatedVisualKind',
                    'generatedVisualLeftTitle',
                    'generatedVisualRightTitle',
                    'generatedVisualElements'
                  ]
                }
              },
              'finalReview': {
                'type': 'ARRAY',
                'items': {'type': 'STRING'},
                'description': 'Lista com os principais pontos para revisão final'
              }
            },
            'required': ['title', 'overview', 'sections', 'finalReview']
          }
        }
      };

      final summaryResult = await _callSummaryWithFallback(
        apiKey: apiKey,
        payload: payload,
      );

      final response = summaryResult.response;
      _lastSummaryModel = summaryResult.model;

      debugPrint('');
      debugPrint('════════════════════════════════════════════════════');
      debugPrint('🏁 RESULTADO FINAL DO RESUMO');
      debugPrint('🤖 Modelo final: ${summaryResult.model}');
      debugPrint('🔢 Tentativa: ${summaryResult.attempt}/${_summaryModels.length}');
      debugPrint('📡 Status final: ${response.statusCode}');
      debugPrint('════════════════════════════════════════════════════');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final String textResponse =
            data['candidates'][0]['content']['parts'][0]['text'];

        final Map<String, dynamic> summaryJson = jsonDecode(textResponse);
        final StudySummary summary = StudySummary.fromJson(summaryJson);

        if (summary.sections.isEmpty) {
          throw Exception('A IA retornou um resumo sem seções.');
        }

        debugPrint('');
        debugPrint('════════════════════════════════════════════════════');
        debugPrint('🖼️ RESUMO V2-B.1 — INTELIGÊNCIA VISUAL COMPLETA');
        final visualSections = summary.sections.where((s) => s.needsVisual).toList();
        final reusedSections = visualSections
            .where((s) => s.useSourceVisual && s.sourceFileIndex > 0)
            .toList();
        final generatedSections = visualSections
            .where((s) => !s.useSourceVisual &&
                s.generatedVisualKind.toLowerCase() != 'none' &&
                s.generatedVisualElements.isNotEmpty)
            .toList();
        debugPrint('📚 Seções totais: ${summary.sections.length}');
        debugPrint('🎯 Seções que pedem apoio visual: ${visualSections.length}');
        debugPrint('♻️ Visuais reaproveitados do material: ${reusedSections.length}');
        debugPrint('🧩 Visuais estruturados V2-B.1: ${generatedSections.length}');
        for (final section in reusedSections) {
          debugPrint('   ♻️ ${section.heading} → arquivo ${section.sourceFileIndex} (${section.visualType})');
          debugPrint('      Crop 0..1000: x=${section.sourceCropX}, y=${section.sourceCropY}, w=${section.sourceCropWidth}, h=${section.sourceCropHeight}, rot=${section.sourceRotation}°');
          if (section.visualDecisionReason.trim().isNotEmpty) {
            debugPrint('      Decisão V2-B.1: ${section.visualDecisionReason}');
          }
          if (section.sourceVisualReason.trim().isNotEmpty) {
            debugPrint('      Motivo da fonte: ${section.sourceVisualReason}');
          }
        }
        for (final section in generatedSections) {
          debugPrint('   🧩 ${section.heading} → ${section.generatedVisualKind} | ${section.generatedVisualElements.length} elementos');
          if (section.visualDecisionReason.trim().isNotEmpty) {
            debugPrint('      Decisão V2-B.1: ${section.visualDecisionReason}');
          }
        }
        debugPrint('════════════════════════════════════════════════════');

        await _logAnalyticsEvent(
          'summary_generated',
          parameters: {
            'model': summaryResult.model,
            'attempt': summaryResult.attempt,
            'sections': summary.sections.length,
            'visual_sections': visualSections.length,
            'source_visuals': reusedSections.length,
            'structured_visuals': generatedSections.length,
          },
        );

        final preparedSourceVisuals = await _prepareSummarySourceVisuals(summary);

        setState(() {
          _currentState = AppState.upload;
        });

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PdfPreviewScreen(
                structuredSummary: summary,
                sourceBytes: List<Uint8List>.from(_imageBytesList),
                sourceMimeTypes: List<String>.from(_mimeTypesList),
                preparedSourceVisuals: preparedSourceVisuals,
              ),
            ),
          );
        }
      } else if (response.statusCode == 429) {
        throw Exception(
          'Os modelos disponíveis para resumo atingiram o limite de uso no momento.',
        );
      } else if (response.statusCode == 503) {
        throw Exception(
          'Os servidores da Google estão sobrecarregados no momento. Tente novamente em instantes.',
        );
      } else {
        String mensagemAmigavel =
            'Erro desconhecido na API: ${response.statusCode}';

        try {
          final erroJson = jsonDecode(response.body);
          if (erroJson['error'] != null &&
              erroJson['error']['message'] != null) {
            mensagemAmigavel = erroJson['error']['message'];
          }
        } catch (_) {}

        throw Exception(
          'Falha na comunicação com a IA.\nDetalhe: $mensagemAmigavel',
        );
      }
    } catch (e) {
      await _logAnalyticsEvent(
        'summary_generation_failed',
        parameters: {
          'file_count': _imageBytesList.length,
        },
      );

      setState(() {
        final erroLimpo = e.toString().replaceAll('Exception: ', '');
        _errorMessage = 'Falha ao gerar o resumo. Detalhes: $erroLimpo';
        _currentState = AppState.upload;
      });
    }
  }

  Future<void> _generateTutorGuide() async {
    if (_imageBytesList.isEmpty) return;

    setState(() {
      _currentState = AppState.generatingTutorGuide;
      _errorMessage = null;
    });

    final String apiKey = (dotenv.env['GEMINI_API_KEY'] ?? '').trim();

    if (apiKey.isEmpty) {
      setState(() {
        _errorMessage = "API Key não encontrada. Verifique o arquivo .env.";
        _currentState = AppState.upload;
      });
      return;
    }

    final String apiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/$_currentModel:generateContent?key=$apiKey';

    try {
      List<Map<String, dynamic>> promptParts = [];

      for (int i = 0; i < _imageBytesList.length; i++) {
        promptParts.add({
          "inlineData": {
            "mimeType": _mimeTypesList[i],
            "data": base64Encode(_imageBytesList[i])
          }
        });
      }

      promptParts.add({
        "text": "Aja como um especialista em pedagogia e crie um 'Guia do Tutor' para os pais ajudarem seus filhos a estudar a matéria dos arquivos anexados. O guia deve ser encorajador e conter:\n1. Resumo em 1 minuto: O conceito principal explicado de forma extremamente mastigada e simples para o adulto entender rapidamente.\n2. Analogias do Dia a Dia: Duas comparações simples e didáticas para o pai usar ao explicar o assunto à criança.\n3. Perguntas de Sondagem: Três perguntas informais (com as respostas logo abaixo) para o pai fazer durante uma conversa e testar o conhecimento do filho.\nRetorne apenas o texto do guia, de forma estruturada e bem espaçada, sem blocos de código ou formato JSON, pronto para ser impresso no PDF."
      });

      final Map<String, dynamic> payload = {
        "contents": [{"role": "user", "parts": promptParts}],
        "generationConfig": {
          "responseMimeType": "text/plain",
          "temperature": 0.4,
        }
      };

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final String textResponse = data['candidates'][0]['content']['parts'][0]['text'];

        setState(() {
          _currentState = AppState.upload;
        });

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PdfPreviewScreen(summaryText: textResponse),
            ),
          );
        }

      } else if (response.statusCode == 429) {
        if (_currentModel == 'gemini-3.5-flash-lite') {
          debugPrint('⚠️ Cota do 3.5 esgotada. Trocando para 3.1 Flash Lite e tentando novamente...');
          setState(() {
            _currentModel = 'gemini-3.1-flash-lite';
          });
          return _generateTutorGuide();
        } else {
          throw Exception('Limite incrível de uso esgotado! As 1.000 requisições gratuitas diárias da IA chegaram ao fim. Tente novamente amanhã.');
        }
      } else if (response.statusCode == 503) {
        throw Exception('Os servidores da Google estão sobrecarregados no momento. Aguarde alguns instantes e tente novamente.');
      } else {
        String mensagemAmigavel = 'Erro desconhecido na API: ${response.statusCode}';
        try {
          final erroJson = jsonDecode(response.body);
          if (erroJson['error'] != null && erroJson['error']['message'] != null) {
            mensagemAmigavel = erroJson['error']['message'];
          }
        } catch (_) {}
        throw Exception('Falha na comunicação com a IA.\nDetalhe: $mensagemAmigavel');
      }
    } catch (e) {
      setState(() {
        String erroLimpo = e.toString().replaceAll('Exception: ', '');
        _errorMessage = erroLimpo;
        _currentState = AppState.upload;
      });
    }
  }

  String _sanitizeLogDetail(Object? value, String apiKey) {
    var text = value?.toString() ?? '';

    if (apiKey.isNotEmpty) {
      text = text.replaceAll(apiKey, '<API_KEY_REDACTED>');
    }

    text = text.replaceAllMapped(
      RegExp(r'([?&]key=)[^&\s]+'),
      (match) => '${match.group(1)}<API_KEY_REDACTED>',
    );

    return text;
  }

  static const List<String> _quizModels = [
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
  ];

  Future<GeminiCallResult> _callQuizWithFallback({
    required String apiKey,
    required Map<String, dynamic> payload,
    String operationName = 'QUIZ',
  }) async {
    http.Response? lastResponse;
    String? lastResponseModel;
    int? lastResponseAttempt;
    Object? lastNetworkError;
    final List<int> statusHistory = [];

    // Erros temporários / de limite que justificam tentar o modelo reserva.
    const fallbackStatusCodes = {404, 408, 429, 500, 502, 503, 504};
    const warningAfter = Duration(seconds: 45);
    const realTimeout = Duration(seconds: 60);
    const retry503Delay = Duration(seconds: 8);

    debugPrint('');
    debugPrint('════════════════════════════════════════════════════');
    debugPrint('🧠 EDUCA+.AI — INÍCIO DA CADEIA DO $operationName');
    debugPrint('📚 Ordem: ${_quizModels.join(' → ')}');
    debugPrint('⏱️ Aviso visual: 45 s | Timeout real: 60 s por modelo');
    debugPrint('🛟 Recuperação 503: 1 nova tentativa no 3.5 após 8 s se ambos retornarem 503');
    debugPrint('════════════════════════════════════════════════════');

    for (int i = 0; i < _quizModels.length; i++) {
      final model = _quizModels[i];
      final attempt = i + 1;
      final apiUrl =
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey';

      debugPrint('');
      debugPrint('────────────────────────────────────────────────────');
      debugPrint('🚀 $operationName — TENTATIVA $attempt/${_quizModels.length}');
      debugPrint('🤖 Modelo: $model');
      debugPrint('────────────────────────────────────────────────────');

      final stopwatch = Stopwatch()..start();
      bool requestFinished = false;

      // Aos 45 s apenas atualizamos a experiência do usuário.
      // A requisição continua viva por mais 15 s e só é cancelada aos 60 s.
      final thinkingTimer = Timer(warningAfter, () {
        if (requestFinished) return;

        if (operationName == 'QUIZ' &&
            mounted &&
            _currentState == AppState.generating) {
          setState(() {
            if (attempt == 1) {
              _quizLoadingTitle = 'Pensando melhor...';
              _quizLoadingSubtitle =
                  'A análise está levando um pouco mais de tempo. Vou aguardar mais alguns instantes antes de tentar outra abordagem.';
            } else {
              _quizLoadingTitle = 'Refinando as questões...';
              _quizLoadingSubtitle =
                  'O modelo reserva ainda está trabalhando. Vou aguardar mais alguns instantes para concluir seu quiz.';
            }
          });
        }

        debugPrint(
          attempt == 1
              ? '💭 PENSANDO MELHOR: 45 s atingidos no $model; mantendo a MESMA requisição até 60 s...'
              : '🧠 REFINANDO: 45 s atingidos no modelo reserva $model; mantendo a MESMA requisição até 60 s...',
        );
      });

      try {
        final response = await http
            .post(
              Uri.parse(apiUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(realTimeout);

        requestFinished = true;
        thinkingTimer.cancel();
        stopwatch.stop();
        lastResponse = response;
        lastResponseModel = model;
        lastResponseAttempt = attempt;
        statusHistory.add(response.statusCode);

        debugPrint('📡 HTTP: ${response.statusCode}');
        debugPrint('⏱️ Tempo: ${stopwatch.elapsedMilliseconds} ms');

        if (response.statusCode == 200) {
          debugPrint('✅ MODELO UTILIZADO NO $operationName: $model');
          debugPrint('📦 Tamanho da resposta: ${response.bodyBytes.length} bytes');
          debugPrint('════════════════════════════════════════════════════');

          return GeminiCallResult(
            response: response,
            model: model,
            attempt: attempt,
          );
        }

        debugPrint('❌ Falha no modelo $model');
        debugPrint('📦 Resposta da API: ${_sanitizeLogDetail(response.body, apiKey)}');

        if (fallbackStatusCodes.contains(response.statusCode) &&
            attempt < _quizModels.length) {
          if (operationName == 'QUIZ' &&
              mounted &&
              _currentState == AppState.generating) {
            setState(() {
              _quizLoadingTitle = 'Tentando outra abordagem...';
              _quizLoadingSubtitle =
                  'O primeiro modelo não conseguiu concluir. Vou usar o modelo reserva para criar seu quiz.';
            });
          }
          debugPrint('🔄 FALLBACK: tentando ${_quizModels[i + 1]}...');
          continue;
        }

        // Se 3.5 e 3.1 responderam 503, saímos do loop para fazer UMA
        // tentativa extra no 3.5 após uma pequena pausa.
        final bothModelsReturned503 =
            attempt == _quizModels.length &&
            statusHistory.length >= _quizModels.length &&
            statusHistory
                .sublist(statusHistory.length - _quizModels.length)
                .every((status) => status == 503);

        if (bothModelsReturned503) {
          break;
        }

        return GeminiCallResult(
          response: response,
          model: model,
          attempt: attempt,
        );
      } catch (e) {
        requestFinished = true;
        thinkingTimer.cancel();
        stopwatch.stop();
        lastNetworkError = e;

        debugPrint('🌐 Falha de rede/timeout no modelo $model');
        debugPrint('⏱️ Tempo: ${stopwatch.elapsedMilliseconds} ms');
        debugPrint('📦 Detalhe: ${_sanitizeLogDetail(e, apiKey)}');

        final isTimeout = e is TimeoutException;
        if (isTimeout) {
          debugPrint('⏱️ TIMEOUT REAL: 60 s concluídos no modelo $model.');
        }

        if (attempt < _quizModels.length) {
          if (operationName == 'QUIZ' &&
              mounted &&
              _currentState == AppState.generating) {
            setState(() {
              _quizLoadingTitle = 'Tentando outra abordagem...';
              _quizLoadingSubtitle = isTimeout
                  ? 'A primeira análise passou de 60 segundos. Vou tentar o modelo reserva agora.'
                  : 'A primeira tentativa não concluiu. Vou tentar o modelo reserva agora.';
            });
          }
          debugPrint('🔄 FALLBACK: tentando ${_quizModels[i + 1]}...');
          continue;
        }
      } finally {
        requestFinished = true;
        thinkingTimer.cancel();
      }
    }

    final bothModelsReturned503 =
        statusHistory.length >= _quizModels.length &&
        statusHistory
            .sublist(statusHistory.length - _quizModels.length)
            .every((status) => status == 503);

    if (bothModelsReturned503) {
      const recoveryModel = 'gemini-3.5-flash-lite';
      const recoveryAttempt = 3;

      if (operationName == 'QUIZ' &&
          mounted &&
          _currentState == AppState.generating) {
        setState(() {
          _quizLoadingTitle = 'Os modelos estão ocupados...';
          _quizLoadingSubtitle =
              'Vou aguardar alguns segundos e tentar mais uma vez antes de encerrar.';
        });
      }

      debugPrint('');
      debugPrint('════════════════════════════════════════════════════');
      debugPrint('⏳ 503/503: os dois modelos informaram alta demanda.');
      debugPrint('🛟 Aguardando 8 s antes de UMA tentativa extra no $recoveryModel...');
      debugPrint('════════════════════════════════════════════════════');

      await Future.delayed(retry503Delay);

      final apiUrl =
          'https://generativelanguage.googleapis.com/v1beta/models/$recoveryModel:generateContent?key=$apiKey';
      final stopwatch = Stopwatch()..start();
      bool requestFinished = false;

      final thinkingTimer = Timer(warningAfter, () {
        if (requestFinished) return;

        if (operationName == 'QUIZ' &&
            mounted &&
            _currentState == AppState.generating) {
          setState(() {
            _quizLoadingTitle = 'Última tentativa...';
            _quizLoadingSubtitle =
                'A demanda ainda está alta. Vou aguardar mais alguns instantes por esta última resposta.';
          });
        }

        debugPrint(
          '🧠 ÚLTIMA TENTATIVA: 45 s atingidos no $recoveryModel; mantendo a MESMA requisição até 60 s...',
        );
      });

      try {
        debugPrint('');
        debugPrint('────────────────────────────────────────────────────');
        debugPrint('🚀 $operationName — TENTATIVA EXTRA 503');
        debugPrint('🤖 Modelo: $recoveryModel');
        debugPrint('────────────────────────────────────────────────────');

        final response = await http
            .post(
              Uri.parse(apiUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(realTimeout);

        requestFinished = true;
        thinkingTimer.cancel();
        stopwatch.stop();
        lastResponse = response;
        lastResponseModel = recoveryModel;
        lastResponseAttempt = recoveryAttempt;

        debugPrint('📡 HTTP: ${response.statusCode}');
        debugPrint('⏱️ Tempo: ${stopwatch.elapsedMilliseconds} ms');

        if (response.statusCode == 200) {
          debugPrint('✅ RECUPERAÇÃO 503 BEM-SUCEDIDA: $recoveryModel');
          debugPrint('📦 Tamanho da resposta: ${response.bodyBytes.length} bytes');
          debugPrint('════════════════════════════════════════════════════');
        } else {
          debugPrint('❌ Tentativa extra também falhou no $recoveryModel');
          debugPrint('📦 Resposta da API: ${_sanitizeLogDetail(response.body, apiKey)}');
        }

        return GeminiCallResult(
          response: response,
          model: recoveryModel,
          attempt: recoveryAttempt,
        );
      } catch (e) {
        requestFinished = true;
        thinkingTimer.cancel();
        stopwatch.stop();
        lastNetworkError = e;

        debugPrint('🌐 Falha na tentativa extra do $recoveryModel');
        debugPrint('⏱️ Tempo: ${stopwatch.elapsedMilliseconds} ms');
        debugPrint('📦 Detalhe: ${_sanitizeLogDetail(e, apiKey)}');
      } finally {
        requestFinished = true;
        thinkingTimer.cancel();
      }
    }

    if (lastResponse != null &&
        lastResponseModel != null &&
        lastResponseAttempt != null) {
      return GeminiCallResult(
        response: lastResponse,
        model: lastResponseModel,
        attempt: lastResponseAttempt,
      );
    }

    throw Exception(
      lastNetworkError == null
          ? 'Os modelos de IA estão temporariamente indisponíveis. Aguarde alguns instantes e tente novamente.'
          : 'Não foi possível concluir a comunicação com os modelos de IA. Verifique sua conexão e tente novamente.',
    );
  }

  String _advancedQuestionMatrix() {
    // Para 5 questões, a matriz pede exatamente uma questão de cada tipo.
    // Para 10, 15 ou 20, a IA deve repetir o ciclo de forma equilibrada.
    return '''
MATRIZ OBRIGATÓRIA DE QUESTÕES AVANÇADAS — V2.2:
Distribua as $_numberOfQuestions questões de forma equilibrada entre os cinco tipos abaixo.
Se forem exatamente 5 questões, respeite também a ORDEM abaixo:
- Questão 1 = TIPO A — causa e consequência complexa;
- Questão 2 = TIPO B — comparação e contraste;
- Questão 3 = TIPO C — aplicação em situação nova;
- Questão 4 = TIPO D — análise de afirmações;
- Questão 5 = TIPO E — síntese / integração de informações.
Se forem 10, 15 ou 20, repita esse ciclo na mesma ordem, mantendo a distribuição equilibrada.
Não troque a habilidade cognitiva de posição apenas porque outro tipo parece mais fácil de gerar.

TIPO A — CAUSA E CONSEQUÊNCIA COMPLEXA
- O aluno deve relacionar pelo menos dois elementos do material para explicar uma consequência, motivação, efeito ou desdobramento.
- Não aceite uma relação causal que esteja respondida literalmente em uma única frase do material.

TIPO B — COMPARAÇÃO E CONTRASTE
- O aluno deve comparar dois ou mais conceitos, grupos, períodos, processos ou situações do material.
- A resposta deve depender da identificação de semelhanças, diferenças, limites ou contradições relevantes.

TIPO C — APLICAÇÃO EM SITUAÇÃO NOVA
- Crie uma situação hipotética curta que NÃO apareça literalmente no material.
- O aluno deve aplicar um princípio, regra ou conceito do material para resolver a situação.
- A situação nova não pode exigir conhecimento externo ao material.

TIPO D — ANÁLISE DE AFIRMAÇÕES
- Apresente afirmações I, II e III, ou uma combinação equivalente.
- O aluno deve julgar quais afirmações são compatíveis com o material e escolher a combinação correta.
- TODAS as afirmações devem parecer defensáveis à primeira leitura para quem estudou parcialmente o conteúdo.
- Evite afirmações obviamente falsas por excesso, absurdo, anacronismo ou oposição direta ao texto.
- Quando uma afirmação estiver incorreta, prefira erros sutis de escopo, generalização, relação causal, cronologia, critério, condição ou associação entre conceitos.
- Não use palavras absolutas como “todos”, “nunca”, “sempre”, “exclusivamente” apenas para denunciar facilmente a afirmação errada, salvo quando isso for indispensável ao conteúdo.
- A combinação correta deve exigir a avaliação individual das afirmações; não deve ser possível acertar eliminando uma única afirmação evidentemente absurda.

TIPO E — SÍNTESE / INTEGRAÇÃO DE INFORMAÇÕES
- A questão deve exigir a combinação de informações provenientes de duas partes, tópicos, exemplos ou seções diferentes do material.
- O aluno deve chegar a uma conclusão que não esteja pronta em uma única frase.

REGRA DE SUBSTITUIÇÃO:
Se o material não permitir algum dos cinco tipos, substitua-o por outro tipo de complexidade equivalente,
mas mantenha obrigatoriamente a exigência de análise, aplicação, inferência ou integração de pelo menos duas informações.
''';
  }

  String _difficultyInstructions() {
    switch (_difficultyLevel) {
      case 'Simples':
        return '''
PÚBLICO-ALVO: crianças do Ensino Fundamental I.

NÍVEL COGNITIVO:
- lembrar;
- reconhecer;
- identificar;
- compreender conceitos básicos.

REGRAS:
- Faça perguntas diretas e objetivas.
- Trabalhe uma ideia principal por questão.
- Use vocabulário simples e adequado para crianças.
- Não use pegadinhas.
- Não exija múltiplas etapas de raciocínio.
- As alternativas devem ser claras e relativamente curtas.
- A dificuldade NÃO deve ser criada aumentando o tamanho do enunciado.
''';

      case 'Intermediário':
        return '''
PÚBLICO-ALVO: estudantes do 6º ao 9º ano do Ensino Fundamental.

NÍVEL COGNITIVO:
- compreensão;
- interpretação;
- comparação;
- aplicação;
- inferência simples.

REGRAS:
- Não faça apenas perguntas de memorização literal.
- Exija compreensão do conteúdo.
- Use situações-problema curtas quando forem adequadas.
- Explore causa e consequência.
- Compare conceitos presentes no material.
- Crie alternativas plausíveis.
- Exija aproximadamente 1 ou 2 etapas de raciocínio.
- A resposta não deve ser apenas uma frase copiada literalmente do material.
- A dificuldade NÃO deve ser criada aumentando o tamanho do texto.
''';

      case 'Avançado':
        return '''
PÚBLICO-ALVO: adultos, vestibulares e concursos públicos.

NÍVEL COGNITIVO:
- aplicação;
- análise;
- inferência;
- avaliação;
- integração de conceitos.

REGRA DE VALIDADE DO NÍVEL AVANÇADO:
Uma questão é INVÁLIDA como Avançada se puder ser respondida apenas localizando ou lembrando uma única frase explícita do material.
Uma questão também é INVÁLIDA se a única diferença em relação a uma questão simples/intermediária for ter enunciado maior, vocabulário mais formal ou alternativas mais longas.

Para ser válida como Avançada, a questão deve exigir PELO MENOS UMA das condições abaixo:
- combinar duas ou mais informações do material;
- interpretar uma relação de causa e consequência;
- aplicar um conceito em uma situação nova;
- comparar conceitos e chegar a uma conclusão;
- avaliar afirmações plausíveis;
- inferir uma conclusão que não esteja escrita literalmente em uma única frase.

REGRAS:
- Exija raciocínio real, não apenas memorização.
- Combine dois ou mais conceitos sempre que o material permitir.
- Use situações novas que exijam aplicação do conteúdo.
- Explore relações de causa e consequência.
- Use afirmações, exceções, comparações e sínteses quando apropriado.
ENGENHARIA OBRIGATÓRIA DOS DISTRATORES — V2.2:
Para CADA questão, construa primeiro a resposta correta e depois crie três distratores com estruturas de erro diferentes:

- ALTERNATIVA CORRETA: deve ser 100% compatível com o material e responder exatamente ao que foi perguntado.
- DISTRATOR 1 — CAUSA/CRITÉRIO INCORRETO: preserve uma conclusão ou informação plausível, mas associe a ela uma causa, condição, critério ou justificativa incorreta.
- DISTRATOR 2 — FATOS VERDADEIROS, RELAÇÃO INCORRETA: utilize informações que aparecem ou são compatíveis com o material, mas conecte-as de forma causal, cronológica, conceitual ou comparativa incorreta.
- DISTRATOR 3 — QUASE CORRETO: apresente um raciocínio majoritariamente correto, porém com uma generalização indevida, condição omitida, escopo ampliado/reduzido ou aplicação fora do contexto adequado.

REGRAS DE PLAUSIBILIDADE E EQUILÍBRIO:
- Cada alternativa incorreta deve parecer possível para um aluno que compreendeu PARCIALMENTE o conteúdo.
- Pelo menos DUAS alternativas incorretas devem obrigar o aluno a conferir detalhes conceituais; não podem ser eliminadas apenas pelo bom senso.
- Evite alternativas absurdas, anacrônicas, fora do tema, caricatas ou que simplesmente invertam tudo o que o material diz.
- Evite usar como pista palavras absolutas como “todos”, “nenhum”, “sempre”, “nunca”, “completamente”, “exclusivamente”, “inteiramente” ou “definitivamente”, salvo quando forem realmente necessárias ao conteúdo.
- Não crie um padrão em que a alternativa correta seja a única moderada e as incorretas sejam extremas.
- Mantenha as quatro alternativas com nível de detalhe, vocabulário e estrutura gramatical semelhantes.
- Mantenha também comprimentos semelhantes: idealmente, a alternativa mais longa não deve superar em mais de aproximadamente 35% a quantidade de palavras da alternativa mais curta.
- Se a resposta correta ficar muito mais longa ou precisa que as demais, REESCREVA os distratores para equilibrá-los; não encurte a correta retirando informação necessária.
- Não permita que uma alternativa seja descartada apenas por ser mais curta, mais longa, mais vaga, mais absoluta ou linguisticamente diferente das demais.
- A posição da resposta correta deve variar naturalmente entre A, B, C e D ao longo da prova; não crie padrão previsível.
- Prefira erros conceituais sutis: generalização indevida, inversão parcial de causa e consequência, confusão entre conceitos próximos, condição necessária tratada como suficiente, aplicação de uma regra fora do contexto, conclusão parcialmente correta ou associação correta com justificativa errada.
- Evite pistas gramaticais ou semânticas entre o enunciado e a resposta correta.
- A resposta correta não deve estar explicitamente óbvia no enunciado.
- NÃO aumente artificialmente o tamanho do texto para simular dificuldade.
- NÃO use pegadinhas puramente linguísticas, dupla negação desnecessária ou ambiguidade.
- A dificuldade deve vir do RACIOCÍNIO necessário para resolver a questão.

${_advancedQuestionMatrix()}

AUTOVALIDAÇÃO OBRIGATÓRIA ANTES DE RESPONDER:
Para CADA questão, verifique internamente:
1. Esta questão poderia ser respondida apenas copiando/localizando uma frase do material?
2. O aluno precisa realmente interpretar, aplicar, comparar, avaliar ou integrar informações?
3. TODOS os distratores são plausíveis para alguém que estudou o assunto, mas cometeu um erro conceitual?
4. Os três distratores utilizam erros conceituais diferentes, em vez de serem apenas versões absurdas ou opostas da resposta correta?
5. Pelo menos duas alternativas incorretas exigem análise real, em vez de poderem ser eliminadas imediatamente pelo bom senso ou por uma palavra-denúncia?
6. Existem palavras absolutas ou extremas que denunciam uma alternativa sem que isso seja necessário ao conteúdo? Se SIM, reescreva.
7. A alternativa correta está visual e linguisticamente equilibrada com as incorretas, sem pistas de tamanho, precisão ou redação?
8. A diferença de comprimento entre as alternativas está razoavelmente equilibrada, sem uma resposta claramente muito maior ou muito menor que as demais?
9. Se for questão de afirmações, cada proposição é plausível isoladamente e o erro, quando existir, é conceitual e suficientemente sutil?
10. A dificuldade está no raciocínio e não no tamanho do texto?

Se a resposta da pergunta 1 for SIM, da pergunta 6 for SIM, ou qualquer uma das perguntas 2 a 5 e 7 a 10 for NÃO, DESCARTE a questão e crie outra antes de retornar o JSON final.
''';

      default:
        return '';
    }
  }

  Future<void> _generateQuiz() async {
    if (_imageBytesList.isEmpty) return;

    setState(() {
      _currentState = AppState.generating;
      _errorMessage = null;
      _quizLoadingTitle = 'Analisando o material...';
      _quizLoadingSubtitle = 'Criando perguntas de nível $_difficultyLevel...';
    });

    await _logAnalyticsEvent(
      'quiz_started',
      parameters: {
        'difficulty': _difficultyLevel,
        'question_count': _numberOfQuestions,
        'file_count': _imageBytesList.length,
      },
    );

    final String apiKey = (dotenv.env['GEMINI_API_KEY'] ?? '').trim();

    if (apiKey.isEmpty) {
      setState(() {
        _errorMessage = "API Key não encontrada. Verifique o arquivo .env.";
        _currentState = AppState.upload;
      });
      return;
    }

    try {
      final List<Map<String, dynamic>> promptParts = [];

      for (int i = 0; i < _imageBytesList.length; i++) {
        promptParts.add({
          "inlineData": {
            "mimeType": _mimeTypesList[i],
            "data": base64Encode(_imageBytesList[i]),
          }
        });
      }

      final difficultyInstructions = _difficultyInstructions();
      final String testId =
          DateTime.now().millisecondsSinceEpoch.toString();

      final String quizPrompt = '''
Aja como um especialista em avaliação educacional.

Analise EXCLUSIVAMENTE os arquivos anexados, que representam páginas de material de estudo.
Crie $_numberOfQuestions questões de múltipla escolha baseadas no conteúdo fornecido.

$difficultyInstructions

REGRA FUNDAMENTAL:
O nível de dificuldade deve ser determinado pela COMPLEXIDADE COGNITIVA necessária para resolver a questão e NÃO pelo tamanho do enunciado, pelo tamanho das alternativas ou pelo uso de palavras difíceis.

REGRAS GERAIS:
- Cada questão deve ter exatamente 4 alternativas.
- Deve existir somente uma alternativa correta.
- Todas as questões devem poder ser respondidas a partir do material fornecido.
- Não invente fatos ou conhecimentos externos apenas para aumentar a dificuldade.
- Antes de retornar o resultado, revise internamente as questões e substitua qualquer uma que não corresponda ao nível selecionado.
- Em cognitiveSkill, informe a habilidade cognitiva predominante realmente exigida por aquela questão e, no nível Avançado com 5 questões, mantenha-a coerente com a posição definida na Matriz V2.2.
- Em difficultyJustification, explique em uma frase curta por que aquela questão pertence ao nível escolhido.
- Esses dois campos são metadados internos de diagnóstico e não devem alterar o texto da pergunta nem das alternativas.
- Retorne estritamente o JSON definido pelo schema.
''';

      promptParts.add({
        "text": quizPrompt,
      });

      final Map<String, dynamic> payload = {
        "contents": [
          {"role": "user", "parts": promptParts}
        ],
        "generationConfig": {
          "responseMimeType": "application/json",
          "temperature": 0.2,
          "responseSchema": {
            "type": "ARRAY",
            "items": {
              "type": "OBJECT",
              "properties": {
                "question": {
                  "type": "STRING",
                  "description": "A pergunta do quiz"
                },
                "options": {
                  "type": "ARRAY",
                  "items": {"type": "STRING"},
                  "minItems": 4,
                  "maxItems": 4,
                  "description": "Exatamente 4 opções de resposta"
                },
                "correctAnswer": {
                  "type": "STRING",
                  "description": "A resposta correta exatamente igual a uma das opções"
                },
                "explanation": {
                  "type": "STRING",
                  "description": "Explicação clara de por que a alternativa correta está correta"
                },
                "cognitiveSkill": {
                  "type": "STRING",
                  "description": "Habilidade cognitiva predominante exigida: lembrança, compreensão, interpretação, aplicação, comparação, causa_consequencia, análise, avaliação ou síntese"
                },
                "difficultyJustification": {
                  "type": "STRING",
                  "description": "Justificativa curta explicando por que a questão corresponde ao nível solicitado sem usar o tamanho do texto como critério"
                }
              },
              "required": [
                "question",
                "options",
                "correctAnswer",
                "explanation",
                "cognitiveSkill",
                "difficultyJustification"
              ]
            }
          }
        }
      };

      // ============================================================
      // MODO DIAGNÓSTICO PEDAGÓGICO
      // Exibe o JSON da requisição sem imprimir as imagens em Base64.
      // ============================================================
      final List<Map<String, dynamic>> sanitizedParts = [];

      for (int i = 0; i < _imageBytesList.length; i++) {
        sanitizedParts.add({
          "inlineData": {
            "mimeType": _mimeTypesList[i],
            "data": "<BASE64 OMITIDO - ${_imageBytesList[i].length} bytes>",
          }
        });
      }

      sanitizedParts.add({
        "text": quizPrompt,
      });

      final Map<String, dynamic> sanitizedPayload = {
        "contents": [
          {"role": "user", "parts": sanitizedParts}
        ],
        "generationConfig": payload["generationConfig"],
      };

      debugPrint('');
      debugPrint('════════════════════════════════════════════════════');
      debugPrint('🧪 DIAGNÓSTICO PEDAGÓGICO DO QUIZ');
      debugPrint('🆔 Teste: $testId');
      debugPrint('📚 Nível: $_difficultyLevel');
      debugPrint('❓ Quantidade: $_numberOfQuestions');
      debugPrint('📎 Arquivos: ${_imageBytesList.length}');
      if (_difficultyLevel == 'Avançado') {
        debugPrint('🧩 Matriz Avançada V2.2: ATIVA');
        debugPrint('   A causa/efeito | B comparação | C aplicação | D afirmações | E síntese');
        debugPrint('🎯 Distratores V2.2: estruturados + equilíbrio de tamanho + erros sutis');
      }
      debugPrint('════════════════════════════════════════════════════');
      debugPrint('📤 JSON ENVIADO AO GEMINI (SANITIZADO)');
      debugPrint(
        const JsonEncoder.withIndent('  ').convert(sanitizedPayload),
      );
      debugPrint('════════════════════════════════════════════════════');

      final quizResult = await _callQuizWithFallback(
        apiKey: apiKey,
        payload: payload,
        operationName: 'QUIZ',
      );

      final response = quizResult.response;

      debugPrint('');
      debugPrint('════════════════════════════════════════════════════');
      debugPrint('🏁 RESULTADO FINAL DO QUIZ');
      debugPrint('🤖 Modelo final: ${quizResult.model}');
      debugPrint(quizResult.attempt <= _quizModels.length
          ? '🔢 Tentativa: ${quizResult.attempt}/${_quizModels.length}'
          : '🔢 Tentativa: ${quizResult.attempt} (recuperação após 503/503)');
      debugPrint('📡 Status final: ${response.statusCode}');
      debugPrint('════════════════════════════════════════════════════');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final String textResponse =
            data['candidates'][0]['content']['parts'][0]['text'];

        debugPrint('');
        debugPrint('════════════════════════════════════════════════════');
        debugPrint('📥 JSON DEVOLVIDO PELO GEMINI - QUIZ');
        debugPrint('🆔 Teste: $testId');
        debugPrint('🤖 Modelo: ${quizResult.model}');
        debugPrint('📚 Nível: $_difficultyLevel');
        debugPrint('════════════════════════════════════════════════════');

        try {
          final dynamic returnedJson = jsonDecode(textResponse);
          debugPrint(
            const JsonEncoder.withIndent('  ').convert(returnedJson),
          );
        } catch (_) {
          // Se por algum motivo o modelo devolver algo que não seja JSON válido,
          // preservamos a resposta bruta no log para diagnóstico.
          debugPrint(textResponse);
        }

        debugPrint('════════════════════════════════════════════════════');

        final List<dynamic> jsonList = jsonDecode(textResponse);
        final questions =
            jsonList.map((json) => QuizQuestion.fromJson(json)).toList();

        if (!mounted) return;

        setState(() {
          _quizData = questions;
          _currentQuestionIdx = 0;
          _userAnswers = {};

          if (_quizData.isNotEmpty) {
            _currentState = AppState.quiz;
          } else {
            _errorMessage =
                "A IA não conseguiu gerar perguntas para este arquivo.";
            _currentState = AppState.upload;
          }
        });

        if (questions.isNotEmpty) {
          await _logAnalyticsEvent(
            'quiz_generated',
            parameters: {
              'difficulty': _difficultyLevel,
              'question_count': questions.length,
              'model': quizResult.model,
              'attempt': quizResult.attempt,
            },
          );
        }

        return;
      }

      String mensagemAmigavel =
          'Erro desconhecido na API: ${response.statusCode}';

      try {
        final erroJson = jsonDecode(response.body);
        if (erroJson['error'] != null &&
            erroJson['error']['message'] != null) {
          mensagemAmigavel = erroJson['error']['message'];
        }
      } catch (_) {}

      if (response.statusCode == 429) {
        throw Exception(
          'Os modelos de IA disponíveis atingiram um limite de uso. '
          'Aguarde um pouco e tente novamente.',
        );
      }

      if (response.statusCode == 503) {
        throw Exception(
          'Os dois modelos de quiz estão com alta demanda no momento. '
          'Aguarde alguns instantes e tente novamente.',
        );
      }

      throw Exception(
        'Falha na comunicação com a IA.\nDetalhe: $mensagemAmigavel',
      );
    } catch (e) {
      await _logAnalyticsEvent(
        'quiz_generation_failed',
        parameters: {
          'difficulty': _difficultyLevel,
          'question_count': _numberOfQuestions,
          'file_count': _imageBytesList.length,
        },
      );

      if (!mounted) return;
      setState(() {
        final erroLimpo = e.toString().replaceAll('Exception: ', '');
        _errorMessage = erroLimpo;
        _currentState = AppState.upload;
      });
    }
  }

  Future<void> _generateQuizSummary() async {
    setState(() {
      _currentState = AppState.analyzingResults;
      _errorMessage = null;
    });

    int score = 0;
    for (int i = 0; i < _quizData.length; i++) {
      if (_userAnswers[i] == _quizData[i].correctAnswer) {
        score++;
      }
    }

    final int scorePercent = _quizData.isEmpty
        ? 0
        : ((score / _quizData.length) * 100).round();

    await _logAnalyticsEvent(
      'quiz_completed',
      parameters: {
        'difficulty': _difficultyLevel,
        'question_count': _quizData.length,
        'correct_answers': score,
        'score_percent': scorePercent,
      },
    );

    final String apiKey = (dotenv.env['GEMINI_API_KEY'] ?? '').trim();

    if (apiKey.isEmpty) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "API Key não encontrada. Verifique o arquivo .env.";
        _currentState = AppState.results;
      });
      return;
    }

    try {
      String performanceReport =
          "O aluno respondeu um quiz de $_numberOfQuestions questões "
          "(nível $_difficultyLevel). Desempenho:\n";

      for (int i = 0; i < _quizData.length; i++) {
        final q = _quizData[i];
        final userAns = _userAnswers[i] ?? "Não respondeu";
        final isCorrect = userAns == q.correctAnswer;

        performanceReport +=
            "Q${i + 1}: ${q.question} | Correta: ${q.correctAnswer} | "
            "Aluno: $userAns (${isCorrect ? 'Acertou' : 'Errou'})\n";
      }

      performanceReport +=
          "\nCom base nisso ($score/${_quizData.length} acertos), "
          "forneça um feedback pedagógico personalizado e encorajador.";

      final Map<String, dynamic> payload = {
        "contents": [
          {
            "role": "user",
            "parts": [
              {
                "text": performanceReport +
                    "\nRetorne estritamente em formato JSON contendo uma chave "
                    "'teacher_feedback' com a mensagem de feedback."
              }
            ]
          }
        ],
        "generationConfig": {
          "responseMimeType": "application/json",
          "temperature": 0.3,
          "responseSchema": {
            "type": "OBJECT",
            "properties": {
              "teacher_feedback": {
                "type": "STRING",
                "description": "Mensagem de feedback do professor"
              }
            },
            "required": ["teacher_feedback"]
          }
        }
      };

      final feedbackResult = await _callQuizWithFallback(
        apiKey: apiKey,
        payload: payload,
        operationName: 'FEEDBACK DO QUIZ',
      );

      final response = feedbackResult.response;

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        String textResponse =
            data['candidates'][0]['content']['parts'][0]['text'];

        textResponse =
            textResponse.replaceAll('```json', '').replaceAll('```', '').trim();

        String finalFeedback;

        try {
          final Map<String, dynamic> jsonResult = jsonDecode(textResponse);
          final String rawFeedback =
              jsonResult['teacher_feedback'] ?? "Aqui está o seu resultado!";

          try {
            finalFeedback = Uri.decodeFull(rawFeedback);
          } catch (_) {
            finalFeedback = rawFeedback;
          }
        } catch (_) {
          try {
            finalFeedback = Uri.decodeFull(textResponse);
          } catch (_) {
            finalFeedback = textResponse;
          }
        }

        if (!mounted) return;
        setState(() {
          _teacherFeedback = finalFeedback;
          _currentState = AppState.results;
        });

        await _logAnalyticsEvent(
          'quiz_feedback_generated',
          parameters: {
            'model': feedbackResult.model,
            'attempt': feedbackResult.attempt,
          },
        );

        return;
      }

      // Se o feedback falhar nos dois modelos, não bloqueia o resultado do aluno.
      await _logAnalyticsEvent('quiz_feedback_failed');

      if (!mounted) return;
      setState(() {
        _teacherFeedback =
            "Seu resultado foi calculado normalmente. O feedback detalhado "
            "do Professor AI está temporariamente indisponível; tente novamente mais tarde.";
        _currentState = AppState.results;
      });
    } catch (e) {
      // O placar não deve ser perdido por uma falha apenas no feedback da IA.
      if (!mounted) return;
      debugPrint('⚠️ Falha ao gerar feedback do quiz: $e');
      await _logAnalyticsEvent('quiz_feedback_failed');
      setState(() {
        _teacherFeedback =
            "Seu resultado foi calculado normalmente. O feedback detalhado "
            "do Professor AI está temporariamente indisponível; tente novamente mais tarde.";
        _currentState = AppState.results;
      });
    }
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Sobre',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'O Educa+.ai é o motor dos seus estudos. Um assistente de inteligência artificial criado para simplificar seu aprendizado, transformar anotações em quizzes interativos e impulsionar seus resultados em um só lugar.',
                style: TextStyle(fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 24),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final Uri url = Uri.parse('https://rodrigocosta1983.github.io/rodrigocosta-dev.com/');

                  if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                    debugPrint('Não foi possível abrir o link: $url');
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Icon(Icons.language, color: Colors.indigo.shade600, size: 28),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Desenvolvido por',
                            style: TextStyle(fontSize: 14, color: Colors.black87),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Rodrigo Costa',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade700,
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.indigo.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Center(
                child: Text(
                  'Versão do App: 1.2.0+13',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Fechar',
                style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUploadSection() {
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_upload_rounded, size: 64, color: Colors.indigo.shade300),
                  const SizedBox(height: 16),
                  const Text(
                    'Transforme suas anotações com IA',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tire fotos ou selecione PDFs do seu material e escolha se deseja gerar um Quiz para se testar ou um Resumo para salvar!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),

                  const SizedBox(height: 24),

                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Questões:',
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.indigo.shade100),
                            ),
                            child: DropdownButton<int>(
                              value: _numberOfQuestions,
                              underline: const SizedBox(),
                              icon: const Icon(Icons.arrow_drop_down, color: Colors.indigo),
                              style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.bold, fontSize: 14),
                              items: [5, 10, 15, 20].map((int value) {
                                return DropdownMenuItem<int>(
                                  value: value,
                                  child: Text('$value'),
                                );
                              }).toList(),
                              onChanged: (int? newValue) {
                                if (newValue != null) setState(() => _numberOfQuestions = newValue);
                              },
                            ),
                          ),
                        ],
                      ),

                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Nível:',
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange.shade100),
                            ),
                            child: DropdownButton<String>(
                              value: _difficultyLevel,
                              underline: const SizedBox(),
                              icon: Icon(Icons.arrow_drop_down, color: Colors.orange.shade800),
                              style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold, fontSize: 14),
                              items: ['Simples', 'Intermediário', 'Avançado'].map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                if (newValue != null) setState(() => _difficultyLevel = newValue);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  if (_imageBytesList.isNotEmpty) ...[
                    Container(
                      alignment: Alignment.centerLeft,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${_imageBytesList.length} arquivo(s) selecionado(s):',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                      ),
                    ),
                    SizedBox(
                      height: 160,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _imageBytesList.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 12.0),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: _mimeTypesList[index] == 'application/pdf'
                                      ? Container(
                                    height: 160,
                                    width: 120,
                                    color: Colors.red.shade50,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.picture_as_pdf, size: 48, color: Colors.red.shade400),
                                        const SizedBox(height: 8),
                                        Text('PDF', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  )
                                      : Image.memory(
                                    _imageBytesList[index],
                                    height: 160,
                                    width: 120,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: InkWell(
                                    onTap: () => _removeImage(index),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close, color: Colors.white, size: 16),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickImage(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Fotos'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickPdf,
                            icon: const Icon(Icons.picture_as_pdf),
                            label: const Text('PDF'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickImage(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Câmera'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _generateQuiz,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Gerar Quiz Interativo', style: TextStyle(fontSize: 16)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _generateSummary,
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Gerar Resumo em PDF', style: TextStyle(fontSize: 16)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade200, width: 2),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // SizedBox(
                    //   width: double.infinity,
                    //   child: OutlinedButton.icon(
                    //     onPressed: _generateTutorGuide,
                    //     icon: const Icon(Icons.family_restroom),
                    //     label: const Text('Gerar Guia para os Pais', style: TextStyle(fontSize: 16)),
                    //     style: OutlinedButton.styleFrom(
                    //       foregroundColor: Colors.teal.shade700,
                    //       side: BorderSide(color: Colors.teal.shade200, width: 2),
                    //       padding: const EdgeInsets.symmetric(vertical: 16),
                    //       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    //     ),
                    //   ),
                    // ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickImage(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Fotos'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickPdf,
                            icon: const Icon(Icons.picture_as_pdf),
                            label: const Text('PDFs'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _pickImage(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Câmera'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                      ),
                    )
                  ]
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingSection(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuizSection() {
    final question = _quizData[_currentQuestionIdx];
    final hasAnswered = _userAnswers.containsKey(_currentQuestionIdx);

    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Chip(
                        label: Text('Questão ${_currentQuestionIdx + 1} de ${_quizData.length}'),
                        backgroundColor: Colors.indigo.shade50,
                        labelStyle: TextStyle(color: Colors.indigo.shade700, fontWeight: FontWeight.bold),
                        side: BorderSide.none,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: _resetApp,
                      )
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    question.question,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.4),
                  ),
                  const SizedBox(height: 32),

                  ...question.options.map((option) {
                    final isSelected = _userAnswers[_currentQuestionIdx] == option;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _userAnswers[_currentQuestionIdx] = option;
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.indigo.shade50 : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? Colors.indigo : Colors.grey.shade300,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                color: isSelected ? Colors.indigo : Colors.grey,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  option,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: isSelected ? Colors.indigo.shade900 : Colors.black87,
                                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (_currentQuestionIdx > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _currentQuestionIdx--;
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Anterior'),
                          ),
                        ),
                      if (_currentQuestionIdx > 0) const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: hasAnswered
                              ? () {
                            if (_currentQuestionIdx < _quizData.length - 1) {
                              setState(() {
                                _currentQuestionIdx++;
                              });
                            } else {
                              _generateQuizSummary();
                            }
                          }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            _currentQuestionIdx < _quizData.length - 1
                                ? 'Próxima Questão'
                                : 'Finalizar e Ver Resultados',
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsSection() {
    int score = 0;
    for (int i = 0; i < _quizData.length; i++) {
      if (_userAnswers[i] == _quizData[i].correctAnswer) {
        score++;
      }
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 45,
                      backgroundColor: Colors.indigo,
                      child: Text(
                        '$score/${_quizData.length}',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Pontuação Final',
                      style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      score >= (_quizData.length / 2) ? 'Você está indo muito bem! Continue assim.' : 'Bom esforço! Continue revisando os pontos.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 32),

                    // --- LISTA DE QUESTÕES (GABARITO DETALHADO) ---
                    ...List.generate(_quizData.length, (index) {
                      final q = _quizData[index];
                      final userAnswer = _userAnswers[index];
                      final isCorrect = userAnswer == q.correctAnswer;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isCorrect ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isCorrect ? Colors.green.shade200 : Colors.red.shade200,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  isCorrect ? Icons.check_circle : Icons.cancel,
                                  color: isCorrect ? Colors.green : Colors.red,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '${index + 1}. ${q.question}',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 36.0, top: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Sua resposta: $userAnswer',
                                    style: TextStyle(
                                      color: isCorrect ? Colors.green.shade700 : Colors.grey.shade600,
                                      decoration: isCorrect ? TextDecoration.none : TextDecoration.lineThrough,
                                    ),
                                  ),
                                  if (!isCorrect)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(
                                        'Correta: ${q.correctAnswer}',
                                        style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '💡 Explicação: ${q.explanation}',
                                      style: TextStyle(color: Colors.grey.shade800),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 16),

                    // --- FEEDBACK GERAL DO PROFESSOR IA (LOGO ABAIXO DO GABARITO) ---
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.indigo.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '💡 Feedback do Professor AI',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _teacherFeedback,
                            style: TextStyle(color: Colors.indigo.shade900, height: 1.4, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _resetApp,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Escanear Outro Arquivo'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Educa+.ai', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.indigo),
            onPressed: () => _showAboutDialog(context),
            tooltip: 'Sobre o App',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: () {
          switch (_currentState) {
            case AppState.upload:
              return _buildUploadSection();
            case AppState.generating:
              return _buildLoadingSection(
                _quizLoadingTitle,
                _quizLoadingSubtitle,
              );
            case AppState.generatingSummary:
              return _buildLoadingSection('Lendo o conteúdo...', 'A IA está estruturando o resumo, localizando e recortando apoios visuais do próprio material...');
            case AppState.quiz:
              return _buildQuizSection();
            case AppState.analyzingResults:
              return _buildLoadingSection('Avaliando seu desempenho...', 'O professor IA está preparando seu feedback personalizado...');
            case AppState.results:
              return _buildResultsSection();
            case AppState.generatingTutorGuide:
              return _buildLoadingSection('Preparando o Guia...', 'A IA está traduzindo a matéria em dicas fáceis para você ensinar...');
          }
        }(),
      ),
    );
  }
}

class PdfPreviewScreen extends StatelessWidget {
  final String? summaryText;
  final StudySummary? structuredSummary;
  final List<Uint8List> sourceBytes;
  final List<String> sourceMimeTypes;
  final Map<int, Uint8List> preparedSourceVisuals;

  const PdfPreviewScreen({
    super.key,
    this.summaryText,
    this.structuredSummary,
    this.sourceBytes = const <Uint8List>[],
    this.sourceMimeTypes = const <String>[],
    this.preparedSourceVisuals = const <int, Uint8List>{},
  }) : assert(
          summaryText != null || structuredSummary != null,
          'Informe summaryText ou structuredSummary.',
        );

  @override
  Widget build(BuildContext context) {
    final isStructured = structuredSummary != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isStructured ? 'Seu Resumo de Estudo' : 'Seu Resumo em PDF',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: PdfPreview(
        build: (format) {
          if (structuredSummary != null) {
            return PdfService.generateStructuredSummaryPdf(
              format,
              structuredSummary!,
              sourceBytes: sourceBytes,
              sourceMimeTypes: sourceMimeTypes,
              preparedSourceVisuals: preparedSourceVisuals,
            );
          }

          return PdfService.generateSummaryPdf(
            format,
            summaryText ?? '',
          );
        },
        allowPrinting: true,
        allowSharing: true,
        canChangeOrientation: false,
        canChangePageFormat: false,
        pdfFileName: isStructured
            ? 'Resumo_Estruturado_EducaMais.pdf'
            : 'Resumo_EducaMais.pdf',
        previewPageMargin: const EdgeInsets.all(12),
        scrollViewDecoration: BoxDecoration(color: Colors.grey.shade100),
      ),
    );
  }
}
