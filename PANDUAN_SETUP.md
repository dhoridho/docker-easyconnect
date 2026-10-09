# Panduan Setup EasyConnect Docker & Solusi Tidak Bisa Buka Google / Internet

Repositori ini menggunakan dockerized Sangfor EasyConnect (`hagb/docker-easyconnect`) dengan wrapper script `ec.sh` otomatis untuk mengatasi masalah DNS, routing, dan cleanup iptables.

---

## 1. Kenapa EasyConnect Konek tapi Google / Internet Luar Mati?

Ini adalah penyakit klasik Sangfor EasyConnect di Linux. Ada 2 penyebab utama:

### Penyebab 1: DNS dibajak oleh ECAgent (Paling Sering)
* **Gejalanya**: VPN status konek, ping ke IP server kantor bisa, tapi buka `google.com`, `github.com`, atau website publik lainnya selalu gagal / timeout / `server IP address could not be found`.
* **Penyebab teknis**: Begitu EasyConnect connect, daemon internalnya (`ECAgent`) memasang rule iptables NAT secara paksa:
  ```bash
  # ECAgent membajak semua traffic port 53 (DNS) ke port lokal 5373 miliknya:
  iptables -t nat -A OUTPUT -p udp --dport 53 -j DNAT --to-destination 127.0.0.1:5373
  ```
  Namun port 5373 tersebut **tidak bisa meresolve domain publik** (hanya bisa meresolve domain internal kantor atau bahkan blackhole total sebelum session stabil).
* **Solusi otomatis di repo ini**:
  Script `ec.sh` sudah memiliki background daemon `_guard_dns` yang berjalan otomatis:
  - Tiap detik mengecek apakah rule iptables NAT pembajak port 53 ini muncul.
  - Jika internet luar (seperti Google/Claude) gagal di-resolve karena rule tersebut, `_guard_dns` langsung **menghapus rule pembajak itu secara otomatis** dan mem-flush cache DNS.
  - Internet Google langsung lancar kembali tanpa memutus koneksi VPN kantor!

* **Solusi manual jika tidak pakai script `ec.sh`**:
  Hapus rule NAT DNAT tersebut secara manual:
  ```bash
  sudo iptables -t nat -D OUTPUT -p udp ! --sport 7789 --dport 53 -j DNAT --to-destination 127.0.0.1:5373
  sudo resolvectl flush-caches
  ```

---

### Penyebab 2: Default Route (Default Gateway) Ditimpa VPN Kantor
* **Gejalanya**: Ping IP publik seperti `8.8.8.8` atau `1.1.1.1` RTO / Request Timed Out (bukan cuma DNS).
* **Penyebab teknis**: Server Sangfor VPN kantor Anda tidak mengaktifkan split-tunneling dari sisi server, sehingga VPN memaksa semua lalu lintas PC (`0.0.0.0/0`) masuk ke interface `tun0`. Jika firewall kantor tidak mengizinkan akses internet keluar lewat VPN mereka, internet publik Anda akan putus total.
* **Cara Cek**:
  ```bash
  ip route show
  ```
  Jika melihat `default dev tun0` atau route `0.0.0.0/1 dev tun0` dan `128.0.0.0/1 dev tun0`:
* **Solusi Split-Tunnel (Kembalikan Default Route)**:
  Kembalikan default gateway ke interface WiFi/LAN lokal Anda:
  ```bash
  # 1. Cari default gateway asli (misal WiFi wlan0 / eth0)
  ip route | grep -v tun0

  # 2. Hapus route catch-all yang dilempar ke tun0 jika ada:
  sudo ip route del 0.0.0.0/1 dev tun0 2>/dev/null || true
  sudo ip route del 128.0.0.0/1 dev tun0 2>/dev/null || true

  # 3. Pastikan hanya subnet kantor yang lewat tun0 (contoh: 10.x.x.x atau 172.16.x.x):
  sudo ip route add 10.0.0.0/8 dev tun0
  ```

---

## 2. Cara Setup di Laptop Teman (Ubuntu / Debian / Mint)

### Prasyarat
1. Docker & Docker Compose sudah terpasang.
2. Kernel module `tun` aktif:
   ```bash
   sudo modprobe tun
   ```

### Langkah Instalasi Cepat

1. **Clone repo atau ekstrak zip**:
   ```bash
   git clone https://github.com/dhoridho/docker-easyconnect
   cd docker-easyconnect
   ```

2. **Jalankan script setup**:
   ```bash
   bash setup.sh
   source ~/.bashrc
   ```

3. **Konfigurasi file `.env`**:
   Buka file konfigurasi di `~/Docker/EasyConnect/.env`:
   ```bash
   nano ~/Docker/EasyConnect/.env
   ```
   Isi data VPN kantor Anda:
   ```env
   DISPLAY=:0
   SVPN_HOST=https://vpn.kantor.co.id:port/
   VPN_USER=username_kamu
   VPN_PASS=password_kamu
   CLIP_TEXT=password_kamu
   ```

4. **Jalankan EasyConnect**:
   ```bash
   ec up
   ```
   - Jendela GUI Sangfor EasyConnect akan muncul di layar.
   - Masukkan alamat VPN dan login seperti biasa.
   - Password sudah otomatis tersimpan di clipboard berkat `CLIP_TEXT`, tinggal `Ctrl + V`.
   - Setelah status "Connected", Anda bisa meminimize atau menutup jendela (koneksi tetap jalan di background).

5. **Matikan EasyConnect**:
   ```bash
   ec down
   ```
   *(Perintah ini otomatis membersihkan iptables, menghapus interface `tun0`, dan memulihkan DNS host normal).*

---

## 3. Shortcut Perintah CLI (`ec`)

Perintah `ec` bisa dijalankan langsung dari terminal manapun:

| Command | Fungsi |
|---|---|
| `ec up` | Menjalankan VPN (GUI) + mengaktifkan DNS Guard otomatis |
| `ec down` | Mematikan VPN dan me-reset iptables & DNS host ke kondisi semula |
| `ec toggle` | Switch On/Off VPN (cocok untuk shortcut keyboard / panel toggle) |
| `ec status` | Cek status container, koneksi `tun0`, dan keepalive |
| `ec fix` | **P3K Jaringan**: Gunakan jika internet host bermasalah/nyangkut setelah crash |
| `ec logs` | Melihat log output container EasyConnect |
| `ec restart` | Restart container VPN |

---

## 4. Opsi Alternatif: Mode SOCKS5 Proxy (Tanpa Ganggu Sistem Host)

Jika teman Anda **hanya butuh buka Web ERP / Odoo / Intranet di Browser**, dan tidak ingin routing sistem laptop tersentuh VPN sama sekali:

1. Buka `docker-compose.yml`, matikan `network_mode: host` dan gunakan port mapping:
   ```yaml
   services:
     easyconnect:
       image: hagb/docker-easyconnect:latest
       container_name: easyconnect
       ports:
         - "127.0.0.1:1080:1080" # SOCKS5 Proxy
         - "127.0.0.1:8888:8888" # HTTP Proxy
       environment:
         - DISPLAY=:0
       volumes:
         - /tmp/.X11-unix:/tmp/.X11-unix:rw
         - ~/.easyconnect-data:/root/conf
   ```
2. Jalankan `docker compose up -d easyconnect`.
3. Di browser (Chrome/Firefox), pasang ekstensi **FoxyProxy** atau **SwitchyOmega**:
   - Proxy: SOCKS5 `127.0.0.1`, port `1080`.
   - Rule: Hanya arahkan URL internal kantor ke proxy tersebut.
4. Dengan cara ini, Google, YouTube, Zoom, dan internet laptop tetap 100% menggunakan koneksi normal Anda tanpa pernah bentrok dengan EasyConnect.
