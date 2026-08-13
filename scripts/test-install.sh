#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="${repo_root}/install.sh"

fail() {
  printf 'test-install.sh: %s\n' "$*" >&2
  exit 1
}

# LIUM_VERSION controls a URL path segment. Traversal, alternate repositories,
# and malformed tags must fail before the first download.
for version in \
  '../../../../attacker-org/evil-repo/releases/download/v1' \
  '../v1.2.3' \
  'v1.2' \
  'v1.2.3/evil' \
  'v1.2.3%2f..%2fevil' \
  'release-candidate'; do
  output="$(LIUM_VERSION="${version}" bash "${installer}" 2>&1 || true)"
  [[ "${output}" == "install.sh: invalid LIUM_VERSION: ${version}" ]] ||
    fail "invalid version was not rejected before download: ${version}; output=${output}"
done

# The final main call is the only side effect at top level. A curl transfer
# truncated anywhere before it must define code but execute nothing.
truncated="$(awk '/^main "\$@"$/ { exit } { print }' "${installer}")"
output="$(bash <<<"${truncated}" 2>&1)" ||
  fail "truncated installer should parse without running"
[[ -z "${output}" ]] ||
  fail "truncated installer produced output (and may have run): ${output}"

[[ "$(awk 'NF { line = $0 } END { print line }' "${installer}")" == 'main "$@"' ]] ||
  fail 'main "$@" is not the final non-empty line'

printf 'installer security tests passed\n'
