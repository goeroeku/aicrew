# Kebijakan privasi aiCrew

Berlaku untuk plugin aiCrew (`goeroeku/aicrew`). Terakhir diperbarui: 2026-10-28.

**Data yang dikumpulkan: tidak ada.** aiCrew tidak memiliki server, akun, analitik, maupun telemetri. Semua berkas kerja (`docs/`, `.aicrew/`, worktree) tetap di mesin dan repositori Anda sendiri.

**Satu-satunya jaringan keluar dari plugin ini adalah notifikasi Telegram, dan hanya bila Anda mengaktifkannya.**
- Aktif hanya bila Anda mengisi token bot dan chat ID Telegram milik Anda (lewat pengaturan plugin `tg_token` dan `tg_chat`, atau variabel lingkungan `AICREW_TG_TOKEN` dan `AICREW_TG_CHAT`). Kosong berarti tidak ada yang dikirim.
- Yang dikirim ke `api.telegram.org`: satu teks notifikasi pendek (mis. "issue #N butuh keputusan") dan nama folder project. Tidak ada isi kode, isi issue, atau percakapan.
- Telegram memproses pesan itu menurut kebijakan Telegram sendiri. Token tersimpan di penyimpanan aman Claude Code (pengaturan plugin) atau di lingkungan shell Anda, bukan di repositori.

**Perintah atas nama Anda.** Skrip memanggil `git` dan `gh` terhadap repositori project Anda sendiri, memakai akun yang sudah Anda login. Tidak ada data yang dikirim ke pihak lain oleh skrip itu selain ke GitHub atau GitLab yang Anda pakai.

Pertanyaan atau masukan: https://github.com/goeroeku/aicrew/issues
