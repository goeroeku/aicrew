# Izin sementara terstruktur dengan masa berlaku (issue #61)

## Maksud

Izin sementara dari owner (mis. "boleh merge PR risk:L2 ke cabang integrasi sampai pukul 04:00") kini teks bebas di `WORKFLOW.md`. `pr-merge-check.sh --auto`
menolak `risk:L2` tanpa melihatnya (`scripts/pr-merge-check.sh:35`), sebuah kalimat bisa disalahbaca orchestrator, dan pencabutan saat kedaluwarsa butuh skrip luar.
Hasil yang diinginkan: izin terstruktur yang dibaca skrip gerbang dari cabang tujuan, kedaluwarsa sendiri, dan tidak bisa disalahtafsirkan.

## Tujuan / bukan tujuan / anti-tujuan

Tujuan: satu jenis izin (`merge` untuk `risk:L2`) yang dibaca gerbang, dengan cabang tujuan dan kedaluwarsa wajib; kedaluwarsa dievaluasi saat gerbang memutuskan.
Bukan tujuan (sekarang): izin selain `merge`; pengganti CI oleh suite lokal (dicatat sebagai bidang yang ditolak, lihat bawah); UI; izin per-PR.
Anti-tujuan: agen memberi dirinya izin; izin yang tidak pernah habis; izin yang diam-diam melonggarkan syarat gerbang lain.

## Format (di `docs/WORKFLOW.md`, bagian `Temporary grants`)

Satu baris per izin, kunci=nilai dipisah `;`:

`- Grant: scope=merge; risk=L2; branch=integration; expires=2026-11-03T04:00:00+07:00; note=teks bebas`

- `scope` wajib, hanya `merge`. `risk` wajib, hanya `L2`. `branch` wajib, satu nama cabang persis (bukan pola; cabang bawaan ditolak, lihat Pengaman).
- `expires` wajib, ISO 8601 dengan zona waktu (`Z` atau `±HH:MM`). Tanpa zona, tak terurai, atau lebih dari 7 hari dari saat gerbang membacanya = izin tidak berlaku.
- `note` opsional, hanya dicetak. Kunci lain (termasuk `ci=...`) = baris tidak berlaku (gagal tertutup), dilaporkan sebagai peringatan.
- Baris yang tidak valid tidak pernah menjadi izin; tidak ada izin tersirat dari teks bebas.

## Perilaku gerbang

`scripts/lib/grants.sh`: `grant_allows <risk> <cabang-tujuan> <teks-WORKFLOW>` → exit 0 dan mencetak baris izin yang cocok bila ada izin sah yang belum kedaluwarsa; selain itu exit 1.
Waktu "sekarang" adalah parameter fungsi (`grant_allows <risk> <cabang> <teks> <now-epoch>`); skrip gerbang mengisinya dari `date -u +%s` dan **tidak pernah membaca variabel lingkungan** untuk waktu. Perbandingan numerik pada epoch.

`pr-merge-check.sh <pr> <cabang> --auto`: bila PR/issue berlabel `risk:L2`, alih-alih langsung menolak, ambil `docs/WORKFLOW.md` **dari cabang tujuan** (jalur REST yang sama dengan pemeriksaan CVE/Release note, `pr-merge-check.sh:87,137`) dan panggil `grant_allows L2 <cabang>`. Ada izin → lanjut ke pemeriksaan lain dan cetak
`izin sementara: <baris> (berlaku sampai <expires apa adanya>; merge sebelum itu, dan jalankan gerbang ulang tepat sebelum merge)`; tidak ada, kedaluwarsa, atau WORKFLOW tak terbaca → tolak seperti sekarang ("risk:L2: auto-merge ditolak; minta owner merge", ditambah alasan: tidak ada izin / kedaluwarsa pada ...).
Semua syarat gerbang lain tetap berlaku utuh (CI hijau, `needs-principal`/`needs-security`, bukti QA, gerbang CVE, dst.). Izin hanya mencabut penolakan `risk:L2`.

## Pengaman (inti keamanan)

1. **Dibaca dari cabang tujuan, bukan dari PR.** Izin yang ditambahkan oleh PR itu sendiri tidak terlihat karena belum ada di cabang tujuan.
2. **PR yang mengubah bagian `Temporary grants` tidak boleh di-merge otomatis.** Gerbang `--auto` menolak PR yang diff-nya menyentuh baris `Grant:` di `docs/WORKFLOW.md` (cek REST atas file PR), tanpa kecuali izin. Hanya owner yang memasukkan izin.
3. Cabang bawaan (`main`/`master`/default repo) tidak boleh menjadi `branch` izin: rilis tidak pernah lewat izin sementara.
4. Maksimum 7 hari dari saat dibaca (mencegah kedaluwarsa tahun 2099). Salah format = tidak berlaku.
5. Gerbang mencetak izin yang dipakai; laporan sesi orchestrator memuat daftar izin yang dipakai (skill `orchestrate` merujuk, tidak mengulang format).
6. Pencabutan manual: hapus baris atau ubah `expires`; berlaku pada pembacaan gerbang berikutnya.

## Perubahan kecil lain

- `templates/WORKFLOW.md`: bagian `Temporary grants` dengan contoh yang dikomentari dan peringatan "tulis hanya sebagai owner; tidak ada izin dari teks bebas".
- `skills/orchestrate`: satu kalimat — izin hanya yang terstruktur; teks bebas "izin sementara" tidak berlaku; `--auto` yang menolak L2 tetap dilaporkan apa adanya.
- README (Stability/Configuration): format dan pengaman, bahasa Inggris. Bidang `ci` (pengganti CI) sengaja belum didukung dan ditolak; dicatat di issue lanjutan, karena melonggarkan syarat gerbang lain dan butuh desain sendiri.

## Kriteria selesai (teruji)

- `grant_allows`: sah → 0; kedaluwarsa, tanpa zona, > 7 hari, kunci tak dikenal (`ci=`), `scope`/`risk` selain `merge`/`L2`, cabang bawaan, cabang berbeda → 1.
- Gerbang `--auto` dengan `risk:L2`: tanpa izin ditolak (alasan jelas); dengan izin sah lulus dan mencetak izin; izin kedaluwarsa ditolak; PR yang menambahkan baris `Grant:` ditolak walau izin lain aktif; izin hanya di PR (belum di cabang tujuan) tidak berlaku.
- `bash tests/run.sh` hijau; CI hijau.

## Diserahkan ke pembangun

Struktur fungsi, urai tanggal ISO 8601 yang portabel di bash 3.2 macOS dan Linux (tanpa GNU date), format pesan tolak, dan cara membaca daftar file PR via REST.

## Putusan setelah builder-check (hasil `aicrew-reviewer`; celah keamanan ditutup dengan pilihan paling ketat)

Putusan saya (bukan keputusan owner; owner bisa membalik):
1. **Pembaca tegas.** Hanya bagian `## Temporary grants` persis (sampai `##` berikutnya), baris `- Grant: ` di kolom 0. Diabaikan: blok kode (``` dan ~~~), komentar HTML (juga multi-baris), baris berindentasi, blockquote. Contoh di template ditulis dengan nilai sengaja tidak sah (`expires=EXAMPLE`), bukan sekadar dikomentari.
2. **Baris.** Dibagi pada `;` lalu `=` pertama; kunci ganda, spasi di sekitar `=`, karakter kontrol/CR, atau kunci tak dikenal = baris tidak sah (dilaporkan `PERINGATAN:` di stderr, tidak membatalkan baris sah lain). Ada minimal satu baris sah yang cocok = izin. `note` wajib terakhir dan tak boleh memuat `;`.
3. **Tanggal ketat:** hanya `YYYY-MM-DDTHH:MM:SS(Z|±HH:MM)`; rentang bulan/hari/jam diperiksa (kabisat, 02-30, detik 60 ditolak), zona maks ±14:00, basis desimal eksplisit (`10#`, bukan oktal), tahun 1970..2100. Tes tepi: 2026-02-29, 2024-02-29, `+14:00`, `-00:00`, `08`/`09`.
4. **Cabang.** `branch` dibandingkan persis (`[ "$a" = "$b" ]`), bukan pola. Cabang tujuan divalidasi `^[A-Za-z0-9._/-]+$` sebelum masuk URL; pembacaan WORKFLOW untuk izin memakai `ref=refs/heads/<cabang>` (bukan tag/SHA bernama sama). Cabang bawaan = `main`, `master`, dan `default_branch` repo dari REST; gagal baca = tolak.
5. **Sumber hanya REST cabang tujuan**, satu pembacaan khusus izin yang gagal tertutup (404 maupun galat = tolak), tidak memakai berkas lokal dan tidak memakai jalur `wfr` yang menelan galat.
6. **TOCTOU.** Gerbang mencetak batas waktu; skill `orchestrate` diminta menjalankan gerbang ulang tepat sebelum `gh pr merge`, dan `--after` memverifikasi basis merge sesudahnya (sudah ada).
7. **Alias Indonesia tidak ada** (`Grant:` Inggris saja; fitur baru, tak ada nama lama). `scope`/`risk` bernilai tunggal; `grant_allows` membandingkan `L2` persis.
8. **Pesan** mencetak `expires` asli (tanpa konversi zona lokal).

Diserahkan ke owner (pertanyaan di bawah): 22–25 dari builder-check.
