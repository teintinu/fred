# Instruções para o Copilot — mcp-xcode

- O servidor MCP usa o SDK TypeScript oficial v2:
  - Pacote do servidor: `@modelcontextprotocol/server`
  - Transporte stdio: `@modelcontextprotocol/server/stdio`
  - Docs: https://ts.sdk.modelcontextprotocol.io/v2/
  - Spec: https://modelcontextprotocol.io/specification/2026-07-28
- Schemas de ferramentas usam Zod v4 (`import * as z from 'zod/v4'` — Standard Schema).
- Ferramentas encapsulam `xcodebuild`/`pkill`/`open` via `child_process.execFile` (sem shell).
- Saídas longas de build são truncadas com `tail()` e erros filtrados com `errorLines()`.
- `restart_app` delega ao script `scripts/restart.sh` do repositório.
