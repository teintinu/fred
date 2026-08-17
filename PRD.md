# Fred — Assistente Pessoal (PRD) — v2

## Visão Geral
O Fred é um assistente pessoal para macOS (menu bar app) que captura áudio do microfone (nativo) ou de aplicativos em execução (via dispositivo virtual **BlackHole**), transcreve **localmente e offline** com WhisperKit/whisper.cpp (multilíngue) e gera resumos **sempre em PT-BR** e ações de agenda com a LLM **Deepseek** (deepseek-chat + deepseek-reasoner). Integra-se ao **Google Calendar** para criar eventos **somente com confirmação manual** e emite **notificações locais** para eventos e follow-ups. O áudio nunca sai do Mac; apenas o texto transcrito é enviado ao Deepseek.

## Objetivos
- Capturar áudio do microfone (nativo) e de apps/sistema (BlackHole) e **persistir a seleção do app** entre sessões.
- Transcrever áudio 100% localmente, com suporte multilíngue.
- Gerar resumos em PT-BR e extrair propostas de agendamento com Deepseek.
- Criar eventos no Google Calendar apenas com confirmação explícita do usuário.
- Emitir notificações locais para eventos e alertas futuros.
- Garantir privacidade (áudio local, segredos no Keychain, criptografia opcional) e experiência nativa.

## Usuários Alvo
- Profissionais que participam de reuniões online e querem resumos automáticos.
- Pessoas que registram chamadas/áudios e querem transformar em ações (agendar, lembrar).
- Usuários macOS que preferem processamento local e controle dos dados.

## Casos de Uso Principais
- Gravar o microfone e obter transcrição + resumo automaticamente ao final.
- Selecionar um app em execução (ex.: Zoom, Teams, Meet) numa lista, gravar o áudio roteado via BlackHole e **reusar a seleção salva** quando o app for reaberto (Fred ou o app-alvo).
- Detectar propostas de agendamento e follow-ups no conteúdo e criar eventos no Google Calendar mediante confirmação.
- Receber notificações locais de eventos e de follow-ups sugeridos.

## Decisões do Produto (v2)
| Decisão | Escolha | Impacto |
|---|---|---|
| Captura de áudio de apps | **BlackHole** (dispositivo virtual) + roteamento | Usuário instala um driver (pkg); captura-se o que for roteado; sem filtro por app nativo |
| Microfone | **Captura nativa** (AVFoundation), sem BlackHole | Simples e direto; mix mic+app via Aggregate Device se desejado |
| Transcrição | **WhisperKit / whisper.cpp local** (Core ML/Metal) | Offline, multilíngue, sem limite de ~1min; substitui a regra original de "só SDK Apple" por decisão do usuário |
| LLM | **Deepseek**: deepseek-chat (resumo) + deepseek-reasoner (ações) | Pipeline de 2 passos; texto vai para a nuvem (China) |
| Google Calendar | **Criar eventos com confirmação manual** | Mais seguro; sync 2 vias fica para v2 |
| Idioma | Transcrição **multilíngue**; resumos **sempre PT-BR** | Whisper detecta idioma; prompts de resumo fixam PT-BR |
| Privacidade do LLM | **Enviar transcrições ao Deepseek por padrão** | Texto apenas (áudio fica local); configurável no futuro |
| Distribuição | **Só dev local (Xcode)** no início | Notarizado/DMG depois; App Store inviável (sandbox) |

## Funcionalidades (MVP)
- Menu bar: iniciar/parar captura, selecionar origem (mic/app), histórico, preferências.
- Captura de microfone nativa (AVFoundation) em WAV 16 kHz mono.
- Captura de apps via BlackHole + guia de instalação/roteamento no onboarding.
- Persistência da seleção de app por `bundleIdentifier` (nunca path fixo; resolução em runtime).
- Transcrição local multilíngue (WhisperKit; fallback whisper.cpp).
- Resumo PT-BR (deepseek-chat) + extração de ações/eventos JSON (deepseek-reasoner).
- Google Calendar: criar eventos com confirmação manual (OAuth2, tokens no Keychain).
- Notificações locais (UNUserNotificationCenter) para eventos e follow-ups.
- Armazenamento local com criptografia opcional (CryptoKit) e retenção configurável.

## Requisitos Não Funcionais
- **Privacidade**: áudio nunca enviado à nuvem; chaves/tokens no Keychain; criptografia opcional de arquivos.
- **Confiabilidade**: retomar seleção salva após reboot; pipeline assíncrono com fila; retry/backoff no Deepseek.
- **Performance**: transcrição em background com Metal (Apple Silicon); meta de resumo < 60s para 5 min de áudio.
- **Segurança**: nenhuma ação executada sem confirmação; mitigação de prompt injection; TLS obrigatório.
- **Manutenibilidade**: Swift + SwiftUI modular, logs locais (os_log), sem telemetria.

## Restrições (atualizadas v2)
- Áudio: APIs nativas do macOS + BlackHole (componente open source aceito por decisão).
- Transcrição: local/offline (WhisperKit/whisper.cpp) — exceção à regra "somente SDK Apple", aprovada.
- LLM: somente Deepseek (deepseek-chat e deepseek-reasoner).
- Captura seletiva "de verdade" por app (sem roteamento) **fora do v1** — exigiria ACE (Rogue Amoeba, licenciado) ou Audio Server Plugin próprio (driver).

## Privacidade e Conformidade
- Permissões macOS: Microfone e Notificações. **Não** são necessárias: Gravação de Tela (não usamos ScreenCaptureKit) nem Speech Recognition.
- LGPD/consentimento: gravar terceiros pode exigir consentimento conforme a jurisdição; prever aviso de gravação opcional e documentação ao usuário.
- Textos transcritos vão ao Deepseek (servidores na China) por padrão; extensão futura: confirmação por envio e/ou modelo local (Ollama).

## Métricas de Sucesso (KPIs)
- WER (taxa de erro de transcrição) ≤ 15% em áudio claro multilíngue.
- Resumo disponível < 60s após a transcrição para gravações de 5 min.
- Propostas de evento corretas > 90% (após confirmação manual).
- **0 ações executadas sem confirmação explícita** (requisito de segurança).

## Critérios de Aceitação (MVP)
- Gravação de mic salva em disco e transcrita offline com sucesso (PT/EN).
- Captura via BlackHole demonstrada em fluxo manual documentado (incluindo limitação Bluetooth).
- Resumo PT-BR gerado com deepseek-chat; ações JSON válidas com deepseek-reasoner.
- OAuth Google Calendar funcional; evento criado somente após confirmação do usuário.
- Notificação local dispara em horário agendado, inclusive com o app fechado.
- Seleção de app persiste e é reaplicada após reabrir o Fred e/ou o app-alvo.

## Fora de Escopo (v1)
- Diarização (identificar quem falou) — não suportada pelo Whisper padrão.
- Wake word / ativação por voz.
- Sync bidirecional com Google Calendar (editar/excluir, watch channels).
- App Store (sandbox inviabiliza captura de outros apps) e ACE Rogue Amoeba.
- Modelo local de LLM (Ollama) — extensão futura.

## Riscos e Mitigações (expandido)
| Risco | Impacto | Mitigação |
|---|---|---|
| Não existe API por app no macOS | Requisito central depende de roteamento | BlackHole + Multi-Output; documentar no onboarding; ACE como upgrade futuro |
| Bluetooth + Multi-Output (clock drift) | Estalos/glitches na gravação | Usar saída embutida ao gravar; detectar dispositivo e avisar; Loopback como alternativa paga |
| Performance do Whisper em CPU | Transcrição lenta | Metal/Core ML no Apple Silicon; opções de modelo menor (small/base) |
| Prompt injection na transcrição | Eventos indevidos | Delimitadores + JSON estrito + confirmação manual + nunca auto-executar |
| Latência/limites do Deepseek | Atraso no resumo | Fila com retry/backoff e status na UI |
| Quotas/verificação OAuth Google | Bloqueio da API | Escopo mínimo; verificação só se o app for público |
| Legalidade de gravar terceiros | Risco jurídico | Aviso de gravação e orientação de consentimento |
| Crescimento de disco | Lotação | Retenção configurável; exclusão automática pós-resumo (opcional) |

## Entregáveis
- PRD (este documento), SPEC técnico, PLAN com fases e estimativas.
- Spike de viabilidade (Fase 0) com go/no-go documentado.
- MVP funcional.

---

*Documento revisado (v2) com decisões do usuário e análise técnica profunda.*
