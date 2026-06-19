# Upstream report

Filed against [Jguer/yay](https://github.com/Jguer/yay) — link added here
once the issue is created.

## Title

`doc/examples/maintainer_change.lua` crashes on load: `cache_file` read
before `yay.opt` is populated

## Body

**yay version:** 13.0.0

**Summary**

The shipped example `doc/examples/maintainer_change.lua` throws a Lua
error on every invocation, including ones that never reach the
`UpgradeSelect` callback (e.g. `yay -Pg`):

```
$ XDG_CONFIG_HOME=/tmp/fake yay -Pg
init.lua:15: cannot perform concat operation between nil and string
stack traceback:
	init.lua:15: in main chunk
	[G]: ?
```

**Cause**

Line 15 of the example:

```lua
local cache_file = yay.opt.build_dir .. "/maintainer_cache"
```

runs at top-level script load time. `yay.opt.build_dir` isn't populated
yet at that point — it only resolves correctly once it's read from inside
a registered callback, after yay finishes its config/option setup. So
`yay.opt.build_dir` is `nil` at load time and the concat fails.

**Fix**

Forward-declare `cache_file` before the closures that use it, and assign
it inside the callback instead of at top level:

```lua
local cache_file

local function load_cache() ... end  -- uses cache_file via closure
local function save_cache() ... end  -- uses cache_file via closure

yay.create_autocmd("UpgradeSelect", {
  callback = function(event)
    cache_file = yay.opt.build_dir .. "/maintainer_cache"
    ...
  end,
})
```

Verified with a minimal Lua mock of `yay.opt`/`yay.log`/`yay.create_autocmd`
(reproducing real dispatch semantics from
`pkg/settings/lua/autocmd.go::RunUpgradeSelect`) exercising three
scenarios: first-seen package, unchanged maintainer, and a maintainer
change — all pass after the fix. Full repro + patched script:
https://github.com/Tomcatt/yay-aur-hardening-hooks

Happy to open a PR with the one-line-relocation fix if useful.
