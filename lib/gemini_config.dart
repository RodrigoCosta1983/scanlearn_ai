/*
|--------------------------------------------------------------------------
| EDUCA+.AI — CONFIGURAÇÃO GEMINI
|--------------------------------------------------------------------------
|
| Centraliza os modelos e parâmetros operacionais usados pelas chamadas
| à Gemini API. Nenhuma API key deve ser armazenada neste arquivo.
|
| Estratégia atual:
|
| QUIZ / FEEDBACK:
| gemini-3.5-flash-lite
|        ↓
| gemini-3.1-flash-lite
|        ↓
| gemini-3.8-flash
|
| RESUMO:
| gemini-3.8-flash
|        ↓
| gemini-3.6-flash
|        ↓
| gemini-3.5-flash-lite
|        ↓
| gemini-3.1-flash-lite
|
| O Quiz prioriza capacidade/cota.
| O Resumo prioriza qualidade e depois desce para modelos de maior cota.
|
|--------------------------------------------------------------------------
*/

class GeminiConfig {
  GeminiConfig._();

  // IDs oficiais usados pela API.
  static const String flash38 = 'gemini-3.8-flash';
  static const String flash36 = 'gemini-3.6-flash';
  static const String flashLite35 = 'gemini-3.5-flash-lite';
  static const String flashLite31 = 'gemini-3.1-flash-lite';

  // Quiz e feedback: preserva primeiro os modelos Lite de maior cota.
  static const List<String> quizModels = <String>[
    flashLite35,
    flashLite31,
    flash38,
  ];

  // Resumo: prioriza qualidade e usa os Lite como reserva de capacidade.
  static const List<String> summaryModels = <String>[
    flash38,
    flash36,
    flashLite35,
    flashLite31,
  ];

  // Guia do Tutor está desativado na interface, mas permanece configurado.
  static const List<String> tutorGuideModels = <String>[
    flashLite35,
    flashLite31,
  ];

  // Após 503 em toda a cadeia do Quiz/Feedback, uma única nova tentativa
  // é feita no 3.5 Flash Lite após pequena pausa.
  static const String quizRecoveryModel = flashLite35;

  // HTTPs temporários/de capacidade que justificam tentar o próximo modelo.
  static const Set<int> fallbackStatusCodes = <int>{
    404,
    408,
    429,
    500,
    502,
    503,
    504,
  };

  static const Duration quizWarningAfter = Duration(seconds: 45);
  static const Duration quizTimeout = Duration(seconds: 60);
  static const Duration summaryTimeout = Duration(seconds: 90);
  static const Duration retry503Delay = Duration(seconds: 8);

  static String generateContentUrl({
    required String model,
    required String apiKey,
  }) {
    return 'https://generativelanguage.googleapis.com/v1beta/models/'
        '$model:generateContent?key=$apiKey';
  }
}
