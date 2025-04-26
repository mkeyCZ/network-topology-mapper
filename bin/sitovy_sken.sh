#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# === Cesty a vystupy ===
BASE_DIR="$(dirname "$(realpath "$0")")/.."
DATA_DIR="$BASE_DIR/data"
OUT_DIR="$BASE_DIR/outputs"
OUI_DB="$DATA_DIR/oui.txt"

mkdir -p "$OUT_DIR"

OUTFILE="$OUT_DIR/vystup_skenu.txt"
DOTFILE="$OUT_DIR/sitova_mapa.dot"
IMGFILE="$OUT_DIR/sitova_mapa.png"
PDFFILE="$OUT_DIR/sitova_mapa.pdf"

# === Barvy ===
RED='\e[31m'
YELLOW='\e[33m'
GREEN='\e[32m'
NC='\e[0m'

# === Seznam rizikovych portu ===
DANGEROUS_PORTS=(21 23 445 3389 3306 5900)
KNOWN_MACS=("b8-27-eb" "dc-a6-32" "00-1a-2b")

# === Kontrola zavislosti ===
for cmd in nmap parallel dot dig; do
  command -v "$cmd" >/dev/null || { echo -e "${RED}[!] Chybi prikaz: $cmd${NC}"; exit 1; }
done

clear
echo "====================================="
echo "   \U0001F575️  SITOVY SKEN A TOPOLOGIE MAPA   "
echo "====================================="
echo "Vystup: ASCII, TXT, PNG a PDF mapa site"
echo

echo "1) Rychla     – pouze bezne porty, bez DNS"
echo "2) Normalni   – sluzby + verze (rychlejsi)"
echo "3) Detailni   – podrobne info + OS"
read -p "Volba [1-3]: " mode
case "$mode" in
  1) SCAN_OPTS="-T5 -F -n" ;;
  2) SCAN_OPTS="-T4 -sS --top-ports 50" ;;
  3) SCAN_OPTS="-T2 -sV -A" ;;
  *) echo "Neplatna volba, pouzivam normalni."; SCAN_OPTS="-T4 -sS --top-ports 50" ;;
esac

GATEWAY=$(ip route | awk '/default/ {print $3}')
SUBNET=$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | head -n1)

# Inicializace vystupu
echo "Sitova brana: $GATEWAY" > "$OUTFILE"
echo "Rozsah skenovani: $SUBNET" >> "$OUTFILE"
echo "" >> "$OUTFILE"
echo "digraph sitova_mapa {" > "$DOTFILE"
echo "  rankdir=TB;" >> "$DOTFILE"
echo "  graph [nodesep=1.0, ranksep=1.5];" >> "$DOTFILE"
echo "  node [shape=box, style=filled, fontname=Arial, fontsize=12, width=1.2];" >> "$DOTFILE"
echo "  \"$GATEWAY\" [label=\"GATEWAY\\n$GATEWAY\", color=orange];" >> "$DOTFILE"

# Barevna legenda
echo "  legend [shape=none, margin=0, label=<" >> "$DOTFILE"
echo "    <TABLE BORDER='0' CELLBORDER='1' CELLSPACING='0' CELLPADDING='4'>" >> "$DOTFILE"
echo "      <TR><TD BGCOLOR='orange'></TD><TD>Router</TD></TR>" >> "$DOTFILE"
echo "      <TR><TD BGCOLOR='yellow'></TD><TD>Switch</TD></TR>" >> "$DOTFILE"
echo "      <TR><TD BGCOLOR='lightblue'></TD><TD>Ostatni zarizeni</TD></TR>" >> "$DOTFILE"
echo "      <TR><TD BGCOLOR='red'></TD><TD>Rizikovy port</TD></TR>" >> "$DOTFILE"
echo "    </TABLE>>];" >> "$DOTFILE"

echo "[+] Skenuji sit $SUBNET ..."
mapfile -t IP_LIST < <(nmap -sn "$SUBNET" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')

echo "[+] Nalezeno ${#IP_LIST[@]} zarizeni."

sken_ip() {
  ip="$1"

  HOSTNAME=$(dig -x "$ip" +short | sed 's/\.$//')
  HOST_METHOD="DNS"
  [[ -z "$HOSTNAME" ]] && HOSTNAME=$(avahi-resolve-address "$ip" 2>/dev/null | awk '{print $2}') && HOST_METHOD="mDNS"
  [[ -z "$HOSTNAME" ]] && HOSTNAME=$(nmblookup -A "$ip" 2>/dev/null | grep '<00>' | head -n1 | awk '{print $1}') && HOST_METHOD="NetBIOS"
  [[ -z "$HOSTNAME" ]] && HOSTNAME="(bez jmena)" && HOST_METHOD="n/d"

  MAC=$(ip neigh | grep "$ip" | awk '{print $5}' | head -n1 | tr '[:upper:]' '[:lower:]')
  if [[ "$MAC" == "FAILED" || -z "$MAC" ]]; then
    MAC="neznamá"
  fi

  MAC_PREFIX=$(echo "$MAC" | cut -c1-8 | tr ':' '-')
  VYROBCE=$(grep -i "^$MAC_PREFIX" "$OUI_DB" | awk '{print $2, $3, $4, $5}' | head -n1)
  [[ -z "$VYROBCE" ]] && VYROBCE="Neznamy"

  GEO=""
  if [[ ! "$ip" =~ ^192\.168\.|^10\.|^172\.(1[6-9]|2[0-9]|3[01])\. ]]; then
    if command -v geoiplookup >/dev/null; then
      GEO=$(geoiplookup "$ip" | sed 's/GeoIP Country Edition: //')
    fi
  fi

  echo "Zarizeni: $ip" >> "$OUTFILE"
  echo "  Hostname: $HOSTNAME ($HOST_METHOD)" >> "$OUTFILE"
  echo "  MAC: $MAC" >> "$OUTFILE"
  echo "  Vyrobce: $VYROBCE" >> "$OUTFILE"
  [[ -n "$GEO" ]] && echo "  GeoIP: $GEO" >> "$OUTFILE"

  PORT_RAW=$(nmap $SCAN_OPTS "$ip")
  PORT_OUTPUT=$(echo "$PORT_RAW" | awk '/^[0-9]+\/tcp/ && /open/ {print $1, $3}')

  if [[ -n "$PORT_OUTPUT" ]]; then
    echo "  Porty:" >> "$OUTFILE"
    while read -r line; do
      [[ -n "$line" ]] && echo "    - $line" >> "$OUTFILE"
    done <<< "$PORT_OUTPUT"
  fi

  echo "" >> "$OUTFILE"

  NODE_COLOR="lightblue"
  if [[ "$ip" == "$GATEWAY" ]]; then
    NODE_COLOR="orange"
  elif [[ "$HOSTNAME" == *"router"* ]] || [[ "$VYROBCE" == *"Mikrotik"* ]] || [[ "$VYROBCE" == *"TP-Link"* ]] || [[ "$VYROBCE" == *"Asus"* ]]; then
    NODE_COLOR="orange"
  elif [[ "$HOSTNAME" == *"switch"* ]] || [[ "$VYROBCE" == *"Netgear"* ]] || [[ "$VYROBCE" == *"D-Link"* ]]; then
    NODE_COLOR="yellow"
  fi

  echo "  \"$ip\" [label=\"$HOSTNAME\\n$ip\\n$MAC\\n$VYROBCE\", color=$NODE_COLOR];" >> "$DOTFILE"
  echo "  \"$GATEWAY\" -> \"$ip\" [minlen=2];" >> "$DOTFILE"

  if [[ -n "$PORT_OUTPUT" ]]; then
    echo "  \"$ip-ports\" [label=<" >> "$DOTFILE"
    echo "    <TABLE BORDER='0' CELLBORDER='1' CELLSPACING='0' CELLPADDING='4'>" >> "$DOTFILE"
    echo "      <TR><TD><B>PORTS:</B></TD></TR>" >> "$DOTFILE"
    while read -r line; do
      if [[ -n "$line" ]]; then
        PORT=$(echo "$line" | cut -d'/' -f1)
        SERVICE=$(echo "$line" | awk '{print $2}')
        if [[ " ${DANGEROUS_PORTS[*]} " =~ " $PORT " ]]; then
          echo "      <TR><TD><FONT COLOR='red'>$PORT ($SERVICE)</FONT></TD></TR>" >> "$DOTFILE"
        else
          echo "      <TR><TD>$PORT ($SERVICE)</TD></TR>" >> "$DOTFILE"
        fi
      fi
    done <<< "$PORT_OUTPUT"
    echo "    </TABLE>>];" >> "$DOTFILE"
    echo "  \"$ip\" -> \"$ip-ports\" [style=solid, color=gray30, penwidth=2.0];" >> "$DOTFILE"
  fi
}

export -f sken_ip
export GATEWAY OUTFILE DOTFILE OUI_DB DANGEROUS_PORTS

CORES=$(nproc --ignore=1 2>/dev/null || echo 3)
echo "[+] Spoustim paralelni sken zarizeni s $CORES vlakny..."
parallel -j "$CORES" sken_ip ::: "${IP_LIST[@]}"

echo "}" >> "$DOTFILE"
dot -Tpng "$DOTFILE" -o "$IMGFILE"
dot -Tpdf "$DOTFILE" -o "$PDFFILE"

# Smazani dot souboru
rm -f "$DOTFILE"

echo ""
echo "[✓] Hotovo!"
echo "Vystupy:"
echo " - Textovy vystup: $OUTFILE"
echo " - PNG mapa:      $IMGFILE"
echo " - PDF mapa:      $PDFFILE"