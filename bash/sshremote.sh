#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECK_DIR="$(dirname "$SCRIPT_DIR")"
HOSTS_FILE="$DECK_DIR/env/hosts.conf"

# Kolory
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[1;34m'; NC='\033[0m'

banner() {
    echo -e "${B}"
    echo "  ╔══════════════════════════════╗"
    echo "  ║        SSH Remote            ║"
    echo "  ╚══════════════════════════════╝"
    echo -e "${NC}"
}

# --- Załaduj hosty z pliku (opcjonalne) ---
declare -a HOST_NAMES
declare -a HOST_ADDRS

if [[ -f "$HOSTS_FILE" ]]; then
    while IFS=: read -r name addr; do
        [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue
        HOST_NAMES+=("${name// /}")
        HOST_ADDRS+=("${addr// /}")
    done < "$HOSTS_FILE"
fi

# --- Wybierz tryb ---
banner
echo -e "  Wybierz tryb:\n"
echo -e "  ${G}[1]${NC} Client  — połącz się z innym PC"
echo -e "  ${G}[2]${NC} Host    — uruchom serwer SSH na tym PC"
echo -e "  ${G}[3]${NC} Wyjście"
echo
read -rp "  > " MODE

case "$MODE" in
    1) # --- CLIENT ---
        echo
        if [[ ${#HOST_NAMES[@]} -gt 0 ]]; then
            echo -e "  Zapisane hosty:"
            for i in "${!HOST_NAMES[@]}"; do
                echo -e "  ${G}[$i]${NC} ${HOST_NAMES[$i]}  (${HOST_ADDRS[$i]})"
            done
            echo -e "  ${G}[m]${NC} Wpisz ręcznie"
            echo
            read -rp "  Wybierz hosta > " CHOICE

            if [[ "$CHOICE" == "m" ]]; then
                read -rp "  Adres (user@host lub IP): " TARGET
                read -rp "  Port [22]: " PORT
                PORT="${PORT:-22}"
                read -rp "  Użytkownik [deck]: " USER
                USER="${USER:-deck}"
                TARGET="${USER}@${TARGET}"
            else
                TARGET="${HOST_ADDRS[$CHOICE]}"
                PORT=22
                # Wyciągnij user z adresu jeśli podany
                if [[ "$TARGET" == *"@"* ]]; then
                    PORT=22
                else
                    read -rp "  Użytkownik [deck]: " USER
                    USER="${USER:-deck}"
                    TARGET="${USER}@${TARGET}"
                fi
            fi
        else
            read -rp "  Adres (user@host lub IP): " TARGET
            read -rp "  Port [22]: " PORT
            PORT="${PORT:-22}"
            if [[ "$TARGET" != *"@"* ]]; then
                read -rp "  Użytkownik [deck]: " USER
                USER="${USER:-deck}"
                TARGET="${USER}@${TARGET}"
            fi
        fi

        echo
        echo -e "  ${Y}Łączę się z:${NC} $TARGET (port $PORT)"
        echo -e "  ${Y}Ctrl+D lub exit żeby wrócić${NC}"
        echo
        ssh -p "$PORT" -o StrictHostKeyChecking=accept-new "$TARGET"
        ;;

    2) # --- HOST ---
        echo
        # Sprawdź czy sshd jest zainstalowany
        if ! command -v sshd &>/dev/null; then
            echo -e "  ${R}[ERR]${NC} sshd nie jest zainstalowany."
            exit 1
        fi

        # Pobierz aktualne IP
        LOCAL_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        SSH_PORT=22

        # Sprawdź czy sshd już działa
        if pgrep -x sshd &>/dev/null; then
            echo -e "  ${G}[OK]${NC} sshd już działa."
        else
            echo -e "  ${Y}[INFO]${NC} Uruchamiam sshd..."
            sudo systemctl start sshd 2>/dev/null || sudo sshd
        fi

        echo
        echo -e "  ${G}Serwer SSH aktywny!${NC}"
        echo -e "  Lokalny adres:  ${Y}${LOCAL_IP:-?}${NC}"
        echo -e "  Port:           ${Y}${SSH_PORT}${NC}"
        echo -e "  Użytkownik:     ${Y}$(whoami)${NC}"
        echo
        echo -e "  Drugi PC: ${B}ssh $(whoami)@${LOCAL_IP:-<IP>} -p ${SSH_PORT}${NC}"
        echo
        read -rp "  Naciśnij Enter żeby zatrzymać sshd lub Ctrl+C żeby zostawić..." _

        echo -e "  ${Y}Zatrzymuję sshd...${NC}"
        sudo systemctl stop sshd 2>/dev/null || true
        echo -e "  ${G}Gotowe.${NC}"
        ;;

    3|q|Q)
        exit 0
        ;;

    *)
        echo -e "  ${R}Nieznana opcja.${NC}"
        exit 1
        ;;
esac
