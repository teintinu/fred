#!/usr/bin/env bash
# restart.sh — dev loop do Fred: mata o processo, compila e relança o app.
#
# Uso:
#   scripts/restart.sh               mata + build + launch (fluxo completo)
#   scripts/restart.sh --no-kill     pula a etapa de matar o processo
#   scripts/restart.sh --no-build    pula o build
#   scripts/restart.sh --no-launch   pula o launch
#   scripts/restart.sh --help        mostra esta ajuda
#
# Configuração via variáveis de ambiente:
#   FRED_APP_NAME        nome do executável/.app (padrão: Fred)
#   FRED_SCHEME          scheme do Xcode (padrão: Fred)
#   FRED_CONFIGURATION   Debug | Release (padrão: Debug)
#   FRED_DERIVED_DATA    caminho do DerivedData (padrão: $REPO/build/DerivedData)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="${FRED_APP_NAME:-Fred}"
SCHEME="${FRED_SCHEME:-Fred}"
CONFIGURATION="${FRED_CONFIGURATION:-Debug}"
DERIVED_DATA="${FRED_DERIVED_DATA:-$ROOT/build/DerivedData}"

DO_KILL=1 DO_BUILD=1 DO_LAUNCH=1

for arg in "$@"; do
  case "$arg" in
    --no-kill)   DO_KILL=0 ;;
    --no-build)  DO_BUILD=0 ;;
    --no-launch) DO_LAUNCH=0 ;;
    -h|--help)
      grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' | head -20
      exit 0
      ;;
    *)
      echo "Argumento desconhecido: $arg (use --help)" >&2
      exit 2
      ;;
  esac
done

c() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
info() { c 36 "ℹ  $1"; }
ok()   { c 32 "✔  $1"; }
err()  { c 31 "✖  $1"; exit 1; }

# 1) Localizar projeto/workspace
WORKSPACE="$(ls -d "$ROOT"/*.xcworkspace 2>/dev/null | head -1 || true)"
PROJECT="$(ls -d "$ROOT"/*.xcodeproj 2>/dev/null | head -1 || true)"
if [[ -n "$WORKSPACE" ]]; then
  TARGET=(-workspace "$WORKSPACE")
  info "Workspace: $WORKSPACE"
elif [[ -n "$PROJECT" ]]; then
  TARGET=(-project "$PROJECT")
  info "Projeto: $PROJECT"
else
  err "Nenhum .xcodeproj/.xcworkspace encontrado em $ROOT (o projeto Xcode do Fred ainda não foi criado)."
fi

# 2) Matar o processo do app
if (( DO_KILL )); then
  if pkill -x "$APP_NAME" 2>/dev/null; then
    ok "Processo '$APP_NAME' finalizado."
  else
    info "Nenhum processo '$APP_NAME' rodando."
  fi
fi

# 3) Build
if (( DO_BUILD )); then
  info "Compilando ($SCHEME/$CONFIGURATION)..."
  mkdir -p "$DERIVED_DATA"
  LOG="$DERIVED_DATA/build.log"
  if ! xcodebuild "${TARGET[@]}" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED_DATA" build > "$LOG" 2>&1; then
    grep -E "error:|BUILD FAILED" "$LOG" | tail -30 || true
    err "Build falhou. Log completo: $LOG"
  fi
  ok "Build concluído."
fi

# 4) Launch
if (( DO_LAUNCH )); then
  APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
  if [[ ! -d "$APP_PATH" ]]; then
    APP_PATH="$(find "$DERIVED_DATA/Build/Products/$CONFIGURATION" -maxdepth 1 -name "$APP_NAME.app" -print -quit 2>/dev/null || true)"
  fi
  [[ -n "$APP_PATH" && -d "$APP_PATH" ]] || err "App '$APP_NAME.app' não encontrado em $DERIVED_DATA/Build/Products/$CONFIGURATION"
  open "$APP_PATH"
  ok "App iniciado: $APP_PATH"
fi
