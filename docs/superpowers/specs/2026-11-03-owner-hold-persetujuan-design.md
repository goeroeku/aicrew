# Keputusan owner terstruktur: `owner-hold` dan komentar persetujuan (#114)

## Masalah
Keputusan owner berupa teks bebas, jadi orkestrator dan gerbang tidak bisa bertindak atasnya dengan andal (kasus di proyek hilir):
1. Aturan henti "mengubah tes yang ada butuh owner" hanya ada di prompt; gerbang tidak memeriksanya. Persetujuan satu kalimat umum ("yang needs-principal saya setujui") lalu dipakai ulang untuk cakupan baru.
2. Owner mengunci issue ("tahan dulu"); hanya ingatan asisten yang mencegah issue itu dilepas oleh persetujuan umum berikutnya. Autopilot hanya mengenal `needs-principal`.
3. Persetujuan bercakupan ("hanya fixture tes ini") harus disalin tangan ke tiap badan PR.

## Tujuan
- Issue berlabel `owner-hold` tidak pernah dikerjakan, tidak pernah dilepas agen, dan tidak ikut terlepas oleh perubahan massal `needs-principal`.
- PR yang mengubah berkas tes yang sudah ada ditolak gerbang (`--auto`) kecuali ada persetujuan owner yang menyebut berkas itu.
- Satu putaran dengan beberapa pertanyaan henti menghasilkan satu ringkasan owner.

## Bukan tujuan
- Mengenali pemilik komentar yang diketik agen dengan akun owner. Batas yang sama dengan #99/#110: gerbang hanya melihat `authorAssociation`, bukan siapa yang mengetik. Nilainya mencegah salah-pakai dan pergeseran cakupan, bukan agen jahat.
- Mengurai `scope-extension` dan `waiver` di gerbang. Keduanya dibaca orkestrator (SKILL), gerbang hanya menegakkan `test-change` dan `owner-hold`.
- Mengubah `needs-principal` atau label `blocked` (#108).

## Rancangan

### 1. Label `owner-hold`
- `scripts/autopilot.sh`: `is_principal` dan hitungan `n_wait` memperlakukan `owner-hold` seperti `needs-principal`/`blocked` (menunggu manusia; semua tersisa ditahan -> exit 3, bukan buntu). Issue ditahan tidak masuk set kerja putaran.
- Agen tidak boleh melepas: `templates/autopilot-permissions.json` menambah deny `gh issue edit * --remove-label owner-hold*` (dan varian `rtk`). Batas pencocokan awalan sama dengan #92, dicatat di README.
- `scripts/owner-actions.sh`: daftar item `owner-hold` dengan perintah pelepasan (`gh issue edit N --remove-label owner-hold`), terpisah dari `needs-principal`.
- Gerbang `--auto`: PR yang menutup/mengacu issue berlabel `owner-hold` ditolak. Label dibaca dari REST yang sudah dipakai gerbang (label issue tertaut). Gagal baca = gagal tertutup.
- "Tidak terlepas oleh persetujuan umum": hanya penghapusan label oleh owner yang melepas; komentar teks apa pun tidak. Tidak ada kode yang menghapus `owner-hold` (diuji: tidak ada skrip yang memuat `--remove-label owner-hold`).

### 2. Komentar persetujuan terstruktur
Bentuk (satu baris, awal komentar): `Owner approval (scope: <kind> <args>): <teks> (Commit: <sha>)`.
- `test-change <berkas>[, <berkas>...]` — dibaca gerbang. `<berkas>` jalur persis, atau awalan direktori berakhiran `/`.
- `scope-extension`, `waiver <kind>` — hanya dibaca orkestrator; gerbang mengabaikan.
- Hanya komentar dari OWNER/MEMBER/COLLABORATOR pada PR itu sendiri (bukan issue tertaut) dan belum diedit yang dihitung (sama dengan vonis, #99). Komentar berawalan mesin (`Laporan ...`, `owner-action:`, `Decision applied:`, `blocked-by-permission:`) tidak dihitung.

### 3. Pemeriksaan gerbang atas berkas tes
Dalam `--auto` PR non-docs: ambil berkas PR dari REST (sudah ada). Satu berkas dihitung "tes yang ada diubah" bila statusnya `modified`, `removed`, atau `renamed` (termasuk `previous_filename`) dan jalurnya cocok pola tes: `(^|/)(tests?|__tests__|spec)/`, `(^|/)test_[^/]*$`, atau `(_test|\.test|\.spec)\.[A-Za-z0-9]+$`. Berkas berstatus `added` tidak butuh persetujuan.
Setiap berkas itu harus tercakup satu persetujuan `test-change`. Tidak tercakup -> gerbang gagal, mencetak daftar berkas dan bentuk komentar yang dibutuhkan. Gagal baca komentar/berkas -> gagal tertutup.
Persetujuan berlaku untuk berkas yang disebut, tidak terikat head tertentu; field `(Commit: <sha>)` opsional dan informatif.

### 4. Satu ringkasan owner per putaran
`owner-actions.sh` sudah mengumpulkan semua item menunggu owner ke `.aicrew/owner-actions.md`, dan autopilot memberi satu notifikasi per keadaan. Pekerjaan: SKILL orchestrate menegaskan agen tidak membuka notifikasi sendiri-sendiri (cukup label + komentar `owner-action:`), dan tes membuktikan tiga issue `needs-principal` menghasilkan satu berkas/satu catatan.

## Keputusan owner (jawaban atas builder-check; menggantikan keputusan 1-3 di atas)
- **Cabang:** gerbang `--auto` juga menolak PR yang `headRefName` = `issue-N` bila issue N berlabel `owner-hold`, tanpa melihat kata kunci penutup.
- **Cakupan izin:** persetujuan `test-change` hanya dihitung bila ditulis di PR itu sendiri (bukan issue tertaut) dan belum diedit (`updated_at` = `created_at`). Tidak terikat commit; awalan direktori harus berakhiran `/`.
- **Pola tes:** daftar tetap, tak peka huruf, diperluas dengan `*Test.java`, `*_spec.rb`, `tests.py`, `testdata/`, `__snapshots__/`, `e2e/`. Tanpa konfigurasi baru.

## Putusan setelah builder-check (pilihan saya)
- `Owner approval (scope: ...)` ditambahkan ke filter `machine` blok #110, supaya persetujuan tidak dianggap keputusan owner baru yang menuntut `Decision applied:`. Tes: persetujuan + vonis lulus + tanpa ack -> lolos.
- Cetakan `--remove-label owner-hold` di `owner-actions.sh` tetap (perintah untuk owner). Tes "tidak ada yang menghapus" mencari pemanggilan `gh issue edit ... --remove-label owner-hold` yang dieksekusi skrip, bukan teks cetakan.
- Deny permission: varian `--remove-label=owner-hold` dan `rtk` ditambah; batas pencocokan awalan (urutan flag, `bash -c`, daftar label berkoma) ditulis di README.
- "Tes yang ada diubah" = status apa pun selain `added`; cek `filename` dan `previous_filename` (rename masuk jalur tes dihitung). Daftar berkas diakumulasi lintas halaman, bukan dicek di dalam loop halaman.
- Penguraian komentar: baris mana pun, tak peka huruf, argumen kosong = menyetujui nol berkas; komentar issue dimuat sekali di awal.
- `owner-hold` memakai `$labels` yang sudah ada (label PR + issue tertaut), hanya menolak di `--auto` (merge manual owner tidak diblokir, seperti #109).
- "Satu catatan" = satu pemanggilan `note` per keadaan. Tes: semua issue `owner-hold` -> exit 3; campuran `owner-hold` + `needs-principal`. Teks "semuanya needs-principal" dan `has_open_pr`/`unsat_blockers` di autopilot ikut diperbarui.

## Kriteria selesai
- [ ] issue `owner-hold`: autopilot melewatinya tiap putaran; semua tersisa ditahan -> exit 3
- [ ] tidak ada skrip yang menghapus `owner-hold`; deny permission terpasang
- [ ] gerbang menolak PR yang mengubah berkas tes yang ada tanpa persetujuan yang menyebutnya; menerima dengan persetujuan; berkas baru tidak butuh
- [ ] persetujuan dari non-OWNER/MEMBER/COLLABORATOR atau berawalan mesin tidak dihitung
- [ ] gerbang menolak PR yang menutup issue `owner-hold`
- [ ] tiga issue `needs-principal` -> satu `owner-actions.md` dan satu catatan
- [ ] gerbang menolak PR bercabang `issue-N` bila issue N ber-`owner-hold`, tanpa kata kunci penutup
- [ ] persetujuan yang diedit, atau di issue tertaut, tidak dihitung
- [ ] rename dari jalur tes tercakup persetujuan atas nama lama atau baru
- [ ] `release-report.sh` menganggap issue `owner-hold` terbuka sebagai menunggu owner
