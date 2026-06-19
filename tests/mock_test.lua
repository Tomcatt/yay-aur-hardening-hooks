-- Mock of yay's Lua API, mirroring real dispatch semantics:
-- multiple autocmds per event are stored in a list and all run;
-- their exclude lists are unioned (deduped), skip_menu is OR'd.
-- (Matches pkg/settings/lua/autocmd.go RunUpgradeSelect in yay 13.0.0.)
yay = {
  opt = {},  -- real yay.opt is an empty table unless the script sets it itself
  log = {
    debug = function(...) print("[debug]", ...) end,
    info = function(...) print("[info]", ...) end,
    warn = function(...) print("[warn]", ...) end,
    error = function(...) print("[error]", ...) end,
  },
  _registered = {},
  create_autocmd = function(name, opts)
    yay._registered[name] = yay._registered[name] or {}
    table.insert(yay._registered[name], opts)
  end,
}

local function run_upgrade_select(event)
  local exclude, seen, skip_menu = {}, {}, false
  for _, autocmd in ipairs(yay._registered["UpgradeSelect"] or {}) do
    local result = autocmd.callback(event)
    for _, name in ipairs(result.exclude or {}) do
      if not seen[name] then
        seen[name] = true
        table.insert(exclude, name)
      end
    end
    if result.skip_menu then skip_menu = true end
  end
  return { exclude = exclude, skip_menu = skip_menu }
end

os.execute("mkdir -p /tmp/yay-test/mockcache")
os.execute("rm -f /tmp/yay-test/mockcache/maintainer_cache")

dofile("/tmp/yay-test/fake-config/yay/init.lua")

local now = os.time()

print("=== run 1: first time seeing pkg, old PKGBUILD ===")
local r1 = run_upgrade_select({ data = { upgrades = {
  { name = "foo-git", repository = "aur", maintainer = "alice", last_modified = now - 30*24*60*60 },
} } })
print("exclude:", table.concat(r1.exclude, ","))

print("=== run 2: same maintainer, old PKGBUILD ===")
local r2 = run_upgrade_select({ data = { upgrades = {
  { name = "foo-git", repository = "aur", maintainer = "alice", last_modified = now - 30*24*60*60 },
} } })
print("exclude:", table.concat(r2.exclude, ","))

print("=== run 3: maintainer changed AND PKGBUILD touched yesterday (the attack scenario) ===")
local r3 = run_upgrade_select({ data = { upgrades = {
  { name = "foo-git", repository = "aur", maintainer = "mallory", last_modified = now - 1*24*60*60 },
} } })
print("exclude:", table.concat(r3.exclude, ","))

print("=== cache file contents ===")
local cache_path = os.getenv("XDG_CACHE_HOME") .. "/yay/maintainer_cache"
local f = io.open(cache_path)
print(f:read("*a"))
f:close()
