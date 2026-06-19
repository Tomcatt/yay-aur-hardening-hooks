-- yay UpgradeSelect hooks for AUR supply-chain review.
-- See https://github.com/Jguer/yay/blob/v13.0.0/doc/examples/recently_modified.lua
-- and .../maintainer_change.lua (upstream examples, maintainer_change.lua
-- patched here for a load-order bug: cache_file referenced yay.opt.build_dir
-- at top-level script load, before yay populates it; moved into the callback
-- and forward-declared as a shared upvalue for load_cache/save_cache).

-- Hook 1: auto-exclude AUR packages whose PKGBUILD changed in the last 3 days.
yay.create_autocmd("UpgradeSelect", {
  desc = "skip recently modified AUR upgrades",
  callback = function(event)
    yay.log.info("pre-excluding AUR packages modified in the last 3 days")
    local exclude = {}
    local recent_cutoff = os.time() - (3 * 24 * 60 * 60)
    for _, pkg in ipairs(event.data.upgrades) do
      if pkg.repository == "aur" and pkg.last_modified >= recent_cutoff then
        yay.log.warn("pre-excluding recently modified AUR package: ", pkg.name)
        table.insert(exclude, pkg.name)
      end
    end

    return { exclude = exclude, skip_menu = false }
  end,
})

-- Hook 2: warn (does not exclude) when an AUR package's maintainer changes.
local cache_file

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
  local f = assert(io.open(cache_file, "w"))
  for name, maintainer in pairs(cache) do
    f:write(name .. "=" .. maintainer .. "\n")
  end
  f:close()
end

yay.create_autocmd("UpgradeSelect", {
  desc = "warn on AUR maintainer changes",
  callback = function(event)
    cache_file = yay.opt.build_dir .. "/maintainer_cache"
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
