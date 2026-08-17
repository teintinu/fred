#!/usr/bin/env node
/**
 * mcp-xcode — Servidor MCP que expõe o xcodebuild para agentes de IA.
 *
 * Ferramentas:
 *  - find_project       localiza .xcodeproj/.xcworkspace
 *  - list_schemes       lista schemes (xcodebuild -list -json)
 *  - list_destinations  lista destinos (xcodebuild -showdestinations)
 *  - build              compila (xcodebuild build)
 *  - test               roda testes (xcodebuild test)
 *  - run_app            abre o .app compilado (open)
 *  - stop_app           finaliza o processo (pkill -x)
 *  - restart_app        executa scripts/restart.sh (kill + build + launch)
 *  - open_project       abre o projeto no Xcode
 *  - raw                xcodebuild com argumentos arbitrários
 */
import { McpServer } from '@modelcontextprotocol/server';
import { StdioServerTransport } from '@modelcontextprotocol/server/stdio';
import * as z from 'zod/v4';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readdir } from 'node:fs/promises';
import path from 'node:path';

const execFileAsync = promisify(execFile);
const BUILD_TIMEOUT = 15 * 60 * 1000;
const TEST_TIMEOUT = 30 * 60 * 1000;

const server = new McpServer({ name: 'xcode', version: '0.1.0' });

// ---------------------------------------------------------------- helpers

type ExecResult = { ok: boolean; stdout: string; stderr: string; code: number | null };

async function exec(
  cmd: string,
  args: string[],
  timeout = BUILD_TIMEOUT,
  cwd?: string,
): Promise<ExecResult> {
  try {
    const { stdout, stderr } = await execFileAsync(cmd, args, {
      timeout,
      maxBuffer: 128 * 1024 * 1024,
      cwd,
    });
    return { ok: true, stdout, stderr, code: 0 };
  } catch (e) {
    const err = e as { stdout?: string; stderr?: string; message?: string; code?: number | null };
    return {
      ok: false,
      stdout: err.stdout ?? '',
      stderr: `${err.message ?? ''}\n${err.stderr ?? ''}`,
      code: err.code ?? null,
    };
  }
}

function tail(output: string, n = 200): string {
  const lines = output.split('\n');
  return lines.slice(-n).join('\n');
}

function errorLines(output: string): string {
  const lines = output
    .split('\n')
    .filter((l) => /(error:|fatal error:|BUILD FAILED|TEST FAILED|Assertion failed)/i.test(l));
  return lines.slice(-40).join('\n');
}

function text(content: string) {
  return { content: [{ type: 'text' as const, text: content }] };
}

type Target = { project?: string; workspace?: string };

async function findTarget(dir: string): Promise<Target> {
  const results: Target = {};
  async function walk(d: string, depth: number) {
    if (depth > 3) return;
    let entries;
    try {
      entries = await readdir(d, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const full = path.join(d, e.name);
      if (e.isDirectory()) {
        if (e.name.endsWith('.xcodeproj') && !results.project) results.project = full;
        else if (e.name.endsWith('.xcworkspace') && !results.workspace) results.workspace = full;
        else if (!e.name.startsWith('.')) await walk(full, depth + 1);
      }
    }
  }
  await walk(dir, 0);
  return results;
}

function xcodeTargetArgs(target: Target): string[] {
  if (target.workspace) return ['-workspace', target.workspace];
  if (target.project) return ['-project', target.project];
  return [];
}

function resolveDir(input?: string): string {
  if (input && input.trim().length > 0) return input;
  return process.env.FRED_REPO_ROOT ?? process.env.WORKSPACE_DIR ?? process.cwd();
}

async function resolveTarget(input?: string): Promise<{ dir: string } & Target> {
  const dir = resolveDir(input);
  const target = await findTarget(dir);
  return { dir, ...target };
}

async function buildApp(
  target: Target,
  scheme: string | undefined,
  configuration: string,
  derived: string,
): Promise<{ ok: boolean; message: string }> {
  const args = [
    ...xcodeTargetArgs(target),
    ...(scheme ? ['-scheme', scheme] : []),
    '-configuration',
    configuration,
    '-derivedDataPath',
    derived,
    'build',
  ];
  const r = await exec('xcodebuild', args);
  if (!r.ok) {
    return {
      ok: false,
      message: `BUILD FALHOU (exit ${r.code})\n${errorLines(r.stdout + r.stderr) || tail(r.stdout + r.stderr, 80)}`,
    };
  }
  return { ok: true, message: tail(r.stdout, 15) };
}

// ---------------------------------------------------------------- tools

server.registerTool(
  'find_project',
  {
    description:
      'Encontra .xcodeproj/.xcworkspace no diretório informado (padrão: raiz do repositório do Fred).',
    inputSchema: z.object({ workspaceDir: z.string().optional() }),
  },
  async ({ workspaceDir }: { workspaceDir?: string }) => {
    const t = await resolveTarget(workspaceDir);
    return text(JSON.stringify(t, null, 2));
  },
);

server.registerTool(
  'list_schemes',
  {
    description: 'Lista os schemes do projeto/workspace do Xcode.',
    inputSchema: z.object({ workspaceDir: z.string().optional() }),
  },
  async ({ workspaceDir }: { workspaceDir?: string }) => {
    const target = await resolveTarget(workspaceDir);
    if (!target.project && !target.workspace) return text('Nenhum projeto Xcode encontrado.');
    const r = await exec('xcodebuild', [...xcodeTargetArgs(target), '-list', '-json'], 60_000);
    if (!r.ok) return text(`xcodebuild -list falhou:\n${tail(r.stderr, 60)}`);
    return text(r.stdout || r.stderr);
  },
);

server.registerTool(
  'list_destinations',
  {
    description: 'Lista destinos de execução (xcodebuild -showdestinations).',
    inputSchema: z.object({
      workspaceDir: z.string().optional(),
      scheme: z.string().optional(),
    }),
  },
  async ({ workspaceDir, scheme }: { workspaceDir?: string; scheme?: string }) => {
    const target = await resolveTarget(workspaceDir);
    if (!target.project && !target.workspace) return text('Nenhum projeto Xcode encontrado.');
    const args = [...xcodeTargetArgs(target), ...(scheme ? ['-scheme', scheme] : []), '-showdestinations'];
    const r = await exec('xcodebuild', args, 120_000);
    return text(tail(r.stdout || r.stderr, 150));
  },
);

server.registerTool(
  'build',
  {
    description: 'Compila o app (xcodebuild build) e retorna status com erros relevantes.',
    inputSchema: z.object({
      workspaceDir: z.string().optional(),
      scheme: z.string().optional(),
      configuration: z.string().optional(),
      derivedDataPath: z.string().optional(),
    }),
  },
  async ({ workspaceDir, scheme, configuration, derivedDataPath }: {
    workspaceDir?: string;
    scheme?: string;
    configuration?: string;
    derivedDataPath?: string;
  }) => {
    const { dir, ...target } = await resolveTarget(workspaceDir);
    if (!target.project && !target.workspace) return text('Nenhum projeto Xcode encontrado.');
    const derived = derivedDataPath ?? path.join(dir, 'build', 'DerivedData');
    const r = await buildApp(target, scheme, configuration ?? 'Debug', derived);
    if (!r.ok) return text(r.message);
    return text(`BUILD OK.\n${r.message}`);
  },
);

server.registerTool(
  'test',
  {
    description: 'Roda os testes (xcodebuild test) do scheme informado.',
    inputSchema: z.object({
      workspaceDir: z.string().optional(),
      scheme: z.string().optional(),
      destination: z.string().optional(),
      derivedDataPath: z.string().optional(),
    }),
  },
  async ({ workspaceDir, scheme, destination, derivedDataPath }: {
    workspaceDir?: string;
    scheme?: string;
    destination?: string;
    derivedDataPath?: string;
  }) => {
    const { dir, ...target } = await resolveTarget(workspaceDir);
    if (!target.project && !target.workspace) return text('Nenhum projeto Xcode encontrado.');
    const derived = derivedDataPath ?? path.join(dir, 'build', 'DerivedData');
    const args = [
      ...xcodeTargetArgs(target),
      ...(scheme ? ['-scheme', scheme] : []),
      '-destination',
      destination ?? 'platform=macOS',
      '-derivedDataPath',
      derived,
      'test',
    ];
    const r = await exec('xcodebuild', args, TEST_TIMEOUT);
    if (!r.ok) {
      return text(
        `TESTE FALHOU (exit ${r.code})\n${errorLines(r.stdout + r.stderr) || tail(r.stdout + r.stderr, 100)}`,
      );
    }
    return text(`TESTES OK.\n${tail(r.stdout, 20)}`);
  },
);

server.registerTool(
  'run_app',
  {
    description:
      'Compila (opcional, padrão true) e abre o .app compilado (macOS) a partir do DerivedData.',
    inputSchema: z.object({
      workspaceDir: z.string().optional(),
      scheme: z.string().optional(),
      configuration: z.string().optional(),
      derivedDataPath: z.string().optional(),
      appName: z.string().optional(),
      buildFirst: z.boolean().optional(),
    }),
  },
  async ({ workspaceDir, scheme, configuration, derivedDataPath, appName, buildFirst }: {
    workspaceDir?: string;
    scheme?: string;
    configuration?: string;
    derivedDataPath?: string;
    appName?: string;
    buildFirst?: boolean;
  }) => {
    const { dir, ...target } = await resolveTarget(workspaceDir);
    if (!target.project && !target.workspace) return text('Nenhum projeto Xcode encontrado.');
    const config = configuration ?? 'Debug';
    const derived = derivedDataPath ?? path.join(dir, 'build', 'DerivedData');
    if (buildFirst !== false) {
      const b = await buildApp(target, scheme, config, derived);
      if (!b.ok) return text(b.message);
    }
    const products = path.join(derived, 'Build', 'Products', config);
    try {
      const entries = await readdir(products, { withFileTypes: true });
      const app = entries
        .filter((e) => e.isDirectory() && e.name.endsWith('.app') && (!appName || e.name.startsWith(appName)))
        .map((e) => path.join(products, e.name))
        .sort((a, b) => a.localeCompare(b))[0];
      if (!app) return text(`App não encontrado em ${products}.`);
      await exec('open', [app], 30_000);
      return text(`App iniciado: ${app}`);
    } catch {
      return text(`Nenhum produto em ${products} — compile antes (buildFirst=true).`);
    }
  },
);

server.registerTool(
  'stop_app',
  {
    description: 'Finaliza o processo do app pelo nome do executável (ex.: Fred) usando pkill -x.',
    inputSchema: z.object({ appName: z.string() }),
  },
  async ({ appName }: { appName: string }) => {
    const r = await exec('pkill', ['-x', appName], 15_000);
    if (r.ok) return text(`Processo '${appName}' finalizado.`);
    return text(`Nenhum processo '${appName}' em execução.`);
  },
);

server.registerTool(
  'restart_app',
  {
    description:
      'Executa scripts/restart.sh do repositório (kill + build + launch) — dev loop rápido do Fred.',
    inputSchema: z.object({
      workspaceDir: z.string().optional(),
      skipKill: z.boolean().optional(),
      skipBuild: z.boolean().optional(),
      skipLaunch: z.boolean().optional(),
    }),
  },
  async ({ workspaceDir, skipKill, skipBuild, skipLaunch }: {
    workspaceDir?: string;
    skipKill?: boolean;
    skipBuild?: boolean;
    skipLaunch?: boolean;
  }) => {
    const dir = resolveDir(workspaceDir);
    const script = path.join(dir, 'scripts', 'restart.sh');
    const args: string[] = [];
    if (skipKill) args.push('--no-kill');
    if (skipBuild) args.push('--no-build');
    if (skipLaunch) args.push('--no-launch');
    const r = await exec('/bin/bash', [script, ...args]);
    const out = (r.stdout + r.stderr).trim();
    return text(`${r.ok ? 'RESTART OK.' : `RESTART FALHOU (exit ${r.code})`}\n${tail(out, 120)}`);
  },
);

server.registerTool(
  'open_project',
  {
    description: 'Abre o projeto/workspace no Xcode.',
    inputSchema: z.object({ workspaceDir: z.string().optional() }),
  },
  async ({ workspaceDir }: { workspaceDir?: string }) => {
    const target = await resolveTarget(workspaceDir);
    const p = target.workspace ?? target.project;
    if (!p) return text('Nenhum projeto Xcode encontrado.');
    await exec('open', ['-a', 'Xcode', p], 30_000);
    return text(`Aberto no Xcode: ${p}`);
  },
);

server.registerTool(
  'raw',
  {
    description:
      'Executa xcodebuild com argumentos arbitrários (escape hatch). Use com cautela.',
    inputSchema: z.object({
      args: z.array(z.string()),
      timeoutSeconds: z.number().optional(),
      cwd: z.string().optional(),
    }),
  },
  async ({ args, timeoutSeconds, cwd }: {
    args: string[];
    timeoutSeconds?: number;
    cwd?: string;
  }) => {
    const r = await exec('xcodebuild', args, (timeoutSeconds ?? 600) * 1000, cwd);
    const out = r.stdout || r.stderr;
    return text(`${r.ok ? 'OK' : `FALHOU (exit ${r.code})`}\n${tail(out, 300)}`);
  },
);

// ---------------------------------------------------------------- main

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((e) => {
  console.error('Fatal:', e);
  process.exit(1);
});
