#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECK_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$DECK_DIR/build"
PROTONTKG_DIR="$BUILD_DIR/proton-tkg"
PROTON_PROFILES_DIR="$DECK_DIR/env/proton"
COMPAT_DIR="${STEAM_COMPAT_DIR:-$HOME/.steam/steam/compatibilitytools.d}"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[1;34m'; C='\033[0;36m'; NC='\033[0m'

log()  { echo -e "  ${G}[OK]${NC}   $*"; }
info() { echo -e "  ${B}[INFO]${NC} $*"; }
warn() { echo -e "  ${Y}[WARN]${NC} $*"; }
err()  { echo -e "  ${R}[ERR]${NC}  $*"; exit 1; }

banner() {
    echo -e "${B}"
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║        ProtonTKG Builder             ║"
    echo "  ╚══════════════════════════════════════╝"
    echo -e "${NC}"
}

# ─── Wykryj sprzęt ────────────────────────────────────────────────────────────
detect_hardware() {
    info "Wykrywam sprzęt..."

    CPU_VENDOR=$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}')
    CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
    CPU_CORES=$(nproc)
    CPU_MARCH=$(gcc -march=native -Q --help=target 2>/dev/null | grep "\-march=" | awk '{print $2}' || echo "native")

    GPU_INFO=$(lspci 2>/dev/null | grep -iE "VGA|3D|Display" | head -3 || echo "unknown")
    IS_AMD_GPU=false
    IS_NVIDIA_GPU=false
    IS_INTEL_GPU=false
    IS_VANGOGH=false
    IS_HYBRID=false   # laptop z dwoma GPU

    if echo "$GPU_INFO" | grep -qi "AMD\|ATI\|Radeon"; then
        IS_AMD_GPU=true
        echo "$GPU_INFO" | grep -qi "vangogh\|custom amd\|AMD Custom GPU 0405" && IS_VANGOGH=true
    fi
    echo "$GPU_INFO" | grep -qi "NVIDIA" && IS_NVIDIA_GPU=true
    echo "$GPU_INFO" | grep -qi "Intel"  && IS_INTEL_GPU=true

    # Hybrid = Intel iGPU + NVIDIA/AMD dGPU
    local gpu_count
    gpu_count=$(lspci 2>/dev/null | grep -icE "VGA|3D|Display" || echo 1)
    [[ "$gpu_count" -gt 1 ]] && IS_HYBRID=true

    RAM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)

    # Sprawdź AVX/AVX2/AVX512
    CPU_FLAGS=$(grep -m1 "^flags" /proc/cpuinfo | cut -d: -f2)
    HAS_AVX=false; HAS_AVX2=false; HAS_AVX512=false
    echo "$CPU_FLAGS" | grep -qw "avx"    && HAS_AVX=true
    echo "$CPU_FLAGS" | grep -qw "avx2"   && HAS_AVX2=true
    echo "$CPU_FLAGS" | grep -qw "avx512f" && HAS_AVX512=true

    echo
    echo -e "  ${C}── Sprzęt ──────────────────────────────────────${NC}"
    echo -e "  CPU:      $CPU_MODEL"
    echo -e "  Vendor:   $CPU_VENDOR  |  Rdzenie: $CPU_CORES  |  -march: $CPU_MARCH"
    echo -e "  AVX: $HAS_AVX  AVX2: $HAS_AVX2  AVX512: $HAS_AVX512"
    echo -e "  RAM:      ${RAM_GB}GB"
    echo -e "  GPU:      $GPU_INFO"
    echo -e "  AMD: $IS_AMD_GPU | NVIDIA: $IS_NVIDIA_GPU | Intel: $IS_INTEL_GPU | VanGogh: $IS_VANGOGH | Hybrid: $IS_HYBRID"
    echo -e "  ${C}────────────────────────────────────────────────${NC}"
    echo
}

# ─── Generuj customization.cfg ────────────────────────────────────────────────
generate_cfg() {
    local profile="$1"
    local cfg_out="$2"

    info "Generuję customization.cfg (profil: $profile)..."

    # Baza — agresywna optymalizacja pod wykryty sprzęt
    cat > "$cfg_out" << CFG
# ProtonTKG customization.cfg
# Wygenerowany przez buildproton.sh — $(date)
# Profil: $profile | Sprzęt: $CPU_MARCH | GPU AMD: $IS_AMD_GPU | VanGogh: $IS_VANGOGH

# ── Wersja Wine/Proton ──────────────────────────────────────────────────────
_proton_branch="bleeding_edge"
_use_staging="true"
_staging_version=""

# ── Kompilacja ──────────────────────────────────────────────────────────────
_GCC_FLAGS="-O3 -march=$CPU_MARCH -mtune=$CPU_MARCH -pipe"
_LD_FLAGS="-Wl,-O2,--sort-common,--as-needed"
_CROSS_FLAGS="-O3 -march=$CPU_MARCH -mtune=$CPU_MARCH -pipe"
_CROSS_LD_FLAGS="-Wl,-O2,--sort-common,--as-needed"
_jobs="$CPU_CORES"
CFG

    # AVX2/AVX512
    if [[ "$HAS_AVX512" == "true" ]]; then
        echo '_extra_gcc_flags="-mavx512f -mavx512dq -mavx512bw"' >> "$cfg_out"
    elif [[ "$HAS_AVX2" == "true" ]]; then
        echo '_extra_gcc_flags="-mavx2 -mfma"' >> "$cfg_out"
    elif [[ "$HAS_AVX" == "true" ]]; then
        echo '_extra_gcc_flags="-mavx"' >> "$cfg_out"
    fi

    cat >> "$cfg_out" << CFG

# ── Esync / Fsync ────────────────────────────────────────────────────────────
CFG

    case "$profile" in
        vanilla|mod)
            cat >> "$cfg_out" << CFG
_use_esync="true"
_use_fsync="true"
CFG
            ;;
        online)
            # Fsync może być problematyczny z niektórymi AC
            cat >> "$cfg_out" << CFG
_use_esync="true"
_use_fsync="false"
CFG
            ;;
    esac

    cat >> "$cfg_out" << CFG

# ── DXVK / VKD3D ────────────────────────────────────────────────────────────
_use_dxvk="true"
_dxvk_branch="bleeding_edge"
_use_vkd3d="true"
_vkd3d_branch="bleeding_edge"

# ── Media Foundation / Kodeki ────────────────────────────────────────────────
_use_mfplat="true"

# ── GPU-specific ─────────────────────────────────────────────────────────────
CFG

    if [[ "$IS_AMD_GPU" == "true" ]]; then
        cat >> "$cfg_out" << CFG
# AMD — RADV GPL pipeline, async shaders
_radv_perf_test="gpl"
_use_dxvk_async="true"
CFG
        if [[ "$IS_VANGOGH" == "true" ]]; then
            cat >> "$cfg_out" << CFG
# Steam Deck VanGogh — async kompilacja shaderów (ograniczony VRAM)
_dxvk_shader_compilation="async"
CFG
        fi
    fi

    if [[ "$IS_NVIDIA_GPU" == "true" ]]; then
        cat >> "$cfg_out" << CFG
# NVIDIA — threaded optymalizacje, DXR dla RTX, brak dxvk_async (buggy na nowym DXVK)
_use_dxvk_async="false"
_nvidia_threaded_opts="true"
CFG
        # Sprawdź czy RTX (GeForce 20xx+)
        if lspci 2>/dev/null | grep -qi "RTX\|GeForce 20\|GeForce 30\|GeForce 40\|GeForce 50"; then
            cat >> "$cfg_out" << CFG
# RTX — włącz DXR ray tracing
_vkd3d_dxr="true"
CFG
        fi
    fi

    if [[ "$IS_INTEL_GPU" == "true" && "$IS_NVIDIA_GPU" == "false" && "$IS_AMD_GPU" == "false" ]]; then
        cat >> "$cfg_out" << CFG
# Intel iGPU — mesa glthread, async shaders
_use_dxvk_async="true"
CFG
    fi

    if [[ "$IS_HYBRID" == "true" ]]; then
        cat >> "$cfg_out" << CFG
# Hybrid GPU (laptop) — PRIME render offload
_prime_render_offload="true"
CFG
    fi

    cat >> "$cfg_out" << CFG

# ── Per-profil ───────────────────────────────────────────────────────────────
CFG

    case "$profile" in
        vanilla)
            cat >> "$cfg_out" << CFG
# Vanilla: max wydajność, brak ograniczeń
_use_gamemode="true"
_use_mangohud="false"
_proton_prefix_version="GE"
CFG
            ;;
        mod)
            cat >> "$cfg_out" << CFG
# Mod: pełna kompatybilność z modami, bez EAC/BattlEye
_use_gamemode="true"
_no_eac="true"
_no_battleye="true"
_proton_prefix_version="GE"
CFG
            ;;
        online)
            cat >> "$cfg_out" << CFG
# Online: kompatybilność z EAC i BattlEye
_use_gamemode="true"
_eac_runtime="true"
_battleye_runtime="true"
_proton_prefix_version="GE"
CFG
            ;;
    esac
}

# ─── Klonuj / aktualizuj ProtonTKG ────────────────────────────────────────────
setup_protontkg() {
    mkdir -p "$BUILD_DIR"

    if [[ -d "$PROTONTKG_DIR/.git" ]]; then
        info "ProtonTKG już istnieje — aktualizuję..."
        git -C "$PROTONTKG_DIR" pull --ff-only
    else
        info "Klonuję ProtonTKG..."
        git clone --depth=1 https://github.com/Frogging-Family/wine-tkg-git.git "$PROTONTKG_DIR"
    fi
}

# ─── Build ────────────────────────────────────────────────────────────────────
build_profile() {
    local profile="$1"
    local build_name="proton-deck-${profile}"
    local cfg_src="$PROTON_PROFILES_DIR/${profile}.cfg"
    local cfg_dst="$PROTONTKG_DIR/proton-tkg/proton-tkg-userpatches/proton-tkg.cfg"

    info "Buduję profil: ${Y}$profile${NC} → $build_name"

    # Upewnij się że compat dir istnieje
    mkdir -p "$COMPAT_DIR"

    # Skopiuj wygenerowany cfg
    mkdir -p "$(dirname "$cfg_dst")"
    cp "$cfg_src" "$cfg_dst"

    # Ustaw nazwę builda
    sed -i "s|^_proton_name=.*|_proton_name=\"$build_name\"|" "$cfg_dst" 2>/dev/null || true
    sed -i "s|^_build_dir=.*|_build_dir=\"$COMPAT_DIR\"|"    "$cfg_dst" 2>/dev/null || true

    # Odpal build
    pushd "$PROTONTKG_DIR/proton-tkg" > /dev/null
    if [[ -f "proton-tkg.sh" ]]; then
        bash proton-tkg.sh install
    else
        err "Nie znaleziono proton-tkg.sh w $PROTONTKG_DIR/proton-tkg"
    fi
    popd > /dev/null

    log "Build gotowy: $COMPAT_DIR/$build_name"
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
banner
detect_hardware

# Generuj cfg dla wszystkich profili
mkdir -p "$PROTON_PROFILES_DIR"
for profile in vanilla mod online; do
    generate_cfg "$profile" "$PROTON_PROFILES_DIR/${profile}.cfg"
    log "Wygenerowano: env/proton/${profile}.cfg"
done

# Wybór profilu do zbudowania
echo
echo -e "  Wybierz co zbudować:\n"
echo -e "  ${G}[1]${NC} vanilla — max wydajność pod wykryty sprzęt (baza)"
echo -e "  ${G}[2]${NC} mod     — bez EAC/BattlEye, dla gier z modami"
echo -e "  ${G}[3]${NC} online  — EAC + BattlEye compat"
echo -e "  ${G}[4]${NC} Wszystkie trzy"
echo -e "  ${G}[5]${NC} Tylko wykryj sprzęt i wygeneruj cfg (bez budowania)"
echo
read -rp "  > " CHOICE

case "$CHOICE" in
    5)
        log "Pliki cfg zapisane w env/proton/. Możesz je edytować przed buildem."
        exit 0
        ;;
    1|2|3|4)
        setup_protontkg
        ;;
    *)
        err "Nieznana opcja."
        ;;
esac

case "$CHOICE" in
    1) build_profile "vanilla" ;;
    2) build_profile "mod"     ;;
    3) build_profile "online"  ;;
    4)
        build_profile "vanilla"
        build_profile "mod"
        build_profile "online"
        ;;
esac

echo
echo -e "  ${G}Gotowe!${NC} Buildy w: ${Y}$COMPAT_DIR${NC}"
echo -e "  Uruchom Steam — powinien wykryć nowe wersje Protona automatycznie."
echo
