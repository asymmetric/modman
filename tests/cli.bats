#!/usr/bin/env bats
# CLI tests for modman: source the script and test its functions directly
# (nothing calls nix). Run: bats tests/cli.bats
# MODMAN overrides the script under test (the flake check points it at a copy
# with patched shebangs).

setup() {
  MODMAN=${MODMAN:-$BATS_TEST_DIRNAME/../modman}
  # shellcheck source=SCRIPTDIR/../modman
  source "$MODMAN"
}

# Assert that each INPUT=EXPECTED pair normalizes as given.
assert_normalized() {
  local pair got
  for pair in "$@"; do
    got=$(normalize "${pair%%=*}")
    [[ $got == "${pair#*=}" ]] || {
      echo "${pair%%=*}: expected ${pair#*=}, got $got" >&2
      return 1
    }
  done
}

# Assert that ARGS parse to MODULE and REFRESH, with FLAKEREF x.
assert_parsed() {
  local want_module=$1 want_refresh=$2
  shift 2
  parse_args "$@"
  [[ $module == "$want_module" && $refresh == "$want_refresh" && $ref == x ]] || {
    echo "args [$*]: got module=$module refresh=$refresh ref=$ref" >&2
    return 1
  }
}

assert_usage() {
  run parse_args "$@"
  [[ $status -eq 2 && $output == *usage:* ]] || {
    echo "args [$*]: expected usage exit 2, got $status: $output" >&2
    return 1
  }
}

@test "normalize: owner/repo and host URLs" {
  assert_normalized \
    Mic92/niks3=github:Mic92/niks3 \
    Mic92/niks3/main=github:Mic92/niks3/main \
    Mic92/repo.nix/main=github:Mic92/repo.nix/main \
    https://codeberg.org/DAWO/DAWO-Sextant=git+https://codeberg.org/DAWO/DAWO-Sextant?shallow=1 \
    codeberg.org/DAWO/DAWO-Sextant=git+https://codeberg.org/DAWO/DAWO-Sextant?shallow=1 \
    github.com/Mic92/niks3=git+https://github.com/Mic92/niks3?shallow=1 \
    http://git.example.org/o/r=git+https://git.example.org/o/r?shallow=1
}

@test "normalize: flake refs and local paths pass through" {
  local r
  for r in github:Mic92/niks3 git+ssh://git@host/o/r path:/x ./foo /abs \~/x nixpkgs; do
    assert_normalized "$r=$r"
  done
}

@test "parse_args: module, --refresh and -- before and after FLAKEREF" {
  assert_parsed default '' x
  assert_parsed foo '' -m foo x
  assert_parsed foo '' x -m foo
  assert_parsed foo '' --module foo x
  assert_parsed foo '' x --module foo
  assert_parsed foo '' --module=foo x
  assert_parsed foo '' x --module=foo
  assert_parsed bar '' -m foo x --module=bar
  assert_parsed default 1 --refresh x
  assert_parsed default 1 x --refresh
  assert_parsed default '' -- x
  assert_parsed foo '' -m foo -- x
}

@test "parse_args: usage errors exit 2" {
  assert_usage
  assert_usage a/b c/d
  assert_usage -x
  assert_usage --bogus x
  assert_usage x -m
  assert_usage x --module
  assert_usage x --module=
  assert_usage -- -weird
  assert_usage -- a/b c/d
}

@test "script: no args or MODMAN_NIXPKGS unset exit 2 before calling nix" {
  run "$MODMAN"
  [[ $status -eq 2 && $output == *usage:* ]]
  MODMAN_NIXPKGS='' run "$MODMAN" x
  [[ $status -eq 2 && $output == *MODMAN_NIXPKGS* ]]
}

@test "cache_key: depends on flake, module, nixpkgs, system, modman.nix contents" {
  local f=$BATS_TEST_TMPDIR/modman.nix base
  echo a >"$f"
  base=$(cache_key flake mod np sys "$f")
  [[ $(cache_key flake mod np sys "$f") == "$base" ]]
  [[ $(cache_key flake2 mod np sys "$f") != "$base" ]]
  [[ $(cache_key flake mod2 np sys "$f") != "$base" ]]
  [[ $(cache_key flake mod np2 sys "$f") != "$base" ]]
  [[ $(cache_key flake mod np sys2 "$f") != "$base" ]]
  echo b >"$f"
  [[ $(cache_key flake mod np sys "$f") != "$base" ]]
}
