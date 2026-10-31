---
name: prd
description: Use after brainstorming with the owner to write the PRD from the agreed discussion, using templates/PRD.md, and get owner approval. Run before aicrew:breakdown.
---

# aicrew prd

Menulis PRD dari hasil diskusi/brainstorming. Bahasa Indonesia. Tidak menulis kode.

## Aturan
- Bila belum ada diskusi/brainstorming untuk project ini, lakukan dulu (skill `brainstorming`), jangan menebak.
- Bila PRD sudah ada (lihat `WORKFLOW.md` → `PRD:`), jangan menimpa: tampilkan celahnya terhadap templat dan usulkan perubahan.
- Tiap kebutuhan wajib punya ID dan kriteria yang bisa diuji. Kriteria tidak bisa ditulis → masuk "Pertanyaan terbuka" dan tanyakan owner.
- Tandai keputusan sulit dibalik (skema DB, bentuk API, auth, uang) sebagai kandidat `needs-principal`.
- **Journeys**: saat diskusi, tanyakan "apa yang bisa dilakukan pengguna setelah ini selesai?" dan isi bagian *Journeys* (satu baris per hasil yang dipahami lead) serta *Kebutuhan non-fungsional* dari jawabannya.
  Tiap kebutuhan (R-ID) harus masuk minimal satu journey, atau ditandai `infrastruktur` (mis. CI, migrasi) bila memang tidak melayani journey. Journey tanpa kebutuhan = celah: tanyakan owner.
- Jangan mengarang kebutuhan yang tidak dibahas; yang diasumsikan ditulis sebagai asumsi.

## Langkah
1. Baca `docs/WORKFLOW.md` (profil, lokasi PRD). Tidak ada → **jalur draf**: tulis PRD dari diskusi ke `docs/PRD.md`
   dengan `Status: draf`, JANGAN minta persetujuan, lalu arahkan ke `/aicrew:kickoff` (yang melengkapi lokasi dan
   status). Setelah `WORKFLOW.md` ada, jalankan `prd` lagi hanya untuk persetujuan (langkah 4).
2. Isi `${CLAUDE_PLUGIN_ROOT}/templates/PRD.md` dari diskusi; simpan ke path PRD di `WORKFLOW.md`.
3. Profil `penuh`: minta agen `aicrew-reviewer` memeriksa PRD (read-only, tanpa konteks percakapan); bawa temuan serius ke owner.
4. Tampilkan ringkasan (bukan seluruh dokumen) dan minta persetujuan. Setelah disetujui: ubah `Status:` di PRD
   dan `Status PRD: disetujui` di `WORKFLOW.md`. Hanya owner yang menyetujui.
5. Lanjut ke `/aicrew:breakdown`.
