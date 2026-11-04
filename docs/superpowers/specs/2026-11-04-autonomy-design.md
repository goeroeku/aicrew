# Satu perintah `autonomy on/off/status` untuk izin sementara (#116)

## Masalah
Izin sementara dipasang dengan puluhan skrip `grant-*`/`expire-*` yang dijalankan owner satu per satu, di dua berkas settings, dengan proses kedaluwarsa yang harus dimatikan dan dinyalakan ulang bila tenggat berubah. #61 membuat baris izin di `docs/WORKFLOW.md` terbaca mesin; entri izin di settings masih dikelola tangan.

## Tujuan
- Satu perintah menyalakan otonomi sampai waktu tertentu; satu perintah mencabut semua yang ditambahkannya, idempoten.
- Himpunan entri tetap dan teruji; tidak pernah memuat `docker`, dan tidak pernah memberi merge ke cabang bawaan.
- `status` menunjukkan entri yang diberikan, tenggat, dan proses pembantu yang berjalan.

## Bukan tujuan
- Menyalakan autopilot, board-watch, atau pembersih worktree. Autopilot sudah punya `autostart.sh`; board-watch hanya ada di proyek hilir. `status` hanya melaporkan proses `autopilot.sh` yang berjalan. (Keputusan saya: YAGNI.)
- Docker. Himpunan tetap tidak memuat Docker sama sekali; set Docker sempit untuk target tes tertentu tetap di #107 dan memakai `--allow` manual bila owner mau (di luar lingkup).
- Mencegah agen jahat: agen hanya dihalangi lewat aturan deny (batas awalan yang sama dengan #92), bukan sandbox.

## Rancangan

### Perintah (`scripts/autonomy.sh`)
- `on <until> [--branch <cabang>] [--file <settings.json>]...` — dijalankan OWNER (mis. `! bash .../autonomy.sh on 2026-11-05T04:00:00+07:00`).
  - `<until>`: ISO8601 dengan zona, divalidasi `grant_epoch` dari `scripts/lib/grants.sh`; harus di masa depan dan paling lama 7 hari (selain itu exit 1).
  - `--branch` bawaan: nilai `Integration branch:` dari `docs/WORKFLOW.md` diekstrak seperti `cleanup.sh` (`wf-normalize.sh` lalu `sed -n 's/^[- ]*.*Integration branch: *\([A-Za-z0-9._\/-]*\).*/\1/p'`, titik/koma akhir dibuang). Ditolak (exit 1) bila kosong, `none`, placeholder `{{...}}`, sama dengan `origin/HEAD`/`main`/`master`, tidak cocok `^[A-Za-z0-9][A-Za-z0-9._/-]*$`, atau berisi `..`.
  - Kode keluar: 0 sukses, 1 ditolak (tenggat/cabang/jq atau tulis gagal = 2), 2 lingkungan (jq hilang, tulis gagal), 64 argumen salah.
  - Berkas settings bawaan `<repo>/.claude/settings.local.json`; `--file` menambah berkas lain (mis. berkas workspace orkestrator). Berkas dibuat bila belum ada.
- `off` — cabut semuanya. `status` — laporan, tidak mengubah apa pun. Argumen salah = exit 64.

### Himpunan entri tetap
`allow`: `Bash(gh pr merge:*)`, `Bash(git merge:*)`, `Bash(git rebase:*)`, dan varian `rtk ` tiap entri. Tidak ada `deny` baru dan tidak ada `gh api` (review: `gh api repos/*` memberi `PUT .../merge` dan `PATCH .../refs/heads/main`, jadi dibuang; skrip aicrew memanggil REST sendiri lewat `bash <plugin>/scripts/*`).
Daftar ini satu-satunya sumber (konstanta `AUTONOMY_ALLOW` di skrip). Tes: himpunan persis sama dengan konstanta; tak ada entri berisi `docker`, `gh api`, `push`, atau `--admin`; `on` tidak mengubah `deny`.
Keterbatasan (README): izin ini tidak terikat cabang. `gh pr merge:*` setara mode `agent-after-qa` yang sudah ada; merge yang aman ke cabang bawaan dijaga gerbang `pr-merge-check.sh --auto` (menolak PR berbasis cabang bawaan dan L2 tanpa Grant) dan deny `git push ... main`. Nilai perintah ini bukan sandbox: ia menyalakan jalur yang sama dengan mode itu untuk waktu terbatas.

### Berkas status `.aicrew/autonomy.json`
`{until, until_epoch, branch, files:[{path, backup, added_allow:[...], added_deny:[...]}], workflow:{path, line}, helper_pid}`.
- Hanya entri yang BELUM ada di berkas settings yang dicatat di `added_*`. `off` mencabut `added_*` DIKURANGI (a) apa pun yang tidak ada di konstanta `AUTONOMY_ALLOW` dan (b) entri allow template untuk mode saat ini, sehingga berkas status yang disunting tidak bisa membuat `off` menghapus entri sembarang dan `install-permissions.sh` yang dijalankan sesudah `on` tidak membuat entri templat ikut tercabut. `off` hanya menghapus baris WORKFLOW yang persis sama dengan baris yang dibuat `on` (cocok `note=autonomy.sh`).
- `on` menyimpan cadangan `<berkas>.bak-autonomy` (ditulis ulang tiap aktivasi baru; `off` menghapusnya). Tulis atomik (`.tmp` lalu `mv`). Berkas yang dibuat `on` dicatat `created:true`; `off` menghapusnya bila allow/deny-nya kosong, selain itu menyisakannya. `--file` baru pada `on` ulang mencabut berkas lama yang tak lagi disebut.
- Pemulihan adalah edit jq, bukan restore cadangan (restore akan menimpa suntingan owner): kriteria pemulihan = JSON setara (`jq -S`), bukan byte per byte. Bagian `## Temporary grants` yang dibuat `on` dicatat `created_section:true` dan dihapus `off` bila kosong.
- `.aicrew/` harus ada di `.gitignore` (`ensure-gitignore.sh` sudah menangani; tes memastikannya). `docs/WORKFLOW.md` yang diubah membuat pohon kerja kotor: owner menggabungkannya sendiri; gerbang membaca WORKFLOW dari cabang tujuan, jadi baris itu baru berlaku setelah ada di cabang tersebut atau dibaca dari checkout yang menjalankan gerbang (sama seperti #61).
- `on` saat sudah menyala: idempoten bila argumen sama (tenggat sama diperbarui, tidak menggandakan entri atau baris); tenggat baru memperbarui baris WORKFLOW, `until`, dan helper (helper lama dimatikan).

### Baris izin WORKFLOW.md
`on` menambah satu baris di bagian `## Temporary grants` (dibuat bila hilang): `- Grant: scope=merge; risk=L2; branch=<cabang>; expires=<until>; note=autonomy.sh`. Format dan pembacaan memakai `grants.sh` yang ada; `off` menghapus persis baris itu (cocok `note=autonomy.sh`). PR yang menyentuh `docs/WORKFLOW.md` tetap tidak di-merge otomatis (aturan #61), jadi owner yang menjalankan perintah. Grant `risk=L2` adalah persis mekanisme #61 yang oleh template WORKFLOW diperbolehkan sebagai pengecualian "L2 selalu owner"; `on` mencetak peringatan itu.

### Pencabutan pada waktu absolut (tahan tidur laptop)
`on` menjalankan satu helper terlepas: `autonomy.sh _expire` (subperintah internal) yang tidur `AUTONOMY_POLL` detik (bawaan 30; env hanya untuk tes dan hanya mengubah jeda, bukan sumber waktu: "sekarang" selalu `date +%s`) per putaran dan membandingkan dengan `until_epoch`, sehingga setelah laptop bangun ia mencabut pada putaran pertama dengan memanggil `off`. PID ditulis ke berkas status; sebelum mematikan helper lama, `ps -p <pid> -o command=` harus memuat `autonomy.sh` (PID dipakai ulang tidak dibunuh). `on`/`off` memakai kunci `mkdir .aicrew/autonomy.lock` (gagal = exit 1). Bila helper mati, baris `Grant:` di WORKFLOW tetap kedaluwarsa sendiri di gerbang (#61); entri settings tersisa ditandai `KEDALUWARSA, jalankan: autonomy.sh off` oleh `status` dan oleh `preflight.sh` (`AWAS`, satu baris; berkas status dibaca dengan `jq`). Cek izin merge di `preflight.sh` tidak menghitung entri yang tercatat di `added_allow` (agar tidak lulus palsu).

### Agen tidak boleh menyalakan
`templates/autopilot-permissions.json` menambah deny `Bash(*autonomy.sh on*)` dan `Bash(*autonomy.sh _expire*)` (+ varian `rtk`; pola `*` di depan menangkap `bash`, `sh`, `./`, `env`, path penuh), serta `Edit/Write` pada `.aicrew/autonomy.json`. `status` dan `off` tidak ditolak (mencabut hanya mengurangi izin dan tervalidasi seperti di atas). Batas: pencocokan awalan harness (#92) dan di Orca deny tidak ditegakkan (`preflight.sh:38` sudah memperingatkan). Tes: string deny ada, tak ada skrip atau SKILL yang menyuruh agen menjalankan `on`.

### `status`
Cetak: `autonomy: aktif sampai <until> (cabang <b>)` atau `autonomy: mati`; per berkas jumlah entri tercatat; baris WORKFLOW ada/tidak; helper `hidup (pid N)`/`mati`; proses `autopilot.sh` yang berjalan (`pgrep -f scripts/autopilot.sh`, tanpa PID sendiri; mungkin milik repo lain, diberi label); `KEDALUWARSA` bila lewat tenggat. Exit 0.

## Kriteria selesai
- [ ] `on` lalu `off` mengembalikan kedua berkas settings dan WORKFLOW.md ke isi semula (byte per byte pada tes), idempoten (dua kali `on`, dua kali `off`).
- [ ] entri milik owner yang sudah ada tidak dicabut `off`.
- [ ] himpunan tak memuat `docker`, dan `on` ditolak untuk cabang bawaan.
- [ ] `status` menampilkan entri, tenggat, PID helper; tenggat lewat = `KEDALUWARSA`.
- [ ] helper mencabut setelah `until` terlewati (tes dengan tenggat beberapa detik dan interval kecil lewat env uji).
- [ ] template menolak agen menjalankan `autonomy.sh on`.
- [ ] README dan SKILL orchestrate menjelaskan perintah, batas, dan siapa yang menjalankan.

## Keputusan saya (owner menyerahkan desain)
Tanpa board-watch/pembersih/autopilot sebagai bagian `on`; tanpa Docker; hanya ISO8601 sebagai format waktu; `--file` untuk berkas kedua alih-alih jalur tertanam; `gh api repos/*` dengan deny DELETE; helper polling 30 detik.
