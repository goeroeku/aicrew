# Kebijakan privasi aiCrew

Berlaku untuk plugin aiCrew (`goeroeku/aicrew`). Terakhir diperbarui: 2026-11-01.

**Data yang dikumpulkan: tidak ada.** aiCrew tidak memiliki server, akun, analitik, maupun telemetri. Semua berkas kerja (`docs/`, `.aicrew/`, worktree) tetap di mesin dan repositori Anda sendiri.

**Jaringan keluar dari plugin ini ada dua: notifikasi Telegram (hanya bila Anda mengaktifkannya) dan pemeriksaan kerentanan dependensi ke OSV (aktif secara bawaan).** (Driver Orca, `AICREW_NOTIFY=orca`, hanya memanggil biner `orca` lokal; tidak ada jaringan.)

**1. Telegram.**
- Aktif hanya bila Anda mengisi token bot dan chat ID Telegram milik Anda (lewat pengaturan plugin `tg_token` dan `tg_chat`, atau variabel lingkungan `AICREW_TG_TOKEN` dan `AICREW_TG_CHAT`). Kosong berarti tidak ada yang dikirim.
- Yang dikirim ke `api.telegram.org`: satu teks notifikasi pendek (mis. "issue #N butuh keputusan") dan nama folder project. Tidak ada isi kode, isi issue, atau percakapan.
- Telegram memproses pesan itu menurut kebijakan Telegram sendiri. Token tersimpan di penyimpanan aman Claude Code (pengaturan plugin) atau di lingkungan shell Anda, bukan di repositori.

**2. Pemeriksaan CVE (OSV), sejak 0.7.0.** `scripts/cve-check.sh` dan `scripts/cve-audit.sh` bertanya ke layanan OSV (`api.osv.dev`) apakah versi dependensi Anda punya kerentanan yang diketahui. Aktif saat PR menyentuh `package-lock.json`, `go.mod`, atau `requirements*.txt` (gerbang `pr-merge-check.sh`) dan saat Anda menjalankan skill `cve-audit`.
- Yang dikirim ke `api.osv.dev`: ekosistem (npm, Go, PyPI), nama paket, dan versi. Tidak ada isi kode, nama repositori, isi issue, atau token.
- OSV memproses permintaan itu menurut kebijakan layanan OSV sendiri. Tidak ada token atau akun.
- Mematikan: baris `Pemeriksaan CVE: tidak` di `docs/WORKFLOW.md`. Memakai cermin sendiri: variabel lingkungan `OSV_API`.

**Perintah atas nama Anda.** Skrip memanggil `git` dan `gh` terhadap repositori project Anda sendiri, memakai akun yang sudah Anda login. Tidak ada data yang dikirim ke pihak lain oleh skrip itu selain ke GitHub atau GitLab yang Anda pakai (pengecualian: pemeriksaan CVE ke OSV di atas).

Pertanyaan atau masukan: https://github.com/goeroeku/aicrew/issues
