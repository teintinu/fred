# Fred — Plano de Implementação (PLAN) — v2

## Resumo
Plano revisado com foco em **validar os riscos técnicos primeiro** (spike P0) antes de construir o MVP, refletindo as decisões: BlackHole para captura de apps, WhisperKit/whisper.cpp local, Deepseek (chat + reasoner), Google Calendar com confirmação manual e distribuição dev local.

## MVP — Escopo (v1)
- Menu bar app (SwiftUI).
- Captura de microfone (nativa) + captura de apps via BlackHole.
- Persistência da seleção de app por bundleIdentifier.
- Transcrição local multilíngue (WhisperKit; fallback whisper.cpp).
- Resumo PT-BR (deepseek-chat) + ações JSON (deepseek-reasoner).
- Google Calendar: criar eventos com confirmação manual (OAuth2 loopback).
- Notificações locais para eventos e follow-ups.

## Fase 0 — Spike de viabilidade (3 dias) [P0 — go/no-go]
- Instalar BlackHole; gravar mic + dispositivo BlackHole; testar Multi-Output com saída embutida e Bluetooth (documentar drift).
- WhisperKit: transcrever arquivo multilíngue (PT/EN) e medir tempo em Apple Silicon; comparar large vs small.
- Deepseek: 1 chamada chat + 1 reasoner com o prompt base; validar JSON de ações.
- Google: PoC OAuth loopback (`ASWebAuthenticationSession` + PKCE) e criação de 1 evento manual.
- **Saída**: documento de go/no-go atualizado no final.

## Fase 1 — Scaffold e fundação (2 dias)
- Projeto Xcode (SwiftUI, menu bar, `LSUIElement`), targets, .gitignore, estrutura de diretórios.
- Onboarding de permissões (mic, notificações) e SMAppService (login item).

## Fase 2 — Captura e armazenamento (4 dias)
- Gravador de mic (AVAudioEngine) em WAV 16 kHz com segmentos crash-safe.
- SQLite de metadados + layout em Application Support; retenção configurável.
- UI de histórico + player simples.

## Fase 3 — Seleção de app + BlackHole (3 dias)
- Listar apps (`NSWorkspace`); persistir bundleIdentifier; resolução em runtime; auto-retomar seleção.
- Captura via BlackHole; detecção de dispositivo de saída com aviso de BT; guia de instalação/roteamento no onboarding.

## Fase 4 — Transcrição local (4 dias)
- Integrar WhisperKit (SPM); fila de processamento em actor; VAD; fallback whisper.cpp.
- UI de status; salvamento de transcrições; benchmark de modelos.

## Fase 5 — Deepseek (3 dias)
- Cliente HTTP; prompt base; pipeline de 2 passos (chat + reasoner); parser JSON estrito com validação; retry/backoff; chave no Keychain.

## Fase 6 — Google Calendar + notificações (4 dias)
- OAuth2 loopback (ASWebAuthenticationSession + PKCE); tokens no Keychain; criar evento com confirmação e draft editável.
- UNUserNotificationCenter: agendamento de eventos/follow-ups; re-sync ao abrir o app.

## Fase 7 — Polimento, segurança e testes (3 dias)
- Criptografia opcional de áudio (CryptoKit); logs; testes E2E; README; revisão final de segurança (injection, Keychain).

**Total estimado: ~26 dias úteis (~5 semanas).**

## Plano de testes
- Unit: parser Deepseek (com payloads de injection), resolução de bundleID, validação de datas.
- Integração: pipeline com mock Deepseek; OAuth com conta de teste.
- Manual: matriz de dispositivos (embutido, USB, BT) e apps (Zoom/Teams/Meet/Chrome) com BlackHole.

## Riscos e contingências (top 5)
| Risco | Fase de mitigação | Plano B |
|---|---|---|
| BlackHole + Bluetooth drift | Fase 0 | Usar saída embutida ao gravar; aviso na UI; Loopback (pago) |
| Whisper lento em CPU | Fase 0/4 | Metal/Core ML; modelo menor |
| JSON instável do reasoner | Fase 5 | Reforçar prompt; fallback para deepseek-chat com parsing |
| Injection via transcrição | Fase 5/7 | Delimitadores + confirmação manual + sem auto-execução |
| OAuth Google (loopback/verificação) | Fase 0/6 | Seguir guia oficial; conta de teste |

## Definição de Pronto (por fase)
- Testes passando, documentação atualizada, demo manual registrada, PR revisável.

## Próximos passos imediatos
- ✅ Aprovar PRD/SPEC/PLAN (v2).
- ✅ BlackHole 0.7.1 instalado via brew — **requer reboot para ativar o driver**.
- ✅ Servidor MCP do Xcode criado (`mcp-xcode/`, ferramentas: build, test, run_app, restart_app…).
- ✅ Script de dev loop `scripts/restart.sh` (kill + build + launch).
- Criar repositório Git e o scaffold do projeto Xcode (Fase 1).
- Executar restante da Fase 0 (spike): WhisperKit, Deepseek (2 modelos), OAuth Google.

---

*Plano revisado (v2) — spike primeiro, MVP em ~5 semanas.*
