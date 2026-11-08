--[[
	Gatherer Reforged Addon for World of Warcraft(tm).
	Version: 1.0.0
	Author: gOOvER

	License:
		This program is free software: you can redistribute it and/or modify
		it under the terms of the GNU General Public License as published by
		the Free Software Foundation, either version 3 of the License, or
		(at your option) any later version.

		This program is distributed in the hope that it will be useful,
		but WITHOUT ANY WARRANTY; without even the implied warranty of
		MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
		GNU General Public License for more details.

		You should have received a copy of the GNU General Public License
		along with this program (see gpl.txt); if not, see <https://www.gnu.org/licenses/>.
]]

-- reference to the Gatherer.Map mapping engine
local Map = Gatherer.Map

function Gatherer.Util.Round(x)
	return math.ceil(x - 0.5);
end

function Gatherer.Util.BreakLink(link)
	--DEFAULT_CHAT_FRAME:AddMessage("Breaking link: " .. (link or "None"))

	if (type(link) ~= 'string') then return end
--	local item, name = link:match("|H(.-)|h[[]([^]]+)[]]|h")
	local i,j, item, name = string.find(link, "|H(.-)|h[[](.-)[]]|h")
	--DEFAULT_CHAT_FRAME:AddMessage(" found item "..(item or "None")..": " .. (name or "None"))
	local itype, id, enchant, slot1,slot2,slot3,slot4, random, uniq = strsplit(":", item)
	
	--DEFAULT_CHAT_FRAME:AddMessage(" id: "..(id or "None"))
	if (random == nil) then
		random, uniq = slot1, slot2
		slot1, slot2, slot3, slot4 = 0, 0, 0, 0
	end
	return
		tonumber(id) or 0,
		tonumber(enchant) or 0,
		tonumber(random) or 0,
		tonumber(slot1) or 0,
		tonumber(slot2) or 0,
		tonumber(slot3) or 0,
		tonumber(slot4) or 0,
		tonumber(uniq) or 0,
		name, itype
end

function Gatherer.Util.DumpAll()
	for _, zone in Gatherer.Storage.GetAreaIndices() do
		for gatherName, gtype in Gatherer.Storage.ZoneGatherNames(zone) do
			for index, x, y, count in Gatherer.Storage.ZoneGatherNodes(zone, gatherName) do
				Gatherer.Util.Print(gtype.." "..gatherName.." was found in zone "..zone.." at "..x..","..y.."  ("..count.." times)")
			end
		end
	end
end

function Gatherer.Util.ChatPrint(str)
	if ( DEFAULT_CHAT_FRAME ) then
		DEFAULT_CHAT_FRAME:AddMessage(str, 1.0, 0.5, 0.25)
	end
end

function Gatherer.Util.Print(str, add)
	if ((Gatherer.Var.LastPrited) and (str == Gatherer.Var.LastPrited)) then
		return
	end
	Gatherer.Var.LastPrited = str
	if (add) then
		str = str..": "..add
	end
	if(ChatFrame5) then
		ChatFrame5:AddMessage(str, 1.0, 1.0, 0.0)
	end
end

function Gatherer.Util.Debug(str, ...)
	if not ( type(Gatherer.Util.DebugFrame) == "table" and Gatherer.Util.DebugFrame.AddMessage ) then
		return
	end
	str = str..": "..strjoin(", ", tostringall(...))
	Gatherer.Util.DebugFrame:AddMessage("DEBUG: "..str, 1.0, 1.0, 0.0)
end

local checkingSkills = false

function Gatherer.Util.GetSkills()
	if checkingSkills then return end
	checkingSkills = true

	if not Gatherer.Var.Skills then Gatherer.Var.Skills = {} end
	Gatherer.Var.Skills.HERB = nil
	Gatherer.Var.Skills.MINE = nil

	local ProfessionTextures = Gatherer.Constants and Gatherer.Constants.ProfessionTextures
	local ProfessionSkillLines = Gatherer.Constants and Gatherer.Constants.ProfessionSkillLines
	local herbName = Gatherer.Locale and Gatherer.Locale.TrClient and Gatherer.Locale.TrClient("TRADE_HERBALISM")
	local mineName = Gatherer.Locale and Gatherer.Locale.TrClient and Gatherer.Locale.TrClient("TRADE_MINING")

	-- 1. Try modern GetProfessions() API
	if GetProfessions and GetProfessionInfo then
		for _, profId in pairs({GetProfessions()}) do
			if profId then
				local name, texture, skillRank, maxRank, _, _, skillLine = GetProfessionInfo(profId)
				local gType = (skillLine and ProfessionSkillLines and ProfessionSkillLines[skillLine])
					or (texture and ProfessionTextures and ProfessionTextures[texture])
				if not gType and name then
					if herbName and name == herbName then
						gType = "HERB"
					elseif mineName and name == mineName then
						gType = "MINE"
					end
				end
				if gType then
					Gatherer.Var.Skills[gType] = math.max(skillRank or 1, 1)
				end
			end
		end
	end

	-- 2. Fallback to Classic GetNumSkillLines() / GetSkillLineInfo() (used on Classic Era / Forever)
	if (not Gatherer.Var.Skills.HERB or not Gatherer.Var.Skills.MINE) and GetNumSkillLines and GetSkillLineInfo then
		local GatherExpandedHeaders = {}
		for i = 0, GetNumSkillLines(), 1 do
			local skillName, header, isExpanded = GetSkillLineInfo(i)
			if header and not isExpanded then
				GatherExpandedHeaders[i] = skillName
			end
		end

		if ExpandSkillHeader then pcall(ExpandSkillHeader, 0) end
		for i = 1, GetNumSkillLines(), 1 do
			local skillName, header, _, skillRank = GetSkillLineInfo(i)
			if skillName and not header then
				if herbName and skillName == herbName then
					Gatherer.Var.Skills.HERB = math.max(skillRank or 1, 1)
				elseif mineName and skillName == mineName then
					Gatherer.Var.Skills.MINE = math.max(skillRank or 1, 1)
				end
			end
			if Gatherer.Var.Skills.HERB and Gatherer.Var.Skills.MINE then
				break
			end
		end

		if CollapseSkillHeader then
			for i = 0, GetNumSkillLines() do
				local skillName, header = GetSkillLineInfo(i)
				for j in pairs(GatherExpandedHeaders) do
					if header and skillName == GatherExpandedHeaders[j] then
						pcall(CollapseSkillHeader, i)
						GatherExpandedHeaders[j] = nil
					end
				end
			end
		end
	end

	checkingSkills = false
end

--******************************************************
-- Current Tracking State Tracker System
--******************************************************

local currentTracks = {};

function Gatherer.Util.UpdateTrackingState()
	local TrackingTextures = Gatherer.Constants.TrackingTextures;
	for id = 1, GetNumTrackingTypes() do
		local name, texture, active, category  = GetTrackingInfo(id);
		if ( TrackingTextures[texture] ) then
			currentTracks[TrackingTextures[texture]] = active and true or false
		end
	end
end

function Gatherer.Util.IsGatherTracked( nodeId )
	local trackType = Gatherer.Nodes.Objects[nodeId]
	
	-- check for a tracking type override
	local category = Gatherer.Categories.ObjectCategories[nodeId]
	trackType = Gatherer.Constants.TrackingOverrides[category] or trackType
	
	return currentTracks[trackType]
end

function Gatherer.Util.IsNodeTracked( mapZone, gatherType, index )
	if ( gatherType == "OPEN" ) or ( gatherType == "ARCH" ) then
		-- tracking overrides only happen for OPEN or ARCH items
		for _, gatherID, count in Gatherer.Storage.GetNodeGatherNames(mapZone, gatherType, index) do
			if ( Gatherer.Util.IsGatherTracked(gatherID) ) then
				return true
			end
		end
	else
		return currentTracks[gatherType]
	end
	return false
end

--******************************************************
-- END Current Tracking State Tracker System
--******************************************************

local nodeNames = {}
if Gatherer.Nodes and Gatherer.Nodes.PrimaryNames then
	for objid, name in pairs(Gatherer.Nodes.PrimaryNames) do
		nodeNames[objid] = name
	end
end
for name, objid in pairs(Gatherer.Nodes.Names) do
	if not nodeNames[objid] then
		nodeNames[objid] = name
	end
end
function Gatherer.Util.RegisterDynamicNodeName(objectID, name)
	if objectID and name then
		nodeNames[objectID] = name
	end
end
function Gatherer.Util.GetNodeName(objectID)
	return (Gatherer.Nodes and Gatherer.Nodes.PrimaryNames and Gatherer.Nodes.PrimaryNames[objectID])
		or nodeNames[objectID]
		or ("Unknown: "..tostring(objectID))
end

function Gatherer.Util.BuildLoot(coins, ...)
	local loot = {}
	coins = tonumber(coins) or 0
	for i=1, select("#", ...) do
		local lootItem = select(i, ...)
		local itemID, count = strsplit("x", lootItem)
		itemID = tonumber(itemID)
		count = tonumber(count)
		if (itemID and count) then
			table.insert(loot, { id = itemID, count = count })
		end
	end
	return coins, loot
end

function Gatherer.Util.LootSplit(lootString)
	return Gatherer.Util.BuildLoot(strsplit(":", lootString))
end

local parseStrings = {}
local parseStringInfo = {}
local returnCache = {}

local function processMatches( format, ... )
	local parseInfo = parseStringInfo[format]
	for i = 1, select("#", ...) do
		if ( parseInfo[i] ) then
			returnCache[i] = select(parseInfo[i], ...)
		else
			returnCache[i] = ""
		end
	end
	return unpack(returnCache, 1, select("#", ...))
end

local function replaceAllBut( char )
	if ( char ~= "$" and char ~= "%" ) then
		return "%"..char
	end
end

function Gatherer.Util.ParseFormattedMessage(format, message)
	local parser = parseStrings[format]
	if not ( parser ) then
		parser = string.gsub(format, "([%p])", replaceAllBut)
		local parseInfo = {}
		local curPos = 0
		local count = 0
		local function analyzeMatch( index, check, type )
			if ( #index > 1 ) then return end
			index = tonumber(index)
			if ( index ) then
				curPos = index
				if ( check ~= "$" ) then
					return
				end
			else
				curPos = curPos + 1
			end
			local replacement
			if ( type == "s" ) then
				replacement = "(.-)"
			elseif ( type == "d" ) then
				replacement = "(-?%d+)"
			else
				return
			end
			count = count + 1
			parseInfo[curPos] = count
			return replacement
		end
		parser = string.gsub(parser, "%%(%d?)(%$?)([sd])", analyzeMatch)
		parseStringInfo[format] = parseInfo
		parser = string.gsub(parser, "%$", "%%$")
		parser = "^"..parser.."$"
		parseStrings[format] = parser
	end
	return processMatches(format, string.match(message, parser))
end

local BuiltinCategoryIcons = {
	-- Treasure / Openable Nodes
	["Open\\Chest"] = 132594,
	["Open\\Crate"] = 132763,
	["Open\\Barrel"] = 132622,
	["Open\\Footlocker"] = 132596,
	["Open\\Clam"] = 133885,
	["Open\\Glowcap"] = 134529,
	["Open\\Egg"] = 132834,
	["Open\\OynxEgg"] = 132834,
	["Open\\NightDragon"] = 134189,
	["Open\\Songflower"] = 134187,
	["Open\\WindBlossom"] = 134188,
	["Open\\WhipperRoot"] = 134059,
	["Open\\BloodHero"] = 134829,
	["Open\\ShellfishTrap"] = 132596,
	["UngoroCrystal"] = 134077,
	["UngoroSprout"] = 134221,

	-- Mining Nodes (Classic-compatible FileDataIDs available across all clients)
	["Mine\\Copper"] = 134566,
	["Mine\\Tin"] = 134579,
	["Mine\\Silver"] = 134577,
	["Mine\\Iron"] = 134572,
	["Mine\\Gold"] = 134570,
	["Mine\\Mithril"] = 134576,
	["Mine\\TrueSilver"] = 134580,
	["Mine\\Thorium"] = 134578,
	["Mine\\RichThorium"] = 134578,
	["Mine\\DarkIron"] = 134573,
	["Mine\\LesserBloodstone"] = 134574,
	["Mine\\FelIron"] = 134569,
	["Mine\\Adamantite"] = 134561,
	["Mine\\Khorium"] = 134575,
	["Mine\\Nethercite"] = 134568,
	["Mine\\Cobalt"] = 134565,
	["Mine\\Saronite"] = 134576,
	["Mine\\Titanium"] = 134580,
	["Mine\\Obsidium"] = 134573,
	["Mine\\Pyrite"] = 134570,
	["Mine\\Elementium"] = 134574,
	["Mine\\GhostIron"] = 134572,
	["Mine\\Kyparite"] = 134561,
	["Mine\\Trillium"] = 134580,
	["Mine\\TrueIron"] = 134572,
	["Mine\\Blackrock"] = 134573,
	["Mine\\Leystone"] = 134576,
	["Mine\\Felslate"] = 134569,
	["Mine\\EmpyriumDeposit"] = 134575,
	["Mine\\EmpyriumSeam"] = 134575,

	-- Herbalism Nodes (Classic-compatible FileDataIDs available across all clients)
	["Herb\\Silverleaf"] = 134199,
	["Herb\\Peacebloom"] = 134187,
	["Herb\\Earthroot"] = 134196,
	["Herb\\Mageroyal"] = 134193,
	["Herb\\Briarthorn"] = 134200,
	["Herb\\Bruiseweed"] = 134190,
	["Herb\\WildSteelbloom"] = 134186,
	["Herb\\Kingsblood"] = 134192,
	["Herb\\GraveMoss"] = 134191,
	["Herb\\Liferoot"] = 134201,
	["Herb\\Fadeleaf"] = 134197,
	["Herb\\KhadgarsWhisker"] = 134194,
	["Herb\\Wintersbite"] = 134188,
	["Herb\\Stranglekelp"] = 134198,
	["Herb\\Goldthorn"] = 134195,
	["Herb\\Firebloom"] = 134209,
	["Herb\\PurpleLotus"] = 134207,
	["Herb\\ArthasTears"] = 134203,
	["Herb\\Sungrass"] = 134208,
	["Herb\\Blindweed"] = 134204,
	["Herb\\GhostMushroom"] = 134202,
	["Herb\\Gromsblood"] = 134206,
	["Herb\\GoldenSansam"] = 134221,
	["Herb\\Dreamfoil"] = 134213,
	["Herb\\MountainSilversage"] = 134215,
	["Herb\\Plaguebloom"] = 134219,
	["Herb\\Icecap"] = 134214,
	["Herb\\BlackLotus"] = 134212,
	["Herb\\Felweed"] = 134190,
	["Herb\\DreamingGlory"] = 134213,
	["Herb\\Ragveil"] = 134202,
	["Herb\\FlameCap"] = 134209,
	["Herb\\Terocone"] = 134221,
	["Herb\\AncientLichen"] = 134191,
	["Herb\\Netherbloom"] = 134207,
	["Herb\\NightmareVine"] = 134206,
	["Herb\\ManaThistle"] = 134214,
	["Herb\\Netherdust"] = 134203,
	["Herb\\GoldClover"] = 134208,
	["Herb\\TigerLily"] = 134186,
	["Herb\\TalandrasRose"] = 134187,
	["Herb\\LichBloom"] = 134219,
	["Herb\\IceThorn"] = 134214,
	["Herb\\FrostLotus"] = 134212,
	["Herb\\AddersTongue"] = 134198,
	["Herb\\Cinderbloom"] = 134209,
	["Herb\\Stormvine"] = 134213,
	["Herb\\AzsharasVeil"] = 134207,
	["Herb\\Heartblossom"] = 134192,
	["Herb\\TwilightJasmine"] = 134203,
	["Herb\\Whiptail"] = 134201,
	["Herb\\GreenTeaLeaf"] = 134199,
	["Herb\\Silkweed"] = 134197,
	["Herb\\SnowLilly"] = 134188,
	["Herb\\RainPoppy"] = 134187,
	["Herb\\GoldenLotus"] = 134208,
	["Herb\\FoolsCap"] = 134202,
	["Herb\\ShaTouchedHerb"] = 134212,
	["Herb\\Frostweed"] = 134214,
	["Herb\\Fireweed"] = 134209,
	["Herb\\GorgrondFlytrap"] = 134221,
	["Herb\\Starflower"] = 134186,
	["Herb\\NagrandArrowbloom"] = 134192,
	["Herb\\TaladorOrchid"] = 134207,
	["Herb\\WitheredHerb"] = 134196,
	["Herb\\Aethril"] = 134204,
	["Herb\\Dreamleaf"] = 134213,
	["Herb\\Foxflower"] = 134209,
	["Herb\\Fjarnskaggl"] = 134195,
	["Herb\\StarlightRose"] = 134203,
	["Herb\\FelEncrustedHerb"] = 134206,
	["Herb\\FelEncrustedHerbCluster"] = 134206,
	["Herb\\AstralGlory"] = 134215,
}

local BuiltinGatherTypeIcons = {
	MINE = 134708,
	HERB = 136246,
	OPEN = 132594,
	ARCH = 134435,
}

local function isQuestionMarkIcon(tex)
	if not tex then return true end
	if tex == 134400 then return true end
	if type(tex) == "string" and tex:lower():find("inv_misc_questionmark", 1, true) then
		return true
	end
	return false
end

function Gatherer.Util.GetNodeTexture( mapZone, gatherType, index )
	local texture, trimTexture = BuiltinGatherTypeIcons[gatherType] or 132594, true
	local maxCount = -1
	for _, gatherID, count in Gatherer.Storage.GetNodeGatherNames(mapZone, gatherType, index) do
		if ( count > maxCount ) then
			texture, trimTexture = Gatherer.Util.GetGatherTexture(gatherID)
			maxCount = count
		end
	end
	return texture, trimTexture
end

function Gatherer.Util.GetGatherTexture( nodeID )
	local selectedTexture
	local trimTexture = false

	if ( Gatherer.Nodes.PrimaryItems[nodeID] ) then
		selectedTexture = GetItemIcon(Gatherer.Nodes.PrimaryItems[nodeID])
		if isQuestionMarkIcon(selectedTexture) then
			selectedTexture = nil
		end
		trimTexture = selectedTexture and true or false
	end

	if ( not selectedTexture and Gatherer.Icons[nodeID] ) then
		local iconKey = Gatherer.Icons[nodeID]
		if BuiltinCategoryIcons[iconKey] then
			selectedTexture = BuiltinCategoryIcons[iconKey]
			trimTexture = true
		end
	end

	if not ( selectedTexture ) then
		local prime, pcount = Gatherer.DropRates.GetPrimaryItem(nodeID)
		if ( prime ) then
			local primaryName, nodeTexture, _
			if ( prime < 0 ) then
				primaryName, _, nodeTexture = GetCurrencyInfo(-prime)
			else
				nodeTexture = GetItemIcon(prime) or select(10, GetItemInfo(prime))
			end
			if isQuestionMarkIcon(nodeTexture) then
				nodeTexture = nil
			end
			selectedTexture = nodeTexture
			trimTexture = selectedTexture and true or false
		end
	end

	-- Fallback by gatherType
	if ( not selectedTexture ) then
		local gType = Gatherer.Nodes.Objects[nodeID]
		selectedTexture = BuiltinGatherTypeIcons[gType] or 132594
		trimTexture = true
	end

	return selectedTexture, trimTexture
end

function Gatherer.Util.GetGatherDifficultyColor(nodeID, gType)
	if not nodeID then return nil end
	gType = gType or (Gatherer.Nodes and Gatherer.Nodes.Objects and Gatherer.Nodes.Objects[nodeID])
	if gType ~= "HERB" and gType ~= "MINE" then return nil end

	local catKey = Gatherer.Categories and Gatherer.Categories.ObjectCategories and Gatherer.Categories.ObjectCategories[nodeID]
	local reqSkill = (Gatherer.Nodes and Gatherer.Nodes.SkillLevels and Gatherer.Nodes.SkillLevels[nodeID])
		or (catKey and Gatherer.Constants and Gatherer.Constants.SkillLevel and Gatherer.Constants.SkillLevel[catKey])
	if not reqSkill then return nil end

	local playerSkill = Gatherer.Var and Gatherer.Var.Skills and Gatherer.Var.Skills[gType]
	if not playerSkill or type(playerSkill) ~= "number" or playerSkill <= 0 then
		return 0.95, 0.20, 0.20, reqSkill, 0
	end

	local over = playerSkill - reqSkill
	if over < 0 then
		return 0.95, 0.20, 0.20, reqSkill, playerSkill -- Red (too low skill)
	elseif over < 25 then
		return 1.00, 0.50, 0.25, reqSkill, playerSkill -- Orange (high skill-up chance)
	elseif over < 50 then
		return 1.00, 0.88, 0.15, reqSkill, playerSkill -- Yellow (medium skill-up chance)
	elseif over < 100 then
		return 0.25, 0.82, 0.25, reqSkill, playerSkill -- Green (low skill-up chance)
	else
		return 0.62, 0.64, 0.68, reqSkill, playerSkill -- Gray (trivial)
	end
end

function Gatherer.Util.GetNodeDifficultyColor(mapZone, gatherType, index)
	if gatherType ~= "HERB" and gatherType ~= "MINE" then return nil end
	local bestGatherID = nil
	local maxCount = -1
	for _, gatherID, count in Gatherer.Storage.GetNodeGatherNames(mapZone, gatherType, index) do
		if count > maxCount then
			bestGatherID = gatherID
			maxCount = count
		end
	end
	if bestGatherID then
		return Gatherer.Util.GetGatherDifficultyColor(bestGatherID, gatherType)
	end
	return nil
end

-- convert list of zoneID1, zoneName1, zoneID2, zoneName2, etc.
-- into just a list of zone names
local function stripZoneIDs(...)
	local n = select("#", ...)
	--print("zoneList count = ", n );
	local temp = {};
	local index = 1;
	for i = 2, n, 2 do
		temp[index] = select(i, ...);
		--print("  item = ", temp[index] );
		index = index + 1;
	end
	return temp;
end

function Gatherer.Util.GetPositionInCurrentZone()
	local realZoneText = GetRealZoneText()
	local zoneToken = Gatherer.ZoneTokens.ZoneNames[realZoneText]
	if ( type(zoneToken) == "table" ) then
		local _, _, _, worldMapID = UnitPosition("player")
		zoneToken = zoneToken[worldMapID] or zoneToken[""]
	end
	local mapID, mapFloor, px, py = Map:GetCurrentPlayerPosition()
	if not ( mapID ) then return end
	if ( zoneToken ) then
		local realMapID, realMapFloor = Gatherer.ZoneTokens.GetZoneMapIDAndFloor(zoneToken)
		if ( realMapID ) then
			px, py = Map:TranslateWorldMapPosition(mapID, mapFloor, px, py, realMapID, realMapFloor)
		else
			return
		end
	else
		zoneToken = Gatherer.ZoneTokens.GetZoneToken(mapID)
	end
	
	-- for debugging Blizzard borked zones, convert to something stable so we can save the data temporarily
	--if (not zoneToken) then
		--print("Gatherer: Unknown zone for mapID: ", mapID )
		--zoneToken = tostring(mapID)
	---end
	
	if ( zoneToken ) then
		return zoneToken, px, py
	end
end


function Gatherer.Util.SecondsToTime(seconds, noSeconds)
	local time = ""
	local count = 0
	local GetText = Gatherer.Locale.GetText
	seconds = floor(seconds)
	if ( seconds >= 604800 ) then
		local tempTime = floor(seconds / 604800)
		time = tempTime.." "..GetText("WEEKS_ABBR", tempTime).." "
		seconds = (seconds % 604800)
		count = count + 1
	end
	if ( seconds >= 86400  ) then
		local tempTime = floor(seconds / 86400)
		time = time..tempTime.." "..GetText("DAYS_ABBR", tempTime).." "
		seconds = (seconds % 86400)
		count = count + 1
	end
	if ( count < 2 and seconds >= 3600  ) then
		local tempTime = floor(seconds / 3600)
		time = time..tempTime.." "..GetText("HOURS_ABBR", tempTime).." "
		seconds = (seconds % 3600)
		count = count + 1
	end
	if ( count < 2 and seconds >= 60  ) then
		local tempTime = floor(seconds / 60)
		time = time..tempTime.." "..GetText("MINUTES_ABBR",tempTime).." "
		seconds = (seconds % 60)
		count = count + 1
	end
	if ( count < 2 and seconds > 0 and not noSeconds ) then
		time = time..seconds.." "..GetText("SECONDS_ABBR", seconds).." "
	end
	return time
end


--******************************************************
-- Client Item Cache Refresh System
--******************************************************

local refreshFrame = CreateFrame("Frame")
local tooltip = not (C_Item and C_Item.RequestLoadItemDataByID) and CreateFrame("GameTooltip", "GathererCacheRefreshTooltip", nil, "GameTooltipTemplate") or nil
refreshFrame:Hide()
local itemIdList = {}
local lastItem = nil
local timer = 0


function Gatherer.Util.StartClientItemCacheRefresh()
	if ( Gatherer.DropRates.OldData ) then
		for nodeId, nodeData in pairs(Gatherer.DropRates.OldData) do
			for itemId in pairs(nodeData) do
				if ( type(itemId) == "number" ) then
					itemIdList[itemId] = true
				end
			end
		end
	end
	for cont, contData in ipairs(Gatherer.DropRates.Data) do
		for zone, zoneData in pairs(contData) do
			for nodeId, nodeData in pairs(zoneData) do
				for itemId in pairs(nodeData) do
					if ( type(itemId) == "number" ) then
						itemIdList[itemId] = true
					end
				end
			end
		end
	end
	
	lastItem = nil
	timer = 0
	refreshFrame:Show()
end

refreshFrame:SetScript("OnUpdate",
	function( self, elapsed )
		timer = timer + elapsed
		if ( timer > 5 ) then
			timer = 0
			local itemId = next(itemIdList, lastItem)
			if not ( itemId ) then
				self:Hide()
				return
			end
			
			while ( itemId and GetItemInfo(itemId) ) do
				itemId = next(itemIdList, itemId)
			end
			if not ( itemId ) then
				self:Hide()
				return
			end
			if C_Item and C_Item.RequestLoadItemDataByID then
				if itemId > 0 then
					C_Item.RequestLoadItemDataByID(itemId)
				end
			elseif tooltip then
				tooltip:SetOwner(refreshFrame, "ANCHOR_NONE")
				tooltip:SetHyperlink("item:"..itemId..":0:0:0:0:0:0:0")
			end
			lastItem = itemId
		end
	end
)
