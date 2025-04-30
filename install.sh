#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

echo "====================================="
echo "  🔧 Instalace závislostí pro skript "
echo "====================================="
echo

# Kontrola, jestli běží skript jako root
if [[ "$EUID" -ne 0 ]]; then
  echo "[!] Tento skript musí být spuštěn jako root. Použij: sudo ./install.sh"
  exit 1
fi

# Aktualizace systému
echo "[+] Aktualizuji balíčky..."
apt update && apt upgrade -y

# Instalace potřebných nástrojů
echo "[+] Instaluji závislosti: nmap, parallel, graphviz, dnsutils, samba-common-bin, avahi-utils, net-tools, iproute2"
apt install -y \
  nmap \
  parallel \
  graphviz \
  dnsutils \
  samba-common-bin \
  avahi-utils \
  net-tools \
  iproute2 \
  lsb-release

# Kontrola, zda je 'flock' dostupný (součást util-linux)
if ! command -v flock &>/dev/null; then
  echo "[+] Instalace util-linux (kvůli flock)..."
  apt install -y util-linux
fi

echo "[✓] Instalace dokončena."

# Doporučení k vytvoření potřebných souborů
echo
echo "[i] Nezapomeň vytvořit:"
echo "  - soubor se seznamem rizikových portů: data/nebezpecne_porty.txt"
echo "  - soubor s OUI databází: data/oui.txt (např. z IEEE: https://standards-oui.ieee.org/oui/oui.txt)"
