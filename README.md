# 🕵️ Skript: **Sken a topologická mapa lokální sítě**

Tento bash skript slouží k automatizované analýze a vizualizaci vaší lokální sítě. Detekuje aktivní zařízení, jejich IP/MAC adresy, hostname, výrobce (OUI), otevřené porty a identifikuje potenciálně rizikové služby. Výstupem je jak přehledný textový report, tak i grafická topologická mapa sítě ve formátu PNG a PDF.

---

## 🖼️ Ukázka výstupu

![Ukázka síťové mapy](https://raw.githubusercontent.com/mkeyCZ/network-topology-mapper/main/screenshot/sitova_mapa_.png)

---

## ✅ Hlavní funkce

- Aktivní sken sítě pomocí `nmap` (`ping scan`, zjištění služeb a OS)
- Získání názvu zařízení z DNS, mDNS a NetBIOS
- Zjištění MAC adres a rozpoznání výrobce pomocí OUI databáze
- Detekce rizikových portů (FTP, Telnet, SMB, RDP, VNC atd.)
- Paralelní skenování zařízení pomocí `GNU Parallel`
- Automatické vytvoření síťové mapy (DOT → PNG/PDF)
- ASCII výstup v terminálu + detailní textový report

---

## 📦 Instalace

Použijte přiložený skript `install.sh`, který provede instalaci všech závislostí:

```bash
sudo ./install.sh
```

Instalační skript:

- Aktualizuje systémové balíčky
- Nainstaluje: `nmap`, `parallel`, `graphviz`, `dnsutils`, `avahi-utils`, `samba`, `iproute2`, `util-linux`
- Upozorní na vytvoření potřebných souborů (`oui.txt`, `nebezpecne_porty.txt`)

---

## 🚀 Spuštění

1. Nastavte práva:
   ```bash
   chmod +x run.sh
   ```

2. Spusťte skript:
   ```bash
   ./run.sh
   ```

3. Vyberte režim skenování:
   - **1** – Rychlý (běžné porty, bez DNS dotazů)
   - **2** – Normální (služby + porty)
   - **3** – Detailní (verze služeb + OS)

---

## 📁 Výstupy

Soubory jsou generovány do složky `outputs/`:

| Soubor               | Popis                                            |
|----------------------|--------------------------------------------------|
| `vystup_skenu.txt`   | Textový report – zařízení, MAC, výrobce, porty  |
| `sitova_mapa.png`    | Grafická síťová mapa pro vizuální přehled       |
| `sitova_mapa.pdf`    | PDF verze mapy pro tisk a archivaci             |

---

## 📂 Struktura projektu

```
projekt/
├── bin/                     # pomocné skripty (volitelné)
├── data/
│   ├── oui.txt              # OUI databáze (výrobci MAC adres)
│   └── nebezpecne_porty.txt # rizikové porty (např. 23, 445, 3306…)
├── outputs/
│   ├── vystup_skenu.txt
│   ├── sitova_mapa.png
│   └── sitova_mapa.pdf
├── run.sh                  # hlavní skript
├── install.sh              # instalační skript závislostí
└── README.md               # tento popis
```

---

## 🔧 Závislosti

| Program         | Popis                              |
|-----------------|-------------------------------------|
| `nmap`          | Aktivní sken IP a portů            |
| `parallel`      | Paralelní spouštění funkcí         |
| `graphviz`      | Vykreslení síťové topologie (DOT)  |
| `dnsutils`      | DNS dotazy (`dig`)                 |
| `avahi-utils`   | mDNS hostname dotazy               |
| `samba`         | NetBIOS hostname (`nmblookup`)     |
| `iproute2`      | Získání brány a IP rozsahu         |
| `util-linux`    | Příkaz `flock` (souborový zámek)   |

---

## 📌 Poznámky

- Funguje nejlépe v LAN sítích (např. 192.168.x.x, 10.x.x.x)
- GeoIP lokalizace není implementována ve výchozím stavu – lze snadno doplnit
- Výstupy se při každém spuštění přepíší
- Pro doplnění GeoIP lze využít `geoiplookup` nebo API službu

---

## ✍️ Autor

Projekt vznikl za účelem rychlé a přehledné analýzy domácích a menších firemních sítí. Vítány jsou jakékoliv návrhy, rozšíření nebo nahlášení chyb.
