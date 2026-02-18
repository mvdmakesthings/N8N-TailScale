#!/usr/bin/env bash
set -euo pipefail

CONTAINER="ollama"
NETWORK="frontend"

usage() {
  echo "Usage: $0 <model> [model...]"
  echo ""
  echo "Pull one or more Ollama models by temporarily connecting the"
  echo "Ollama container to the internet."
  echo ""
  echo "Examples:"
  echo "  $0 mistral:7b"
  echo "  $0 llama3.1:8b codellama:34b"
  echo "  $0 qwen3-vl"
  echo ""
  echo "List installed models:"
  echo "  $0 --list"
  exit 1
}

list_models() {
  docker exec "$CONTAINER" ollama list
}

pull_models() {
  echo "Connecting $CONTAINER to $NETWORK network..."
  docker network connect "$NETWORK" "$CONTAINER"

  trap 'echo "Disconnecting $CONTAINER from $NETWORK network..."; docker network disconnect "$NETWORK" "$CONTAINER"' EXIT

  for model in "$@"; do
    echo ""
    echo "Pulling $model..."
    docker exec "$CONTAINER" ollama pull "$model"
  done

  echo ""
  echo "Done. Installed models:"
  list_models
}

[[ $# -eq 0 ]] && usage

if [[ "$1" == "--list" ]]; then
  list_models
  exit 0
fi

pull_models "$@"
