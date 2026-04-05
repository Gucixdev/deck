#!/usr/bin/env bash
set -euo pipefail

# runps4 — TUI launcher dla PS4 gier przez shadPS4
# Użycie: bash runps4 [CUSA_ID]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECK_DIR="$(dirname "$SCRIPT_DIR")"
PS4_CONF="$DECK_DIR/env/ps4games.conf"
SHADPS4_BIN="$DECK_DIR/build/shadps4/build/shadps4"

B='\033[1;34m'; G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; C='\033[0;36m'; DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'
kbtn() { printf "${DIM}⌈${NC}${Y}${BOLD} %s ${NC}${DIM}⌋${NC}" "$1"; }
err()  { echo -e "  ${R}✖${NC}  $*"; exit 1; }
info() { echo -e "  ${B}ℹ${NC}  $*"; }

# ─── Sprawdź binary ───────────────────────────────────────────────────────────
if [[ ! -f "$SHADPS4_BIN" ]]; then
    echo -e "  ${R}✖${NC}  shadPS4 nie zbudowany"
    echo -e "  Uruchom: ${Y}bash buildshadps4${NC}"
    exit 1
fi

# ─── Wczytaj gry ──────────────────────────────────────────────────────────────
declare -a CUSA_IDS
declare -a GAME_NAMES
declare -a GAME_PATHS

while IFS=: read -r cusa name path; do
    [[ "$cusa" =~ ^#.*$ || -z "$cusa" ]] && continue
    cusa="${cusa// /}"
    CUSA_IDS+=("$cusa")
    GAME_NAMES+=("$name")
    GAME_PATHS+=("$path")
done < "$PS4_CONF"

# ─── Bezpośrednie uruchomienie przez CUSA ID ─────────────────────────────────
if [[ -n "${1:-}" ]]; then
    TARGET_CUSA="$1"
    for i in "${!CUSA_IDS[@]}"; do
        if [[ "${CUSA_IDS[$i]}" == "$TARGET_CUSA" ]]; then
            GAME_PATH="${GAME_PATHS[$i]}"
            GAME_NAME="${GAME_NAMES[$i]}"
            [[ ! -d "$GAME_PATH" ]] && err "Ścieżka nie istnieje: $GAME_PATH"
            echo -e "\n  ${G}▶${NC}  ${BOLD}$GAME_NAME${NC}  ${DIM}($TARGET_CUSA)${NC}\n"
            exec "$SHADPS4_BIN" "$GAME_PATH"
        fi
    done
    err "CUSA ID nie znaleziono w ps4games.conf: $TARGET_CUSA"
fi

# ─── TUI ─────────────────────────────────────────────────────────────────────
clear
echo
echo -e "  ${B}╭──────────────────────────────────────────────────╮${NC}"
echo -e "  ${B}│${NC}  ${BOLD}🎮  PS4 Games — shadPS4 Launcher${NC}                  ${B}│${NC}"
echo -e "  ${B}╰──────────────────────────────────────────────────╯${NC}"
echo

if [[ ${#CUSA_IDS[@]} -eq 0 ]]; then
    echo -e "  ${Y}⚠${NC}  Brak gier w env/ps4games.conf"
    echo
    echo -e "  Dodaj gry w formacie:"
    echo -e "  ${DIM}CUSA00900:Bloodborne:/home/user/PS4Games/CUSA00900${NC}"
    echo
    exit 0
fi

# Wyświetl listę
for i in "${!CUSA_IDS[@]}"; do
    local_num=$(( i + 1 ))
    local_path="${GAME_PATHS[$i]}"
    local_ok="${R}✖ brak${NC}"
    [[ -d "$local_path" ]] && local_ok="${G}✔${NC}"

    printf "  $(kbtn "%2d") %-40s ${DIM}%s${NC}  %b\n" \
        "$local_num" \
        "${GAME_NAMES[$i]}" \
        "${CUSA_IDS[$i]}" \
        "$local_ok"
done

echo
echo -e "  $(kbtn " Q") Wyjście"
echo
read -rp "  > " choice

[[ "$choice" =~ ^[qQ]$ ]] && exit 0
[[ ! "$choice" =~ ^[0-9]+$ ]] && err "Nieprawidłowy wybór"

IDX=$(( choice - 1 ))
[[ "$IDX" -lt 0 || "$IDX" -ge ${#CUSA_IDS[@]} ]] && err "Numer poza zakresem"

GAME_PATH="${GAME_PATHS[$IDX]}"
GAME_NAME="${GAME_NAMES[$IDX]}"
TARGET_CUSA="${CUSA_IDS[$IDX]}"

[[ ! -d "$GAME_PATH" ]] && err "Ścieżka nie istnieje: $GAME_PATH"

echo
echo -e "  ${G}▶${NC}  ${BOLD}$GAME_NAME${NC}  ${DIM}($TARGET_CUSA)${NC}"
echo -e "  ${DIM}$GAME_PATH${NC}"
echo

exec "$SHADPS4_BIN" "$GAME_PATH"
