#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECK_DIR="$(dirname "$SCRIPT_DIR")"

# ─── Kolory ───────────────────────────────────────────────────────────────────
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
B='\033[1;34m'
C='\033[0;36m'
M='\033[0;35m'
W='\033[1;37m'
DIM='\033[2m'
NC='\033[0m'
BOLD='\033[1m'

# ─── Button renderer ──────────────────────────────────────────────────────────
# Użycie: btn "ENTER" lub btn "1" lub btn "ESC"
btn() {
    local key="$1"
    local color="${2:-$W}"
    echo -e "${DIM}╭─────╮${NC}"
    echo -e "${DIM}│${NC} ${color}${BOLD}$(printf '%-3s' "$key")${NC} ${DIM}│${NC}"
    echo -e "${DIM}╰─────╯${NC}"
}

# Inline button (jedna linia) — do użycia w tekście menu
ibtn() {
    local key="$1"
    local color="${2:-$Y}"
    echo -e "${DIM}╭╴${NC}${color}${BOLD}${key}${NC}${DIM}╶╮${NC} "
}

# Kompaktowy inline button
kbtn() {
    local key="$1"
    local color="${2:-$Y}"
    printf "${DIM}⌈${NC}${color}${BOLD} %s ${NC}${DIM}⌋${NC}" "$key"
}

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()    { echo -e "  ${G}✔${NC}  $*"; }
info()   { echo -e "  ${B}ℹ${NC}  $*"; }
warn()   { echo -e "  ${Y}⚠${NC}  $*"; }
err()    { echo -e "  ${R}✖${NC}  $*"; }
step()   { echo -e "\n  ${M}●${NC} ${BOLD}$*${NC}"; }
divider(){ echo -e "  ${DIM}────────────────────────────────────────────────────${NC}"; }

pause() {
    echo
    echo -e "  $(kbtn "ENTER") ${DIM}aby kontynuować...${NC}"
    read -r _
}

confirm() {
    local msg="$1"
    echo -e "\n  $msg"
    echo -e "  $(kbtn "T") ${G}Tak${NC}   $(kbtn "N") ${R}Nie${NC}"
    echo
    read -rp "  > " ans
    [[ "$ans" =~ ^[tTyY]$ ]]
}

# ─── Banner ───────────────────────────────────────────────────────────────────
banner() {
    clear
    echo
    echo -e "  ${B}╭──────────────────────────────────────────────────╮${NC}"
    echo -e "  ${B}│${NC}  ${BOLD}🎮  Steam Deck Setup${NC}                              ${B}│${NC}"
    echo -e "  ${B}│${NC}  ${DIM}github.com/Gucixdev/deck${NC}                          ${B}│${NC}"
    echo -e "  ${B}╰──────────────────────────────────────────────────╯${NC}"
    echo
}

# ─── Pasek postępu ────────────────────────────────────────────────────────────
progress() {
    local current=$1
    local total=$2
    local label="${3:-}"
    local width=40
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))
    local bar="${G}$(printf '█%.0s' $(seq 1 $filled))${DIM}$(printf '░%.0s' $(seq 1 $empty))${NC}"
    printf "  [%b] %d/%d %s\n" "$bar" "$current" "$total" "$label"
}

# ─── KROK 1: Sprawdź zależności ───────────────────────────────────────────────
check_deps() {
    banner
    step "Sprawdzam zależności"
    divider
    echo

    local missing=()
    local deps=(git curl python3 gcc make pkgconf)

    local i=0
    for dep in "${deps[@]}"; do
        (( i++ ))
        progress "$i" "${#deps[@]}" "$dep"
        if command -v "$dep" &>/dev/null; then
            echo -e "    ${G}✔${NC} $dep $(command -v "$dep")"
        else
            echo -e "    ${R}✖${NC} $dep — ${R}brak!${NC}"
            missing+=("$dep")
        fi
    done

    echo
    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Brak: ${missing[*]}"
        warn "Zainstaluj przez: sudo pacman -S ${missing[*]}"
        pause
        return 1
    fi

    log "Wszystkie zależności OK"
    pause
}

# ─── KROK 2: Steam API — pobierz gry ─────────────────────────────────────────
fetch_steam_games() {
    banner
    step "Steam API — pobieranie gier"
    divider
    echo

    local steam_env="$DECK_DIR/env/steam.env"
    source "$steam_env" 2>/dev/null || true

    if [[ -z "${STEAM_API_KEY:-}" || -z "${STEAM_ID:-}" ]]; then
        warn "Brak Steam credentials w env/steam.env"
        echo
        echo -e "  Pobierz klucz API: ${C}https://steamcommunity.com/dev/apikey${NC}"
        echo -e "  Steam ID:          ${C}https://steamidfinder.com${NC}"
        echo
        read -rp "  $(kbtn "STEAM_API_KEY") > " api_key
        read -rp "  $(kbtn "STEAM_ID    ") > " steam_id

        sed -i "s|^STEAM_API_KEY=.*|STEAM_API_KEY=\"$api_key\"|" "$steam_env"
        sed -i "s|^STEAM_ID=.*|STEAM_ID=\"$steam_id\"|"           "$steam_env"
        log "Zapisano credentials"
    else
        info "Steam ID: $STEAM_ID"
    fi

    echo
    if confirm "Pobrać/zaktualizować listę gier ze Steam?"; then
        bash "$DECK_DIR/bash/fetchgames.sh"
        log "games.conf i games.info zaktualizowane"
    else
        info "Pomijam pobieranie gier"
    fi

    pause
}

# ─── KROK 3: Przegląd profili gier ───────────────────────────────────────────
review_profiles() {
    banner
    step "Przegląd profili gier"
    divider
    echo

    local games_conf="$DECK_DIR/games.conf"
    local count_vanilla count_mod count_online count_total

    count_vanilla=$(grep -v "^#" "$games_conf" | grep ":vanilla$" | wc -l || echo 0)
    count_mod=$(grep -v "^#" "$games_conf"     | grep ":mod$"     | wc -l || echo 0)
    count_online=$(grep -v "^#" "$games_conf"  | grep ":online$"  | wc -l || echo 0)
    count_total=$(grep -v "^#\|^$" "$games_conf" | wc -l || echo 0)

    echo -e "  Łącznie gier: ${BOLD}$count_total${NC}"
    echo
    echo -e "  🎮 $(kbtn "vanilla") ${count_vanilla} gier — max wydajność"
    echo -e "  🛠  $(kbtn "mod    ") ${count_mod} gier — pełna kompatybilność z modami"
    echo -e "  🌐 $(kbtn "online ") ${count_online} gier — EAC/BattlEye compat"
    echo
    divider
    echo
    echo -e "  Możesz ręcznie edytować ${Y}games.conf${NC} żeby zmienić profil gry."
    echo -e "  Format: ${DIM}AppID:Nazwa:profil${NC}"
    echo
    echo -e "  $(kbtn "E") Otwórz games.conf w edytorze"
    echo -e "  $(kbtn "ENTER") Kontynuuj"
    echo
    read -rp "  > " choice

    if [[ "$choice" =~ ^[eE]$ ]]; then
        "${EDITOR:-nano}" "$games_conf"
    fi
}

# ─── KROK 4: Build ProtonTKG ──────────────────────────────────────────────────
build_proton() {
    banner
    step "ProtonTKG Builder"
    divider
    echo

    echo -e "  Wybierz co zbudować:\n"
    echo -e "  $(kbtn "1") 🎮 vanilla  — baza, max wydajność pod sprzęt"
    echo -e "  $(kbtn "2") 🛠  mod      — bez EAC/BattlEye, dla modów"
    echo -e "  $(kbtn "3") 🌐 online   — EAC + BattlEye compat"
    echo -e "  $(kbtn "4") 🔥 Wszystkie trzy"
    echo -e "  $(kbtn "5") ⚙️  Tylko wygeneruj cfg (bez budowania)"
    echo -e "  $(kbtn "S") ⏭  Pomiń"
    echo
    read -rp "  > " choice

    case "$choice" in
        [sS]) info "Pomijam build Protona" ;;
        *)    bash "$DECK_DIR/bash/buildproton.sh" <<< "$choice" ;;
    esac

    pause
}

# ─── KROK 5: Ustaw Launch Options ─────────────────────────────────────────────
set_launch_options() {
    banner
    step "Steam Launch Options"
    divider
    echo

    if pgrep -x "steam" &>/dev/null; then
        warn "Steam jest uruchomiony!"
        echo -e "  Zamknij Steam żeby kontynuować."
        echo
        echo -e "  $(kbtn "ENTER") po zamknięciu Steama   $(kbtn "S") pomiń"
        read -rp "  > " ans
        [[ "$ans" =~ ^[sS]$ ]] && return
        if pgrep -x "steam" &>/dev/null; then
            err "Steam nadal działa — pomijam"
            pause
            return
        fi
    fi

    info "Wpisuję launch options do Steam VDF..."
    bash "$DECK_DIR/bash/setlaunch.sh"
    log "Launch options ustawione"
    pause
}

# ─── KROK 6: Przegląd per-gra overrides ──────────────────────────────────────
review_overrides() {
    banner
    step "Per-gra overrides — cutsceny i audio"
    divider
    echo

    echo -e "  Plik: ${Y}env/game_overrides.conf${NC}"
    echo
    echo -e "  Najważniejsze overrides:"
    echo
    echo -e "  ${C}Cutsceny (mfplat):${NC}"
    echo -e "  ${DIM}AppID:PROTON_ENABLE_MFPLAT=1${NC}"
    echo
    echo -e "  ${C}Stare filmy (Bink video):${NC}"
    echo -e "  ${DIM}AppID:WINEDLLOVERRIDES=binkw32=n,b${NC}"
    echo
    echo -e "  ${C}Audio (XAudio2 crash):${NC}"
    echo -e "  ${DIM}AppID:WINEDLLOVERRIDES=xaudio2_7=n,b${NC}"
    echo
    echo -e "  ${C}Crackling audio (PulseAudio):${NC}"
    echo -e "  ${DIM}AppID:PULSE_LATENCY_MSEC=60${NC}"
    echo
    divider
    echo
    echo -e "  $(kbtn "E") Edytuj game_overrides.conf"
    echo -e "  $(kbtn "ENTER") Kontynuuj"
    echo
    read -rp "  > " choice
    [[ "$choice" =~ ^[eE]$ ]] && "${EDITOR:-nano}" "$DECK_DIR/env/game_overrides.conf"
}

# ─── KROK 7: Fix cutscen ─────────────────────────────────────────────────────
fix_cutscenes_step() {
    banner
    step "Fix cutscen — kodeki i DLL"
    divider
    echo

    echo -e "  Instaluje kodeki do Wine prefix per-gra:"
    echo -e "  ${DIM}Media Foundation, DirectShow, WMP, LAV Filters, XAudio2${NC}"
    echo
    echo -e "  $(kbtn "E") Uruchom fixcutscenes.sh teraz"
    echo -e "  $(kbtn "ENTER") Pomiń"
    echo
    read -rp "  > " choice
    [[ "$choice" =~ ^[eE]$ ]] && bash "$DECK_DIR/bash/fixcutscenes.sh"
}

# ─── KROK 8: shadPS4 ─────────────────────────────────────────────────────────
setup_shadps4() {
    banner
    step "shadPS4 — PS4 Emulator"
    divider
    echo

    local bin="$DECK_DIR/build/shadps4/build/shadps4"
    if [[ -f "$bin" ]]; then
        local ver; ver=$("$bin" --version 2>/dev/null | head -1 || echo "?")
        log "shadPS4 zbudowany: $ver"
    else
        warn "shadPS4 nie zbudowany"
        echo -e "  $(kbtn "B") Zbuduj teraz   $(kbtn "ENTER") Pomiń"
        read -rp "  > " ans
        [[ "$ans" =~ ^[bB]$ ]] && bash "$DECK_DIR/bash/buildshadps4.sh"
    fi

    echo
    echo -e "  $(kbtn "E") Edytuj env/ps4games.conf"
    echo -e "  $(kbtn "L") Uruchom runps4 (launcher)"
    echo -e "  $(kbtn "ENTER") Kontynuuj"
    echo
    read -rp "  > " choice
    case "$choice" in
        [eE]) "${EDITOR:-nano}" "$DECK_DIR/env/ps4games.conf" ;;
        [lL]) bash "$DECK_DIR/bash/runps4.sh" ;;
    esac
}

# ─── KROK 9: SSH Remote ───────────────────────────────────────────────────────
setup_ssh() {
    banner
    step "SSH Remote"
    divider
    echo

    local hosts_conf="$DECK_DIR/env/hosts.conf"

    echo -e "  Plik hostów: ${Y}env/hosts.conf${NC}"
    echo -e "  Format: ${DIM}Nazwa:user@adres_lub_IP${NC}"
    echo

    local count
    count=$(grep -v "^#\|^$" "$hosts_conf" 2>/dev/null | wc -l || echo 0)
    info "Zapisanych hostów: $count"
    echo
    echo -e "  $(kbtn "E") Edytuj hosts.conf"
    echo -e "  $(kbtn "C") Uruchom sshremote.sh teraz"
    echo -e "  $(kbtn "ENTER") Kontynuuj"
    echo
    read -rp "  > " choice
    case "$choice" in
        [eE]) "${EDITOR:-nano}" "$hosts_conf" ;;
        [cC]) bash "$DECK_DIR/bash/sshremote.sh" ;;
    esac
}

# ─── Podsumowanie ─────────────────────────────────────────────────────────────
summary() {
    banner
    step "Podsumowanie"
    divider
    echo

    local games_count compat_count
    games_count=$(grep -v "^#\|^$" "$DECK_DIR/games.conf" 2>/dev/null | wc -l || echo 0)
    compat_count=$(ls -d "${HOME}/.steam/steam/compatibilitytools.d/proton-deck-"* 2>/dev/null | wc -l || echo 0)

    echo -e "  🎮 Gier w games.conf:     ${BOLD}$games_count${NC}"
    echo -e "  ⚙️  Proton builds:          ${BOLD}$compat_count${NC}"
    echo
    echo -e "  ${G}✔${NC}  run.sh wpisany jako Launch Options"
    echo -e "  ${G}✔${NC}  Per-gra overrides: ${Y}env/game_overrides.conf${NC}"
    echo
    divider
    echo
    echo -e "  ${BOLD}Gotowe! 🚀${NC}"
    echo -e "  Uruchom Steam — powinien wykryć nowe wersje Protona."
    echo
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
banner
echo -e "  Witaj w ${BOLD}Steam Deck Setup Wizard${NC}"
echo
echo -e "  Ten skrypt przeprowadzi Cię przez:"
echo -e "   $(kbtn "1") Sprawdzenie zależności"
echo -e "   $(kbtn "2") Pobranie gier ze Steam API"
echo -e "   $(kbtn "3") Ustawienie profili gier"
echo -e "   $(kbtn "4") Build ProtonTKG"
echo -e "   $(kbtn "5") Ustawienie Launch Options w Steam"
echo -e "   $(kbtn "6") Per-gra overrides (cutsceny/audio)"
echo -e "   $(kbtn "7") Fix cutscen — kodeki do Wine prefix"
echo -e "   $(kbtn "8") shadPS4 — PS4 emulator"
echo -e "   $(kbtn "9") SSH Remote"
echo
echo -e "  $(kbtn "ENTER") Start   $(kbtn "Q") Wyjście"
echo
read -rp "  > " ans
[[ "$ans" =~ ^[qQ]$ ]] && exit 0

check_deps
fetch_steam_games
review_profiles
build_proton
set_launch_options
review_overrides
fix_cutscenes_step
setup_shadps4
setup_ssh
summary
