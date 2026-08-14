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

# Windows shells (Git Bash / MSYS2 / Cygwin) must resolve to the .exe release
# asset. Shim uname (to report a Windows kernel) and curl (to record the URL and
# stop before any download), so the OS/arch -> asset mapping is exercised with no
# network access.
for uname_s in MINGW64_NT-10.0 MSYS_NT-10.0 CYGWIN_NT-10.0; do
  shim="$(mktemp -d)"
  cat >"${shim}/uname" <<SHIM
#!/usr/bin/env bash
case "\$1" in
  -s) printf '%s\n' '${uname_s}' ;;
  -m) printf '%s\n' 'x86_64' ;;
esac
SHIM
  cat >"${shim}/curl" <<'SHIM'
#!/usr/bin/env bash
for arg in "$@"; do
  case "${arg}" in https://*) printf '%s\n' "${arg}" >>"${CURL_LOG}" ;; esac
done
exit 22
SHIM
  chmod +x "${shim}/uname" "${shim}/curl"
  export CURL_LOG="${shim}/urls"
  : >"${CURL_LOG}"
  PATH="${shim}:${PATH}" bash "${installer}" >/dev/null 2>&1 || true
  grep -q '/lium\.windows-amd64\.exe$' "${CURL_LOG}" ||
    fail "windows shell ${uname_s} did not request the .exe asset; urls=$(cat "${CURL_LOG}")"
  unset CURL_LOG
  rm -rf "${shim}"
done

printf 'installer security tests passed\n'
