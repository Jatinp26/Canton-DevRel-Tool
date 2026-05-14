#!/usr/bin/env bats
# _fetch_onboarding_secret mints a one-time DevNet onboarding token from the
# SV's prepare endpoint. The body is opaque (a base64 JSON envelope) and the
# helper must return it verbatim, fail loudly on non-200, and fail loudly on
# transport errors. Curl is stubbed so the test stays hermetic.
load ../test_helper

setup() {
  TMPHOME="$(mktemp -d)"
  # Source the lib via a wrapper so we can stub curl before any call.
  source "$REPO_DIR/scripts/lib/common.sh"
  source "$REPO_DIR/scripts/lib/validator.sh"
}
teardown() { rm -rf "$TMPHOME"; unset -f curl; }

_stub_curl() {
  # Stub mimics `curl -o <file> -w '%{http_code}' …` — writes body to the -o
  # file and prints the status code to stdout, like the real flag combination.
  local body="$1" code="$2" exitcode="${3:-0}"
  eval "curl() {
    local out=\"\"
    while [ \$# -gt 0 ]; do
      case \"\$1\" in
        -o) out=\"\$2\"; shift 2;;
        *) shift;;
      esac
    done
    [ -n \"\$out\" ] && printf '%s' '$body' > \"\$out\"
    printf '%s' '$code'
    return $exitcode
  }"
}

@test "_fetch_onboarding_secret returns the body verbatim on HTTP 200" {
  _stub_curl "eyJzcG9uc29yaW5nU3Yi==" 200
  run _fetch_onboarding_secret
  [ "$status" -eq 0 ]
  [ "$output" = "eyJzcG9uc29yaW5nU3Yi==" ]
}

@test "_fetch_onboarding_secret fails on HTTP 503" {
  _stub_curl "service unavailable" 503
  run _fetch_onboarding_secret
  [ "$status" -ne 0 ]
  echo "$output" | grep -q '503'
}

@test "_fetch_onboarding_secret fails on empty body even with HTTP 200" {
  _stub_curl "" 200
  run _fetch_onboarding_secret
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'empty'
}

@test "_fetch_onboarding_secret fails when curl exits non-zero (network error)" {
  _stub_curl "" 000 7
  run _fetch_onboarding_secret
  [ "$status" -ne 0 ]
}

@test "_fetch_onboarding_secret hits the documented endpoint path" {
  # Verify the URL the helper requests, by having the stub record it.
  local recorder="$TMPHOME/url.log"
  eval "curl() {
    while [ \$# -gt 0 ]; do
      case \"\$1\" in
        -o) shift 2;;
        http*) echo \"\$1\" > '$recorder'; shift;;
        *) shift;;
      esac
    done
    printf '200'
    return 0
  }"
  # The stub writes nothing to the -o file → body is empty → helper exits 1,
  # but the URL was still recorded.
  _fetch_onboarding_secret || true
  grep -q '/api/sv/v0/devnet/onboard/validator/prepare$' "$recorder"
}

@test "_fetch_onboarding_secret honors SV_SPONSOR_HOST_URL override" {
  local recorder="$TMPHOME/url.log"
  eval "curl() {
    while [ \$# -gt 0 ]; do
      case \"\$1\" in
        -o) shift 2;;
        http*) echo \"\$1\" > '$recorder'; shift;;
        *) shift;;
      esac
    done
    printf '200'
    return 0
  }"
  SV_SPONSOR_HOST_URL='http://other-host:1234' _fetch_onboarding_secret || true
  grep -q '^http://other-host:1234/api/sv/v0/devnet/onboard/validator/prepare$' "$recorder"
}
