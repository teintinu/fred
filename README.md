# Fred — Assistente Pessoal para macOS

Assistente pessoal (menu bar app) que captura áudio do microfone ou de aplicativos (via BlackHole), transcreve localmente (whisper.cpp) e gera resumos e agendamentos com a LLM Deepseek, integrando com Google Calendar e notificações locais.

## Documentação

| Documento | Conteúdo |
|---|---|
| [PRD.md](PRD.md) | Requisitos de produto, decisões e riscos |
| [SPEC.md](SPEC.md) | Arquitetura, APIs, segurança, modelos de dados |
| [PLAN.md](PLAN.md) | Fases, estimativas e plano de testes |

## Estrutura

```
fred/
├── PRD.md / SPEC.md / PLAN.md   # documentação
├── project.yml                  # fonte do projeto (XcodeGen)
├── Fred/                        # app macOS (SwiftUI)
│   ├── Models/                  # Recording, SummaryResult, EventDraft
│   ├── Audio/                   # WaveWriter, AudioCaptureEngine, dispositivos, apps
│   ├── Storage/                 # RecordingStore (JSON), KeychainStore
│   ├── Transcription/           # WhisperCLITranscriber (whisper.cpp)
│   ├── Deepseek/                # prompts anti-injection, parser estrito, cliente
│   ├── Calendar/                # OAuth2 (PKCE), GoogleCalendarAPI
│   ├── Notifications/           # planos + UNUserNotificationCenter
│   ├── Pipeline/                # processamento + DraftStore (confirmação manual)
│   └── Live/                    # painel ao vivo: transcrição original + resumo PT-BR
├── FredTests/                   # 78 testes unitários (XCTest)
├── mcp-xcode/                   # servidor MCP do Xcode (dev tooling)
├── scripts/
│   ├── restart.sh               # kill + build + launch (dev loop)
│   └── download-whisper-model.sh
└── .vscode/mcp.json             # registro do MCP no VS Code
```

## Painel ao vivo (⌘L)

- Flutuante: fica **acima de qualquer app** e **acompanha todos os Spaces** (inclusive telas cheias).
- Ajustes: **tamanho** (redimensionável), **visibilidade** (mostrar/ocultar), **transparência** e **tamanho da fonte** (sliders no painel).
- Conteúdo: transcrição **no idioma original** (esquerda) e resumo **sempre em PT-BR** (direita), ambos em tempo real.
- ⚡ Otimização: com o painel oculto, **nenhum processamento em tempo real** é feito (zero chamadas ao whisper/Deepseek).
- Segmentos de ~12s são transcritos em sequência; o resumo é atualizado com debounce a cada 2 segmentos.

## Rodar testes

```bash
xcodebuild -project Fred.xcodeproj -scheme Fred -configuration Debug -derivedDataPath build/DerivedData test
```

Ou peça ao Copilot (modo Agent) para usar `xcode_test` do MCP.

## Dev loop rápido

```bash
./scripts/restart.sh              # mata, compila e relança o Fred
./scripts/restart.sh --no-build   # só relança o app já compilado
```

## Configuração do app (Preferências)

- **Deepseek**: cole a API Key (salva no Keychain).
- **Google Calendar**: crie um client OAuth no Google Cloud Console (tipo Desktop), com redirect URI `com.fred.app:/oauth2callback`, e cole Client ID + Secret.
- **Transcrição**: `brew install whisper-cpp` + `scripts/download-whisper-model.sh` (modelo ggml-base ~142 MB).
- **Captura de apps**: instale o BlackHole (`brew install blackhole-2ch`, requer reboot) e roteie o áudio via Audio MIDI Setup (Multi-Output).

> 🔒 Segurança: eventos sugeridos pela LLM são criados no Google Calendar **somente após confirmação manual**. Transcrições nunca executam instruções (anti prompt-injection).

## Pré-requisitos

- macOS 13+ (recomendado 14+ / Apple Silicon)
- Xcode + XcodeGen (`brew install xcodegen`)
- Node.js ≥ 20 (apenas para o `mcp-xcode`)
