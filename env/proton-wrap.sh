#!/usr/bin/env bash
# proton-wrap - minimalist proton launcher
# tsoding philosophy: no bloat, one job, max perf
#
# usage: ustaw jako launch option w Steam:
#   ENV_DIR=/home/deck/dev/env GAME=eldenring /home/deck/dev/env/proton-wrap.sh %command%

set -euo pipefail

ENV_DIR="${ENV_DIR:-/home/deck/dev/env}"
GAME="${GAME:-}"

# auto-detect gry po AppID jesli nie podano GAME
if [[ -z "$GAME" && -n "${STEAM_COMPAT_APP_ID:-}" ]]; then
    case "$STEAM_COMPAT_APP_ID" in
        1245620) GAME=eldenring ;;
        489830)  GAME=skyrim ;;
        22380)   GAME=fnv ;;
        *)       GAME="" ;;
    esac
fi

# load base
# shellcheck source=/dev/null
source "$ENV_DIR/base.env"

# load game-specific
if [[ -n "$GAME" && -f "$ENV_DIR/$GAME.env" ]]; then
    source "$ENV_DIR/$GAME.env"
fi

mkdir -p "$HOME/.cache/dxvk-state"

exec "$@"
