--[[
	Gatherer Reforged - Modern Loot & World Object Gathering Scanner (Gatherer.Scanner)
	Supports Classic Era, Classic Progression, Retail (11.x / 12.x), and dynamic future expansion nodes ("Forever").
	Author: gOOvER
	License: GNU General Public License v3.0 (GPL-3.0)
]]

Gatherer = Gatherer or {}
Gatherer.Scanner = Gatherer.Scanner or {}
Gatherer_DynamicNodes = Gatherer_DynamicNodes or {}

local Scanner = Gatherer.Scanner

local hooks = {}
local lastTip = { tip = nil, time = 0, gType = nil, isRedReq = false }
local lastClick = { tip = nil, time = 0, gType = nil }
local lastCast = { target = nil, spellID = nil, gType = nil, time = 0 }
local lootProcessed = false

-- Known gathering spell IDs and textures across all WoW versions
local MINE_SPELLS = {
	[2575] = true, [2576] = true, [3564] = true, [10248] = true,
	[29354] = true, [50310] = true, [74517] = true, [102161] = true,
	[158754] = true, [195122] = true, [265837] = true, [309835] = true,
	[366260] = true, [423341] = true,
}

local HERB_SPELLS = {
	[2366] = true, [2368] = true, [3570] = true, [11993] = true,
	[28695] = true, [50300] = true, [74519] = true, [110413] = true,
	[158745] = true, [195114] = true, [265819] = true, [309780] = true,
	[366252] = true, [423339] = true,
}

local ARCH_SPELLS = {
	[73979] = true, [92828] = true,
}

local OPEN_SPELLS = {
	[3365] = true, [6247] = true, [6477] = true, [6478] = true, [22810] = true,
	-- Fishing (schools / wreckage) & Engineering Gas Cloud extraction & Logging
	[7620] = true, [7731] = true, [7732] = true, [18248] = true, [33095] = true,
	[51294] = true, [88868] = true, [110410] = true, [131474] = true, [131476] = true,
	[131490] = true, [158743] = true, [30427] = true, [167895] = true, [167898] = true,
}

local function isSafeString(val)
	if Gatherer and Gatherer.IsSafeString then
		return Gatherer.IsSafeString(val)
	end
	if type(val) ~= "string" then return false end
	if _G.issecretvalue and _G.issecretvalue(val) then return false end
	if _G.canaccessvalue and not _G.canaccessvalue(val) then return false end
	local ok, nonEmpty = pcall(function() return val ~= "" end)
	return ok and nonEmpty
end

local function isSafeValue(val)
	if Gatherer and Gatherer.IsSafeValue then
		return Gatherer.IsSafeValue(val)
	end
	if val == nil then return false end
	if _G.issecretvalue and _G.issecretvalue(val) then return false end
	if _G.canaccessvalue and not _G.canaccessvalue(val) then return false end
	return true
end

local function detectGatherTypeFromSpell(spellID)
	if not isSafeValue(spellID) or type(spellID) ~= "number" then return nil end
	if MINE_SPELLS[spellID] then return "MINE" end
	if HERB_SPELLS[spellID] then return "HERB" end
	if ARCH_SPELLS[spellID] then return "ARCH" end
	if OPEN_SPELLS[spellID] then return "OPEN" end

	local name, _, icon = GetSpellInfo(spellID)
	if icon == 134708 or icon == 136248 or icon == 136025 then
		return "MINE"
	elseif icon == 136246 then
		return "HERB"
	elseif icon == 441139 then
		return "ARCH"
	end

	if isSafeString(name) and Gatherer and Gatherer.Locale and Gatherer.Locale.TrClient then
		local herbName = Gatherer.Locale.TrClient("TRADE_HERBALISM")
		local mineName = Gatherer.Locale.TrClient("TRADE_MINING")
		if herbName and name:find(herbName, 1, true) then return "HERB" end
		if mineName and name:find(mineName, 1, true) then return "MINE" end
		if OPENING and name == OPENING then return "OPEN" end
	end
	return nil
end

local function detectGatherTypeFromTooltip()
	if not GameTooltip or not GameTooltip:IsShown() then return nil, false end

	local detectedType = nil
	local isRedRequirement = false

	for i = 2, math.min(5, GameTooltip:NumLines() or 0) do
		local lineObj = _G["GameTooltipTextLeft" .. i]
		local ok, text = pcall(function() return lineObj and lineObj:GetText() end)
		if ok and isSafeString(text) then
			local rOk, r, g, b = pcall(function() return lineObj:GetTextColor() end)
			if rOk and type(r) == "number" and type(g) == "number" and type(b) == "number" then
				if r > 0.8 and g < 0.25 and b < 0.25 then
					isRedRequirement = true
				end
			end
			if Gatherer and Gatherer.Locale and Gatherer.Locale.TrClient then
				local herbName = Gatherer.Locale.TrClient("TRADE_HERBALISM")
				local mineName = Gatherer.Locale.TrClient("TRADE_MINING")
				if herbName and text:find(herbName, 1, true) then detectedType = "HERB" end
				if mineName and text:find(mineName, 1, true) then detectedType = "MINE" end
			end
		end
	end
	return detectedType, isRedRequirement
end

local function cleanTooltipLine(text)
	if not isSafeString(text) then return nil end
	text = text:gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return text:match("^%s*(.-)%s*$")
end

function Scanner.SetTooltip()
	pcall(function()
		if not GameTooltip or not GameTooltip:IsShown() then return end
		if UnitExists and UnitExists("mouseover") then
			-- Clear lastTip when hovering over a unit/mob corpse so mob loots never inherit a previous node tooltip
			lastTip.tip = nil
			lastTip.gType = nil
			lastTip.isRedReq = false
			lastTip.time = 0
			return
		end
		local owner = GameTooltip:GetOwner()
		if owner and owner ~= UIParent and owner ~= WorldFrame then return end

		local line1 = _G["GameTooltipTextLeft1"]
		if not line1 then return end
		local text = cleanTooltipLine(line1:GetText())
		if isSafeString(text) then
			local knownObjId = Gatherer and Gatherer.Nodes and (
				(Gatherer.Nodes.ResolveNodeByName and Gatherer.Nodes.ResolveNodeByName(text))
				or (Gatherer.Nodes.Names and Gatherer.Nodes.Names[text])
			)
			local knownType = knownObjId and Gatherer.Nodes.Objects and Gatherer.Nodes.Objects[knownObjId]
			local tipType, isRedReq = detectGatherTypeFromTooltip()
			lastTip.tip = text
			lastTip.time = GetTime()
			lastTip.gType = tipType or knownType
			lastTip.isRedReq = isRedReq
			if Gatherer and Gatherer.Nodes and not Gatherer.Nodes.Names[text] and (tipType == "HERB" or tipType == "MINE") and Gatherer.Nodes.RegisterDynamicNode then
				Gatherer.Nodes.RegisterDynamicNode(text, tipType, nil, knownObjId)
			end
		end
	end)
end

-- Live Minimap Radar Tracking State (inspired by GatherRadar)
local liveNodes = {} -- [zoneToken .. ":" .. gType .. ":" .. coordKey] = timestamp
local LIVE_DURATION = 10

local function makeCoordKey(x, y)
	return math.floor((x or 0) * 1000 + 0.5) * 10000 + math.floor((y or 0) * 1000 + 0.5)
end

function Scanner.MarkNodeLive(zoneToken, gType, x, y)
	if not (zoneToken and gType and x and y) then return end
	local key = tostring(zoneToken) .. ":" .. tostring(gType) .. ":" .. tostring(makeCoordKey(x, y))
	liveNodes[key] = GetTime()
end

function Scanner.ClearNodeLive(zoneToken, gType, x, y)
	if not (zoneToken and gType and x and y) then return end
	local key = tostring(zoneToken) .. ":" .. tostring(makeCoordKey(x, y))
	liveNodes[tostring(zoneToken) .. ":" .. tostring(gType) .. ":" .. tostring(makeCoordKey(x, y))] = nil
end

function Scanner.IsNodeLive(zoneToken, gType, x, y)
	if not (zoneToken and gType and x and y) then return false end
	local now = GetTime()
	local cx = math.floor((x or 0) * 1000 + 0.5)
	local cy = math.floor((y or 0) * 1000 + 0.5)
	local prefix = tostring(zoneToken) .. ":" .. tostring(gType) .. ":"
	for dx = -2, 2 do
		for dy = -2, 2 do
			local t = liveNodes[prefix .. tostring((cx + dx) * 10000 + (cy + dy))]
			if t and (now - t) < LIVE_DURATION then
				return true
			end
		end
	end
	return false
end

local lastUnskilledObj = nil
local lastUnskilledTime = 0

function Scanner.RecordUnskilledGather(tipName, fallbackGType)
	tipName = cleanTooltipLine(tipName)
	if not isSafeString(tipName) then return false end
	if UnitOnTaxi and UnitOnTaxi("player") then return false end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false end
	if not Gatherer or not Gatherer.Nodes or not Gatherer.Api or not Gatherer.Api.AddGather then return false end

	-- Only record unskilled gathers when the player explicitly right-clicked the object recently (never on mouseover)
	local now = GetTime()
	if not lastClick.tip or (now - (lastClick.time or 0)) > 1.5 or lastClick.tip ~= tipName then
		return false
	end

	local objId = (Gatherer.Nodes.ResolveNodeByName and Gatherer.Nodes.ResolveNodeByName(tipName))
		or Gatherer.Nodes.Names[tipName]
	local objGType = objId and Gatherer.Nodes.Objects[objId]

	-- Never record a stale HERB tooltip when a MINE error fired (or vice-versa)
	if fallbackGType and objGType and objGType ~= fallbackGType then
		return false
	end

	local gType = objGType or fallbackGType or lastClick.gType or lastTip.gType
	if not objId and (gType == "HERB" or gType == "MINE") and Gatherer.Nodes.RegisterDynamicNode then
		objId = Gatherer.Nodes.RegisterDynamicNode(tipName, gType)
	elseif objId and not Gatherer.Nodes.Names[tipName] then
		Gatherer.Nodes.Names[tipName] = objId
	end
	if not objId or (gType ~= "HERB" and gType ~= "MINE" and gType ~= "OPEN") then
		return false
	end

	if lastUnskilledObj == objId and (now - lastUnskilledTime) < 5 then
		return false
	end
	lastUnskilledObj = objId
	lastUnskilledTime = now
	lastClick.tip = nil
	lastClick.time = 0

	return Gatherer.Api.AddGather(objId, gType, nil, "REQUIRE", 0, {}, false)
end

function Scanner.GetLastTip()
	if lastTip.tip and (GetTime() - (lastTip.time or 0)) < 2.0 then
		return lastTip
	end
	return nil
end

function Scanner.RegisterHook(name, lootHook, castHook)
	hooks[name] = {
		loot = lootHook,
		cast = castHook,
	}
end

local function parseCopperFromMoneyString(str)
	if type(str) ~= "string" then return 0 end
	local total = 0
	for num in str:gmatch("(%d+)") do
		total = total * 100 + (tonumber(num) or 0)
	end
	return total
end

local TRADE_GOODS_CLASS = 7
local SUBCLASS_HERB = 9
local SUBCLASS_METAL_STONE = 7
local getItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant

local function processLoot()
	if lootProcessed then return end
	lootProcessed = true

	if IsFishingLoot and IsFishingLoot() then return end

	-- Verify loot source GUID: reject Mob corpses ("Creature-", "Vehicle-") and bag items ("Item-")
	local isGameObjectLoot = false
	if GetLootSourceInfo then
		local ok, srcGuid = pcall(GetLootSourceInfo, 1)
		if ok and isSafeString(srcGuid) and srcGuid ~= "" then
			if srcGuid:sub(1, 11) == "GameObject-" then
				isGameObjectLoot = true
			else
				return
			end
		end
	end

	local nodeName = nil
	local gType = nil
	local hasRecentGatherCast = false
	local now = GetTime()

	if lastCast.target and (now - (lastCast.time or 0)) < 8 then
		nodeName = lastCast.target
		gType = lastCast.gType
		if gType == "HERB" or gType == "MINE" or gType == "OPEN" or gType == "ARCH" then
			hasRecentGatherCast = true
		end
	end
	if not nodeName and lastTip.tip and (now - (lastTip.time or 0)) < 3 then
		nodeName = lastTip.tip
		gType = gType or lastTip.gType
	end
	nodeName = cleanTooltipLine(nodeName)
	if not nodeName then return end

	-- Additional fallback guard for clients without GetLootSourceInfo: reject dead unit targets/mouseovers
	if not isGameObjectLoot and UnitExists then
		if (UnitExists("target") and UnitIsDead and UnitIsDead("target"))
			or (UnitExists("mouseover") and UnitIsDead and UnitIsDead("mouseover")) then
			return
		end
	end

	local resolvedId = Gatherer and Gatherer.Nodes and (
		(Gatherer.Nodes.ResolveNodeByName and Gatherer.Nodes.ResolveNodeByName(nodeName))
		or (Gatherer.Nodes.Names and Gatherer.Nodes.Names[nodeName])
	)
	-- On clients without GetLootSourceInfo, require either a known built-in node (< 900000) or an explicit recent HERB/MINE spellcast
	if not isGameObjectLoot and not (resolvedId and resolvedId < 900000) and not (hasRecentGatherCast and (gType == "HERB" or gType == "MINE")) then
		return
	end

	local lootTable = {}
	local coinAmount = 0
	local primaryItemID = nil
	local lootDetectedType = nil
	local hasQuestItem = false
	local numSlots = GetNumLootItems and GetNumLootItems() or 0
	local QUEST_ITEM_CLASS = 12

	for slot = 1, numSlots do
		local slotType = GetLootSlotType and GetLootSlotType(slot)
		local texture, item, quantity, a4, a5, a6, a7 = GetLootSlotInfo(slot)
		local link = GetLootSlotLink and GetLootSlotLink(slot)

		-- Detect quest items across Classic/Wrath (6th return = isQuestItem) and Retail (7th return = isQuestItem)
		if a6 == true or a7 == true or (LOOT_SLOT_QUEST and slotType == LOOT_SLOT_QUEST) then
			hasQuestItem = true
		end

		local isMoney = (LOOT_SLOT_MONEY and slotType == LOOT_SLOT_MONEY)
			or (Enum and Enum.LootSlotType and slotType == Enum.LootSlotType.Money)
		local isCurrency = (LOOT_SLOT_CURRENCY and slotType == LOOT_SLOT_CURRENCY)
			or (Enum and Enum.LootSlotType and slotType == Enum.LootSlotType.Currency)

		if isMoney then
			coinAmount = coinAmount + parseCopperFromMoneyString(item)
		elseif isCurrency and a4 then
			table.insert(lootTable, {
				id = a4,
				count = quantity or 1,
				type = LOOT_SLOT_CURRENCY or 3,
			})
		elseif link and isSafeString(link) then
			local itemID = tonumber(link:match("item:(%d+)"))
			if getItemInfoInstant then
				local ok, instID, itemType, _, _, _, classID, subclassID = pcall(getItemInfoInstant, link)
				if ok and instID then
					itemID = itemID or instID
					if classID == QUEST_ITEM_CLASS or (isSafeString(itemType) and itemType:lower():find("quest", 1, true)) then
						hasQuestItem = true
					elseif classID == TRADE_GOODS_CLASS then
						if subclassID == SUBCLASS_HERB and not lootDetectedType then
							lootDetectedType = "HERB"
							primaryItemID = itemID
						elseif subclassID == SUBCLASS_METAL_STONE and not lootDetectedType then
							lootDetectedType = "MINE"
							primaryItemID = itemID
						end
					end
				end
			end
			if GetItemInfo then
				local okInfo, _, _, _, _, _, itemTypeStr, _, _, _, _, _, classID2 = pcall(GetItemInfo, link)
				if okInfo and (classID2 == QUEST_ITEM_CLASS or (isSafeString(itemTypeStr) and itemTypeStr:lower():find("quest", 1, true))) then
					hasQuestItem = true
				end
			end
			if itemID and not primaryItemID then
				primaryItemID = itemID
			end
			table.insert(lootTable, {
				link = link,
				id = itemID,
				count = isSafeValue(quantity) and tonumber(quantity) or 1,
				type = slotType,
			})
		end
	end

	-- Never record unknown world objects that drop quest items or lack genuine herb/ore trade goods
	if not (resolvedId and resolvedId < 900000) then
		if hasQuestItem or not lootDetectedType then
			lastCast.target = nil
			lastCast.gType = nil
			lastCast.time = 0
			return
		end
		gType = lootDetectedType
	end

	if not gType and isGameObjectLoot and lootDetectedType then
		gType = lootDetectedType
	elseif not gType and isGameObjectLoot and resolvedId then
		gType = Gatherer.Nodes.Objects[resolvedId]
	end

	if Gatherer and Gatherer.Nodes then
		local objId = resolvedId
		if objId then
			if not Gatherer.Nodes.Names[nodeName] then
				Gatherer.Nodes.Names[nodeName] = objId
			end
			gType = Gatherer.Nodes.Objects[objId] or gType
			if primaryItemID and Gatherer.Nodes.PrimaryItems and not Gatherer.Nodes.PrimaryItems[objId] then
				Gatherer.Nodes.PrimaryItems[objId] = primaryItemID
			end
		elseif (gType == "HERB" or gType == "MINE") and Gatherer.Nodes.RegisterDynamicNode then
			objId = Gatherer.Nodes.RegisterDynamicNode(nodeName, gType, primaryItemID)
		else
			return
		end
	end

	-- Clear cast/tip state after processing so subsequent mob loots cannot reuse it
	lastCast.target = nil
	lastCast.gType = nil
	lastCast.time = 0
	lastTip.tip = nil
	lastTip.gType = nil
	lastTip.time = 0

	if not gType then return end

	if Gatherer and Gatherer.Util and Gatherer.Util.GetPositionInCurrentZone then
		local zToken, px, py = Gatherer.Util.GetPositionInCurrentZone()
		if zToken and px and py then
			Scanner.ClearNodeLive(zToken, gType, px, py)
		end
	end

	local extraData = { tip = nodeName }
	for _, h in pairs(hooks) do
		if h.loot then
			h.loot(gType, lootTable, coinAmount, extraData)
		end
	end
end

-- ============================================================================
-- Virtual Minimap Radar Scanner (Coroutine-based, inspired by GatherRadar)
-- Automatically detects tracked herbs, ores, and treasures on the Minimap
-- from up to ~100 yards away without requiring the player to walk up to them.
-- ============================================================================
local RADAR_STEP = 6
local RADAR_PROBES_PER_FRAME = 75
local RADAR_WAIT_MOVING = 1.2
local RADAR_WAIT_STILL = 3.0
local RADAR_REACH = 24
local AROUND_OFFSETS = { -1001, -1000, -999, -1, 1, 999, 1000, 1001 }

local radarCo = nil
local radarWait = 1.5
local radarProbes = 0
local lastRadarX, lastRadarY, lastRadarFacing, lastRadarRadius
local radarSeenIds = {}

local function probeMinimapPoint(left, bottom, scale, x, y)
	wipe(radarSeenIds)
	radarProbes = radarProbes + 1
	if radarProbes >= RADAR_PROBES_PER_FRAME then
		radarProbes = 0
		coroutine.yield()
	end
	if not (Minimap and Minimap:IsVisible() and not Minimap:IsMouseOver()) then
		return radarSeenIds
	end
	Minimap:UpdateMouseoverAtPoint((left + x) * scale, (bottom + y) * scale)
	local data = C_TooltipInfo and C_TooltipInfo.GetMinimapMouseover and C_TooltipInfo.GetMinimapMouseover()
	local lines = data and isSafeValue(data) and data.lines
	if not lines or not isSafeValue(lines) then return radarSeenIds end

	for _, line in ipairs(lines) do
		local rawText = line and line.leftText
		if isSafeString(rawText) then
			for subLine in rawText:gmatch("[^\n]+") do
				local cleaned = cleanTooltipLine(subLine)
				if cleaned and cleaned ~= "" then
					local objId = Gatherer and Gatherer.Nodes and (
						(Gatherer.Nodes.ResolveNodeByName and Gatherer.Nodes.ResolveNodeByName(cleaned))
						or (Gatherer.Nodes.Names and Gatherer.Nodes.Names[cleaned])
					)
					local gType = objId and Gatherer.Nodes.Objects and Gatherer.Nodes.Objects[objId]
					if objId and (gType == "HERB" or gType == "MINE" or gType == "OPEN") then
						radarSeenIds[objId] = cleaned
					end
				end
			end
		end
	end
	return radarSeenIds
end

local function findBlipEdge(left, bottom, scale, objId, cx, cy, dx, dy)
	local hit, miss = 0, nil
	for d = 2, RADAR_REACH, 2 do
		if not probeMinimapPoint(left, bottom, scale, cx + dx * d, cy + dy * d)[objId] then
			miss = d
			break
		end
		hit = d
	end
	if not miss then return hit end
	for _ = 1, 4 do
		local mid = (hit + miss) / 2
		if probeMinimapPoint(left, bottom, scale, cx + dx * mid, cy + dy * mid)[objId] then
			hit = mid
		else
			miss = mid
		end
	end
	return (hit + miss) / 2
end

local function groupGridPoints(points)
	local groups, done = {}, {}
	for start in pairs(points) do
		if not done[start] then
			local group, queue = {}, { start }
			done[start] = true
			while #queue > 0 do
				local p = table.remove(queue)
				table.insert(group, p)
				for _, off in ipairs(AROUND_OFFSETS) do
					local q = p + off
					if points[q] and not done[q] then
						done[q] = true
						table.insert(queue, q)
					end
				end
			end
			table.insert(groups, group)
		end
	end
	return groups
end

local function minimapOffsetToZoneCoords(ox, oy)
	local Map = Gatherer and Gatherer.Map
	if not Map then return nil end
	local mapID, mapFloor, px, py = Map:GetCurrentPlayerPosition()
	local radius = Map:GetMinimapRadius()
	if not (mapID and px and py and radius and radius > 0) then return nil end

	local halfWidth = (Minimap:GetWidth() or 140) / 2
	if halfWidth <= 0 then return nil end
	local yardsPerUnit = radius / halfWidth
	local east, north = ox * yardsPerUnit, oy * yardsPerUnit

	if Map:IsRotateMinimapEnabled() then
		local f = GetPlayerFacing and GetPlayerFacing()
		if not f then return nil end
		east, north = east * math.cos(f) - north * math.sin(f), east * math.sin(f) + north * math.cos(f)
	end

	local _, _, w, h = Map:GetMapInfo(mapID, mapFloor)
	if not (w and h and w > 0 and h > 0) then return nil end

	local nx = px + (east / w)
	local ny = py - (north / h)
	if nx <= 0 or nx >= 1 or ny <= 0 or ny >= 1 then return nil end

	local zoneToken = Gatherer.ZoneTokens and Gatherer.ZoneTokens.GetZoneToken(mapID)
	if not zoneToken then return nil end
	return zoneToken, nx, ny
end

local function runMinimapRadarScan()
	local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
	local scale = Minimap:GetEffectiveScale()
	local size = Minimap:GetWidth()
	if not (left and bottom and scale and size and size > 0) then return end

	local half = size / 2
	local hits = {}
	local limit = (half - 2) ^ 2
	local maxSteps = math.floor(size / RADAR_STEP)

	for gx = 0, maxSteps do
		for gy = 0, maxSteps do
			local x, y = gx * RADAR_STEP, gy * RADAR_STEP
			if (x - half) ^ 2 + (y - half) ^ 2 <= limit then
				for objId in pairs(probeMinimapPoint(left, bottom, scale, x, y)) do
					hits[objId] = hits[objId] or {}
					hits[objId][gx * 1000 + gy] = true
				end
			end
		end
	end

	for objId, points in pairs(hits) do
		local gType = Gatherer.Nodes.Objects[objId]
		if gType then
			for _, group in ipairs(groupGridPoints(points)) do
				local sx, sy = 0, 0
				for _, p in ipairs(group) do
					sx = sx + math.floor(p / 1000) * RADAR_STEP
					sy = sy + (p % 1000) * RADAR_STEP
				end
				local cx, cy = sx / #group, sy / #group
				if probeMinimapPoint(left, bottom, scale, cx, cy)[objId] then
					local r = findBlipEdge(left, bottom, scale, objId, cx, cy, 1, 0)
					local l = findBlipEdge(left, bottom, scale, objId, cx, cy, -1, 0)
					local u = findBlipEdge(left, bottom, scale, objId, cx, cy, 0, 1)
					local d = findBlipEdge(left, bottom, scale, objId, cx, cy, 0, -1)
					cx = cx + (r - l) / 2
					cy = cy + (u - d) / 2
				end

				local zoneToken, zx, zy = minimapOffsetToZoneCoords(cx - half, cy - half)
				if zoneToken and zx and zy then
					Scanner.MarkNodeLive(zoneToken, gType, zx, zy)
					Gatherer.Api.AddGather(objId, gType, nil, "REQUIRE", 0, {}, false, nil, zoneToken, zx, zy)
				end
			end
		end
	end
end

local function canRunRadarScan()
	if not (Minimap and Minimap:IsVisible() and Minimap.UpdateMouseoverAtPoint and C_TooltipInfo and C_TooltipInfo.GetMinimapMouseover) then
		return false
	end
	if Minimap:IsMouseOver() then return false end
	if InCombatLockdown and InCombatLockdown() then return false end
	if UnitOnTaxi and UnitOnTaxi("player") then return false end
	if Gatherer and Gatherer.Config and Gatherer.Config.GetSetting and not Gatherer.Config.GetSetting("minimap.enable", true) then
		return false
	end
	return true
end

local function resumeRadarScan()
	if not radarCo then return end
	if Minimap.SetUsingSoftCursor then pcall(Minimap.SetUsingSoftCursor, Minimap, true) end
	local ok = coroutine.resume(radarCo)
	if Minimap.SetUsingSoftCursor then pcall(Minimap.SetUsingSoftCursor, Minimap, false) end
	if not ok or coroutine.status(radarCo) == "dead" then
		radarCo = nil
	end
end

local function updateRadarScanner(elapsed)
	if radarCo then
		if not canRunRadarScan() then
			radarCo = nil
			return
		end
		resumeRadarScan()
		return
	end
	radarWait = radarWait - elapsed
	if radarWait > 0 then return end

	local Map = Gatherer and Gatherer.Map
	if Map then
		local _, _, px, py = Map:GetCurrentPlayerPosition()
		local f = GetPlayerFacing and GetPlayerFacing()
		local r = Map:GetMinimapRadius()
		local still = (px == lastRadarX and py == lastRadarY and f == lastRadarFacing and r == lastRadarRadius)
		lastRadarX, lastRadarY, lastRadarFacing, lastRadarRadius = px, py, f, r
		radarWait = still and RADAR_WAIT_STILL or RADAR_WAIT_MOVING
	else
		radarWait = RADAR_WAIT_STILL
	end

	if not canRunRadarScan() then return end
	radarProbes = 0
	radarCo = coroutine.create(runMinimapRadarScan)
	resumeRadarScan()
end

local scannerFrame
function Scanner.Init()
	if scannerFrame then return end
	scannerFrame = CreateFrame("Frame", "GathererScannerFrame")
	scannerFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
	scannerFrame:RegisterEvent("LOOT_READY")
	scannerFrame:RegisterEvent("LOOT_OPENED")
	scannerFrame:RegisterEvent("LOOT_CLOSED")
	scannerFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")

	scannerFrame:SetScript("OnEvent", function(self, event, ...)
		if event == "UNIT_SPELLCAST_SENT" then
			local unit, target, castGUID, spellID = ...
			if isSafeString(unit) and unit == "player" then
				-- In older clients UNIT_SPELLCAST_SENT passed (unit, spellName, rank, target)
				if not isSafeValue(spellID) or type(spellID) ~= "number" then
					local _, _, oldTarget, oldSpellID = select(2, ...)
					if isSafeString(oldTarget) then
						target = oldTarget
					end
					spellID = isSafeValue(oldSpellID) and tonumber(oldSpellID) or nil
				end
				local spellGType = detectGatherTypeFromSpell(spellID)
				target = cleanTooltipLine(target)
				if isSafeString(target) and spellGType then
					lastCast.target = target
					lastCast.spellID = spellID
					lastCast.gType = spellGType
					lastCast.time = GetTime()
				elseif not spellGType then
					lastCast.target = nil
					lastCast.spellID = nil
					lastCast.gType = nil
					lastCast.time = 0
				end
			end
		elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
			processLoot()
		elseif event == "LOOT_CLOSED" then
			lootProcessed = false
			lastCast.target = nil
			lastCast.gType = nil
			lastCast.time = 0
			lastTip.tip = nil
			lastTip.gType = nil
			lastTip.time = 0
			lastClick.tip = nil
			lastClick.gType = nil
			lastClick.time = 0
		elseif event == "UPDATE_MOUSEOVER_UNIT" then
			Scanner.SetTooltip()
		end
	end)

	if GameTooltip then
		GameTooltip:HookScript("OnShow", function()
			Scanner.SetTooltip()
		end)
	end

	if WorldFrame and WorldFrame.HookScript then
		WorldFrame:HookScript("OnMouseDown", function(_, button)
			-- Only record click intent on RightButton (interact with object), never save nodes on mouse down!
			if button ~= "RightButton" then return end
			if not GameTooltip or not GameTooltip:IsShown() then return end
			if UnitExists and UnitExists("mouseover") then return end
			local owner = GameTooltip:GetOwner()
			if owner and owner ~= UIParent and owner ~= WorldFrame then return end

			Scanner.SetTooltip()
			if lastTip.tip and (GetTime() - (lastTip.time or 0)) < 1.0 then
				lastClick.tip = lastTip.tip
				lastClick.gType = lastTip.gType
				lastClick.time = GetTime()
			end
		end)
	end
end

