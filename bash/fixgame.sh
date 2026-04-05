#!/usr/bin/env bash
set -euo pipefail

# fixgame.sh — per-gra runtime fixer (vcrun, dotnet, fonts, engine fixes)
#
# Użycie:
#   ./fixgame.sh              # interaktywny
#   ./fixgame.sh <AppID>      # dla konkretnej gry
#   ./fixgame.sh <AppID> auto # bez pytań, użyj profilu silnika

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
    echo -e "  ${B}│${NC}  ${BOLD}🎮  FixGame — Per-Game Runtime Installer${NC}          ${B}│${NC}"
    echo -e "  ${B}╰──────────────────────────────────────────────────╯${NC}"
    echo
}

check_winetricks() {
    if ! command -v winetricks &>/dev/null; then
        err "winetricks nie zainstalowany. Uruchom najpierw sysfix.sh lub: sudo pacman -S winetricks"
    fi
}

find_prefix() {
    local appid="$1"
    local prefix="$COMPATDATA/$appid/pfx"
    if [[ ! -d "$prefix" ]]; then
        warn "Prefix nie istnieje: $prefix"
        warn "Uruchom grę raz przez Steam żeby stworzył prefix, potem wróć tutaj."
        return 1
    fi
    echo "$prefix"
}

find_wine() {
    local compat_dir="${HOME}/.steam/steam/compatibilitytools.d"
    for dir in "$compat_dir"/proton-deck-*; do
        local wine
        wine=$(find "$dir" -name "wine" -type f 2>/dev/null | head -1 || true)
        [[ -n "$wine" ]] && echo "$wine" && return
    done
    command -v wine 2>/dev/null || echo ""
}

wt() {
    local prefix="$1"; shift
    local wine_bin; wine_bin=$(find_wine)
    if [[ -n "$wine_bin" ]]; then
        local wine_dir; wine_dir=$(dirname "$wine_bin")
        WINEPREFIX="$prefix" PATH="$wine_dir:$PATH" winetricks -q "$@"
    else
        WINEPREFIX="$prefix" winetricks -q "$@"
    fi
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
        log "DLL: $dll → $appid"
    else
        info "DLL $dll już ustawiony dla $appid"
    fi
}

# ─── Komponenty ───────────────────────────────────────────────────────────────

install_vcrun() {
    local prefix="$1"
    info "Instaluję Visual C++ Redistributables..."
    wt "$prefix" vcrun2022
    wt "$prefix" vcrun2019
    wt "$prefix" vcrun2017
    wt "$prefix" vcrun2015
    wt "$prefix" vcrun2013
    wt "$prefix" vcrun2010
    wt "$prefix" vcrun2008
    wt "$prefix" vcrun2005
    log "Visual C++ redist zainstalowane (2005-2022)"
}

install_dotnet() {
    local prefix="$1"
    local version="${2:-48}"
    info "Instaluję .NET $version..."
    case "$version" in
        48) wt "$prefix" dotnet48 ;;
        6)  wt "$prefix" dotnet6  ;;
        7)  wt "$prefix" dotnet7  ;;
        35) wt "$prefix" dotnet35 ;;
        20) wt "$prefix" dotnet20sp2 ;;
    esac
    log ".NET $version zainstalowane"
}

install_fonts() {
    local prefix="$1"
    info "Instaluję czcionki (corefonts + cleartype)..."
    wt "$prefix" corefonts
    wt "$prefix" tahoma
    wt "$prefix" consolas
    # CJK fonts jeśli potrzebne
    # wt "$prefix" cjkfonts
    log "Czcionki zainstalowane (Arial, Times, Verdana...)"
}

install_openal() {
    local prefix="$1"
    info "Instaluję OpenAL..."
    wt "$prefix" openal
    log "OpenAL zainstalowany"
}

install_directplay() {
    local prefix="$1"
    info "Instaluję DirectPlay (stare gry multiplayer)..."
    wt "$prefix" directplay
    log "DirectPlay zainstalowany"
}

install_physx() {
    local prefix="$1"
    info "Instaluję PhysX..."
    wt "$prefix" physx
    log "PhysX zainstalowany"
}

install_d3dx() {
    local prefix="$1"
    info "Instaluję DirectX components (d3dx9, d3dx10, d3dx11)..."
    wt "$prefix" d3dx9
    wt "$prefix" d3dx10
    wt "$prefix" d3dx11_43
    log "DirectX components zainstalowane"
}

install_xna() {
    local prefix="$1"
    info "Instaluję XNA Framework..."
    wt "$prefix" xna40
    log "XNA 4.0 zainstalowany"
}

# ─── Profile silników ─────────────────────────────────────────────────────────

profile_source_engine() {
    local prefix="$1" appid="$2"
    info "Source Engine profile..."
    wt "$prefix" vcrun2010 vcrun2013
    add_dll "$appid" "steam_api=n,b"
    add_override "$appid" "PROTON_LOG" "0"
    # Source engine crashuje z esync na niektórych grach
    add_override "$appid" "PROTON_NO_ESYNC" "0"
    log "Source Engine fixes zastosowane"
}

profile_ue4() {
    local prefix="$1" appid="$2"
    info "Unreal Engine 4 profile..."
    wt "$prefix" vcrun2022 vcrun2019
    # UE4 ma problemy z VKD3D na niektórych tytułach
    add_override "$appid" "PROTON_USE_WINED3D11" "0"
    add_override "$appid" "VKD3D_CONFIG" "dxr,upload_hvv"
    # Shader pre-compile
    add_override "$appid" "DXVK_ASYNC" "1"
    log "UE4 fixes zastosowane"
}

profile_ue5() {
    local prefix="$1" appid="$2"
    info "Unreal Engine 5 profile..."
    wt "$prefix" vcrun2022
    add_override "$appid" "VKD3D_CONFIG" "dxr,upload_hvv"
    add_override "$appid" "VKD3D_SHADER_MODEL" "6_6"
    add_override "$appid" "WINE_LARGE_ADDRESS_AWARE" "1"
    log "UE5 fixes zastosowane"
}

profile_unity() {
    local prefix="$1" appid="$2"
    info "Unity Engine profile..."
    wt "$prefix" vcrun2019 dotnet48
    # Unity IL2CPP często ma problemy z audio
    add_override "$appid" "PULSE_LATENCY_MSEC" "60"
    add_override "$appid" "PROTON_ENABLE_MFPLAT" "1"
    log "Unity fixes zastosowane"
}

profile_gamebryo() {
    local prefix="$1" appid="$2"
    info "GameBryo/Creation Engine profile (Bethesda)..."
    wt "$prefix" vcrun2010 vcrun2013 d3dx9
    add_dll "$appid" "xaudio2_7=n,b"
    add_override "$appid" "PROTON_ENABLE_MFPLAT" "1"
    add_override "$appid" "WINE_LARGE_ADDRESS_AWARE" "1"
    log "Creation Engine fixes zastosowane"
}

profile_old_dx8() {
    local prefix="$1" appid="$2"
    info "Old DX8/DX9 game profile..."
    wt "$prefix" vcrun2005 vcrun2008 d3dx9
    add_override "$appid" "PROTON_USE_WINED3D" "1"
    add_dll "$appid" "d3d8=n,b"
    add_dll "$appid" "ddraw=n,b"
    log "Old DX8 fixes zastosowane"
}

profile_32bit() {
    local prefix="$1" appid="$2"
    info "32-bit game profile..."
    add_override "$appid" "WINE_LARGE_ADDRESS_AWARE" "1"
    # Zwiększ wirtualny heap dla 32-bit gier
    add_override "$appid" "WINEDEBUG" "-all"
    add_dll "$appid" "msvcr120=n,b"
    log "32-bit game fixes zastosowane"
}

# ─── Profile per znane gry ────────────────────────────────────────────────────
game_profile() {
    local appid="$1"
    GAME_NAME="Nieznana gra ($appid)"
    GAME_ENGINE=""
    GAME_COMPONENTS=()

    case "$appid" in
        4800)   GAME_NAME="Heroes of Annihilated Empires"
                GAME_ENGINE="old_dx8"
                GAME_COMPONENTS=(vcrun fonts openal) ;;
        223470|360960)
                GAME_NAME="Postal 2"
                GAME_ENGINE="old_dx8"
                GAME_COMPONENTS=(vcrun fonts openal directplay) ;;
        570)    GAME_NAME="Dota 2"
                GAME_ENGINE="source"
                GAME_COMPONENTS=(vcrun) ;;
        730)    GAME_NAME="CS2"
                GAME_ENGINE="source"
                GAME_COMPONENTS=(vcrun) ;;
        440)    GAME_NAME="Team Fortress 2"
                GAME_ENGINE="source"
                GAME_COMPONENTS=(vcrun) ;;
        72850|489830|22380|22370)
                GAME_NAME="Bethesda/Creation Engine"
                GAME_ENGINE="gamebryo"
                GAME_COMPONENTS=(vcrun fonts d3dx) ;;
        1091500)GAME_NAME="Cyberpunk 2077"
                GAME_ENGINE="ue4"
                GAME_COMPONENTS=(vcrun) ;;
        292030) GAME_NAME="The Witcher 3"
                GAME_ENGINE=""
                GAME_COMPONENTS=(vcrun physx fonts) ;;
        1245620)GAME_NAME="Elden Ring"
                GAME_ENGINE="ue4"
                GAME_COMPONENTS=(vcrun) ;;
    esac
}

# ─── Instalacja ───────────────────────────────────────────────────────────────
install_for_game() {
    local appid="$1"
    local auto="${2:-}"

    game_profile "$appid"

    echo -e "  ${C}── Gra ──────────────────────────────────────────────${NC}"
    echo -e "  AppID:   ${BOLD}$appid${NC}  —  ${BOLD}$GAME_NAME${NC}"
    [[ -n "$GAME_ENGINE" ]] && echo -e "  Silnik:  ${Y}$GAME_ENGINE${NC}"
    echo -e "  ${C}────────────────────────────────────────────────────${NC}"
    echo

    local prefix
    prefix=$(find_prefix "$appid") || return 1
    info "Prefix: $prefix"
    echo

    # Wybór co zainstalować
    local chosen_comps=()
    local chosen_engine=""

    if [[ "$auto" == "auto" ]]; then
        chosen_comps=("${GAME_COMPONENTS[@]:-}")
        chosen_engine="$GAME_ENGINE"
    else
        echo -e "  ${BOLD}Komponenty:${NC}\n"
        echo -e "  $(kbtn "1") 📦  Visual C++ redist  2005-2022"
        echo -e "  $(kbtn "2") 🔷  .NET Framework     ${DIM}(wpisz wersję: 35/48/6/7)${NC}"
        echo -e "  $(kbtn "3") 🔤  Czcionki            ${DIM}(corefonts, tahoma, consolas)${NC}"
        echo -e "  $(kbtn "4") 🔊  OpenAL              ${DIM}(audio fix)${NC}"
        echo -e "  $(kbtn "5") 🌐  DirectPlay          ${DIM}(stare multiplayer)${NC}"
        echo -e "  $(kbtn "6") ⚡  PhysX               ${DIM}(NVIDIA physics)${NC}"
        echo -e "  $(kbtn "7") 🎮  DirectX d3dx9/10/11"
        echo -e "  $(kbtn "8") 🎯  XNA Framework       ${DIM}(indie gry)${NC}"
        echo
        echo -e "  ${BOLD}Profil silnika:${NC}\n"
        echo -e "  $(kbtn "S") Source Engine  $(kbtn "U") UE4  $(kbtn "5") UE5  $(kbtn "N") Unity"
        echo -e "  $(kbtn "B") Creation/Bethesda  $(kbtn "D") Stary DX8  $(kbtn "3") 32-bit"
        echo

        if [[ -n "$GAME_ENGINE" || ${#GAME_COMPONENTS[@]} -gt 0 ]]; then
            echo -e "  Zalecany profil: silnik=${Y}${GAME_ENGINE:-brak}${NC} komponenty=${Y}${GAME_COMPONENTS[*]:-brak}${NC}"
            echo -e "  $(kbtn "ENTER") Użyj zalecanego   $(kbtn "C") Wybierz ręcznie"
            echo
            read -rp "  > " ans
            if [[ ! "$ans" =~ ^[cC]$ ]]; then
                chosen_comps=("${GAME_COMPONENTS[@]:-}")
                chosen_engine="$GAME_ENGINE"
                # Pomiń do instalacji
                do_install "$appid" "$prefix" chosen_comps "$chosen_engine"
                return
            fi
        fi

        echo
        read -rp "  Komponenty (np: 1 3 4): " raw_comps
        read -rp "  Silnik (S/U/5/N/B/D/3 lub Enter): " raw_engine

        for token in $raw_comps; do
            case "$token" in
                1) chosen_comps+=(vcrun) ;;
                2) read -rp "  .NET wersja (35/48/6/7) [48]: " dotnet_ver
                   chosen_comps+=("dotnet:${dotnet_ver:-48}") ;;
                3) chosen_comps+=(fonts) ;;
                4) chosen_comps+=(openal) ;;
                5) chosen_comps+=(directplay) ;;
                6) chosen_comps+=(physx) ;;
                7) chosen_comps+=(d3dx) ;;
                8) chosen_comps+=(xna) ;;
            esac
        done

        case "$raw_engine" in
            [sS]) chosen_engine="source" ;;
            [uU]) chosen_engine="ue4" ;;
            5)    chosen_engine="ue5" ;;
            [nN]) chosen_engine="unity" ;;
            [bB]) chosen_engine="gamebryo" ;;
            [dD]) chosen_engine="old_dx8" ;;
            3)    chosen_engine="32bit" ;;
        esac
    fi

    do_install "$appid" "$prefix" chosen_comps "$chosen_engine"
}

do_install() {
    local appid="$1"
    local prefix="$2"
    local -n comps="$3"
    local engine="$4"

    echo

    # Komponenty
    for comp in "${comps[@]:-}"; do
        [[ -z "$comp" ]] && continue
        case "${comp%%:*}" in
            vcrun)      install_vcrun      "$prefix" ;;
            dotnet)     install_dotnet     "$prefix" "${comp#*:}" ;;
            fonts)      install_fonts      "$prefix" ;;
            openal)     install_openal     "$prefix" ;;
            directplay) install_directplay "$prefix" ;;
            physx)      install_physx      "$prefix" ;;
            d3dx)       install_d3dx       "$prefix" ;;
            xna)        install_xna        "$prefix" ;;
        esac
    done

    # Silnik
    case "$engine" in
        source)   profile_source_engine "$prefix" "$appid" ;;
        ue4)      profile_ue4           "$prefix" "$appid" ;;
        ue5)      profile_ue5           "$prefix" "$appid" ;;
        unity)    profile_unity         "$prefix" "$appid" ;;
        gamebryo) profile_gamebryo      "$prefix" "$appid" ;;
        old_dx8)  profile_old_dx8       "$prefix" "$appid" ;;
        32bit)    profile_32bit         "$prefix" "$appid" ;;
    esac

    echo
    log "Gotowe dla AppID $appid ($GAME_NAME)"
    echo -e "  ${DIM}Uruchom grę. Jeśli nadal są problemy, spróbuj dodatkowych komponentów.${NC}"
    echo
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
banner
check_winetricks

APPID="${1:-}"
AUTO="${2:-}"

if [[ -z "$APPID" ]]; then
    echo -e "  Wpisz AppID gry lub wybierz ze znanych:\n"
    echo -e "  $(kbtn "4800  ") Heroes of Annihilated Empires"
    echo -e "  $(kbtn "223470") Postal 2"
    echo -e "  $(kbtn "730   ") CS2"
    echo -e "  $(kbtn "1091500") Cyberpunk 2077"
    echo -e "  $(kbtn "1245620") Elden Ring"
    echo -e "  $(kbtn "inne  ") Wpisz AppID ręcznie"
    echo
    read -rp "  AppID > " APPID
fi

[[ -z "$APPID" ]] && err "Nie podano AppID"
[[ ! "$APPID" =~ ^[0-9]+$ ]] && err "AppID musi być liczbą"

install_for_game "$APPID" "$AUTO"
