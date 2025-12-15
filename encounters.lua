-- ShaguDPS Encounters (Turtle WoW) - v2
-- Drop into Interface\AddOns\ShaguDPS\ and add to ShaguDPS.toc (after settings.lua)
--
-- Fixes in v2:
--  • UIDropDownMenu error fixed (dropdown frame now has a global name)
--  • Zone-name mismatches fixed via zone aliasing (e.g. "Ahn'Qiraj" -> "Temple of Ahn'Qiraj")
--  • Safe fallback when encounter name can't be resolved (Trash when Bosses Only is OFF)

-- =========================================================
-- 1) Boss lists (edit/extend anytime)
-- =========================================================
ShaguDPS_EncounterBosses = ShaguDPS_EncounterBosses or {
  ["Molten Core"] = {
    "Lucifron",
    "Magmadar",
    "Garr",
    "Baron Geddon",
    "Shazzrah",
    "Sulfuron Harbinger",
    "Golemagg the Incinerator",
    "Majordomo Executus",
    "Ragnaros",
    "Incindis",
    "Twin Golems",
    "Sorcerer-Thane Thaurissan",
  },

  ["Zul'Gurub"] = {
    "High Priestess Jeklik",
    "High Priest Venoxis",
    "High Priestess Mar'li",
    "Bloodlord Mandokir",
    "Edge of Madness",
    "High Priest Thekal",
    "Gahz'ranka",
    "High Priestess Arlokk",
    "Jin'do the Hexxer",
    "Hakkar",
  },

  ["Blackwing Lair"] = {
    "Razorgore the Untamed",
    "Vaelastrasz the Corrupt",
    "Broodlord Lashlayer",
    "Firemaw",
    "Ebonroc",
    "Flamegor",
    "Chromaggus",
    "Nefarian",
  },

  ["Ruins of Ahn'Qiraj"] = {
    "Kurinnaxx",
    "General Rajaxx",
    "Moam",
    "Buru the Gorger",
    "Ayamiss the Hunter",
    "Ossirian the Unscarred",
  },

  -- NOTE: In vanilla the zone text is often "Ahn'Qiraj"
  ["Temple of Ahn'Qiraj"] = {
    "The Prophet Skeram",
    "The Bug Family",
    "Battleguard Sartura",
    "The Twin Emperors",
    "Ouro",
    "C'Thun",
    "Fankriss the Unyielding",
    "Viscidus",
    "Princess Huhuran",
  },

  ["Naxxramas"] = {
    "Patchwerk",
    "Grobbulus",
    "Gluth",
    "Thaddius",
    "Noth the Plaguebringer",
    "Heigan the Unclean",
    "Loatheb",
    "Anub'Rekhan",
    "Grand Widow Faerlina",
    "Maexxna",
    "Instructor Razuvious",
    "The Four Horsemen",
    "Sapphiron",
    "Kel'Thuzad",
  },

  ["Tower of Karazhan"] = {
    "Keeper Gnarmoon",
    "Ley-Watcher Incantagos",
    "Anomalus",
    "Echo of Medivh",
    "Chess Fight",
    "Sanv Tas'dal",
    "Rupturan the Broken",
    "Kruul",
    "Mephistroth",
  },
}

-- =========================================================
-- 2) Alias triggers for encounters that aren't the boss unit name
-- =========================================================
ShaguDPS_EncounterAliases = ShaguDPS_EncounterAliases or {
  ["Temple of Ahn'Qiraj"] = {
    ["The Twin Emperors"] = { "Emperor Vek'lor", "Emperor Vek'nilash" },
    ["The Bug Family"]    = { "Vem", "Lord Kri", "Princess Yauj" },
  },

  ["Zul'Gurub"] = {
    ["Edge of Madness"] = { "Gri'lek", "Hazza'rah", "Renataki", "Wushoolay" },
  },

  ["Tower of Karazhan"] = {
    ["Chess Fight"] = {
      "King",
      "Queen",
      "The Rook",
      "The Knight",
      "The Bishop",
      "Withering Pawns",
      "Withering Pawn", -- safety
    },
  },
}

-- =========================================================
-- 2.5) Zone aliasing (fixes zone text differences)
-- =========================================================
ShaguDPS_EncounterZoneAliases = ShaguDPS_EncounterZoneAliases or {
  ["Ahn'Qiraj"] = "Temple of Ahn'Qiraj",    -- vanilla AQ40 zone text
  ["Karazhan Tower"] = "Tower of Karazhan", -- common Turtle variant
  ["Karazhan"] = "Tower of Karazhan",       -- fallback
}

-- =========================================================
-- 3) Implementation
-- =========================================================
local function __ShaguDPSEncounters_Init()
  if not ShaguDPS or not ShaguDPS.data or not ShaguDPS.window or not ShaguDPS.parser then return nil end
  if ShaguDPS.Encounters and ShaguDPS.Encounters.__initialized then return true end

  local data   = ShaguDPS.data
  local window = ShaguDPS.window
  local parser = ShaguDPS.parser
  local config = ShaguDPS.config or {}

  local function IsOn(v) return v == 1 or v == true or v == "1" end

  -- Defaults
  if config.encounters == nil then config.encounters = 1 end
  if config.encounters_bossonly == nil then config.encounters_bossonly = 1 end
  if config.encounters_keep == nil then config.encounters_keep = 25 end
  if config.encounters_autoselect == nil then config.encounters_autoselect = 0 end

  -- Ensure segment slot #2 exists
  data.damage[2] = data.damage[2] or {}
  data.heal[2]   = data.heal[2]   or {}

  ShaguDPS.Encounters = ShaguDPS.Encounters or {}
  local ENC = ShaguDPS.Encounters
  ENC.__initialized = true

  ENC.archive = ENC.archive or { list = {}, counts = {}, selected = nil }
  ENC.active  = ENC.active  or nil

  local function SafeZoneText()
    if type(GetRealZoneText) == "function" then
      local z = GetRealZoneText()
      if z and z ~= "" then return z end
    end
    if type(GetZoneText) == "function" then
      local z = GetZoneText()
      if z and z ~= "" then return z end
    end
    return "Unknown"
  end

  local function ZoneKey(zoneText)
    if not zoneText then return "Unknown" end
    return ShaguDPS_EncounterZoneAliases[zoneText] or zoneText
  end

  local function Norm(s)
    if not s then return nil end
    s = string.lower(s)
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
  end

  local function BossListed(zoneKey, name)
    if not zoneKey or not name then return false end
    local t = ShaguDPS_EncounterBosses[zoneKey]
    if not t then return false end
    for _, bn in pairs(t) do
      if bn == name then return true end
    end
    return false
  end

  local function BossListedAnyZone(name)
    if not name then return nil end
    for zk, list in pairs(ShaguDPS_EncounterBosses) do
      for _, bn in pairs(list) do
        if bn == name then return zk end
      end
    end
    return nil
  end

  local function LooksLikeBossTarget()
    if not UnitExists("target") or UnitIsPlayer("target") then return false end
    local lvl = UnitLevel("target")
    if lvl == -1 then return true end -- skull
    if type(UnitClassification) == "function" then
      local c = UnitClassification("target")
      if c == "worldboss" then return true end
    end
    return false
  end

  local function ResolveEncounterLabel(zoneKey, targetName)
    if not targetName then return nil end

    if zoneKey and BossListed(zoneKey, targetName) then
      return zoneKey, targetName
    end

    local any = BossListedAnyZone(targetName)
    if any then
      return any, targetName
    end

    if zoneKey then
      local z = ShaguDPS_EncounterAliases[zoneKey]
      if z then
        local tn = Norm(targetName)
        for label, triggers in pairs(z) do
          for _, trig in pairs(triggers) do
            if Norm(trig) == tn then
              return zoneKey, label
            end
          end
        end
      end
    end

    if LooksLikeBossTarget() then
      return zoneKey, targetName
    end

    return nil
  end

  local function HasAnyData(seg)
    if not seg then return false end
    for _ in pairs(seg) do return true end
    return false
  end

  local function FormatDuration(sec)
    sec = tonumber(sec) or 0
    if sec < 0 then sec = 0 end
    local m = math.floor(sec / 60)
    local s = math.floor(sec - (m * 60))
    if m < 10 then m = "0" .. m end
    if s < 10 then s = "0" .. s end
    return tostring(m) .. ":" .. tostring(s)
  end

  function ENC:Clear()
    self.archive.list = {}
    self.archive.counts = {}
    self.archive.selected = nil
    data.damage[2] = {}
    data.heal[2] = {}
    if window and window.Refresh then window.Refresh(true) end
  end

  function ENC:Select(entry)
    self.archive.selected = entry
    if entry then
      data.damage[2] = entry.damage or {}
      data.heal[2]   = entry.heal   or {}
    else
      data.damage[2] = {}
      data.heal[2]   = {}
    end
    if window and window.Refresh then window.Refresh(true) end
  end

  function ENC:Start()
    if not IsOn(config.encounters) then return end

    local zt = SafeZoneText()
    local zk = ZoneKey(zt)

    self.active = {
      start = GetTime(),
      zoneText = zt,
      zoneKey  = zk,
      name     = nil,
    }

    if UnitExists("target") and not UnitIsPlayer("target") then
      local tn = UnitName("target")
      local resolvedZone, label = ResolveEncounterLabel(zk, tn)
      if resolvedZone then self.active.zoneKey = resolvedZone end
      if label then self.active.name = label end
    end
  end

  function ENC:UpdateBossNameFromTarget()
    if not self.active then return end
    if not UnitExists("target") or UnitIsPlayer("target") then return end

    local tn = UnitName("target")
    local resolvedZone, label = ResolveEncounterLabel(self.active.zoneKey, tn)
    if resolvedZone then self.active.zoneKey = resolvedZone end
    if label then self.active.name = label end
  end

  function ENC:End()
    if not self.active then return end

    local stop = GetTime()
    local zone = self.active.zoneKey or (self.active.zoneText or "Unknown")
    local name = self.active.name
    local bossOnly = IsOn(config.encounters_bossonly)

    if bossOnly and (not name or name == "") then
      self.active = nil
      return
    end
    if (not bossOnly) and (not name or name == "") then
      name = "Trash"
    end

    if not HasAnyData(data.damage[1]) and not HasAnyData(data.heal[1]) then
      self.active = nil
      return
    end

    local key = tostring(zone) .. ":" .. tostring(name)
    self.archive.counts[key] = (self.archive.counts[key] or 0) + 1

    local entry = {
      zone   = zone,
      name   = name,
      count  = self.archive.counts[key],
      start  = self.active.start or (stop - 1),
      stop   = stop,
      damage = data.damage[1],
      heal   = data.heal[1],
    }

    table.insert(self.archive.list, entry)

    local keep = tonumber(config.encounters_keep) or 25
    while table.getn(self.archive.list) > keep do
      table.remove(self.archive.list, 1)
    end

    if IsOn(config.encounters_autoselect) then
      self:Select(entry)
    end

    self.active = nil
  end

  -- Hook ShaguDPS combat state transitions (COMBAT <-> NO_COMBAT)
  do
    local old = parser.combat and parser.combat.UpdateState
    if old and not ENC.__combat_hooked then
      ENC.__combat_hooked = true
      parser.combat.UpdateState = function(self)
        local prev = self.oldstate
        old(self)
        local cur = self.oldstate
        if cur ~= prev then
          if cur == "COMBAT" then ENC:Start()
          elseif cur == "NO_COMBAT" then ENC:End() end
        end
      end
    end
  end

  -- Update encounter label when you change targets
  do
    if not ENC.__target_hooked then
      ENC.__target_hooked = true
      local f = CreateFrame("Frame")
      f:RegisterEvent("PLAYER_TARGET_CHANGED")
      f:SetScript("OnEvent", function() ENC:UpdateBossNameFromTarget() end)
    end
  end

  -- Hook ResetData to also clear encounter history
  do
    if type(ResetData) == "function" and not ENC.__reset_hooked then
      ENC.__reset_hooked = true
      local oldReset = ResetData
      ResetData = function()
        oldReset()
        if ENC and ENC.Clear then ENC:Clear() end
      end
    end
  end

  -- Settings UI integration
  do
    if ShaguDPS.settings and ShaguDPS.settings.CreateConfig and not ENC.__settings_added then
      ENC.__settings_added = true
      local s = ShaguDPS.settings
      s:CreateConfig("Encounter History", nil, "header")
      s:CreateConfig("Track Encounters", "encounters", "boolean")
      s:CreateConfig("Bosses Only", "encounters_bossonly", "boolean")
      s:CreateConfig("Auto-select last", "encounters_autoselect", "boolean")
      s:CreateConfig("Keep last", "encounters_keep", "number", { 5, 10, 15, 20, 25, 30, 40, 50 })
    end
  end

  -- UI: Right-click segment button to choose encounter
  local function PatchWindowFrame(frame)
    if not frame or frame.__enc_patched then return end
    frame.__enc_patched = true

    if frame.Refresh then
      local oldRefresh = frame.Refresh
      frame.Refresh = function(self, force, report)
        oldRefresh(self, force, report)
        local wid = self:GetID()
        if config[wid] and config[wid].segment == 2 and self.btnSegment and self.btnSegment.caption then
          self.btnSegment.caption:SetText("Enc")
        end
      end
    end

    if frame.btnSegment and frame.btnSegment.GetScript then
      local oldSeg = frame.btnSegment:GetScript("OnClick")
      frame.btnSegment:RegisterForClicks("LeftButtonUp", "RightButtonUp")

      frame.btnSegment:SetScript("OnClick", function()
        if arg1 == "RightButton" then
          if not UIDropDownMenu_Initialize or not ToggleDropDownMenu then return end

          if not frame.__enc_dd then
            local ddName = "ShaguDPSEncounterDropDown" .. tostring(frame:GetID())
            frame.__enc_dd = CreateFrame("Frame", ddName, frame, "UIDropDownMenuTemplate")
            frame.__enc_dd.displayMode = "MENU"
          end

          local function NewInfo()
            if UIDropDownMenu_CreateInfo then return UIDropDownMenu_CreateInfo() end
            return {}
          end

          UIDropDownMenu_Initialize(frame.__enc_dd, function()
            local info

            info = NewInfo()
            info.isTitle = true
            info.notCheckable = true
            info.text = "Encounter History"
            UIDropDownMenu_AddButton(info)

            info = NewInfo()
            info.notCheckable = true
            info.text = "Overall"
            info.func = function()
              local wid = frame:GetID()
              if config[wid] then config[wid].segment = 0 end
              if window and window.Refresh then window.Refresh(true) end
            end
            UIDropDownMenu_AddButton(info)

            info = NewInfo()
            info.notCheckable = true
            info.text = "Current"
            info.func = function()
              local wid = frame:GetID()
              if config[wid] then config[wid].segment = 1 end
              if window and window.Refresh then window.Refresh(true) end
            end
            UIDropDownMenu_AddButton(info)

            info = NewInfo()
            info.notCheckable = true
            info.text = "Clear Encounter History"
            info.func = function() ENC:Clear() end
            UIDropDownMenu_AddButton(info)

            if table.getn(ENC.archive.list) == 0 then
              info = NewInfo()
              info.notCheckable = true
              info.disabled = true
              info.text = "(No encounters yet)"
              UIDropDownMenu_AddButton(info)
            else
              for i = table.getn(ENC.archive.list), 1, -1 do
                local e = ENC.archive.list[i]
                local label = tostring(e.zone or "?") .. " - " .. tostring(e.name or "?") ..
                  " #" .. tostring(e.count or 1) .. " (" .. FormatDuration((e.stop or 0) - (e.start or 0)) .. ")"

                info = NewInfo()
                info.notCheckable = true
                info.text = label
                info.checked = (ENC.archive.selected == e)
                info.func = function()
                  local wid = frame:GetID()
                  if config[wid] then config[wid].segment = 2 end
                  ENC:Select(e)
                end
                UIDropDownMenu_AddButton(info)
              end
            end
          end, "MENU")

          ToggleDropDownMenu(1, nil, frame.__enc_dd, "cursor", 0, 0)
        else
          if oldSeg then oldSeg() end
        end
      end)
    end
  end

  -- Wrap window.Refresh so frames get patched after creation
  do
    if window and window.Refresh and not ENC.__window_refresh_wrapped then
      ENC.__window_refresh_wrapped = true
      local oldWR = window.Refresh
      window.Refresh = function(force, report)
        oldWR(force, report)
        for i = 1, 10 do
          if window[i] then PatchWindowFrame(window[i]) end
        end
      end
    end
  end

  for i = 1, 10 do
    if window[i] then PatchWindowFrame(window[i]) end
  end

  return true
end

-- Deferred init
do
  local f = CreateFrame("Frame")
  local tries = 0
  f:SetScript("OnUpdate", function()
    tries = tries + 1
    if __ShaguDPSEncounters_Init() then
      this:SetScript("OnUpdate", nil)
    elseif tries > 200 then
      this:SetScript("OnUpdate", nil)
    end
  end)
end
