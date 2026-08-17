# mcp-xcode — Servidor MCP para Xcode

Servidor **MCP (Model Context Protocol)** que expõe o `xcodebuild` (build, teste, execução, restart) para agentes de IA (ex.: GitHub Copilot no VS Code), agilizando o dev loop do app **Fred**.

## Ferramentas

| Ferramenta | Descrição |
|---|---|
| `find_project` | Localiza `.xcodeproj`/`.xcworkspace` no diretório |
| `list_schemes` | Lista schemes (`xcodebuild -list -json`) |
| `list_destinations` | Lista destinos (`xcodebuild -showdestinations`) |
| `build` | Compila (`xcodebuild build`) e retorna erros relevantes |
| `test` | Roda testes (`xcodebuild test`) |
| `run_app` | Compila (opcional) e abre o `.app` do DerivedData |
| `stop_app` | Finaliza o processo do app (`pkill -x`) |
| `restart_app` | Executa `scripts/restart.sh` (kill + build + launch) |
| `open_project` | Abre o projeto no Xcode |
| `raw` | `xcodebuild` com argumentos arbitrários |

## Instalação

```bash
cd mcp-xcode
npm install
npm run build
```

## Registro no VS Code

O arquivo `.vscode/mcp.json` na raiz do repositório já registra o servidor:

```json
{
  "servers": {
    "xcode": {
      "type": "stdio",
      "command": "node",
      "args": ["${workspaceFolder}/mcp-xcode/dist/index.js"]
    }
  }
}
```

Ao abrir o workspace, o VS Code pede para **confiar/aceitar** o servidor MCP — clique em **Allow**. Depois ele aparece no Chat do Copilot (modo Agent) como `xcode_<ferramenta>`.

> Se `${workspaceFolder}` não resolver, troque pelo caminho absoluto: `/Users/teintinu/dsv/fred/mcp-xcode/dist/index.js`.

## Teste manual (smoke)

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2026-07-28","capabilities":{},"clientInfo":{"name":"smoke","version":"1.0.0"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | node dist/index.js
```

## Desenvolvimento

```bash
npm run dev          # roda com tsx (sem build)
npm run typecheck    # checagem de tipos
```

## Referências

- SDK MCP TypeScript (v2): https://github.com/modelcontextprotocol/typescript-sdk
- Docs v2: https://ts.sdk.modelcontextprotocol.io/v2/
- Spec MCP: https://modelcontextprotocol.io/specification/2026-07-28
- xcodebuild: `man xcodebuild`
