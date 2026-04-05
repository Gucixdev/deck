#!/usr/bin/env bash
set -euo pipefail

# compress — backup i kompresja save'ów z gier, Proton prefixów, buildów
# Format: tar.zst (szybka kompresja, dobry ratio)
# Wymaga: zstd, tar

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECK_DIR="$(dirname "$SCRIPT_DIR")"
GAMES_CONF="$DECK_DIR/games.conf"
BACKUP_DIR="${DECK_BACKUP_DIR:-$HOME/GameBackups}"
STEAM_ROOT="${HOME}/.steam/steam"
COMPATDATA="$STEAM_ROOT/steamapps/compatdata"
USERDATA="$STEAM_ROOT/userdata"
COMPAT_TOOLS="$STEAM_ROOT/compatibilitytools.d"

B='\033[1;34m'; G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; C='\033[0;36m'; DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "  ${G}✔${NC}  $*"; }
info() { echo -e "  ${B}ℹ${NC}  $*"; }
warn() { echo -e "  ${Y}⚠${NC}  $*"; }
err()  { echo -e "  ${R}✖${NC}  $*"; exit 1; }
kbtn() { printf "${DIM}⌈${NC}${Y}${BOLD} %s ${NC}${DIM}⌋${NC}" "$1"; }
hs()   { du -sh "$1" 2>/dev/null | cut -f1 || echo "0B"; }

banner() {
    echo
    echo -e "  ${B}╭──────────────────────────────────────────────────╮${NC}"
    echo -e "  ${B}│${NC}  ${BOLD}📦  Compress — Game Saves & Builds Backup${NC}         ${B}│${NC}"
    echo -e "  ${B}╰──────────────────────────────────────────────────╯${NC}"
    echo
}

check_deps() {
    command -v zstd &>/dev/null || err "zstd nie zainstalowany — sudo apt install zstd"
    command -v tar  &>/dev/null || err "tar nie zainstalowany"
}

ts() { date +%Y%m%d_%H%M; }

mk_archive() {
    local name="$1" src="$2" out_dir="$3"
    mkdir -p "$out_dir"
    local out="$out_dir/${name}_$(ts).tar.zst"
    tar -C "$(dirname "$src")" \
        --use-compress-program="zstd -T0 -19" \
        -cf "$out" \
        "$(basename "$src")" 2>/dev/null
    echo "$out"
}

# ─── Znajdź save'y w Proton prefix ───────────────────────────────────────────
# Typowe lokalizacje: Documents, Saved Games, AppData/Local, AppData/Roaming
find_saves_in_prefix() {
    local prefix="$1"
    local user_dir="$prefix/drive_c/users/steamuser"
    local found=()

    local dirs=(
        "Documents"
        "Saved Games"
        "AppData/Local"
        "AppData/Roaming"
        "AppData/LocalLow"
        "My Documents"
    )

    for d in "${dirs[@]}"; do
        local p="$user_dir/$d"
        if [[ -d "$p" ]] && [[ -n "$(ls -A "$p" 2>/dev/null)" ]]; then
            found+=("$p")
        fi
    done

    printf '%s\n' "${found[@]:-}"
}

# ─── Backup save'ów jednej gry ────────────────────────────────────────────────
backup_game_saves() {
    local appid="$1"
    local game_name="${2:-AppID_$appid}"
    local out_dir="$BACKUP_DIR/saves/$(echo "$game_name" | tr ' /' '__')"

    info "Backup save'ów: $game_name ($appid)..."

    local backed=0

    # 1. Steam Cloud saves (userdata)
    while IFS= read -r uid_dir; do
        local save_dir="$uid_dir/$appid"
        if [[ -d "$save_dir" ]]; then
            local out; out=$(mk_archive "steam_cloud_${appid}" "$save_dir" "$out_dir")
            log "Steam Cloud: $(hs "$out") → $out"
            (( backed++ ))
        fi
    done < <(ls -d "$USERDATA"/*/  2>/dev/null || true)

    # 2. Proton prefix saves
    local prefix="$COMPATDATA/$appid/pfx"
    if [[ -d "$prefix" ]]; then
        local saves
        saves=$(find_saves_in_prefix "$prefix")
        if [[ -n "$saves" ]]; then
            while IFS= read -r save_path; do
                [[ -z "$save_path" ]] && continue
                local label
                label=$(basename "$save_path" | tr ' ' '_')
                local out; out=$(mk_archive "${appid}_${label}" "$save_path" "$out_dir")
                log "Prefix/$label: $(hs "$out") → $(basename "$out")"
                (( backed++ ))
            done <<< "$saves"
        fi
    fi

    if [[ "$backed" -eq 0 ]]; then
        warn "Nie znaleziono save'ów dla $appid"
    else
        log "$game_name — $backed archiwów → $out_dir"
    fi
}

# ─── Backup wszystkich gier z games.conf ─────────────────────────────────────
backup_all_saves() {
    info "Backup wszystkich gier z games.conf..."
    local count=0

    while IFS=: read -r appid name _profile; do
        [[ "$appid" =~ ^#.*$ || -z "$appid" ]] && continue
        appid="${appid// /}"
        backup_game_saves "$appid" "$name"
        (( count++ ))
    done < "$GAMES_CONF"

    log "Backup zakończony — $count gier"
}

# ─── Backup pełnego Proton prefix (cała gra + registry) ──────────────────────
backup_prefix() {
    local appid="$1" game_name="${2:-AppID_$appid}"
    local prefix_dir="$COMPATDATA/$appid"

    [[ ! -d "$prefix_dir" ]] && warn "Brak prefix dla $appid" && return

    info "Backup pełnego prefix: $game_name ($appid)..."
    local out_dir="$BACKUP_DIR/prefixes"
    local out; out=$(mk_archive "prefix_${appid}" "$prefix_dir" "$out_dir")
    log "Prefix $(hs "$prefix_dir") → $(hs "$out") : $(basename "$out")"
}

# ─── Backup starych Proton buildów ───────────────────────────────────────────
backup_proton_builds() {
    info "Backup Proton buildów..."
    local out_dir="$BACKUP_DIR/proton_builds"
    local count=0

    for build_dir in "$COMPAT_TOOLS"/proton-deck-*; do
        [[ -d "$build_dir" ]] || continue
        local name; name=$(basename "$build_dir")
        local size; size=$(hs "$build_dir")
        local out; out=$(mk_archive "$name" "$build_dir" "$out_dir")
        log "$name ($size) → $(hs "$out") : $(basename "$out")"
        (( count++ ))
    done

    [[ "$count" -eq 0 ]] && warn "Brak proton-deck-* buildów w compatibilitytools.d"
}

# ─── Restore ──────────────────────────────────────────────────────────────────
restore_archive() {
    local archive="$1"
    local target="${2:-$HOME}"

    [[ ! -f "$archive" ]] && err "Archiwum nie istnieje: $archive"

    info "Przywracam: $archive → $target"
    mkdir -p "$target"
    tar -C "$target" \
        --use-compress-program="zstd -d" \
        -xf "$archive"
    log "Przywrócono do: $target"
}

# ─── Lista archiwów ───────────────────────────────────────────────────────────
list_backups() {
    echo -e "  ${C}── Backupy w $BACKUP_DIR ───────────────────────────${NC}"
    echo

    if [[ ! -d "$BACKUP_DIR" ]]; then
        warn "Brak katalogu backupów: $BACKUP_DIR"
        return
    fi

    local total_size; total_size=$(hs "$BACKUP_DIR")
    echo -e "  Łączny rozmiar: ${BOLD}$total_size${NC}"
    echo

    find "$BACKUP_DIR" -name "*.tar.zst" 2>/dev/null | sort | while read -r f; do
        local rel="${f#$BACKUP_DIR/}"
        local size; size=$(hs "$f")
        local date; date=$(stat -c %y "$f" 2>/dev/null | cut -d' ' -f1 || echo "?")
        printf "  %-55s %6s  %s\n" "$rel" "$size" "$date"
    done

    echo -e "  ${C}────────────────────────────────────────────────────${NC}"
}

# ─── Wyczyść stare backupy ────────────────────────────────────────────────────
clean_old_backups() {
    local keep="${1:-5}"
    info "Zostawiam $keep najnowszych backupów per gra..."

    find "$BACKUP_DIR" -name "*.tar.zst" 2>/dev/null | \
        sed 's/_[0-9]\{8\}_[0-9]\{4\}\.tar\.zst$//' | \
        sort -u | while read -r prefix; do
            local files
            files=$(ls "${prefix}"_*.tar.zst 2>/dev/null | sort -r || true)
            local count=0
            while IFS= read -r f; do
                (( count++ ))
                if [[ "$count" -gt "$keep" ]]; then
                    rm -f "$f"
                    echo -e "  ${R}✖${NC}  Usunięto: $(basename "$f")"
                fi
            done <<< "$files"
        done

    log "Czyszczenie zakończone (zachowano max $keep per gra)"
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
banner
check_deps

echo -e "  Backup dir: ${DIM}$BACKUP_DIR${NC}  ${DIM}(zmień przez DECK_BACKUP_DIR=... bash compress)${NC}"
echo
echo -e "  Co zrobić?\n"
echo -e "  $(kbtn "1") 💾  Backup save'ów jednej gry"
echo -e "  $(kbtn "2") 💾  Backup save'ów wszystkich gier (games.conf)"
echo -e "  $(kbtn "3") 🗂  Backup pełnego Wine prefix jednej gry"
echo -e "  $(kbtn "4") ⚙️  Backup Proton buildów (proton-deck-*)"
echo -e "  $(kbtn "5") 📋  Lista wszystkich backupów"
echo -e "  $(kbtn "6") ♻️  Przywróć z archiwum"
echo -e "  $(kbtn "7") 🗑  Wyczyść stare backupy (zostaw N najnowszych)"
echo -e "  $(kbtn "Q") ⏭  Wyjście"
echo
read -rp "  > " choice

case "$choice" in
    1)
        read -rp "  AppID: " appid
        # Pobierz nazwę z games.conf
        name=$(grep "^${appid}:" "$GAMES_CONF" 2>/dev/null | cut -d: -f2 || echo "")
        backup_game_saves "$appid" "${name:-AppID_$appid}"
        ;;
    2)
        backup_all_saves
        ;;
    3)
        read -rp "  AppID: " appid
        name=$(grep "^${appid}:" "$GAMES_CONF" 2>/dev/null | cut -d: -f2 || echo "")
        backup_prefix "$appid" "${name:-AppID_$appid}"
        ;;
    4)
        backup_proton_builds
        ;;
    5)
        list_backups
        ;;
    6)
        list_backups
        echo
        read -rp "  Ścieżka do archiwum: " arc
        read -rp "  Cel przywrócenia [$HOME]: " target
        restore_archive "$arc" "${target:-$HOME}"
        ;;
    7)
        read -rp "  Ile backupów zostawić per gra [5]: " keep
        clean_old_backups "${keep:-5}"
        ;;
    [qQ])
        exit 0
        ;;
    *)
        err "Nieznana opcja"
        ;;
esac
