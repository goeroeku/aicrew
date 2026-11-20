# Backend berjenjang: GraphQL, REST, lokal (kerja tidak berhenti karena kuota GitHub)

## Masalah
Autopilot di proyek aicenter (`aicenter-core/.aicrew/autopilot.log`, 2026-11-19/20) menghabiskan kuota GraphQL ±600-800 poin per putaran
(sisa 4789 -> 2694 dalam 4 putaran, putaran 3-4 menit), jadi habis dalam ±1 jam. Pada 22:04 `gh` gagal terbaca 5 kali beruntun dan autopilot
berhenti (`autopilot.sh` baris "gh tidak terbaca 5 kali beruntun; berhenti"). Satu token `goeroeku` dipakai bersama semua sesi dan autopilot, jadi
kuotanya diperebutkan. Pemilik ingin: pekerjaan tidak pernah berhenti karena kuota; bila GitHub habis, kerja lanjut dengan bukti lokal dan tetap
tersinkron ke GitHub setelah pulih.

## Yang sudah ada (diverifikasi di `origin/main`)
- `scripts/ghx.sh` (186 baris) sudah punya jenjang 1 -> 2 untuk issue dan kartu Project v2: `ghx_gql` menjalankan GraphQL; bila galat batas, masuk
  "mode cadangan" dan mengulang SEKALI lewat REST (`ghx_issues`, `ghx_issue_*`, `ghx_items`, `ghx_card_*`). Status mode ada di berkas sementara per
  proses (`GHX_STATE`), jadi tiap proses baru mencoba GraphQL lagi dan membayar satu panggilan gagal.
- 16 skrip memakai `ghx`; 23 skrip memanggil `gh` (127 kecocokan). `autopilot.sh` memakai `gh issue list/pr list --limit 200` mentah di 5 tempat
  (sidik jari, ringkasan putaran, `has_open_pr`, daftar PR terbuka, daftar issue terbuka), semuanya GraphQL, tanpa jenjang REST.
- Catatan di `ghx.sh`: batas GraphQL yang benar dibaca dari header respons GraphQL; angka `gh api rate_limit` bisa menyesatkan. Spec ini mengikuti
  catatan itu (probe berbiaya 1 poin, bukan `rate_limit`).

Jadi jenjang 1-2 setengah ada. Yang kurang: (a) operasi PR dan daftar di autopilot tidak lewat `ghx`; (b) status jenjang tidak bertahan antar
proses dan putaran; (c) tidak ada ETag/cache; (d) tidak ada jenjang 3 (lokal) maupun sinkron balik.

## Tujuan
1. Tiga jenjang berurutan per operasi: GraphQL -> REST -> lokal, dipilih dari status kuota yang bertahan antar proses, bukan dari kegagalan berulang.
2. Pada jenjang 3 kerja L0/L1 tetap berjalan sampai merge (bukti lokal), dan semua perubahan status tersinkron ke GitHub setelah kuota pulih.
3. Mengurangi konsumsi kuota pada keadaan normal: semua panggilan daftar autopilot lewat `ghx`, REST dengan ETag, cache dengan umur.
4. Autopilot tidak lagi berhenti karena `gh` tak terbaca; ia turun jenjang dan terus bekerja.
5. Konfigurasi: `Quota mode: auto|github|local` (bawaan `auto`). `auto` = GraphQL -> REST -> lokal dengan sinkron; `github` = tanpa jenjang lokal; `local` = mode mandiri penuh tanpa GitHub (bagian 7).

## Bukan tujuan
- Mengganti CI GitHub atau menjadikan bukti lokal setara CI independen (lihat Keamanan).
- Backend selain GitHub (GitLab, Forgejo); kerja banyak orang pada satu repo tanpa GitHub.
- Mengubah kontrak mesin: token vonis (`Laporan qa|security|perf: lulus|gagal`, `Commit:`), judul `## Daftar periksa rilis`, `## Temporary grants`,
  awalan `GAGAL:`/`PERINGATAN:`/`ok:`, penanda `blocked:`/`blocked-by-permission:`. Gerbang tetap menolak, bukan melonggar.
- Rilis, `cve-audit`, dan pembaruan dependensi pada jenjang 3: tetap butuh GitHub dan menunggu.

## Rancangan

### 1. Jenjang dan status yang bertahan
Berkas `.aicrew/backend/state.json` (ditulis atomik oleh skrip; bukan oleh agen):
`{"graphql":{"exhausted_until":<epoch|0>},"rest":{"exhausted_until":<epoch|0>},"checked":<epoch>}`.
- `ghx_tier` mengembalikan `graphql`, `rest`, atau `local`: `graphql` bila `exhausted_until` GraphQL sudah lewat; `rest` bila GraphQL habis tetapi
  REST tidak; `local` bila keduanya habis. Tanpa panggilan jaringan bila `exhausted_until` masih di masa depan.
- Menandai habis: galat batas dari `gh` (pola `ghx_is_limit` yang ada, ditambah HTTP 403/429 dengan `x-ratelimit-remaining: 0` atau `retry-after`
  untuk batas sekunder) menulis `exhausted_until` dari header `x-ratelimit-reset` (atau `retry-after`); tanpa header, +60 detik.
- Pulih: setelah `exhausted_until` lewat, satu probe (`gh api graphql -i`, 1 poin; REST `gh api rate_limit` tidak memakai kuota dan dipakai untuk REST)
  mengonfirmasi; gagal -> tulis `exhausted_until` baru.
- Probe proaktif: sebelum tiap putaran autopilot dan tiap 50 panggilan, baca `remaining` dari header respons yang sudah ada; bila di bawah
  `AICREW_QUOTA_FLOOR` (bawaan 5% dari limit), turun jenjang lebih dulu, supaya sisa kuota tersedia untuk tindakan penting (merge, komentar bukti).
- `Quota mode: github` menonaktifkan jenjang `local` (menunggu `exhausted_until` lalu lanjut; bukan berhenti). `Quota mode: local` memaksa jenjang
  `local` (kerja luring). Urutan baca: `AICREW_QUOTA_MODE`, `Quota mode:` di `docs/WORKFLOW.md`, lalu `auto`.

### 2. Cache baca dengan ETag
`.aicrew/backend/cache/<kunci>.json` + `.etag`. Daftar issue/PR (`ghx_issues`, `ghx_prs` baru) di jenjang REST memakai `If-None-Match`; 304 tidak
memotong kuota. Di jenjang `graphql` hasil juga ditulis ke cache. Di jenjang `local` baca dari cache; umur dicatat (`fetched`), dan keputusan
yang butuh data segar (merge, penutupan) ditolak bila umur melebihi `AICREW_CACHE_MAX_AGE` (bawaan 3600 detik) kecuali tindakan lokal murni.
Setiap tulisan yang sukses (jenjang 1-2) juga memperbarui cache (write-through), jadi cache tidak tertinggal dari tindakan kita sendiri.

### 3. Operasi tulis dan outbox (jenjang 3)
Jenjang 1-2: tulis langsung (perilaku sekarang). Jenjang 3: operasi ditambahkan ke `.aicrew/backend/outbox.jsonl` (append-only):
`{"id":"<uuid>","op":"label_add|label_remove|comment|issue_close|issue_body|card_set|pr_merge|...","args":{...},"ts":<epoch>,"actor":"agent"}`
dan diterapkan ke cache lokal (status terkini bagi pembaca berikutnya). Revisi dari usulan sebelumnya: jurnal ditulis hanya pada jenjang 3, bukan di
semua jenjang; write-through cache sudah menutup celah status saat peralihan, dan menulis jurnal di jenjang 1-2 hanya menambah kompleksitas.
- `scripts/backend-sync.sh` menguras outbox berurutan saat `ghx_tier` bukan `local`. Setiap operasi idempoten: label/kartu/penutupan memeriksa
  keadaan jarak jauh dulu; komentar memuat penanda `<!-- aicrew-op:<id> -->` agar tidak ganda; `pr_merge` memeriksa apakah sha sudah ada di `main`.
- Konflik: bila keadaan jarak jauh berubah dari yang diasumsikan operasi (mis. pemilik mencabut label, menutup issue, atau memberi komentar
  persetujuan), tindakan pemilik menang: operasi dilewati, dicatat di `.aicrew/backend/conflicts.log`, dan `notify.sh` dipanggil. Tidak ada
  penimpaan diam-diam.
- Pengurasan dibatasi anggaran per putaran (`AICREW_SYNC_BUDGET`, bawaan 100 operasi) agar sinkron tidak menghabiskan kuota yang baru pulih.
- Bila `outbox.jsonl` rusak (baris tak terbaca), baris itu dipindah ke `outbox.bad` dan dicatat; sisanya tetap berjalan.

### 4. Gerbang lokal (merge pada jenjang 3), diperketat setelah review
Prinsip: **gagal tertutup**. Syarat apa pun yang butuh data jaringan yang tidak bisa diverifikasi lokal MENOLAK merge (menunggu), tidak dilewati.
- **Titik masuk**: `scripts/merge-pr.sh <pr>` baru (dipanggil skill `orchestrate` menggantikan `gh pr merge` mentah di `skills/orchestrate/SKILL.md`). Jenjang 1-2:
  gerbang `pr-merge-check.sh` seperti sekarang, lalu `gh pr merge --match-head-commit`. Jenjang 3: jalur lokal di bawah. Jalur lokal dicabangkan
  SEBELUM pembacaan `gh` di awal `pr-merge-check.sh` (baris 15-16), bukan ditambahkan setelahnya.
- **Bukti jenjang 3 tidak dipercaya dari berkas**: gerbang lokal menjalankan sendiri `evidence.sh run` secara sinkron (bukan membaca berkas bukti yang
  mungkin ditulis agen lewat Bash). Berkas di `.aicrew/evidence/` hanya jejak audit. Tidak ada kunci/HMAC; ancaman yang dijaga adalah kecelakaan dan
  injeksi perintah, bukan agen berniat jahat dengan Bash (batas ini ditulis di README).
- **Jenjang tidak dipercaya dari `state.json`/env**: gerbang menentukan sendiri lewat probe langsung bahwa GraphQL DAN REST benar-benar habis (header
  `x-ratelimit-remaining: 0`, atau galat batas dari panggilan itu sendiri). `AICREW_QUOTA_MODE`, `AICREW_CACHE_MAX_AGE`, dan `state.json` diabaikan
  gerbang; konfigurasi dibaca dari `docs/WORKFLOW.md` di `main` (cabang tujuan, via `git show`), bukan dari cabang PR. Hanya `Quota mode: local`
  (mode mandiri, bagian 7) melewati probe karena memang tidak ada GitHub.
- **Sumber aturan**: `Test command:`, label risiko dari WORKFLOW.md di `main`. PR yang menyentuh `docs/WORKFLOW.md` ditolak (seperti jalur `--auto` sekarang).
- **Daftar syarat jalur lokal** (sama dengan `pr-merge-check.sh`, tidak ada yang diturunkan diam-diam):
  | Syarat | Jenjang 3 |
  |---|---|
  | Risiko L0/L1 (`risk:*`) | dari cache berumur <= 600 detik (tetap, tak dapat diubah env); lebih tua = tunggu |
  | L2, `needs-principal`, grant sementara, `Owner approval`, persetujuan perubahan tes, keputusan pemilik tertunda, `owner-hold` | tunggu (`gate.local_needs_github`); hanya terbukti di GitHub |
  | `needs-security`/`needs-perf` | tunggu (vonisnya komentar GitHub) |
  | Cek mutakhir terhadap `main` | `git fetch origin` dulu; fetch gagal = tolak |
  | Baseline-scan rahasia | dijalankan lokal pada diff (skrip lokal) |
  | CVE/OSV | dijalankan hanya bila manifest dependensi tak berubah; berubah = tunggu |
  | Tes lulus | gerbang menjalankan sendiri (lihat atas) pada hasil merge, bukan pada kepala cabang |
- **Merge diuji sebagaimana dikirim**: di worktree bersih dari `origin/main` setelah fetch, `git merge --no-ff <sha-kepala>`, lalu `Test command:` dijalankan
  PADA hasil merge itu; push (`git push origin <sha-merge>:main`, hanya fast-forward) mendorong sha yang sama. Bukti mengikat sha kepala dan sha merge.
- Push ditolak (cabang dilindungi, bukan fast-forward) -> `main` lokal tidak maju, operasi `pr_merge` tetap di outbox dan gerbang menunggu. Repo
  aicenter-core privat paket gratis tidak punya proteksi cabang (HTTP 403 "Upgrade to GitHub Pro"), jadi push langsung diizinkan di sana.
- **Setelah pulih**: CI GitHub pada `main` menjadi pemeriksa silang; merah -> `notify.sh` dan issue regresi (tanpa rollback otomatis; usulan revert
  dibuat untuk keputusan). Pada sinkron, bila GitHub kini punya `risk:L2` atau `owner-hold` untuk PR yang sudah di-merge lokal, `notify.sh` dan catatan
  konflik dibuat dengan keras (risiko sisa dari cache <= 600 detik diterima dan ditulis di README).
- Berkas di `.aicrew/backend/**` dan `.aicrew/evidence/**` dilindungi dari Edit/Write agen di `templates/autopilot-permissions.json` (pagar kecelakaan, bukan
  keamanan terhadap Bash berniat jahat).

### 5. Autopilot
- Semua `gh issue list`/`gh pr list` mentah di `autopilot.sh` diganti `ghx_issues`/`ghx_prs` (cache, ETag, jenjang). `has_open_pr` membaca daftar PR
  yang sudah diambil sekali per putaran, bukan satu panggilan per isu.
- "gh tidak terbaca 5 kali beruntun; berhenti" diganti: turun jenjang dan lanjut. Autopilot berhenti hanya bila state lokal sendiri tak terpakai
  (cache dan outbox tak terbaca) atau `Quota mode: github` dengan GitHub tak terjangkau (tidur sampai `exhausted_until`, bukan berhenti).
- Peralihan jenjang dicatat di log (`backend.tier_changed`) dan, sekali per peralihan, lewat `notify.sh`.
- Agen di dalam putaran mendapat teks: gunakan skrip `ghx`/REST dan `--json` berkolom minimal; jangan `gh` mentah berulang.

### 7. Mode `local` penuh (tanpa GitHub sama sekali)
`Quota mode: local` bukan hanya jenjang 3 saat kuota habis; ia adalah mode kerja yang berdiri sendiri, tanpa `gh`, tanpa remote, bahkan tanpa akun GitHub.
- **Penyimpanan isu lokal**: `.aicrew/issues/<n>.md` (front matter: judul, label, status, induk/epic, risiko; isi: badan isu) dan `.aicrew/issues/<n>.log`
  (komentar, termasuk vonis dan bukti, berurutan). Penomoran lokal berurutan dari `.aicrew/issues/next`. `breakdown`, `prd`, `orchestrate`, label,
  `blocked-*`, `integrated`, `awaiting-release` membaca/menulis lewat lapisan `ghx` yang sama; di mode `local` lapisan itu menunjuk ke berkas, bukan API.
- **PR = cabang lokal** (`issue-<n>`); gerbang memakai jalur lokal (bagian 4) dengan satu perbedaan: merge hanya `git merge --no-ff` ke `main` lokal,
  tanpa push (tidak ada remote yang wajib).
- **Persetujuan pemilik**: pemilik ada di mesin yang sama, jadi persetujuan (L2, grant, `Owner approval`) dicatat dengan `scripts/owner-local.sh approve
  <n> <lingkup>`, yang menolak berjalan tanpa TTY interaktif (agen tidak punya TTY) dan masuk daftar tolak izin agen; ia menulis baris bertanda
  waktu di `<n>.log` dan `.aicrew/backend/owner.log`. Pembacaan gerbang atas baris itu memakai aturan yang sama dengan komentar pemilik di GitHub
  (lingkup tepat, sha terkunci). Tanpa baris itu, L2 menunggu seperti biasa.
- **Rilis**: tag git lokal dan `CHANGELOG`; tidak ada Release GitHub.
- **Beralih ke GitHub kemudian**: `scripts/backend-attach.sh` (opsional, tahap lanjutan, di luar tiga PR pertama) mengimpor isu lokal ke GitHub
  (membuat isu, memetakan nomor lokal ke nomor GitHub di `.aicrew/issues/map.json`) lalu mode berganti ke `auto`. Selama belum dikerjakan, mode `local`
  penuh adalah satu arah: berdiri sendiri, tanpa sinkron.
- **Yang tidak tersedia**: CI silang, `cve-audit` berbasis GitHub, papan Project v2, notifikasi PR. Skrip yang butuh GitHub keluar dengan pesan
  `backend.local_unsupported` (bukan galat samar).

### 6. Pesan dan catalog
Kunci baru di `scripts/lib/msg/en.sh` dan `id.sh` dengan awalan `backend.` (peralihan jenjang, `gate.local_*`, konflik, sinkron selesai). Token mesin
tidak berubah.

## Keamanan dan batas
- Jenjang 3 tidak menurunkan syarat: hanya L0/L1, bukti terikat sha, vonis di berkas yang tak bisa ditulis agen, dan CI sebagai pemeriksa silang.
- Bukti lokal bukan independen seperti CI GitHub (mesin sama dengan penulis). Mitigasi: worktree bersih dari sha, hash keluaran, CI silang setelah
  push, L2 tak pernah lewat jenjang 3.
- `.aicrew/backend/**` dan `.aicrew/evidence/**` masuk `.gitignore` (lokal, bukan diunggah). `ensure-gitignore.sh` ditambah polanya.
- Outbox dapat memuat isi komentar yang akan dipublikasikan; tidak ada rahasia yang ditulis ke sana (aturan lama: tidak ada rahasia di komentar).
- Batas sekunder GitHub (abuse limit): `retry-after` dihormati; pengurasan outbox berurutan dengan jeda kecil (`AICREW_SYNC_PAUSE`, bawaan 1 detik).

## Tahap (empat PR, tanpa rilis sampai kata "rilis" dari pemilik)
1. **Router, status, cache, ETag**: `ghx_tier`, `state.json`, `ghx_prs`, cache baca, autopilot memakai `ghx`, penghentian "gh tidak terbaca 5 kali".
   Tes dengan `gh` palsu di PATH (galat batas GraphQL, batas REST, ETag 304, header reset). Mengurangi kuota normal; berguna sendiri.
2. **Outbox dan sinkron**: operasi tulis jenjang 3, `backend-sync.sh`, idempoten, konflik, anggaran, `notify`.
3. **Bukti lokal dan gerbang lokal**: `evidence.sh`, jalur `local` di `pr-merge-check.sh`, izin agen, `Test command:`, CI silang, dokumentasi (README,
   `templates/WORKFLOW.md`: `Quota mode:` dan `Test command:`).
4. **Mode `local` penuh**: penyimpanan isu lokal, `owner-local.sh`, `ghx` menunjuk ke berkas pada `Quota mode: local`, `backend.local_unsupported`.
   (`backend-attach.sh` untuk pindah ke GitHub: tahap terpisah, hanya bila diminta.)

## Kriteria selesai
- [ ] `ghx_tier` bertahan antar proses; satu proses baru tidak membayar panggilan gagal saat GraphQL diketahui habis.
- [ ] Tidak ada `gh issue list`/`gh pr list` mentah di `autopilot.sh`; daftar lewat `ghx` dengan ETag/cache.
- [ ] Dengan `gh` palsu yang selalu membalas batas pada GraphQL dan REST, autopilot tetap bekerja pada isu L0/L1 sampai merge lokal, dan outbox terkuras
      tepat sekali setelah `gh` palsu pulih; tidak ada operasi ganda.
- [ ] Isu L2/grant/`Owner approval` tidak pernah di-merge pada jenjang 3 (tes menolak).
- [ ] Bukti dengan sha berbeda dari kepala cabang, `rc` != 0, atau berkas bukti ditulis di luar `evidence.sh`: gerbang menolak.
- [ ] Konflik dengan tindakan pemilik dicatat dan pemilik menang.
- [ ] Tes lama lulus tanpa diubah (suite penuh, `AICREW_LANG=id`); tes baru hanya penambahan.
- [ ] Token mesin, judul, dan awalan tidak berubah.

## Keputusan saya (pemilik menyerahkan desain)
Jenjang dipilih dari status kuota yang bertahan, bukan dari kegagalan; jurnal hanya pada jenjang 3 (write-through di atasnya); L2 tidak pernah lewat
jenjang 3; push langsung ke `main` pada jenjang 3 hanya bila cabang tak dilindungi; `Quota mode:` bawaan `auto`; bukti lokal memakai worktree bersih
dan CI silang; `Test command:` baris opsional baru di `docs/WORKFLOW.md`.

## Revisi setelah review pembaca (agen reviewer independen; semua ditangani)
1. **Tabrakan nama `Backend:`** (WORKFLOW.md baris 7 sudah berarti host VCS, `cleanup.sh:43`, tes): kunci baru bernama `Quota mode:` (env `AICREW_QUOTA_MODE`).
2. **Tes lama `tests/run.sh:1683` (gh mati terus: exit 6, 5 percobaan)**: dipertahankan. Hanya galat kelas batas (kuota) yang menurunkan jenjang; galat non-batas
   (jaringan/login) tetap 5 percobaan lalu exit 6 seperti sekarang.
3. **Vonis lokal dan jalur gerbang**: `verdict_ok` hanya membaca komentar GitHub; jalur lokal tidak memakainya (gerbang menjalankan tes sendiri, bagian 4).
4. **`pr-merge-check.sh` sengaja `GHX_STATE=/dev/null`**: gerbang tetap tidak memakai status bertahan untuk jenjang 1-2; jenjang 3 ditentukan probe langsung milik gerbang.
5. **`GHX_STATE`/`GHX_REST` per proses**: tetap sebagai jalur cepat dalam proses; `state.json` adalah lapisan bertahan yang dibaca saat `ghx.sh` di-source.
6. **Header untuk `exhausted_until`**: jenjang REST memakai `gh api -i`; jalur galat tanpa header memakai probe 1 panggilan atau +60 detik. Tidak ada perubahan pada 16 skrip pengguna
   `ghx`; cakupan tahap 1 hanya `ghx.sh` dan `autopilot.sh`. `AICREW_QUOTA_FLOOR` dihitung dari header `x-ratelimit-limit`.
7. **Urutan outbox**: urutan tetap `pr_create` -> `pr_merge` -> `issue_close` -> `label_add` -> `card_set`; id kartu dicari saat sinkron via `ghx_items`, tidak disimpan di cache.
8. **Multi-proses**: penulisan `state.json`, outbox, dan cache memakai `scripts/lock.sh`; dua `backend-sync.sh` paralel dicegah kunci yang sama.
9. **Kriteria terukur**: `gh` palsu mencatat panggilan; "tepat sekali" = jumlah POST bermarka `aicrew-op:<id>` sama dengan 1. Konflik = keadaan jauh berbeda dari `expect`
   yang dicatat operasi (label dicabut dan sudah tak ada = no-op, bukan konflik; menambah label pada isu yang kini tertutup = konflik).
10. **Non-tujuan tambahan**: jenjang 3 tidak melihat isu baru dari pemilik sebelum cache disegarkan; pembuatan PR di jenjang 3 masuk outbox (`pr_create`); `state.json` dan cache
    per klon (dua mesin/klon tidak berbagi status).

11. **Catatan pelaksanaan tahap 1** (setelah review diff): status jenjang disimpan satu berkas per kunci, `.aicrew/backend/graphql.until` dan `rest.until`
    (epoch), bukan satu `state.json` (menghindari baca-ubah-tulis yang saling menimpa); nilai dibatasi sekarang+3700 detik saat dibaca. Cache REST satu berkas
    per URL (baris 1 ETag, sisanya isi; pasangan atomik) dan ETag hanya dipakai bila cache lebih muda dari `AICREW_CACHE_MAX_AGE` menit (bawaan 10). Agen
    dengan Bash tetap bisa menulis berkas ini (batas yang sama dengan bukti lokal); gerbang melepas `GHX_PERSIST` dan tidak memakainya. REST dipakai
    lebih dulu hanya saat GraphQL di bawah lantai `AICREW_QUOTA_FLOOR` (bawaan 5%) atau habis; di atas lantai tetap GraphQL (perilaku dan tes lama tidak berubah).

## Pertanyaan terbuka (butuh jawaban pemilik sebelum tahap 3)
- Push langsung ke `main` pada jenjang 3 untuk L0/L1 (tanpa review GitHub, dengan CI silang sesudahnya): pemilik menyetujui spec ini pada 2026-11-20 ("mantap saya setuju"), tahap 3 mengikutinya. Pemilik dapat mengubah keputusan ini sebelum tahap 3.
