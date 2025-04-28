#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# === Cesty a výstupy ===
BASE_DIR="$(dirname "$(realpath "$0")")/.."
DATA_DIR="$BASE_DIR/data"
OUT_DIR="$BASE_DIR/outputs"
OUI_DB="$DATA_DIR/oui.txt"
DANGEROUS_PORTS_FILE="$DATA_DIR/nebezpecne_porty.txt"
LOCKFILE="$OUT_DIR/.dotfile.lock"

mkdir -p "$OUT_DIR"

OUTFILE="$OUT_DIR/vystup_skenu.txt"
DOTFILE="$OUT_DIR/sitova_mapa.dot"
IMGFILE="$OUT_DIR/sitova_mapa.png"
PDFFILE="$OUT_DIR/sitova_mapa.pdf"

# === Načtení rizikových portů ===
if [[ ! -f "$DANGEROUS_PORTS_FILE" ]]; then
  echo "[!] Soubor $DANGEROUS_PORTS_FILE nenalezen!"
  echo "[!] Vytvoř prosím soubor a napiš do něj rizikové porty (jeden port na řádek)."
  exit 1
fi

mapfile -t DANGEROUS_PORTS < "$DANGEROUS_PORTS_FILE"

# === Kontrola závislostí ===
for cmd in nmap parallel dot dig flock; do
  command -v "$cmd" >/dev/null || { echo "[!] Chybí příkaz: $cmd"; exit 1; }
done

clear
echo "====================================="
echo "   🕵️  SÍŤOVÝ SKEN A TOPOLOGICKÁ MAPA  "
echo "====================================="
echo "Výstup: ASCII, TXT, PNG a PDF mapa sítě"
echo

echo "1) Rychlý     – pouze běžné porty, bez DNS"
echo "2) Normální   – služby + verze (rychlejší)"
echo "3) Detailní   – podrobné info + OS"
read -p "Volba [1-3]: " mode
case "$mode" in
  1) SCAN_OPTS="-T5 -F -n" ;;
  2) SCAN_OPTS="-T4 -sS --top-ports 50" ;;
  3) SCAN_OPTS="-T2 -sV -A" ;;
  *) echo "Neplatná volba, používám normální."; SCAN_OPTS="-T4 -sS --top-ports 50" ;;
esac

GATEWAY=$(ip route | awk '/default/ {print $3}')
SUBNET=$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | head -n1)

# Inicializace výstupů
echo "Síťová brána: $GATEWAY" > "$OUTFILE"
echo "Rozsah skenování: $SUBNET" >> "$OUTFILE"
echo "" >> "$OUTFILE"
echo "digraph sitova_mapa {" > "$DOTFILE"
echo "  rankdir=TB;" >> "$DOTFILE"
echo "  graph [nodesep=1.0, ranksep=1.5];" >> "$DOTFILE"
echo "  node [shape=box, style=filled, fontname=Arial, fontsize=12, width=1.2];" >> "$DOTFILE"
echo "  \"$GATEWAY\" [label=\"GATEWAY\\n$GATEWAY\", color=orange];" >> "$DOTFILE"

# === Legenda ===
echo "  legend [shape=none, margin=0, label=<" >> "$DOTFILE"
echo "    <TABLE BORDER='0' CELLBORDER='1' CELLSPACING='0' CELLPADDING='4'>" >> "$DOTFILE"
echo "      <TR><TD BGCOLOR='orange'></TD><TD>Router</TD></TR>" >> "$DOTFILE"
echo "      <TR><TD BGCOLOR='yellow'></TD><TD>Switch</TD></TR>" >> "$DOTFILE"
echo "      <TR><TD BGCOLOR='lightblue'></TD><TD>Ostatní zařízení</TD></TR>" >> "$DOTFILE"
echo "      <TR><TD></TD><TD>[!RIZIKO!] označuje rizikový port</TD></TR>" >> "$DOTFILE"
echo "    </TABLE>>];" >> "$DOTFILE"

echo "[+] Skenuji síť $SUBNET ..."
mapfile -t IP_LIST < <(nmap -sn "$SUBNET" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')

echo "[+] Nalezeno ${#IP_LIST[@]} zařízení."

sken_ip() {
  ip="$1"

  HOSTNAME=$(dig -x "$ip" +short | sed 's/\.$//')
  HOST_METHOD="DNS"
  [[ -z "$HOSTNAME" ]] && HOSTNAME=$(avahi-resolve-address "$ip" 2>/dev/null | awk '{print $2}') && HOST_METHOD="mDNS"
  [[ -z "$HOSTNAME" ]] && HOSTNAME=$(nmblookup -A "$ip" 2>/dev/null | grep '<00>' | head -n1 | awk '{print $1}') && HOST_METHOD="NetBIOS"
  [[ -z "$HOSTNAME" ]] && HOSTNAME="(bez jména)" && HOST_METHOD="n/d"

  MAC=$(ip neigh | grep "$ip" | awk '{print $5}' | head -n1 | tr '[:upper:]' '[:lower:]')
  [[ "$MAC" == "FAILED" || -z "$MAC" ]] && MAC="neznámá"

  MAC_PREFIX=$(echo "$MAC" | cut -c1-8 | tr ':' '-')
  VYROBCE=$(grep -i "^$MAC_PREFIX" "$OUI_DB" | awk '{print $2, $3, $4, $5}' | head -n1)
  [[ -z "$VYROBCE" ]] && VYROBCE="Neznámý"

  GEO=""
  if [[ ! "$ip" =~ ^192\.168\.|^10\.|^172\.(1[6-9]|2[0-9]|3[01])\. ]]; then
    if command -v geoiplookup >/dev/null; then
      GEO=$(geoiplookup "$ip" | sed 's/GeoIP Country Edition: //')
    fi
  fi

  {
    echo "Zařízení: $ip"
    echo "  Hostname: $HOSTNAME ($HOST_METHOD)"
    echo "  MAC: $MAC"
    echo "  Výrobce: $VYROBCE"
    [[ -n "$GEO" ]] && echo "  GeoIP: $GEO"
  } >> "$OUTFILE"

  PORT_RAW=$(nmap $SCAN_OPTS "$ip")
  PORT_OUTPUT=$(echo "$PORT_RAW" | awk '/^[0-9]+\/tcp/ && /open/ {print $1, $3}')

  NODE_COLOR="lightblue"
  if [[ "$ip" == "$GATEWAY" ]]; then
    NODE_COLOR="orange"
  elif [[ "$HOSTNAME" == *"router"* ]] || [[ "$VYROBCE" == *"Mikrotik"* ]] || [[ "$VYROBCE" == *"TP-Link"* ]] || [[ "$VYROBCE" == *"Asus"* ]]; then
    NODE_COLOR="orange"
  elif [[ "$HOSTNAME" == *"switch"* ]] || [[ "$VYROBCE" == *"Netgear"* ]] || [[ "$VYROBCE" == *"D-Link"* ]]; then
    NODE_COLOR="yellow"
  fi

  {
    echo "  \"$ip\" [label=\"$HOSTNAME\\n$ip\\n$MAC\\n$VYROBCE\", color=$NODE_COLOR];"
    echo "  \"$GATEWAY\" -> \"$ip\" [minlen=2];"

    if [[ -n "$PORT_OUTPUT" ]]; then
      echo "  \"$ip-ports\" [label=<"
      echo "    <TABLE BORDER='0' CELLBORDER='1' CELLSPACING='0' CELLPADDING='4'>"
      echo "      <TR><TD><B>PORTS:</B></TD></TR>"

      while read -r line; do
        if [[ -n "$line" ]]; then
          PORT=$(echo "$line" | cut -d'/' -f1)
          SERVICE=$(echo "$line" | awk '{print $2}')
          FINAL_LABEL="$PORT ($SERVICE)"
          for dp in "${DANGEROUS_PORTS[@]}"; do
            if [[ "$PORT" == "$dp" ]]; then
              FINAL_LABEL="[!RIZIKO!] $PORT ($SERVICE)"
              break
            fi
          done
          echo "      <TR><TD>$FINAL_LABEL</TD></TR>"
          echo "    - $FINAL_LABEL" >> "$OUTFILE"
        fi
      done <<< "$PORT_OUTPUT"

      echo "    </TABLE>>];"
      echo "  \"$ip\" -> \"$ip-ports\" [style=solid, color=gray30, penwidth=2.0];"
    fi
  } | flock "$LOCKFILE" tee -a "$DOTFILE" > /dev/null

  echo "" >> "$OUTFILE"
}

export -f sken_ip
export GATEWAY OUTFILE DOTFILE OUI_DB DANGEROUS_PORTS LOCKFILE

CORES=$(nproc --ignore=1 2>/dev/null || echo 3)
echo "[+] Spouštím paralelní skenování s $CORES vlákny..."
parallel -j "$CORES" sken_ip ::: "${IP_LIST[@]}"

echo "}" >> "$DOTFILE"
dot -Tpng "$DOTFILE" -o "$IMGFILE"
dot -Tpdf "$DOTFILE" -o "$PDFFILE"

rm -f "$LOCKFILE"

echo ""
echo "[✓] Hotovo!"
echo "Výstupy:"
echo " - Textový výstup: $OUTFILE"
echo " - PNG mapa:       $IMGFILE"
echo " - PDF mapa:       $PDFFILE"

