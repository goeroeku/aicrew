# Gerbang merge: hasil merge terhadap target terkini (#109)

## Masalah

Gerbang `pr-merge-check.sh --auto` memeriksa head PR, bukan hasil menggabungkannya ke target terkini. Dua PR yang masing-masing hijau (QA, security, CI) bisa merusak target begitu digabung berurutan: satu tes dari PR pertama memakai objek yang ditolak oleh penjaga baru dari PR kedua. Kasus lain: dua migrasi bernomor sama setelah PR lain masuk.

## Keputusan

Dua syarat baru hanya untuk `--auto` (merge manual oleh owner tidak berubah, hanya mendapat peringatan):

1. **Tidak tertinggal dari target.** `GET repos/<r>/compare/<dst>...<head>` memberi `behind_by`. `behind_by > 0` menolak dengan "PR tertinggal N commit dari <dst>; perbarui cabang (merge <dst>) lalu tunggu CI untuk head baru". Tidak terbaca atau `behind_by` bukan angka = tolak (gagal tertutup).
2. **CI hijau untuk head ini.** `GET repos/<r>/commits/<head>/check-runs` lewat `ci-classify.sh`:
   - `none` (semua selesai, tidak ada yang gagal) = lulus.
   - `code` = tolak "CI gagal untuk head".
   - `infrastructure` = tolak "CI tidak dapat mulai (infrastruktur)", bukan vonis kode, dan tidak diizinkan lolos (pengganti suite lokal butuh izin terstruktur, #61/#83, bukan bagian ini).
   - `pending` = tolak "CI belum selesai".
   - tidak ada check-run sama sekali: lulus hanya bila repo tidak punya workflow (`GET repos/<r>/actions/workflows` -> `total_count` 0); bila ada workflow, tolak "CI belum mulai" (head baru didorong, CI belum terdaftar).
   - klasifikasi/REST gagal = tolak.

Tertinggal dari target dengan CI hijau tetap ditolak: CI itu tidak membuktikan apa pun tentang target terkini. Konflik semantik (tes memakai API yang diubah PR lain) ditangkap karena PR kedua harus diperbarui dulu, sehingga CI berjalan pada kode gabungan; vonis QA/security terikat head, jadi pembaruan menuntut vonis baru (tinjauan delta murah).

## Bukan tujuan

- Gerbang tidak membangun merge di worktree sementara dan tidak menjalankan tes (menjalankan kode PR di gerbang, butuh perintah tes, lambat).
- Tidak ada jalur "CI pada merge ref dengan basis = head target": REST tidak menyebut basis merge ref sebuah run, jadi tidak dapat diverifikasi.
- Merge manual tanpa `--auto` tidak diblokir; hanya mencetak `PERINGATAN: PR tertinggal N commit dari <dst>`.

## Antarmuka

- Pesan memakai awalan `GAGAL:` seperti penolakan lain; peringatan manual memakai `PERINGATAN:`.
- Urutan: setelah pemeriksaan basis dan label, sebelum vonis QA (agar pesan "perbarui cabang" muncul lebih dulu daripada permintaan vonis untuk head yang akan berubah).

## Tes

Fake `gh` dengan `BEHIND`, `CHECKRUNS_JSON`, `WORKFLOWS_COUNT`, `COMPARE_FAIL`: tertinggal -> tolak (dengan N); sejajar + CI hijau -> lulus; `code`, `infrastructure`, `pending` -> tolak; tanpa check-run dengan/ tanpa workflow; compare/check-runs tak terbaca -> tolak; manual tidak ditolak tetapi memberi peringatan; dua PR semantik: PR kedua tertinggal -> ditolak.

## Keputusan setelah builder-check (pemeriksa tanpa konteks)

Diputuskan oleh saya (bukan owner; bisa dibalik di PR) agar gerbang tidak menolak tanpa jalan keluar:

- **PR dokumentasi saja (`nondoc=0`) dikecualikan dari kedua syarat** (tertinggal dan CI): tidak ada kode yang bisa berbenturan, workflow berfilter path tidak jalan untuknya, dan memaksa pembaruan akan menghapus vonis terikat head tanpa manfaat. Tertinggal tetap dicetak sebagai `PERINGATAN`.
- **"CI hijau" = setelah deduplikasi (run terbaru per nama check menang, supaya re-run hijau menggantikan yang gagal) tidak ada yang gagal/menunggu, dan ada minimal satu check-run `success`.** Semua `skipped`/`neutral` bukan hijau (tidak membuktikan apa pun).
- **Tidak ada check-run:** lulus hanya bila `actions/workflows` `total_count` = 0 (repo tanpa CI); jika ada workflow, tolak "CI belum mulai". Pembacaan gagal atau bukan angka = tolak.
- **Pagination:** `check-runs?per_page=100 --paginate`, digabung `jq -s`; `compare/<dst>...<head>` memakai `$dst` yang sudah divalidasi regex dan tidak ada fallback diam-diam.
- **PR dari fork** (compare/check-runs gagal) ditolak lewat jalur gagal-tertutup: auto-merge dirancang untuk cabang `issue-N` di repo yang sama.
- **Urutan:** di dalam blok `--auto`, sesudah pemeriksaan izin L2 dan sebelum pembacaan komentar/vonis (security, perf, QA), sehingga "perbarui cabang" muncul lebih dulu.
- **Keluaran `ci-classify`:** hanya baris pertama sebagai vonis; exit non-nol = tolak; untuk `infrastructure`, baris kedua (owner-action) ikut di pesan.
- Merge manual: compare gagal = tanpa peringatan (informasi saja), tidak pernah memblokir. `--after` tidak berubah.
- Akseptasi ketiga (konflik semantik) tidak dapat diuji end-to-end dengan fake: yang diuji adalah PR kedua ditolak karena tertinggal dan tes membuktikan bahwa CI hijau pada head lama tidak cukup.
