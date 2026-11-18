# Educa+.ai — Registro da Nova Versão

**Versão do aplicativo:** `1.2.0+14`  
**Status:** Em desenvolvimento / testes  
**Plataformas configuradas:** Android, iOS e Web

---

## 🚀 VISÃO GERAL DA ATUALIZAÇÃO

Esta versão representa uma das maiores evoluções do Educa+.ai até o momento.

O aplicativo deixou de ser apenas um gerador de quizzes a partir de imagens e passou a funcionar como uma plataforma de estudo inteligente, capaz de transformar materiais enviados pelo aluno em:

- Quizzes personalizados;
- Questões com níveis reais de complexidade cognitiva;
- Feedback pedagógico;
- Resumos estruturados;
- PDFs de estudo;
- Recursos visuais didáticos;
- Linhas do tempo;
- Tabelas comparativas;
- Hierarquias;
- Fluxos;
- Cards educacionais;
- Métricas de utilização através do Firebase Analytics.

---

# 🎨 REBRANDING — SCANLEARN.AI → EDUCA+.AI

Foi realizado o rebranding do aplicativo para **Educa+.ai**.

A nova identidade representa melhor a evolução do projeto e sua proposta de transformar o próprio material do usuário em uma experiência completa de estudo.

### Identidade atual

**Nome comercial:** Educa+.ai

**Proposta:**

> Você envia o conteúdo. O Educa+.ai transforma em estudo.

O nome apresentado ao usuário foi atualizado na interface e nas plataformas configuradas.

Os identificadores técnicos antigos do aplicativo foram mantidos para preservar a continuidade do projeto, como:

- Android: `com.scanlearn_ai.app.scanlearn_ai`
- iOS: `com.scanlearnai.app.scanlearnAi`

---

# 🧠 MOTOR PEDAGÓGICO V2.2 — QUIZ

Foi concluído o **Motor Pedagógico V2.2**, responsável pela criação dos quizzes.

O objetivo principal foi fazer com que a dificuldade das questões seja determinada pelo **raciocínio necessário para respondê-las**, e não simplesmente por textos maiores ou palavras mais difíceis.

## 🟢 Nível Simples

Voltado principalmente para estudantes do Ensino Fundamental I.

Habilidades trabalhadas:

- Lembrar;
- Reconhecer;
- Identificar;
- Compreender conceitos básicos.

As questões trabalham uma ideia principal por vez, sem pegadinhas e sem exigir várias etapas de raciocínio.

## 🟡 Nível Intermediário

Voltado principalmente para estudantes do 6º ao 9º ano.

Habilidades trabalhadas:

- Compreensão;
- Interpretação;
- Comparação;
- Aplicação;
- Inferência simples;
- Relações de causa e consequência.

As perguntas deixam de ser apenas cópias literais do material.

## 🔴 Nível Avançado

Voltado para vestibulares, concursos, provas complexas e estudantes que desejam maior profundidade.

O Motor Pedagógico V2.2 utiliza uma matriz cognitiva.

Para um quiz com 5 questões:

1. Causa e consequência complexa;
2. Comparação e contraste;
3. Aplicação em situação nova;
4. Análise de afirmações;
5. Síntese e integração de informações.

A dificuldade deve estar no raciocínio e não no tamanho do texto.

---

# 🎯 DISTRATORES ESTRUTURADOS V2.2

As alternativas incorretas passaram a ser criadas com maior cuidado pedagógico.

O sistema evita alternativas obviamente erradas e procura criar distratores baseados em:

- Causa incorreta;
- Critério incorreto;
- Relações aparentemente corretas, mas associadas de forma errada;
- Generalizações;
- Mudanças sutis de condição;
- Erros de escopo;
- Erros de cronologia;
- Confusão entre conceitos relacionados.

Também foi implementada uma autovalidação das questões avançadas antes do retorno do JSON final.

---

# 🔄 CADEIA DE MODELOS — QUIZ

O Quiz utiliza atualmente:

`gemini-3.5-flash-lite`

↓ fallback

`gemini-3.1-flash-lite`

O sistema possui:

- Timeout real de 60 segundos por modelo;
- Mensagem de espera aos 45 segundos;
- Fallback automático;
- Tratamento de erros 404, 408, 429, 500, 502, 503 e 504;
- Tentativa extra após 503 + 503;
- Pausa de 8 segundos antes da recuperação;
- Sanitização da API Key nos logs.

---

# 📄 RESUMO ESTRUTURADO — INTELIGÊNCIA VISUAL V2-B.1

Foi concluída a versão **V2-B.1 da Inteligência Visual dos Resumos**.

O sistema não apenas resume o conteúdo.

Agora ele analisa cada seção e decide qual tipo de representação ajuda mais o aluno a compreender o assunto.

---

# 🖼️ DECISÃO VISUAL PEDAGÓGICA

Para cada seção, a IA avalia se um apoio visual realmente traz ganho pedagógico.

Quando existe ganho, ela compara duas possibilidades:

### Opção A
Reaproveitar um elemento visual existente no material original.

### Opção B
Criar um recurso didático estruturado diretamente no PDF.

A decisão não é baseada simplesmente na existência de uma imagem.

A prioridade é:

- Clareza;
- Fidelidade;
- Valor didático;
- Menor carga visual;
- Melhor compreensão.

Em caso de empate pedagógico, o sistema prioriza o visual estruturado.

---

# ✂️ RECORTE E ROTAÇÃO INTELIGENTE

Quando uma imagem do material original é considerada pedagogicamente útil, o Educa+.ai consegue:

- Identificar o arquivo de origem;
- Localizar a região relevante;
- Recortar somente a parte necessária;
- Evitar inserir a página inteira;
- Remover áreas desnecessárias;
- Corrigir a orientação;
- Aplicar rotação de 0°, 90°, 180° ou 270°;
- Redimensionar o recorte para uso no PDF.

O sistema trabalha com coordenadas normalizadas de `0..1000`.

---

# 🧩 VISUAIS ESTRUTURADOS

Quando o material original não possui a melhor representação possível, o próprio Educa+.ai constrói um visual didático.

Tipos disponíveis:

- 📅 Timeline;
- 📊 Comparison;
- 🔄 Flow;
- 🔽 Hierarchy;
- 🗂️ Cards;
- `none`, quando nenhum visual é necessário.

Esses visuais são produzidos diretamente pelo PDF, sem necessidade de uma segunda geração de imagem por IA.

---

# 📄 PDF SERVICE — V2-B.1

O `PdfService` foi reformulado para suportar os novos resumos estruturados.

Principais melhorias:

- Renderização de timelines;
- Tabelas comparativas;
- Hierarquias;
- Fluxos;
- Cards;
- Imagens recortadas do material original;
- Organização visual dos pontos-chave;
- Legendas;
- Identificação da origem do visual;
- Paginação de blocos visuais;
- Fonte Noto Sans;
- Melhor suporte a caracteres Unicode;
- Redução de problemas com acentos, travessões, setas e caracteres especiais.

Também foi implementado o conceito de **Keep Together**, evitando que o título de um visual fique sozinho no fim de uma página enquanto o conteúdo aparece somente na página seguinte.

---

# 🔄 CADEIA DE MODELOS — RESUMO

O Resumo utiliza atualmente:

`gemini-3.7-flash`

↓

`gemini-3.6-flash`

↓

`gemini-3.5-flash-lite`

↓

`gemini-3.1-flash-lite`

Essa cadeia oferece maior resiliência quando um modelo está temporariamente indisponível.

---

# 📎 SUPORTE A PDF

Foi adicionado suporte à seleção de arquivos PDF utilizando:

`file_picker`

Agora o usuário pode adicionar:

- Fotos da galeria;
- Fotos pela câmera;
- Arquivos PDF.

O material é enviado para análise da IA junto com os demais arquivos selecionados.

---

# 📊 ANALYTICS V1.0

Foi iniciada a integração do **Firebase Analytics** no Educa+.ai.

Objetivo:

Acompanhar não apenas downloads, mas principalmente como os usuários realmente utilizam o aplicativo.

---

# 🔥 FIREBASE

Foi criado o projeto:

`educa-plus-ai-app`

Plataformas configuradas:

- ✅ Android
- ✅ iOS
- ✅ Web

O FlutterFire gerou:

`lib/firebase_options.dart`

Pacotes adicionados:

- `firebase_core`
- `firebase_analytics`

Versões instaladas durante a configuração:

- `firebase_core 4.14.0`
- `firebase_analytics 12.5.0`
- `flutterfire_cli 1.4.1`

---

# 🤖 ANDROID — MIN SDK

O Firebase Analytics atual exige Android SDK mínimo 23.

Por isso o projeto foi atualizado de:

`minSdkVersion 21`

para:

`minSdkVersion 23`

Isso significa suporte a partir do Android 6.0.

---

# 📊 ANALYTICS — EVENTOS

O Analytics foi preparado para acompanhar eventos importantes do Educa+.ai.

## 📊 ANALYTICS → material_added

Registrado quando o usuário adiciona um material.

Informações possíveis:

- Origem: câmera;
- Origem: galeria;
- Origem: PDF;
- Quantidade de arquivos adicionados;
- Total de arquivos carregados.

Exemplo no Debug:

```text
📊 ANALYTICS → material_added
   📦 {source: gallery, file_count: 3, total_files: 3}
```

---

## 📊 ANALYTICS → quiz_started

Registrado quando o usuário inicia a criação de um Quiz.

Exemplo:

```text
📊 ANALYTICS → quiz_started
   📦 {
     difficulty: Avançado,
     question_count: 5,
     file_count: 3
   }
```

---

## 📊 ANALYTICS → quiz_generated

Registrado quando o Quiz é criado com sucesso.

Pode registrar:

- Dificuldade;
- Quantidade de questões;
- Modelo Gemini utilizado;
- Tentativa necessária.

Exemplo:

```text
📊 ANALYTICS → quiz_generated
   📦 {
     difficulty: Avançado,
     question_count: 5,
     model: gemini-3.5-flash-lite,
     attempt: 1
   }
```

---

## 📊 ANALYTICS → quiz_generation_failed

Registrado quando a geração do Quiz falha.

Permite acompanhar futuramente:

- Quantidade de falhas;
- Status HTTP;
- Instabilidade dos modelos;
- Problemas de comunicação.

---

## 📊 ANALYTICS → quiz_completed

Registrado quando o aluno termina o Quiz.

Exemplo:

```text
📊 ANALYTICS → quiz_completed
   📦 {
     difficulty: Avançado,
     question_count: 5,
     correct_answers: 4,
     score_percent: 80
   }
```

Esse evento permitirá analisar:

- Taxa de conclusão;
- Dificuldade mais usada;
- Desempenho médio;
- Quantidade média de questões.

---

## 📊 ANALYTICS → quiz_feedback_generated

Registrado quando o feedback pedagógico é criado com sucesso.

---

## 📊 ANALYTICS → quiz_feedback_failed

Registrado quando o feedback pedagógico não consegue ser gerado.

O resultado do aluno continua sendo exibido normalmente.

---

## 📊 ANALYTICS → summary_started

Registrado quando o usuário inicia a criação de um resumo.

Exemplo:

```text
📊 ANALYTICS → summary_started
   📦 {file_count: 3}
```

---

## 📊 ANALYTICS → summary_generated

Registrado quando o Resumo Inteligente é criado com sucesso.

Exemplo:

```text
📊 ANALYTICS → summary_generated
   📦 {
     model: gemini-3.6-flash,
     attempt: 2,
     sections: 4,
     visual_sections: 3,
     source_visuals: 1,
     structured_visuals: 2
   }
```

Esse evento permitirá acompanhar:

- Quantos resumos são gerados;
- Modelos mais utilizados;
- Número médio de seções;
- Quantos visuais são utilizados;
- Quantos vêm do material original;
- Quantos são criados pelo Educa+.ai.

---

## 📊 ANALYTICS → summary_generation_failed

Registrado quando a geração do resumo falha.

---

## 📊 ANALYTICS → pdf_generated

Evento destinado ao acompanhamento da geração de PDFs.

---

# 📊 ANALYTICS — EVENTOS AUTOMÁTICOS DO FIREBASE

Além dos eventos personalizados do Educa+.ai, o Firebase Analytics registra automaticamente diversos eventos.

Entre os mais importantes:

- `first_open`
- `session_start`
- `user_engagement`

Isso permitirá comparar:

`DOWNLOAD`

↓

`PRIMEIRA ABERTURA`

↓

`MATERIAL ADICIONADO`

↓

`QUIZ INICIADO`

↓

`QUIZ CONCLUÍDO`

↓

`RESUMO GERADO`

↓

`USUÁRIO RETORNOU AO APP`

---

# 🧪 LOGS DE DEBUG MANTIDOS

Os logs existentes do projeto foram mantidos.

Durante o desenvolvimento teremos dois níveis diferentes de acompanhamento:

### 🧪 Debug local

Utilizando `debugPrint()`.

Permite acompanhar:

- Modelo utilizado;
- HTTP;
- Tempo de resposta;
- Fallback;
- Timeout;
- JSON sanitizado;
- Matriz pedagógica;
- Resultado das questões;
- Recortes;
- Orientação;
- Decisão visual;
- Visuais estruturados.

### 📊 Firebase Analytics

Permite acompanhar o comportamento agregado dos usuários reais.

Exemplo de fluxo no console:

```text
📊 ANALYTICS → quiz_started

🧪 DIAGNÓSTICO PEDAGÓGICO DO QUIZ

🧠 EDUCA+.AI — INÍCIO DA CADEIA DO QUIZ

🚀 QUIZ — TENTATIVA 1/2

🤖 Modelo: gemini-3.5-flash-lite

📡 HTTP: 200

✅ MODELO UTILIZADO NO QUIZ: gemini-3.5-flash-lite

📊 ANALYTICS → quiz_generated
```

---

# 🛡️ ANALYTICS ISOLADO DO FUNCIONAMENTO DO APP

O sistema de Analytics foi pensado para não interferir nas funções principais.

Se um evento do Firebase não puder ser registrado, o Quiz ou Resumo deve continuar funcionando normalmente.

Exemplo:

```text
⚠️ ANALYTICS → falha ao registrar quiz_started
```

A falha de telemetria não deve interromper a experiência do usuário.

---

# 🔐 PRIVACIDADE

O Analytics não deve receber o conteúdo de estudo do usuário.

Não devem ser enviados:

- Fotos;
- Texto das apostilas;
- Perguntas completas;
- Respostas completas;
- Nome do arquivo;
- Nome do aluno;
- E-mail;
- Conteúdo dos PDFs;
- Dados pessoais desnecessários.

São enviadas apenas métricas operacionais, como:

- Nível do Quiz;
- Quantidade de questões;
- Número de arquivos;
- Modelo utilizado;
- Quantidade de acertos;
- Percentual;
- Número de seções;
- Quantidade de visuais.

---

# 🔐 API KEY

O projeto continua utilizando `.env` durante o desenvolvimento.

O arquivo evita que a chave seja publicada diretamente no repositório Git.

Entretanto, uma API Key presente em um aplicativo Flutter distribuído não deve ser considerada um segredo absoluto.

Para uma versão de produção mais robusta, a arquitetura ideal continuará sendo:

`Aplicativo`

↓

`Backend`

↓

`API Gemini`

Assim a chave poderá permanecer no servidor.

---

# 📊 PRIMEIRO TESTE DO FIREBASE

Após atualização do `minSdkVersion` para 23, o aplicativo compilou com sucesso.

Resultado:

```text
√ Built build\app\outputs\flutter-apk\app-debug.apk
```

O aplicativo foi instalado no dispositivo Samsung utilizado nos testes.

Em seguida apareceu no console:

```text
📊 Firebase Analytics inicializado com sucesso.
```

Isso confirmou que:

- Firebase Core inicializou;
- Firebase Analytics carregou;
- A configuração Android está funcional;
- O arquivo `firebase_options.dart` está sendo utilizado;
- O aplicativo conseguiu iniciar normalmente com o Firebase integrado.

---

# 📈 OBJETIVO DAS MÉTRICAS

Com o Analytics, futuramente será possível responder perguntas como:

- Quantas pessoas abriram o aplicativo?
- Quantas adicionaram um material?
- Quantas iniciaram um Quiz?
- Quantas concluíram?
- Qual nível de dificuldade é mais utilizado?
- Quantas pessoas geram Resumos?
- Quantos PDFs são criados?
- Qual modelo Gemini está sendo usado com maior frequência?
- Qual é a taxa de erro dos modelos?
- Quantos usuários retornam ao aplicativo?
- Em que ponto os usuários abandonam o fluxo?

Exemplo de funil:

```text
1.000 primeiras aberturas
        ↓
850 adicionaram material
        ↓
700 iniciaram Quiz
        ↓
680 concluíram Quiz
        ↓
430 geraram Resumo
        ↓
310 voltaram ao aplicativo
```

---

# ☁️ DOWNLOADS X USO REAL

Os downloads continuarão sendo acompanhados pelas lojas:

### Android
Google Play Console

### iOS
App Store Connect

O Firebase Analytics complementará essas informações mostrando o que acontece depois da instalação.

Assim teremos:

`Play Store / App Store`

→ Quantas pessoas instalaram.

`Firebase Analytics`

→ Quantas abriram, utilizaram, estudaram e retornaram.

---

# 📦 STATUS ATUAL DO EDUCA+.AI

### 🎨 Rebranding
✅ Educa+.ai

### 🧠 Quiz
✅ Motor Pedagógico V2.2

### 🎯 Distratores
✅ Distratores estruturados V2.2

### 🔄 Quiz Fallback
✅ Gemini 3.5 Flash Lite → Gemini 3.1 Flash Lite

### 📄 Resumo
✅ Inteligência Visual V2-B.1

### ✂️ Recorte de imagens
✅ Implementado

### 🔄 Rotação inteligente
✅ Implementada

### 🧩 Visuais estruturados
✅ Timeline  
✅ Comparison  
✅ Flow  
✅ Hierarchy  
✅ Cards

### 📄 PDF
✅ Resumo estruturado  
✅ Unicode / Noto Sans  
✅ Keep Together

### 📎 Arquivos
✅ Imagens  
✅ Câmera  
✅ PDF

### 🔥 Firebase
✅ Projeto criado

### 📊 ANALYTICS
✅ Firebase Core integrado  
✅ Firebase Analytics integrado  
✅ Inicialização confirmada em dispositivo real  
✅ Eventos personalizados preparados  
✅ Logs de Debug mantidos

---

# 🏁 MARCO DA VERSÃO

Esta versão marca a transição do Educa+.ai de um simples gerador de quizzes para uma plataforma de estudo inteligente.

O aplicativo agora possui três grandes camadas:

### 🧠 APRENDER
Transformação do material em Quiz com dificuldade pedagógica real.

### 📄 COMPREENDER
Transformação do material em Resumos Inteligentes com apoio visual.

### 📊 MEDIR
Acompanhamento do uso real do aplicativo através do Firebase Analytics.

---

## Educa+.ai

**Você envia o conteúdo. O Educa+.ai transforma em estudo. 🚀**
