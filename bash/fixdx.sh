#!/usr/bin/env bash
set -euo pipefail

# fixdx.sh — DirectDraw / stary DX / dxvk.conf per-gra
# Dla gier DX6/DX7/DX8, DirectDraw, 3dfx/Glide, starych silników

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECK_DIR="$(dirname "$SCRIPT_DIR")"
OVERRIDES_CONF="$DECK_DIR/env/game_overrides.conf"
DXVK_CONF_DIR="$DECK_DIR/env/dxvk"
STEAMAPPS="${STEAM_ROOT:-$HOME/.steam/steam}/steamapps"
COMPATDATA="$STEAMAPPS/compatdata"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[1;34m'; C='\033[0;36m'; DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "  ${G}✔${NC}  $*"; }
info() { echo -e "  ${B}ℹ${NC}  $*"; }
warn() { echo -e "  ${Y}⚠${NC}  $*"; }
err()  { echo -e "  ${R}✖${NC}  $*"; exit 1; }
kbtn() { printf "${DIM}⌈${NC}${Y}${BOLD} %s ${NC}${DIM}⌋${NC}" "$1"; }

banner() {
    echo
    echo -e "  ${B}╭──────────────────────────────────────────────────╮${NC}"
    echo -e "  ${B}│${NC}  ${BOLD}🎲  FixDX — DirectX Legacy & DXVK Config${NC}          ${B}│${NC}"
    echo -e "  ${B}╰──────────────────────────────────────────────────╯${NC}"
    echo
}

find_prefix() {
    local appid="$1"
    local p="$COMPATDATA/$appid/pfx"
    [[ -d "$p" ]] && echo "$p" && return
    warn "Prefix nie istnieje: $p — uruchom grę raz przez Steam"
    return 1
}

add_override() {
    local appid="$1" key="$2" val="$3"
    if grep -q "^${appid}:${key}=" "$OVERRIDES_CONF" 2>/dev/null; then
        sed -i "s|^${appid}:${key}=.*|${appid}:${key}=${val}|" "$OVERRIDES_CONF"
    else
        echo "${appid}:${key}=${val}" >> "$OVERRIDES_CONF"
    fi
    log "Override: $appid:$key=$val"
}

add_dll() {
    local appid="$1" dll="$2"
    local current
    current=$(grep "^${appid}:WINEDLLOVERRIDES=" "$OVERRIDES_CONF" 2>/dev/null | cut -d= -f2- || echo "")
    if [[ -z "$current" ]]; then
        add_override "$appid" "WINEDLLOVERRIDES" "$dll"
    elif ! echo "$current" | grep -q "${dll%%=*}"; then
        sed -i "s|^${appid}:WINEDLLOVERRIDES=.*|${appid}:WINEDLLOVERRIDES=${current};${dll}|" "$OVERRIDES_CONF"
        log "DLL: $dll"
    fi
}

# ─── dxvk.conf per-gra ────────────────────────────────────────────────────────
generate_dxvk_conf() {
    local appid="$1"
    local preset="${2:-default}"

    mkdir -p "$DXVK_CONF_DIR"
    local conf="$DXVK_CONF_DIR/${appid}.conf"

    info "Generuję dxvk.conf dla AppID $appid (preset: $preset)..."

    case "$preset" in
        default)
            cat > "$conf" << CONF
# dxvk.conf — AppID: $appid
# Wygenerowany przez fixdx.sh

# Async shader compilation (mniej stutterów przy pierwszym uruchomieniu)
dxvk.enableAsync = True

# Present mode — mailbox zmniejsza latency vs vsync
dxvk.presentMode = auto

# Limit buforowanych klatek (mniej input lag)
dxvk.numBackBuffers = 2

# State cache
dxvk.enableStateCache = True
CONF
            ;;
        old_game)
            cat > "$conf" << CONF
# dxvk.conf — AppID: $appid (stara gra DX8/DX9)

# Stare gry często mają problemy z nowymi feature levels
dxvk.maxFeatureLevel = d3d9

# Async — stare gry mają mało shaderów, async wystarczy
dxvk.enableAsync = True

# Wyłącz niektóre rozszerzenia które crashują stare gry
dxvk.enableRtxgi = False

# Bufor — stare gry nie lubią >2
dxvk.numBackBuffers = 2

dxvk.enableStateCache = True
CONF
            ;;
        performance)
            cat > "$conf" << CONF
# dxvk.conf — AppID: $appid (performance max)

dxvk.enableAsync = True
dxvk.presentMode = mailbox
dxvk.numBackBuffers = 2
dxvk.enableStateCache = True

# Agresywne optymalizacje
dxvk.shrinkNvidiaHvvHeap = False
dxvk.useRawSsbo = True
CONF
            ;;
        compatibility)
            cat > "$conf" << CONF
# dxvk.conf — AppID: $appid (max kompatybilność)

# Wyłącz async — może powodować glitche w niektórych grach
dxvk.enableAsync = False

# Prezentacja synchroniczna
dxvk.presentMode = fifo

dxvk.numBackBuffers = 3
dxvk.enableStateCache = True

# Fallback dla problematycznych gier
dxvk.maxFeatureLevel = d3d11_0
CONF
            ;;
    esac

    log "dxvk.conf → $conf"
    add_override "$appid" "DXVK_CONFIG_FILE" "$conf"
}

# ─── DirectDraw (DX1-DX7) ────────────────────────────────────────────────────
fix_directdraw() {
    local prefix="$1" appid="$2"
    info "Fixing DirectDraw (DX1-DX7)..."

    # ddraw.dll — Wine ma własny ale często jest buggy dla starych gier
    # Użyj ddraw z DXVK (dxvk-legacy)
    WINEPREFIX="$prefix" wine reg add \
        "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" \
        /v "ddraw" /t REG_SZ /d "native,builtin" /f 2>/dev/null || true

    add_dll "$appid" "ddraw=n,b"

    # Wymuś 16-bit color depth dla starych gier
    WINEPREFIX="$prefix" wine reg add \
        "HKEY_CURRENT_USER\\Software\\Wine\\Direct3D" \
        /v "DirectDrawRenderer" /t REG_SZ /d "opengl" /f 2>/dev/null || true

    # Wyłącz emulację wirtualnego pulpitu (powoduje problemy z pełnym ekranem)
    WINEPREFIX="$prefix" wine reg add \
        "HKEY_CURRENT_USER\\Software\\Wine\\Explorer\\Desktops" \
        /v "Default" /t REG_SZ /d "" /f 2>/dev/null || true

    add_override "$appid" "PROTON_USE_WINED3D" "1"
    log "DirectDraw fixes zastosowane"
}

# ─── DX9 z wineD3D (fallback jeśli DXVK ma problemy) ────────────────────────
fix_wined3d_dx9() {
    local prefix="$1" appid="$2"
    info "Switching DX9 → wineD3D (software renderer)..."
    add_dll "$appid" "d3d9=n,b"
    add_override "$appid" "PROTON_USE_WINED3D" "1"
    log "wineD3D DX9 aktywny"
}

# ─── dgVoodoo2 — 3dfx Glide / DX1-DX7 na Vulkan ─────────────────────────────
install_dgvoodoo() {
    local prefix="$1" appid="$2"
    info "Instaluję dgVoodoo2 (3dfx/Glide → Vulkan)..."

    local dgv_dir="$DECK_DIR/build/dgvoodoo2"
    local dgv_ver="2.8.3"
    local dgv_url="https://github.com/dege-diosg/dgVoodoo2/releases/download/v${dgv_ver}/dgVoodoo2_${dgv_ver/./_}.zip"

    mkdir -p "$dgv_dir"

    if [[ ! -f "$dgv_dir/dgVoodoo2.zip" ]]; then
        info "Pobieranie dgVoodoo2 ${dgv_ver}..."
        curl -fsSL "$dgv_url" -o "$dgv_dir/dgVoodoo2.zip" || {
            warn "Nie udało się pobrać dgVoodoo2. Pobierz ręcznie z: https://github.com/dege-diosg/dgVoodoo2"
            return 1
        }
        cd "$dgv_dir" && unzip -q "dgVoodoo2.zip" && cd -
    fi

    # Skopiuj DLL do systemu Wine
    local game_dir
    game_dir=$(find "$STEAMAPPS/common" -maxdepth 2 -name "*.exe" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")

    if [[ -z "$game_dir" ]]; then
        warn "Nie znaleziono katalogu gry — skopiuj ręcznie z $dgv_dir/MS/x86/ do katalogu gry"
    else
        cp "$dgv_dir/MS/x86/D3D8.dll"   "$game_dir/" 2>/dev/null || true
        cp "$dgv_dir/MS/x86/D3D9.dll"   "$game_dir/" 2>/dev/null || true
        cp "$dgv_dir/MS/x86/DDraw.dll"  "$game_dir/" 2>/dev/null || true
        cp "$dgv_dir/MS/x86/Glide.dll"  "$game_dir/" 2>/dev/null || true
        cp "$dgv_dir/MS/x86/Glide2x.dll" "$game_dir/" 2>/dev/null || true
        cp "$dgv_dir/MS/x86/Glide3x.dll" "$game_dir/" 2>/dev/null || true
        cp "$dgv_dir/dgVoodoo.conf"      "$game_dir/" 2>/dev/null || true
        log "dgVoodoo2 skopiowany do $game_dir"
    fi

    add_dll "$appid" "ddraw=n,b"
    add_dll "$appid" "d3d8=n,b"
    log "dgVoodoo2 skonfigurowany"
}

# ─── OpenGL legacy fix ────────────────────────────────────────────────────────
fix_opengl() {
    local prefix="$1" appid="$2"
    info "OpenGL legacy fixes..."

    WINEPREFIX="$prefix" wine reg add \
        "HKEY_CURRENT_USER\\Software\\Wine\\Direct3D" \
        /v "renderer" /t REG_SZ /d "opengl" /f 2>/dev/null || true

    WINEPREFIX="$prefix" wine reg add \
        "HKEY_CURRENT_USER\\Software\\Wine\\Direct3D" \
        /v "UseGLSL" /t REG_SZ /d "enabled" /f 2>/dev/null || true

    add_dll "$appid" "opengl32=n,b"
    log "OpenGL legacy fixes zastosowane"
}

# ─── Resize window / virtual desktop ─────────────────────────────────────────
fix_virtual_desktop() {
    local prefix="$1" appid="$2" res="${3:-1920x1080}"
    info "Ustawiam wirtualny pulpit $res..."
    WINEPREFIX="$prefix" wine reg add \
        "HKEY_CURRENT_USER\\Software\\Wine\\Explorer" \
        /v "Desktop" /t REG_SZ /d "Default" /f 2>/dev/null || true
    WINEPREFIX="$prefix" wine reg add \
        "HKEY_CURRENT_USER\\Software\\Wine\\Explorer\\Desktops" \
        /v "Default" /t REG_SZ /d "$res" /f 2>/dev/null || true
    log "Wirtualny pulpit $res"
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
banner

APPID="${1:-}"
if [[ -z "$APPID" ]]; then
    echo -e "  Wpisz AppID gry:\n"
    read -rp "  AppID > " APPID
fi
[[ ! "$APPID" =~ ^[0-9]+$ ]] && err "AppID musi być liczbą"

prefix=$(find_prefix "$APPID") || exit 1

echo
echo -e "  Co zrobić dla AppID ${BOLD}$APPID${NC}?\n"
echo -e "  $(kbtn "1") 🎲  dxvk.conf — domyślny (async, mailbox)"
echo -e "  $(kbtn "2") 🎲  dxvk.conf — stara gra DX8/DX9"
echo -e "  $(kbtn "3") 🎲  dxvk.conf — max performance"
echo -e "  $(kbtn "4") 🎲  dxvk.conf — max kompatybilność"
echo -e "  $(kbtn "5") 🖼  DirectDraw fix (DX1-DX7, stare gry)"
echo -e "  $(kbtn "6") 🔄  DX9 → wineD3D (fallback gdy DXVK ma problemy)"
echo -e "  $(kbtn "7") 🟣  dgVoodoo2 (3dfx Glide / DX1-DX7 → Vulkan)"
echo -e "  $(kbtn "8") 🟩  OpenGL legacy"
echo -e "  $(kbtn "9") 🖥  Wirtualny pulpit (fullscreen fix)"
echo -e "  $(kbtn "A") ✨  Pełny fix dla starych gier (5+6+1)"
echo
read -rp "  > " choice

case "$choice" in
    1) generate_dxvk_conf "$APPID" "default" ;;
    2) generate_dxvk_conf "$APPID" "old_game" ;;
    3) generate_dxvk_conf "$APPID" "performance" ;;
    4) generate_dxvk_conf "$APPID" "compatibility" ;;
    5) fix_directdraw "$prefix" "$APPID" ;;
    6) fix_wined3d_dx9 "$prefix" "$APPID" ;;
    7) install_dgvoodoo "$prefix" "$APPID" ;;
    8) fix_opengl "$prefix" "$APPID" ;;
    9)
        read -rp "  Rozdzielczość [1920x1080]: " res
        fix_virtual_desktop "$prefix" "$APPID" "${res:-1920x1080}"
        ;;
    [aA])
        fix_directdraw "$prefix" "$APPID"
        fix_wined3d_dx9 "$prefix" "$APPID"
        generate_dxvk_conf "$APPID" "old_game"
        ;;
    *) err "Nieznana opcja" ;;
esac

echo
log "Gotowe dla AppID $APPID"
