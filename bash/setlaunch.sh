#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECK_DIR="$(dirname "$SCRIPT_DIR")"
GAMES_CONF="$DECK_DIR/games.conf"
RUN_SCRIPT="$DECK_DIR/bash/run.sh"

# --- Walidacja ---
if [[ ! -f "$GAMES_CONF" ]]; then
    echo "[ERR] Nie znaleziono games.conf: $GAMES_CONF"
    exit 1
fi

if pgrep -x "steam" > /dev/null; then
    echo "[ERR] Steam jest uruchomiony. Zamknij Steam przed użyciem tego skryptu."
    exit 1
fi

# --- Znajdź localconfig.vdf ---
STEAM_ROOT="${HOME}/.steam/steam"
USERDATA_DIR="$STEAM_ROOT/userdata"

if [[ ! -d "$USERDATA_DIR" ]]; then
    echo "[ERR] Nie znaleziono katalogu userdata: $USERDATA_DIR"
    exit 1
fi

# Wybierz użytkownika (jeśli jest więcej niż jeden, weź pierwszego)
USERIDS=($(ls "$USERDATA_DIR"))
if [[ ${#USERIDS[@]} -eq 0 ]]; then
    echo "[ERR] Brak użytkowników w userdata."
    exit 1
fi

if [[ ${#USERIDS[@]} -gt 1 ]]; then
    echo "Znaleziono wielu użytkowników:"
    for i in "${!USERIDS[@]}"; do
        echo "  [$i] ${USERIDS[$i]}"
    done
    read -rp "Wybierz numer użytkownika [0]: " choice
    choice="${choice:-0}"
    USERID="${USERIDS[$choice]}"
else
    USERID="${USERIDS[0]}"
fi

VDF_PATH="$USERDATA_DIR/$USERID/config/localconfig.vdf"

if [[ ! -f "$VDF_PATH" ]]; then
    echo "[ERR] Nie znaleziono localconfig.vdf: $VDF_PATH"
    exit 1
fi

echo "[INFO] Użytkownik: $USERID"
echo "[INFO] VDF: $VDF_PATH"

# --- Wczytaj games.conf ---
declare -A GAME_PROFILES
declare -A GAME_NAMES

while IFS=: read -r appid name profile; do
    [[ "$appid" =~ ^#.*$ || -z "$appid" ]] && continue
    appid="${appid// /}"
    profile="${profile// /}"
    GAME_PROFILES["$appid"]="$profile"
    GAME_NAMES["$appid"]="$name"
done < "$GAMES_CONF"

if [[ ${#GAME_PROFILES[@]} -eq 0 ]]; then
    echo "[WARN] games.conf jest pusty lub nie zawiera żadnych gier."
    exit 0
fi

echo "[INFO] Gier do ustawienia: ${#GAME_PROFILES[@]}"

# --- Backup VDF ---
cp "$VDF_PATH" "${VDF_PATH}.bak"
echo "[INFO] Backup: ${VDF_PATH}.bak"

# --- Modyfikuj VDF przez Python ---
python3 << PYEOF
import re
import sys

vdf_path = "$VDF_PATH"
run_script = "$RUN_SCRIPT"

game_profiles = {$(for k in "${!GAME_PROFILES[@]}"; do echo "\"$k\": \"${GAME_PROFILES[$k]}\","; done)}
game_names    = {$(for k in "${!GAME_NAMES[@]}"; do echo "\"$k\": \"${GAME_NAMES[$k]}\","; done)}

with open(vdf_path, "r", encoding="utf-8") as f:
    content = f.read()

updated = 0
skipped = 0

for appid, profile in game_profiles.items():
    launch_options = f"{run_script} %command%"

    # Znajdź blok danego AppID w sekcji "apps"
    # Wzorzec: "AppID"\n\s*{\n ... }
    app_pattern = re.compile(
        r'("' + re.escape(appid) + r'"\s*\{)(.*?)(^\s*\})',
        re.DOTALL | re.MULTILINE
    )

    match = app_pattern.search(content)
    if not match:
        print(f"[WARN] AppID {appid} ({game_names.get(appid, '?')}) nie znaleziono w VDF — pomijam")
        skipped += 1
        continue

    block_start = match.start(2)
    block_end   = match.end(2)
    block       = match.group(2)

    launch_pattern = re.compile(r'"LaunchOptions"\s*"[^"]*"')

    if launch_pattern.search(block):
        new_block = launch_pattern.sub(f'"LaunchOptions"\t\t"{launch_options}"', block)
    else:
        # Dodaj przed zamknięciem bloku
        indent = "\t\t\t"
        new_block = block.rstrip() + f'\n{indent}"LaunchOptions"\t\t"{launch_options}"\n'

    content = content[:block_start] + new_block + content[block_end:]
    print(f"[OK] {appid} ({game_names.get(appid, '?')}) [{profile}] -> {launch_options}")
    updated += 1

with open(vdf_path, "w", encoding="utf-8") as f:
    f.write(content)

print(f"\nGotowe: {updated} zaktualizowanych, {skipped} pominiętych.")
PYEOF
