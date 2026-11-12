-- Runs in the runner's own environment (may use io). Repo root is the working directory.
local function readFile(path)
  local f = assert(io.open(path, "r"))
  local s = f:read("*a")
  f:close()
  return s
end

local function tocLines()
  local list = {}
  for line in readFile("TwizCrew/TwizCrew.toc"):gmatch("[^\r\n]+") do list[#list + 1] = line end
  return list
end

local function tocFiles()
  local out = {}
  for _, line in ipairs(tocLines()) do
    if line:match("%S") and line:sub(1, 2) ~= "##" then out[#out + 1] = line end
  end
  return out
end

local function luaFilesOnDisk()
  local out = {}
  local p = io.popen("cd TwizCrew && find . -name '*.lua' | sort")
  for line in p:lines() do out[#out + 1] = (line:gsub("^%./", ""):gsub("/", "\\")) end
  p:close()
  return out
end

-- Replaces comments (and optionally string literals) with blanks. Handles long brackets.
local function strip(src, keepStrings)
  local out, i, n = {}, 1, #src
  while i <= n do
    local c = src:sub(i, i)
    if src:sub(i, i + 1) == "--" then
      local eq = src:match("^%-%-%[(=*)%[", i)
      if eq then
        local _, e = src:find("]" .. eq .. "]", i, true)
        i = (e or n) + 1
      else
        local e = src:find("\n", i, true)
        i = e or n + 1
      end
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n and src:sub(j, j) ~= c do
        if src:sub(j, j) == "\\" then j = j + 1 end
        j = j + 1
      end
      if keepStrings then out[#out + 1] = src:sub(i, j) else out[#out + 1] = '""' end
      i = j + 1
    elseif c == "[" and src:match("^%[=*%[", i) then
      local eq = src:match("^%[(=*)%[", i)
      local _, e = src:find("]" .. eq .. "]", i, true)
      e = e or n
      if keepStrings then out[#out + 1] = src:sub(i, e) else out[#out + 1] = '""' end
      i = e + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

-- A luac that can list byte code: luac5.1 on the PATH, else the one built in tools/lua-5.1.5.
local function findLuac()
  for _, cmd in ipairs({ "luac5.1", "tools/lua-5.1.5/src/luac" }) do
    local p = io.popen(cmd .. " -v 2>&1")
    local out = p:read("*a")
    p:close()
    if out:find("Lua 5.1", 1, true) then return cmd end
  end
end

local function globalAllowed(name)
  return name == "TwizCrewDB" or name:match("^SLASH_") or name:match("^BINDING_") or name:match("^TwizCrew_")
end

return {
  files = {},
  tests = {
    every_lua_file_is_in_toc_and_exists = function(ns, A)
      local listed, onDisk = {}, {}
      for _, f in ipairs(tocFiles()) do
        A.no(f:find("/", 1, true), "TOC path must use backslashes: " .. f)
        listed[f] = true
        local fh = io.open("TwizCrew/" .. f:gsub("\\", "/"), "r")
        A.ok(fh, "TOC lists a missing file: " .. f)
        if fh then fh:close() end
      end
      for _, f in ipairs(luaFilesOnDisk()) do
        onDisk[f] = true
        A.ok(listed[f], "Lua file not in TOC: " .. f)
      end
    end,
    toc_has_required_lines = function(ns, A)
      local have = {}
      for _, l in ipairs(tocLines()) do have[#have + 1] = l end
      local text = "\n" .. table.concat(have, "\n") .. "\n"
      A.contains(text, "\n## Interface: 16001\n")
      A.contains(text, "\n## SavedVariables: TwizCrewDB\n")
      A.contains(text, "\n## Version: ")
    end,
    toc_version_matches_the_code = function(ns, A)
      local toc = readFile("TwizCrew/TwizCrew.toc"):match("\n## Version:%s*([^\r\n]-)%s*[\r\n]")
      local init = readFile("TwizCrew/Core/Init.lua")
      local code = init:match('local ADDON_VERSION%s*=%s*"([^"]+)"')
      local since = init:match('local RESTART_SINCE%s*=%s*"([^"]+)"')
      A.ok(toc and code and since, "## Version in the .toc, ADDON_VERSION and RESTART_SINCE in Core/Init.lua")
      A.eq(code, toc, "ADDON_VERSION in Core/Init.lua must match ## Version in TwizCrew.toc")
      A.ok(since:match("^%d+[%.%d]*$"), "RESTART_SINCE is a plain version")
    end,
    no_forbidden_lua = function(ns, A)
      for _, f in ipairs(tocFiles()) do
        local src = readFile("TwizCrew/" .. f:gsub("\\", "/"))
        local bare = strip(src, false)
        A.no(bare:find("%f[%w_]os%."), f .. " uses os.")
        A.no(bare:find("%f[%w_]io%."), f .. " uses io.")
        A.no(bare:find("%f[%w_]require%f[^%w_]"), f .. " uses require")
        A.no(bare:find("%f[%w_]goto%f[^%w_]"), f .. " uses goto")
        A.no(bare:find("//", 1, true), f .. " uses //")
        local withStrings = strip(src, true)
        A.no(withStrings:find('SLASH_[%w_]*%s*=%s*["\']/twiz["\']'), f .. " registers /twiz")
      end
    end,
    -- The addon's only globals are TwizCrewDB, the slash command and binding names and the TwizCrew_ functions: a
    -- forgotten `local` shows up as a SETGLOBAL in the compiled code.
    no_stray_global_writes = function(ns, A)
      local luac = findLuac()
      if not luac then
        print("  (no_stray_global_writes skipped: no luac found; build tools/lua-5.1.5 or install luac5.1)")
        return
      end
      for _, f in ipairs(tocFiles()) do
        local path = "TwizCrew/" .. f:gsub("\\", "/")
        local p = io.popen(luac .. " -l -p " .. path .. " 2>&1")
        for line in p:lines() do
          local name = line:match("SETGLOBAL.-;%s*(%S+)")
          A.ok(not name or globalAllowed(name), path .. " writes the global " .. tostring(name))
        end
        p:close()
      end
    end,
    -- Find the crew: the game has one waypoint and one super-tracked target, and QuestMaster, OpenMap and Questie use
    -- them. TwizCrew draws its own arrow and icons and never touches those.
    never_touches_the_games_waypoint = function(ns, A)
      for _, f in ipairs(tocFiles()) do
        local bare = strip(readFile("TwizCrew/" .. f:gsub("\\", "/")), true)
        for _, name in ipairs({ "SetUserWaypoint", "ClearUserWaypoint", "C_SuperTrack", "SetSuperTracked" }) do
          A.no(bare:find(name, 1, true), f .. " uses " .. name)
        end
      end
    end,
  },
}
