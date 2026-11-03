# Sourced helper (#80): ci_infra_line <repo> <head-sha> prints the ci-classify owner-action line and returns 0 only when the
# check-runs of that commit are an infrastructure failure. Any error (REST, jq, classify) returns 1 = not infrastructure (fail-closed).
ci_infra_line() {
  local cr v
  cr="$(gh api "repos/$1/commits/$2/check-runs?per_page=100" 2>/dev/null)" || return 1
  v="$(printf '%s' "$cr" | bash "${here:?}/ci-classify.sh" 2>/dev/null)" || return 1
  [ "$(printf '%s\n' "$v" | head -1)" = infrastructure ] || return 1
  printf '%s\n' "$v" | sed -n 2p
}
