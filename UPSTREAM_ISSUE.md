# Upstream report

Filed: https://github.com/Jguer/yay/issues/2878

**Update:** the original report below misdiagnosed this as a load-order
bug. Real-world testing against an actual `yay -Syu` (not just `-Pg`,
which never reaches the `UpgradeSelect` callback at all) showed the
"fixed" version still crashes identically. The actual cause and fix are
in the follow-up comment, posted to the issue and reproduced at the
bottom of this file.

## Title

`doc/examples/maintainer_change.lua` crashes on every real upgrade:
`yay.opt.build_dir` is never populated

## Body

**yay version:** 13.0.0

**Summary**

The shipped example `doc/examples/maintainer_change.lua` throws a Lua
error on every real `yay -Syu`/`-Syyuu` that reaches the `UpgradeSelect`
hook:

```
-> UpgradeSelect: init.lua:15: cannot perform concat operation between nil and string
stack traceback:
	init.lua:15: in main chunk
	[G]: ?
```

**Cause**

Line 15 of the example:

```lua
local cache_file = yay.opt.build_dir .. "/maintainer_cache"
```

`yay.opt` (`pkg/settings/lua/lua.go`) is created as an **empty** table at
engine start, and is only ever read *from* by yay (`Engine.Apply`) to copy
user-set overrides into yay's config — yay never writes resolved config
values *into* it. So `yay.opt.build_dir` is `nil` for the entire lifetime
of the script — at top-level load and inside every callback alike —
unless the script sets that key itself (the way `doc/init.lua`'s own
template does: `yay.opt.build_dir = os.getenv("HOME") .. "/.cache/yay"`).
The example assumes `yay.opt` is a readable resolved-config object; it
isn't — it's a write-only options-override channel.

(An earlier version of this report assumed the bug was a load-order
issue and proposed moving the read into the callback. That "fix" loads
without error under `yay -Pg` — which never invokes `UpgradeSelect` —
but still crashes identically on a real `-Syu`, since the callback-time
read hits the same permanently-empty table.)

**Fix**

Don't read `yay.opt.build_dir`. Derive the cache directory independently,
matching yay's own default `build_dir` convention:

```lua
local cache_dir = (os.getenv("XDG_CACHE_HOME") or (os.getenv("HOME") .. "/.cache")) .. "/yay"
local cache_file = cache_dir .. "/maintainer_cache"
```

`save_cache` should also `mkdir -p` that directory before writing, since a
host that's never run an AUR build may not have created it yet.

Verified against the real yay 13.0.0 binary with live AUR data via
`yay -Syyuu < /dev/null` (blocks before any package transaction, so safe
to run repeatedly) on two separate machines — confirmed the original
script crashes and the fixed one doesn't, with identical upgrade data on
both runs. Full patched scripts + a Lua mock test harness:
https://github.com/Tomcatt/yay-aur-hardening-hooks

Happy to open a PR with this fix if useful.
