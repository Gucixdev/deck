#!/usr/bin/env bash
set -euo pipefail

# fetchgames — pobiera gry ze Steam API + ProtonDB ratings
# Zapisuje: games.conf (AppID:Nazwa:profil), games.info (szczegóły + ProtonDB)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECK_DIR="$(dirname "$SCRIPT_DIR")"
STEAM_ENV="$DECK_DIR/env/steam.env"
GAMES_CONF="$DECK_DIR/games.conf"
GAMES_INFO="$DECK_DIR/games.info"
PROTONDB_CACHE="$DECK_DIR/build/protondb_cache"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[1;34m'; NC='\033[0m'

# ─── Credentials ──────────────────────────────────────────────────────────────
[[ ! -f "$STEAM_ENV" ]] && echo "[ERR] Brak: $STEAM_ENV" && exit 1
source "$STEAM_ENV"
[[ -z "${STEAM_API_KEY:-}" || -z "${STEAM_ID:-}" ]] && \
    echo "[ERR] Uzupełnij STEAM_API_KEY i STEAM_ID w env/steam.env" && exit 1

# ─── Steam API ────────────────────────────────────────────────────────────────
echo "[INFO] Pobieram gry dla Steam ID: $STEAM_ID ..."

RESPONSE=$(curl -sf \
    "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?key=${STEAM_API_KEY}&steamid=${STEAM_ID}&include_appinfo=1&include_played_free_games=1&format=json")

[[ -z "$RESPONSE" ]] && echo "[ERR] Brak odpowiedzi Steam API" && exit 1

GAME_COUNT=$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['response'].get('game_count', 0))")
echo "[INFO] Gier: $GAME_COUNT"
[[ "$GAME_COUNT" -eq 0 ]] && echo "[WARN] Brak gier lub profil prywatny" && exit 0

# ─── ProtonDB — pobierz ratings ───────────────────────────────────────────────
# Cache: build/protondb_cache/<AppID>.json — ważny 7 dni
mkdir -p "$PROTONDB_CACHE"

fetch_protondb() {
    local appid="$1"
    local cache_file="$PROTONDB_CACHE/${appid}.json"
    local max_age_days=7

    # Użyj cache jeśli świeży
    if [[ -f "$cache_file" ]]; then
        local age_days
        age_days=$(( ( $(date +%s) - $(stat -c %Y "$cache_file") ) / 86400 ))
        [[ "$age_days" -lt "$max_age_days" ]] && cat "$cache_file" && return
    fi

    # Pobierz
    local data
    data=$(curl -sf --max-time 3 \
        "https://www.protondb.com/api/v1/reports/summaries/${appid}.json" 2>/dev/null || echo "null")

    echo "$data" > "$cache_file"
    echo "$data"
}

# ─── Wczytaj istniejące wpisy ────────────────────────────────────────────────
declare -A EXISTING

if [[ -f "$GAMES_CONF" ]]; then
    while IFS=: read -r appid _name profile; do
        [[ "$appid" =~ ^#.*$ || -z "$appid" ]] && continue
        appid="${appid// /}"
        EXISTING["$appid"]="${profile// /}"
    done < "$GAMES_CONF"
fi

echo "[INFO] Istniejących wpisów: ${#EXISTING[@]}"

# ─── Pobierz ProtonDB dla top gier (>1h) i zapisz w tle ──────────────────────
echo "[INFO] Pobieram ProtonDB ratings (>1h gry)..."

# Wyodrębnij AppIDs z >60 min (żeby nie pobierać dla wszystkich 500 gier)
ACTIVE_APPIDS=$(echo "$RESPONSE" | python3 -c "
import json,sys
games = json.load(sys.stdin)['response'].get('games', [])
ids = [str(g['appid']) for g in games if g.get('playtime_forever', 0) > 60]
print('\n'.join(ids))
")

PROTONDB_COUNT=0
while IFS= read -r appid; do
    [[ -z "$appid" ]] && continue
    fetch_protondb "$appid" > /dev/null &
    (( PROTONDB_COUNT++ ))
    # Max 10 równoległych requestów
    [[ $(jobs -r | wc -l) -ge 10 ]] && wait
done <<< "$ACTIVE_APPIDS"
wait
echo "[INFO] ProtonDB cache: $PROTONDB_COUNT gier"

# ─── Python: games.conf + games.info ─────────────────────────────────────────
python3 << PYEOF
import json, datetime, os

response   = json.loads(r"""$RESPONSE""")
games      = response["response"].get("games", [])
games.sort(key=lambda g: g.get("name", "").lower())

existing        = {$(for k in "${!EXISTING[@]}"; do echo "\"$k\": \"${EXISTING[$k]}\","; done)}
games_conf_path = "$GAMES_CONF"
games_info_path = "$GAMES_INFO"
pdb_cache_dir   = "$PROTONDB_CACHE"

# ── Mapowanie ProtonDB tier → sugerowany profil ──────────────────────────────
TIER_PROFILE = {
    "platinum": "vanilla",
    "gold":     "vanilla",
    "silver":   "mod",      # wymaga tweakow — mod profil bardziej liberalny
    "bronze":   "mod",
    "borked":   "mod",      # sprawdź overrides ręcznie
}

TIER_EMOJI = {
    "platinum": "🏆",
    "gold":     "🥇",
    "silver":   "🥈",
    "bronze":   "🥉",
    "borked":   "💀",
    "unknown":  "❓",
}

def get_protondb(appid):
    path = os.path.join(pdb_cache_dir, f"{appid}.json")
    if not os.path.exists(path):
        return None, "unknown", 0
    try:
        with open(path) as f:
            data = json.load(f)
        if not data or data == "null":
            return None, "unknown", 0
        tier  = data.get("tier", "unknown").lower()
        total = data.get("total", 0)
        score = data.get("score", 0.0)
        return data, tier, total
    except Exception:
        return None, "unknown", 0

# ── games.conf — dodaj nowe gry ──────────────────────────────────────────────
added = skipped = 0
try:
    with open(games_conf_path) as f:
        existing_content = f.read()
except FileNotFoundError:
    existing_content = "# AppID:nazwa:profil\n# Profile: vanilla | mod | online\n\n"

new_lines = []
for game in games:
    appid = str(game["appid"])
    name  = game.get("name", f"AppID_{appid}").replace(":", "-")
    if appid in existing:
        skipped += 1
        continue
    # Auto-profil z ProtonDB
    _data, tier, _total = get_protondb(appid)
    profile = TIER_PROFILE.get(tier, "vanilla")
    new_lines.append(f"{appid}:{name}:{profile}")
    added += 1

if new_lines:
    with open(games_conf_path, "a") as f:
        if not existing_content.endswith("\n\n"):
            f.write("\n")
        f.write("\n".join(new_lines) + "\n")

print(f"[OK] games.conf — dodano: {added}, pominięto: {skipped}")

# ── games.info — szczegóły + ProtonDB ────────────────────────────────────────
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
lines = [
    f"# Steam games info + ProtonDB — {now}",
    f"# Steam ID: $STEAM_ID",
    f"# Gier: {len(games)}",
    f"# Format: AppID | Nazwa | Godziny | Ostatnie uruchomienie | ProtonDB | Ocen",
    "#" + "-" * 85,
    "",
]

for game in games:
    appid      = str(game["appid"])
    name       = game.get("name", f"AppID_{appid}")
    hours      = game.get("playtime_forever", 0) / 60
    last_epoch = game.get("rtime_last_played", 0)
    last       = datetime.datetime.fromtimestamp(last_epoch).strftime("%Y-%m-%d") if last_epoch else "nigdy"

    _data, tier, total = get_protondb(appid)
    emoji = TIER_EMOJI.get(tier, "❓")
    pdb   = f"{emoji} {tier:<8}" if tier != "unknown" else "  ❓       "
    pdb_n = f"{total:>5}" if total else "    -"

    lines.append(
        f"{appid:<12} | {name:<48} | {hours:>7.1f}h | {last} | {pdb} | {pdb_n}"
    )

with open(games_info_path, "w") as f:
    f.write("\n".join(lines) + "\n")

print(f"[OK] games.info — {len(games)} gier z ProtonDB ratings → $GAMES_INFO")

# ── Podsumowanie ProtonDB ─────────────────────────────────────────────────────
tier_counts = {}
for game in games:
    appid = str(game["appid"])
    _d, tier, _t = get_protondb(appid)
    tier_counts[tier] = tier_counts.get(tier, 0) + 1

print()
print("[ProtonDB summary]")
for tier, count in sorted(tier_counts.items(), key=lambda x: ["platinum","gold","silver","bronze","borked","unknown"].index(x[0]) if x[0] in ["platinum","gold","silver","bronze","borked","unknown"] else 99):
    emoji = TIER_EMOJI.get(tier, "?")
    print(f"  {emoji} {tier:<10} {count}")
PYEOF
