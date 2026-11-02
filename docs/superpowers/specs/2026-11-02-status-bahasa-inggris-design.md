# Status autopilot, nama mesin berbahasa Inggris, dan audit bahasa (#66)

## Tujuan
Permukaan teknis aiCrew berbahasa Inggris (arahan owner, #55/#64): kunci dan nilai `autopilot.json`, nama aksi `resume.sh`. Nama lama tetap terbaca sepanjang 1.x (alias usang, hapus hanya di mayor). `autopilot.json` juga memberi tahu apa yang sedang dikerjakan dan apa yang terakhir selesai.

## Bukan tujuan
- Prosa pesan dan tag log (`PERINGATAN`, `AWAS`, `GAGAL`) tidak diubah: log dan pesan bukan antarmuka publik (README, Stability) dan jadi bagian #64 (1.4.0). Tag-tag itu dipakai ratusan baris tes.
- Tidak mengubah nama berkas `.aicrew/*` atau kode keluar.
- Tidak mengamati peran/issue di luar apa yang terbaca dari `gh` (skrip tidak tahu isi sesi model).

## Keputusan
1. **`autopilot.json`** ditulis dengan DUA set kunci dalam satu objek: baru `phase`, `round`, `idle_seconds`, `heartbeat`; lama `fase`, `putaran`, `idle_sejak_detik`, `detak` (isi sama). Nilai `phase` bahasa Inggris: `running` (lama `putaran`), `idle-interrupted` (`idle-diinterupsi`), `waiting-owner` (`menunggu-owner`), `sleeping-limit` (`tidur-limit`), `done` (`selesai`); `stuck` dan `gh-down` tetap. Nilai `fase` tetap nama lama. Sumber kebenaran di kode: satu tabel pemetaan.
2. **`current`** (larik) dan **`last_completed`** (objek atau `null`) ditambahkan. `current` = issue berlabel `in-progress` pada awal putaran, tiap elemen `{"issue":N,"role":"role:qa"|null}` (role dari label `role:*` pertama). `last_completed` = PR ter-merge terbaru yang terlihat oleh ringkasan putaran (#91): `{"pr":N,"merged_at":"ISO8601"}`; dipertahankan antar putaran (disimpan di `.aicrew/last-completed.json`), `null` bila belum ada. Perubahan keduanya dicatat satu baris di `autopilot.log` (`putaran N: sedang dikerjakan: ...`, `putaran N: terakhir selesai: ...`). Kunci tambahan ini baru; konsumen lama mengabaikannya.
3. **`resume.sh`**: kolom 2 memakai nama Inggris `finish-merge`, `continue-pr`, `check-branch`, `requeue`, `check-release`; kolom 4 (baru) memuat nama lama (`selesaikan-merge`, ...). Skill `orchestrate` memetakan kedua nama ke langkah yang sama dan menyebut nama lama sebagai alias usang.
4. **Tes penjaga bahasa**: memindai kunci JSON yang ditulis (`jq -n '{...}'` di skrip), nilai fase, nama aksi, dan nama label bawaan terhadap daftar token Indonesia (`fase`, `putaran`, `detak`, `selesaikan`, `lanjut-pr`, ...) dengan daftar izin eksplisit untuk alias usang yang didokumentasikan. Prosa tidak dipindai.
5. **Preflight**: mode merge `agent-after-qa` tanpa aturan `Bash(gh pr merge` naik dari `info` ke `AWAS`; izin baca di luar repo (`Read(<basis worktree>/...)`) disebut bila hilang. Selebihnya sudah dikerjakan #88.
6. **README**: bagian Stability mencatat kunci/nama baru dan bahwa yang lama adalah alias usang sampai mayor berikutnya.

## Urutan PR
A: (1)+(2) `autopilot.json`. B: (3) `resume.sh` dan skill. C: (4) tes penjaga. D: (5) preflight. README disentuh oleh tiap PR bagiannya.

## Keputusan tambahan (hasil pemeriksaan pembangun)
- **"Isi sama"** berarti setara lewat tabel pemetaan; `stuck` dan `gh-down` bernilai sama di `phase` dan `fase`. Alias dihapus paling cepat di rilis mayor berikutnya.
- **`current`** dihitung di awal tiap iterasi loop dari `$open` (label sudah ada di sana), disimpan di variabel dan ditulis oleh setiap `set_phase`; saat fase bukan `running` nilainya tetap yang terakhir dihitung, dan `[]` pada fase `done`. Urutan dengan `board_sync` tidak berpengaruh.
- **`role`** = label `role:*` pertama dalam urutan abjad; `null` bila tidak ada. Awalan `role:` tetap.
- **`last_completed`** = PR ter-merge terbaru yang terlihat oleh `round_summary` pada putaran itu (PR yang digabung selama putaran, bukan "terbaru secara umum"); disimpan di `.aicrew/last-completed.json`, dipertahankan antar putaran dan antar start ulang; gh gagal = nilai lama dipertahankan; `--reset-total` tidak menyentuhnya. `autopilot.json` memuatnya pada `set_phase` berikutnya setelah ringkasan ditulis.
- **`resume.sh`**: baris `<issue>\t<aksi-Inggris>\t<detail>\t<aksi-lama>`; kolom 4 aman diabaikan; skill memakai nama Inggris sebagai kunci utama dan menyebut nama lama sebagai alias usang; komentar kepala skrip diperbarui. Tes lama diubah memeriksa kolom 2 (baru) dan kolom 4 (lama). Tabel pemetaan resume terpisah dari tabel fase (dua skrip, dua tabel kecil).
- **Tes penjaga**: daftar token terlarang = `fase putaran detak idle_sejak selesaikan lanjut-pr periksa-cabang periksa-rilis antre-ulang menunggu-owner tidur-limit idle-diinterupsi`; memindai `scripts/*.sh` pada baris tanpa penanda `alias-usang` (baris tabel pemetaan diberi komentar itu). Label bawaan seperti `menunggu-rilis` sudah punya alias terdokumentasi dan dikecualikan lewat daftar izin eksplisit.
- **Preflight (butir 5)** tidak mengganti tag; hanya menaikkan tingkat satu baris yang sudah ada. Kriteria: mode `agent-after-qa` tanpa aturan `gh pr merge` -> baris `AWAS`; mode `owner` -> tetap `info`. **README (butir 6)** diuji dengan `grep` pada kunci baru.

## Dibiarkan ke pembangun
Bentuk fungsi pemetaan, nama berkas sementara, urutan kunci JSON.

## Kriteria
- Tes dengan sesi palsu: `autopilot.json` memuat kunci lama dan baru bernilai sama saat putaran, menunggu owner, tidur limit, selesai; `current` memuat issue berlabel in-progress beserta role; `last_completed` bertahan antar putaran.
- `resume.sh` mencetak nama baru di kolom 2 dan nama lama di kolom 4 untuk kelima aksi; tes lama tetap lulus lewat kolom 4.
- Tes penjaga gagal bila token Indonesia baru muncul di kunci/nilai/aksi di luar daftar izin.
