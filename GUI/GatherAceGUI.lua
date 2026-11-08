--[[
	Gatherer Reforged - Modern Ace3 GUI & Options System (AceConfig-3.0 / AceGUI-3.0)
	Provides a modern, skinnable Ace3 interface and registers Gatherer Reforged
	directly in the Blizzard Options panel.

	Author: gOOvER
	License: GNU General Public License v3.0 (GPL-3.0)
]]

local AceConfig = LibStub and LibStub("AceConfig-3.0", true)
local AceConfigDialog = LibStub and LibStub("AceConfigDialog-3.0", true)
local AceConfigRegistry = LibStub and LibStub("AceConfigRegistry-3.0", true)
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)

if not (AceConfig and AceConfigDialog and AceConfigRegistry and AceGUI) then
	return
end

local _tr = Gatherer.Locale.Tr
local _trC = Gatherer.Locale.TrClient
local _trL = Gatherer.Locale.TrLocale
local refreshCustomConfigFrame

local GetSetting = function(key, default)
	return Gatherer.Config.GetSetting(key, default)
end

local SetSetting = function(key, value)
	Gatherer.Config.SetSetting(key, value)
	AceConfigRegistry:NotifyChange("GathererReforged")
	if refreshCustomConfigFrame then
		refreshCustomConfigFrame()
	end
end

-- Formats locale strings containing %d / %0.1f / %% with the current setting value
local function sliderLabel(localeKey, settingKey, defaultVal)
	return function()
		local val = tonumber(GetSetting(settingKey, defaultVal)) or defaultVal or 0
		local raw = _trL(localeKey)
		if type(raw) == "string" and raw:find("%%") then
			local ok, formatted = pcall(string.format, raw, val)
			if ok and formatted then
				return formatted
			end
		end
		return raw
	end
end

-- Helper for RGB / RGBA string settings ("r,g,b" or "r,g,b,a")
local function getColorRGB(key, defR, defG, defB)
	local r, g, b = GetSetting(key)
	if type(r) == "string" and not g then
		r, g, b = strsplit(",", r)
	end
	return tonumber(r) or defR or 1, tonumber(g) or defG or 1, tonumber(b) or defB or 1
end

local function setColorRGB(key, r, g, b)
	SetSetting(key, string.format("%.2f,%.2f,%.2f", r or 1, g or 1, b or 1))
end

local function getColorRGBA(key, defR, defG, defB, defA)
	local raw = tostring(GetSetting(key) or "")
	local r, g, b, a = strsplit(",", raw)
	return tonumber(r) or defR or 1, tonumber(g) or defG or 1, tonumber(b) or defB or 1, tonumber(a) or defA or 1
end

local function setColorRGBA(key, r, g, b, a)
	SetSetting(key, string.format("%.2f, %.2f, %.2f, %.2f", r or 1, g or 1, b or 1, a or 1))
end

-- Build node filter arguments dynamically for MINE, HERB, OPEN
local function buildNodeFilterGroup(gTypeLower, titleKey, filterLabelKey)
	local args = {
		header = {
			type = "header",
			name = _trL(titleKey),
			order = 1,
		},
		desc = {
			type = "description",
			name = _trL(filterLabelKey),
			order = 2,
		},
		enableAll = {
			type = "execute",
			name = _trL("ALL") .. " (+)",
			width = "normal",
			order = 3,
			func = function()
				for _, objid in pairs(Gatherer.Nodes.Names) do
					local objType = Gatherer.Nodes.Objects[objid]
					if objType and objType:lower() == gTypeLower then
						Gatherer.Config.SetSetting("show." .. gTypeLower .. "." .. objid, true)
					end
				end
				AceConfigRegistry:NotifyChange("GathererReforged")
			end,
		},
		disableAll = {
			type = "execute",
			name = _trL("DISABLE") .. " (-)",
			width = "normal",
			order = 4,
			func = function()
				for _, objid in pairs(Gatherer.Nodes.Names) do
					local objType = Gatherer.Nodes.Objects[objid]
					if objType and objType:lower() == gTypeLower then
						Gatherer.Config.SetSetting("show." .. gTypeLower .. "." .. objid, false)
					end
				end
				AceConfigRegistry:NotifyChange("GathererReforged")
			end,
		},
		spacer = {
			type = "header",
			name = "",
			order = 5,
		},
	}

	local entries = {}
	local seen = {}
	for _, objid in pairs(Gatherer.Nodes.Names) do
		local objType = Gatherer.Nodes.Objects[objid]
		if objType and objType:lower() == gTypeLower and not seen[objid] then
			seen[objid] = true
			local name = Gatherer.Util.GetNodeName(objid)
			local cat = Gatherer.Categories.ObjectCategories[objid]
			local skill = cat and Gatherer.Constants.SkillLevel[cat] or nil
			table.insert(entries, { id = objid, name = name, skill = skill })
		end
	end

	table.sort(entries, function(a, b)
		if a.skill and b.skill and a.skill ~= b.skill then
			return a.skill < b.skill
		elseif a.skill and not b.skill then
			return true
		elseif not a.skill and b.skill then
			return false
		end
		return tostring(a.name) < tostring(b.name)
	end)

	for idx, item in ipairs(entries) do
		local settingKey = "show." .. gTypeLower .. "." .. item.id
		local label = item.skill and string.format("%s |cff888888[%d]|r", item.name, item.skill) or item.name
		local tex = Gatherer.Util.GetGatherTexture(item.id)
		args["node_" .. item.id] = {
			type = "toggle",
			name = label,
			image = tex,
			width = "normal",
			order = 10 + idx,
			get = function() return GetSetting(settingKey) end,
			set = function(_, val) SetSetting(settingKey, val) end,
		}
	end

	return args
end

local newProfileName = ""
local selectedBlacklistPlayer = nil
local newBlacklistPlayer = ""

local function buildOptionsTable()
	local options = {
		type = "group",
		name = "Gatherer Reforged " .. tostring(Gatherer.Var.Version or "1.0.0"),
		childGroups = "tab",
		args = {
			openReport = {
				type = "execute",
				name = _tr("LABEL_REPORT"),
				desc = _tr("LABEL_REPORT"),
				order = 1,
				width = "normal",
				func = function()
					AceConfigDialog:Close("GathererReforged")
					Gatherer.Report.Show()
				end,
			},
			openSearch = {
				type = "execute",
				name = _tr("LABEL_DENSITY_REPORT"),
				desc = _tr("LABEL_DENSITY_REPORT"),
				order = 2,
				width = "normal",
				func = function()
					AceConfigDialog:Close("GathererReforged")
					Gatherer.NodeSearch.Show()
				end,
			},

			----------------------------------------------------------------------
			-- 1. General
			----------------------------------------------------------------------
			general = {
				type = "group",
				name = _trL("CONFIG_SECTION_GENERAL"),
				order = 10,
				args = {
					worldmapGroup = {
						type = "group",
						inline = true,
						name = _trL("CONFIG_GENERAL_WORLDMAP_LABEL"),
						order = 1,
						args = {
							enable = {
								type = "toggle",
								name = _trL("CONFIG_WORLDMAP_ENABLE"),
								width = "full",
								order = 1,
								get = function() return GetSetting("mainmap.enable") end,
								set = function(_, v) SetSetting("mainmap.enable", v) end,
							},
							count = {
								type = "range",
								name = sliderLabel("CONFIG_WORLDMAP_MAX_NOTES", "mainmap.count", 600),
								min = 10, max = 2500, step = 10,
								order = 2,
								get = function() return tonumber(GetSetting("mainmap.count", 600)) or 600 end,
								set = function(_, v) SetSetting("mainmap.count", v) end,
							},
							opacity = {
								type = "range",
								name = sliderLabel("CONFIG_WORLDMAP_NOTE_OPACITY", "mainmap.opacity", 80),
								min = 10, max = 100, step = 2,
								order = 3,
								get = function() return tonumber(GetSetting("mainmap.opacity", 80)) or 80 end,
								set = function(_, v) SetSetting("mainmap.opacity", v) end,
							},
							iconsize = {
								type = "range",
								name = sliderLabel("CONFIG_WORLDMAP_ICON_SIZE", "mainmap.iconsize", 16),
								min = 4, max = 64, step = 1,
								order = 4,
								get = function() return tonumber(GetSetting("mainmap.iconsize", 16)) or 16 end,
								set = function(_, v) SetSetting("mainmap.iconsize", v) end,
							},
							tooltipEnable = {
								type = "toggle",
								name = _trL("CONFIG_TOOLTIP_ENABLE"),
								width = "full",
								order = 5,
								get = function() return GetSetting("mainmap.tooltip.enable") end,
								set = function(_, v) SetSetting("mainmap.tooltip.enable", v) end,
							},
							tooltipCount = {
								type = "toggle",
								name = _trL("CONFIG_TOOLTIP_COUNTS"),
								order = 6,
								get = function() return GetSetting("mainmap.tooltip.count") end,
								set = function(_, v) SetSetting("mainmap.tooltip.count", v) end,
							},
							tooltipSource = {
								type = "toggle",
								name = _trL("CONFIG_TOOLTIP_SOURCE"),
								order = 7,
								get = function() return GetSetting("mainmap.tooltip.source") end,
								set = function(_, v) SetSetting("mainmap.tooltip.source", v) end,
							},
							tooltipSeen = {
								type = "toggle",
								name = _trL("CONFIG_TOOLTIP_LAST_SEEN"),
								order = 8,
								get = function() return GetSetting("mainmap.tooltip.seen") end,
								set = function(_, v) SetSetting("mainmap.tooltip.seen", v) end,
							},
							tooltipRate = {
								type = "toggle",
								name = _trL("CONFIG_TOOLTIP_DROP_RATES"),
								order = 9,
								get = function() return GetSetting("mainmap.tooltip.rate") end,
								set = function(_, v) SetSetting("mainmap.tooltip.rate", v) end,
							},
						},
					},
					miniiconGroup = {
						type = "group",
						inline = true,
						name = _trL("CONFIG_GENERAL_MINIICON_LABEL"),
						order = 2,
						args = {
							enable = {
								type = "toggle",
								name = _trL("CONFIG_MINIICON_ENABLE"),
								order = 1,
								get = function() return GetSetting("miniicon.enable") end,
								set = function(_, v) SetSetting("miniicon.enable", v) end,
							},
							angle = {
								type = "range",
								name = sliderLabel("CONFIG_MINIICON_ANGLE", "miniicon.angle", 220),
								min = 0, max = 360, step = 1,
								order = 2,
								get = function() return tonumber(GetSetting("miniicon.angle", 220)) or 220 end,
								set = function(_, v) SetSetting("miniicon.angle", v) end,
							},
							distance = {
								type = "range",
								name = sliderLabel("CONFIG_MINIICON_DISTANCE", "miniicon.distance", 12),
								min = -80, max = 80, step = 1,
								order = 3,
								get = function() return tonumber(GetSetting("miniicon.distance", 12)) or 12 end,
								set = function(_, v) SetSetting("miniicon.distance", v) end,
							},
						},
					},
					minimapTrackingGroup = {
						type = "group",
						inline = true,
						name = _trL("CONFIG_GENERAL_MINIMAP_TRACKING_LABEL"),
						order = 3,
						args = {
							mine = {
								type = "toggle",
								name = _trL("CONFIG_ENABLE_MINE"),
								order = 1,
								get = function() return GetSetting("show.minimap.mine") end,
								set = function(_, v) SetSetting("show.minimap.mine", v) end,
							},
							mineAll = {
								type = "toggle",
								name = _trL("ALL") .. " (" .. _trL("TRADE_MINING") .. ")",
								order = 2,
								get = function() return GetSetting("show.minimap.mine.all") end,
								set = function(_, v) SetSetting("show.minimap.mine.all", v) end,
							},
							mineSkilled = {
								type = "toggle",
								name = _trL("CONFIG_ENABLE_MINE_MINER_ONLY"),
								order = 3,
								get = function() return GetSetting("show.minimap.mine.onlyifskilled") end,
								set = function(_, v) SetSetting("show.minimap.mine.onlyifskilled", v) end,
							},
							mineTracked = {
								type = "toggle",
								name = _trL("CONFIG_ENABLE_ONLY_IF_TRACKING"),
								order = 4,
								get = function() return GetSetting("show.minimap.mine.onlyiftracked") end,
								set = function(_, v) SetSetting("show.minimap.mine.onlyiftracked", v) end,
							},
							herb = {
								type = "toggle",
								name = _trL("CONFIG_ENABLE_HERB"),
								order = 5,
								get = function() return GetSetting("show.minimap.herb") end,
								set = function(_, v) SetSetting("show.minimap.herb", v) end,
							},
							herbAll = {
								type = "toggle",
								name = _trL("ALL") .. " (" .. _trL("TRADE_HERBALISM") .. ")",
								order = 6,
								get = function() return GetSetting("show.minimap.herb.all") end,
								set = function(_, v) SetSetting("show.minimap.herb.all", v) end,
							},
							herbSkilled = {
								type = "toggle",
								name = _trL("CONFIG_ENABLE_HERB_HERBALIST_ONLY"),
								order = 7,
								get = function() return GetSetting("show.minimap.herb.onlyifskilled") end,
								set = function(_, v) SetSetting("show.minimap.herb.onlyifskilled", v) end,
							},
							herbTracked = {
								type = "toggle",
								name = _trL("CONFIG_ENABLE_ONLY_IF_TRACKING"),
								order = 8,
								get = function() return GetSetting("show.minimap.herb.onlyiftracked") end,
								set = function(_, v) SetSetting("show.minimap.herb.onlyiftracked", v) end,
							},
							open = {
								type = "toggle",
								name = _trL("ENABLE_OPEN"),
								order = 9,
								get = function() return GetSetting("show.minimap.open") end,
								set = function(_, v) SetSetting("show.minimap.open", v) end,
							},
							openAll = {
								type = "toggle",
								name = _trL("ALL") .. " (" .. _trL("CONFIG_SECTION_OPEN") .. ")",
								order = 10,
								get = function() return GetSetting("show.minimap.open.all") end,
								set = function(_, v) SetSetting("show.minimap.open.all", v) end,
							},
						},
					},
					worldmapTrackingGroup = {
						type = "group",
						inline = true,
						name = _trL("CONFIG_GENERAL_WORLDMAP_TRACKING_LABEL"),
						order = 4,
						args = {
							mine = {
								type = "toggle",
								name = _trL("CONFIG_ENABLE_MINE"),
								order = 1,
								get = function() return GetSetting("show.mainmap.mine") end,
								set = function(_, v) SetSetting("show.mainmap.mine", v) end,
							},
							mineAll = {
								type = "toggle",
								name = _trL("ALL") .. " (" .. _trL("TRADE_MINING") .. ")",
								order = 2,
								get = function() return GetSetting("show.mainmap.mine.all") end,
								set = function(_, v) SetSetting("show.mainmap.mine.all", v) end,
							},
							mineSkilled = {
								type = "toggle",
								name = _trL("CONFIG_ENABLE_MINE_MINER_ONLY"),
								order = 3,
								get = function() return GetSetting("show.mainmap.mine.onlyifskilled") end,
								set = function(_, v) SetSetting("show.mainmap.mine.onlyifskilled", v) end,
							},
							mineTracked = {
								type = "toggle",
								name = _trL("CONFIG_ENABLE_ONLY_IF_TRACKING"),
								order = 4,
								get = function() return GetSetting("show.mainmap.mine.onlyiftracked") end,
								set = function(_, v) SetSetting("show.mainmap.mine.onlyiftracked", v) end,
							},
							herb = {
								type = "toggle",
								name = _trL("CONFIG_ENABLE_HERB"),
								order = 5,
								get = function() return GetSetting("show.mainmap.herb") end,
								set = function(_, v) SetSetting("show.mainmap.herb", v) end,
							},
							herbAll = {
								type = "toggle",
								name = _trL("ALL") .. " (" .. _trL("TRADE_HERBALISM") .. ")",
								order = 6,
								get = function() return GetSetting("show.mainmap.herb.all") end,
								set = function(_, v) SetSetting("show.mainmap.herb.all", v) end,
							},
							herbSkilled = {
								type = "toggle",
								name = _trL("CONFIG_ENABLE_HERB_HERBALIST_ONLY"),
								order = 7,
								get = function() return GetSetting("show.mainmap.herb.onlyifskilled") end,
								set = function(_, v) SetSetting("show.mainmap.herb.onlyifskilled", v) end,
							},
							herbTracked = {
								type = "toggle",
								name = _trL("CONFIG_ENABLE_ONLY_IF_TRACKING"),
								order = 8,
								get = function() return GetSetting("show.mainmap.herb.onlyiftracked") end,
								set = function(_, v) SetSetting("show.mainmap.herb.onlyiftracked", v) end,
							},
							open = {
								type = "toggle",
								name = _trL("ENABLE_OPEN"),
								order = 9,
								get = function() return GetSetting("show.mainmap.open") end,
								set = function(_, v) SetSetting("show.mainmap.open", v) end,
							},
							openAll = {
								type = "toggle",
								name = _trL("ALL") .. " (" .. _trL("CONFIG_SECTION_OPEN") .. ")",
								order = 10,
								get = function() return GetSetting("show.mainmap.open.all") end,
								set = function(_, v) SetSetting("show.mainmap.open.all", v) end,
							},
						},
					},
				},
			},

			----------------------------------------------------------------------
			-- 2. Minimap
			----------------------------------------------------------------------
			minimap = {
				type = "group",
				name = _trL("CONFIG_SECTION_MINIMAP"),
				order = 20,
				args = {
					baseGroup = {
						type = "group",
						inline = true,
						name = _trL("CONFIG_MINIMAP_LABEL"),
						order = 1,
						args = {
							enable = {
								type = "toggle",
								name = _trL("CONFIG_MINIMAP_ENABLE"),
								width = "full",
								order = 1,
								get = function() return GetSetting("minimap.enable") end,
								set = function(_, v) SetSetting("minimap.enable", v) end,
							},
							count = {
								type = "range",
								name = sliderLabel("CONFIG_MINIMAP_MAX_NOTES", "minimap.count", 20),
								min = 1, max = 50, step = 1,
								order = 2,
								get = function() return tonumber(GetSetting("minimap.count", 20)) or 20 end,
								set = function(_, v) SetSetting("minimap.count", v) end,
							},
							opacity = {
								type = "range",
								name = sliderLabel("CONFIG_MINIMAP_NOTE_OPACITY", "minimap.opacity", 80),
								min = 0, max = 100, step = 1,
								order = 3,
								get = function() return tonumber(GetSetting("minimap.opacity", 80)) or 80 end,
								set = function(_, v) SetSetting("minimap.opacity", v) end,
							},
							iconsize = {
								type = "range",
								name = sliderLabel("CONFIG_MINIMAP_ICON_SIZE", "minimap.iconsize", 12),
								min = 4, max = 64, step = 1,
								order = 4,
								get = function() return tonumber(GetSetting("minimap.iconsize", 12)) or 12 end,
								set = function(_, v) SetSetting("minimap.iconsize", v) end,
							},
							distance = {
								type = "range",
								name = sliderLabel("CONFIG_MINIMAP_DISTANCE", "minimap.distance", 800),
								min = 100, max = 5000, step = 50,
								order = 5,
								get = function() return tonumber(GetSetting("minimap.distance", 800)) or 800 end,
								set = function(_, v) SetSetting("minimap.distance", v) end,
							},
							tooltipEnable = {
								type = "toggle",
								name = _trL("CONFIG_TOOLTIP_ENABLE"),
								width = "full",
								order = 6,
								get = function() return GetSetting("minimap.tooltip.enable") end,
								set = function(_, v) SetSetting("minimap.tooltip.enable", v) end,
							},
							tooltipCount = {
								type = "toggle",
								name = _trL("CONFIG_TOOLTIP_COUNTS"),
								order = 7,
								get = function() return GetSetting("minimap.tooltip.count") end,
								set = function(_, v) SetSetting("minimap.tooltip.count", v) end,
							},
							tooltipSource = {
								type = "toggle",
								name = _trL("CONFIG_TOOLTIP_SOURCE"),
								order = 8,
								get = function() return GetSetting("minimap.tooltip.source") end,
								set = function(_, v) SetSetting("minimap.tooltip.source", v) end,
							},
							tooltipSeen = {
								type = "toggle",
								name = _trL("CONFIG_TOOLTIP_LAST_SEEN"),
								order = 9,
								get = function() return GetSetting("minimap.tooltip.seen") end,
								set = function(_, v) SetSetting("minimap.tooltip.seen", v) end,
							},
							tooltipDistance = {
								type = "toggle",
								name = _trL("CONFIG_TOOLTIP_DISTANCE"),
								order = 10,
								get = function() return GetSetting("minimap.tooltip.distance") end,
								set = function(_, v) SetSetting("minimap.tooltip.distance", v) end,
							},
							tooltipRate = {
								type = "toggle",
								name = _trL("CONFIG_TOOLTIP_DROP_RATES"),
								order = 11,
								get = function() return GetSetting("minimap.tooltip.rate") end,
								set = function(_, v) SetSetting("minimap.tooltip.rate", v) end,
							},
						},
					},
					extraGroup = {
						type = "group",
						inline = true,
						name = _trL("CONFIG_MINIMAP_ADD_LABEL"),
						order = 2,
						args = {
							fadeEnable = {
								type = "toggle",
								name = _trL("CONFIG_MINIMAP_FADE_ENABLE"),
								width = "full",
								order = 1,
								get = function() return GetSetting("fade.enable") end,
								set = function(_, v) SetSetting("fade.enable", v) end,
							},
							fadeDist = {
								type = "range",
								name = sliderLabel("CONFIG_MINIMAP_FADE_DIST", "fade.distance", 500),
								min = 10, max = 1000, step = 10,
								order = 2,
								get = function() return tonumber(GetSetting("fade.distance", 500)) or 500 end,
								set = function(_, v) SetSetting("fade.distance", v) end,
							},
							fadePercent = {
								type = "range",
								name = sliderLabel("CONFIG_MINIMAP_FADE_PERCENT", "fade.percent", 50),
								min = 0, max = 100, step = 1,
								order = 3,
								get = function() return tonumber(GetSetting("fade.percent", 50)) or 50 end,
								set = function(_, v) SetSetting("fade.percent", v) end,
							},
							trackEnable = {
								type = "toggle",
								name = _trL("CONFIG_MINIMAP_TRACKING_ENABLE"),
								width = "full",
								order = 4,
								get = function() return GetSetting("track.enable") end,
								set = function(_, v) SetSetting("track.enable", v) end,
							},
							trackCircle = {
								type = "toggle",
								name = _trL("CONFIG_MINIMAP_TRACKING_CIRCLE_ENABLE"),
								order = 5,
								get = function() return GetSetting("track.circle") end,
								set = function(_, v) SetSetting("track.circle", v) end,
							},
							trackCurrent = {
								type = "toggle",
								name = _trL("CONFIG_MINIMAP_TRACKING_ACTIVE_ONLY"),
								order = 6,
								get = function() return GetSetting("track.current") end,
								set = function(_, v) SetSetting("track.current", v) end,
							},
							trackColorMine = {
								type = "color",
								name = _trC("TRADE_MINING"),
								order = 7,
								get = function() return getColorRGB("track.colour.MINE", 1, 0, 0) end,
								set = function(_, r, g, b) setColorRGB("track.colour.MINE", r, g, b) end,
							},
							trackColorHerb = {
								type = "color",
								name = _trC("TRADE_HERBALISM"),
								order = 8,
								get = function() return getColorRGB("track.colour.HERB", 0, 1, 0) end,
								set = function(_, r, g, b) setColorRGB("track.colour.HERB", r, g, b) end,
							},
							trackDist = {
								type = "range",
								name = sliderLabel("CONFIG_MINIMAP_TRACKING_DISTANCE", "track.distance", 100),
								min = 50, max = 150, step = 1,
								order = 9,
								get = function() return tonumber(GetSetting("track.distance", 100)) or 100 end,
								set = function(_, v) SetSetting("track.distance", v) end,
							},
							trackOpacity = {
								type = "range",
								name = sliderLabel("CONFIG_MINIMAP_TRACKING_OPACITY", "track.opacity", 80),
								min = 0, max = 100, step = 1,
								order = 10,
								get = function() return tonumber(GetSetting("track.opacity", 80)) or 80 end,
								set = function(_, v) SetSetting("track.opacity", v) end,
							},
							inspectEnable = {
								type = "toggle",
								name = _trL("CONFIG_MINIMAP_INSPECT_ENABLE"),
								width = "full",
								order = 11,
								get = function() return GetSetting("inspect.enable") end,
								set = function(_, v) SetSetting("inspect.enable", v) end,
							},
							inspectTint = {
								type = "toggle",
								name = _trL("CONFIG_MINIMAP_INSPECT_TINT_ENABLE"),
								order = 12,
								get = function() return GetSetting("inspect.tint") end,
								set = function(_, v) SetSetting("inspect.tint", v) end,
							},
							inspectDist = {
								type = "range",
								name = sliderLabel("CONFIG_MINIMAP_INSPECT_DIST", "inspect.distance", 25),
								min = 1, max = 100, step = 1,
								order = 13,
								get = function() return tonumber(GetSetting("inspect.distance", 25)) or 25 end,
								set = function(_, v) SetSetting("inspect.distance", v) end,
							},
							inspectPercent = {
								type = "range",
								name = sliderLabel("CONFIG_MINIMAP_INSPECT_FADING", "inspect.percent", 80),
								min = 0, max = 100, step = 1,
								order = 14,
								get = function() return tonumber(GetSetting("inspect.percent", 80)) or 80 end,
								set = function(_, v) SetSetting("inspect.percent", v) end,
							},
							inspectTime = {
								type = "range",
								name = sliderLabel("CONFIG_MINIMAP_INSPECT_TIMEOUT", "inspect.time", 120),
								min = 10, max = 900, step = 10,
								order = 15,
								get = function() return tonumber(GetSetting("inspect.time", 120)) or 120 end,
								set = function(_, v) SetSetting("inspect.time", v) end,
							},
							anonEnable = {
								type = "toggle",
								name = _trL("CONFIG_MINIMAP_ANON_ENABLE"),
								width = "full",
								order = 16,
								get = function() return GetSetting("anon.enable") end,
								set = function(_, v) SetSetting("anon.enable", v) end,
							},
							anonTint = {
								type = "toggle",
								name = _trL("CONFIG_MINIMAP_ANON_TINT"),
								order = 17,
								get = function() return GetSetting("anon.tint") end,
								set = function(_, v) SetSetting("anon.tint", v) end,
							},
							anonOpacity = {
								type = "range",
								name = sliderLabel("CONFIG_MINIMAP_ANON_OPACITY", "anon.opacity", 60),
								min = 0, max = 100, step = 1,
								order = 18,
								get = function() return tonumber(GetSetting("anon.opacity", 60)) or 60 end,
								set = function(_, v) SetSetting("anon.opacity", v) end,
							},
						},
					},
				},
			},

			----------------------------------------------------------------------
			-- 3. Mining / Herbalism / Treasure / Archaeology Filters
			----------------------------------------------------------------------
			mining = {
				type = "group",
				name = _trL("TRADE_MINING"),
				order = 30,
				args = buildNodeFilterGroup("mine", "CONFIG_SECTION_TITLE_MINE", "CONFIG_MINE_FILTER_LABEL"),
			},
			herbalism = {
				type = "group",
				name = _trL("TRADE_HERBALISM"),
				order = 40,
				args = buildNodeFilterGroup("herb", "CONFIG_SECTION_TITLE_HERB", "CONFIG_HERB_FILTER_LABEL"),
			},
			treasure = {
				type = "group",
				name = _trL("CONFIG_SECTION_OPEN"),
				order = 50,
				args = buildNodeFilterGroup("open", "CONFIG_SECTION_TITLE_OPEN", "CONFIG_OPEN_FILTER_LABEL"),
			},
			archaeology = {
				type = "group",
				name = _trL("PROFESSIONS_ARCHAEOLOGY"),
				order = 60,
				args = {
					header = {
						type = "header",
						name = _trL("CONFIG_SECTION_TITLE_ARCH"),
						order = 1,
					},
					enable = {
						type = "toggle",
						name = _trL("ENABLE"),
						order = 2,
						get = function() return GetSetting("arch.enable") end,
						set = function(_, v) SetSetting("arch.enable", v) end,
					},
					count = {
						type = "range",
						name = sliderLabel("CONFIG_ARCH_MAX_NOTES", "arch.minimap.count", 20),
						min = 1, max = 50, step = 1,
						order = 3,
						get = function() return tonumber(GetSetting("arch.minimap.count", 20)) or 20 end,
						set = function(_, v) SetSetting("arch.minimap.count", v) end,
					},
				},
			},

			----------------------------------------------------------------------
			-- 4. Sharing & Sync
			----------------------------------------------------------------------
			sharing = {
				type = "group",
				name = _trL("CONFIG_SECTION_SHARING"),
				order = 70,
				args = {
					guildGroup = {
						type = "group",
						inline = true,
						name = _trL("CONFIG_SHARING_GUILD_LABEL"),
						order = 1,
						args = {
							enable = {
								type = "toggle",
								name = _trL("CONFIG_SHARING_GUILD_ENABLE"),
								width = "full",
								order = 1,
								get = function() return GetSetting("guild.enable") end,
								set = function(_, v) SetSetting("guild.enable", v) end,
							},
							receive = {
								type = "toggle",
								name = _trL("CONFIG_SHARING_GUILD_DATABASE"),
								width = "full",
								order = 2,
								get = function() return GetSetting("guild.receive") end,
								set = function(_, v) SetSetting("guild.receive", v) end,
							},
							printSend = {
								type = "toggle",
								name = _trL("CONFIG_SHARING_GUILD_MESSAGE_SENT"),
								width = "full",
								order = 3,
								get = function() return GetSetting("guild.print.send") end,
								set = function(_, v) SetSetting("guild.print.send", v) end,
							},
							printRecv = {
								type = "toggle",
								name = _trL("CONFIG_SHARING_GUILD_MESSAGE_RECV"),
								width = "full",
								order = 4,
								get = function() return GetSetting("guild.print.recv") end,
								set = function(_, v) SetSetting("guild.print.recv", v) end,
							},
						},
					},
					raidGroup = {
						type = "group",
						inline = true,
						name = _trL("CONFIG_SHARING_GROUP_LABEL"),
						order = 2,
						args = {
							enable = {
								type = "toggle",
								name = _trL("CONFIG_SHARING_GROUP_ENABLE"),
								width = "full",
								order = 1,
								get = function() return GetSetting("raid.enable") end,
								set = function(_, v) SetSetting("raid.enable", v) end,
							},
							receive = {
								type = "toggle",
								name = _trL("CONFIG_SHARING_GROUP_DATABASE"),
								width = "full",
								order = 2,
								get = function() return GetSetting("raid.receive") end,
								set = function(_, v) SetSetting("raid.receive", v) end,
							},
							printSend = {
								type = "toggle",
								name = _trL("CONFIG_SHARING_GROUP_MESSAGE_SENT"),
								width = "full",
								order = 3,
								get = function() return GetSetting("raid.print.send") end,
								set = function(_, v) SetSetting("raid.print.send", v) end,
							},
							printRecv = {
								type = "toggle",
								name = _trL("CONFIG_SHARING_GROUP_MESSAGE_RECV"),
								width = "full",
								order = 4,
								get = function() return GetSetting("raid.print.recv") end,
								set = function(_, v) SetSetting("raid.print.recv", v) end,
							},
						},
					},
					personalGroup = {
						type = "group",
						inline = true,
						name = _trL("CONFIG_SHARING_PERSONAL_LABEL"),
						order = 3,
						args = {
							print = {
								type = "toggle",
								name = _trL("CONFIG_SHARING_PERSONAL_ENABLE"),
								width = "full",
								order = 1,
								get = function() return GetSetting("personal.print") end,
								set = function(_, v) SetSetting("personal.print", v) end,
							},
						},
					},
					bridgeGroup = {
						type = "group",
						inline = true,
						name = _trL("CONFIG_BRIDGE_GROUP"),
						order = 3.5,
						args = {
							enable = {
								type = "toggle",
								name = _trL("CONFIG_BRIDGE_ENABLE"),
								desc = _trL("CONFIG_BRIDGE_ENABLE_DESC"),
								width = "full",
								order = 1,
								get = function() return GetSetting("sharing.bridge.enable", true) end,
								set = function(_, v) SetSetting("sharing.bridge.enable", v) end,
							},
						},
					},
					blacklistGroup = {
						type = "group",
						inline = true,
						name = _trL("CONFIG_SHARING_BLACKLIST_LABEL"),
						order = 4,
						args = {
							addInput = {
								type = "input",
								name = _trL("IGNORE_PLAYER"),
								order = 1,
								get = function() return newBlacklistPlayer end,
								set = function(_, val)
									newBlacklistPlayer = (val or ""):trim()
									if newBlacklistPlayer ~= "" then
										Gatherer.Config.SharingBlacklist_Add(newBlacklistPlayer)
										newBlacklistPlayer = ""
										AceConfigRegistry:NotifyChange("GathererReforged")
									end
								end,
							},
							selectIgnored = {
								type = "select",
								name = _trL("CONFIG_SHARING_BLACKLIST_LABEL"),
								order = 2,
								values = function()
									local t = {}
									if type(Gatherer_SharingBlacklist) == "table" then
										for _, name in ipairs(Gatherer_SharingBlacklist) do
											t[name] = name
										end
									end
									return t
								end,
								get = function() return selectedBlacklistPlayer end,
								set = function(_, val) selectedBlacklistPlayer = val end,
							},
							removeBtn = {
								type = "execute",
								name = _trL("STOP_IGNORE"),
								order = 3,
								disabled = function() return not selectedBlacklistPlayer end,
								func = function()
									if selectedBlacklistPlayer then
										Gatherer.Config.SharingBlacklist_Remove(selectedBlacklistPlayer)
										selectedBlacklistPlayer = nil
										AceConfigRegistry:NotifyChange("GathererReforged")
									end
								end,
							},
						},
					},
				},
			},

			----------------------------------------------------------------------
			-- 5. HUD Plugin (GathererReforged_HUD)
			----------------------------------------------------------------------
			hud = {
				type = "group",
				name = "HUD",
				order = 80,
				args = {
					enable = {
						type = "toggle",
						name = _trL("ENABLE") .. " (Gatherer Reforged HUD)",
						width = "full",
						order = 1,
						get = function() return GetSetting("plugin.gatherer_hud.enable") end,
						set = function(_, v) SetSetting("plugin.gatherer_hud.enable", v) end,
					},
					note = {
						type = "description",
						name = _tr("HUD_CONFIG_USAGE_NOTE"),
						order = 2,
					},
					displayGroup = {
						type = "group",
						inline = true,
						name = _trL("HUD_CONFIG_DISPLAY_LABEL"),
						order = 3,
						args = {
							strata = {
								type = "select",
								name = _trL("HUD_CONFIG_STRATA_LABEL"),
								order = 1,
								values = {
									[1] = _trL("STRATA_BACKGROUND"),
									[2] = _trL("STRATA_LOW"),
									[3] = _trL("STRATA_MEDIUM"),
									[4] = _trL("STRATA_HIGH"),
								},
								get = function() return tonumber(GetSetting("plugin.gatherer_hud.strata", 1)) or 1 end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.strata", v) end,
							},
							radius = {
								type = "range",
								name = sliderLabel("HUD_CONFIG_plugin.gatherer_hud.radius", "plugin.gatherer_hud.radius", 500),
								min = 25, max = 800, step = 25,
								order = 2,
								get = function() return tonumber(GetSetting("plugin.gatherer_hud.radius", 500)) or 500 end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.radius", v) end,
							},
							iconsize = {
								type = "range",
								name = sliderLabel("HUD_CONFIG_plugin.gatherer_hud.iconsize", "plugin.gatherer_hud.iconsize", 40),
								min = 5, max = 80, step = 1,
								order = 3,
								get = function() return tonumber(GetSetting("plugin.gatherer_hud.iconsize", 40)) or 40 end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.iconsize", v) end,
							},
							offsetH = {
								type = "range",
								name = sliderLabel("HUD_CONFIG_plugin.gatherer_hud.offset.horizontal", "plugin.gatherer_hud.offset.horizontal", 0),
								min = -800, max = 800, step = 10,
								order = 4,
								get = function() return tonumber(GetSetting("plugin.gatherer_hud.offset.horizontal", 0)) or 0 end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.offset.horizontal", v) end,
							},
							offsetV = {
								type = "range",
								name = sliderLabel("HUD_CONFIG_plugin.gatherer_hud.offset.vertical", "plugin.gatherer_hud.offset.vertical", -200),
								min = -800, max = 800, step = 10,
								order = 5,
								get = function() return tonumber(GetSetting("plugin.gatherer_hud.offset.vertical", -200)) or -200 end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.offset.vertical", v) end,
							},
							alpha = {
								type = "range",
								name = sliderLabel("HUD_CONFIG_plugin.gatherer_hud.alpha", "plugin.gatherer_hud.alpha", 70),
								min = 1, max = 100, step = 1,
								order = 6,
								get = function() return tonumber(GetSetting("plugin.gatherer_hud.alpha", 70)) or 70 end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.alpha", v) end,
							},
							yards = {
								type = "range",
								name = sliderLabel("HUD_CONFIG_plugin.gatherer_hud.yards", "plugin.gatherer_hud.yards", 1200),
								min = 100, max = 2000, step = 100,
								order = 7,
								get = function() return tonumber(GetSetting("plugin.gatherer_hud.yards", 1200)) or 1200 end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.yards", v) end,
							},
							fade = {
								type = "range",
								name = sliderLabel("HUD_CONFIG_plugin.gatherer_hud.fade", "plugin.gatherer_hud.fade", 45),
								min = 1, max = 100, step = 1,
								order = 8,
								get = function() return tonumber(GetSetting("plugin.gatherer_hud.fade", 45)) or 45 end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.fade", v) end,
							},
							angle = {
								type = "range",
								name = sliderLabel("HUD_CONFIG_plugin.gatherer_hud.angle", "plugin.gatherer_hud.angle", 40),
								min = 1, max = 90, step = 1,
								order = 9,
								get = function() return tonumber(GetSetting("plugin.gatherer_hud.angle", 40)) or 40 end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.angle", v) end,
							},
							perspective = {
								type = "range",
								name = sliderLabel("HUD_CONFIG_plugin.gatherer_hud.perspective", "plugin.gatherer_hud.perspective", 10),
								min = 2, max = 10, step = 0.1,
								order = 10,
								get = function() return tonumber(GetSetting("plugin.gatherer_hud.perspective", 10)) or 10 end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.perspective", v) end,
							},
							framerate = {
								type = "range",
								name = sliderLabel("HUD_CONFIG_plugin.gatherer_hud.min_fullframerate", "plugin.gatherer_hud.min_fullframerate", 100),
								min = 0, max = 100, step = 1,
								order = 11,
								get = function() return tonumber(GetSetting("plugin.gatherer_hud.min_fullframerate", 100)) or 100 end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.min_fullframerate", v) end,
							},
						},
					},
					hideGroup = {
						type = "group",
						inline = true,
						name = _trL("HUD_CONFIG_HIDING_LABEL"),
						order = 4,
						args = {
							combat = {
								type = "toggle",
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.hide.combat"),
								order = 1,
								get = function() return GetSetting("plugin.gatherer_hud.hide.combat") end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.hide.combat", v) end,
							},
							target = {
								type = "toggle",
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.hide.target"),
								order = 2,
								get = function() return GetSetting("plugin.gatherer_hud.hide.target") end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.hide.target", v) end,
							},
							flying = {
								type = "toggle",
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.hide.flying"),
								order = 3,
								get = function() return GetSetting("plugin.gatherer_hud.hide.flying") end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.hide.flying", v) end,
							},
							inside = {
								type = "toggle",
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.hide.inside"),
								order = 4,
								get = function() return GetSetting("plugin.gatherer_hud.hide.inside") end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.hide.inside", v) end,
							},
							mounted = {
								type = "toggle",
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.hide.mounted"),
								order = 5,
								get = function() return GetSetting("plugin.gatherer_hud.hide.mounted") end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.hide.mounted", v) end,
							},
							walking = {
								type = "toggle",
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.hide.walking"),
								order = 6,
								get = function() return GetSetting("plugin.gatherer_hud.hide.walking") end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.hide.walking", v) end,
							},
							resting = {
								type = "toggle",
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.hide.resting"),
								order = 7,
								get = function() return GetSetting("plugin.gatherer_hud.hide.resting") end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.hide.resting", v) end,
							},
							stealth = {
								type = "toggle",
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.hide.stealth"),
								order = 8,
								get = function() return GetSetting("plugin.gatherer_hud.hide.stealth") end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.hide.stealth", v) end,
							},
							swimming = {
								type = "toggle",
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.hide.swimming"),
								order = 9,
								get = function() return GetSetting("plugin.gatherer_hud.hide.swimming") end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.hide.swimming", v) end,
							},
						},
					},
					visualGroup = {
						type = "group",
						inline = true,
						name = _trL("HUD_CONFIG_VISIBILITY_LABEL"),
						order = 5,
						args = {
							baseEnable = {
								type = "toggle",
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.base.enable"),
								order = 1,
								get = function() return GetSetting("plugin.gatherer_hud.base.enable") end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.base.enable", v) end,
							},
							baseColor = {
								type = "color",
								hasAlpha = true,
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.base.color"),
								order = 2,
								get = function() return getColorRGBA("plugin.gatherer_hud.base.color", 0, 0, 0, 0.5) end,
								set = function(_, r, g, b, a) setColorRGBA("plugin.gatherer_hud.base.color", r, g, b, a) end,
							},
							centerEnable = {
								type = "toggle",
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.center.enable"),
								order = 3,
								get = function() return GetSetting("plugin.gatherer_hud.center.enable") end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.center.enable", v) end,
							},
							centerColor = {
								type = "color",
								hasAlpha = true,
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.center.color"),
								order = 4,
								get = function() return getColorRGBA("plugin.gatherer_hud.center.color", 1, 1, 1, 0.4) end,
								set = function(_, r, g, b, a) setColorRGBA("plugin.gatherer_hud.center.color", r, g, b, a) end,
							},
							heatEnable = {
								type = "toggle",
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.heat.enable"),
								order = 5,
								get = function() return GetSetting("plugin.gatherer_hud.heat.enable") end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.heat.enable", v) end,
							},
							heatColor = {
								type = "color",
								hasAlpha = true,
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.heat.color"),
								order = 6,
								get = function() return getColorRGBA("plugin.gatherer_hud.heat.color", 1, 0.3, 0, 0.7) end,
								set = function(_, r, g, b, a) setColorRGBA("plugin.gatherer_hud.heat.color", r, g, b, a) end,
							},
							partyEnable = {
								type = "toggle",
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.party.enable"),
								order = 7,
								get = function() return GetSetting("plugin.gatherer_hud.party.enable") end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.party.enable", v) end,
							},
							partyColor = {
								type = "color",
								hasAlpha = true,
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.party.color"),
								order = 8,
								get = function() return getColorRGBA("plugin.gatherer_hud.party.color", 0.2, 0.2, 1, 0.7) end,
								set = function(_, r, g, b, a) setColorRGBA("plugin.gatherer_hud.party.color", r, g, b, a) end,
							},
							partySize = {
								type = "range",
								name = sliderLabel("HUD_CONFIG_plugin.gatherer_hud.party.size", "plugin.gatherer_hud.party.size", 40),
								min = 5, max = 80, step = 1,
								order = 9,
								get = function() return tonumber(GetSetting("plugin.gatherer_hud.party.size", 40)) or 40 end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.party.size", v) end,
							},
							heatCooldown = {
								type = "range",
								name = sliderLabel("HUD_CONFIG_plugin.gatherer_hud.heat.cooldown", "plugin.gatherer_hud.heat.cooldown", 600),
								min = 10, max = 4800, step = 10,
								order = 10,
								get = function() return tonumber(GetSetting("plugin.gatherer_hud.heat.cooldown", 600)) or 600 end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.heat.cooldown", v) end,
							},
							heatNeverCooldown = {
								type = "toggle",
								name = _trL("HUD_CONFIG_plugin.gatherer_hud.heat.nevercooldown"),
								order = 11,
								get = function() return GetSetting("plugin.gatherer_hud.heat.nevercooldown") end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.heat.nevercooldown", v) end,
							},
							heatSize = {
								type = "range",
								name = sliderLabel("HUD_CONFIG_plugin.gatherer_hud.heat.size", "plugin.gatherer_hud.heat.size", 120),
								min = 0, max = 300, step = 10,
								order = 12,
								get = function() return tonumber(GetSetting("plugin.gatherer_hud.heat.size", 120)) or 120 end,
								set = function(_, v) SetSetting("plugin.gatherer_hud.heat.size", v) end,
							},
						},
					},
				},
			},

			----------------------------------------------------------------------
			-- 6. Profiles
			----------------------------------------------------------------------
			profiles = {
				type = "group",
				name = _trL("CONFIG_SECTION_PROFILES"),
				order = 90,
				args = {
					header = {
						type = "header",
						name = _trL("CONFIG_SECTION_TITLE_PROFILES"),
						order = 1,
					},
					currentProfile = {
						type = "select",
						name = _trL("CONFIG_PROFILE_CURRENT_LABEL"),
						order = 2,
						values = function()
							local res = {}
							local list = GetSetting("profile.profiles") or { "Default" }
							for _, p in ipairs(list) do
								res[p] = p
							end
							return res
						end,
						get = function() return GetSetting("profile") or "Default" end,
						set = function(_, val) SetSetting("profile", val) end,
					},
					deleteProfile = {
						type = "execute",
						name = _trL("DELETE"),
						order = 3,
						confirm = true,
						disabled = function() return (GetSetting("profile") or "Default") == "Default" end,
						func = function()
							SetSetting("profile.delete", true)
						end,
					},
					newHeader = {
						type = "header",
						name = _trL("CONFIG_PROFILE_NEW"),
						order = 4,
					},
					newName = {
						type = "input",
						name = _trL("CONFIG_PROFILE_NEW_LABEL"),
						order = 5,
						get = function() return newProfileName end,
						set = function(_, val)
							newProfileName = (val or ""):trim()
							SetSetting("profile.name", newProfileName)
						end,
					},
					createNew = {
						type = "execute",
						name = _trL("CONFIG_PROFILE_CREATE_NEW"),
						order = 6,
						disabled = function() return newProfileName == "" end,
						func = function()
							SetSetting("profile.name", newProfileName)
							SetSetting("profile.save", true)
							newProfileName = ""
						end,
					},
					copyNew = {
						type = "execute",
						name = _trL("CONFIG_PROFILE_CREATE_COPY"),
						order = 7,
						disabled = function() return newProfileName == "" end,
						func = function()
							SetSetting("profile.name", newProfileName)
							SetSetting("profile.copy", true)
							newProfileName = ""
						end,
					},
				},
			},

			----------------------------------------------------------------------
			-- 6.5 Database & Integrations (GatherMate2, Session Tracker, AH, Cooldowns)
			----------------------------------------------------------------------
			integrations = {
				type = "group",
				name = _trL("CONFIG_SECTION_INTEGRATIONS"),
				order = 85,
				args = {
					importGroup = {
						type = "group",
						inline = true,
						name = _trL("CONFIG_GM2_GROUP"),
						order = 1,
						args = {
							desc = {
								type = "description",
								name = _trL("CONFIG_GM2_DESC"),
								order = 1,
							},
							importSaved = {
								type = "execute",
								name = _trL("CONFIG_GM2_IMPORT_SAVED"),
								desc = _trL("CONFIG_GM2_IMPORT_SAVED_DESC"),
								width = "normal",
								order = 2,
								func = function()
									if Gatherer.Integrations and Gatherer.Integrations.ImportGatherMate2 then
										Gatherer.Integrations.ImportGatherMate2(false)
										AceConfigRegistry:NotifyChange("GathererReforged")
									end
								end,
							},
							importFullData = {
								type = "execute",
								name = _trL("CONFIG_GM2_IMPORT_FULL"),
								desc = _trL("CONFIG_GM2_IMPORT_FULL_DESC"),
								width = "double",
								order = 3,
								func = function()
									if Gatherer.Integrations and Gatherer.Integrations.ImportGatherMate2 then
										Gatherer.Integrations.ImportGatherMate2(true)
										AceConfigRegistry:NotifyChange("GathererReforged")
									end
								end,
							},
							bridgeEnable = {
								type = "toggle",
								name = _trL("CONFIG_BRIDGE_ENABLE"),
								desc = _trL("CONFIG_BRIDGE_ENABLE_DESC"),
								width = "full",
								order = 4,
								get = function() return GetSetting("sharing.bridge.enable", true) end,
								set = function(_, v) SetSetting("sharing.bridge.enable", v) end,
							},
						},
					},
					sessionGroup = {
						type = "group",
						inline = true,
						name = _trL("CONFIG_SESSION_GROUP"),
						order = 2,
						args = {
							enable = {
								type = "toggle",
								name = _trL("CONFIG_SESSION_ENABLE"),
								width = "full",
								order = 1,
								get = function() return GetSetting("session.enable", true) end,
								set = function(_, v)
									SetSetting("session.enable", v)
									if Gatherer.MiniIcon and Gatherer.MiniIcon.UpdateLDBText then
										Gatherer.MiniIcon.UpdateLDBText()
									end
								end,
							},
							marketPrice = {
								type = "toggle",
								name = _trL("CONFIG_MARKET_PRICE_ENABLE"),
								width = "full",
								order = 2,
								get = function() return GetSetting("tooltip.marketprice", true) end,
								set = function(_, v) SetSetting("tooltip.marketprice", v) end,
							},
							priceSource = {
								type = "select",
								name = _trL("CONFIG_PRICE_SOURCE"),
								width = "normal",
								order = 2.5,
								values = function()
									if Gatherer.Integrations and Gatherer.Integrations.GetAvailablePriceSources then
										return Gatherer.Integrations.GetAvailablePriceSources()
									end
									return { ["AUTO"] = _trL("CONFIG_PRICE_SOURCE_AUTO") }
								end,
								get = function()
									local cur = GetSetting("tooltip.pricesource", "AUTO") or "AUTO"
									local avail = Gatherer.Integrations and Gatherer.Integrations.GetAvailablePriceSources and Gatherer.Integrations.GetAvailablePriceSources()
									if avail and not avail[cur] then
										return "AUTO"
									end
									return cur
								end,
								set = function(_, v)
									SetSetting("tooltip.pricesource", v)
									if Gatherer.MiniIcon and Gatherer.MiniIcon.UpdateLDBText then
										Gatherer.MiniIcon.UpdateLDBText()
									end
								end,
							},
							statsText = {
								type = "description",
								fontSize = "medium",
								order = 3,
								name = function()
									if not (Gatherer.Integrations and Gatherer.Integrations.Session) then
										return ""
									end
									local s = Gatherer.Integrations.Session.GetSummary()
									local mins = math.floor(s.elapsed / 60)
									local secs = s.elapsed % 60
									return string.format(
										_trL("CONFIG_SESSION_STATS_FMT"),
										mins, secs, s.nodes, s.nodesPerHour,
										Gatherer.Integrations.FormatMoney(s.totalValue),
										Gatherer.Integrations.FormatMoney(s.goldPerHour)
									)
								end,
							},
							resetBtn = {
								type = "execute",
								name = _trL("CONFIG_SESSION_RESET"),
								order = 4,
								func = function()
									if Gatherer.Integrations and Gatherer.Integrations.Session then
										Gatherer.Integrations.Session.Reset()
										AceConfigRegistry:NotifyChange("GathererReforged")
									end
								end,
							},
						},
					},
					cooldownGroup = {
						type = "group",
						inline = true,
						name = _trL("CONFIG_COOLDOWN_GROUP"),
						order = 3,
						args = {
							enable = {
								type = "toggle",
								name = _trL("CONFIG_COOLDOWN_ENABLE"),
								width = "full",
								order = 1,
								get = function() return GetSetting("cooldown.enable", true) end,
								set = function(_, v) SetSetting("cooldown.enable", v) end,
							},
							time = {
								type = "range",
								name = sliderLabel("CONFIG_COOLDOWN_TIME", "cooldown.time", 300),
								min = 30, max = 1200, step = 15,
								order = 2,
								get = function() return tonumber(GetSetting("cooldown.time", 300)) or 300 end,
								set = function(_, v) SetSetting("cooldown.time", v) end,
							},
							opacity = {
								type = "range",
								name = sliderLabel("CONFIG_COOLDOWN_OPACITY", "cooldown.opacity", 35),
								min = 10, max = 90, step = 5,
								order = 3,
								get = function() return tonumber(GetSetting("cooldown.opacity", 35)) or 35 end,
								set = function(_, v) SetSetting("cooldown.opacity", v) end,
							},
						},
					},
				},
			},

			----------------------------------------------------------------------
			-- 7. About
			----------------------------------------------------------------------
			about = {
				type = "group",
				name = _trL("CONFIG_SECTION_ABOUT"),
				order = 100,
				args = {
					infoGroup = {
						type = "group",
						inline = true,
						name = _trL("CONFIG_SECTION_TITLE_ABOUT"),
						order = 1,
						args = {
							banner = {
								type = "description",
								image = 133939,
								imageWidth = 36,
								imageHeight = 36,
								imageCoords = { 0.08, 0.92, 0.08, 0.92 },
								fontSize = "medium",
								order = 1,
								name = function()
									return string.format(
										"|cffffd200Gatherer Reforged|r  |cff00ff96v%s|r\n"
										.. "|cff8892a4Author:|r |cff00ff96gOOvER|r   |cff555c68||   |cff8892a4License:|r |cffffffffGPL-3.0|r   |cff555c68||   |cff8892a4Legacy:|r |cffb0b8c4Norganna's Gatherer (2005–2017)|r",
										tostring(Gatherer.Var.Version or "1.0.0")
									)
								end,
							},
							desc1 = {
								type = "description",
								fontSize = "medium",
								order = 2,
								name = "\n" .. _trL("DESCRIPTION") .. "\n",
							},
							desc2 = {
								type = "description",
								order = 3,
								name = "|cff8892a4" .. _trL("DESCRIPTION_LICENSE") .. "|r\n",
							},
							loadedMsg = {
								type = "toggle",
								name = _trL("CONFIG_ABOUT_LOADED_ENABLE"),
								width = "full",
								order = 4,
								get = function() return GetSetting("about.loaded") end,
								set = function(_, v) SetSetting("about.loaded", v) end,
							},
						},
					},
					statsGroup = {
						type = "group",
						inline = true,
						name = _trL("CONFIG_SECTION_INTEGRATIONS") .. "  —  " .. _tr("REPORT_TITLE"),
						order = 2,
						args = {
							dbSummary = {
								type = "description",
								fontSize = "medium",
								order = 1,
								name = function()
									local totalZones, totalHerbs, totalOres, totalTreasures, totalArch = 0, 0, 0, 0, 0
									if Gatherer.Storage and Gatherer.Storage.GetAreaIndices and Gatherer.Storage.GetNodeCountsByGatherType then
										for _, zone in Gatherer.Storage.GetAreaIndices() do
											totalZones = totalZones + 1
											local a, t, h, o = Gatherer.Storage.GetNodeCountsByGatherType(zone)
											totalArch = totalArch + (a or 0)
											totalTreasures = totalTreasures + (t or 0)
											totalHerbs = totalHerbs + (h or 0)
											totalOres = totalOres + (o or 0)
										end
									end
									local totalNodes = totalHerbs + totalOres + totalTreasures + totalArch
									local dynCount = 0
									if type(_G.Gatherer_DynamicNodes) == "table" then
										for _ in pairs(_G.Gatherer_DynamicNodes) do dynCount = dynCount + 1 end
									end
									return string.format(
										"|T134269:14:14:0:0:64:64:5:59:5:59|t  |cffffd200%s:|r |cff00ff96%d|r     "
										.. "|T134437:14:14:0:0:64:64:5:59:5:59|t  |cffffd200%s:|r |cffffffff%d|r     "
										.. "|T134332:14:14:0:0:64:64:5:59:5:59|t  |cffffd200%s:|r |cffffd200%s|r\n\n"
										.. "|T136065:14:14:0:0:64:64:5:59:5:59|t  |cffb0b8c4%s:|r |cff00ff96%d|r     "
										.. "|T136248:14:14:0:0:64:64:5:59:5:59|t  |cffb0b8c4%s:|r |cff00ff96%d|r     "
										.. "|T132594:14:14:0:0:64:64:5:59:5:59|t  |cffb0b8c4%s:|r |cff00ff96%d|r     "
										.. "|T134435:14:14:0:0:64:64:5:59:5:59|t  |cffb0b8c4%s:|r |cff00ff96%d|r",
										_tr("DENSITY_COLUMN_HEADER_NUM_NODE"), totalNodes,
										_tr("REPORT_COLUMN_HEADER_REGION"), totalZones,
										_trL("CONFIG_SECTION_PROFILES"), tostring(GetSetting("profile") or "Default"),
										_trL("TRADE_HERBALISM"), totalHerbs,
										_trL("TRADE_MINING"), totalOres,
										_trL("CONFIG_SECTION_OPEN"), totalTreasures,
										_trL("PROFESSIONS_ARCHAEOLOGY"), totalArch
									)
								end,
							},
						},
					},
					commandsGroup = {
						type = "group",
						inline = true,
						name = "Slash-Commands & Shortcuts (/gather, /gatherer)",
						order = 3,
						args = {
							cmdList = {
								type = "description",
								fontSize = "medium",
								order = 1,
								name = function()
									Gatherer.Locale.SECTION_HIGHLIGHT_CODE = "|cff1fb3ff"
									return table.concat({
										"|cffffd200/gather|r  |cff667080—|r  " .. _tr("LABEL_CONFIG"),
										"|cffffd200/gather report|r  |cff667080—|r  " .. _tr("LABEL_REPORT"),
										"|cffffd200/gather search|r  |cff667080—|r  " .. _tr("LABEL_DENSITY_REPORT"),
										"|cffffd200/gather import|r  |cff667080—|r  " .. _trL("CONFIG_GM2_IMPORT_FULL"),
										"|cffffd200/gather session|r  /  |cffffd200/gather reset|r  |cff667080—|r  " .. _trL("CONFIG_SESSION_GROUP"),
										"|cffffd200/gather minimap|r  /  |cffffd200/gather mainmap|r  /  |cffffd200/gather herbs||mining||open|r",
										"",
										_tr("MINIICON_ACTIONS_CLICK") .. "   |cff555c68•|r   " .. _tr("MINIICON_ACTIONS_RIGHT_CLICK"),
										_tr("MINIICON_ACTIONS_SHIFT_CLICK") .. "   |cff555c68•|r   " .. _tr("MINIICON_ACTIONS_SHIFT_RIGHT_CLICK"),
									}, "\n")
								end,
							},
						},
					},
					linksGroup = {
						type = "group",
						inline = true,
						name = "GitHub, Wago.io & Support (Ctrl+C)",
						order = 4,
						args = {
							githubUrl = {
								type = "input",
								name = "GitHub Repository",
								width = "double",
								order = 1,
								get = function() return "https://github.com/gOOvER/GathererReforged" end,
								set = function() end,
							},
							wagoUrl = {
								type = "input",
								name = "Wago Addons",
								width = "double",
								order = 2,
								get = function() return "https://addons.wago.io/addons/gathererreforged" end,
								set = function() end,
							},
							donateUrl = {
								type = "input",
								name = "Support & Donate (gOOvER)",
								width = "double",
								order = 3,
								get = function() return "https://donate.goover.dev" end,
								set = function() end,
							},
						},
					},
				},
			},
		},
	}

	return options
end

local registered = false
local function ensureRegistered()
	if registered then return end
	registered = true

	AceConfig:RegisterOptionsTable("GathererReforged", buildOptionsTable)
	AceConfigDialog:SetDefaultSize("GathererReforged", 840, 620)
	pcall(function()
		AceConfigDialog:AddToBlizOptions("GathererReforged", "Gatherer Reforged")
	end)
end

--------------------------------------------------------------------------------
-- Modern Dark-Gold Standalone Options Window (GathererConfigFrame)
--------------------------------------------------------------------------------
local configFrame = nil
local hostGroup = nil
local activeCategory = "general"

local CONFIG_SECTIONS = {
	{ key = "general",      icon = 134269, label = function() return _trL("CONFIG_SECTION_GENERAL") end },
	{ key = "minimap",      icon = 134437, label = function() return _trL("CONFIG_SECTION_MINIMAP") end },
	{ key = "mining",       icon = 136248, label = function() return _trL("TRADE_MINING") end },
	{ key = "herbalism",    icon = 136065, label = function() return _trL("TRADE_HERBALISM") end },
	{ key = "treasure",     icon = 132594, label = function() return _trL("CONFIG_SECTION_OPEN") end },
	{ key = "archaeology",  icon = 134435, label = function() return _trL("PROFESSIONS_ARCHAEOLOGY") end },
	{ key = "sharing",      icon = 133464, label = function() return _trL("CONFIG_SECTION_SHARING") end },
	{ key = "hud",          icon = 135769, label = function() return "HUD" end },
	{ key = "integrations", icon = 132596, label = function() return _trL("CONFIG_SECTION_INTEGRATIONS") end },
	{ key = "profiles",     icon = 134332, label = function() return _trL("CONFIG_SECTION_PROFILES") end },
	{ key = "about",        icon = 133738, label = function() return _trL("CONFIG_SECTION_ABOUT") end },
}

local function styleAceCheckBox(widget, UIStyle)
	if not widget or not widget.frame or not widget.checkbg then return end
	local frame = widget.frame
	if not frame._gathCheckBoxBg then
		local box = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
		box:SetSize(18, 18)
		box:SetPoint("CENTER", widget.checkbg, "CENTER", 0, 0)
		UIStyle.ApplyBox(box, 0.06, 0.07, 0.10, 1, 0.30, 0.34, 0.44, 1)
		frame._gathCheckBoxBg = box

		local icon = box:CreateTexture(nil, "OVERLAY", nil, 7)
		icon:SetSize(16, 16)
		icon:SetPoint("CENTER", box, "CENTER", 0, 0)
		icon:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		frame._gathCheckIcon = icon

		local function syncBoxState(w)
			if not w or not w.frame or not w.frame._gathCheckBoxBg then return end
			local b = w.frame._gathCheckBoxBg
			local ic = w.frame._gathCheckIcon
			if w.check then w.check:SetAlpha(0) end
			if w.checkbg then w.checkbg:SetAlpha(0) end
			if w.checkbg and w.checkbg.backdrop then w.checkbg.backdrop:SetAlpha(0) end
			if w.checked then
				ic:Show()
				UIStyle.ApplyBox(b, 0.13, 0.23, 0.19, 1, 0.82, 0.68, 0.20, 1)
			else
				ic:Hide()
				UIStyle.ApplyBox(b, 0.06, 0.07, 0.10, 1, 0.30, 0.34, 0.44, 1)
			end
			if w.disabled then
				ic:SetDesaturated(true)
				b:SetAlpha(0.45)
			else
				ic:SetDesaturated(false)
				b:SetAlpha(1.0)
			end
		end

		hooksecurefunc(widget, "SetValue", syncBoxState)
		hooksecurefunc(widget, "SetDisabled", syncBoxState)
		frame._gathSyncCheck = syncBoxState
	end
	if frame._gathSyncCheck then
		frame._gathSyncCheck(widget)
	end
end

local function styleAceWidgetsRecursive(widget)
	if not widget then return end
	local UIStyle = Gatherer.UIStyle
	if UIStyle then
		local fontSize = UIStyle.GetFontSize()
		if widget.type == "InlineGroup" and widget.border then
			UIStyle.ApplyBox(widget.border, 0.10, 0.12, 0.16, 0.92, 0.22, 0.26, 0.34, 1)
			if widget.titletext then
				widget.titletext:SetTextColor(0.95, 0.80, 0.28)
				UIStyle.ApplyFont(widget.titletext, 1)
			end
		elseif widget.type == "Heading" and widget.label then
			UIStyle.ApplyFont(widget.label, 1)
		elseif (widget.type == "Label" or widget.type == "InteractiveLabel") and widget.label then
			UIStyle.ApplyFont(widget.label, 0)
		elseif widget.type == "CheckBox" and widget.text then
			styleAceCheckBox(widget, UIStyle)
			UIStyle.ApplyFont(widget.text, 0)
			if widget.SetHeight then
				widget:SetHeight(math.max(24, fontSize + 11))
			end
		elseif widget.type == "Button" and widget.frame then
			local fs = widget.text or (widget.frame.GetFontString and widget.frame:GetFontString())
			if fs then
				UIStyle.ApplyFont(fs, 0)
				local strW = fs:GetStringWidth() or 0
				local curW = widget.frame:GetWidth() or 100
				if strW > 0 and (strW + 28) > curW then
					widget.frame:SetWidth(math.ceil(strW + 28))
				end
			end
		elseif widget.type == "EditBox" then
			if widget.label then UIStyle.ApplyFont(widget.label, -1) end
			if widget.editbox then UIStyle.ApplyFont(widget.editbox, 0) end
		elseif widget.type == "MultiLineEditBox" then
			if widget.label then UIStyle.ApplyFont(widget.label, 0) end
			if widget.editBox then UIStyle.ApplyFont(widget.editBox, 0) end
		elseif widget.type == "Dropdown" then
			if widget.label then UIStyle.ApplyFont(widget.label, -1) end
			if widget.text then UIStyle.ApplyFont(widget.text, 0) end
		elseif widget.type == "Slider" then
			if widget.label then UIStyle.ApplyFont(widget.label, 0) end
			if widget.editbox then UIStyle.ApplyFont(widget.editbox, 0) end
		end
	end
	if type(widget.children) == "table" then
		for _, child in ipairs(widget.children) do
			styleAceWidgetsRecursive(child)
		end
	end
	if widget.PerformLayout then
		pcall(function() widget:PerformLayout() end)
	end
end

local function renderActiveCategory()
	if not configFrame or not configFrame:IsShown() or not hostGroup then return end
	ensureRegistered()
	local UIStyle = Gatherer.UIStyle

	for _, sec in ipairs(CONFIG_SECTIONS) do
		local btn = configFrame.NavButtons[sec.key]
		if btn then
			if UIStyle then
				UIStyle.ApplyFont(btn.Label, 0)
			end
			local isSelected = (sec.key == activeCategory)
			btn.isSelected = isSelected
			btn:UpdateVisual(false)
			if isSelected then
				configFrame.Content.HeaderIcon:SetTexture(sec.icon)
				configFrame.Content.HeaderTitle:SetText(sec.label())
				if UIStyle then
					UIStyle.ApplyFont(configFrame.Content.HeaderTitle, 1)
				end
			end
		end
	end

	if configFrame.ProfileBadge then
		if UIStyle then UIStyle.ApplyFont(configFrame.ProfileBadge, 0) end
		configFrame.ProfileBadge:SetText("|cff778292" .. _trL("CONFIG_SECTION_PROFILES") .. ":|r |cffffd200" .. tostring(GetSetting("profile") or "Default") .. "|r")
	end

	if configFrame.ReportBtn and configFrame.SearchBtn and configFrame.ProfileBadge then
		configFrame.ReportBtn:UpdateSize()
		configFrame.SearchBtn:UpdateSize()
		configFrame.SearchBtn:ClearAllPoints()
		configFrame.SearchBtn:SetPoint("LEFT", configFrame.ReportBtn, "RIGHT", 8, 0)
		configFrame.ProfileBadge:ClearAllPoints()
		configFrame.ProfileBadge:SetPoint("LEFT", configFrame.SearchBtn, "RIGHT", 18, 0)
	end
	if configFrame.DoneBtn then
		configFrame.DoneBtn:UpdateSize()
	end

	AceConfigDialog:Open("GathererReforged", hostGroup, activeCategory)
	styleAceWidgetsRecursive(hostGroup)
end

refreshCustomConfigFrame = function()
	if configFrame and configFrame:IsShown() then
		renderActiveCategory()
	end
end

local function ensureConfigFrame()
	if configFrame then return configFrame end
	local UIStyle = Gatherer.UIStyle
	if not UIStyle then return nil end

	local frame = CreateFrame("Frame", "GathererConfigFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame:Hide()
	frame:SetSize(960, 620)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	UIStyle.ApplyBox(frame, 0.07, 0.08, 0.11, 0.97, 0.26, 0.30, 0.38, 1)
	table.insert(UISpecialFrames, "GathererConfigFrame")

	-- 1. Top Header Bar
	frame.Header = UIStyle.CreateHeader(
		frame,
		"Gatherer Reforged  |cff667080—|r  |cffffffff" .. _tr("LABEL_CONFIG") .. "|r",
		133939,
		function() Gatherer.Config.Hide() end
	)
	frame.Header.Badge:SetText("|cff00ff96v" .. tostring(Gatherer.Var.Version or "1.0.0") .. "|r")

	-- 2. Bottom Footer Bar
	frame.Footer = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame.Footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
	frame.Footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
	frame.Footer:SetHeight(36)
	UIStyle.ApplyBox(frame.Footer, 0.10, 0.12, 0.15, 1, 0.20, 0.23, 0.29, 1)

	frame.ReportBtn = UIStyle.CreateButton(frame.Footer, 165, 24, _tr("LABEL_REPORT"), "default", 134327)
	frame.ReportBtn:SetPoint("LEFT", frame.Footer, "LEFT", 8, 0)
	frame.ReportBtn:SetScript("OnClick", function()
		Gatherer.Config.Hide()
		if Gatherer.Report and Gatherer.Report.Show then
			Gatherer.Report.Show()
		end
	end)

	frame.SearchBtn = UIStyle.CreateButton(frame.Footer, 165, 24, _tr("LABEL_DENSITY_REPORT"), "default", 134436)
	frame.SearchBtn:SetPoint("LEFT", frame.ReportBtn, "RIGHT", 8, 0)
	frame.SearchBtn:SetScript("OnClick", function()
		Gatherer.Config.Hide()
		if Gatherer.NodeSearch and Gatherer.NodeSearch.Show then
			Gatherer.NodeSearch.Show()
		end
	end)

	frame.ProfileBadge = frame.Footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.ProfileBadge:SetPoint("LEFT", frame.SearchBtn, "RIGHT", 18, 0)

	frame.DoneBtn = UIStyle.CreateButton(frame.Footer, 100, 24, _tr("DONE"), "primary")
	frame.DoneBtn:SetPoint("RIGHT", frame.Footer, "RIGHT", -8, 0)
	frame.DoneBtn:SetScript("OnClick", function() Gatherer.Config.Hide() end)

	-- 3. Left Vertical Category Sidebar
	frame.Sidebar = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame.Sidebar:SetPoint("TOPLEFT", frame.Header, "BOTTOMLEFT", 10, -8)
	frame.Sidebar:SetPoint("BOTTOMLEFT", frame.Footer, "TOPLEFT", 0, 8)
	frame.Sidebar:SetWidth(210)
	UIStyle.ApplyBox(frame.Sidebar, 0.09, 0.11, 0.14, 1, 0.22, 0.25, 0.32, 1)

	local navTitle = frame.Sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	navTitle:SetPoint("TOPLEFT", frame.Sidebar, "TOPLEFT", 12, -12)
	navTitle:SetText(_trL("CONFIG_SECTION_HEADER_CORE"))
	navTitle:SetTextColor(0.92, 0.78, 0.28)

	local navDiv = frame.Sidebar:CreateTexture(nil, "ARTWORK")
	navDiv:SetPoint("TOPLEFT", navTitle, "BOTTOMLEFT", 0, -4)
	navDiv:SetPoint("RIGHT", frame.Sidebar, "RIGHT", -12, 0)
	navDiv:SetHeight(1)
	navDiv:SetColorTexture(0.22, 0.25, 0.32, 1)

	frame.NavButtons = {}
	local prevBtn = nil
	for _, sec in ipairs(CONFIG_SECTIONS) do
		local nBtn = CreateFrame("Button", nil, frame.Sidebar, BackdropTemplateMixin and "BackdropTemplate" or nil)
		nBtn:SetHeight(32)
		if not prevBtn then
			nBtn:SetPoint("TOPLEFT", frame.Sidebar, "TOPLEFT", 8, -36)
			nBtn:SetPoint("TOPRIGHT", frame.Sidebar, "TOPRIGHT", -8, -36)
		else
			nBtn:SetPoint("TOPLEFT", prevBtn, "BOTTOMLEFT", 0, -4)
			nBtn:SetPoint("TOPRIGHT", prevBtn, "BOTTOMRIGHT", 0, -4)
		end
		prevBtn = nBtn

		local markBar = nBtn:CreateTexture(nil, "OVERLAY")
		markBar:SetPoint("TOPLEFT", nBtn, "TOPLEFT", 1, -1)
		markBar:SetPoint("BOTTOMLEFT", nBtn, "BOTTOMLEFT", 1, 1)
		markBar:SetWidth(3)
		markBar:SetColorTexture(0.95, 0.78, 0.20, 1)
		nBtn.MarkBar = markBar

		local ic = nBtn:CreateTexture(nil, "ARTWORK")
		ic:SetSize(16, 16)
		ic:SetPoint("LEFT", nBtn, "LEFT", 12, 0)
		ic:SetTexture(sec.icon)
		ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		nBtn.Icon = ic

		local lbl = nBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		lbl:SetPoint("LEFT", ic, "RIGHT", 9, 0)
		lbl:SetPoint("RIGHT", nBtn, "RIGHT", -6, 0)
		lbl:SetJustifyH("LEFT")
		lbl:SetText(sec.label())
		nBtn.Label = lbl

		function nBtn:UpdateVisual(hovered)
			if self.isSelected then
				UIStyle.ApplyBox(self, 0.24, 0.20, 0.09, 0.98, 0.85, 0.68, 0.18, 1)
				self.Label:SetTextColor(1, 0.88, 0.30)
				self.MarkBar:Show()
			elseif hovered then
				UIStyle.ApplyBox(self, 0.16, 0.20, 0.27, 0.95, 0.38, 0.44, 0.56, 1)
				self.Label:SetTextColor(1, 1, 1)
				self.MarkBar:Hide()
			else
				UIStyle.ApplyBox(self, 0.12, 0.14, 0.18, 0.90, 0.18, 0.21, 0.27, 1)
				self.Label:SetTextColor(0.78, 0.82, 0.88)
				self.MarkBar:Hide()
			end
		end

		nBtn:SetScript("OnEnter", function(self) self:UpdateVisual(true) end)
		nBtn:SetScript("OnLeave", function(self) self:UpdateVisual(false) end)
		nBtn:SetScript("OnClick", function()
			activeCategory = sec.key
			renderActiveCategory()
		end)

		frame.NavButtons[sec.key] = nBtn
	end

	-- 4. Right Content Area
	frame.Content = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame.Content:SetPoint("TOPLEFT", frame.Sidebar, "TOPRIGHT", 10, 0)
	frame.Content:SetPoint("BOTTOMRIGHT", frame.Footer, "TOPRIGHT", 0, 8)
	UIStyle.ApplyBox(frame.Content, 0.08, 0.09, 0.12, 1, 0.22, 0.25, 0.32, 1)

	frame.Content.Header = CreateFrame("Frame", nil, frame.Content, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame.Content.Header:SetPoint("TOPLEFT", frame.Content, "TOPLEFT", 1, -1)
	frame.Content.Header:SetPoint("TOPRIGHT", frame.Content, "TOPRIGHT", -1, -1)
	frame.Content.Header:SetHeight(32)
	UIStyle.ApplyBox(frame.Content.Header, 0.12, 0.14, 0.19, 1, 0.22, 0.25, 0.32, 1)

	local hIcon = frame.Content.Header:CreateTexture(nil, "ARTWORK")
	hIcon:SetSize(18, 18)
	hIcon:SetPoint("LEFT", frame.Content.Header, "LEFT", 12, 0)
	hIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frame.Content.HeaderIcon = hIcon

	local hTitle = frame.Content.Header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	hTitle:SetPoint("LEFT", hIcon, "RIGHT", 8, 0)
	hTitle:SetTextColor(1, 0.85, 0.25)
	frame.Content.HeaderTitle = hTitle

	frame.Content.Host = CreateFrame("Frame", nil, frame.Content)
	frame.Content.Host:SetPoint("TOPLEFT", frame.Content.Header, "BOTTOMLEFT", 10, -8)
	frame.Content.Host:SetPoint("BOTTOMRIGHT", frame.Content, "BOTTOMRIGHT", -10, 10)

	hostGroup = AceGUI:Create("SimpleGroup")
	hostGroup.type = "GathererOptionsContainer"
	hostGroup:SetLayout("Fill")
	hostGroup.frame:SetParent(frame.Content.Host)
	hostGroup.frame:ClearAllPoints()
	hostGroup.frame:SetAllPoints(frame.Content.Host)
	hostGroup.frame:Show()

	frame:SetScript("OnShow", function()
		renderActiveCategory()
	end)

	UIStyle.RegisterFontListener(function()
		if frame:IsShown() then
			renderActiveCategory()
		end
	end)

	configFrame = frame
	return configFrame
end

-- Override Gatherer.Config Show / Hide / ToggleOptions to use our Modern Dark-Gold Window
function Gatherer.Config.Show()
	ensureRegistered()
	if Gatherer.Report and Gatherer.Report.Hide then
		Gatherer.Report.Hide()
	end
	if Gatherer.NodeSearch and Gatherer.NodeSearch.Hide then
		Gatherer.NodeSearch.Hide()
	end
	local frame = ensureConfigFrame()
	if frame then
		frame:Show()
		renderActiveCategory()
	else
		AceConfigDialog:Open("GathererReforged")
	end
end

function Gatherer.Config.ShowOptions()
	Gatherer.Config.Show()
end

function Gatherer.Config.Hide()
	if configFrame and configFrame:IsShown() then
		configFrame:Hide()
	end
	if registered then
		AceConfigDialog:Close("GathererReforged")
	end
end

function Gatherer.Config.HideOptions()
	Gatherer.Config.Hide()
end

function Gatherer.Config.ToggleOptions()
	ensureRegistered()
	local frame = ensureConfigFrame()
	if frame then
		if frame:IsShown() then
			Gatherer.Config.Hide()
		else
			Gatherer.Config.Show()
		end
	elseif AceConfigDialog.OpenFrames and AceConfigDialog.OpenFrames["GathererReforged"] then
		AceConfigDialog:Close("GathererReforged")
	else
		AceConfigDialog:Open("GathererReforged")
	end
end

-- Register in Blizzard Options on PLAYER_LOGIN
Gatherer.ElvUI = Gatherer.ElvUI or {}
function Gatherer.ElvUI.SkinFrames() end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
	ensureRegistered()
end)

