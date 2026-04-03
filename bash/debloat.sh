#!/bin/bash
# Debloat script - run after SteamOS updates
BLOAT="kate okular gwenview cups cups-pdf orca espeak-ng maliit-keyboard ibus ibus-anthy ibus-hangul ibus-pinyin ibus-table ibus-table-cangjie-lite noto-fonts-cjk podman distrobox strace renderdoc-minimal lib32-renderdoc-minimal gpu-trace drm_janitor umr bats evtest f3 xterm xbindkeys xdotool xorg-xwininfo rxvt-unicode-terminfo partitionmanager filelight ffmpegthumbs spectacle flatpak-kcm tk dos2unix steamos-devkit-service wireguard-tools openvpn networkmanager-openvpn kdeconnect dolphin ark discover"

TO_REMOVE=""
for pkg in $BLOAT; do
    if pacman -Qi "$pkg" &>/dev/null; then
        TO_REMOVE="$TO_REMOVE $pkg"
    fi
done

if [ -n "$TO_REMOVE" ]; then
    pacman -R --noconfirm $TO_REMOVE
fi
