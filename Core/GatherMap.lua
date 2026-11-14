--[[
	Gatherer Reforged - Native C_Map Mapping Engine (Gatherer.Map)
	Replaces the discontinued Astrolabe library with direct C_Map API support
	for Retail (11.x / 12.x), Classic (Era / Progression), and WoW Forever (16001+).

	License:
		This program is free software: you can redistribute it and/or modify
		it under the terms of the GNU General Public License as published by
		the Free Software Foundation, either version 3 of the License, or
		(at your option) any later version.
]]

local Map = Gatherer.Map or {}
Gatherer.Map = Map

Map.IconsOnEdge = {}
Map.MinimapIcons = {}
Map.IconAssociations = {}
Map.LastPlayerPosition = { 0, 0, 0, 0 }
Map.minimapOutside = true
Map.WorldMapVisible = false
Map.TargetMinimapChanged_Callbacks = {}
Map.ContinentList = {}
Map.HarvestedMapData = {}

local processingFrame = CreateFrame("Frame", "GathererMapProcessingFrame", Minimap)
Map.processingFrame = processingFrame

-- Ensure WorldMapButton global exists on modern clients (8.0+) for XML and Lua compatibility
if not _G.WorldMapButton and WorldMapFrame then
	local canvas = (WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas())
		or (WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child)
		or WorldMapFrame
	_G.WorldMapButton = canvas
end

-- Minimap indoor/outdoor radius tables (fallback when C_Minimap.GetViewRadius is unavailable)
local MinimapSize = {
	indoor = { [0] = 300, [1] = 240, [2] = 180, [3] = 120, [4] = 80, [5] = 50 },
	outdoor = { [0] = 466 + 2/3, [1] = 400, [2] = 333 + 1/3, [3] = 266 + 2/6, [4] = 200, [5] = 133 + 1/3 },
}

local function getMinimapRadius()
	if C_Minimap and C_Minimap.GetViewRadius then
		local r = C_Minimap.GetViewRadius()
		if r and r > 0 then return r end
	end
	local zoom = Minimap:GetZoom() or 0
	if Map.minimapOutside then
		return (MinimapSize.outdoor[zoom] or 400) / 2
	else
		return (MinimapSize.indoor[zoom] or 240) / 2
	end
end

-- Build Continent & Zone hierarchy using C_Map (WoW 8.0+)
local continentRecords = {}
local mapSizeCache = {}

local function queryMapSize(uiMapID)
	if not uiMapID then return 4000, 2666 end
	local cached = mapSizeCache[uiMapID]
	if cached then return cached[1], cached[2] end

	if C_Map and C_Map.GetMapWorldSize then
		local w, h = C_Map.GetMapWorldSize(uiMapID)
		if w and h and w > 0 and h > 0 then
			mapSizeCache[uiMapID] = { w, h }
			return w, h
		end
	end

	if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
		local ok1, inst1, pos1 = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, CreateVector2D(0, 0))
		local ok2, inst2, pos2 = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, CreateVector2D(1, 1))
		if ok1 and ok2 and pos1 and pos2 and inst1 == inst2 then
			-- In WoW world coords: x is North-South (height), y is West-East (width)
			local w = math.abs((pos1.y or 0) - (pos2.y or 0))
			local h = math.abs((pos1.x or 0) - (pos2.x or 0))
			if w > 0 and h > 0 then
				mapSizeCache[uiMapID] = { w, h }
				return w, h
			end
		end
	end

	mapSizeCache[uiMapID] = { 4000, 2666 }
	return 4000, 2666
end

local function harvestModernMaps()
	if not (C_Map and C_Map.GetMapInfo and C_Map.GetMapChildrenInfo) then return end

	local seenContinents = {}
	local seenZones = {}

	local function addContinent(contMapInfo)
		if not contMapInfo or not contMapInfo.mapID or seenContinents[contMapInfo.mapID] then return end
		seenContinents[contMapInfo.mapID] = true

		local contIdx = #continentRecords + 1
		local zList = { [0] = contMapInfo.mapID }
		local zNames = {}
		local w, h = queryMapSize(contMapInfo.mapID)
		Map.HarvestedMapData[contMapInfo.mapID] = {
			mapName = contMapInfo.name or ("Continent " .. contMapInfo.mapID),
			cont = contIdx,
			zone = 0,
			width = w,
			height = h,
		}

		local children = C_Map.GetMapChildrenInfo(contMapInfo.mapID, nil, true) or {}
		for _, child in ipairs(children) do
			if child and child.mapID and not seenZones[child.mapID] then
				if not Enum or not Enum.UIMapType or child.mapType == Enum.UIMapType.Zone or child.mapType == Enum.UIMapType.Micro or child.mapType == Enum.UIMapType.Continent then
					seenZones[child.mapID] = true
					local zIdx = #zList + 1
					zList[zIdx] = child.mapID
					zNames[zIdx] = child.name or ("Zone " .. child.mapID)
					local zw, zh = queryMapSize(child.mapID)
					Map.HarvestedMapData[child.mapID] = {
						mapName = child.name or ("Zone " .. child.mapID),
						cont = contIdx,
						zone = zIdx,
						width = zw,
						height = zh,
					}
				end
			end
		end

		Map.ContinentList[contIdx] = zList
		continentRecords[contIdx] = {
			mapID = contMapInfo.mapID,
			name = contMapInfo.name or ("Continent " .. contMapInfo.mapID),
			zones = zList,
			zoneNames = zNames,
		}
	end

	-- Scan Cosmic (946) and World (947) roots, plus direct IDs 1..3500 for future expansions
	local roots = { 946, 947 }
	for _, rootID in ipairs(roots) do
		local conts = C_Map.GetMapChildrenInfo(rootID, Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2, true)
		if conts then
			for _, cInfo in ipairs(conts) do
				addContinent(cInfo)
			end
		end
	end

	-- Fallback scan if root scan returned nothing or missed standalone continents/worlds
	for mapID = 1, 3500 do
		local info = C_Map.GetMapInfo(mapID)
		if info and info.mapType == (Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2) then
			addContinent(info)
		end
	end

	-- Catch standalone/custom zones (e.g. WoW Forever custom islands/zones like 2521 Zephras Isle, 2548 Riverglades, 2652 Shen'dralas)
	local orphanZones = {}
	for mapID = 1, 3500 do
		if not seenZones[mapID] and not seenContinents[mapID] then
			local info = C_Map.GetMapInfo(mapID)
			if info and info.mapID then
				local isZone = (not Enum or not Enum.UIMapType)
					or info.mapType == Enum.UIMapType.Zone
					or info.mapType == Enum.UIMapType.Micro
					or info.mapType == Enum.UIMapType.Orphan
				if isZone then
					-- Walk up parentMapID to see if it belongs to an already-registered continent
					local parentID = info.parentMapID
					local targetContIdx = nil
					local hops = 0
					while parentID and parentID > 0 and hops < 6 do
						hops = hops + 1
						local parentData = Map.HarvestedMapData[parentID]
						if parentData and parentData.cont and parentData.zone == 0 then
							targetContIdx = parentData.cont
							break
						end
						local pInfo = C_Map.GetMapInfo(parentID)
						parentID = pInfo and pInfo.parentMapID or nil
					end
					if targetContIdx and continentRecords[targetContIdx] then
						seenZones[mapID] = true
						local rec = continentRecords[targetContIdx]
						local zIdx = #rec.zones + 1
						rec.zones[zIdx] = mapID
						rec.zoneNames[zIdx] = info.name or ("Zone " .. mapID)
						local zw, zh = queryMapSize(mapID)
						Map.HarvestedMapData[mapID] = {
							mapName = info.name or ("Zone " .. mapID),
							cont = targetContIdx,
							zone = zIdx,
							width = zw,
							height = zh,
						}
					else
						table.insert(orphanZones, info)
					end
				end
			end
		end
	end

	if #orphanZones > 0 then
		local contIdx = #continentRecords + 1
		local zList = { [0] = 947 }
		local zNames = {}
		for _, zInfo in ipairs(orphanZones) do
			seenZones[zInfo.mapID] = true
			local zIdx = #zList + 1
			zList[zIdx] = zInfo.mapID
			zNames[zIdx] = zInfo.name or ("Zone " .. zInfo.mapID)
			local zw, zh = queryMapSize(zInfo.mapID)
			Map.HarvestedMapData[zInfo.mapID] = {
				mapName = zInfo.name or ("Zone " .. zInfo.mapID),
				cont = contIdx,
				zone = zIdx,
				width = zw,
				height = zh,
			}
		end
		Map.ContinentList[contIdx] = zList
		continentRecords[contIdx] = {
			mapID = 947,
			name = "Azeroth",
			zones = zList,
			zoneNames = zNames,
		}
	end
end

harvestModernMaps()

-- Provide legacy Map Global Polyfills for GatherZoneTokens, GatherStorage, GathererNodeSearch, GatherMapNotes
if not _G.GetMapContinents then
	_G.GetMapContinents = function()
		local res = {}
		for idx, rec in ipairs(continentRecords) do
			table.insert(res, rec.mapID)
			table.insert(res, rec.name)
		end
		return unpack(res)
	end
end

if not _G.GetMapZones then
	_G.GetMapZones = function(continentIndex)
		local rec = continentRecords[continentIndex]
		if not rec then return end
		local res = {}
		for zIdx, zMapID in ipairs(rec.zones) do
			table.insert(res, zMapID)
			table.insert(res, rec.zoneNames[zIdx] or ("Zone " .. zMapID))
		end
		return unpack(res)
	end
end

if not _G.GetContinentMaps then
	_G.GetContinentMaps = function()
		local t = {}
		for idx, rec in ipairs(continentRecords) do
			t[idx] = rec.mapID
		end
		return t
	end
end

if not _G.GetContinentMapInfo then
	_G.GetContinentMapInfo = function(id)
		return id
	end
end

if not _G.GetCurrentMapAreaID then
	_G.GetCurrentMapAreaID = function()
		if WorldMapFrame and WorldMapFrame.GetMapID then
			local mapID = WorldMapFrame:GetMapID()
			if mapID then return mapID end
		end
		if C_Map and C_Map.GetBestMapForUnit then
			return C_Map.GetBestMapForUnit("player")
		end
		return 0
	end
end

if not _G.GetMapInfo then
	_G.GetMapInfo = function()
		local mapID = _G.GetCurrentMapAreaID()
		if mapID and C_Map and C_Map.GetMapInfo then
			local info = C_Map.GetMapInfo(mapID)
			if info then
				local isMicro = (Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Micro) or false
				local w, h = queryMapSize(mapID)
				return info.name, w, h, isMicro
			end
		end
		return nil, 0, 0, false
	end
end

-- Gatherer.Map API Implementation
function Map:GetNumFloors(mapID)
	return 0
end

function Map:GetMapID(continent, zone)
	local cList = self.ContinentList[continent]
	if cList then
		return cList[zone or 0] or cList[0]
	end
	return continent
end

function Map:GetMapInfo(mapID, mapFloor)
	local w, h = queryMapSize(mapID)
	return mapID, mapID, w, h, 0, 0
end

function Map:GetUnitPosition(unit, noMapChange)
	unit = unit or "player"
	if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
		local mapID = C_Map.GetBestMapForUnit(unit) or C_Map.GetBestMapForUnit("player")
		if mapID then
			local pos = C_Map.GetPlayerMapPosition(mapID, unit)
			if pos then
				local x, y = pos:GetXY()
				if x and y and (x > 0 or y > 0) then
					if unit == "player" then
						self.LastPlayerPosition[1] = mapID
						self.LastPlayerPosition[2] = 0
						self.LastPlayerPosition[3] = x
						self.LastPlayerPosition[4] = y
					end
					return mapID, 0, x, y
				end
			end
		end
	end
	return nil
end

function Map:GetCurrentPlayerPosition()
	return self:GetUnitPosition("player", true)
end

function Map:TranslateWorldMapPosition(M, F, xPos, yPos, nM, nF)
	if not (M and nM and xPos and yPos) then return nil, nil end
	if M == nM then return xPos, yPos end

	if C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D then
		local ok1, instID, worldPos = pcall(C_Map.GetWorldPosFromMapPos, M, CreateVector2D(xPos, yPos))
		if ok1 and instID and worldPos then
			local ok2, _, mapPos = pcall(C_Map.GetMapPosFromWorldPos, instID, worldPos, nM)
			if ok2 and mapPos then
				local nx, ny = mapPos:GetXY()
				if nx and ny then
					return nx, ny
				end
			end
		end
	end

	if C_Map and type(C_Map.GetMapRectOnMap) == "function" then
		local ok, l, r, t, b = pcall(C_Map.GetMapRectOnMap, tonumber(M), tonumber(nM))
		if ok and l and r and t and b and r > l and b > t then
			return l + xPos * (r - l), t + yPos * (b - t)
		end
	end

	return nil, nil
end

function Map:ComputeDistance(m1, f1, x1, y1, m2, f2, x2, y2)
	if not (m1 and x1 and y1 and m2 and x2 and y2) then return nil end

	if m1 ~= m2 then
		x2, y2 = self:TranslateWorldMapPosition(m2, f2, x2, y2, m1, f1)
		if not (x2 and y2) then return nil end
	end

	local w, h = queryMapSize(m1)
	local xDist = (x2 - x1) * w
	local yDist = (y2 - y1) * h
	local dist = math.sqrt(xDist * xDist + yDist * yDist)
	return dist, xDist, yDist
end

function Map:Register_TargetMinimapChanged_Callback(func, id)
	if type(func) == "function" then
		self.TargetMinimapChanged_Callbacks[id or func] = func
	end
end

function Map:SetTargetMinimap(newMinimap)
	if not newMinimap or newMinimap == processingFrame:GetParent() then return end
	processingFrame:SetParent(newMinimap)
	for icon in pairs(self.MinimapIcons) do
		icon:SetParent(newMinimap)
	end
	for _, cb in pairs(self.TargetMinimapChanged_Callbacks) do
		pcall(cb, newMinimap)
	end
end

function Map:AssociateIcon(icon, group)
	if icon then
		self.IconAssociations[icon] = group
	end
end

function Map:GetDistanceToIcon(icon)
	local data = self.MinimapIcons[icon]
	if not data then return nil end
	local pm, pf, px, py = self:GetCurrentPlayerPosition()
	if not (pm and px and py) then return data.lastDist end
	local dist, xDist, yDist = self:ComputeDistance(pm, pf, px, py, data.mapID, data.mapFloor, data.x, data.y)
	if dist then
		data.lastDist = dist
		data.xDist = xDist
		data.yDist = yDist
	end
	return dist
end

-- Standard Minimap shapes table (supports ElvUI square/round minimap, SexyMap, BasicMinimap, Chinchilla, etc.)
local MinimapShapes = {
	["ROUND"]                 = { true,  true,  true,  true  },
	["SQUARE"]                = { false, false, false, false },
	["CORNER-TOPLEFT"]        = { true,  false, false, false },
	["CORNER-TOPRIGHT"]       = { false, false, true,  false },
	["CORNER-BOTTOMLEFT"]     = { false, true,  false, false },
	["CORNER-BOTTOMRIGHT"]    = { false, false, false, true  },
	["SIDE-LEFT"]             = { true,  true,  false, false },
	["SIDE-RIGHT"]            = { false, false, true,  true  },
	["SIDE-TOP"]              = { true,  false, true,  false },
	["SIDE-BOTTOM"]           = { false, true,  false, true  },
	["TRICORNER-TOPLEFT"]     = { true,  true,  true,  false },
	["TRICORNER-TOPRIGHT"]    = { true,  false, true,  true  },
	["TRICORNER-BOTTOMLEFT"]  = { true,  true,  false, true  },
	["TRICORNER-BOTTOMRIGHT"] = { false, true,  true,  true  },
}

local function isRotateMinimapEnabled()
	if C_Minimap and C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored() then
		return false
	end
	if C_CVar and C_CVar.GetCVar then
		return C_CVar.GetCVar("rotateMinimap") == "1"
	end
	return GetCVar and GetCVar("rotateMinimap") == "1" or false
end

function Map:GetMinimapRadius()
	return getMinimapRadius()
end

function Map:IsRotateMinimapEnabled()
	return isRotateMinimapEnabled()
end

local function positionMinimapIcon(icon, data, pm, pf, px, py, radius, rotateMinimap, facing)
	local targetMinimap = processingFrame:GetParent() or Minimap
	local dist, xDist, yDist = Map:ComputeDistance(pm, pf, px, py, data.mapID, data.mapFloor, data.x, data.y)
	if not dist then
		icon:Hide()
		return
	end
	data.lastDist = dist
	data.xDist = xDist
	data.yDist = yDist

	if rotateMinimap and facing then
		local sinF = math.sin(facing)
		local cosF = math.cos(facing)
		local rx = xDist * cosF - yDist * sinF
		local ry = xDist * sinF + yDist * cosF
		xDist, yDist = rx, ry
	end

	local mapW = targetMinimap:GetWidth() / 2
	local mapH = targetMinimap:GetHeight() / 2
	if mapW <= 0 or mapH <= 0 then
		icon:Hide()
		return
	end

	local diffX = xDist / radius
	local diffY = yDist / radius

	local shapeName = (_G.GetMinimapShape and _G.GetMinimapShape()) or "ROUND"
	local quadTable = MinimapShapes[shapeName] or MinimapShapes["ROUND"]
	local isRound = true
	if diffX ~= 0 or diffY ~= 0 then
		local q = (diffX < 0) and 1 or 3
		if diffY < 0 then
			isRound = quadTable[q]
		else
			isRound = quadTable[q + 1]
		end
	end

	local normDist
	if isRound then
		normDist = math.sqrt(diffX * diffX + diffY * diffY)
	else
		normDist = math.max(math.abs(diffX), math.abs(diffY))
	end

	if normDist > 0.94 then
		diffX = diffX * (0.94 / normDist)
		diffY = diffY * (0.94 / normDist)
		Map.IconsOnEdge[icon] = true
	else
		Map.IconsOnEdge[icon] = nil
	end

	local ix = diffX * mapW
	local iy = -diffY * mapH

	if icon:GetParent() ~= targetMinimap then
		icon:SetParent(targetMinimap)
	end
	local desiredLevel = (targetMinimap:GetFrameLevel() or 1) + 5
	if icon:GetFrameLevel() < desiredLevel then
		icon:SetFrameLevel(desiredLevel)
	end

	icon:ClearAllPoints()
	icon:SetPoint("CENTER", targetMinimap, "CENTER", ix, iy)
	icon:Show()
end

function Map:PlaceIconOnMinimap(icon, mapID, mapFloor, xPos, yPos)
	if not (icon and mapID and xPos and yPos) then return -1 end
	local pm, pf, px, py = self:GetCurrentPlayerPosition()
	if not (pm and px and py) then return -1 end

	local data = self.MinimapIcons[icon] or {}
	data.mapID = mapID
	data.mapFloor = mapFloor or 0
	data.x = xPos
	data.y = yPos
	self.MinimapIcons[icon] = data

	local radius = getMinimapRadius()
	local rotateMinimap = isRotateMinimapEnabled()
	local facing = rotateMinimap and GetPlayerFacing() or 0
	positionMinimapIcon(icon, data, pm, pf, px, py, radius, rotateMinimap, facing)
	return 0
end

function Map:RemoveIconFromMinimap(icon)
	if not icon then return end
	self.MinimapIcons[icon] = nil
	self.IconsOnEdge[icon] = nil
	icon:Hide()
end

function Map:GetCanvasScale(canvas)
	if WorldMapFrame and WorldMapFrame.ScrollContainer and type(WorldMapFrame.ScrollContainer.GetCanvasScale) == "function" then
		local ok, scale = pcall(WorldMapFrame.ScrollContainer.GetCanvasScale, WorldMapFrame.ScrollContainer)
		if ok and type(scale) == "number" and scale > 0 then
			return scale
		end
	end
	if _G.MapWiseAPI and MapWiseAPI.Map and type(MapWiseAPI.Map.scale) == "number" and MapWiseAPI.Map.scale > 0 then
		return MapWiseAPI.Map.scale
	end
	if canvas and type(canvas.GetScale) == "function" then
		local s = canvas:GetScale()
		if type(s) == "number" and s > 0 then
			return s
		end
	end
	return 1
end

function Map:PlaceIconOnWorldMap(worldMapFrame, icon, mapID, mapFloor, xPos, yPos)
	if not (icon and mapID and xPos and yPos) then return -1 end
	local canvas = (WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas())
		or worldMapFrame
		or _G.WorldMapButton
	if not canvas then return -1 end

	local curMapID = _G.GetCurrentMapAreaID()
	local projX, projY

	-- OpenMap integration: project via OpenMapAPI when OpenMap's stitched map is active
	local om = _G.OpenMapAPI
	local omStitched = om and type(om.IsStitched) == "function" and om.IsStitched()
	if omStitched and curMapID and type(om.WorldFromMap) == "function" and type(om.MapFromWorld) == "function" then
		local okW, u, v = pcall(om.WorldFromMap, mapID, xPos, yPos)
		if okW and type(u) == "number" and type(v) == "number" then
			local okM, px, py = pcall(om.MapFromWorld, curMapID, u, v)
			if okM and type(px) == "number" and type(py) == "number" then
				projX, projY = px, py
			end
		end
	end

	-- MapWise integration: use MapWiseAPI.Project when MapWise is active so Gatherer pins match both
	-- MapWise's calibrated terrain projection (aspect-fitted tiles) and continent/Azeroth views
	local mw = _G.MapWiseAPI
	if not (projX and projY) and mw and mw.Map and mw.Data and mw.Data.maps and mw.db and type(mw.Project) == "function" then
		local mwMapKey = mw.db.map
		local mwMap = mwMapKey and mw.Data.maps[mwMapKey]
		if mwMap then
			if mw.NativeMap and type(mw.NativeMap.CanvasSize) == "function" then
				local cw, ch = canvas:GetWidth(), canvas:GetHeight()
				if cw and ch and cw > 0 and ch > 0 then
					pcall(mw.NativeMap.CanvasSize, mw.NativeMap, cw, ch)
				end
			end
			local ok, px, py = pcall(mw.Project, mwMap, mapID, xPos, yPos, mw.Map.active == true)
			if ok and type(px) == "number" and type(py) == "number" then
				projX, projY = px, py
			elseif curMapID and curMapID ~= mapID then
				icon:Hide()
				return -1
			end
		end
	end

	if not (projX and projY) then
		if curMapID and curMapID ~= mapID then
			projX, projY = self:TranslateWorldMapPosition(mapID, mapFloor, xPos, yPos, curMapID, 0)
		else
			projX, projY = xPos, yPos
		end
	end

	if not (projX and projY) then
		icon:Hide()
		return -1
	end
	if not omStitched and (projX < 0 or projX > 1 or projY < 0 or projY > 1) then
		icon:Hide()
		return -1
	end

	local w = canvas:GetWidth()
	local h = canvas:GetHeight()
	if not (w and h and w > 0 and h > 0) then
		icon:Hide()
		return -1
	end

	-- Counteract canvas zoom scale so WorldMap pins remain crisp and constant size when zooming
	local canvasScale = self:GetCanvasScale(canvas)
	local pinScale = 1 / canvasScale
	icon:SetScale(pinScale)
	icon:ClearAllPoints()
	icon:SetPoint("CENTER", canvas, "TOPLEFT", (projX * w) / pinScale, -(projY * h) / pinScale)
	icon:Show()
	return 0
end

-- Periodic update for minimap pins & indoor/outdoor state
local updateElapsed = 0
processingFrame:SetScript("OnUpdate", function(self, elapsed)
	updateElapsed = updateElapsed + elapsed
	if updateElapsed < 0.05 then return end
	updateElapsed = 0

	Map.minimapOutside = not IsIndoors()
	Map.WorldMapVisible = (WorldMapFrame and WorldMapFrame:IsVisible()) and true or false

	if not next(Map.MinimapIcons) then return end
	local pm, pf, px, py = Map:GetCurrentPlayerPosition()
	if not (pm and px and py) then return end

	local radius = getMinimapRadius()
	local rotateMinimap = isRotateMinimapEnabled()
	local facing = rotateMinimap and GetPlayerFacing() or 0

	for icon, data in pairs(Map.MinimapIcons) do
		positionMinimapIcon(icon, data, pm, pf, px, py, radius, rotateMinimap, facing)
	end
end)

