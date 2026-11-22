#!/usr/bin/env bash
# aicrew docker-need (#107): apakah target tes proyek butuh Docker? Di-source oleh install-permissions.sh dan preflight.sh.
#   docker_needed <akar-repo>   exit 0 bila ada berkas compose (docker-compose*.y*ml, compose*.y*ml) di akar atau Makefile yang menyebut docker/compose.
# AICREW_DOCKER=1|0 memaksa ya/tidak (lingkungan; tanpa efek pada keamanan: hanya menambah/tidak menambah izin sempit `docker info` dan `docker compose -f <berkas> up|exec|ps|down`).
docker_needed() {
  case "${AICREW_DOCKER:-}" in 1) return 0 ;; 0) return 1 ;; esac
  local top="${1:-.}" f
  for f in "$top"/docker-compose*.y*ml "$top"/compose*.y*ml; do [ -f "$f" ] && return 0; done
  [ -f "$top/Makefile" ] && grep -qiE '(^|[^[:alnum:]_])docker([^[:alnum:]_]|$)' "$top/Makefile" && return 0
  return 1
}
