# Skript: **Sitovy sken a topologie mapa**

Tento bash skript automatizuje proces mapování a analýzy vaší sítě. Provádí rychlý nebo detailní aktivní sken IP adres, detekuje dostupná zařízení, zjistí jejich hostname, MAC adresy, výrobce (OUI databáze), otevřené porty a volitelně i geografickou lokaci (GeoIP).

Výsledkem je:
- Podrobný textový report
- ASCII výpis v terminálu
- Grafická mapa sítě (PNG a PDF)

---

## Použití

1. **Stažení a příprava**

   Nakopírujte skript do vašeho zařízení (ideálně Linux server, Raspberry Pi, notebook).

2. **OUI databáze**

   Soubor `oui.txt` potřebný pro rozpoznávání výrobců MAC adres je již součástí projektu ve složce `data/`, inspirováno projektem: https://gist.github.com/aallan/b4bb86db86079509e6159810ae9bd3e4. Není potřeba jej stahovat.

3. **Instalace všech závislostí najednou**

   ```bash
   sudo apt update && sudo apt install -y nmap parallel graphviz dnsutils avahi-utils samba geoip-bin
   ```

4. **Spuštění**

   ```bash
   chmod +x run.sh
   ./run.sh
   ```

   Po spuštění budete vyzváni k výběru rychlosti skenu:

   - **Rychlý sken**: pouze běžné porty, bez zjišťování služeb – velmi rychlý přehled
   - **Normální sken**: základní zjištění otevřených portů a služeb – vyvážená rychlost a informace
   - **Detailní sken**: kompletní průzkum včetně verzí služeb a operačních systémů – vhodný pro hlubší analýzu

---

## Výstupy

Výsledné soubory najdete ve složce `outputs/` a logy v `log/`:

- **vystup_skenu.txt**: podrobný textový report se všemi nalezenými zařízeními, MAC adresami, službami a případně GeoIP informacemi.
- **sitova_mapa.png**: grafická mapa sítě ve formátu PNG vhodná pro rychlý vizuální přehled.
- **sitova_mapa.pdf**: mapa sítě ve formátu PDF vhodná pro tisk nebo archivaci.

---

## Závislosti

Před spuštěním je nutné mít nainstalováno:

| Program         | Popis                      | Instalace na Debian/Ubuntu                |
|-----------------|-----------------------------|-------------------------------------------|
| `nmap`          | Skenovací nástroj pro IP/porty | `sudo apt install nmap`                  |
| `parallel`      | Paralelní spouštění procesů | `sudo apt install parallel`              |
| `graphviz` (dot)| Generování grafů z DOT souborů | `sudo apt install graphviz`              |
| `dig` (bind9-utils)| Dotazy na DNS            | `sudo apt install dnsutils`               |
| `avahi-utils`   | mDNS hostname dotazy         | `sudo apt install avahi-utils`            |
| `samba`         | NetBIOS nástroje (nmblookup)  | `sudo apt install samba`                 |
| (volitelně) `geoip-bin` | GeoIP lookup       | `sudo apt install geoip-bin`              |

---

## Funkcionality

- Aktivní discovery zařízení pomocí `nmap -sn` (ping scan)
- Hostname lookup:
  - DNS (`dig`)
  - mDNS (`avahi-resolve-address`)
  - NetBIOS (`nmblookup`)
- Identifikace MAC adres a výrobců (OUI databáze)
- Zjišťování GeoIP informací pro veřejné IP adresy
- Detekce rizikových portů (FTP, Telnet, SMB, RDP, MySQL, VNC)
- Paralelní skenování více IP pomocí GNU Parallel
- Vygenerování grafické mapy sítě (PNG, PDF)

---

## Struktura projektu

```
projekt/
|— bin/
|— data/
|   — oui.txt
|— log/
|— outputs/
|   — vystup_skenu.txt
|   — sitova_mapa.png
|   — sitova_mapa.pdf
|— run.sh
|— README.md
```

---

## Poznámky

- Skript funguje nejlépe v lokálních sítích (192.168.x.x, 10.x.x.x, 172.16–31.x.x).
- Pro veřejné IP adresy jsou GeoIP dotazy omezeny dostupností služeb.
- Výstupné grafy jsou tvořeny pomocí Graphviz ("dot" jazyk).
- Soubory v `outputs/` a `log/` se případně přepíší při dalším spuštění.

---

## Autor

- Tento skript byl vytvořen za účelem efektivní analýzy domácích a firemních sítí.
- Nápady, zlepšení a reporty chyb jsou vítány!
