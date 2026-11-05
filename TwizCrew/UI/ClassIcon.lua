-- Class icon with fallbacks: the atlas "classicon-<class>", then the character-creation texture with
-- CLASS_ICON_TCOORDS, then nothing (texture hidden). Which one worked is kept for /tc report.
local _, ns = ...

local ClassIcon = {}
ns.ClassIcon = ClassIcon

local SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local last = "none"
local logged = {}

local function hasAtlas(name)
  if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
  local ok, info = pcall(C_Texture.GetAtlasInfo, name)
  return ok and info ~= nil and info ~= false
end

-- Returns "atlas" | "texture" | "none".
function ClassIcon.apply(texture, classFile)
  local method = "none"
  if type(classFile) == "string" and classFile ~= "" then
    local atlas = "classicon-" .. string.lower(classFile)
    local coords = type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS[classFile]
    if texture.SetAtlas and hasAtlas(atlas) then
      texture:SetTexCoord(0, 1, 0, 1)
      texture:SetAtlas(atlas)
      method = "atlas"
    elseif type(coords) == "table" then
      texture:SetTexture(SHEET)
      texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
      method = "texture"
    end
    last = method
    if not logged[method] then
      logged[method] = true
      ns.Log.add("info", "Class icons: using %s (first seen for %s)", method, classFile)
    end
  end
  if method == "none" then texture:Hide() else texture:Show() end
  return method
end

-- The last method used for a known class name ("none" until an icon was drawn).
function ClassIcon.method() return last end
