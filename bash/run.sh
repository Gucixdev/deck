#!/usr/bin/env bash
set -euo pipefail

# run.sh — Steam Launch Options wrapper
# Użycie w Steam: /path/to/run.sh %command%

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECK_DIR="$(dirname "$SCRIPT_DIR")"
GAMES_CONF="$DECK_DIR/games.conf"
OVERRIDES_CONF="$DECK_DIR/env/game_overrides.conf"
COMPAT_DIR="${STEAM_COMPAT_DIR:-$HOME/.steam/steam/compatibilitytools.d}"
DXVK_CACHE_DIR="${HOME}/.cache/dxvk"
VKD3D_CACHE_DIR="${HOME}/.cache/vkd3d-proton"

# ─── PS4 game — przekieruj do runps4 ─────────────────────────────────────────
# Steam non-Steam games mogą mieć SteamAppId ustawiony na CUSA* w launch options
APPID="${SteamAppId:-}"
if [[ "$APPID" =~ ^CUSA ]]; then
    exec bash "$SCRIPT_DIR/runps4.sh" "$APPID"
fi

# ─── Profil gry ───────────────────────────────────────────────────────────────
PROFILE="vanilla"
GAME_USE_GAMESCOPE=""
GAME_CPU_CORES=""

if [[ -z "$APPID" ]]; then
    echo "[run.sh] ⚠️  SteamAppId nie ustawiony — vanilla"
else
    if [[ -f "$GAMES_CONF" ]]; then
        while IFS=: read -r conf_appid _name conf_profile; do
            [[ "$conf_appid" =~ ^#.*$ || -z "$conf_appid" ]] && continue
            conf_appid="${conf_appid// /}"
            if [[ "$conf_appid" == "$APPID" ]]; then
                PROFILE="${conf_profile// /}"
                break
            fi
        done < "$GAMES_CONF"
    fi
fi

# ─── Proton build ─────────────────────────────────────────────────────────────
PROTON_BUILD=""
if [[ -d "$COMPAT_DIR/proton-deck-${PROFILE}" ]]; then
    PROTON_BUILD="$COMPAT_DIR/proton-deck-${PROFILE}"
else
    for dir in "$COMPAT_DIR"/proton-deck-*; do
        [[ -d "$dir" ]] && PROTON_BUILD="$dir" && break
    done
fi

# ─── Wykryj GPU ───────────────────────────────────────────────────────────────
GPU_VENDOR="unknown"
GPU_INFO=$(lspci 2>/dev/null | grep -iE "VGA|3D|Display" | head -1 || true)
IS_RTX=false

if echo "$GPU_INFO" | grep -qi "NVIDIA"; then
    GPU_VENDOR="nvidia"
    echo "$GPU_INFO" | grep -qi "RTX\|GeForce [234][0-9][0-9][0-9]\|GeForce 50" && IS_RTX=true
elif echo "$GPU_INFO" | grep -qi "AMD\|ATI\|Radeon"; then
    GPU_VENDOR="amd"
elif echo "$GPU_INFO" | grep -qi "Intel"; then
    GPU_VENDOR="intel"
fi

# ─── GPU vars ────────────────────────────────────────────────────────────────
case "$GPU_VENDOR" in
    amd)
        export mesa_glthread=true
        export RADV_PERFTEST=gpl
        export DXVK_ASYNC=1
        # FSR przez Wine na każdej rozdzielczości
        export WINE_FULLSCREEN_FSR=1
        export WINE_FULLSCREEN_FSR_STRENGTH=2
        ;;
    nvidia)
        export __GL_THREADED_OPTIMIZATIONS=1
        export __GL_SYNC_TO_VBLANK=0
        export DXVK_ASYNC=0
        export VKD3D_CONFIG=dxr
        # DLSS — wymaga NVAPI
        export PROTON_ENABLE_NVAPI=1
        $IS_RTX && export PROTON_DLSS=1 || true
        # Hybrid GPU
        if lspci 2>/dev/null | grep -qi "Intel.*VGA\|AMD.*VGA"; then
            export __NV_PRIME_RENDER_OFFLOAD=1
            export __VK_LAYER_NV_optimus=NVIDIA_only
            export __GLX_VENDOR_LIBRARY_NAME=nvidia
        fi
        ;;
    intel)
        export mesa_glthread=true
        export DXVK_ASYNC=1
        export WINE_FULLSCREEN_FSR=1
        export WINE_FULLSCREEN_FSR_STRENGTH=2
        ;;
esac

# ─── Profil vars ──────────────────────────────────────────────────────────────
case "$PROFILE" in
    vanilla)
        export PROTON_LOG=0
        export PROTON_HEAP_DELAY_FREE=1
        ;;
    mod)
        export PROTON_LOG=0
        export PROTON_HEAP_DELAY_FREE=1
        export PROTON_NO_ESYNC=0
        export PROTON_NO_FSYNC=0
        ;;
    online)
        export PROTON_LOG=0
        export PROTON_HEAP_DELAY_FREE=1
        export PROTON_NO_FSYNC=1
        export PROTON_IPV6=0
        [[ "$GPU_VENDOR" == "nvidia" ]] && export DXVK_ASYNC=0
        ;;
esac

# ─── Shader cache ─────────────────────────────────────────────────────────────
mkdir -p "$DXVK_CACHE_DIR" "$VKD3D_CACHE_DIR"
export DXVK_STATE_CACHE_PATH="$DXVK_CACHE_DIR"
export DXVK_STATE_CACHE=1
export VKD3D_SHADER_CACHE_PATH="$VKD3D_CACHE_DIR"

# Per-gra dxvk.conf jeśli istnieje
if [[ -n "$APPID" && -f "$DECK_DIR/env/dxvk/${APPID}.conf" ]]; then
    export DXVK_CONFIG_FILE="$DECK_DIR/env/dxvk/${APPID}.conf"
    echo "[run.sh] 🔧 dxvk.conf: env/dxvk/${APPID}.conf"
fi

echo "[run.sh] 🖥️  GPU=$GPU_VENDOR RTX=$IS_RTX | Profil=$PROFILE | AppID=${APPID:-?}"

# ─── Per-gra overrides ────────────────────────────────────────────────────────
WINE_DLL_OVERRIDES=""

if [[ -n "$APPID" && -f "$OVERRIDES_CONF" ]]; then
    while IFS=: read -r ov_appid ov_kv; do
        [[ "$ov_appid" =~ ^#.*$ || -z "$ov_appid" ]] && continue
        ov_appid="${ov_appid// /}"
        [[ "$ov_appid" != "$APPID" ]] && continue

        key="${ov_kv%%=*}"
        val="${ov_kv#*=}"
        key="${key// /}"

        case "$key" in
            WINEDLLOVERRIDES)
                [[ -z "$WINE_DLL_OVERRIDES" ]] \
                    && WINE_DLL_OVERRIDES="$val" \
                    || WINE_DLL_OVERRIDES="${WINE_DLL_OVERRIDES};${val}"
                ;;
            DECK_GAMESCOPE)  GAME_USE_GAMESCOPE="$val" ;;
            DECK_CPU_CORES)  GAME_CPU_CORES="$val" ;;
            *)
                export "$key=$val"
                echo "[run.sh] 🔧 $key=$val"
                ;;
        esac
    done < "$OVERRIDES_CONF"

    if [[ -n "$WINE_DLL_OVERRIDES" ]]; then
        export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+${WINEDLLOVERRIDES};}${WINE_DLL_OVERRIDES}"
        echo "[run.sh] 🔧 WINEDLLOVERRIDES=$WINEDLLOVERRIDES"
    fi
fi

# ─── SDL input fix ────────────────────────────────────────────────────────────
export SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD=1
export SDL_JOYSTICK_HIDAPI=0

# ─── Gamescope ────────────────────────────────────────────────────────────────
# Format: WxH@FPS[:fsr|nis]  np. 1920x1080@60:fsr
GAMESCOPE_WRAP=""
if [[ -n "$GAME_USE_GAMESCOPE" ]] && command -v gamescope &>/dev/null; then
    GS_RES="${GAME_USE_GAMESCOPE%%:*}"
    GS_FLAGS="${GAME_USE_GAMESCOPE#*:}"
    GS_W="${GS_RES%%x*}"
    GS_RH="${GS_RES#*x}"
    GS_H="${GS_RH%%@*}"
    GS_FPS="${GS_RH##*@}"
    GS_ARGS="-w $GS_W -h $GS_H -r $GS_FPS -f --steam"
    [[ "$GS_FLAGS" == *"fsr"* ]] && GS_ARGS="$GS_ARGS --fsr-upscaling"
    [[ "$GS_FLAGS" == *"nis"* ]] && GS_ARGS="$GS_ARGS --nis-upscaling"
    GAMESCOPE_WRAP="gamescope $GS_ARGS --"
    echo "[run.sh] 🔍 Gamescope: ${GS_W}x${GS_H}@${GS_FPS} flags=$GS_FLAGS"
fi

# ─── GameMode ────────────────────────────────────────────────────────────────
GAMEMODE_WRAP=""
command -v gamemoded &>/dev/null && GAMEMODE_WRAP="gamemoderun" && \
    echo "[run.sh] 🎮 GameMode aktywny"

# ─── CPU governor ────────────────────────────────────────────────────────────
PREV_GOVERNOR=""
if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
    PREV_GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "")
    if [[ "$PREV_GOVERNOR" != "performance" ]]; then
        echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor &>/dev/null || true
        echo "[run.sh] ⚡ CPU governor: $PREV_GOVERNOR → performance"
    fi
fi

# ─── Compositor suspend ───────────────────────────────────────────────────────
COMPOSITOR_WAS_ACTIVE=false
suspend_compositor() {
    if command -v qdbus &>/dev/null; then
        qdbus org.kde.KWin /Compositor active 2>/dev/null | grep -q "true" || return 0
        qdbus org.kde.KWin /Compositor suspend 2>/dev/null && COMPOSITOR_WAS_ACTIVE=true && \
            echo "[run.sh] 🖥️  KWin zawieszony"; return
    fi
    if command -v gsettings &>/dev/null && \
       gsettings get org.gnome.mutter compositing-manager &>/dev/null 2>&1; then
        gsettings set org.gnome.mutter compositing-manager false 2>/dev/null && \
            COMPOSITOR_WAS_ACTIVE=true && echo "[run.sh] 🖥️  GNOME compositor wyłączony"; return
    fi
    if command -v xfconf-query &>/dev/null; then
        [[ "$(xfconf-query -c xfwm4 -p /general/use_compositing 2>/dev/null)" == "true" ]] || return 0
        xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null && \
            COMPOSITOR_WAS_ACTIVE=true && echo "[run.sh] 🖥️  XFCE compositor wyłączony"; return
    fi
    if pgrep -x "picom|compton" &>/dev/null; then
        pkill -x "picom|compton" 2>/dev/null && COMPOSITOR_WAS_ACTIVE=true && \
            echo "[run.sh] 🖥️  picom zatrzymany"
    fi
}

# ─── Cleanup ──────────────────────────────────────────────────────────────────
cleanup() {
    # Przywróć CPU governor
    if [[ -n "$PREV_GOVERNOR" && "$PREV_GOVERNOR" != "performance" ]]; then
        echo "$PREV_GOVERNOR" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor &>/dev/null || true
    fi
    # Przywróć compositor
    if [[ "$COMPOSITOR_WAS_ACTIVE" == "true" ]]; then
        command -v qdbus       &>/dev/null && qdbus org.kde.KWin /Compositor resume 2>/dev/null || true
        command -v gsettings   &>/dev/null && gsettings set org.gnome.mutter compositing-manager true 2>/dev/null || true
        command -v xfconf-query &>/dev/null && xfconf-query -c xfwm4 -p /general/use_compositing -s true 2>/dev/null || true
    fi
}
trap cleanup EXIT

suspend_compositor

# ─── CPU core pinning dla starych gier ───────────────────────────────────────
# DECK_CPU_CORES=N — ogranicz do N rdzeni (stare gry crashują z >4/8 rdzeniami)
TASKSET_WRAP=""
if [[ -n "$GAME_CPU_CORES" ]] && command -v taskset &>/dev/null; then
    CORE_RANGE="0-$(( GAME_CPU_CORES - 1 ))"
    TASKSET_WRAP="taskset -c $CORE_RANGE"
    echo "[run.sh] 📌 CPU pinning: $CORE_RANGE ($GAME_CPU_CORES rdzeni)"
fi

# ─── Launch ───────────────────────────────────────────────────────────────────
echo "[run.sh] 🚀 Proton=${PROTON_BUILD:-systemowy}"

if [[ -n "$PROTON_BUILD" && -f "$PROTON_BUILD/proton" ]]; then
    export PROTON_PATH="$PROTON_BUILD"
    exec ${GAMESCOPE_WRAP:+$GAMESCOPE_WRAP} \
         ${GAMEMODE_WRAP:+$GAMEMODE_WRAP} \
         ${TASKSET_WRAP:+$TASKSET_WRAP} \
         "$PROTON_BUILD/proton" run "$@"
else
    echo "[run.sh] ⚠️  Brak proton-deck-${PROFILE} — Steam użyje domyślnego"
    exec ${GAMESCOPE_WRAP:+$GAMESCOPE_WRAP} \
         ${GAMEMODE_WRAP:+$GAMEMODE_WRAP} \
         ${TASKSET_WRAP:+$TASKSET_WRAP} \
         "$@"
fi
