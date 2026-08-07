import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  // Garante que os bindings do Flutter estão inicializados antes de carregar o .env
  WidgetsFlutterBinding.ensureInitialized();

  // Carrega o arquivo .env
  await dotenv.load(fileName: ".env");

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

class ScanLearnApp extends StatelessWidget {
  const ScanLearnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScanLearn.ai',
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

enum AppState { upload, generating, quiz, results }

class _ScanLearnHomePageState extends State<ScanLearnHomePage> {
  AppState _currentState = AppState.upload;

  List<Uint8List> _imageBytesList = [];
  List<String> _mimeTypesList = [];

  List<QuizQuestion> _quizData = [];
  int _currentQuestionIdx = 0;
  Map<int, String> _userAnswers = {};
  String? _errorMessage;

  int _numberOfQuestions = 5; // Valor padrão de questões
  String _difficultyLevel = 'Intermediário'; // Nível de dificuldade padrão

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        // Permite selecionar múltiplas imagens da galeria de uma vez
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
        }
      } else {
        // Câmera captura uma por vez, mas vamos adicionando à lista
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
      _errorMessage = null;
      // Não resetamos _numberOfQuestions e _difficultyLevel para lembrar a preferência do usuário
    });
  }

  Future<void> _generateQuiz() async {
    if (_imageBytesList.isEmpty) return;

    setState(() {
      _currentState = AppState.generating;
      _errorMessage = null;
    });

    // Puxa a chave de forma segura do arquivo .env
    final String apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

    if (apiKey.isEmpty) {
      setState(() {
        _errorMessage = "API Key não encontrada. Verifique o arquivo .env.";
        _currentState = AppState.upload;
      });
      return;
    }

    final String apiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent?key=$apiKey';

    try {
      List<Map<String, dynamic>> promptParts = [];

      // Adiciona cada imagem processada na lista de requisição
      for (int i = 0; i < _imageBytesList.length; i++) {
        promptParts.add({
          "inlineData": {
            "mimeType": _mimeTypesList[i],
            "data": base64Encode(_imageBytesList[i])
          }
        });
      }

      // Adiciona o texto de instrução no final
      promptParts.add({
        "text": "Aja como um professor especialista criando material didático. Analise as imagens anexadas, que representam páginas de um material de estudo. Crie um quiz de múltipla escolha com $_numberOfQuestions perguntas com nível de dificuldade $_difficultyLevel baseadas puramente no conteúdo destas imagens. Se o nível for Simples foque no mais básico, se for Avançado crie pegadinhas e exija raciocínio profundo. Retorne o resultado estritamente no formato JSON requisitado."
      });

      final Map<String, dynamic> payload = {
        "contents": [
          {
            "role": "user",
            "parts": promptParts
          }
        ],
        "generationConfig": {
          "responseMimeType": "application/json",
          "temperature": 0.2,
          "responseSchema": {
            "type": "ARRAY",
            "items": {
              "type": "OBJECT",
              "properties": {
                "question": {"type": "STRING", "description": "A pergunta do quiz"},
                "options": {
                  "type": "ARRAY",
                  "items": {"type": "STRING"},
                  "description": "Exatamente 4 opções de resposta"
                },
                "correctAnswer": {"type": "STRING", "description": "A resposta correta igual a uma das opções"},
                "explanation": {"type": "STRING", "description": "Explicação da resposta"}
              },
              "required": ["question", "options", "correctAnswer", "explanation"]
            }
          }
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

        final List<dynamic> jsonList = jsonDecode(textResponse);

        setState(() {
          _quizData = jsonList.map((json) => QuizQuestion.fromJson(json)).toList();
          if (_quizData.isNotEmpty) {
            _currentState = AppState.quiz;
          } else {
            _errorMessage = "A IA não conseguiu gerar perguntas para esta imagem.";
            _currentState = AppState.upload;
          }
        });
      } else {
        throw Exception('Erro na API: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Falha ao gerar o quiz. Verifique sua conexão e se a foto está legível. Detalhes: $e";
        _currentState = AppState.upload;
      });
    }
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
                    'Transforme suas anotações em Quiz',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tire uma foto da página do livro, apostila ou caderno. Nossa IA vai ler o conteúdo e gerar um quiz na hora!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),

                  const SizedBox(height: 24),

                  // Seleção de Quantidade de Questões
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Quantidade:',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.indigo.shade100),
                        ),
                        child: DropdownButton<int>(
                          value: _numberOfQuestions,
                          underline: const SizedBox(),
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.indigo),
                          style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.bold, fontSize: 16),
                          items: [5, 10, 15, 20].map((int value) {
                            return DropdownMenuItem<int>(
                              value: value,
                              child: Text('$value'),
                            );
                          }).toList(),
                          onChanged: (int? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _numberOfQuestions = newValue;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Seleção de Dificuldade
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Dificuldade:',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade100),
                        ),
                        child: DropdownButton<String>(
                          value: _difficultyLevel,
                          underline: const SizedBox(),
                          icon: Icon(Icons.arrow_drop_down, color: Colors.orange.shade800),
                          style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold, fontSize: 16),
                          items: ['Simples', 'Intermediário', 'Avançado'].map((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _difficultyLevel = newValue;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  if (_imageBytesList.isNotEmpty) ...[
                    Container(
                      alignment: Alignment.centerLeft,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${_imageBytesList.length} página(s) selecionada(s):',
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
                                  child: Image.memory(
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
                            icon: const Icon(Icons.add_photo_alternate),
                            label: const Text('Mais Fotos'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickImage(ImageSource.camera),
                            icon: const Icon(Icons.add_a_photo),
                            label: const Text('Câmera'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _generateQuiz,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Gerar Quiz'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickImage(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Galeria'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
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

  Widget _buildLoadingSection() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          const Text(
            'Analisando o material...',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Criando perguntas de nível $_difficultyLevel...',
            style: TextStyle(color: Colors.grey.shade600),
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
                              setState(() {
                                _currentState = AppState.results;
                              });
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
                      radius: 50,
                      backgroundColor: Colors.indigo,
                      child: Text(
                        '$score/${_quizData.length}',
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Quiz Finalizado!',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 32),

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

                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _resetApp,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Escanear Outro Capítulo'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo.shade50,
                          foregroundColor: Colors.indigo.shade700,
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
            Text('ScanLearn.ai', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: () {
          switch (_currentState) {
            case AppState.upload:
              return _buildUploadSection();
            case AppState.generating:
              return _buildLoadingSection();
            case AppState.quiz:
              return _buildQuizSection();
            case AppState.results:
              return _buildResultsSection();
          }
        }(),
      ),
    );
  }
}