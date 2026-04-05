#!/usr/bin/env bash
set -euo pipefail

# fixshaders.sh — DXVK/VKD3D shader cache management
# Pre-warm, eksport/import, statystyki, czyszczenie

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECK_DIR="$(dirname "$SCRIPT_DIR")"
DXVK_CACHE="${HOME}/.cache/dxvk"
VKD3D_CACHE="${HOME}/.cache/vkd3d-proton"
MESA_CACHE="${HOME}/.cache/mesa_shader_cache"
STEAM_SHADER_CACHE="${HOME}/.steam/steam/steamapps/shadercache"
BACKUP_DIR="$DECK_DIR/build/shader_backups"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[1;34m'; C='\033[0;36m'; DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "  ${G}✔${NC}  $*"; }
info() { echo -e "  ${B}ℹ${NC}  $*"; }
warn() { echo -e "  ${Y}⚠${NC}  $*"; }
kbtn() { printf "${DIM}⌈${NC}${Y}${BOLD} %s ${NC}${DIM}⌋${NC}" "$1"; }

banner() {
    echo
    echo -e "  ${B}╭──────────────────────────────────────────────────╮${NC}"
    echo -e "  ${B}│${NC}  ${BOLD}⚡  FixShaders — Shader Cache Manager${NC}             ${B}│${NC}"
    echo -e "  ${B}╰──────────────────────────────────────────────────╯${NC}"
    echo
}

human_size() {
    du -sh "$1" 2>/dev/null | cut -f1 || echo "0"
}

# ─── Statystyki cache ─────────────────────────────────────────────────────────
show_stats() {
    echo -e "  ${C}── Shader Cache — Stan ─────────────────────────────${NC}"
    echo

    # DXVK
    local dxvk_size dxvk_count
    dxvk_size=$(human_size "$DXVK_CACHE")
    dxvk_count=$(find "$DXVK_CACHE" -name "*.dxvk-cache" 2>/dev/null | wc -l || echo 0)
    echo -e "  DXVK cache:      ${BOLD}$dxvk_size${NC}  ($dxvk_count plików)"

    # VKD3D
    local vkd3d_size vkd3d_count
    vkd3d_size=$(human_size "$VKD3D_CACHE")
    vkd3d_count=$(find "$VKD3D_CACHE" -name "*.cache" 2>/dev/null | wc -l || echo 0)
    echo -e "  VKD3D-Proton:    ${BOLD}$vkd3d_size${NC}  ($vkd3d_count plików)"

    # Mesa
    if [[ -d "$MESA_CACHE" ]]; then
        echo -e "  Mesa shader:     ${BOLD}$(human_size "$MESA_CACHE")${NC}"
    fi

    # Steam shader pre-cache
    if [[ -d "$STEAM_SHADER_CACHE" ]]; then
        local steam_size steam_count
        steam_size=$(human_size "$STEAM_SHADER_CACHE")
        steam_count=$(ls "$STEAM_SHADER_CACHE" 2>/dev/null | wc -l || echo 0)
        echo -e "  Steam pre-cache: ${BOLD}$steam_size${NC}  ($steam_count gier)"
    fi

    echo
    # Per-gra DXVK cache
    if [[ "$dxvk_count" -gt 0 ]]; then
        echo -e "  ${C}── Per-gra DXVK ─────────────────────────────────────${NC}"
        find "$DXVK_CACHE" -name "*.dxvk-cache" 2>/dev/null | while read -r f; do
            local fname fsize
            fname=$(basename "$f")
            fsize=$(human_size "$f")
            printf "  %-45s %s\n" "$fname" "$fsize"
        done
        echo
    fi

    echo -e "  ${C}────────────────────────────────────────────────────${NC}"
}

# ─── Pre-warm przez dxvk-cache-client ────────────────────────────────────────
prewarm_dxvk() {
    local appid="${1:-}"

    if ! command -v dxvk-cache-client &>/dev/null; then
        warn "dxvk-cache-client nie zainstalowany"
        info "AUR: yay -S dxvk-cache-client lub https://github.com/DarkTigrus/dxvk-cache-tool"
        return 1
    fi

    if [[ -n "$appid" ]]; then
        local cache_file="$DXVK_CACHE/${appid}.dxvk-cache"
        if [[ -f "$cache_file" ]]; then
            info "Pre-warm DXVK cache dla AppID $appid..."
            dxvk-cache-client merge "$cache_file" "$cache_file" 2>/dev/null && \
                log "Pre-warm gotowy: $cache_file" || \
                warn "Pre-warm nieudany"
        else
            warn "Brak cache dla AppID $appid — uruchom grę raz żeby go stworzyć"
        fi
    else
        info "Pre-warm wszystkich DXVK cache..."
        find "$DXVK_CACHE" -name "*.dxvk-cache" | while read -r f; do
            dxvk-cache-client merge "$f" "$f" 2>/dev/null && \
                log "$(basename "$f")" || true
        done
    fi
}

# ─── Eksport cache ────────────────────────────────────────────────────────────
export_cache() {
    local appid="${1:-all}"
    mkdir -p "$BACKUP_DIR"
    local ts; ts=$(date +%Y%m%d_%H%M)
    local archive="$BACKUP_DIR/shader_cache_${appid}_${ts}.tar.gz"

    info "Eksportuję shader cache..."

    if [[ "$appid" == "all" ]]; then
        tar -czf "$archive" \
            -C "$HOME/.cache" dxvk vkd3d-proton 2>/dev/null || true
    else
        tar -czf "$archive" \
            -C "$DXVK_CACHE" "${appid}.dxvk-cache" 2>/dev/null || true
    fi

    log "Backup: $archive ($(human_size "$archive"))"
    echo -e "  ${DIM}Skopiuj na inny PC żeby nie kompilować shaderów od zera${NC}"
}

# ─── Import cache ─────────────────────────────────────────────────────────────
import_cache() {
    local archive="$1"

    if [[ ! -f "$archive" ]]; then
        warn "Plik nie istnieje: $archive"
        return 1
    fi

    info "Importuję shader cache z $archive..."
    mkdir -p "$DXVK_CACHE" "$VKD3D_CACHE"
    tar -xzf "$archive" -C "$HOME/.cache" 2>/dev/null || {
        warn "Błąd podczas importu"
        return 1
    }
    log "Import gotowy"
}

# ─── Merge DXVK cache (usuwa duplikaty) ──────────────────────────────────────
merge_dxvk() {
    local appid="${1:-}"

    if ! command -v dxvk-cache-client &>/dev/null; then
        warn "dxvk-cache-client wymagany do merge"
        return 1
    fi

    if [[ -n "$appid" ]]; then
        local f="$DXVK_CACHE/${appid}.dxvk-cache"
        [[ -f "$f" ]] || { warn "Brak cache dla $appid"; return 1; }
        local before; before=$(human_size "$f")
        dxvk-cache-client merge "$f" "$f"
        local after; after=$(human_size "$f")
        log "Merge $appid: $before → $after"
    else
        find "$DXVK_CACHE" -name "*.dxvk-cache" | while read -r f; do
            local before; before=$(human_size "$f")
            dxvk-cache-client merge "$f" "$f" 2>/dev/null || continue
            local after; after=$(human_size "$f")
            log "$(basename "$f"): $before → $after"
        done
    fi
}

# ─── Wyczyść stare cache ──────────────────────────────────────────────────────
clean_cache() {
    local days="${1:-30}"
    info "Usuwam cache starszy niż $days dni..."

    local removed=0

    # DXVK
    find "$DXVK_CACHE" -name "*.dxvk-cache" -mtime "+$days" 2>/dev/null | while read -r f; do
        rm -f "$f"
        echo -e "  ${R}✖${NC}  Usunięto: $(basename "$f")"
        (( removed++ )) || true
    done

    # VKD3D
    find "$VKD3D_CACHE" -name "*.cache" -mtime "+$days" 2>/dev/null | while read -r f; do
        rm -f "$f"
        echo -e "  ${R}✖${NC}  Usunięto: $(basename "$f")"
    done

    log "Czyszczenie zakończone"
}

# ─── Wymuś rekompilację (usuń cache dla gry) ──────────────────────────────────
force_recompile() {
    local appid="$1"
    local f="$DXVK_CACHE/${appid}.dxvk-cache"

    if [[ -f "$f" ]]; then
        rm -f "$f"
        log "Usunięto DXVK cache dla $appid — gra skompiluje shadery od nowa"
    else
        warn "Brak DXVK cache dla $appid"
    fi

    # Steam shader cache
    local steam_cache="$STEAM_SHADER_CACHE/$appid"
    if [[ -d "$steam_cache" ]]; then
        read -rp "  Usunąć też Steam shader pre-cache dla $appid? [t/N] " ans
        if [[ "$ans" =~ ^[tTyY]$ ]]; then
            rm -rf "$steam_cache"
            log "Steam shader cache dla $appid usunięty"
        fi
    fi
}

# ─── Optymalizuj Mesa cache ───────────────────────────────────────────────────
optimize_mesa() {
    info "Optymalizuję Mesa shader cache..."

    # Mesa GL_CACHE_DIR
    local mesa_conf="${HOME}/.config/drirc"
    if [[ ! -f "$mesa_conf" ]]; then
        cat > "$mesa_conf" << 'DRI'
<driconf>
    <device>
        <application name="Default">
            <option name="allow_glsl_extension_directive_midshader" value="true" />
            <option name="glsl_correct_derivatives_after_discard" value="true" />
        </application>
    </device>
</driconf>
DRI
        log "Mesa drirc → $mesa_conf"
    fi

    # Zwiększ rozmiar Mesa cache
    local mesa_size_mb=4096
    local profile="${HOME}/.profile"
    if ! grep -q "MESA_SHADER_CACHE_MAX_SIZE" "$profile" 2>/dev/null; then
        echo "export MESA_SHADER_CACHE_MAX_SIZE=${mesa_size_mb}M" >> "$profile"
        log "MESA_SHADER_CACHE_MAX_SIZE=${mesa_size_mb}M → ~/.profile"
    fi

    export MESA_SHADER_CACHE_MAX_SIZE="${mesa_size_mb}M"
    log "Mesa cache limit: ${mesa_size_mb}MB"
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
banner
show_stats

echo -e "  Co zrobić?\n"
echo -e "  $(kbtn "1") 📊  Statystyki cache"
echo -e "  $(kbtn "2") ⚡  Pre-warm DXVK cache (wszystkie gry)"
echo -e "  $(kbtn "3") ⚡  Pre-warm DXVK cache (konkretna gra)"
echo -e "  $(kbtn "4") 🔄  Merge cache — usuń duplikaty"
echo -e "  $(kbtn "5") 📦  Eksportuj cache (backup/transfer na inny PC)"
echo -e "  $(kbtn "6") 📥  Importuj cache z archiwum"
echo -e "  $(kbtn "7") 🗑  Wyczyść stare cache (>30 dni)"
echo -e "  $(kbtn "8") 💥  Wymuś rekompilację dla gry (usuń cache)"
echo -e "  $(kbtn "9") 🟩  Optymalizuj Mesa shader cache"
echo -e "  $(kbtn "Q") ⏭  Wyjście"
echo
read -rp "  > " choice

case "$choice" in
    1) show_stats ;;
    2) prewarm_dxvk ;;
    3) read -rp "  AppID: " aid; prewarm_dxvk "$aid" ;;
    4)
        echo -e "  $(kbtn "A") Wszystkie  $(kbtn "1") Konkretna gra"
        read -rp "  > " m
        if [[ "$m" == "1" ]]; then
            read -rp "  AppID: " aid; merge_dxvk "$aid"
        else
            merge_dxvk
        fi
        ;;
    5)
        echo -e "  $(kbtn "A") Wszystkie  $(kbtn "1") Konkretna gra"
        read -rp "  > " m
        if [[ "$m" == "1" ]]; then
            read -rp "  AppID: " aid; export_cache "$aid"
        else
            export_cache "all"
        fi
        ;;
    6) read -rp "  Ścieżka do archiwum: " arc; import_cache "$arc" ;;
    7) read -rp "  Usuń cache starszy niż X dni [30]: " d; clean_cache "${d:-30}" ;;
    8) read -rp "  AppID: " aid; force_recompile "$aid" ;;
    9) optimize_mesa ;;
    [qQ]) exit 0 ;;
    *) echo "  Nieznana opcja" ;;
esac
