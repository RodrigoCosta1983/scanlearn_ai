ScanLearn.ai - Transforme suas anotações em Quizzes com IA

Read in English

ScanLearn.ai é um aplicativo educacional inovador desenvolvido em Flutter que utiliza o poder da Inteligência Artificial do Google (Gemini) para transformar fotos de materiais de estudo — como livros, apostilas e cadernos — em quizzes interativos de múltipla escolha em questão de segundos. Focado no estudo ativo, o app ajuda estudantes a testarem seus conhecimentos de forma dinâmica e personalizada.

✨ Funcionalidades Principais

O aplicativo foi construído com foco na praticidade e na eficiência do aprendizado ativo:

Visão Computacional e IA

Leitura Inteligente de Imagens: Suporte para envio de múltiplas fotos via Galeria ou Câmera do dispositivo. A IA lê e interpreta os textos e contextos das imagens.

Geração Dinâmica de Quizzes: Criação instantânea de perguntas de múltipla escolha estritamente baseadas no material escaneado, eliminando alucinações da IA.

Feedback Pedagógico Personalizado: Ao final do teste, a Inteligência Artificial analisa os erros e acertos do aluno e gera uma mensagem de feedback exclusiva e encorajadora.

Customização do Estudo

Níveis de Dificuldade: O usuário pode escolher a complexidade das perguntas (Simples, Intermediário ou Avançado), permitindo desde revisões básicas até a preparação para exames com "pegadinhas".

Controle de Quantidade: Flexibilidade para gerar quizzes rápidos (5 ou 10 questões) ou testes mais longos (15 ou 20 questões) a partir do mesmo material.

Interface e Experiência do Usuário (UX/UI)

Design Limpo e Focado: Interface minimalista e sem distrações, garantindo que o foco do usuário permaneça no conteúdo e no aprendizado.

Navegação Fluida: Transições de estado suaves entre as etapas de upload, carregamento (geração da IA), resolução do quiz e visualização de resultados.

Gabarito Detalhado: Tela final de resultados que não apenas mostra a pontuação, mas revisa as respostas escolhidas pelo usuário, indicando a alternativa correta.

Segurança e Boas Práticas

Proteção de Credenciais: Implementação do pacote flutter_dotenv para garantir que a chave de API (API Key) do Google Gemini fique salva localmente e isolada, sem nunca ser exposta no repositório do GitHub.

📸 Telas do Aplicativo

(Instrução: Faça o upload das capturas de tela do seu app para a pasta do projeto e substitua as URLs abaixo pelos links reais das imagens)

Upload e Configuração

IA Gerando o Quiz

Respondendo o Quiz

Resultados e Feedback









🚀 Tecnologias Utilizadas

Framework: Flutter

Linguagem: Dart

Inteligência Artificial: API do Google Gemini 1.5 Flash

Pacotes Principais:

http (Para consumo seguro da API REST do Gemini)

image_picker (Para acesso nativo à câmera e galeria)

flutter_dotenv (Para gerenciamento seguro de variáveis de ambiente e chaves de API)

🔮 Próximos Passos (Roadmap)

Histórico de Quizzes: Salvar os testes gerados no banco de dados (Firebase ou SQLite) para que o usuário possa refazê-los no futuro.

Exportação de Resumos: Permitir que a IA gere um resumo em texto (PDF) da página escaneada, além do quiz.

Gamificação: Adicionar sistema de pontos, ofensivas (streaks) diárias e conquistas para manter os alunos engajados.

Suporte a PDFs: Permitir que o usuário faça o upload de arquivos PDF (slides de aulas) ao invés de apenas fotos.

🏁 Como Executar o Projeto

Pré-requisitos:

Ter o Flutter SDK instalado.

Ter um editor de código como VS Code ou Android Studio.

Obter uma API Key gratuita no Google AI Studio.

Configuração da Chave de API (Importante):

Clone este repositório.

Na raiz do projeto (mesma pasta do pubspec.yaml), crie um arquivo chamado exatamente .env.

Dentro do arquivo .env, adicione a sua chave de API desta forma (sem aspas):

GEMINI_API_KEY=SuaChaveGeradaNoGoogleAqui


Execução:

# Clone o repositório
git clone https://github.com/RodrigoCosta1983/scanlearn_ai.git

# Entre na pasta do projeto
cd scanlearn_ai

# Instale as dependências
flutter pub get

# Execute o aplicativo
flutter run