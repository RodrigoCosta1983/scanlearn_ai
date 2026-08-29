# Educa+.ai

> Transforme seu próprio material de estudo em quizzes inteligentes e resumos visuais com IA.

O **Educa+.ai** é um aplicativo educacional desenvolvido em **Flutter** que utiliza a **API do Google Gemini** para transformar fotos de livros, apostilas, cadernos e outros materiais de estudo em experiências de aprendizagem personalizadas.

A proposta do projeto vai além de simplesmente gerar perguntas ou resumir textos: o app procura **entender o conteúdo enviado pelo aluno, adaptar o nível cognitivo das questões e reorganizar o material em uma estrutura didática mais fácil de revisar**.

Atualmente, o Educa+.ai possui dois grandes motores educacionais:

- **Quiz Inteligente — Motor Pedagógico V2.2**
- **Resumo Estruturado — Inteligência Visual V2-B.1**

---

## ✨ Funcionalidades principais

### 📸 Leitura inteligente do material

- Envio de múltiplas imagens pela **galeria** ou **câmera** do dispositivo.
- Análise multimodal do conteúdo com Google Gemini.
- As perguntas e os resumos são produzidos com base no **material fornecido pelo aluno**.
- Suporte a várias páginas em uma única sessão de estudo.

---

## 🧠 Quiz Inteligente — Motor Pedagógico V2.2

O quiz foi desenvolvido para que os níveis de dificuldade não representem apenas perguntas com textos maiores, mas sim **diferentes níveis de raciocínio**.

### Níveis de dificuldade

#### 🟢 Simples

Voltado para revisão básica e compreensão inicial.

Prioriza:

- reconhecimento;
- identificação;
- conceitos fundamentais;
- compreensão direta;
- perguntas sem pegadinhas ou raciocínio em múltiplas etapas.

#### 🟡 Intermediário

Voltado principalmente para interpretação e aplicação do conteúdo.

Prioriza:

- interpretação;
- comparação;
- causa e consequência;
- aplicação simples;
- inferência;
- resolução em uma ou duas etapas de raciocínio.

#### 🔴 Avançado

Pensado para estudantes que desejam questões mais próximas do estilo de **vestibulares, concursos e avaliações de maior exigência cognitiva**.

A geração procura distribuir as questões entre diferentes habilidades:

1. causa e consequência;
2. comparação entre conceitos;
3. aplicação em situação nova;
4. análise de afirmações;
5. síntese e integração de informações.

Uma questão avançada não deve ser considerada válida apenas por possuir um enunciado maior. Ela deve exigir interpretação, aplicação, análise ou integração de duas ou mais informações do material.

### Distratores estruturados

Na versão V2.2, as alternativas incorretas são orientadas a representar **erros conceituais plausíveis**, reduzindo respostas absurdas ou facilmente elimináveis.

O objetivo é fazer com que a dificuldade venha do **raciocínio**, e não de truques de linguagem.

### Quantidade de questões

O usuário pode escolher entre:

- 5 questões;
- 10 questões;
- 15 questões;
- 20 questões.

### Feedback pedagógico

Ao final do quiz, o Gemini analisa o desempenho do aluno e produz um feedback personalizado com base nos acertos e erros apresentados durante aquela sessão.

---

## 📚 Resumo Estruturado — Inteligência Visual V2-B.1

O Educa+.ai também transforma o material enviado em um **resumo estruturado exportável em PDF**.

O resumo pode conter:

- título do conteúdo;
- visão geral;
- seções temáticas;
- explicações resumidas;
- pontos-chave;
- revisão rápida;
- imagens reaproveitadas do próprio material;
- recursos visuais didáticos produzidos automaticamente.

### 🖼️ Inteligência Visual

O sistema avalia cada seção e decide se um recurso visual realmente ajuda na aprendizagem.

Quando existe uma imagem útil no material original, o Educa+.ai pode:

1. identificar em qual arquivo ela está;
2. localizar a região relevante da foto;
3. recortar somente o conteúdo necessário;
4. corrigir sua orientação;
5. inserir o resultado na seção correspondente do PDF.

O app evita usar uma imagem apenas como decoração: o visual precisa ter **valor pedagógico**.

### 🧩 Visuais estruturados

Quando uma imagem do material não é a melhor forma de explicar o conteúdo, o próprio Educa+.ai pode construir recursos didáticos diretamente no PDF.

Atualmente são suportados:

- **timeline** — linhas do tempo;
- **comparison** — quadros e tabelas comparativas;
- **hierarchy** — estruturas hierárquicas;
- **flow** — fluxos e sequências;
- **cards** — grupos de conceitos organizados em cartões.

Assim, o sistema não apenas sugere que uma linha do tempo ou um quadro comparativo seria útil: **ele constrói o recurso automaticamente**.

### Seleção pedagógica do visual

A versão V2-B.1 compara duas possibilidades:

- reaproveitar uma imagem existente no material;
- criar um visual estruturado.

A escolha é feita de acordo com o recurso que oferece **maior clareza para o aluno**, e não simplesmente pela existência de uma imagem na página original.

### PDF preparado para estudo

O gerador de PDF possui:

- organização automática por seções;
- blocos visuais integrados ao conteúdo;
- controle de paginação para evitar separar título, visual e legenda;
- suporte a caracteres Unicode;
- revisão rápida ao final do material.

---

## 🤖 Arquitetura dos modelos Gemini

O Educa+.ai utiliza uma estratégia de **fallback**, permitindo que outro modelo continue a operação quando o primeiro estiver temporariamente indisponível.

### Quiz e feedback

```text
Gemini 3.5 Flash Lite
        ↓ fallback
Gemini 3.1 Flash Lite
```

Esses modelos são priorizados para operações frequentes do quiz.

### Resumo estruturado

```text
Gemini 3.7 Flash
        ↓
Gemini 3.6 Flash
        ↓
Gemini 3.5 Flash Lite
        ↓
Gemini 3.1 Flash Lite
```

A cadeia permite que a geração do resumo continue mesmo quando um dos modelos retorna erros temporários de disponibilidade, como HTTP `503`.

### Tratamento de indisponibilidade

O aplicativo possui mecanismos para lidar com:

- `404`;
- `408`;
- `429`;
- `500`;
- `502`;
- `503`;
- `504`;
- falhas temporárias de rede;
- timeout das requisições.

No Quiz, o usuário também recebe mensagens de progresso quando uma geração está levando mais tempo que o esperado, evitando a sensação de que o aplicativo travou.

---

## 🎨 Interface e experiência do usuário

O projeto busca manter uma experiência simples e focada no estudo:

- interface limpa e sem distrações;
- seleção rápida do material;
- escolha do nível de dificuldade;
- escolha da quantidade de questões;
- estados visuais durante a geração pela IA;
- resolução das questões diretamente no aplicativo;
- gabarito detalhado;
- feedback pedagógico;
- visualização e exportação de resumo em PDF.

---

## 📸 Telas do aplicativo

> As capturas de tela oficiais serão adicionadas conforme a interface visual for consolidada.

Sugestões para esta seção:

- Tela inicial / seleção de material
- Configuração do Quiz
- IA analisando o conteúdo
- Quiz em andamento
- Resultado e feedback
- Resumo estruturado
- Resumo com timeline, comparação e outros recursos visuais

---

## 🚀 Tecnologias utilizadas

### Aplicação

- **Flutter**
- **Dart**

### Inteligência Artificial

- **Google Gemini API**
- Gemini 3.7 Flash
- Gemini 3.6 Flash
- Gemini 3.5 Flash Lite
- Gemini 3.1 Flash Lite

### Principais pacotes

- `http` — comunicação com a API Gemini;
- `image_picker` — câmera e galeria;
- `flutter_dotenv` — carregamento de variáveis de ambiente durante o desenvolvimento;
- `pdf` — geração dos documentos PDF;
- `printing` — visualização/compartilhamento dos PDFs;
- processamento de imagens para recorte, redimensionamento e orientação dos visuais reutilizados.

---

## 🔐 Segurança

Durante o desenvolvimento, a chave da API Gemini é carregada através de um arquivo `.env`, que **não deve ser enviado ao GitHub**.

Isso reduz o risco de exposição acidental no repositório, porém é importante observar que aplicativos Flutter são executados no dispositivo do usuário. Portanto, uma chave incluída no aplicativo cliente **não deve ser considerada um segredo seguro em produção**.

Antes da publicação da versão final, a arquitetura prevista é mover as chamadas protegidas da API para um **backend**, mantendo as credenciais fora do aplicativo distribuído aos usuários.

Os logs de diagnóstico também devem ocultar a API Key antes de imprimir URLs ou mensagens de exceção.

---

## 🛣️ Roadmap

### Concluído ✅

- [x] Upload de múltiplas imagens
- [x] Geração de quizzes com IA
- [x] Níveis Simples, Intermediário e Avançado
- [x] Motor Pedagógico V2.2
- [x] Distratores avançados estruturados
- [x] Feedback pedagógico personalizado
- [x] Resumo estruturado
- [x] Exportação para PDF
- [x] Inteligência Visual V2-A
- [x] Recorte inteligente de imagens do material
- [x] Visuais estruturados V2-B
- [x] Seleção pedagógica de recursos visuais V2-B.1
- [x] Cadeias de fallback entre modelos Gemini

### Próximas etapas 🔜

- [ ] Histórico de quizzes e resumos
- [ ] Persistência local e/ou em nuvem
- [ ] Permitir refazer quizzes já gerados
- [ ] Progresso e estatísticas de aprendizagem
- [ ] Gamificação, conquistas e streaks
- [ ] Upload e análise direta de arquivos PDF
- [ ] Melhorias de desempenho no processamento de imagens
- [ ] Backend para proteger as credenciais da API em produção
- [ ] Sincronização entre dispositivos

---

## 🏁 Como executar o projeto

### Pré-requisitos

- Flutter SDK instalado;
- VS Code, Android Studio ou outro editor compatível;
- dispositivo/emulador configurado;
- API Key do Google Gemini.

### 1. Clone o repositório

```bash
git clone https://github.com/RodrigoCosta1983/scanlearn_ai.git
```

### 2. Entre na pasta do projeto

```bash
cd scanlearn_ai
```

### 3. Instale as dependências

```bash
flutter pub get
```

### 4. Configure a API Key

Na raiz do projeto, na mesma pasta do `pubspec.yaml`, crie um arquivo chamado `.env`:

```env
GEMINI_API_KEY=SuaChaveGeradaNoGoogleAqui
```

Garanta que `.env` esteja incluído no `.gitignore`.

### 5. Execute o aplicativo

```bash
flutter run
```

---

## 📌 Status atual

O projeto está em desenvolvimento ativo.

A base educacional atual é composta por:

```text
Quiz
└── Motor Pedagógico V2.2 ✅

Resumo
└── Inteligência Visual V2-B.1 ✅
```

Esses dois módulos formam o núcleo atual do **Educa+.ai** e servirão de base para as próximas etapas do produto.

---

## 📄 Licença

Defina aqui a licença escolhida para o projeto antes da distribuição pública.

---

**Educa+.ai — seu material de estudo transformado em uma experiência de aprendizagem mais ativa, visual e personalizada.**
