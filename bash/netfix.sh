#!/usr/bin/env bash
set -euo pipefail

# netfix.sh — optymalizacja sieci dla gamingu
# Wykrywa kartę sieciową i stosuje odpowiednie tweaki

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[1;34m'; C='\033[0;36m'; DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "  ${G}✔${NC}  $*"; }
info() { echo -e "  ${B}ℹ${NC}  $*"; }
warn() { echo -e "  ${Y}⚠${NC}  $*"; }
err()  { echo -e "  ${R}✖${NC}  $*"; }

banner() {
    echo
    echo -e "  ${B}╭──────────────────────────────────────────────────╮${NC}"
    echo -e "  ${B}│${NC}  ${BOLD}🌐  NetFix — Gaming Network Optimizer${NC}            ${B}│${NC}"
    echo -e "  ${B}╰──────────────────────────────────────────────────╯${NC}"
    echo
}

need_root() {
    if [[ $EUID -ne 0 ]]; then
        warn "Niektóre tweaki wymagają sudo."
        SUDO="sudo"
    else
        SUDO=""
    fi
}

# ─── Wykryj interfejsy ────────────────────────────────────────────────────────
detect_interfaces() {
    WIFI_IFACES=()
    ETH_IFACES=()

    while IFS= read -r iface; do
        if [[ -d "/sys/class/net/$iface/wireless" ]]; then
            WIFI_IFACES+=("$iface")
        elif [[ "$iface" != "lo" ]]; then
            ETH_IFACES+=("$iface")
        fi
    done < <(ls /sys/class/net/)

    echo -e "  ${C}── Interfejsy sieciowe ──────────────────────────────${NC}"
    for iface in "${WIFI_IFACES[@]:-}"; do
        [[ -z "$iface" ]] && continue
        local driver=""
        driver=$(basename "$(readlink -f "/sys/class/net/$iface/device/driver" 2>/dev/null)" 2>/dev/null || echo "?")
        echo -e "  📶 WiFi:     ${BOLD}$iface${NC}  ${DIM}(driver: $driver)${NC}"
    done
    for iface in "${ETH_IFACES[@]:-}"; do
        [[ -z "$iface" ]] && continue
        local driver=""
        driver=$(basename "$(readlink -f "/sys/class/net/$iface/device/driver" 2>/dev/null)" 2>/dev/null || echo "?")
        echo -e "  🔌 Ethernet: ${BOLD}$iface${NC}  ${DIM}(driver: $driver)${NC}"
    done
    echo -e "  ${C}────────────────────────────────────────────────────${NC}"
    echo
}

# ─── WiFi power management OFF ────────────────────────────────────────────────
fix_wifi_power() {
    if [[ ${#WIFI_IFACES[@]} -eq 0 ]]; then
        info "Brak interfejsów WiFi — pomijam"
        return
    fi

    for iface in "${WIFI_IFACES[@]}"; do
        [[ -z "$iface" ]] && continue

        local driver=""
        driver=$(basename "$(readlink -f "/sys/class/net/$iface/device/driver" 2>/dev/null)" 2>/dev/null || echo "")

        # Wyłącz power save
        if command -v iwconfig &>/dev/null; then
            $SUDO iwconfig "$iface" power off 2>/dev/null && \
                log "$iface: power management wyłączony" || \
                warn "$iface: nie udało się wyłączyć power management"
        fi

        # Wyłącz przez iw (nowszy sposób)
        if command -v iw &>/dev/null; then
            $SUDO iw dev "$iface" set power_save off 2>/dev/null && \
                log "$iface: iw power_save off" || true
        fi

        # Driver-specific tweaks
        case "$driver" in
            iwlwifi)
                info "$iface: Intel WiFi (iwlwifi) — ustawiam parametry modułu"
                # Wyłącz aggressive power save i 11n power save
                if [[ -d "/sys/module/iwlwifi/parameters" ]]; then
                    echo 1 | $SUDO tee /sys/module/iwlwifi/parameters/power_save      &>/dev/null || true
                    echo 0 | $SUDO tee /sys/module/iwlwifi/parameters/power_level     &>/dev/null || true
                    # Persistence — zapisz do modprobe
                    local conf="/etc/modprobe.d/iwlwifi-gaming.conf"
                    echo "options iwlwifi power_save=0 uapsd_disable=1" | $SUDO tee "$conf" > /dev/null
                    log "Intel WiFi: power_save=0 uapsd_disable=1 → $conf"
                fi
                ;;
            ath9k|ath9k_htc)
                info "$iface: Atheros ath9k — wyłączam PS"
                if [[ -d "/sys/module/ath9k/parameters" ]]; then
                    echo 0 | $SUDO tee /sys/module/ath9k/parameters/ps_enable &>/dev/null || true
                    local conf="/etc/modprobe.d/ath9k-gaming.conf"
                    echo "options ath9k ps_enable=0" | $SUDO tee "$conf" > /dev/null
                    log "Atheros ath9k: ps_enable=0 → $conf"
                fi
                ;;
            ath10k_pci|ath10k_usb)
                info "$iface: Atheros ath10k — wyłączam PS"
                local conf="/etc/modprobe.d/ath10k-gaming.conf"
                echo "options ath10k_core skip_otp=y" | $SUDO tee "$conf" > /dev/null
                log "Atheros ath10k → $conf"
                ;;
            rtl8192cu|rtl8xxxu|rtl8188ee|rtl8192ee|rtl8723be|rtl8821ce|r8188eu)
                info "$iface: Realtek WiFi — wyłączam power save"
                local conf="/etc/modprobe.d/realtek-gaming.conf"
                local mod="${driver%%[0-9]*}"
                echo "options $driver rtw_power_mgnt=0 rtw_enusbss=0" | $SUDO tee "$conf" > /dev/null 2>&1 || \
                echo "options $driver power_mgmt=0" | $SUDO tee "$conf" > /dev/null
                log "Realtek $driver: power_mgnt=0 → $conf"
                ;;
            mt76*|mt7921*|mt7922*)
                info "$iface: MediaTek WiFi — wyłączam PS"
                local conf="/etc/modprobe.d/mt76-gaming.conf"
                echo "options mt76_core disable_aspm=1" | $SUDO tee "$conf" > /dev/null
                log "MediaTek mt76: disable_aspm=1 → $conf"
                ;;
            brcmfmac|brcmsmac)
                info "$iface: Broadcom WiFi"
                local conf="/etc/modprobe.d/brcmfmac-gaming.conf"
                echo "options brcmfmac roamoff=1" | $SUDO tee "$conf" > /dev/null
                log "Broadcom: roamoff=1 → $conf"
                ;;
            *)
                warn "$iface: nieznany driver ($driver) — tylko iwconfig/iw power off"
                ;;
        esac

        # Wyłącz roaming agresywny (NetworkManager)
        if command -v nmcli &>/dev/null; then
            local nm_iface
            nm_iface=$(nmcli -g GENERAL.CONNECTION device show "$iface" 2>/dev/null | head -1 || true)
            if [[ -n "$nm_iface" && "$nm_iface" != "--" ]]; then
                nmcli connection modify "$nm_iface" 802-11-wireless.band a 2>/dev/null || true
                log "NetworkManager: $nm_iface zaktualizowany"
            fi
        fi
    done
}

# ─── Ethernet — wyłącz energy efficient ethernet ─────────────────────────────
fix_ethernet() {
    if [[ ${#ETH_IFACES[@]} -eq 0 ]]; then
        return
    fi

    if ! command -v ethtool &>/dev/null; then
        warn "ethtool nie zainstalowany — pomijam Ethernet tweaks (sudo pacman -S ethtool)"
        return
    fi

    for iface in "${ETH_IFACES[@]}"; do
        [[ -z "$iface" ]] && continue

        # Wyłącz Energy Efficient Ethernet (powoduje latency spikes)
        $SUDO ethtool --set-eee "$iface" eee off 2>/dev/null && \
            log "$iface: EEE (Energy Efficient Ethernet) wyłączony" || true

        # Ustaw max ring buffer
        local rx max_rx
        max_rx=$($SUDO ethtool -g "$iface" 2>/dev/null | grep "RX:" | tail -1 | awk '{print $2}' || echo "")
        if [[ -n "$max_rx" ]]; then
            $SUDO ethtool -G "$iface" rx "$max_rx" 2>/dev/null && \
                log "$iface: RX ring buffer → $max_rx" || true
        fi

        # Wyłącz interrupt coalescing (zmniejsza latency kosztem CPU)
        $SUDO ethtool -C "$iface" rx-usecs 0 2>/dev/null || true
    done
}

# ─── Kernel sysctl — TCP/UDP gaming tuning ───────────────────────────────────
fix_sysctl() {
    info "Ustawiam parametry kernela (sysctl)..."

    local sysctl_conf="/etc/sysctl.d/99-gaming-net.conf"

    $SUDO tee "$sysctl_conf" > /dev/null << 'SYSCTL'
# Gaming network tuning — wygenerowane przez netfix.sh

# Zwiększ bufory TCP/UDP
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 16777216
net.core.wmem_default = 16777216
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# Wyłącz Nagle (zmniejsza latency w grach multiplayer)
net.ipv4.tcp_nodelay = 1

# Szybszy retransmit
net.ipv4.tcp_fastopen = 3

# BBR congestion control (Google, lepszy dla gameingu)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Zmniejsz czas TIME_WAIT
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1

# Więcej połączeń w kolejce
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192

# Wyłącz slow start po idle (ważne dla gier z przerwami)
net.ipv4.tcp_slow_start_after_idle = 0

# Keepalive
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
SYSCTL

    $SUDO sysctl -p "$sysctl_conf" &>/dev/null && \
        log "sysctl → $sysctl_conf" || \
        warn "Nie udało się zaaplikować sysctl (niektóre parametry mogą wymagać restartu)"
}

# ─── Sprawdź czy BBR jest dostępny ───────────────────────────────────────────
check_bbr() {
    if ! modinfo tcp_bbr &>/dev/null; then
        warn "TCP BBR nie dostępny w tym kernelu — pomijam"
        return 1
    fi
    $SUDO modprobe tcp_bbr 2>/dev/null || true
    return 0
}

# ─── NetworkManager — wyłącz WiFi scan w tle ─────────────────────────────────
fix_nm_scanning() {
    if ! command -v nmcli &>/dev/null; then
        return
    fi

    local nm_conf="/etc/NetworkManager/conf.d/gaming.conf"
    $SUDO tee "$nm_conf" > /dev/null << 'NM'
[device]
wifi.scan-rand-mac-address=no

[connection]
wifi.powersave=2
NM
    log "NetworkManager: skanowanie tła → $nm_conf"

    # Restart NM tylko jeśli jest aktywny
    if systemctl is-active NetworkManager &>/dev/null; then
        $SUDO systemctl reload NetworkManager 2>/dev/null || true
    fi
}

# ─── Status sieci ─────────────────────────────────────────────────────────────
show_status() {
    echo
    echo -e "  ${C}── Status ───────────────────────────────────────────${NC}"

    for iface in "${WIFI_IFACES[@]:-}" "${ETH_IFACES[@]:-}"; do
        [[ -z "$iface" ]] && continue
        local state ip
        state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo "?")
        ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "brak IP")
        echo -e "  ${BOLD}$iface${NC}  stan: $state  IP: $ip"
    done

    # Ping test
    echo
    info "Ping test (8.8.8.8)..."
    if ping -c 3 -q 8.8.8.8 &>/dev/null; then
        local ping_ms
        ping_ms=$(ping -c 10 -q 8.8.8.8 2>/dev/null | grep "rtt" | grep -oP '[\d.]+' | head -2 | tail -1 || echo "?")
        log "Ping avg: ${ping_ms}ms"
    else
        warn "Brak połączenia z internetem"
    fi

    echo -e "  ${C}────────────────────────────────────────────────────${NC}"
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
banner
need_root
detect_interfaces

echo -e "  Co chcesz zrobić?\n"
echo -e "  ⌈ 1 ⌋ Pełna optymalizacja (WiFi + Ethernet + sysctl)"
echo -e "  ⌈ 2 ⌋ Tylko WiFi power management"
echo -e "  ⌈ 3 ⌋ Tylko sysctl (TCP/UDP tuning)"
echo -e "  ⌈ 4 ⌋ Pokaż status sieci"
echo -e "  ⌈ Q ⌋ Wyjście"
echo
read -rp "  > " choice

case "$choice" in
    1)
        fix_wifi_power
        fix_ethernet
        check_bbr && fix_sysctl || true
        fix_nm_scanning
        show_status
        ;;
    2)
        fix_wifi_power
        show_status
        ;;
    3)
        check_bbr && fix_sysctl || true
        ;;
    4)
        show_status
        ;;
    [qQ])
        exit 0
        ;;
    *)
        err "Nieznana opcja"
        exit 1
        ;;
esac

echo
echo -e "  ${G}${BOLD}Gotowe!${NC} Niektóre zmiany (modprobe) wymagają restartu żeby były trwałe."
echo
