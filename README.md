# modman

Generates manpages for NixOS modules.

Given a flake, `modman` evaluates one of its `nixosModules` and renders the
options that module declares (and only those) as a manpage.

## Usage

```
modman FLAKEREF [-m|--module NAME] [--refresh]
```

```
modman Mic92/niks3
modman github:nlewo/comin -m comin
```

Options may appear before or after `FLAKEREF`.

| Option | Meaning |
|---|---|
| `-m`, `--module NAME` | Render `nixosModules.NAME` (default: `default`). An unknown name lists the available modules. |
| `--refresh` | Re-resolve the flake ref and rebuild the page, ignoring the cache. |

On a terminal the page opens in `man`; otherwise the roff source is printed.

## Flake refs

| Input | Becomes |
|---|---|
| `owner/repo[/branch]` | `github:owner/repo[/branch]` |
| `https://host.tld/owner/repo`, `host.tld/owner/repo` | `git+https://host.tld/owner/repo?shallow=1` |
| any other flake ref (`github:…`, `git+ssh://…`, `path:…`) | unchanged |
| `./dir`, `/abs/dir`, `~/dir` | unchanged (local path) |

The first segment is read as a hostname if it contains a dot, otherwise as a
GitHub owner. A relative directory needs a leading `./`.

`git+https` refs are fetched shallow (latest commit only). `owner/repo` or
`github:owner/repo` fetch a tarball, which is still faster than
`github.com/owner/repo`.

## Installation

```
nix run github:asymmetric/modman -- Mic92/niks3
```

or add `packages.<system>.default` from this flake to your profile/config.

## How it works

1. `nix flake metadata` resolves the ref to a locked revision.
2. The module is evaluated with NixOS (`nixos/lib/eval-config.nix`) using
   modman's own pinned nixpkgs, not the target flake's.
3. Options are kept only if declared inside the target flake's source.
4. `nixosOptionsDoc` + `nixos-render-docs` render the manpage.

## Cache

Pages are cached per locked revision, module, nixpkgs, system and
`modman.nix` version, as `nix build --out-link` symlinks in
`$XDG_RUNTIME_DIR/modman` (falling back to `$TMPDIR/modman`, then
`/tmp/modman-$UID`). The links are GC roots only until that directory is
cleared (logout/reboot). Branch refs are re-resolved at most every
`tarball-ttl` (1h by default); use `--refresh` to force it.

## Development

```
nix develop          # shellcheck, nixfmt, bats, jq
nix flake check      # shellcheck + CLI tests
```

The CLI tests (`tests/cli.bats`) run `modman` against a stub `nix`
(`tests/nix-stub`), so they need neither network nor a nix daemon:

```
nix develop -c bats tests/cli.bats
```

Running `./modman` from a checkout needs `MODMAN_NIXPKGS` set to a nixpkgs
source path (the packaged wrapper sets it):

```
MODMAN_NIXPKGS=$(nix flake archive --json | jq -r .inputs.nixpkgs.path) ./modman Mic92/niks3
```
