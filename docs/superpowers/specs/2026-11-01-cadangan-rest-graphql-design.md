# Cadangan REST saat GraphQL kena batas — desain

Status: draf untuk persetujuan owner. Tanda **[owner]** = diputuskan owner dalam percakapan; **[saya]** = keputusan penulis desain, boleh dikoreksi. Issue: #16.

## Maksud dan alasan
Batas GraphQL GitHub (5.000 poin/jam) dipakai bersama semua alat dan sesi pada satu akun. Saat habis, skrip aicrew berhenti total:
- `scripts/pr-merge-check.sh` menolak semua merge karena gagal membaca PR (terjadi pada PR #15, 2026-11-01).
- `scripts/board.sh` gagal dengan "API rate limit already exceeded" atau "unknown owner type"; `--sync` tertunda, issue `di-integrasi` tidak tertutup, progres epic tidak bergerak, autopilot menunggu (laporan pemakai aicrew 0.6.3 di proyek Nexora).

Dua fakta yang membentuk desain (diamati 2026-11-01):
1. REST (limit `core`, 5.000/jam terpisah) tetap punya sisa saat GraphQL habis (`core` 4.969).
2. `gh api rate_limit` menyesatkan: menunjukkan sisa 4.058 saat respons GraphQL berkata `Remaining: 0`. Waktu reset yang benar ada di header `X-Ratelimit-Reset` pada respons GraphQL.

## Tujuan
- `board.sh` (termasuk `--sync`) dan `epic-link.sh` (termasuk `--check`) tetap bekerja saat GraphQL diblokir, lewat REST. **[owner]**
- `pr-merge-check.sh` tetap fail-closed; yang diperbaiki hanya pesannya (sebut batas GraphQL, waktu reset, sarankan menunggu). **[owner]**
- Tipe pemilik project (org/user) tidak lagi bergantung pada GraphQL. **[saya]**

## Non-tujuan
- Mengganti pembacaan `pr-merge-check.sh` ke REST. `closingIssuesReferences` tidak ada di REST; melewatinya membuat PR yang menutup issue `needs-security` bisa lolos. **[owner]**
- Mengurangi jumlah panggilan (cache, batching): issue terpisah. **[saya]**
- Menangani batas REST: di luar cakupan. **[saya]**

## Anti-tujuan (gagal walau tampak jalan)
- Gerbang merge yang meloloskan PR tanpa data issue-penutup.
- Loop ulang yang menghabiskan sisa kuota atau memperpanjang blokir.
- Kartu dipindah atau issue ditutup berdasarkan data REST yang tidak setara dengan data GraphQL.

## Rancangan
**Pola tunggal [saya]:** jalankan jalur GraphQL; bila gagal dan penyebabnya batas, ulangi satu kali lewat REST; bila REST juga gagal, keluar dengan pesan. Tanpa loop.

**Pustaka kecil yang di-`source` skrip [saya]**, tiga kemampuan:
- mengenali kegagalan karena batas (teks `rate limit`, `RATE_LIMIT`, `graphql_rate_limit` pada keluaran galat);
- membaca waktu reset dari header `X-Ratelimit-Reset` respons GraphQL (bukan dari `gh api rate_limit`);
- mencetak pesan seragam: batas GraphQL, jam reset (UTC), saran menunggu.

**Padanan REST [saya]; yang bertanda ✓ sudah diverifikasi 2026-11-01:**
| Kebutuhan | REST |
|---|---|
| tipe pemilik | `GET users/{owner}` → `.type` ✓ |
| daftar issue | `GET repos/{r}/issues?state=&labels=&per_page=100` (paginasi; buang entri yang punya `pull_request`) ✓ untuk bentuk respons |
| lihat/ubah/tutup issue | `GET/PATCH repos/{r}/issues/{n}` |
| sub-issue, komentar | sudah REST di skrip sekarang |
| daftar kartu project | `GET {orgs\|users}/{owner}/projectsV2/{n}/items` ✓ (`users/.../projectsV2` terbaca) |
| tambah kartu | `POST .../items` dengan `type=Issue` dan `id` = id NUMERIK issue (nomor memberi 404); 422 "Content already exists" = kartu sudah ada |
| isi Status | `PATCH .../items/{item_id}`; id kolom dan opsi dibaca dari `GET .../fields`, tidak di-hardcode |

Endpoint item/fields untuk org, perilaku 404/422, dan bentuk opsi sudah **dilaporkan diuji sungguhan** oleh sesi Nexora (org `idcloudhost`, project 2, 2026-11-01); hasilnya belum diulang di repo ini:
- `GET orgs/{org}/projectsV2/{n}` dan `.../fields` jalan tanpa GraphQL. `.name` opsi berbentuk objek `{"html","raw"}`: cocokkan lewat `.name.raw`, ambil `.id` opsi.
- `POST .../items` dengan nomor issue → 404; dengan id NUMERIK issue → sukses; kartu sudah ada → 422 "Content already exists in this project" (**dianggap sukses**, idempoten).
- Cari `item_id` lewat `GET .../items?per_page=100 --paginate` (`.content.number == N`). Kartu baru dari project tidak punya Status sampai di-PATCH.
- `PATCH .../items/{item_id}` dengan `{"fields":[{"id":<id kolom>,"value":"<id opsi sebagai string>"}]}` → 200 (dicoba pada dua kartu).
- Tidak teruji siapa pun: `users/{user}/projectsV2/...` untuk **menulis** (di repo ini hanya pembacaan daftar yang terverifikasi), penghapusan kartu, dan kolom selain Status. Builder memverifikasi jalur user sebelum mengandalkannya.
- Gejala "unknown owner type" pada `board.sh` saat GraphQL terblokir dikonfirmasi pemakai Nexora.

## Kendala
- `board.sh:55` memakai `closedByPullRequestsReferences` (GraphQL). Bila tak ada padanan REST yang setara, jalur itu **dilewati dengan peringatan** pada mode cadangan, bukan menebak. **[saya]**
- Suite tes memakai `gh` palsu; tes baru harus mensimulasikan GraphQL-limit tanpa jaringan.
- Bahasa artefak repo ini: Indonesia (komentar, commit, pesan).

## Kriteria selesai
- Dengan GraphQL disimulasikan terblokir: `board.sh --sync`, `epic-link.sh --check`, dan penambahan kartu tetap berhasil lewat REST; `pr-merge-check.sh` menolak dengan pesan yang memuat "batas GraphQL" dan jam reset.
- Tes merah dulu untuk tiap perilaku; `bash tests/run.sh` → `SEMUA LULUS`.
- Rilis patch (kandidat 0.6.4) lewat alur rilis yang ada; owner menyetujui sebelum merge. **[saya]**

## Perilaku `--sync` saat langkah dilewati **[owner]**
Pada mode cadangan, langkah yang butuh data khusus GraphQL (pemindahan kartu ke Done berdasarkan `closedByPullRequestsReferences`, `board.sh:55`) dilewati. `--sync` tetap keluar dengan **kode 0** dan mencetak `PERINGATAN: N langkah dilewati (batas GraphQL), jalankan --sync lagi setelah reset`. Alasan: sinkron idempoten dan batas ini sering terjadi, jadi autopilot tidak boleh berhenti karenanya.

## Keputusan tambahan (hasil pemeriksaan builder; semuanya **[saya]**)
- **Cakupan "jalur GraphQL".** Semua subperintah `gh` di tiga skrip itu yang berbasis GraphQL ikut dipindah: `gh issue list|view|edit|close`, `gh project ...`, dan `gh repo view`. Nama repo diambil dari `GH_REPO` atau `git remote get-url origin`, tanpa GraphQL (`gh repo view` dipakai di `board.sh:16,61`, `board-init.sh:9`, `epic-link.sh:8`).
- **Granularitas.** Deteksi per panggilan; begitu satu panggilan gagal karena batas, skrip masuk "mode cadangan" untuk sisa jalannya (panggilan berikutnya langsung REST, tanpa mencoba GraphQL lagi). Langkah sinkron bersifat idempoten (`board.sh` membandingkan status sebelum memindah), jadi jalan setengah-setengah aman diulang.
- **Pemicu.** Teks `rate limit`/`RATE_LIMIT`/`graphql_rate_limit`, dan juga `unknown owner type` (gejala batas yang tidak menyebut kata itu).
- **Waktu reset.** Satu probe `gh api graphql -i` untuk membaca `X-Ratelimit-Reset`; bila tak ada header, pesan tetap tampil tanpa jam reset.
- **Batas daftar.** REST mengikuti `--limit 200` agar peringatan `--check` tetap sama; kartu project dibaca semua halaman.
- **Scope dan izin.** Endpoint kartu butuh scope `project` seperti sekarang (`preflight.sh:26`). Bila REST kartu menjawab 403/404, operasi kartu dilewati dengan `PERINGATAN`; operasi issue tetap jalan.
- **Tes.** Fake `gh` baru yang terpisah; fake yang ada tidak diubah.
- **Keluaran.** Mode cadangan mengumumkan diri satu baris di stderr (`mode cadangan REST: batas GraphQL ...`). Tidak ada parser yang bergantung pada teks stdout `board.sh`: tes membuangnya (`tests/run.sh:444,447,501`) dan skill hanya memanggilnya.

## Diserahkan ke builder
Nama fungsi dan berkas pustaka, cara fake `gh` mensimulasikan batas, urutan pengerjaan, dan cara menangani padanan REST yang ternyata tidak setara (default aman: lewati dengan peringatan).
