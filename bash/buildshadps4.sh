#!/usr/bin/env bash
set -euo pipefail

# buildshadps4 — clone + build shadPS4 emulator
# deps: clang cmake vulkan sdl2 openal alsa evdev udev ssl png
# out:  build/shadps4/build/shadps4

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECK_DIR="$(dirname "$SCRIPT_DIR")"
REPO_URL="https://github.com/shadps4-emu/shadPS4.git"
SRC_DIR="$DECK_DIR/build/shadps4"
BIN="$SRC_DIR/build/shadps4"

B='\033[1;34m'; G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "  ${G}✔${NC}  $*"; }
info() { echo -e "  ${B}ℹ${NC}  $*"; }
warn() { echo -e "  ${Y}⚠${NC}  $*"; }
err()  { echo -e "  ${R}✖${NC}  $*"; exit 1; }

echo -e "\n  ${B}╭──────────────────────────────────────────────────╮${NC}"
echo -e "  ${B}│${NC}  ${BOLD}🎮  shadPS4 Builder${NC}                               ${B}│${NC}"
echo -e "  ${B}╰──────────────────────────────────────────────────╯${NC}\n"

# ─── Sprawdź clang i cmake ────────────────────────────────────────────────────
command -v clang   &>/dev/null || err "clang nie zainstalowany — sudo apt install clang"
command -v cmake   &>/dev/null || err "cmake nie zainstalowany — sudo apt install cmake"
command -v git     &>/dev/null || err "git nie zainstalowany"

CLANG_VER=$(clang --version | grep -oP '\d+' | head -1)
info "clang $CLANG_VER | cmake $(cmake --version | head -1 | grep -oP '[\d.]+')"

# ─── Deps (Debian/Devuan/Ubuntu) ──────────────────────────────────────────────
install_deps() {
    info "Instaluję zależności..."
    sudo apt-get install -y \
        clang cmake git \
        libvulkan-dev vulkan-validationlayers \
        libsdl2-dev \
        libopenal-dev \
        libasound2-dev \
        libpulse-dev \
        libevdev-dev \
        libudev-dev \
        libssl-dev \
        libpng-dev \
        zlib1g-dev \
        libedit-dev \
        libjack-dev \
        libsndio-dev \
        2>/dev/null
    log "Zależności zainstalowane"
}

if [[ "${1:-}" == "--deps" ]]; then
    install_deps
fi

# ─── Wykryj -march=native ─────────────────────────────────────────────────────
CPU_MARCH=$(gcc -march=native -Q --help=target 2>/dev/null | grep "\-march=" | awk '{print $2}' || echo "native")
info "CPU: -march=$CPU_MARCH | rdzenie: $(nproc)"

# ─── Clone / update ───────────────────────────────────────────────────────────
if [[ -d "$SRC_DIR/.git" ]]; then
    info "Repo istnieje — aktualizuję..."
    git -C "$SRC_DIR" pull --ff-only
    git -C "$SRC_DIR" submodule update --init --recursive --depth=1
else
    info "Klonuję shadPS4..."
    git clone --recursive --depth=1 "$REPO_URL" "$SRC_DIR"
fi
log "Źródła: $SRC_DIR"

# ─── Configure ────────────────────────────────────────────────────────────────
info "Konfiguruję cmake..."
cmake -S "$SRC_DIR" -B "$SRC_DIR/build" \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS="-march=$CPU_MARCH -O3 -pipe" \
    -DCMAKE_C_FLAGS="-march=$CPU_MARCH -O3 -pipe" \
    -DENABLE_DISCORD_RPC=OFF \
    -DENABLE_UPDATER=OFF \
    2>&1 | grep -v "^--" | grep -v "^$" || true
log "cmake skonfigurowany"

# ─── Build ────────────────────────────────────────────────────────────────────
info "Buduję shadPS4 ($(nproc) wątków)..."
cmake --build "$SRC_DIR/build" --parallel "$(nproc)"

# ─── Weryfikacja ──────────────────────────────────────────────────────────────
if [[ -f "$BIN" ]]; then
    log "Binary: $BIN"
    VER=$("$BIN" --version 2>/dev/null | head -1 || echo "?")
    log "Wersja: $VER"
else
    err "Binary nie znaleziono po buildzie: $BIN"
fi

echo
echo -e "  ${G}${BOLD}shadPS4 zbudowany!${NC}"
echo -e "  Binary: ${DIM}$BIN${NC}"
echo -e "  Użycie: ${DIM}bash runps4${NC}"
echo
