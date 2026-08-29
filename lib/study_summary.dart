/*
|--------------------------------------------------------------------------
| EDUCA+.AI — MODELOS DO RESUMO E INTELIGÊNCIA VISUAL
|--------------------------------------------------------------------------
|
| Arquivo responsável pelas estruturas de dados utilizadas pelo sistema
| de Resumo Inteligente do Educa+.ai.
|
| Define os modelos que representam:
|
| • Resumo completo do material.
| • Visão geral.
| • Seções de estudo.
| • Pontos-chave.
| • Revisão rápida.
| • Necessidade de apoio visual.
| • Imagens reaproveitadas do material original.
| • Coordenadas para recorte inteligente.
| • Rotação/orientação da imagem.
| • Justificativa pedagógica para a escolha do visual.
| • Visuais estruturados criados pelo Educa+.ai:
|     - timeline;
|     - comparison;
|     - hierarchy;
|     - flow;
|     - cards.
|
| Este arquivo funciona como a camada de dados entre:
|
| Gemini
|   ↓
| JSON estruturado
|   ↓
| StudySummary
|   ↓
| PDF Service
|
| Versão atual:
| Inteligência Visual V2-B.1
|
|--------------------------------------------------------------------------
*/


class SummaryVisualElement {
  final String label;
  final String description;
  final String leftValue;
  final String rightValue;
  final int level;

  const SummaryVisualElement({
    required this.label,
    required this.description,
    required this.leftValue,
    required this.rightValue,
    required this.level,
  });

  factory SummaryVisualElement.fromJson(Map<String, dynamic> json) {
    final rawLevel = json['level'];
    final parsedLevel = rawLevel is num
        ? rawLevel.toInt()
        : int.tryParse(rawLevel?.toString() ?? '') ?? 0;

    return SummaryVisualElement(
      label: json['label']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      leftValue: json['leftValue']?.toString() ?? '',
      rightValue: json['rightValue']?.toString() ?? '',
      level: parsedLevel.clamp(0, 4).toInt(),
    );
  }
}

class SummarySection {
  final String heading;
  final String content;
  final List<String> keyPoints;
  final bool needsVisual;
  final String visualType;
  final String visualTitle;
  final String visualCaption;

  // V2-B.1 — justificativa interna da escolha entre visual do material e visual estruturado.
  // Não é exibida ao aluno; serve para diagnóstico e auditoria pedagógica.
  final String visualDecisionReason;

  // V2-A — reutilização de visual presente no próprio material.
  final bool useSourceVisual;
  final int sourceFileIndex;
  final String sourceVisualReason;

  // V2-A.1/V2-B — caixa de recorte normalizada em 0..1000.
  final int sourceCropX;
  final int sourceCropY;
  final int sourceCropWidth;
  final int sourceCropHeight;

  // V2-B incorpora o ajuste de orientação pendente da V2-A.2.
  // Rotação HORÁRIA aplicada após o recorte: 0, 90, 180 ou 270.
  final int sourceRotation;

  // V2-B — quando não existe figura adequada no material, o Gemini descreve
  // um visual educacional estruturado e o próprio PDF o desenha. Isso evita
  // uma segunda chamada à API e mantém todo o conteúdo fiel às fontes.
  final String generatedVisualKind;
  final String generatedVisualLeftTitle;
  final String generatedVisualRightTitle;
  final List<SummaryVisualElement> generatedVisualElements;

  const SummarySection({
    required this.heading,
    required this.content,
    required this.keyPoints,
    required this.needsVisual,
    required this.visualType,
    required this.visualTitle,
    required this.visualCaption,
    required this.visualDecisionReason,
    required this.useSourceVisual,
    required this.sourceFileIndex,
    required this.sourceVisualReason,
    required this.sourceCropX,
    required this.sourceCropY,
    required this.sourceCropWidth,
    required this.sourceCropHeight,
    required this.sourceRotation,
    required this.generatedVisualKind,
    required this.generatedVisualLeftTitle,
    required this.generatedVisualRightTitle,
    required this.generatedVisualElements,
  });

  factory SummarySection.fromJson(Map<String, dynamic> json) {
    final rawIndex = json['sourceFileIndex'];
    int parsedIndex = 0;

    if (rawIndex is int) {
      parsedIndex = rawIndex;
    } else if (rawIndex is num) {
      parsedIndex = rawIndex.toInt();
    } else {
      parsedIndex = int.tryParse(rawIndex?.toString() ?? '') ?? 0;
    }

    int parseCrop(String key) {
      final value = json[key];
      if (value is int) return value.clamp(0, 1000).toInt();
      if (value is num) return value.toInt().clamp(0, 1000).toInt();
      return (int.tryParse(value?.toString() ?? '') ?? 0)
          .clamp(0, 1000)
          .toInt();
    }

    int parseRotation() {
      final raw = json['sourceRotation'];
      final value = raw is num
          ? raw.toInt()
          : int.tryParse(raw?.toString() ?? '') ?? 0;
      return const <int>[0, 90, 180, 270].contains(value) ? value : 0;
    }

    final rawElements = json['generatedVisualElements'] as List<dynamic>? ?? const [];

    return SummarySection(
      heading: json['heading']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      keyPoints: List<String>.from(
        (json['keyPoints'] as List<dynamic>? ?? const []).map((e) => e.toString()),
      ),
      needsVisual: json['needsVisual'] == true,
      visualType: json['visualType']?.toString() ?? '',
      visualTitle: json['visualTitle']?.toString() ?? '',
      visualCaption: json['visualCaption']?.toString() ?? '',
      visualDecisionReason: json['visualDecisionReason']?.toString() ?? '',
      useSourceVisual: json['useSourceVisual'] == true,
      sourceFileIndex: parsedIndex,
      sourceVisualReason: json['sourceVisualReason']?.toString() ?? '',
      sourceCropX: parseCrop('sourceCropX'),
      sourceCropY: parseCrop('sourceCropY'),
      sourceCropWidth: parseCrop('sourceCropWidth'),
      sourceCropHeight: parseCrop('sourceCropHeight'),
      sourceRotation: parseRotation(),
      generatedVisualKind: json['generatedVisualKind']?.toString() ?? 'none',
      generatedVisualLeftTitle: json['generatedVisualLeftTitle']?.toString() ?? '',
      generatedVisualRightTitle: json['generatedVisualRightTitle']?.toString() ?? '',
      generatedVisualElements: rawElements
          .whereType<Map<String, dynamic>>()
          .map(SummaryVisualElement.fromJson)
          .toList(),
    );
  }
}

class StudySummary {
  final String title;
  final String overview;
  final List<SummarySection> sections;
  final List<String> finalReview;

  const StudySummary({
    required this.title,
    required this.overview,
    required this.sections,
    required this.finalReview,
  });

  factory StudySummary.fromJson(Map<String, dynamic> json) {
    final rawSections = json['sections'] as List<dynamic>? ?? const [];

    return StudySummary(
      title: json['title']?.toString() ?? 'Resumo de Estudo',
      overview: json['overview']?.toString() ?? '',
      sections: rawSections
          .whereType<Map<String, dynamic>>()
          .map(SummarySection.fromJson)
          .toList(),
      finalReview: List<String>.from(
        (json['finalReview'] as List<dynamic>? ?? const []).map((e) => e.toString()),
      ),
    );
  }
}
