#!/usr/bin/env bats
# CLI tests for modman, run against a stub `nix` (tests/nix-stub).
#
#   bats tests/cli.bats
#
# MODMAN overrides the script under test (the flake check points it at a copy
# with patched shebangs).

setup() {
  MODMAN=${MODMAN:-$BATS_TEST_DIRNAME/../modman}

  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/rt"
  ln -s "$BATS_TEST_DIRNAME/nix-stub" "$BATS_TEST_TMPDIR/bin/nix"
  PATH=$BATS_TEST_TMPDIR/bin:$PATH

  export STUB_LOG=$BATS_TEST_TMPDIR/nix.log
  export STUB_PAGE=$BATS_TEST_TMPDIR/page.5
  : >"$STUB_LOG"

  export MODMAN_NIXPKGS=/nix/store/fake-nixpkgs
  export MODMAN_SYSTEM=x86_64-linux
  export MODMAN_NIX=$BATS_TEST_DIRNAME/../modman.nix
  export XDG_RUNTIME_DIR=$BATS_TEST_TMPDIR/rt

  # Set by the /tmp fallback tests when they create /tmp/modman-$UID.
  tmp_cache=
}

teardown() {
  if [[ -n $tmp_cache ]]; then
    rm -rf "$tmp_cache"
  fi
}

# Run modman with an empty log and an empty cache.
fresh() {
  : >"$STUB_LOG"
  rm -rf "$XDG_RUNTIME_DIR/modman"
  run "$MODMAN" "$@"
}

# Ref passed to the last `nix flake metadata`.
metadata_ref() {
  grep '^flake metadata ' "$STUB_LOG" | tail -n 1 | awk '{ print $NF }'
}

# Value of `--argstr NAME VALUE` in the last `nix build`.
argstr() {
  local want=$1 line
  line=$(grep '^build ' "$STUB_LOG" | tail -n 1)
  # shellcheck disable=SC2086 # split the logged command line into words
  set -- $line
  while [[ $# -ge 3 ]]; do
    if [[ $1 == --argstr && $2 == "$want" ]]; then
      printf '%s\n' "$3"
      return 0
    fi
    shift
  done
  return 1
}

builds() {
  grep -c '^BUILD$' "$STUB_LOG" || true
}

# Assert that INPUT is resolved as REF (metadata) and displayed as REF (name).
assert_normalized() {
  local input=$1 expected=$2
  fresh "$input"
  if [[ $status -ne 0 ]]; then
    echo "$input: exit $status: $output" >&2
    return 1
  fi
  local got_meta got_name
  got_meta=$(metadata_ref)
  got_name=$(argstr name)
  if [[ $got_meta != "$expected" || $got_name != "$expected" ]]; then
    echo "$input: expected $expected, got metadata=$got_meta name=$got_name" >&2
    return 1
  fi
}

assert_usage() {
  fresh "$@"
  if [[ $status -ne 2 || $output != *usage:* ]]; then
    echo "args [$*]: expected usage exit 2, got $status: $output" >&2
    return 1
  fi
  # Nothing reached nix.
  [[ ! -s $STUB_LOG ]]
}

assert_module() {
  local expected=$1
  shift
  fresh "$@"
  if [[ $status -ne 0 ]]; then
    echo "args [$*]: exit $status: $output" >&2
    return 1
  fi
  local got
  got=$(argstr module)
  if [[ $got != "$expected" ]]; then
    echo "args [$*]: expected module $expected, got $got" >&2
    return 1
  fi
}

# --- normalization -----------------------------------------------------------

@test "owner/repo[/branch] becomes github:" {
  assert_normalized Mic92/niks3 github:Mic92/niks3
  assert_normalized Mic92/niks3/main github:Mic92/niks3/main
  assert_normalized Mic92/repo.nix/main github:Mic92/repo.nix/main
}

@test "host URLs become git+https:" {
  assert_normalized https://codeberg.org/DAWO/DAWO-Sextant git+https://codeberg.org/DAWO/DAWO-Sextant?shallow=1
  assert_normalized codeberg.org/DAWO/DAWO-Sextant git+https://codeberg.org/DAWO/DAWO-Sextant?shallow=1
  assert_normalized github.com/Mic92/niks3 git+https://github.com/Mic92/niks3?shallow=1
  assert_normalized http://git.example.org/o/r git+https://git.example.org/o/r?shallow=1
}

@test "flake refs and local paths pass through" {
  local ref
  for ref in github:Mic92/niks3 git+ssh://git@host/o/r path:/x ./foo /abs nixpkgs; do
    assert_normalized "$ref" "$ref"
  done
}

@test "build gets the locked ref as flake and the unlocked one as name" {
  fresh Mic92/niks3
  [ "$status" -eq 0 ]
  [ "$(argstr flake)" = 'github:Mic92/niks3?locked=1' ]
  [ "$(argstr name)" = github:Mic92/niks3 ]
  [ "$(argstr nixpkgs)" = /nix/store/fake-nixpkgs ]
  [ "$(argstr system)" = x86_64-linux ]
}

@test "system falls back to nix config show system" {
  unset MODMAN_SYSTEM
  fresh Mic92/niks3
  [ "$status" -eq 0 ]
  grep -qx 'config show system' "$STUB_LOG"
  [ "$(argstr system)" = x86_64-linux ]
}

# --- options -----------------------------------------------------------------

@test "module defaults to default" {
  assert_module default Mic92/niks3
}

@test "-m, --module NAME and --module=NAME before and after FLAKEREF" {
  assert_module foo -m foo Mic92/niks3
  assert_module foo Mic92/niks3 -m foo
  assert_module foo --module foo Mic92/niks3
  assert_module foo Mic92/niks3 --module foo
  assert_module foo --module=foo Mic92/niks3
  assert_module foo Mic92/niks3 --module=foo
  # Last one wins.
  assert_module bar -m foo Mic92/niks3 --module=bar
}

@test "--refresh before and after FLAKEREF is passed to flake metadata" {
  fresh --refresh Mic92/niks3
  [ "$status" -eq 0 ]
  grep -qx 'flake metadata --json --refresh github:Mic92/niks3' "$STUB_LOG"

  fresh Mic92/niks3 --refresh
  [ "$status" -eq 0 ]
  grep -qx 'flake metadata --json --refresh github:Mic92/niks3' "$STUB_LOG"
}

@test "no --refresh: flake metadata without --refresh" {
  fresh Mic92/niks3
  [ "$status" -eq 0 ]
  grep -qx 'flake metadata --json github:Mic92/niks3' "$STUB_LOG"
}

@test "-- ends option parsing" {
  fresh -- Mic92/niks3
  [ "$status" -eq 0 ]
  [ "$(metadata_ref)" = github:Mic92/niks3 ]

  fresh -m foo -- Mic92/niks3
  [ "$status" -eq 0 ]
  [ "$(metadata_ref)" = github:Mic92/niks3 ]
  [ "$(argstr module)" = foo ]
}

@test "usage errors exit 2" {
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

@test "MODMAN_NIXPKGS unset exits 2" {
  unset MODMAN_NIXPKGS
  fresh Mic92/niks3
  [ "$status" -eq 2 ]
  [[ $output == *MODMAN_NIXPKGS* ]]
  [ "$(builds)" -eq 0 ]
}

@test "nix flake metadata failure is fatal" {
  # Replace the stub with one that always fails.
  printf '#!/bin/sh\nexit 1\n' >"$BATS_TEST_TMPDIR/bin/nix-fail"
  chmod +x "$BATS_TEST_TMPDIR/bin/nix-fail"
  ln -sf "$BATS_TEST_TMPDIR/bin/nix-fail" "$BATS_TEST_TMPDIR/bin/nix"
  fresh Mic92/niks3
  [ "$status" -ne 0 ]
  [ ! -e "$STUB_PAGE" ]
}

# --- cache -------------------------------------------------------------------

@test "second run is served from the cache" {
  run "$MODMAN" Mic92/niks3
  [ "$status" -eq 0 ]
  [ "$(builds)" -eq 1 ]

  run "$MODMAN" Mic92/niks3
  [ "$status" -eq 0 ]
  [ "$(builds)" -eq 1 ]
  # The ref is still resolved (cache is keyed on the locked ref).
  [ "$(grep -c '^flake metadata ' "$STUB_LOG")" -eq 2 ]
}

@test "--refresh rebuilds" {
  run "$MODMAN" Mic92/niks3
  [ "$(builds)" -eq 1 ]
  run "$MODMAN" Mic92/niks3 --refresh
  [ "$status" -eq 0 ]
  [ "$(builds)" -eq 2 ]
  # Same key: still one cache entry.
  [ "$(find "$XDG_RUNTIME_DIR/modman" -mindepth 1 | wc -l)" -eq 1 ]
}

@test "each module gets its own cache entry" {
  run "$MODMAN" Mic92/niks3 -m a
  [ "$(argstr module)" = a ]
  run "$MODMAN" Mic92/niks3 -m b
  [ "$(argstr module)" = b ]
  [ "$(builds)" -eq 2 ]

  run "$MODMAN" Mic92/niks3 -m a
  run "$MODMAN" Mic92/niks3 -m b
  [ "$status" -eq 0 ]
  [ "$(builds)" -eq 2 ]
  [ "$(find "$XDG_RUNTIME_DIR/modman" -mindepth 1 -name '*.5' -type l | wc -l)" -eq 2 ]
}

@test "different flake refs get their own cache entries" {
  run "$MODMAN" Mic92/niks3
  run "$MODMAN" Mic92/other
  run "$MODMAN" Mic92/niks3
  [ "$(builds)" -eq 2 ]
}

@test "changing modman.nix invalidates the cache" {
  cp "$MODMAN_NIX" "$BATS_TEST_TMPDIR/modman.nix"
  export MODMAN_NIX=$BATS_TEST_TMPDIR/modman.nix

  run "$MODMAN" Mic92/niks3
  run "$MODMAN" Mic92/niks3
  [ "$(builds)" -eq 1 ]

  echo '# changed' >>"$MODMAN_NIX"
  run "$MODMAN" Mic92/niks3
  [ "$status" -eq 0 ]
  [ "$(builds)" -eq 2 ]
  [ "$(argstr nixpkgs)" = /nix/store/fake-nixpkgs ]
  grep -q -- "-f $MODMAN_NIX " "$STUB_LOG"
}

@test "changing MODMAN_NIXPKGS invalidates the cache" {
  run "$MODMAN" Mic92/niks3
  MODMAN_NIXPKGS=/nix/store/other-nixpkgs run "$MODMAN" Mic92/niks3
  [ "$status" -eq 0 ]
  [ "$(builds)" -eq 2 ]
  [ "$(argstr nixpkgs)" = /nix/store/other-nixpkgs ]
}

# --- output ------------------------------------------------------------------

@test "page is printed when stdout is not a tty" {
  run "$MODMAN" Mic92/niks3
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$STUB_PAGE")" ]

  # Cache hit prints the same page.
  run "$MODMAN" Mic92/niks3
  [ "$status" -eq 0 ]
  [ "$(builds)" -eq 1 ]
  [ "$output" = "$(cat "$STUB_PAGE")" ]
}

# --- cache directory ---------------------------------------------------------

@test "cache dir is \$XDG_RUNTIME_DIR/modman with mode 700" {
  run "$MODMAN" Mic92/niks3
  [ "$status" -eq 0 ]
  [ -d "$XDG_RUNTIME_DIR/modman" ]
  [ "$(stat -c %a "$XDG_RUNTIME_DIR/modman")" = 700 ]
  [ -L "$(grep '^build ' "$STUB_LOG" | awk '{ for (i = 1; i < NF; i++) if ($i == "--out-link") print $(i + 1) }')" ]
}

@test "cache dir falls back to \$TMPDIR/modman" {
  unset XDG_RUNTIME_DIR
  export TMPDIR=$BATS_TEST_TMPDIR/tmp
  mkdir -p "$TMPDIR"
  run "$MODMAN" Mic92/niks3
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$TMPDIR/modman")" = 700 ]
  [ "$(find "$TMPDIR/modman" -name '*.5' -type l | wc -l)" -eq 1 ]
}

# The last fallback is hardcoded to /tmp/modman-$UID. Only touch it when /tmp
# is writable and that directory doesn't exist yet (e.g. the nix build sandbox),
# never a real shared one.
use_tmp_cache() {
  local dir
  dir=/tmp/modman-$(id -u)
  [[ -w /tmp ]] || skip "/tmp is not writable"
  [[ ! -e $dir && ! -L $dir ]] || skip "$dir already exists"
  tmp_cache=$dir
  unset XDG_RUNTIME_DIR TMPDIR
}

@test "/tmp fallback: creates /tmp/modman-\$UID with mode 700" {
  use_tmp_cache
  run "$MODMAN" Mic92/niks3
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$tmp_cache")" = 700 ]
  [ "$(builds)" -eq 1 ]
}

@test "/tmp fallback: refuses a directory with the wrong mode" {
  use_tmp_cache
  mkdir -m 755 "$tmp_cache"
  run "$MODMAN" Mic92/niks3
  [ "$status" -eq 1 ]
  [[ $output == *"mode is not 700"* ]]
  [ "$(builds)" -eq 0 ]
}

@test "/tmp fallback: refuses a symlink" {
  use_tmp_cache
  mkdir -m 700 "$BATS_TEST_TMPDIR/elsewhere"
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$tmp_cache"
  run "$MODMAN" Mic92/niks3
  [ "$status" -eq 1 ]
  [[ $output == *"is a symlink"* ]]
  [ "$(builds)" -eq 0 ]
}

@test "/tmp fallback: refuses a non-directory" {
  use_tmp_cache
  touch "$tmp_cache"
  run "$MODMAN" Mic92/niks3
  [ "$status" -eq 1 ]
  [[ $output == *"not a directory"* ]]
  [ "$(builds)" -eq 0 ]
}
