# yay-aur-hardening-hooks

Ready-to-use `init.lua` for [yay](https://github.com/Jguer/yay) 13.0+ that
combines its two official AUR-review example hooks, with a bug fix applied
to one of them.

## Background

In June 2026, attackers took over orphaned AUR packages and injected
malicious build-time dependencies into their `PKGBUILD`s ([Arch Linux
advisory][advisory]). yay 13.0 responded by adding a Lua hook system
(`init.lua`, `UpgradeSelect`, `AURPreInstall`, `AURPostDownload`) so users
can script their own review automation. The release shipped two example
hooks for exactly this kind of attack:

- `recently_modified.lua` — auto-excludes any AUR package from `-Syu` if
  its PKGBUILD was modified in the last 3 days.
- `maintainer_change.lua` — tracks each AUR package's maintainer across
  upgrades and warns (without blocking) if it changes. Relevant because
  "package gets a new maintainer" is exactly what happens when an orphaned
  package is taken over.

[advisory]: https://archlinux.org/news/active-aur-malicious-packages-incident/

## The bug

As shipped (`doc/examples/maintainer_change.lua` in the yay 13.0.0 source),
the script crashes on every real `-Syu`:

```lua
local cache_file = yay.opt.build_dir .. "/maintainer_cache"
```

The concat against `nil` throws:

```
init.lua:15: cannot perform concat operation between nil and string
```

**Root cause:** `yay.opt` is a write-only table (`pkg/settings/lua/lua.go`):
it's created empty at engine start, and yay only ever *reads from* it (to
apply your overrides into its config) — yay never *writes into* it. So
`yay.opt.build_dir` is `nil` everywhere in the script's lifetime — at
top-level load **and** inside every callback — unless the script sets that
key itself, the way the upstream `doc/init.lua` template does
(`yay.opt.build_dir = os.getenv("HOME") .. "/.cache/yay"`). The example
script assumes a reader, but `yay.opt` only supports writers.

An earlier version of this fix moved the read into the callback, assuming
it was a load-order/timing issue. That's wrong — it loaded without error
under non-upgrade invocations (which never reach the callback) but still
crashed on a real `yay -Syu`, because the value is never populated at all,
regardless of when you read it.

Filed upstream: https://github.com/Jguer/yay/issues/2878 (full report in
[`UPSTREAM_ISSUE.md`](./UPSTREAM_ISSUE.md)).

### The fix

Don't read `yay.opt.build_dir` at all — derive the cache directory
independently, the same way yay derives its own default:

```lua
local cache_dir = (os.getenv("XDG_CACHE_HOME") or (os.getenv("HOME") .. "/.cache")) .. "/yay"
local cache_file = cache_dir .. "/maintainer_cache"
```

`save_cache` also `mkdir -p`s `cache_dir` before writing, since a fresh
host may never have run an AUR build and so never created `~/.cache/yay`.
Verified against the real yay 13.0.0 binary on live AUR data (not just the
mock harness below) — see commit history for the before/after.

## Usage

Copy [`hooks/init.lua`](./hooks/init.lua) to `~/.config/yay/init.lua`. Both
hooks register independently and both run on every `yay -Syu` — yay 13.0
unions their `exclude` lists and ORs `skip_menu`
(`pkg/settings/lua/autocmd.go::RunUpgradeSelect`), so they compose safely.

The maintainer-change cache lives at `$XDG_CACHE_HOME/yay/maintainer_cache`
(default `~/.cache/yay/maintainer_cache`), one `pkgname=maintainer` line
per package. First time it sees a package it seeds the cache silently;
after that, a maintainer change logs a loud `error`-level warning but does
**not** exclude the package — you still see and approve the upgrade, just
with a flag on it.

## Testing without touching your system

[`tests/mock_test.lua`](./tests/mock_test.lua) mocks yay's Lua API
(`yay.opt` as the real *empty* table — not a fabricated value — plus
`yay.log` and `yay.create_autocmd`) closely enough to exercise the real
hook logic, including yay's actual multi-hook dispatch semantics for
`UpgradeSelect`, without running yay or pacman at all:

```console
$ XDG_CACHE_HOME=/tmp/some/dir lua5.4 tests/mock_test.lua
```

Three scenarios are simulated: first-seen package, unchanged maintainer,
and a maintainer change with a same-day PKGBUILD edit (the actual attack
shape) — confirming the auto-exclude and the warning both fire together.

## License

The example hooks originate from [Jguer/yay][yay], licensed
GPL-3.0-or-later. This repo keeps the same license; see [`LICENSE`](./LICENSE).

[yay]: https://github.com/Jguer/yay
