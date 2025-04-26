#!/bin/bash

# === Nastavení cest ===
cd "$(dirname "$0")"

# === Zajištění potřebných složek ===
mkdir -p outputs

# === Přehledné spuštění hlavního skeneru ===
echo "====================================="
echo "  🚀 Spouštím síťový skener a mapu..."
echo "====================================="

# === Spustí hlavní skript a uloží log ze spuštění ===
bash bin/sitovy_sken.sh | tee log/sken_log_$(date +%F_%H-%M).txt

echo ""
echo "====================================="
echo " ✅ Sken dokončen. Výstupy najdeš ve složce outputs/ "
echo "====================================="

