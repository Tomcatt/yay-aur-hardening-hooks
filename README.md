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
the script crashes on every yay invocation:

```lua
local cache_file = yay.opt.build_dir .. "/maintainer_cache"
```

This line runs at **script load time** (top-level), but `yay.opt.build_dir`
is not yet populated when `init.lua` is first loaded — it's only available
once a hook *callback* actually fires. The concat against `nil` throws:

```
init.lua:15: cannot perform concat operation between nil and string
```

Filed upstream: https://github.com/Jguer/yay/issues/2878 (full report in
[`UPSTREAM_ISSUE.md`](./UPSTREAM_ISSUE.md)).

### The fix

Forward-declare `cache_file` as a shared upvalue, and assign it *inside*
the callback (where `yay.opt` is populated), not at top-level:

```lua
local cache_file  -- declared before the functions that close over it

local function load_cache() ... uses cache_file ... end
local function save_cache() ... uses cache_file ... end

yay.create_autocmd("UpgradeSelect", {
  callback = function(event)
    cache_file = yay.opt.build_dir .. "/maintainer_cache"  -- no `local` here
    ...
  end,
})
```

`load_cache`/`save_cache` are defined earlier in the file but as closures
over the same lexical scope, so they share the upvalue once the callback
assigns it. Declaring `cache_file` as `local` *inside* the callback (the
naive fix) does not work — it creates a new local scoped only to that
function body, invisible to `load_cache`/`save_cache`.

## Usage

Copy [`hooks/init.lua`](./hooks/init.lua) to `~/.config/yay/init.lua`. Both
hooks register independently and both run on every `yay -Syu` — yay 13.0
unions their `exclude` lists and ORs `skip_menu`
(`pkg/settings/lua/autocmd.go::RunUpgradeSelect`), so they compose safely.

The maintainer-change cache lives at `<build_dir>/maintainer_cache`
(default `~/.cache/yay/maintainer_cache`), one `pkgname=maintainer` line
per package. First time it sees a package it seeds the cache silently;
after that, a maintainer change logs a loud `error`-level warning but does
**not** exclude the package — you still see and approve the upgrade, just
with a flag on it.

## Testing without touching your system

[`tests/mock_test.lua`](./tests/mock_test.lua) mocks yay's Lua API
(`yay.opt`, `yay.log`, `yay.create_autocmd`) closely enough to exercise the
real hook logic — including yay's actual multi-hook dispatch semantics for
`UpgradeSelect` — without running yay or pacman at all:

```console
$ lua5.4 tests/mock_test.lua
```

Three scenarios are simulated: first-seen package, unchanged maintainer,
and a maintainer change with a same-day PKGBUILD edit (the actual attack
shape) — confirming the auto-exclude and the warning both fire together.

## License

The example hooks originate from [Jguer/yay][yay], licensed
GPL-3.0-or-later. This repo keeps the same license; see [`LICENSE`](./LICENSE).

[yay]: https://github.com/Jguer/yay
