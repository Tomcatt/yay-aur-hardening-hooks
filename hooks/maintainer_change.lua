-- Warn when an AUR package's maintainer changes between upgrades.
--
-- Patched from upstream doc/examples/maintainer_change.lua (yay 13.0.0):
-- the original read `yay.opt.build_dir` to locate its cache file, but
-- yay.opt is a write-only table (pkg/settings/lua/lua.go: created empty,
-- only ever read FROM by yay to apply settings INTO config — never
-- written TO by yay). It's nil unless the script sets it itself, so the
-- original crashes on every real `-Syu`, not just at top-level load.
-- Fixed by deriving the cache path independently via XDG_CACHE_HOME/HOME,
-- matching yay's own default build_dir convention without depending on
-- the (always-empty) yay.opt table. See README.md in this repo for details.
--
-- The known maintainer for each package is stored in a plain text cache
-- file under $XDG_CACHE_HOME/yay (default ~/.cache/yay). On the first
-- upgrade for a package the current maintainer is recorded without any
-- warning. On subsequent upgrades:
--   * same maintainer  → debug "match correct"
--   * different maintainer → error "new maintainer, double check build files"
--
-- The cache is updated whenever a new or changed maintainer is seen.
--
-- Cache file location: $XDG_CACHE_HOME/yay/maintainer_cache
-- Format: one "pkgname=maintainer" entry per line.

local cache_dir = (os.getenv("XDG_CACHE_HOME") or (os.getenv("HOME") .. "/.cache")) .. "/yay"
local cache_file = cache_dir .. "/maintainer_cache"

local function load_cache()
  local cache = {}
  local f = io.open(cache_file, "r")
  if not f then return cache end
  for line in f:lines() do
    local name, maintainer = line:match("^([^=]+)=(.*)$")
    if name then
      cache[name] = maintainer
    end
  end
  f:close()
  return cache
end

local function save_cache(cache)
  os.execute('mkdir -p "' .. cache_dir .. '"')
  local f = assert(io.open(cache_file, "w"))
  for name, maintainer in pairs(cache) do
    f:write(name .. "=" .. maintainer .. "\n")
  end
  f:close()
end

yay.create_autocmd("UpgradeSelect", {
  desc = "warn on AUR maintainer changes",
  callback = function(event)
    yay.log.info("checking for AUR maintainer changes")
    local cache = load_cache()
    local dirty = false

    for _, pkg in ipairs(event.data.upgrades) do
      if pkg.repository == "aur" and pkg.maintainer ~= "" then
        local cached = cache[pkg.name]
        if cached == nil then
          -- First time seeing this package: seed the cache silently.
          cache[pkg.name] = pkg.maintainer
          dirty = true
        elseif cached == pkg.maintainer then
          yay.log.debug("match correct: " .. pkg.name .. " " .. pkg.maintainer)
        else
          yay.log.error("new maintainer, double check build files: ", pkg.name,
            "(was: " .. cached .. ", now: " .. pkg.maintainer .. ")")
          cache[pkg.name] = pkg.maintainer
          dirty = true
        end
      end
    end

    if dirty then
      yay.log.info("saving maintainer cache:", cache_file)
      save_cache(cache)
    end

    return { exclude = {}, skip_menu = false }
  end,
})
