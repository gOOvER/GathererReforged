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

local _tr = Gatherer.Locale.Tr
local _trC = Gatherer.Locale.TrClient
local _trL = Gatherer.Locale.TrLocale

-- reference to the Gatherer.Map mapping engine
local Map = Gatherer.Map

function Gatherer.MapNotes.Enable()
	Gatherer.Config.SetSetting("mainmap.enable", true)
	Gatherer.MapNotes.Update()
end

function Gatherer.MapNotes.Disable()
	Gatherer.Config.SetSetting("mainmap.enable", false)
	Gatherer.MapNotes.Update()
end

function Gatherer.MapNotes.ToggleDisplay()
	if ( Gatherer.Config.GetSetting("mainmap.enable") ) then
		Gatherer.MapNotes.Disable()
	else
		Gatherer.MapNotes.Enable()
	end
end

function Gatherer.MapNotes.Update()
	if ( Gatherer.Config.GetSetting("mainmap.enable") ) then
		GathererMapOverlayParent:Show()
		Gatherer.MapNotes.MapDraw()
	else
		GathererMapOverlayParent:Hide()
	end
	if Gatherer.MapNotes.UpdateWorldMapButton then
		Gatherer.MapNotes.UpdateWorldMapButton()
	end
end

-- Dynamically ensure GathererMapOverlayParent & child frames sit ABOVE Blizzard MapExplorationPinTemplate,
-- Leatrix_Maps reveal overlays, and MapWise's ForeverAtlasTerrainLayer (MapWiseAPI.Map.view / pinLevel)
function Gatherer.MapNotes.UpdateOverlayLayering()
	if not GathererMapOverlayParent then return end
	local canvas = (WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas())
		or _G.WorldMapButton
	if not canvas then return end

	if GathererMapOverlayParent:GetParent() ~= canvas then
		GathererMapOverlayParent:SetParent(canvas)
		GathererMapOverlayParent:ClearAllPoints()
		GathererMapOverlayParent:SetAllPoints(canvas)
	end

	local cw, ch = canvas:GetWidth(), canvas:GetHeight()
	if cw and ch and cw > 0 and ch > 0 then
		GathererMapOverlayParent:SetSize(cw, ch)
	end

	local baseLevel = (canvas:GetFrameLevel() or 1) + 50
	if WorldMapFrame and type(WorldMapFrame.GetPinFrameLevelsManager) == "function" then
		local ok, manager = pcall(WorldMapFrame.GetPinFrameLevelsManager, WorldMapFrame)
		if ok and manager and type(manager.GetValidFrameLevel) == "function" then
			local ok1, poiLevel = pcall(manager.GetValidFrameLevel, manager, "PIN_FRAME_LEVEL_AREA_POI")
			if ok1 and type(poiLevel) == "number" then
				baseLevel = math.max(baseLevel, poiLevel + 10)
			end
			local ok2, expLevel = pcall(manager.GetValidFrameLevel, manager, "PIN_FRAME_LEVEL_MAP_EXPLORATION")
			if ok2 and type(expLevel) == "number" then
				baseLevel = math.max(baseLevel, expLevel + 20)
			end
		end
	end

	if _G.ForeverAtlasTerrainLayer and _G.ForeverAtlasTerrainLayer.GetFrameLevel then
		local ok, mwViewLevel = pcall(_G.ForeverAtlasTerrainLayer.GetFrameLevel, _G.ForeverAtlasTerrainLayer)
		if ok and type(mwViewLevel) == "number" then
			baseLevel = math.max(baseLevel, mwViewLevel + 10)
		end
	end

	if _G.MapWiseAPI and MapWiseAPI.Map and type(MapWiseAPI.Map.pinLevel) == "number" then
		baseLevel = math.max(baseLevel, MapWiseAPI.Map.pinLevel + 5)
	end

	if _G.OpenMapAPI and type(_G.OpenMapAPI.ArtTopLevel) == "function" then
		local ok, omArtTop = pcall(_G.OpenMapAPI.ArtTopLevel)
		if ok and type(omArtTop) == "number" then
			baseLevel = math.max(baseLevel, omArtTop + 10)
		end
	end

	baseLevel = math.max(baseLevel, 2100)

	if GathererMapOverlayParent:GetFrameLevel() ~= baseLevel then
		GathererMapOverlayParent:SetFrameLevel(baseLevel)
	end

	for _, overlayFrame in ipairs(GathererMapOverlayParent) do
		if overlayFrame:GetFrameLevel() ~= baseLevel + 1 then
			overlayFrame:SetFrameLevel(baseLevel + 1)
		end
		if cw and ch and cw > 0 and ch > 0 then
			overlayFrame:SetSize(cw, ch)
		end
		for _, noteBtn in ipairs(overlayFrame) do
			if noteBtn:GetFrameLevel() ~= baseLevel + 2 then
				noteBtn:SetFrameLevel(baseLevel + 2)
			end
		end
	end
end

-- WorldMap Toggle Button (automatically detected by MapWise's "Addons" toolbar menu and usable on all WorldMap addons)
function Gatherer.MapNotes.UpdateWorldMapButton()
	local btn = Gatherer.MapNotes.WorldMapButton
	if not btn then return end
	local enabled = Gatherer.Config.GetSetting("mainmap.enable")
	if btn.Icon then
		btn.Icon:SetDesaturated(not enabled)
		btn.Icon:SetAlpha(enabled and 1.0 or 0.5)
	end
end

function Gatherer.MapNotes.CreateWorldMapButton()
	if Gatherer.MapNotes.WorldMapButton or not WorldMapFrame then return end
	local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
	local btn = CreateFrame("Button", "GathererReforgedWorldMapButton", parent)
	btn:SetSize(28, 28)
	btn:SetToplevel(true)
	btn:SetFrameStrata("HIGH")
	btn:SetFrameLevel((parent:GetFrameLevel() or 10) + 50)
	btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -6)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(24, 24)
	bg:SetPoint("CENTER", 0, 0)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	btn.Background = bg

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER", 0, 0)
	-- Use addon path so MapWise AddonMenu:Owner() recognizes "GathererReforged" via texture folder path
	local ok = pcall(icon.SetTexture, icon, "Interface\\AddOns\\GathererReforged\\Skin\\GatherOrb")
	if not ok or not icon:GetTexture() then
		icon:SetTexture(133939)
	end
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	btn.Icon = icon

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetSize(48, 48)
	border:SetPoint("TOPLEFT", -2, 2)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	btn.Border = border

	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

	btn:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			if IsShiftKeyDown() or IsControlKeyDown() then
				Gatherer.Config.ToggleOptions()
			else
				Gatherer.Report.Toggle()
			end
		else
			Gatherer.MapNotes.ToggleDisplay()
		end
		Gatherer.MapNotes.UpdateWorldMapButton()
	end)

	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:SetFrameStrata("TOOLTIP")
		GameTooltip:ClearLines()
		Gatherer.Locale.SECTION_HIGHLIGHT_CODE = "|cff1fb3ff"
		local ver = tostring((Gatherer.Var and Gatherer.Var.Version) or "1.0.0")
		GameTooltip:AddDoubleLine("|T133939:16:16:0:0:64:64:5:59:5:59|t  |cffffd200Gatherer Reforged|r", "|cff00ff96v" .. ver .. "|r")
		GameTooltip:AddLine(" ")
		local enabled = Gatherer.Config.GetSetting("mainmap.enable")
		GameTooltip:AddDoubleLine("|cffb0b8c4" .. _tr("MAP_NOTES_SHOW") .. ":|r", enabled and ("|cff00ff96" .. _tr("ENABLE") .. "|r") or ("|cffff5050" .. _tr("DISABLE") .. "|r"))
		GameTooltip:AddLine(" ")
		for _, rawLine in ipairs({
			_tr("MINIICON_ACTIONS_CLICK"),
			_tr("MINIICON_ACTIONS_RIGHT_CLICK"),
			_tr("MINIICON_ACTIONS_SHIFT_RIGHT_CLICK"),
		}) do
			local left, right = rawLine:match("^(.-|r):?%s*(.+)$")
			if left and right then
				GameTooltip:AddDoubleLine(left:gsub(":$", ""), "   " .. right:gsub("^:%s*", ""), 0.12, 0.70, 1.0, 0.90, 0.93, 0.98)
			else
				GameTooltip:AddLine(rawLine, 0.90, 0.93, 0.98)
			end
		end
		GameTooltip:Show()
	end)

	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	Gatherer.MapNotes.WorldMapButton = btn
	Gatherer.MapNotes.UpdateWorldMapButton()

	-- If MapWise AddonMenu is already initialized, mark it dirty so it picks up our button immediately
	if _G.MapWiseAPI and MapWiseAPI.AddonMenu then
		MapWiseAPI.AddonMenu.dirty = true
	end
end

if ( WorldMapFrame and WorldMapFrame.UIElementsFrame and WorldMapFrame.UIElementsFrame.TrackingOptionsButton and WorldMapFrame.UIElementsFrame.TrackingOptionsButton.DropDown ) then
	hooksecurefunc(WorldMapFrame.UIElementsFrame.TrackingOptionsButton.DropDown, "initialize", function()
		UnitPopup_AddDropDownButton({}, UnitPopupButtons["SUBSECTION_SEPARATOR"], "SUBSECTION_SEPARATOR", UIDROPDOWNMENU_MENU_LEVEL);
		local info = {}
		info.text = _tr("BINDING_HEADER_GATHERER")..": ".._tr("MAP_NOTES_SHOW")
		info.value = "gatherer.mainmap.enable"
		info.func = Gatherer.MapNotes.ToggleDisplay
		info.checked = Gatherer.Config.GetSetting("mainmap.enable")
		info.isNotRadio = true;
		info.keepShownOnClick = 1
		UIDropDownMenu_AddButton(info)
	end)
elseif ( Menu and Menu.ModifyMenu ) then
	pcall(function()
		Menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", function(owner, rootDescription, contextData)
			rootDescription:CreateDivider()
			rootDescription:CreateCheckbox(
				_tr("BINDING_HEADER_GATHERER")..": ".._tr("MAP_NOTES_SHOW"),
				function() return Gatherer.Config.GetSetting("mainmap.enable") end,
				function() Gatherer.MapNotes.ToggleDisplay() end
			)
		end)
	end)
end

-- Hook MapWise, ElvUI, Leatrix_Maps, and native MapCanvas events
local mapWiseHooked = false
local function hookMapAddons()
	if not mapWiseHooked and _G.MapWiseAPI and MapWiseAPI.Map then
		mapWiseHooked = true
		if type(MapWiseAPI.Map.Render) == "function" then
			hooksecurefunc(MapWiseAPI.Map, "Render", function()
				Gatherer.MapNotes.UpdateOverlayLayering()
				Gatherer.MapNotes.MapDraw()
			end)
		end
		if type(MapWiseAPI.Map.Pan) == "function" then
			hooksecurefunc(MapWiseAPI.Map, "Pan", function()
				Gatherer.MapNotes.UpdateOverlayLayering()
				Gatherer.MapNotes.MapDraw()
			end)
		end
		if type(MapWiseAPI.Map.Layers) == "function" then
			hooksecurefunc(MapWiseAPI.Map, "Layers", function()
				Gatherer.MapNotes.UpdateOverlayLayering()
			end)
		end
	end
	Gatherer.MapNotes.CreateWorldMapButton()
end

if ( WorldMapFrame ) then
	if ( WorldMapFrame.OnMapChanged ) then
		hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
			Gatherer.MapNotes.MapDraw()
		end)
	end
	if ( WorldMapFrame.SetMapID ) then
		hooksecurefunc(WorldMapFrame, "SetMapID", function()
			Gatherer.MapNotes.MapDraw()
		end)
	end
	if ( WorldMapFrame.Maximize ) then
		hooksecurefunc(WorldMapFrame, "Maximize", function()
			Gatherer.MapNotes.MapDraw()
		end)
	end
	if ( WorldMapFrame.Minimize ) then
		hooksecurefunc(WorldMapFrame, "Minimize", function()
			Gatherer.MapNotes.MapDraw()
		end)
	end
	WorldMapFrame:HookScript("OnShow", function()
		hookMapAddons()
		Gatherer.MapNotes.UpdateWorldMapButton()
		Gatherer.MapNotes.MapDraw()
	end)
	WorldMapFrame:HookScript("OnSizeChanged", function()
		Gatherer.MapNotes.MapDraw()
	end)
	if WorldMapFrame.OnCanvasScaleChanged then
		hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", function()
			Gatherer.MapNotes.MapDraw()
		end)
	end
	if WorldMapFrame.ScrollContainer then
		if WorldMapFrame.ScrollContainer.OnCanvasSizeChanged then
			hooksecurefunc(WorldMapFrame.ScrollContainer, "OnCanvasSizeChanged", function()
				Gatherer.MapNotes.MapDraw()
			end)
		end
		if WorldMapFrame.ScrollContainer.OnCanvasScaleChanged then
			hooksecurefunc(WorldMapFrame.ScrollContainer, "OnCanvasScaleChanged", function()
				Gatherer.MapNotes.MapDraw()
			end)
		end
		WorldMapFrame.ScrollContainer:HookScript("OnSizeChanged", function()
			Gatherer.MapNotes.MapDraw()
		end)
	end
end

if EventRegistry and type(EventRegistry.RegisterCallback) == "function" then
	EventRegistry:RegisterCallback("MapCanvas.MapSet", function()
		Gatherer.MapNotes.MapDraw()
	end, Gatherer.MapNotes)
end

local addonHookFrame = CreateFrame("Frame")
addonHookFrame:RegisterEvent("PLAYER_LOGIN")
addonHookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
addonHookFrame:RegisterEvent("ADDON_LOADED")
addonHookFrame:SetScript("OnEvent", function(_, event, arg1)
	hookMapAddons()
	if event == "PLAYER_ENTERING_WORLD" or arg1 == "MapWise" or arg1 == "ElvUI" or arg1 == "Leatrix_Maps" then
		if Gatherer.ElvUI and Gatherer.ElvUI.SkinFrames then
			Gatherer.ElvUI.SkinFrames()
		end
		if WorldMapFrame and WorldMapFrame:IsShown() then
			Gatherer.MapNotes.MapDraw()
		end
	end
end)


function Gatherer.MapNotes.GetNoteObject( noteNumber )
	local button = _G["GatherMain"..noteNumber]
	if not ( button ) then
		local overlayFrameNumber = math.ceil(noteNumber / 100)
		local overlayFrame = GathererMapOverlayParent[overlayFrameNumber]
		if not ( overlayFrame ) then
			overlayFrame = CreateFrame("Frame", "GathererMapOverlayFrame"..overlayFrameNumber, GathererMapOverlayParent, "GathererMapOverlayTemplate")
			overlayFrame:SetFrameLevel((GathererMapOverlayParent:GetFrameLevel() or 2100) + 1)
			GathererMapOverlayParent[overlayFrameNumber] = overlayFrame
		end
		button = CreateFrame("Button" ,"GatherMain"..noteNumber, overlayFrame, "GatherMainTemplate")
		button:SetID(noteNumber)
		button:SetFrameLevel((overlayFrame:GetFrameLevel() or 2101) + 1)
		overlayFrame[(noteNumber-1) % 100 + 1] = button
		Gatherer.Util.Debug("create id "..noteNumber.." frame ".. overlayFrameNumber)
	end
	return button
end

local function isContinentOrWorldMap(uiMapID)
	if not uiMapID then return false end
	if uiMapID == 946 or uiMapID == 947 or uiMapID == 1414 or uiMapID == 1415 then
		return true
	end
	if C_Map and C_Map.GetMapInfo and Enum and Enum.UIMapType then
		local info = C_Map.GetMapInfo(uiMapID)
		if info and (info.mapType == Enum.UIMapType.Continent or info.mapType == Enum.UIMapType.World or info.mapType == Enum.UIMapType.Cosmic) then
			return true
		end
	end
	return false
end

function Gatherer.MapNotes.MapDraw()
	local GathererMapOverlayParent = GathererMapOverlayParent
	if not ( GathererMapOverlayParent and GathererMapOverlayParent:IsVisible() ) then
		return
	end
	Gatherer.MapNotes.UpdateOverlayLayering()

	local setting = Gatherer.Config.GetSetting
	local maxNotes = setting("mainmap.count", 600)
	local noteCount = 0

	-- prevent the function from running twice at the same time.
	if (Gatherer.Var.UpdateWorldMap == 0 ) then return; end
	Gatherer.Var.UpdateWorldMap = 0

	local GetNodeInfo = Gatherer.Storage.GetNodeInfo
	local GetNodeGatherNames = Gatherer.Storage.GetNodeGatherNames
	local _, _, _, isMicroDungeon = GetMapInfo()
	local opacity = setting("mainmap.opacity", 80) / 100
	local iconsize = setting("mainmap.iconsize", 16)
	local tooltip = setting("mainmap.tooltip.enable")

	local function drawZoneNodes(zoneToken, nodeMapID, nodeMapFloor)
		if not (zoneToken and nodeMapID and Gatherer.Storage.HasDataOnZone(zoneToken)) then
			return
		end
		for _, gatherType in pairs(Gatherer.Constants.SupportedGatherTypes) do
			for index, xPos, yPos in Gatherer.Storage.ZoneGatherNodes(zoneToken, gatherType) do
				local displayNode = false
				for _, gatherID, count in GetNodeGatherNames(zoneToken, gatherType, index) do
					if ( Gatherer.Config.DisplayFilter_MainMap(gatherID) ) then
						displayNode = true
						break
					end
				end
				if ( displayNode and isMicroDungeon ) then
					local _, _, indoors = GetNodeInfo(zoneToken, gatherType, index)
					displayNode = indoors
				end
				if ( displayNode ) then
					if ( noteCount < maxNotes ) then
						local nextIdx = noteCount + 1
						local mainNote = Gatherer.MapNotes.GetNoteObject(nextIdx)
						local placed = Map:PlaceIconOnWorldMap(WorldMapButton, mainNote, nodeMapID, nodeMapFloor, xPos, yPos)
						if placed == 0 then
							noteCount = nextIdx
							mainNote:SetAlpha(opacity)

							local texture, trimTexture = Gatherer.Util.GetNodeTexture(zoneToken, gatherType, index)
							local noteTexture = _G[mainNote:GetName().."Texture"]
							noteTexture:SetTexture(texture)
							if ( trimTexture ) then
								noteTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
							else
								noteTexture:SetTexCoord(0, 1, 0, 1)
							end

							mainNote:SetWidth(iconsize)
							mainNote:SetHeight(iconsize)

							mainNote.mapID = nodeMapID
							mainNote.zoneToken = zoneToken
							mainNote.index = index
							mainNote.gType = gatherType
							mainNote.xPos = xPos
							mainNote.yPos = yPos

							if (tooltip and not mainNote:IsMouseEnabled()) then
								mainNote:EnableMouse(true)
							elseif (not tooltip and mainNote:IsMouseEnabled()) then
								mainNote:EnableMouse(false)
							end
						else
							mainNote:Hide()
						end
					else -- reached note limit
						return
					end
				end
			end
		end
	end

	local curAreaID = GetCurrentMapAreaID()
	local curZoneToken = Gatherer.ZoneTokens.GetZoneToken(curAreaID)
	local mapID, mapFloor = Gatherer.ZoneTokens.GetZoneMapIDAndFloor(curZoneToken)
	if mapID then
		drawZoneNodes(curZoneToken, mapID, mapFloor)
	end

	-- When viewing a Continent/World map or OpenMap's stitched world view,
	-- also project nodes from gathered child/adjacent zones onto the canvas!
	local om = _G.OpenMapAPI
	local omStitched = om and type(om.IsStitched) == "function" and om.IsStitched()
	if (isContinentOrWorldMap(curAreaID) or omStitched) and noteCount < maxNotes then
		for _, zoneToken in Gatherer.Storage.GetAreaIndices() do
			if zoneToken ~= curZoneToken then
				local zMapID, zMapFloor = Gatherer.ZoneTokens.GetZoneMapIDAndFloor(zoneToken)
				if zMapID then
					local shouldDrawZone = true
					if omStitched and type(om.WorldFromMap) == "function" then
						local okW, u, v = pcall(om.WorldFromMap, zMapID, 0.5, 0.5)
						shouldDrawZone = okW and type(u) == "number" and type(v) == "number"
					end
					if shouldDrawZone then
						drawZoneNodes(zoneToken, zMapID, zMapFloor)
						if noteCount >= maxNotes then
							break
						end
					end
				end
			end
		end
	end
	
	local numUsedOverlays = math.ceil(noteCount / 100)
	local partialOverlay = GathererMapOverlayParent[numUsedOverlays]
	if ( partialOverlay ) then
		for i = (noteCount - ((numUsedOverlays - 1) * 100) + 1), 100 do
			local note = partialOverlay[i]
			if not ( note ) then
				break
			end
			note:Hide()
		end
	end
	for i, overlay in ipairs(GathererMapOverlayParent) do
		if ( i <= numUsedOverlays ) then
			overlay:Show()
		else
			overlay:Hide()
		end
	end
	
	Gatherer.Var.UpdateWorldMap = -1
end

function Gatherer.MapNotes.MapOverlayFrame_OnHide( frame )
	for _, childFrame in ipairs(frame) do
		childFrame:Hide()
	end
end

-- Click handler on WorldMap pins: Shift+RightClick or Alt+LeftClick sets a TomTom or Blizzard waypoint;
-- normal clicks pass through to the WorldMap canvas
function Gatherer.MapNotes.MapNoteOnClick(frame, button)
	if frame and frame.mapID and frame.xPos and frame.yPos and (IsShiftKeyDown() or IsAltKeyDown()) and (button == "RightButton" or button == "LeftButton") then
		local zone = frame.zoneToken or Gatherer.ZoneTokens.GetZoneToken(frame.mapID)
		local title = "Gatherer Reforged"
		for _, gatherID in Gatherer.Storage.GetNodeGatherNames(zone, frame.gType, frame.index) do
			title = Gatherer.Util.GetNodeName(gatherID) or title
			break
		end
		if _G.TomTom and type(_G.TomTom.AddWaypoint) == "function" then
			pcall(_G.TomTom.AddWaypoint, _G.TomTom, frame.mapID, frame.xPos, frame.yPos, {
				title = title,
				persistent = false,
				minimap = true,
				world = true,
			})
			return
		elseif C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
			local ok, canSet = pcall(C_Map.CanSetUserWaypointOnMap, frame.mapID)
			if ok and canSet then
				pcall(function()
					local pt = UiMapPoint.CreateFromCoordinates(frame.mapID, frame.xPos, frame.yPos)
					C_Map.SetUserWaypoint(pt)
					if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
						C_SuperTrack.SetSuperTrackedUserWaypoint(true)
					end
				end)
				return
			end
		end
	end

	if ( WorldMapButton and WorldMapButton.GetScript ) then
		local func = WorldMapButton:GetScript("OnMouseUp")
		if ( func ) then
			func(WorldMapButton, button)
		end
	end
end

function Gatherer.MapNotes.MapNoteOnEnter(frame)
	local setting = Gatherer.Config.GetSetting
	
	local enabled = setting("mainmap.tooltip.enable")
	if (not enabled) then 
		return
	end
	
	local showcount = setting("mainmap.tooltip.count")
	local showsource = setting("mainmap.tooltip.source")
	local showseen = setting("mainmap.tooltip.seen")
	local showrate = setting("mainmap.tooltip.rate")
	
	local cont = frame.continent
	local zone = frame.zoneToken or Gatherer.ZoneTokens.GetZoneToken(frame.mapID)
	local index = frame.index
	local gType = frame.gType
	local inspected = Gatherer.Storage.GetNodeInspected(zone, gType, index)
	
	local numTooltips = 0
	for id, gatherID, count, harvested, who in Gatherer.Storage.GetNodeGatherNames(zone, gType, index) do
		local tooltip = Gatherer.Tooltip.GetTooltip(id)
		tooltip:ClearLines()
		tooltip:SetParent(UIParent)
		tooltip:SetFrameStrata("TOOLTIP")
		tooltip:SetToplevel(true)
		tooltip:SetFrameLevel(math.max((frame:GetFrameLevel() or 2100) + 20, 3000))
		if ( id == 1 ) then
			tooltip:SetOwner(frame, "ANCHOR_BOTTOMLEFT")
		else
			tooltip:SetOwner(frame, "ANCHOR_PRESERVE")
			tooltip:SetPoint("TOPLEFT", Gatherer.Tooltip.GetTooltip(id - 1),"BOTTOMLEFT")
		end
		
		local name = Gatherer.Util.GetNodeName(gatherID)
		local last = inspected or harvested
		
		tooltip:AddLine(name)
		if (count > 0 and showcount) then
			tooltip:AddLine(_tr("NOTE_COUNT", count))
		end
		if (who and showsource) then
			if (who == "REQUIRE") then
				tooltip:AddLine(_tr("NOTE_UNSKILLED"))
			elseif (who == "IMPORTED") then
				tooltip:AddLine(_tr("NOTE_IMPORTED"))
			else
				tooltip:AddLine(_tr("NOTE_SOURCE", who:gsub(",", ", ")))
			end
		end
		if (last and last > 0 and showseen) then
			tooltip:AddLine(_tr("NOTE_LASTVISITED", Gatherer.Util.SecondsToTime(time()-last)))
		end
		
		if ( showrate ) then
			local num = Gatherer.Config.GetSetting("mainmap.tooltip.rate.num")
			if ( gType ~= "OPEN" and gatherID ~= 190175 ) then
				zone = nil
			end
			Gatherer.Tooltip.AddDropRates(tooltip, gatherID, zone, num)
		end
		tooltip:Show()
		numTooltips = id
	end
	Gatherer.Tooltip.SetClamps(numTooltips)
end
