# Fred — Assistente Pessoal para macOS

Assistente pessoal (menu bar app) que captura áudio do microfone ou de aplicativos (via BlackHole), transcreve localmente (WhisperKit/whisper.cpp) e gera resumos e agendamentos com a LLM Deepseek, integrando com Google Calendar e notificações locais.

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
├── mcp-xcode/                   # servidor MCP do Xcode (dev tooling)
├── scripts/
│   └── restart.sh               # kill + build + launch (dev loop)
├── .vscode/mcp.json             # registro do MCP no VS Code
└── (futuro) Fred.xcodeproj      # app (Fase 1)
```

## Dev loop rápido

```bash
./scripts/restart.sh              # mata, compila e relança o Fred
./scripts/restart.sh --no-build   # só relança o app já compilado
```

Ou peça ao Copilot (modo Agent) para usar as ferramentas `xcode_build`, `xcode_test`, `xcode_restart_app` etc.

## Pré-requisitos

- macOS 13+ (recomendado 14+ / Apple Silicon)
- Xcode
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) (`brew install blackhole-2ch`) — requer reboot para ativar o driver
- Node.js ≥ 20 (apenas para o `mcp-xcode`)
