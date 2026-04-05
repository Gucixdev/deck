#!/usr/bin/env bash
set -euo pipefail

# fixcutscenes.sh — kompleksowy fix cutscen dla gier Wine/Proton
#
# Użycie:
#   ./fixcutscenes.sh              # interaktywny wybór gry
#   ./fixcutscenes.sh <AppID>      # bezpośrednio dla AppID
#   ./fixcutscenes.sh <AppID> auto # bez pytań, zainstaluj wszystko

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECK_DIR="$(dirname "$SCRIPT_DIR")"
GAMES_CONF="$DECK_DIR/games.conf"
OVERRIDES_CONF="$DECK_DIR/env/game_overrides.conf"
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
    echo -e "  ${B}│${NC}  ${BOLD}🎬  Fix Cutscenes — Wine/Proton Codec Installer${NC}  ${B}│${NC}"
    echo -e "  ${B}╰──────────────────────────────────────────────────╯${NC}"
    echo
}

# ─── Sprawdź winetricks ───────────────────────────────────────────────────────
check_winetricks() {
    if ! command -v winetricks &>/dev/null; then
        warn "winetricks nie zainstalowany."
        echo -e "  Instaluję winetricks..."
        if command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm winetricks
        elif command -v apt &>/dev/null; then
            sudo apt install -y winetricks
        else
            # Pobierz bezpośrednio
            local wt_path="/usr/local/bin/winetricks"
            sudo curl -fsSL https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
                -o "$wt_path"
            sudo chmod +x "$wt_path"
        fi
        log "winetricks zainstalowany"
    fi
}

# ─── Znajdź Wine prefix dla AppID ────────────────────────────────────────────
find_prefix() {
    local appid="$1"
    local prefix="$COMPATDATA/$appid/pfx"

    if [[ ! -d "$prefix" ]]; then
        warn "Prefix nie istnieje: $prefix"
        warn "Uruchom grę raz przez Steam żeby Steam stworzył prefix, potem wróć tutaj."
        return 1
    fi

    echo "$prefix"
}

# ─── Znajdź proton dla AppID ─────────────────────────────────────────────────
find_proton_wine() {
    local appid="$1"

    # Sprawdź nasz custom build
    local compat_dir="${HOME}/.steam/steam/compatibilitytools.d"
    for dir in "$compat_dir"/proton-deck-*; do
        if [[ -f "$dir/proton" ]]; then
            # Znajdź wine w dist/bin
            local wine
            wine=$(find "$dir" -name "wine" -type f 2>/dev/null | head -1 || true)
            [[ -n "$wine" ]] && echo "$wine" && return
        fi
    done

    # Fallback — systemowe wine
    command -v wine 2>/dev/null || echo ""
}

# ─── Uruchom winetricks w prefixie gry ───────────────────────────────────────
run_winetricks() {
    local prefix="$1"
    shift
    local components=("$@")

    local wine_bin
    wine_bin=$(find_proton_wine "")

    if [[ -z "$wine_bin" ]]; then
        warn "Nie znaleziono wine — winetricks użyje systemowego"
        WINEPREFIX="$prefix" winetricks "${components[@]}"
    else
        local wine_dir
        wine_dir=$(dirname "$wine_bin")
        WINEPREFIX="$prefix" PATH="$wine_dir:$PATH" winetricks "${components[@]}"
    fi
}

# ─── Profile komponentów per-typ cutscen ─────────────────────────────────────

# Media Foundation — nowoczesne gry (.mp4, .mov, .wmv przez MF API)
install_mf() {
    local prefix="$1"
    info "Instaluję Media Foundation (mfplat, mf, mfreadwrite)..."
    run_winetricks "$prefix" mf
    log "Media Foundation zainstalowane"
}

# DirectShow + kodeki — stare gry (.avi, .mpg, cinepak, indeo)
install_directshow() {
    local prefix="$1"
    info "Instaluję DirectShow i kodeki..."
    run_winetricks "$prefix" quartz devenum cinepak xvid
    log "DirectShow zainstalowany"
}

# Windows Media Player — gry które bezpośrednio wywołują WMP
install_wmp() {
    local prefix="$1"
    info "Instaluję Windows Media Player 11..."
    run_winetricks "$prefix" wmp11
    log "WMP11 zainstalowany"
}

# LAV Filters — nowoczesny DirectShow filter, zastępuje stare kodeki
install_lav() {
    local prefix="$1"
    info "Instaluję LAV Filters..."
    run_winetricks "$prefix" lavfilters
    log "LAV Filters zainstalowane"
}

# XAudio2 — fix audio w cutscenach
install_xaudio() {
    local prefix="$1"
    info "Instaluję XAudio2..."
    run_winetricks "$prefix" xact
    log "XAudio2/XACT zainstalowany"
}

# ─── Zaktualizuj game_overrides.conf ─────────────────────────────────────────
add_override() {
    local appid="$1"
    local key="$2"
    local val="$3"

    # Sprawdź czy już istnieje
    if grep -q "^${appid}:${key}=" "$OVERRIDES_CONF" 2>/dev/null; then
        # Zaktualizuj
        sed -i "s|^${appid}:${key}=.*|${appid}:${key}=${val}|" "$OVERRIDES_CONF"
        log "Override zaktualizowany: $appid:$key=$val"
    else
        echo "${appid}:${key}=${val}" >> "$OVERRIDES_CONF"
        log "Override dodany: $appid:$key=$val"
    fi
}

add_dll_override() {
    local appid="$1"
    local dll="$2"

    local current
    current=$(grep "^${appid}:WINEDLLOVERRIDES=" "$OVERRIDES_CONF" 2>/dev/null | cut -d= -f2- || echo "")

    if [[ -z "$current" ]]; then
        add_override "$appid" "WINEDLLOVERRIDES" "$dll"
    elif echo "$current" | grep -q "$dll"; then
        info "DLL override $dll już istnieje dla $appid"
    else
        sed -i "s|^${appid}:WINEDLLOVERRIDES=.*|${appid}:WINEDLLOVERRIDES=${current};${dll}|" "$OVERRIDES_CONF"
        log "DLL override dodany: $dll dla $appid"
    fi
}

# ─── Znane profile per-gra ────────────────────────────────────────────────────
# Zwraca opis i listę komponentów do zainstalowania
game_profile() {
    local appid="$1"

    case "$appid" in
        4800) # Heroes of Annihilated Empires
            GAME_NAME="Heroes of Annihilated Empires"
            GAME_DESC="DirectX 8 (2006), Bink video, Miles Sound System"
            COMPONENTS=(directshow wmp lav)
            DLL_OVERRIDES=("binkw32=n,b" "mss32=n,b" "d3d8=n,b")
            ENV_OVERRIDES=("PROTON_USE_WINED3D=1" "PROTON_ENABLE_MFPLAT=1" "PULSE_LATENCY_MSEC=60" "WINE_LARGE_ADDRESS_AWARE=1")
            ;;
        223470|360960) # Postal 2
            GAME_NAME="Postal 2"
            GAME_DESC="Unreal Engine 2 (2003), Bink video, Miles Sound System"
            COMPONENTS=(directshow lav xaudio)
            DLL_OVERRIDES=("mss32=n,b" "binkw32=n,b")
            ENV_OVERRIDES=("PROTON_ENABLE_MFPLAT=1" "PULSE_LATENCY_MSEC=60" "WINE_LARGE_ADDRESS_AWARE=1")
            ;;
        *)
            GAME_NAME="Nieznana gra ($appid)"
            GAME_DESC=""
            COMPONENTS=()
            DLL_OVERRIDES=()
            ENV_OVERRIDES=()
            ;;
    esac
}

# ─── Interaktywny wybór komponentów ──────────────────────────────────────────
choose_components() {
    echo -e "  Wybierz co zainstalować:\n"
    echo -e "  $(kbtn "1") 🎞️  Media Foundation    — nowoczesne gry (.mp4, .wmv)"
    echo -e "  $(kbtn "2") 📽️  DirectShow + kodeki  — stare gry (.avi, cinepak, indeo)"
    echo -e "  $(kbtn "3") 📺  Windows Media Player — gry używające WMP bezpośrednio"
    echo -e "  $(kbtn "4") 🎬  LAV Filters          — nowoczesny DirectShow filter (zalecane)"
    echo -e "  $(kbtn "5") 🔊  XAudio2/XACT         — audio w cutscenach"
    echo -e "  $(kbtn "A") ✨  Wszystko             — pełny stack (najlepsza kompatybilność)"
    echo -e "  $(kbtn "Q") ⏭️  Wyjście"
    echo
    echo -e "  Wpisz numery rozdzielone spacją, np: ${DIM}1 2 4${NC}"
    echo
    read -rp "  > " raw

    CHOSEN_COMPONENTS=()

    if [[ "$raw" =~ ^[aA]$ ]]; then
        CHOSEN_COMPONENTS=(mf directshow wmp lav xaudio)
        return
    fi

    for token in $raw; do
        case "$token" in
            1) CHOSEN_COMPONENTS+=(mf) ;;
            2) CHOSEN_COMPONENTS+=(directshow) ;;
            3) CHOSEN_COMPONENTS+=(wmp) ;;
            4) CHOSEN_COMPONENTS+=(lav) ;;
            5) CHOSEN_COMPONENTS+=(xaudio) ;;
        esac
    done
}

# ─── Główna instalacja ────────────────────────────────────────────────────────
install_for_game() {
    local appid="$1"
    local auto="${2:-}"

    game_profile "$appid"

    echo -e "  ${C}── Gra ──────────────────────────────────────────────${NC}"
    echo -e "  AppID:  ${BOLD}$appid${NC}"
    echo -e "  Nazwa:  ${BOLD}$GAME_NAME${NC}"
    [[ -n "$GAME_DESC" ]] && echo -e "  Info:   ${DIM}$GAME_DESC${NC}"
    echo -e "  ${C}────────────────────────────────────────────────────${NC}"
    echo

    local prefix
    prefix=$(find_prefix "$appid") || return 1

    info "Prefix: $prefix"
    echo

    # Wybierz komponenty
    local to_install=()
    if [[ "$auto" == "auto" && ${#COMPONENTS[@]} -gt 0 ]]; then
        to_install=("${COMPONENTS[@]}")
        info "Auto-profil: ${COMPONENTS[*]}"
    elif [[ "$auto" == "auto" ]]; then
        to_install=(mf directshow lav)
        info "Brak profilu — instaluję domyślnie: mf directshow lav"
    else
        if [[ ${#COMPONENTS[@]} -gt 0 ]]; then
            echo -e "  Zalecany profil dla tej gry: ${Y}${COMPONENTS[*]}${NC}"
            echo -e "  $(kbtn "ENTER") Użyj zalecanego   $(kbtn "C") Wybierz ręcznie"
            echo
            read -rp "  > " ans
            if [[ "$ans" =~ ^[cC]$ ]]; then
                choose_components
                to_install=("${CHOSEN_COMPONENTS[@]}")
            else
                to_install=("${COMPONENTS[@]}")
            fi
        else
            choose_components
            to_install=("${CHOSEN_COMPONENTS[@]}")
        fi
    fi

    # Zainstaluj komponenty
    echo
    for comp in "${to_install[@]}"; do
        case "$comp" in
            mf)          install_mf          "$prefix" ;;
            directshow)  install_directshow  "$prefix" ;;
            wmp)         install_wmp         "$prefix" ;;
            lav)         install_lav         "$prefix" ;;
            xaudio)      install_xaudio      "$prefix" ;;
        esac
    done

    # Dodaj DLL overrides
    if [[ ${#DLL_OVERRIDES[@]} -gt 0 ]]; then
        echo
        info "Ustawiam DLL overrides..."
        for dll in "${DLL_OVERRIDES[@]}"; do
            add_dll_override "$appid" "$dll"
        done
    fi

    # Dodaj ENV overrides
    if [[ ${#ENV_OVERRIDES[@]} -gt 0 ]]; then
        info "Ustawiam env overrides..."
        for kv in "${ENV_OVERRIDES[@]}"; do
            local k="${kv%%=*}"
            local v="${kv#*=}"
            add_override "$appid" "$k" "$v"
        done
    fi

    echo
    log "Gotowe dla AppID $appid ($GAME_NAME)"
    echo -e "  ${DIM}Uruchom grę — cutsceny powinny działać.${NC}"
    echo -e "  ${DIM}Jeśli nadal nie działają, spróbuj opcję 'Wszystko' (A).${NC}"
    echo
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
banner
check_winetricks

APPID="${1:-}"
AUTO="${2:-}"

if [[ -z "$APPID" ]]; then
    # Interaktywny wybór
    echo -e "  Wpisz AppID gry lub wybierz z listy:\n"
    echo -e "  $(kbtn "4800  ") Heroes of Annihilated Empires"
    echo -e "  $(kbtn "223470") Postal 2"
    echo -e "  $(kbtn "360960") Postal 2: Paradise Lost"
    echo -e "  $(kbtn "inne  ") Wpisz dowolny AppID"
    echo
    read -rp "  AppID > " APPID
fi

[[ -z "$APPID" ]] && err "Nie podano AppID"
[[ ! "$APPID" =~ ^[0-9]+$ ]] && err "AppID musi być liczbą"

install_for_game "$APPID" "$AUTO"
