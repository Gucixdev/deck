#!/usr/bin/env bash
set -euo pipefail

# sysfix.sh — systemowe fixy dla gamingu na Linuxie
# Krytyczne: bez tych ustawień duża część gier się nie odpala lub crasha

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[1;34m'; C='\033[0;36m'; DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "  ${G}✔${NC}  $*"; }
info() { echo -e "  ${B}ℹ${NC}  $*"; }
warn() { echo -e "  ${Y}⚠${NC}  $*"; }
err()  { echo -e "  ${R}✖${NC}  $*"; exit 1; }
kbtn() { printf "${DIM}⌈${NC}${Y}${BOLD} %s ${NC}${DIM}⌋${NC}" "$1"; }

banner() {
    echo
    echo -e "  ${B}╭──────────────────────────────────────────────────╮${NC}"
    echo -e "  ${B}│${NC}  ${BOLD}🔧  SysFix — System Gaming Optimizer${NC}             ${B}│${NC}"
    echo -e "  ${B}╰──────────────────────────────────────────────────╯${NC}"
    echo
}

need_root() {
    [[ $EUID -ne 0 ]] && SUDO="sudo" || SUDO=""
}

check_status() {
    echo -e "  ${C}── Aktualny stan ────────────────────────────────────${NC}"
    echo

    local nofile
    nofile=$(ulimit -n)
    local nofile_status="${R}✖ za niski (esync nie działa!)${NC}"
    [[ "$nofile" -ge 524288 ]] && nofile_status="${G}✔ OK${NC}"
    echo -e "  ulimit -n (file descriptors): ${BOLD}$nofile${NC}  $nofile_status"

    local inotify_watches
    inotify_watches=$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo "?")
    local inotify_status="${R}✖ za niski${NC}"
    [[ "$inotify_watches" -ge 524288 ]] 2>/dev/null && inotify_status="${G}✔ OK${NC}"
    echo -e "  inotify max_user_watches:     ${BOLD}$inotify_watches${NC}  $inotify_status"

    local vm_max
    vm_max=$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo "?")
    local vm_status="${R}✖ za niski${NC}"
    [[ "$vm_max" -ge 2147483642 ]] 2>/dev/null && vm_status="${G}✔ OK${NC}"
    echo -e "  vm.max_map_count:             ${BOLD}$vm_max${NC}  $vm_status"

    local pipewire_status="${R}✖ nie działa${NC}"
    pgrep -x pipewire &>/dev/null && pipewire_status="${G}✔ działa${NC}"
    echo -e "  PipeWire:                     $pipewire_status"

    local gamescope_status="${Y}brak${NC}"
    command -v gamescope &>/dev/null && gamescope_status="${G}✔ zainstalowany${NC}"
    echo -e "  Gamescope:                    $gamescope_status"

    local gamemode_status="${Y}brak${NC}"
    command -v gamemoded &>/dev/null && gamemode_status="${G}✔ zainstalowany${NC}"
    echo -e "  GameMode:                     $gamemode_status"

    local mangohud_status="${Y}brak${NC}"
    command -v mangohud &>/dev/null && mangohud_status="${G}✔ zainstalowany${NC}"
    echo -e "  MangoHud:                     $mangohud_status"

    echo -e "  ${C}────────────────────────────────────────────────────${NC}"
    echo
}

# ─── 1. File descriptor limits (esync) ───────────────────────────────────────
fix_ulimit() {
    info "Ustawiam file descriptor limits (wymagane przez esync)..."

    local limits_conf="/etc/security/limits.conf"
    local limits_d="/etc/security/limits.d/gaming.conf"

    # Sprawdź czy już ustawione
    if grep -q "nofile.*524288" "$limits_conf" 2>/dev/null || \
       grep -q "nofile.*524288" "$limits_d" 2>/dev/null; then
        log "File descriptor limits już ustawione (524288)"
        return
    fi

    $SUDO tee "$limits_d" > /dev/null << 'LIMITS'
# Gaming limits — wygenerowane przez sysfix.sh
# Wymagane przez esync (Wine/Proton)
* hard nofile 524288
* soft nofile 524288
LIMITS

    log "limits.d/gaming.conf → nofile=524288"

    # systemd user session
    local systemd_conf_dir="${HOME}/.config/systemd/user.conf.d"
    mkdir -p "$systemd_conf_dir"
    cat > "$systemd_conf_dir/limits.conf" << 'SYSD'
[Manager]
DefaultLimitNOFILE=524288
SYSD
    log "systemd user limits → $systemd_conf_dir/limits.conf"

    # Aktywuj na bieżącej sesji
    ulimit -n 524288 2>/dev/null && log "ulimit -n 524288 aktywny teraz" || \
        warn "Pełny efekt po ponownym zalogowaniu"
}

# ─── 2. inotify limits ────────────────────────────────────────────────────────
fix_inotify() {
    info "Ustawiam inotify limits..."

    local sysctl_d="/etc/sysctl.d/99-gaming-inotify.conf"

    $SUDO tee "$sysctl_d" > /dev/null << 'SYSCTL'
# inotify limits dla gamingu i esync
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
fs.inotify.max_queued_events = 32768
SYSCTL

    $SUDO sysctl -p "$sysctl_d" &>/dev/null
    log "inotify → max_user_watches=524288"
}

# ─── 3. vm.max_map_count (wymagane przez niektóre gry: Star Citizen, Elden Ring) ──
fix_vm_maps() {
    info "Ustawiam vm.max_map_count..."

    local sysctl_d="/etc/sysctl.d/99-gaming-vm.conf"

    $SUDO tee "$sysctl_d" > /dev/null << 'SYSCTL'
# Wymagane przez niektóre gry (Star Citizen, Elden Ring, itp.)
vm.max_map_count = 2147483642
SYSCTL

    $SUDO sysctl -p "$sysctl_d" &>/dev/null
    log "vm.max_map_count=2147483642"
}

# ─── 4. PipeWire — native Wine audio (koniec z crackling) ────────────────────
fix_pipewire() {
    if ! pgrep -x pipewire &>/dev/null; then
        warn "PipeWire nie działa — sprawdź czy jest zainstalowany"
        warn "sudo pacman -S pipewire pipewire-pulse pipewire-alsa wireplumber"
        return
    fi

    info "Konfiguruję PipeWire dla gamingu..."

    # Zmniejsz quantum (latency) dla gamingu
    local pw_conf_dir="${HOME}/.config/pipewire/pipewire.conf.d"
    mkdir -p "$pw_conf_dir"

    cat > "$pw_conf_dir/gaming.conf" << 'PW'
# PipeWire gaming config — niskie latency
context.properties = {
    default.clock.rate          = 48000
    default.clock.quantum       = 256
    default.clock.min-quantum   = 32
    default.clock.max-quantum   = 8192
}
PW
    log "PipeWire quantum=256 (niskie latency) → $pw_conf_dir/gaming.conf"

    # WINE PipeWire native backend
    local wine_conf_dir="${HOME}/.config/wine"
    mkdir -p "$wine_conf_dir"
    cat > "$wine_conf_dir/wine.conf" << 'WINE'
[HKEY_CURRENT_USER\Software\Wine\Drivers]
"Audio"="pipewire"
WINE
    log "Wine audio driver → pipewire"

    # Restart PipeWire żeby zaaplikować
    systemctl --user restart pipewire pipewire-pulse 2>/dev/null && \
        log "PipeWire zrestartowany" || true
}

# ─── 5. GameMode ──────────────────────────────────────────────────────────────
fix_gamemode() {
    if command -v gamemoded &>/dev/null; then
        log "GameMode już zainstalowany"
    else
        warn "GameMode nie zainstalowany"
        info "sudo pacman -S gamemode"
        if command -v pacman &>/dev/null; then
            read -rp "  Zainstalować teraz? [t/N] " ans
            [[ "$ans" =~ ^[tTyY]$ ]] && sudo pacman -S --noconfirm gamemode
        fi
        return
    fi

    # Config GameMode
    local gm_conf="${HOME}/.config/gamemode.ini"
    if [[ ! -f "$gm_conf" ]]; then
        cat > "$gm_conf" << 'GM'
[general]
renice=10
ioprio=0

[filter]
whitelist=

[gpu]
apply_gpu_optimisations=accept-responsibility
gpu_device=0
amd_performance_level=high

[cpu]
park_cores=no
pin_cores=no

[custom]
start=notify-send "GameMode" "Aktywny 🎮" 2>/dev/null || true
end=notify-send "GameMode" "Nieaktywny" 2>/dev/null || true
GM
        log "GameMode config → $gm_conf"
    else
        log "GameMode config już istnieje"
    fi

    # Uruchom gamemode service
    systemctl --user enable --now gamemoded 2>/dev/null && \
        log "gamemoded service aktywny" || true
}

# ─── 6. MangoHud ──────────────────────────────────────────────────────────────
fix_mangohud() {
    if ! command -v mangohud &>/dev/null; then
        warn "MangoHud nie zainstalowany"
        info "sudo pacman -S mangohud"
        return
    fi

    local mh_conf_dir="${HOME}/.config/MangoHud"
    mkdir -p "$mh_conf_dir"

    if [[ ! -f "$mh_conf_dir/MangoHud.conf" ]]; then
        cat > "$mh_conf_dir/MangoHud.conf" << 'MH'
# MangoHud config — gaming overlay
fps
frame_timing
gpu_stats
gpu_temp
cpu_stats
cpu_temp
ram
vram
wine
engine_version
position=top-left
font_size=18
background_alpha=0.4
MH
        log "MangoHud config → $mh_conf_dir/MangoHud.conf"
    else
        log "MangoHud config już istnieje"
    fi
}

# ─── 7. Gamescope ─────────────────────────────────────────────────────────────
fix_gamescope() {
    if ! command -v gamescope &>/dev/null; then
        warn "Gamescope nie zainstalowany"
        info "sudo pacman -S gamescope"
        if command -v pacman &>/dev/null; then
            read -rp "  Zainstalować teraz? [t/N] " ans
            [[ "$ans" =~ ^[tTyY]$ ]] && sudo pacman -S --noconfirm gamescope
        fi
    else
        log "Gamescope zainstalowany: $(gamescope --version 2>/dev/null | head -1 || echo '?')"
    fi
}

# ─── 8. DXVK state cache dir ─────────────────────────────────────────────────
fix_dxvk_cache() {
    local cache_dir="${HOME}/.cache/dxvk"
    mkdir -p "$cache_dir"
    log "DXVK state cache dir: $cache_dir"

    # Ustaw w środowisku użytkownika
    local profile_d="${HOME}/.profile"
    if ! grep -q "DXVK_STATE_CACHE_PATH" "$profile_d" 2>/dev/null; then
        echo "export DXVK_STATE_CACHE_PATH=\"$cache_dir\"" >> "$profile_d"
        log "DXVK_STATE_CACHE_PATH dodany do ~/.profile"
    fi
}

# ─── 9. Transparent hugepages (zmniejsza stuttery) ───────────────────────────
fix_hugepages() {
    info "Ustawiam transparent hugepages → madvise..."

    local thp="/sys/kernel/mm/transparent_hugepage/enabled"
    if [[ -f "$thp" ]]; then
        echo "madvise" | $SUDO tee "$thp" > /dev/null
        log "transparent_hugepage=madvise"

        # Persistentne przez tmpfiles
        local tmpfiles="/etc/tmpfiles.d/gaming-thp.conf"
        echo "w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise" | \
            $SUDO tee "$tmpfiles" > /dev/null
    else
        warn "transparent_hugepage nie dostępne w tym kernelu"
    fi
}

# ─── 10. Split lock mitigation OFF (zmniejsza latency na Intel) ──────────────
fix_split_lock() {
    local sl="/proc/sys/kernel/split_lock_mitigate"
    if [[ -f "$sl" ]]; then
        echo 0 | $SUDO tee "$sl" > /dev/null
        local sysctl_d="/etc/sysctl.d/99-gaming-cpu.conf"
        echo "kernel.split_lock_mitigate = 0" | $SUDO tee "$sysctl_d" > /dev/null
        log "split_lock_mitigate=0 (mniejsza latency na Intel)"
    fi
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
banner
need_root
check_status

echo -e "  Co naprawić?\n"
echo -e "  $(kbtn "1") 🔑  ulimit / file descriptors  ${DIM}(esync wymaga 524288)${NC}"
echo -e "  $(kbtn "2") 👁  inotify limits             ${DIM}(crashe w wielu grach)${NC}"
echo -e "  $(kbtn "3") 🗺  vm.max_map_count           ${DIM}(Star Citizen, Elden Ring)${NC}"
echo -e "  $(kbtn "4") 🔊  PipeWire native audio      ${DIM}(koniec z crackling)${NC}"
echo -e "  $(kbtn "5") 🎮  GameMode                   ${DIM}(CPU/GPU boost podczas gry)${NC}"
echo -e "  $(kbtn "6") 📊  MangoHud                   ${DIM}(overlay FPS/temp)${NC}"
echo -e "  $(kbtn "7") 🖥  Gamescope                  ${DIM}(FSR upscaling, frame cap)${NC}"
echo -e "  $(kbtn "8") 💾  DXVK cache dir             ${DIM}(mniej stutterów)${NC}"
echo -e "  $(kbtn "9") 📑  Transparent hugepages      ${DIM}(mniej stutterów pamięci)${NC}"
echo -e "  $(kbtn "0") ⚡  Split lock mitigation OFF  ${DIM}(niższa latency Intel)${NC}"
echo -e "  $(kbtn "A") ✨  Wszystko naraz"
echo -e "  $(kbtn "Q") ⏭  Wyjście"
echo
read -rp "  > " choice

run_all() {
    fix_ulimit
    fix_inotify
    fix_vm_maps
    fix_pipewire
    fix_gamemode
    fix_mangohud
    fix_gamescope
    fix_dxvk_cache
    fix_hugepages
    fix_split_lock
}

case "$choice" in
    1) fix_ulimit ;;
    2) fix_inotify ;;
    3) fix_vm_maps ;;
    4) fix_pipewire ;;
    5) fix_gamemode ;;
    6) fix_mangohud ;;
    7) fix_gamescope ;;
    8) fix_dxvk_cache ;;
    9) fix_hugepages ;;
    0) fix_split_lock ;;
    [aA]) run_all ;;
    [qQ]) exit 0 ;;
    *) err "Nieznana opcja" ;;
esac

echo
echo -e "  ${G}${BOLD}Gotowe!${NC}"
echo -e "  ${DIM}Niektóre zmiany (ulimit, sysctl) wymagają ponownego zalogowania.${NC}"
echo
