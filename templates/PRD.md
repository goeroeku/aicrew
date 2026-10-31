# PRD — {{nama project}}

Status: {{draf | disetujui owner pada YYYY-MM-DD}}

## Masalah dan pengguna
{{siapa, masalah apa, kenapa sekarang — maks 5 baris}}

## Tujuan dan non-tujuan
- Tujuan: {{hasil yang diukur}}
- Non-tujuan (sengaja tidak dikerjakan): {{...}}

## Kebutuhan
Tiap kebutuhan punya ID tetap dan kriteria yang bisa diuji mesin atau diamati.

| ID | Kebutuhan | Kriteria diterima (bisa dicek) | Prioritas |
|---|---|---|---|
| R1 | {{...}} | {{tes/perintah/halaman yang membuktikan}} | {{must/should}} |

## Journeys
Apa yang bisa dilakukan pengguna, dalam bahasa yang dipahami lead. Tiap journey menjadi satu epic saat breakdown.
Satu kebutuhan boleh melayani lebih dari satu journey.

| ID | Journey | Kebutuhan (R-ID) | Selesai bila |
|---|---|---|---|
| J1 | {{pengguna dapat masuk dengan SSO}} | {{R3, R4}} | {{hasil yang bisa diamati}} |

## Kebutuhan non-fungsional
| ID | Kebutuhan | Kriteria diterima (bisa dicek) | Label |
|---|---|---|---|
| N1 | {{login merespons < 1 s}} | {{uji beban / pengukuran}} | {{needs-perf / needs-security}} |

## Batasan
Stack, kinerja, keamanan/otorisasi, data, biaya, tenggat: {{...}}

## Risiko dan keputusan sulit dibalik
{{skema DB, bentuk API, auth, uang — tandai yang butuh `needs-principal`}}

## Pertanyaan terbuka
{{daftar; kosongkan sebelum status disetujui, atau tandai eksplisit sebagai diterima}}

## Peta issue (diisi oleh breakdown)
{{R-ID / N-ID → #issue, gelombang, journey (J-ID → #epic)}}
