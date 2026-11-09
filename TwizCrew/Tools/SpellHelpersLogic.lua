-- Spell helpers, the rules (no game calls): the smart-target macros TwizCrew writes, how to recognise them again,
-- and which macros to make, change or delete (the bars are never touched). Used by Tools/SpellHelpers.lua.
--
-- Smart target: a harmful spell cast at a friend hits the friend's target; a helpful spell cast at an enemy lands
-- on the enemy's target (or on you when nobody friendly is there). "Switch target" also makes that unit your
-- target (with /assist). The spell is cast by name, so it is always your highest rank, unless "Newest rank" is off
-- for it, then the macro names the rank.
local _, ns = ...

local L = {}
ns.SpellHelpersLogic = L

L.NAME_MAX = 16 -- the longest macro name the game takes
L.ICON = 134400  -- the question mark: with #showtooltip the macro shows the spell's own icon

-- "Flash Heal(Rank 3)", or just the name (the highest rank you know).
function L.castName(spell, rank)
  return rank and (spell .. "(Rank " .. rank .. ")") or spell
end

-- The macro text. kind: "harm" | "help"; switch: also make that unit your target.
function L.body(spell, rank, kind, switch)
  local s = L.castName(spell, rank)
  if kind == "harm" then
    if switch then return "#showtooltip\n/assist [help,nodead]\n/cast " .. s end
    return "#showtooltip\n/cast [@target,harm,nodead][@targettarget,harm,nodead][] " .. s
  elseif kind == "help" then
    if switch then return "#showtooltip\n/assist [harm,nodead]\n/cast [@target,help][@player] " .. s end
    return "#showtooltip\n/cast [@target,help][@targettarget,help][@player] " .. s
  end
  return nil
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- One of our macros? Returns { spell, rank, kind, switch } when the text is exactly one TwizCrew writes, else nil.
-- (A macro you wrote yourself is never touched.)
function L.parse(body)
  if type(body) ~= "string" then return nil end
  body = trim(body:gsub("\r", ""))
  local last = body:match("/cast ([^\n]*)$")
  if not last then return nil end
  local s = trim(last:match("%]%s*([^%]]+)$") or last)
  local spell, rank = s:match("^(.-)%(Rank (%d+)%)$")
  if not spell then spell = s end
  rank = tonumber(rank)
  if spell == "" then return nil end
  for _, kind in ipairs({ "harm", "help" }) do
    for _, switch in ipairs({ false, true }) do
      if L.body(spell, rank, kind, switch) == body then
        return { spell = spell, rank = rank, kind = kind, switch = switch }
      end
    end
  end
  return nil
end

-- The macro's name: the spell (cut to fit), with the rank when it keeps one: "Flash Heal 3".
function L.macroName(spell, rank)
  local tail = rank and (" " .. rank) or ""
  local room = L.NAME_MAX - #tail
  local base = spell
  if #base > room then
    base = base:sub(1, room):gsub("[\192-\255][\128-\191]*$", "") -- never cut a letter in half
    base = trim(base)
  end
  return base .. tail
end

-- A spell's choices with the defaults filled in: newest rank on, smart target off, switch target off.
function L.choice(c)
  c = type(c) == "table" and c or {}
  return { newest = c.newest ~= false, smart = c.smart == true, switch = c.switch == true }
end

-- Which macros to write. The bars are never touched: you drag the macros where you want them, and because a macro
-- keeps its name (only its text changes), one already on your bars stays there and just works differently.
--   spells   the spells you know, in the order to make their macros (bar spells first: macro slots run out)
--   have     our macros now: { { index, name, p = L.parse(body), body } }
--   choiceOf(spell) -> L.choice; kindOf(spell) -> "harm" | "help" | nil; bestRank(spell) -> rank | nil
-- Returns edit = { { index, name, body } }, make = { { name, body, spell } }, drop = { index } (highest first: deleting
-- one moves the ones after it). A spell with "Newest rank" off keeps the rank its macro has (or the top one now).
function L.macros(spells, have, choiceOf, kindOf, bestRank)
  local mineFor = {}
  for _, m in ipairs(have or {}) do
    local s = m.p and m.p.spell
    if s then mineFor[s] = mineFor[s] or {}; table.insert(mineFor[s], m) end
  end
  local edit, make, drop, wanted, taken = {}, {}, {}, {}, {}
  for _, m in ipairs(have or {}) do taken[m.name] = true end
  for _, spell in ipairs(spells or {}) do
    local c, kind = choiceOf(spell), kindOf(spell)
    if c.smart and kind and not wanted[spell] then
      wanted[spell] = true
      local old = mineFor[spell]
      local rank = nil
      if not c.newest then rank = (old and old[1].p.rank) or bestRank(spell) end
      local body = L.body(spell, rank, kind, c.switch)
      if old then
        for _, m in ipairs(old) do
          if (m.body or ""):gsub("\r", ""):gsub("%s+$", "") ~= body then edit[#edit + 1] = { index = m.index, name = m.name, body = body } end
        end
      else
        local name = L.macroName(spell)
        if not taken[name] then
          taken[name] = true
          make[#make + 1] = { name = name, body = body, spell = spell }
        end
      end
    end
  end
  for _, m in ipairs(have or {}) do
    if not wanted[m.p and m.p.spell or ""] then drop[#drop + 1] = m.index end
  end
  table.sort(drop, function(a, b) return a > b end)
  return edit, make, drop
end
