#!/usr/bin/env bash
# download-whisper-model.sh — baixa o modelo GGML base (multilíngue) para o Fred.
# Uso: scripts/download-whisper-model.sh
set -euo pipefail

MODEL_DIR="$HOME/Library/Application Support/Fred/models"
MODEL="$MODEL_DIR/ggml-base.bin"
URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"

mkdir -p "$MODEL_DIR"
if [[ -f "$MODEL" ]]; then
  echo "Modelo já existe: $MODEL"
  exit 0
fi

echo "Baixando ggml-base.bin (~142 MB)..."
curl -L --fail --progress-bar -o "$MODEL.tmp" "$URL"
mv "$MODEL.tmp" "$MODEL"
echo "OK: $MODEL"
