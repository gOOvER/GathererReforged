--[[
	Gatherer Reforged - External Addon Integrations & Advanced Farming Suite (Gatherer.Integrations)
	Version: 1.0.0
	Author: gOOvER
	License: GNU General Public License v3.0 (GPL-3.0)

	Provides:
	1. GatherMate2 & GatherMate2_Data / GatherMate2Storage_* 1-Click Database Importer
	   (Classic, TBC, Wrath, Cata, MoP, WoD, Legion, BfA, SL, DF, TWW, Midnight & WoW Forever)
	2. Auctionator, TradeSkillMaster (TSM), OEMarketInfo & RECrystallize Live Market Prices
	3. Live Session Statistics & Gold-per-Hour (GPH) / Nodes-per-Hour Tracker + LDB Feed
	4. Harvest Cooldown ("Respawn Timer") Dimming for Minimap & 3D HUD
	5. FarmHud & Routes Addon Compatibility Bridges
]]

Gatherer = Gatherer or {}
Gatherer.Integrations = Gatherer.Integrations or {}

local Integrations = Gatherer.Integrations
local floor = math.floor
local max = math.max

--------------------------------------------------------------------------------
-- 1. Money Formatting & Auction House / Market Value API
--------------------------------------------------------------------------------

function Integrations.FormatMoney(copper)
	copper = floor(tonumber(copper) or 0)
	if copper <= 0 then
		return "|cff8888880c|r"
	end
	if _G.GetCoinTextureString then
		local ok, str = pcall(_G.GetCoinTextureString, copper, 12)
		if ok and type(str) == "string" and str ~= "" then
			return str
		end
	end
	local g = floor(copper / 10000)
	local s = floor((copper % 10000) / 100)
	local c = copper % 100
	local parts = {}
	if g > 0 then table.insert(parts, string.format("|cffffd700%dg|r", g)) end
	if s > 0 or g > 0 then table.insert(parts, string.format("|cffc7c7cf%ds|r", s)) end
	table.insert(parts, string.format("|cffeda55f%dc|r", c))
	return table.concat(parts, " ")
end

local PRICE_SOURCE_ORDER = { "AUCTIONEER", "AUCTIONATOR", "TSM", "OE", "RECRYSTALLIZE", "VENDOR" }

local function isPriceSourceAvailable(sourceKey)
	if sourceKey == "AUTO" or sourceKey == "VENDOR" then
		return true
	elseif sourceKey == "AUCTIONEER" then
		return type(_G.AucAdvanced) == "table" and type(_G.AucAdvanced.API) == "table" and type(_G.AucAdvanced.API.GetMarketValue) == "function"
	elseif sourceKey == "AUCTIONATOR" then
		return type(_G.Auctionator) == "table" and type(_G.Auctionator.API) == "table" and type(_G.Auctionator.API.v1) == "table"
	elseif sourceKey == "TSM" then
		return type(_G.TSM_API) == "table" and type(_G.TSM_API.GetCustomPriceValue) == "function"
	elseif sourceKey == "OE" then
		return type(_G.OEMarketInfo) == "function"
	elseif sourceKey == "RECRYSTALLIZE" then
		return type(_G.RECrystallize_PriceCheckItemID) == "function"
	end
	return false
end

function Integrations.GetAvailablePriceSources()
	local trL = Gatherer and Gatherer.Locale and Gatherer.Locale.Translate
	local autoLabel = (trL and trL("CONFIG_PRICE_SOURCE_AUTO"))
	if not autoLabel or autoLabel == "CONFIG_PRICE_SOURCE_AUTO" then autoLabel = "Auto" end
	local vendorLabel = (trL and trL("CONFIG_PRICE_SOURCE_VENDOR"))
	if not vendorLabel or vendorLabel == "CONFIG_PRICE_SOURCE_VENDOR" then vendorLabel = "Vendor" end

	local sources = {
		["AUTO"] = autoLabel,
	}
	if isPriceSourceAvailable("AUCTIONEER") then
		sources["AUCTIONEER"] = "Auctioneer Reforged"
	end
	if isPriceSourceAvailable("AUCTIONATOR") then
		sources["AUCTIONATOR"] = "Auctionator"
	end
	if isPriceSourceAvailable("TSM") then
		sources["TSM"] = "TradeSkillMaster (TSM)"
	end
	if isPriceSourceAvailable("OE") then
		sources["OE"] = "OribosExchange"
	end
	if isPriceSourceAvailable("RECRYSTALLIZE") then
		sources["RECRYSTALLIZE"] = "RECrystallize"
	end
	sources["VENDOR"] = vendorLabel
	return sources
end

local function queryPriceSource(sourceKey, itemID, itemLink)
	if sourceKey == "AUCTIONEER" and isPriceSourceAvailable("AUCTIONEER") then
		local linkOrID = itemLink or select(2, GetItemInfo(itemID)) or itemID
		local ok, price = pcall(_G.AucAdvanced.API.GetMarketValue, linkOrID)
		if (not ok or not price or price <= 0) and _G.AucAdvanced.Modules and _G.AucAdvanced.Modules.Util and _G.AucAdvanced.Modules.Util.Appraiser and type(_G.AucAdvanced.Modules.Util.Appraiser.GetPrice) == "function" then
			ok, price = pcall(_G.AucAdvanced.Modules.Util.Appraiser.GetPrice, linkOrID)
		end
		if ok and type(price) == "number" and price > 0 then
			return price, "Auctioneer"
		end
	elseif sourceKey == "AUCTIONATOR" and isPriceSourceAvailable("AUCTIONATOR") then
		local api = _G.Auctionator.API.v1
		if itemLink and type(api.GetAuctionPriceByItemLink) == "function" then
			local ok, price = pcall(api.GetAuctionPriceByItemLink, "GathererReforged", itemLink)
			if ok and type(price) == "number" and price > 0 then
				return price, "Auctionator"
			end
		end
		if type(api.GetAuctionPriceByItemID) == "function" then
			local ok, price = pcall(api.GetAuctionPriceByItemID, "GathererReforged", itemID)
			if ok and type(price) == "number" and price > 0 then
				return price, "Auctionator"
			end
		end
	elseif sourceKey == "TSM" and isPriceSourceAvailable("TSM") then
		local itemString = "i:" .. tostring(itemID)
		local ok, price = pcall(_G.TSM_API.GetCustomPriceValue, "dbmarket", itemString)
		if (not ok or not price or price <= 0) then
			ok, price = pcall(_G.TSM_API.GetCustomPriceValue, "dbminbuyout", itemString)
		end
		if ok and type(price) == "number" and price > 0 then
			return price, "TSM"
		end
	elseif sourceKey == "OE" and isPriceSourceAvailable("OE") then
		local temp = {}
		local ok = pcall(_G.OEMarketInfo, itemID, temp)
		if ok and type(temp.market) == "number" and temp.market > 0 then
			return temp.market, "OE"
		elseif ok and type(temp.region) == "number" and temp.region > 0 then
			return temp.region, "OE"
		end
	elseif sourceKey == "RECRYSTALLIZE" and isPriceSourceAvailable("RECRYSTALLIZE") then
		local ok, price = pcall(_G.RECrystallize_PriceCheckItemID, itemID)
		if ok and type(price) == "number" and price > 0 then
			return price, "RECrystallize"
		end
	elseif sourceKey == "VENDOR" then
		local vendorPrice = select(11, GetItemInfo(itemLink or itemID))
		if (not vendorPrice or vendorPrice <= 0) and _G.Informant and type(_G.Informant.GetItem) == "function" then
			local ok, info = pcall(_G.Informant.GetItem, itemID)
			if ok and type(info) == "table" and type(info.sell) == "number" then
				vendorPrice = info.sell
			end
		end
		if type(vendorPrice) == "number" and vendorPrice > 0 then
			return vendorPrice, "Vendor"
		end
	end
	return nil, nil
end

function Integrations.GetItemValue(itemIDOrLink)
	if not itemIDOrLink then return 0, nil end
	local itemID = tonumber(itemIDOrLink)
	local itemLink = type(itemIDOrLink) == "string" and itemIDOrLink or nil
	if not itemID and itemLink then
		itemID = tonumber(itemLink:match("item:(%d+)"))
	end
	if not itemID then return 0, nil end

	local pref = (Gatherer and Gatherer.Config and Gatherer.Config.GetSetting and Gatherer.Config.GetSetting("tooltip.pricesource", "AUTO")) or "AUTO"
	if pref ~= "AUTO" and isPriceSourceAvailable(pref) then
		local price, src = queryPriceSource(pref, itemID, itemLink)
		if price and price > 0 then
			return price, src
		end
		if pref ~= "VENDOR" then
			local vPrice, vSrc = queryPriceSource("VENDOR", itemID, itemLink)
			if vPrice and vPrice > 0 then
				return vPrice, vSrc
			end
		end
		return 0, nil
	end

	for _, sourceKey in ipairs(PRICE_SOURCE_ORDER) do
		local price, src = queryPriceSource(sourceKey, itemID, itemLink)
		if price and price > 0 then
			return price, src
		end
	end

	return 0, nil
end

function Integrations.GetNodeValue(nodeID)
	if not nodeID then return 0, nil, nil end
	local primaryItem = Gatherer.Nodes and Gatherer.Nodes.PrimaryItems and Gatherer.Nodes.PrimaryItems[nodeID]
	if not primaryItem and Gatherer.DropRates and Gatherer.DropRates.GetPrimaryItem then
		primaryItem = Gatherer.DropRates.GetPrimaryItem(nodeID)
	end
	if primaryItem and primaryItem > 0 then
		local price, source = Integrations.GetItemValue(primaryItem)
		return price, primaryItem, source
	end
	return 0, nil, nil
end

--------------------------------------------------------------------------------
-- 2. Live Session Statistics & Gold-per-Hour (GPH) Tracker
--------------------------------------------------------------------------------

Integrations.Session = {
	startTime = GetTime and GetTime() or 0,
	nodesGathered = 0,
	itemsGathered = 0,
	coinsLooted = 0,
	byType = {
		HERB = 0,
		MINE = 0,
		OPEN = 0,
		ARCH = 0,
	},
	items = {}, -- [itemID] = { count = N, link = link, name = name }
}

function Integrations.Session.Reset()
	local s = Integrations.Session
	s.startTime = GetTime and GetTime() or 0
	s.nodesGathered = 0
	s.itemsGathered = 0
	s.coinsLooted = 0
	s.byType = { HERB = 0, MINE = 0, OPEN = 0, ARCH = 0 }
	s.items = {}
	if Gatherer.MiniIcon and Gatherer.MiniIcon.UpdateLDBText then
		Gatherer.MiniIcon.UpdateLDBText()
	end
end

function Integrations.Session.RecordGather(objectId, gatherType, coins, lootTable)
	local s = Integrations.Session
	if not s.startTime or s.startTime == 0 then
		s.startTime = GetTime and GetTime() or 0
	end
	s.nodesGathered = (s.nodesGathered or 0) + 1
	if gatherType then
		s.byType[gatherType] = (s.byType[gatherType] or 0) + 1
	end
	if type(coins) == "number" and coins > 0 then
		s.coinsLooted = (s.coinsLooted or 0) + coins
	end

	local recordedItems = false
	if type(lootTable) == "table" then
		for _, entry in ipairs(lootTable) do
			local itemID = entry.id or (entry.link and tonumber(entry.link:match("item:(%d+)")))
			local count = tonumber(entry.count) or 1
			if itemID and itemID > 0 then
				recordedItems = true
				s.itemsGathered = (s.itemsGathered or 0) + count
				local itemRec = s.items[itemID]
				if not itemRec then
					local name, link = GetItemInfo(entry.link or itemID)
					itemRec = { count = 0, link = entry.link or link, name = name }
					s.items[itemID] = itemRec
				end
				itemRec.count = itemRec.count + count
				if entry.link and not itemRec.link then
					itemRec.link = entry.link
				end
			end
		end
	end

	-- Fallback if lootTable didn't contain item IDs yet: use node's primary item
	if not recordedItems and objectId and Gatherer.Nodes and Gatherer.Nodes.PrimaryItems then
		local primID = Gatherer.Nodes.PrimaryItems[objectId]
		if primID and primID > 0 then
			s.itemsGathered = (s.itemsGathered or 0) + 1
			local itemRec = s.items[primID]
			if not itemRec then
				local name, link = GetItemInfo(primID)
				itemRec = { count = 0, link = link, name = name }
				s.items[primID] = itemRec
			end
			itemRec.count = itemRec.count + 1
		end
	end

	if Gatherer.MiniIcon and Gatherer.MiniIcon.UpdateLDBText then
		Gatherer.MiniIcon.UpdateLDBText()
	end
end

function Integrations.Session.GetSummary()
	local s = Integrations.Session
	local now = GetTime and GetTime() or 0
	local elapsed = max(now - (s.startTime or now), 1)
	local totalValue = s.coinsLooted or 0
	local itemBreakdown = {}

	for itemID, info in pairs(s.items) do
		local unitPrice, priceSource = Integrations.GetItemValue(info.link or itemID)
		local stackValue = (unitPrice or 0) * (info.count or 0)
		totalValue = totalValue + stackValue
		local name, link = info.name, info.link
		if not name or not link then
			name, link = GetItemInfo(itemID)
		end
		table.insert(itemBreakdown, {
			itemID = itemID,
			name = name or ("Item #" .. tostring(itemID)),
			link = link or name or ("Item #" .. tostring(itemID)),
			count = info.count or 0,
			unitPrice = unitPrice or 0,
			totalPrice = stackValue,
			source = priceSource,
		})
	end

	table.sort(itemBreakdown, function(a, b)
		if a.totalPrice ~= b.totalPrice then
			return a.totalPrice > b.totalPrice
		end
		return a.count > b.count
	end)

	local hours = elapsed / 3600
	local nodesPerHour = s.nodesGathered > 0 and floor((s.nodesGathered / hours) + 0.5) or 0
	local goldPerHour = totalValue > 0 and floor((totalValue / hours) + 0.5) or 0

	return {
		elapsed = floor(elapsed),
		nodes = s.nodesGathered or 0,
		itemsCount = s.itemsGathered or 0,
		nodesPerHour = nodesPerHour,
		totalValue = totalValue,
		goldPerHour = goldPerHour,
		byType = s.byType,
		items = itemBreakdown,
	}
end

function Integrations.Session.AddTooltipLines(tooltip)
	if not tooltip or not tooltip.AddLine then return end
	if not Gatherer.Config.GetSetting("session.enable", true) then return end

	local _tr = Gatherer.Locale and Gatherer.Locale.Tr
	local summary = Integrations.Session.GetSummary()
	tooltip:AddLine(" ")
	tooltip:AddLine("|cffffd200" .. (_tr and _tr("CONFIG_SESSION_GROUP") or "Session Tracker (GPH)") .. "|r")
	if _tr then
		local summaryText = string.format(_tr("UI_SESSION_SUMMARY_FMT"),
			floor(summary.elapsed / 60),
			summary.elapsed % 60,
			summary.nodes,
			summary.nodesPerHour,
			Integrations.FormatMoney(summary.totalValue),
			Integrations.FormatMoney(summary.goldPerHour))
		for line in summaryText:gmatch("[^\n]+") do
			-- Split multi-pair lines ("Label1: Val1   Label2: Val2") or single "Label: Val" into clean AddDoubleLine rows
			local pairCount = 0
			for seg in line:gmatch("(|cff8892a4.-:%s*|r%s*[^|]+)") do
				local k, v = seg:match("^(|cff8892a4.-:|r)%s*(.-)%s*$")
				if k and v and tooltip.AddDoubleLine then
					tooltip:AddDoubleLine(k, v, 0.75, 0.80, 0.88, 1, 1, 1)
					pairCount = pairCount + 1
				end
			end
			if pairCount == 0 then
				local k, v = line:match("^(.-:|r)%s*(.+)$")
				if not k then k, v = line:match("^([^:]+:)%s*(.+)$") end
				if k and v and tooltip.AddDoubleLine then
					tooltip:AddDoubleLine(k, "   " .. v, 0.75, 0.80, 0.88, 1, 1, 1)
				else
					tooltip:AddLine(line, 0.9, 0.9, 0.9)
				end
			end
		end
	end

	local maxItems = math.min(#summary.items, 5)
	if maxItems > 0 then
		tooltip:AddLine(" ")
		for i = 1, maxItems do
			local it = summary.items[i]
			local rightText = string.format("x%d", it.count)
			if it.totalPrice > 0 then
				rightText = string.format("x%d (%s)", it.count, Integrations.FormatMoney(it.totalPrice))
			end
			tooltip:AddDoubleLine("  " .. tostring(it.link), rightText, 1, 1, 1, 0.9, 0.9, 0.9)
		end
	end
end

--------------------------------------------------------------------------------
-- 3. Harvest Cooldown ("Respawn Timer") Dimming Helper
--------------------------------------------------------------------------------

function Integrations.GetNodeCooldownInfo(zoneToken, gType, nodeIndex)
	if not Gatherer.Config.GetSetting("cooldown.enable", true) then
		return nil
	end
	if not (zoneToken and gType and nodeIndex and Gatherer.Storage and Gatherer.Storage.GetNodeGatherNames) then
		return nil
	end
	local cooldownTime = tonumber(Gatherer.Config.GetSetting("cooldown.time", 300)) or 300
	if cooldownTime <= 0 then return nil end

	local lastHarvested = 0
	for _, _, _, harvested in Gatherer.Storage.GetNodeGatherNames(zoneToken, gType, nodeIndex) do
		if type(harvested) == "number" and harvested > lastHarvested then
			lastHarvested = harvested
		end
	end

	if lastHarvested <= 0 then return nil end
	local now = time()
	local delta = now - lastHarvested
	if delta >= 0 and delta < cooldownTime then
		local minAlpha = (tonumber(Gatherer.Config.GetSetting("cooldown.opacity", 35)) or 35) / 100
		local remaining = cooldownTime - delta
		return minAlpha, remaining, delta
	end
	return nil
end

--------------------------------------------------------------------------------
-- 4. GatherMate2 & GatherMate2_Data / GatherMate2Storage_* Importer
--------------------------------------------------------------------------------

-- Built-in mapping of GatherMate2 node IDs to { name, gType, gathererID, primaryItemID }
local GM2_NODE_MAP = {
	-- Mining (Classic -> Midnight)
	[201] = { "Copper Vein", "MINE", 1731, 2770 },
	[202] = { "Tin Vein", "MINE", 1732, 2771 },
	[203] = { "Iron Deposit", "MINE", 1735, 2772 },
	[204] = { "Silver Vein", "MINE", 1733, 2775 },
	[205] = { "Gold Vein", "MINE", 1734, 2776 },
	[206] = { "Mithril Deposit", "MINE", 2040, 3858 },
	[207] = { "Ooze Covered Mithril Deposit", "MINE", 123310, 3858 },
	[208] = { "Truesilver Deposit", "MINE", 2047, 7911 },
	[209] = { "Ooze Covered Silver Vein", "MINE", 73940, 2775 },
	[210] = { "Ooze Covered Gold Vein", "MINE", 73941, 2776 },
	[211] = { "Ooze Covered Truesilver Deposit", "MINE", 123309, 7911 },
	[212] = { "Ooze Covered Rich Thorium Vein", "MINE", 177388, 10620 },
	[213] = { "Ooze Covered Thorium Vein", "MINE", 123848, 10620 },
	[214] = { "Small Thorium Vein", "MINE", 324, 10620 },
	[215] = { "Rich Thorium Vein", "MINE", 175404, 10620 },
	[216] = { "Hakkari Thorium Vein", "MINE", 180215, 10620 },
	[217] = { "Dark Iron Deposit", "MINE", 165658, 11370 },
	[218] = { "Lesser Bloodstone Deposit", "MINE", 2653, 4278 },
	[219] = { "Incendicite Mineral Vein", "MINE", 1610, 2798 },
	[220] = { "Indurium Mineral Vein", "MINE", 19903, 5833 },
	[221] = { "Fel Iron Deposit", "MINE", 181555, 23424 },
	[222] = { "Adamantite Deposit", "MINE", 181556, 23425 },
	[223] = { "Rich Adamantite Deposit", "MINE", 181569, 23425 },
	[224] = { "Khorium Vein", "MINE", 181557, 23426 },
	[225] = { "Large Obsidian Chunk", "MINE", 181069, 22203 },
	[226] = { "Small Obsidian Chunk", "MINE", 181068, 22202 },
	[227] = { "Nethercite Deposit", "MINE", 185877, 32464 },
	[228] = { "Cobalt Deposit", "MINE", 189978, 36909 },
	[229] = { "Rich Cobalt Deposit", "MINE", 189979, 36909 },
	[230] = { "Titanium Vein", "MINE", 191133, 36910 },
	[231] = { "Saronite Deposit", "MINE", 189980, 36912 },
	[232] = { "Rich Saronite Deposit", "MINE", 189981, 36912 },
	[233] = { "Obsidium Deposit", "MINE", 202736, 53038 },
	[235] = { "Pure Saronite Deposit", "MINE", 189981, 36912 },
	[236] = { "Elementium Vein", "MINE", 202738, 52185 },
	[237] = { "Rich Elementium Vein", "MINE", 202741, 52185 },
	[238] = { "Pyrite Deposit", "MINE", 202737, 52183 },
	[239] = { "Rich Obsidium Deposit", "MINE", 202739, 53038 },
	[240] = { "Rich Pyrite Deposit", "MINE", 202740, 52183 },
	[241] = { "Ghost Iron Deposit", "MINE", 209311, 72092 },
	[242] = { "Rich Ghost Iron Deposit", "MINE", 209328, 72092 },
	[245] = { "Kyparite Deposit", "MINE", 209312, 72093 },
	[246] = { "Rich Kyparite Deposit", "MINE", 209329, 72093 },
	[247] = { "Trillium Vein", "MINE", 209313, 72094 },
	[248] = { "Rich Trillium Vein", "MINE", 209330, 72094 },
	[249] = { "True Iron Deposit", "MINE", 228493, 109119 },
	[250] = { "Rich True Iron Deposit", "MINE", 228510, 109119 },
	[251] = { "Blackrock Deposit", "MINE", 228563, 109118 },
	[252] = { "Rich Blackrock Deposit", "MINE", 228564, 109118 },
	[253] = { "Leystone Deposit", "MINE", 241726, 123918 },
	[254] = { "Rich Leystone Deposit", "MINE", 245324, 123918 },
	[255] = { "Leystone Seam", "MINE", 253280, 123918 },
	[256] = { "Felslate Deposit", "MINE", 241743, 123919 },
	[257] = { "Rich Felslate Deposit", "MINE", 245325, 123919 },
	[258] = { "Felslate Seam", "MINE", 255344, 123919 },
	[259] = { "Empyrium Deposit", "MINE", 272768, 151564 },
	[260] = { "Rich Empyrium Deposit", "MINE", 272778, 151564 },
	[261] = { "Empyrium Seam", "MINE", 272780, 151564 },
	[262] = { "Monelite Deposit", "MINE", nil, 152512 },
	[263] = { "Rich Monelite Deposit", "MINE", nil, 152512 },
	[264] = { "Monelite Seam", "MINE", nil, 152512 },
	[265] = { "Platinum Deposit", "MINE", nil, 152513 },
	[266] = { "Rich Platinum Deposit", "MINE", nil, 152513 },
	[267] = { "Storm Silver Deposit", "MINE", nil, 152579 },
	[268] = { "Rich Storm Silver Deposit", "MINE", nil, 152579 },
	[269] = { "Storm Silver Seam", "MINE", nil, 152579 },
	[270] = { "Osmenite Deposit", "MINE", nil, 168185 },
	[271] = { "Rich Osmenite Deposit", "MINE", nil, 168185 },
	[272] = { "Osmenite Seam", "MINE", nil, 168185 },
	[273] = { "Laestrite Deposit", "MINE", nil, 171828 },
	[274] = { "Rich Laestrite Deposit", "MINE", nil, 171828 },
	[275] = { "Phaedrum Deposit", "MINE", nil, 171830 },
	[276] = { "Rich Phaedrum Deposit", "MINE", nil, 171830 },
	[277] = { "Oxxein Deposit", "MINE", nil, 171829 },
	[278] = { "Rich Oxxein Deposit", "MINE", nil, 171829 },
	[280] = { "Elethium Deposit", "MINE", nil, 171833 },
	[282] = { "Solenium Deposit", "MINE", nil, 171829 },
	[283] = { "Rich Solenium Deposit", "MINE", nil, 171829 },
	[284] = { "Sinvyr Deposit", "MINE", nil, 171832 },
	[285] = { "Rich Sinvyr Deposit", "MINE", nil, 171832 },
	[287] = { "Progenium Deposit", "MINE", nil, 187700 },
	[1200] = { "Serevite Seam", "MINE", nil, 190396 },
	[1201] = { "Serevite Deposit", "MINE", nil, 190396 },
	[1208] = { "Draconium Seam", "MINE", nil, 188658 },
	[1209] = { "Draconium Deposit", "MINE", nil, 188658 },
	[1218] = { "Bismuth", "MINE", nil, 210930 },
	[1225] = { "Bismuth Seam", "MINE", nil, 210930 },
	[1226] = { "Aqirite", "MINE", nil, 210933 },
	[1233] = { "Aqirite Seam", "MINE", nil, 210933 },
	[1234] = { "Ironclaw", "MINE", nil, 210936 },
	[1241] = { "Ironclaw Seam", "MINE", nil, 210936 },
	[1242] = { "Webbed Ore Deposit", "MINE", nil, 210930 },
	[1243] = { "Desolate Deposit", "MINE", nil, 210930 },
	[1245] = { "Brilliant Silver", "MINE", nil, nil },
	[1246] = { "Brilliant Silver Seam", "MINE", nil, nil },
	[1247] = { "Refulgent Copper", "MINE", nil, nil },
	[1248] = { "Refulgent Copper Seam", "MINE", nil, nil },
	[1249] = { "Umbral Tin", "MINE", nil, nil },
	[1250] = { "Umbral Tin Seam", "MINE", nil, nil },

	-- Herbalism (Classic -> Midnight)
	[401] = { "Peacebloom", "HERB", 1618, 2447 },
	[402] = { "Silverleaf", "HERB", 1617, 765 },
	[403] = { "Earthroot", "HERB", 1619, 2449 },
	[404] = { "Mageroyal", "HERB", 1620, 785 },
	[405] = { "Briarthorn", "HERB", 1621, 2450 },
	[407] = { "Stranglekelp", "HERB", 2045, 3820 },
	[408] = { "Bruiseweed", "HERB", 1622, 2453 },
	[409] = { "Wild Steelbloom", "HERB", 1623, 3355 },
	[410] = { "Grave Moss", "HERB", 1628, 3369 },
	[411] = { "Kingsblood", "HERB", 1624, 3356 },
	[412] = { "Liferoot", "HERB", 2041, 3357 },
	[413] = { "Fadeleaf", "HERB", 2042, 3818 },
	[414] = { "Goldthorn", "HERB", 2046, 3821 },
	[415] = { "Khadgar's Whisker", "HERB", 2043, 3358 },
	[416] = { "Wintersbite", "HERB", 2044, 3819 },
	[417] = { "Firebloom", "HERB", 2866, 4625 },
	[418] = { "Purple Lotus", "HERB", 142140, 8831 },
	[420] = { "Arthas' Tears", "HERB", 142141, 8836 },
	[421] = { "Sungrass", "HERB", 142142, 8838 },
	[422] = { "Blindweed", "HERB", 142143, 8839 },
	[423] = { "Ghost Mushroom", "HERB", 142144, 8845 },
	[424] = { "Gromsblood", "HERB", 142145, 8846 },
	[425] = { "Golden Sansam", "HERB", 176583, 13464 },
	[426] = { "Dreamfoil", "HERB", 176584, 13463 },
	[427] = { "Mountain Silversage", "HERB", 176586, 13465 },
	[428] = { "Plaguebloom", "HERB", 176587, 13466 },
	[429] = { "Icecap", "HERB", 176588, 13467 },
	[431] = { "Black Lotus", "HERB", 176589, 13468 },
	[432] = { "Felweed", "HERB", 181270, 22785 },
	[433] = { "Dreaming Glory", "HERB", 181271, 22786 },
	[434] = { "Terocone", "HERB", 181277, 22789 },
	[435] = { "Ancient Lichen", "HERB", 181278, 22790 },
	[436] = { "Bloodthistle", "HERB", 181166, 22710 },
	[437] = { "Mana Thistle", "HERB", 181281, 22793 },
	[438] = { "Netherbloom", "HERB", 181279, 22791 },
	[439] = { "Nightmare Vine", "HERB", 181280, 22792 },
	[440] = { "Ragveil", "HERB", 181275, 22787 },
	[441] = { "Flame Cap", "HERB", 181276, 22788 },
	[442] = { "Netherdust Bush", "HERB", 185881, 32468 },
	[443] = { "Adder's Tongue", "HERB", 191019, 36903 },
	[446] = { "Goldclover", "HERB", 189973, 36901 },
	[447] = { "Icethorn", "HERB", 190172, 36906 },
	[448] = { "Lichbloom", "HERB", 190171, 36905 },
	[449] = { "Talandra's Rose", "HERB", 190170, 36907 },
	[450] = { "Tiger Lily", "HERB", 190169, 36904 },
	[451] = { "Firethorn", "HERB", 191303, 39970 },
	[452] = { "Frozen Herb", "HERB", 190175, 36901 },
	[453] = { "Frost Lotus", "HERB", 190176, 36908 },
	[454] = { "Dragon's Teeth", "HERB", 2044, 3819 },
	[455] = { "Sorrowmoss", "HERB", 176587, 13466 },
	[456] = { "Azshara's Veil", "HERB", 202749, 52985 },
	[457] = { "Cinderbloom", "HERB", 202747, 52983 },
	[458] = { "Stormvine", "HERB", 202748, 52984 },
	[459] = { "Heartblossom", "HERB", 202750, 52986 },
	[460] = { "Twilight Jasmine", "HERB", 202751, 52987 },
	[461] = { "Whiptail", "HERB", 202752, 52988 },
	[462] = { "Golden Lotus", "HERB", 209354, 72238 },
	[463] = { "Fool's Cap", "HERB", 209355, 79011 },
	[464] = { "Snow Lily", "HERB", 209351, 79010 },
	[465] = { "Silkweed", "HERB", 209350, 72235 },
	[466] = { "Green Tea Leaf", "HERB", 209349, 72234 },
	[467] = { "Rain Poppy", "HERB", 209353, 72237 },
	[468] = { "Sha-Touched Herb", "HERB", 214510, 72234 },
	[469] = { "Talador Orchid", "HERB", 228576, 109129 },
	[470] = { "Nagrand Arrowbloom", "HERB", 228575, 109128 },
	[471] = { "Starflower", "HERB", 228574, 109127 },
	[472] = { "Gorgrond Flytrap", "HERB", 228573, 109126 },
	[473] = { "Fireweed", "HERB", 228572, 109125 },
	[474] = { "Frostweed", "HERB", 228571, 109124 },
	[475] = { "Withered Herb", "HERB", 243334, 109124 },
	[476] = { "Aethril", "HERB", 244774, 124101 },
	[477] = { "Dreamleaf", "HERB", 244776, 124102 },
	[478] = { "Felwort", "HERB", nil, 124106 },
	[479] = { "Fjarnskaggl", "HERB", 244777, 124104 },
	[480] = { "Foxflower", "HERB", 241641, 124103 },
	[481] = { "Starlight Rose", "HERB", 244778, 124105 },
	[482] = { "Fel-Encrusted Herb", "HERB", 269278, 124105 },
	[483] = { "Fel-Encrusted Herb Cluster", "HERB", 269887, 124105 },
	[484] = { "Astral Glory", "HERB", 272782, 151565 },
	[485] = { "Akunda's Bite", "HERB", nil, 152507 },
	[486] = { "Anchor Weed", "HERB", nil, 152510 },
	[487] = { "Riverbud", "HERB", nil, 152505 },
	[488] = { "Sea Stalks", "HERB", nil, 152511 },
	[489] = { "Siren's Sting", "HERB", nil, 152509 },
	[490] = { "Star Moss", "HERB", nil, 152506 },
	[491] = { "Winter's Kiss", "HERB", nil, 152508 },
	[492] = { "Zin'anthid", "HERB", nil, 168487 },
	[493] = { "Death Blossom", "HERB", nil, 169701 },
	[494] = { "Nightshade", "HERB", nil, 171315 },
	[495] = { "Marrowroot", "HERB", nil, 168589 },
	[496] = { "Vigil's Torch", "HERB", nil, 170554 },
	[497] = { "Rising Glory", "HERB", nil, 168586 },
	[498] = { "Widowbloom", "HERB", nil, 168583 },
	[499] = { "First Flower", "HERB", nil, 187699 },
	[1407] = { "Hochenblume", "HERB", nil, 191460 },
	[1414] = { "Bubble Poppy", "HERB", nil, 191467 },
	[1421] = { "Saxifrage", "HERB", nil, 191464 },
	[1428] = { "Writhebark", "HERB", nil, 191470 },
	[1439] = { "Mycobloom", "HERB", nil, 210796 },
	[1447] = { "Blessing Blossom", "HERB", nil, 210808 },
	[1455] = { "Luredrop", "HERB", nil, 210805 },
	[1463] = { "Orbinid", "HERB", nil, 210802 },
	[1471] = { "Arathor's Spear", "HERB", nil, 210811 },
	[1479] = { "Phantom Bloom", "HERB", nil, 210796 },
	[1481] = { "Argentleaf", "HERB", nil, nil },
	[1482] = { "Azeroot", "HERB", nil, nil },
	[1483] = { "Mana Lily", "HERB", nil, nil },
	[1484] = { "Sanguithorn", "HERB", nil, nil },
	[1485] = { "Tranquility Bloom", "HERB", nil, nil },

	-- Treasure / Open
	[501] = { "Giant Clam", "OPEN", 2744, 5503 },
	[502] = { "Battered Chest", "OPEN", 2843, nil },
	[503] = { "Tattered Chest", "OPEN", 2844, nil },
	[504] = { "Solid Chest", "OPEN", 2850, nil },
	[505] = { "Large Iron Bound Chest", "OPEN", 74447, nil },
	[506] = { "Large Solid Chest", "OPEN", 74448, nil },
	[507] = { "Large Battered Chest", "OPEN", 75293, nil },
	[508] = { "Buccaneer's Strongbox", "OPEN", 123330, nil },
	[509] = { "Large Mithril Bound Chest", "OPEN", 131978, nil },
	[510] = { "Large Darkwood Chest", "OPEN", 131979, nil },
	[511] = { "Un'Goro Dirt Pile", "OPEN", 157936, 11018 },
	[512] = { "Bloodpetal Sprout", "OPEN", 164958, 11315 },
	[513] = { "Blood of Heroes", "OPEN", 176213, 12938 },
	[514] = { "Practice Lockbox", "OPEN", 178244, nil },
	[515] = { "Battered Footlocker", "OPEN", 179486, nil },
	[516] = { "Waterlogged Footlocker", "OPEN", 179487, nil },
	[517] = { "Dented Footlocker", "OPEN", 179492, nil },
	[518] = { "Mossy Footlocker", "OPEN", 179493, nil },
	[519] = { "Scarlet Footlocker", "OPEN", 179498, nil },
	[520] = { "Burial Chest", "OPEN", 181665, nil },
	[521] = { "Fel Iron Chest", "OPEN", 181798, nil },
	[522] = { "Heavy Fel Iron Chest", "OPEN", 181800, nil },
	[523] = { "Adamantite Bound Chest", "OPEN", 181802, nil },
	[524] = { "Felsteel Chest", "OPEN", 181804, nil },
	[525] = { "Glowcap", "OPEN", 182053, 24245 },
	[526] = { "Wicker Chest", "OPEN", 184740, nil },
	[527] = { "Primitive Chest", "OPEN", 184793, nil },
	[528] = { "Solid Fel Iron Chest", "OPEN", 184930, nil },
	[529] = { "Bound Fel Iron Chest", "OPEN", 184931, nil },
	[530] = { "Bound Adamantite Chest", "OPEN", 184936, nil },
	[531] = { "Netherwing Egg", "OPEN", 185915, 32506 },
	[532] = { "Everfrost Chip", "OPEN", 193997, 44724 },
	[533] = { "Brightly Colored Egg", "OPEN", 113768, 45072 },
	[534] = { "Silken Treasure Chest", "OPEN", 207512, nil },
	[535] = { "Sturdy Treasure Chest", "OPEN", 207484, nil },
	[536] = { "Runestone Treasure Chest", "OPEN", 207533, nil },
	[537] = { "Silverbound Treasure Chest", "OPEN", 207472, nil },
	[538] = { "Mysterious Camel Figurine", "OPEN", nil, nil },
	[539] = { "Dark Iron Treasure Chest", "OPEN", 207498, nil },
	[540] = { "Maplewood Treasure Chest", "OPEN", 207529, nil },
	[545] = { "Dark Soil", "OPEN", 210565, nil },
	[546] = { "Onyx Egg", "OPEN", 214945, 89155 },

	-- Archaeology
	[601] = { "Night Elf Archaeology Find", "ARCH", 203071, nil },
	[602] = { "Troll Archaeology Find", "ARCH", 202655, nil },
	[603] = { "Dwarf Archaeology Find", "ARCH", 204282, nil },
	[604] = { "Fossil Archaeology Find", "ARCH", 206836, nil },
	[605] = { "Draenei Archaeology Find", "ARCH", 207188, nil },
	[606] = { "Orc Archaeology Find", "ARCH", 207187, nil },
	[607] = { "Nerubian Archaeology Find", "ARCH", 203078, nil },
	[608] = { "Vrykul Archaeology Find", "ARCH", 207189, nil },
	[609] = { "Tol'vir Archaeology Find", "ARCH", 207190, nil },
	[611] = { "Pandaren Archaeology Find", "ARCH", 211163, nil },
	[612] = { "Mogu Archaeology Find", "ARCH", 211174, nil },
	[613] = { "Mantid Archaeology Find", "ARCH", 218950, nil },
	[614] = { "Arakkoa Archaeology Find", "ARCH", 234105, nil },
	[615] = { "Draenor Clans Archaeology Find", "ARCH", 226521, nil },
	[616] = { "Ogre Archaeology Find", "ARCH", 234106, nil },
	[617] = { "Demonic Archaeology Find", "ARCH", 246812, nil },
	[618] = { "Highborne Archaeology Find", "ARCH", 256811, nil },
	[619] = { "Highmountain Tauren Archaeology Find", "ARCH", 246804, nil },

	-- Fishing Schools & Gas Clouds (mapped under OPEN so they work with all filters & reports)
	[101] = { "Floating Wreckage", "OPEN", nil, 6358 },
	[103] = { "Floating Debris", "OPEN", nil, 6358 },
	[105] = { "Firefin Snapper School", "OPEN", nil, 6359 },
	[106] = { "Greater Sagefish School", "OPEN", nil, 21153 },
	[107] = { "Oily Blackmouth School", "OPEN", nil, 6358 },
	[108] = { "Sagefish School", "OPEN", nil, 21071 },
	[109] = { "School of Deviate Fish", "OPEN", nil, 6522 },
	[110] = { "Stonescale Eel Swarm", "OPEN", nil, 13422 },
	[113] = { "Pure Water", "OPEN", nil, 7070 },
	[301] = { "Windy Cloud", "OPEN", nil, 22578 },
	[302] = { "Swamp Gas", "OPEN", nil, 22577 },
	[303] = { "Arcane Vortex", "OPEN", nil, 22576 },
	[304] = { "Felmist", "OPEN", nil, 22575 },
	[305] = { "Steam Cloud", "OPEN", nil, 37705 },
	[306] = { "Cinder Cloud", "OPEN", nil, 37702 },
	[307] = { "Arctic Cloud", "OPEN", nil, 37700 },

	-- WoW Forever Ores & Herbs (GatherRadar 90201..90406 IDs -> Gatherer 890201..890406)
	[90201] = { "Cold Iron Deposit", "MINE", 890201, nil },
	[90202] = { "Fool's Gold Vein", "MINE", 890202, nil },
	[90203] = { "Starsilver Vein", "MINE", 890203, nil },
	[90204] = { "Greater Moonstone Formation", "MINE", 890204, nil },
	[90205] = { "Heavy Thorium Vein", "MINE", 890205, nil },
	[90206] = { "Moonstone Formation", "MINE", 890206, nil },
	[90207] = { "Chunk of Amber", "MINE", 890207, nil },
	[90401] = { "Nightmare Moss", "HERB", 890401, nil },
	[90402] = { "Dreamroot", "HERB", 890402, nil },
	[90403] = { "Moonroot", "HERB", 890403, nil },
	[90404] = { "Star Lotus", "HERB", 890404, nil },
	[90405] = { "Doom Weed", "HERB", 890405, nil },
	[90406] = { "Gloom Weed", "HERB", 890406, nil },
}

local DB_TYPE_TO_GTYPE = {
	["Herb Gathering"] = "HERB",
	["Mining"] = "MINE",
	["Treasure"] = "OPEN",
	["Archaeology"] = "ARCH",
	["Fishing"] = "OPEN",
	["Extract Gas"] = "OPEN",
	["Logging"] = "OPEN",
}

local function resolveGatherMateNode(gmNodeID, dbType)
	local gType = DB_TYPE_TO_GTYPE[dbType] or "OPEN"
	local entry = GM2_NODE_MAP[gmNodeID]
	local gmAddon = LibStub and LibStub("AceAddon-3.0", true) and LibStub("AceAddon-3.0"):GetAddon("GatherMate2", true)
	local localizedName = gmAddon and gmAddon.reverseNodeIDs and gmAddon.reverseNodeIDs[dbType] and gmAddon.reverseNodeIDs[dbType][gmNodeID]

	if entry then
		local engName, entryGType, explicitID, primaryItem = entry[1], entry[2], entry[3], entry[4]
		gType = entryGType or gType
		if explicitID and Gatherer.Nodes and Gatherer.Nodes.Objects and Gatherer.Nodes.Objects[explicitID] then
			if localizedName and Gatherer.Nodes.Names and not Gatherer.Nodes.Names[localizedName] then
				Gatherer.Nodes.Names[localizedName] = explicitID
			end
			return explicitID, gType
		end
		local existing = (localizedName and Gatherer.Nodes.Names[localizedName]) or (engName and Gatherer.Nodes.Names[engName])
		if existing then
			return existing, Gatherer.Nodes.Objects[existing] or gType
		end
		if Gatherer.Nodes and Gatherer.Nodes.RegisterDynamicNode then
			local regID = Gatherer.Nodes.RegisterDynamicNode(localizedName or engName, gType, primaryItem, explicitID)
			if regID then
				return regID, gType
			end
		end
	end

	if localizedName and Gatherer.Nodes then
		local existing = Gatherer.Nodes.Names[localizedName]
		if existing then
			return existing, Gatherer.Nodes.Objects[existing] or gType
		end
		if Gatherer.Nodes.RegisterDynamicNode then
			local regID = Gatherer.Nodes.RegisterDynamicNode(localizedName, gType, nil, 800000 + (tonumber(gmNodeID) or 0))
			if regID then
				return regID, gType
			end
		end
	end

	return nil, nil
end

Integrations.ResolveGatherMateNode = resolveGatherMateNode

-- Reverse lookup table: Gatherer objectID -> { gmNodeID, dbType, engName }
local GTYPE_TO_DB_TYPE = {
	HERB = "Herb Gathering",
	MINE = "Mining",
	OPEN = "Treasure",
	ARCH = "Archaeology",
}

local OBJECT_TO_GM2 = {}
local NAME_TO_GM2 = {}
for gmNodeID, entry in pairs(GM2_NODE_MAP) do
	local engName, entryGType, explicitID = entry[1], entry[2], entry[3]
	local dbType = GTYPE_TO_DB_TYPE[entryGType] or "Treasure"
	if gmNodeID >= 100 and gmNodeID < 200 then
		dbType = "Fishing"
	elseif gmNodeID >= 300 and gmNodeID < 400 then
		dbType = "Extract Gas"
	end
	if explicitID and not OBJECT_TO_GM2[explicitID] then
		OBJECT_TO_GM2[explicitID] = { gmNodeID, dbType, engName }
	end
	if engName then
		NAME_TO_GM2[engName:lower()] = { gmNodeID, dbType, engName }
	end
end

function Integrations.GetGatherMateNodeForObject(objectId, gatherType)
	if not objectId then return nil, nil end
	local direct = OBJECT_TO_GM2[objectId]
	if direct then
		return direct[1], direct[2]
	end

	local nodeName = Gatherer.Util and Gatherer.Util.GetNodeName and Gatherer.Util.GetNodeName(objectId)
	if nodeName then
		local byName = NAME_TO_GM2[nodeName:lower()]
		if byName then
			return byName[1], byName[2]
		end
	end

	local gmAddon = LibStub and LibStub("AceAddon-3.0", true) and LibStub("AceAddon-3.0"):GetAddon("GatherMate2", true)
	if gmAddon and gmAddon.nodeIDs and nodeName then
		for dbType, tbl in pairs(gmAddon.nodeIDs) do
			if type(tbl) == "table" and tbl[nodeName] then
				return tbl[nodeName], dbType
			end
		end
	end

	if type(objectId) == "number" and objectId >= 800000 and objectId < 810000 then
		local gmID = objectId - 800000
		local entry = GM2_NODE_MAP[gmID]
		if entry then
			return gmID, GTYPE_TO_DB_TYPE[entry[2]] or "Treasure"
		end
	end

	return nil, GTYPE_TO_DB_TYPE[gatherType]
end

local function importGM2Table(dbTable, dbType, sourceLabel)
	if type(dbTable) ~= "table" then return 0 end
	local imported = 0
	for uiMapID, coordList in pairs(dbTable) do
		local mapID = tonumber(uiMapID)
		local zoneToken = mapID and Gatherer.ZoneTokens and Gatherer.ZoneTokens.GetZoneToken(mapID)
		if zoneToken and type(coordList) == "table" then
			for coord, gmNodeID in pairs(coordList) do
				if type(coord) == "number" and type(gmNodeID) == "number" then
					local x = floor(coord / 1000000) / 10000
					local y = floor((coord % 1000000) / 100) / 10000
					if x > 0 and x < 1 and y > 0 and y < 1 then
						local objID, gType = resolveGatherMateNode(gmNodeID, dbType)
						if objID and gType then
							local idx = Gatherer.Storage.AddNode(objID, gType, zoneToken, x, y, sourceLabel or "DB:GatherMate2", false, false)
							if idx then
								imported = imported + 1
							end
						end
					end
				end
			end
		end
	end
	return imported
end

function Integrations.IsGatherMateAvailable()
	if _G.GatherMate2HerbDB or _G.GatherMate2MineDB or _G.GatherMateData2HerbDB or _G.GatherMateData2MineDB or (_G.GatherRadarDB and _G.GatherRadarDB.nodes) then
		return true
	end
	local getState = (C_AddOns and C_AddOns.GetAddOnEnableState) or _G.GetAddOnEnableState
	local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or _G.GetAddOnInfo
	if getInfo then
		for _, addonName in ipairs({ "GatherMate2", "GatherMate2_Data", "GatherRadar", "GatherMate2Storage_Dragonflight", "GatherMate2Storage_TheWarWithin", "GatherMate2Storage_Midnight" }) do
			local ok, name = pcall(getInfo, addonName)
			if ok and name then
				return true
			end
		end
	end
	return false
end

function Integrations.ImportGatherMate2(includeDataAddon)
	local loadAddOn = (C_AddOns and C_AddOns.LoadAddOn) or _G.LoadAddOn
	local AceAddon = LibStub and LibStub("AceAddon-3.0", true)

	-- Ensure a minimal GatherMate2 stub exists if the user only has GatherMate2_Data installed without GatherMate2 enabled
	if includeDataAddon and AceAddon and not AceAddon:GetAddon("GatherMate2", true) then
		pcall(function()
			local stub = AceAddon:NewAddon("GatherMate2")
			stub.nodeIDReplacementMap = {}
			stub.mapBlacklist = {}
			function stub:ClearDB() end
			function stub:InjectNode2() end
			function stub:SendMessage() end
			function stub:RegisterStorageAddOn() end
		end)
	end

	if includeDataAddon and loadAddOn then
		for _, addonName in ipairs({ "GatherMate2_Data", "GatherMate2Storage_Dragonflight", "GatherMate2Storage_TheWarWithin", "GatherMate2Storage_Midnight" }) do
			pcall(loadAddOn, addonName)
		end
	end

	local totalImported = 0
	Gatherer.Storage.MassImportMode = true

	-- 1. Import active GatherMate2 SavedVariables (including expansion storage splits)
	local gm2Prefixes = {
		{ "Herb", "Herb Gathering" },
		{ "Mine", "Mining" },
		{ "Treasure", "Treasure" },
		{ "Archaeology", "Archaeology" },
		{ "Fish", "Fishing" },
		{ "Gas", "Extract Gas" },
	}
	local storageSuffixes = { "", "DF", "TWW", "MN" }

	for _, pair in ipairs(gm2Prefixes) do
		local prefix, dbType = pair[1], pair[2]
		for _, suffix in ipairs(storageSuffixes) do
			local globalTable = _G["GatherMate2" .. prefix .. "DB" .. suffix]
			if type(globalTable) == "table" then
				totalImported = totalImported + importGM2Table(globalTable, dbType, "IMPORTED")
			end
		end
		-- Also import Gatherer_Reborn SavedVariables if present
		local grbTable = _G["GathererReborn" .. prefix .. "DB"]
		if type(grbTable) == "table" then
			totalImported = totalImported + importGM2Table(grbTable, dbType, "IMPORTED")
		end
	end

	-- 2. Import GatherMate2_Data pre-populated tables (Forever, Classic, TBC, Wrath, Mainline)
	if includeDataAddon then
		for _, pair in ipairs(gm2Prefixes) do
			local prefix, dbType = pair[1], pair[2]
			local dataTable = _G["GatherMateData2" .. prefix .. "DB"]
			if type(dataTable) == "table" then
				totalImported = totalImported + importGM2Table(dataTable, dbType, "IMPORTED")
			end
		end
	end

	-- 3. Import GatherRadar SavedVariables if present
	if _G.GatherRadarDB and type(_G.GatherRadarDB.nodes) == "table" then
		local grKindMap = {
			herb = "Herb Gathering",
			ore = "Mining",
			treasure = "Treasure",
			fish = "Fishing",
		}
		for grKind, dbType in pairs(grKindMap) do
			if type(_G.GatherRadarDB.nodes[grKind]) == "table" then
				totalImported = totalImported + importGM2Table(_G.GatherRadarDB.nodes[grKind], dbType, "IMPORTED")
			end
		end
	end

	Gatherer.Storage.MassImportMode = false
	Gatherer.Report.NeedsUpdate()
	Gatherer.MiniNotes.ForceUpdate()
	Gatherer.MapNotes.MapDraw()

	if Gatherer.Util and Gatherer.Util.ChatPrint then
		local _tr = Gatherer.Locale and Gatherer.Locale.Tr
		Gatherer.Util.ChatPrint(string.format("|cff00ff96Gatherer Reforged:|r %s — %s (%d)",
			_tr and _tr("CONFIG_GM2_GROUP") or "GatherMate2 Import",
			_tr and _tr("DONE") or "Done",
			totalImported))
	end
	return totalImported
end

--------------------------------------------------------------------------------
-- 5. FarmHud & Routes Addon Compatibility Bridges
--------------------------------------------------------------------------------

local farmHudHooked = false
function Integrations.SetupFarmHud()
	if farmHudHooked or not _G.FarmHud then return end
	farmHudHooked = true
	pcall(function()
		_G.FarmHud:HookScript("OnShow", function()
			if Gatherer.Map and Gatherer.Map.SetTargetMinimap then
				Gatherer.Map:SetTargetMinimap(_G.FarmHud)
				Gatherer.MiniNotes.ForceUpdate()
			end
		end)
		_G.FarmHud:HookScript("OnHide", function()
			if Gatherer.Map and Gatherer.Map.SetTargetMinimap then
				Gatherer.Map:SetTargetMinimap(_G.Minimap)
				Gatherer.MiniNotes.ForceUpdate()
			end
		end)
	end)
end

local routesRegistered = false
function Integrations.SetupRoutes()
	if routesRegistered then return end
	local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
	local Routes = AceAddon and AceAddon:GetAddon("Routes", true)
	if not Routes or not Routes.plugins then return end
	routesRegistered = true

	local plugin = {}
	function plugin.IsActive()
		return true
	end

	function plugin.Summarize(data, zone)
		local uiMapID = tonumber(zone) or (Routes.LZName and Routes.LZName[zone] and Routes.LZName[zone][2])
		local zoneToken = uiMapID and Gatherer.ZoneTokens.GetZoneToken(uiMapID)
		if not zoneToken or not Gatherer.Storage.HasDataOnZone(zoneToken) then
			return data
		end
		for _, gType in pairs(Gatherer.Constants.SupportedGatherTypes) do
			for index in Gatherer.Storage.ZoneGatherNodes(zoneToken, gType) do
				for _, gatherID in Gatherer.Storage.GetNodeGatherNames(zoneToken, gType, index) do
					local nodeName = Gatherer.Util.GetNodeName(gatherID)
					local key = string.format("GathererReforged;%s;%s", tostring( gType ), tostring(gatherID))
					data[key] = string.format("%s - %s (%d)", gType, nodeName, (tonumber(data[key] and data[key]:match("%((%d+)%)$")) or 0) + 1)
				end
			end
		end
		return data
	end

	function plugin.AppendNodes(node_list, zone, db_type, node_type)
		local uiMapID = tonumber(zone) or (Routes.LZName and Routes.LZName[zone] and Routes.LZName[zone][2])
		local zoneToken = uiMapID and Gatherer.ZoneTokens.GetZoneToken(uiMapID)
		local targetID = tonumber(node_type)
		if not zoneToken or not targetID or not Gatherer.Storage.HasDataOnZone(zoneToken) then
			return Gatherer.Util.GetNodeName(targetID or 0), Gatherer.Util.GetNodeName(targetID or 0), db_type
		end
		for index, x, y in Gatherer.Storage.ZoneGatherNodes(zoneToken, db_type) do
			for _, gatherID in Gatherer.Storage.GetNodeGatherNames(zoneToken, db_type, index) do
				if gatherID == targetID then
					local coord = floor(x * 10000 + 0.5) * 10000 + floor(y * 10000 + 0.5)
					table.insert(node_list, coord)
					break
				end
			end
		end
		return Gatherer.Util.GetNodeName(targetID), Gatherer.Util.GetNodeName(targetID), db_type
	end

	function plugin.AddCallbacks() end
	function plugin.RemoveCallbacks() end

	Routes.plugins["GathererReforged"] = plugin
end

--------------------------------------------------------------------------------
-- 6. Cross-Addon Live Node Sharing Bridge
--    Supports:
--    - Gatherer Reborn ("GRBNode" tab-delimited protocol: "1\tzone\tnodeType\tcoords\tnodeID")
--    - GatherMate2_Sharing / GatherMate_Sharing ("GM2SD" & "GMSD")
--    - GatherLite ("GATHERLITE", "GatherLite", "GatherLiteSync", "G2G")
--    - Two-way live sync with local GatherMate2 & Gatherer Reborn installations
--------------------------------------------------------------------------------

local EXTERNAL_PREFIXES = {
	["GRBNode"] = "Gatherer Reborn",
	["GM2SD"] = "GatherMate_Sharing",
	["GMSD"] = "GatherMate_Sharing",
	["GatherRadar"] = "GatherRadar",
	["GATHERLITE"] = "GatherLite",
	["GatherLite"] = "GatherLite",
	["GatherLiteSync"] = "GatherLite",
	["G2G"] = "GatherLite",
}

local GR_LETTER_BY_DBTYPE = {
	["Herb Gathering"] = "h",
	["Mining"] = "o",
	["Treasure"] = "t",
	["Fishing"] = "f",
}
local GR_DBTYPE_BY_LETTER = {
	["h"] = "Herb Gathering",
	["o"] = "Mining",
	["t"] = "Treasure",
	["f"] = "Fishing",
}

-- Exact dbIndexes table from GatherMate_Sharing.lua (lines 21-36)
local GM2_DB_INDEXES = {
	["Herb Gathering"] = 1,
	["Mining"] = 2,
	["Fishing"] = 3,
	["Extract Gas"] = 4,
	["Treasure"] = 5,
	["Archaeology"] = 6,
	["Logging"] = 7,
	[1] = "Herb Gathering",
	[2] = "Mining",
	[3] = "Fishing",
	[4] = "Extract Gas",
	[5] = "Treasure",
	[6] = "Archaeology",
	[7] = "Logging",
}

local function safeRegisterAddonPrefix(prefix)
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
	elseif _G.RegisterAddonMessagePrefix then
		pcall(_G.RegisterAddonMessagePrefix, prefix)
	end
end

local function safeSendAddonMessage(prefix, text, chatType, target)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		pcall(C_ChatInfo.SendAddonMessage, prefix, text, chatType, target)
	elseif _G.SendAddonMessage then
		pcall(_G.SendAddonMessage, prefix, text, chatType, target)
	end
end

function Integrations.RegisterSharingPrefixes()
	for prefix in pairs(EXTERNAL_PREFIXES) do
		safeRegisterAddonPrefix(prefix)
	end
end

function Integrations.IsExternalSharingPrefix(prefix)
	return prefix and EXTERNAL_PREFIXES[prefix] ~= nil
end

local isMirroringGM2 = false

function Integrations.MirrorNodeToGatherMate2(objectId, gatherType, zoneToken, x, y)
	if isMirroringGM2 then return end
	if not Gatherer.Config.GetSetting("sharing.bridge.enable", true) then return end
	local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
	if not AceAddon then return end

	local uiMapID = tonumber(zoneToken)
	if not uiMapID and Gatherer.ZoneTokens and Gatherer.ZoneTokens.GetZoneToken then
		uiMapID = tonumber(Gatherer.ZoneTokens.GetZoneToken(zoneToken))
	end
	if not uiMapID or not x or not y or x <= 0 or y <= 0 or x >= 1 or y >= 1 then return end

	local gmNodeID, dbType = Integrations.GetGatherMateNodeForObject(objectId, gatherType)
	if not gmNodeID or not dbType then return end

	local coord = floor(x * 10000 + 0.5) * 1000000 + floor(y * 10000 + 0.5) * 100
	isMirroringGM2 = true
	for _, addonInfo in ipairs({
		{ name = "GatherMate2", msg = "GatherMate2ConfigChanged" },
		{ name = "GathererReborn", msg = "GathererRebornConfigChanged" },
	}) do
		local extAddon = AceAddon:GetAddon(addonInfo.name, true)
		if extAddon then
			local nodeName = extAddon.reverseNodeIDs and extAddon.reverseNodeIDs[dbType] and extAddon.reverseNodeIDs[dbType][gmNodeID]
			if nodeName and type(extAddon.AddNodeChecked) == "function" then
				pcall(extAddon.AddNodeChecked, extAddon, uiMapID, x, y, dbType, nodeName)
			elseif type(extAddon.InjectNode2) == "function" then
				pcall(extAddon.InjectNode2, extAddon, uiMapID, coord, dbType, gmNodeID)
				if type(extAddon.SendMessage) == "function" then
					pcall(extAddon.SendMessage, extAddon, addonInfo.msg)
				end
			end
		end
	end
	isMirroringGM2 = false
end

local lastExternalSent = {}
local lastExternalSentTime = 0

function Integrations.BroadcastToExternalAddons(chatType, target, objectId, gatherType, zoneToken, x, y)
	if not Gatherer.Config.GetSetting("sharing.bridge.enable", true) then return end
	local uiMapID = tonumber(zoneToken)
	if not uiMapID and Gatherer.ZoneTokens and Gatherer.ZoneTokens.GetZoneToken then
		uiMapID = tonumber(Gatherer.ZoneTokens.GetZoneToken(zoneToken))
	end
	if not uiMapID or not x or not y or x <= 0 or y <= 0 or x >= 1 or y >= 1 then return end

	local gmNodeID, dbType = Integrations.GetGatherMateNodeForObject(objectId, gatherType)
	if gmNodeID and dbType then
		local coord = floor(x * 10000 + 0.5) * 1000000 + floor(y * 10000 + 0.5) * 100
		lastExternalSentTime = GetTime and GetTime() or 0
		-- 1. Gatherer Reborn ("GRBNode") tab-delimited format: "1\t<zone>\t<nodeType>\t<coords>\t<nodeID>"
		local grbPayload = table.concat({ "1", tostring(uiMapID), tostring(dbType), tostring(coord), tostring(gmNodeID) }, "\t")
		lastExternalSent["GRBNode"] = grbPayload
		safeSendAddonMessage("GRBNode", grbPayload, chatType, target)

		-- 2. GatherMate_Sharing ("GM2SD") exact format ("A:%i:%i:%s:%i"): zone, dbIndexes[nodeType], coord, nodeID
		local dbIndex = GM2_DB_INDEXES[dbType] or 5
		local gm2Payload = string.format("A:%d:%d:%s:%d", uiMapID, dbIndex, tostring(coord), gmNodeID)
		lastExternalSent["GM2SD"] = gm2Payload
		safeSendAddonMessage("GM2SD", gm2Payload, chatType, target)

		-- 3. GatherRadar ("GatherRadar") format: "1|<letter>,<map>,<coord>,<id>"
		local grLetter = GR_LETTER_BY_DBTYPE[dbType]
		if grLetter and (chatType == "PARTY" or chatType == "RAID" or chatType == "INSTANCE_CHAT") then
			local grPayload = string.format("1|%s,%d,%.0f,%d", grLetter, uiMapID, coord, gmNodeID)
			lastExternalSent["GatherRadar"] = grPayload
			safeSendAddonMessage("GatherRadar", grPayload, chatType, target)
		end
	end
end

local lastExternalMsg = ""
function Integrations.OnExternalAddonMessage(prefix, msg, how, who)
	if not prefix or not msg or not EXTERNAL_PREFIXES[prefix] then return end
	if not Gatherer.Config.GetSetting("sharing.bridge.enable", true) then return end

	if Gatherer.Comm and Gatherer.Comm.IsSelfSender and Gatherer.Comm.IsSelfSender(who) then
		return
	end
	if lastExternalSent[prefix] == msg and lastExternalSentTime > 0 and ((GetTime and GetTime() or 0) - lastExternalSentTime) < 15 then
		return
	end
	local playerShort = UnitName("player")
	local cleanWho = type(who) == "string" and (who:match("^([^%-]+)") or who) or ""
	if playerShort and (who == playerShort or cleanWho == playerShort) then
		return
	end

	if Gatherer.Config.SharingBlacklist_IsPlayerIgnored and Gatherer.Config.SharingBlacklist_IsPlayerIgnored(who) then
		return
	end

	local msgtype = (how == "GUILD") and "guild" or "raid"
	if how ~= "WHISPER" then
		if not (Gatherer.Config.GetSetting(msgtype .. ".enable") and Gatherer.Config.GetSetting(msgtype .. ".receive")) then
			return
		end
	end

	local dedupKey = prefix .. "|" .. tostring(who) .. "|" .. tostring(msg)
	if dedupKey == lastExternalMsg then
		return
	end
	lastExternalMsg = dedupKey

	local objectID, gatherType, zoneToken, gatherX, gatherY
	local gmMapID, gmDbType, gmCoord, gmNodeID

	if prefix == "GRBNode" then
		-- Gatherer Reborn format: "1\t<zone>\t<nodeType>\t<coords>\t<nodeID>"
		local version, zoneStr, nodeTypeStr, coordsStr, nodeIDStr = msg:match("^(%d+)\t(%d+)\t([^\t]+)\t(%d+)\t(%d+)$")
		if version == "1" then
			gmMapID = tonumber(zoneStr)
			gmDbType = GM2_DB_INDEXES[tonumber(nodeTypeStr)] or nodeTypeStr
			gmCoord = tonumber(coordsStr)
			gmNodeID = tonumber(nodeIDStr)
			if gmMapID and gmDbType and gmCoord and gmNodeID then
				zoneToken = Gatherer.ZoneTokens.GetZoneToken(gmMapID)
				gatherX = floor(gmCoord / 1000000) / 10000
				gatherY = floor((gmCoord % 1000000) / 100) / 10000
				objectID, gatherType = resolveGatherMateNode(gmNodeID, gmDbType)
			end
		end
	elseif prefix == "GM2SD" or prefix == "GMSD" then
		-- GatherMate_Sharing format: "A:%i:%i:%s:%i" (cmd, zone, dbIndexes[nodeType], coord, nodeID)
		local p1, p2, p3, p4, p5 = strsplit(":", msg)
		if p1 == "D" then
			return -- ignore node deletion packets
		elseif p1 == "A" then
			gmMapID = tonumber(p2)
			gmDbType = GM2_DB_INDEXES[tonumber(p3)] or p3
			gmCoord = tonumber(p4)
			gmNodeID = tonumber(p5)
		else
			gmMapID = tonumber(p1)
			gmDbType = GM2_DB_INDEXES[tonumber(p2)] or p2
			gmCoord = tonumber(p3)
			gmNodeID = tonumber(p4)
		end

		if gmMapID and gmDbType and gmCoord and gmNodeID then
			zoneToken = Gatherer.ZoneTokens.GetZoneToken(gmMapID)
			gatherX = floor(gmCoord / 1000000) / 10000
			gatherY = floor((gmCoord % 1000000) / 100) / 10000
			objectID, gatherType = resolveGatherMateNode(gmNodeID, gmDbType)
		end
	elseif prefix == "GatherRadar" then
		-- GatherRadar format: "1|h,1411,3570284000,401;o,..."
		local version, body = msg:match("^(%d+)|(.*)$")
		if version == "1" and body then
			for entry in body:gmatch("[^;]+") do
				local letter, mapStr, coordStr, idStr = entry:match("^(%a),(%d+),(%d+),(%d+)$")
				local grDbType = letter and GR_DBTYPE_BY_LETTER[letter]
				local grMapID = tonumber(mapStr)
				local grCoord = tonumber(coordStr)
				local grNodeID = tonumber(idStr)
				if grDbType and grMapID and grCoord and grNodeID then
					local zToken = Gatherer.ZoneTokens.GetZoneToken(grMapID)
					local gx = floor(grCoord / 1000000) / 10000
					local gy = floor((grCoord % 1000000) / 100) / 10000
					local objID, gType = resolveGatherMateNode(grNodeID, grDbType)
					if objID and gType and zToken and gx > 0 and gx < 1 and gy > 0 and gy < 1 then
						if Gatherer.Scanner and Gatherer.Scanner.MarkNodeLive then
							Gatherer.Scanner.MarkNodeLive(zToken, gType, gx, gy)
						end
						objectID, gatherType, zoneToken, gatherX, gatherY = objID, gType, zToken, gx, gy
					end
				end
			end
		end
	else
		-- GatherLite format: either AceSerializer table/tuple or delimited string
		if Gatherer.Deserialize then
			local ok, a, b, c, d, e = Gatherer:Deserialize(msg)
			if ok then
				if type(a) == "table" then
					local nodeID = tonumber(a.nodeID or a.objectID or a.id)
					local mapID = tonumber(a.mapID or a.zone or a.uiMapID)
					local nx = tonumber(a.x or a.posX)
					local ny = tonumber(a.y or a.posY)
					if nodeID and mapID and nx and ny then
						objectID = nodeID
						gatherType = Gatherer.Nodes.Objects[objectID] or DB_TYPE_TO_GTYPE[a.type or ""] or "OPEN"
						zoneToken = Gatherer.ZoneTokens.GetZoneToken(mapID)
						gatherX, gatherY = nx, ny
					end
				elseif type(b) == "number" and type(c) == "number" then
					objectID = tonumber(b)
					zoneToken = Gatherer.ZoneTokens.GetZoneToken(tonumber(c))
					gatherX = tonumber(d)
					gatherY = tonumber(e)
					gatherType = objectID and Gatherer.Nodes.Objects[objectID]
				end
			end
		end
		if not objectID then
			local p1, p2, p3, p4, p5 = strsplit(":;\t", msg)
			local nodeID = tonumber(p2) or tonumber(p1)
			local mapID = tonumber(p3) or tonumber(p2)
			local nx = tonumber(p4) or tonumber(p3)
			local ny = tonumber(p5) or tonumber(p4)
			if nodeID and mapID and nx and ny then
				objectID = nodeID
				gatherType = Gatherer.Nodes.Objects[objectID]
				zoneToken = Gatherer.ZoneTokens.GetZoneToken(mapID)
				gatherX, gatherY = nx, ny
			end
		end
	end

	if objectID and gatherType and zoneToken and gatherX and gatherY and gatherX > 0 and gatherX < 1 and gatherY > 0 and gatherY < 1 then
		Gatherer.Api.AddGather(objectID, gatherType, false, who, nil, nil, false, nil, zoneToken, gatherX, gatherY)
		-- Also mirror into local GatherMate2 / Gatherer Reborn if installed
		Integrations.MirrorNodeToGatherMate2(objectID, gatherType, zoneToken, gatherX, gatherY)

		if Gatherer.Config.GetSetting(msgtype .. ".print.recv") then
			local objName = Gatherer.Util.GetNodeName(objectID)
			local localizedZoneName = Gatherer.ZoneTokens.ZoneNames[zoneToken] or tostring(zoneToken)
			local _tr = Gatherer.Locale.Tr
			local howKey = (how == "INSTANCE_CHAT") and "GROUP" or how
			Gatherer.Util.ChatPrint(_tr("COMM_RECEIVE_NODE", objName, localizedZoneName, who .. " [" .. (EXTERNAL_PREFIXES[prefix] or prefix) .. "]", _tr(howKey)))
		end
	end
end

local hookedLiveAddons = {}
function Integrations.SetupGatherMate2LiveSync()
	local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
	if not AceAddon then return end

	for _, addonName in ipairs({ "GatherMate2", "GathererReborn" }) do
		if not hookedLiveAddons[addonName] then
			local extAddon = AceAddon:GetAddon(addonName, true)
			if extAddon and type(extAddon.AddNode) == "function" then
				hookedLiveAddons[addonName] = true
				hooksecurefunc(extAddon, "AddNode", function(self, zone, x, y, nodeType, name)
					if isMirroringGM2 then return end
					if not Gatherer.Config.GetSetting("sharing.bridge.enable", true) then return end
					local uiMapID = tonumber(zone)
					local zoneToken = uiMapID and Gatherer.ZoneTokens and Gatherer.ZoneTokens.GetZoneToken(uiMapID)
					if not zoneToken or not x or not y then return end

					local gmNodeID = self.nodeIDs and self.nodeIDs[nodeType] and self.nodeIDs[nodeType][name]
					local objID, gType = resolveGatherMateNode(gmNodeID, nodeType)
					if not objID and name and Gatherer.Nodes then
						objID = Gatherer.Nodes.Names[name]
						gType = (objID and Gatherer.Nodes.Objects[objID]) or DB_TYPE_TO_GTYPE[nodeType] or "OPEN"
						if not objID and Gatherer.Nodes.RegisterDynamicNode then
							objID = Gatherer.Nodes.RegisterDynamicNode(name, gType)
						end
					end

					if objID and gType then
						isMirroringGM2 = true
						Gatherer.Api.AddGather(objID, gType, false, nil, nil, nil, false, nil, zoneToken, x, y)
						isMirroringGM2 = false
					end
				end)
			end
		end
	end
end

local bridgeFrame = CreateFrame("Frame")
bridgeFrame:RegisterEvent("PLAYER_LOGIN")
bridgeFrame:RegisterEvent("ADDON_LOADED")
bridgeFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" or arg1 == "FarmHud" or arg1 == "Routes" or arg1 == "GatherMate2" or arg1 == "Gatherer_Reborn" then
		Integrations.SetupFarmHud()
		Integrations.SetupRoutes()
		Integrations.SetupGatherMate2LiveSync()
		Integrations.RegisterSharingPrefixes()
	end
end)
