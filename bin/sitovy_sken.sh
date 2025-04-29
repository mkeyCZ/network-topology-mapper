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

OUTFILE_RAW="$OUT_DIR/vystup_skenu_raw.txt"
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

# === Inicializace výstupů ===
echo "Síťová brána: $GATEWAY" > "$OUTFILE_RAW"
echo "Rozsah skenování: $SUBNET" >> "$OUTFILE_RAW"
echo "" >> "$OUTFILE_RAW"

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

  {
    echo "Zařízení: $ip"
    echo "  Hostname: $HOSTNAME"
    echo "  MAC: $MAC"
    echo "  Výrobce: $VYROBCE"
  } >> "$OUTFILE_RAW"

  PORT_RAW=$(nmap $SCAN_OPTS "$ip")
  PORT_OUTPUT=$(echo "$PORT_RAW" | awk '/^[0-9]+\/tcp/ && /open/ {print $1, $3}')

  while read -r line; do
    [[ -n "$line" ]] && echo "    - ${line//// }" >> "$OUTFILE_RAW"
  done <<< "$PORT_OUTPUT"

  echo "" >> "$OUTFILE_RAW"
}

export -f sken_ip
export OUTFILE_RAW OUI_DB DANGEROUS_PORTS

CORES=$(nproc --ignore=1 2>/dev/null || echo 3)
echo "[+] Spouštím paralelní skenování s $CORES vlákny..."
parallel -j "$CORES" sken_ip ::: "${IP_LIST[@]}"

# === Označení rizikových portů ===
cp "$OUTFILE_RAW" "$OUTFILE"
for port in "${DANGEROUS_PORTS[@]}"; do
  sed -i "s/^    - $port /    - [!RIZIKO!] $port /" "$OUTFILE"
done

# === Generování .dot souboru ===
echo "digraph sitova_mapa {" > "$DOTFILE"
echo "  rankdir=TB;" >> "$DOTFILE"
echo "  graph [nodesep=1.0, ranksep=1.5];" >> "$DOTFILE"
echo "  node [shape=box, style=filled, fontname=Arial, fontsize=12, width=1.2];" >> "$DOTFILE"
echo "  \"$GATEWAY\" [label=\"GATEWAY\\n$GATEWAY\", color=orange];" >> "$DOTFILE"

echo "  legend [shape=none, margin=0, label=<" >> "$DOTFILE"
echo "    <TABLE BORDER='0' CELLBORDER='1' CELLSPACING='0' CELLPADDING='4'>" >> "$DOTFILE"
echo "      <TR><TD BGCOLOR='orange'></TD><TD>Router</TD></TR>" >> "$DOTFILE"
echo "      <TR><TD BGCOLOR='yellow'></TD><TD>Switch</TD></TR>" >> "$DOTFILE"
echo "      <TR><TD BGCOLOR='lightblue'></TD><TD>Ostatní zařízení</TD></TR>" >> "$DOTFILE"
echo "    </TABLE>>];" >> "$DOTFILE"

current_ip=""
current_hostname=""
current_mac=""
current_vyrobce=""
declare -a current_ports=()

while read -r line; do
  if [[ "$line" =~ ^Zařízení:\ (.+)$ ]]; then
    if [[ -n "$current_ip" ]]; then
      echo "  \"$current_ip-ports\" [label=<" >> "$DOTFILE"
      echo "    <TABLE BORDER='0' CELLBORDER='1' CELLSPACING='0' CELLPADDING='4'>" >> "$DOTFILE"
      echo "      <TR><TD><B>PORTY:</B></TD></TR>" >> "$DOTFILE"
      for p in "${current_ports[@]}"; do
        echo "      <TR><TD>$p</TD></TR>" >> "$DOTFILE"
      done
      echo "    </TABLE>>];" >> "$DOTFILE"
      echo "  \"$current_ip\" -> \"$current_ip-ports\" [style=solid, color=gray30, penwidth=2.0];" >> "$DOTFILE"
    fi
    current_ip="${BASH_REMATCH[1]}"
    current_ports=()
  elif [[ "$line" =~ ^\ {2}Hostname:\ (.+)$ ]]; then
    current_hostname="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^\ {2}MAC:\ (.+)$ ]]; then
    current_mac="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^\ {2}Výrobce:\ (.+)$ ]]; then
    current_vyrobce="${BASH_REMATCH[1]}"
    label="$current_hostname\\n$current_ip\\n$current_mac\\n$current_vyrobce"
    echo "  \"$current_ip\" [label=\"$label\", color=lightblue];" >> "$DOTFILE"
    echo "  \"$GATEWAY\" -> \"$current_ip\" [minlen=2];" >> "$DOTFILE"
  elif [[ "$line" =~ ^\ {4}-\ (.+)$ ]]; then
    current_ports+=("${BASH_REMATCH[1]}")
  fi
done < "$OUTFILE"

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
