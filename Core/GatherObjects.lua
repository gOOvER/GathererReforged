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

Gatherer = {
	Api = {},
	Categories = {},
	Comm = {},
	Command = {},
	Convert = {},
	Config = {},
	Constants = {},
	DropRates = {},
	Event = {},
	HUD = {},
	Integrations = {},
	Interface = {},
	Locale = {},
	Map = {},
	MapNotes = {},
	MiniNotes = {},
	Nodes = {},
	Notifications = {},
	Plugins = {},
	Scanner = Gatherer and Gatherer.Scanner or {},
	IsSafeString = Gatherer and Gatherer.IsSafeString,
	IsSafeValue = Gatherer and Gatherer.IsSafeValue,
	SpecialCases = {},
	Storage = {},
	Tooltip = {},
	UI = Gatherer and Gatherer.UI or {},
	Util = {},
	Var = {},
	ZoneTokens = {},
}

-- Register with AceAddon-3.0 and embed Ace3 mixins
local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
if AceAddon and not AceAddon:GetAddon("GathererReforged", true) then
	local mixins = {}
	for _, libName in ipairs({ "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceComm-3.0", "AceSerializer-3.0" }) do
		if LibStub(libName, true) then
			table.insert(mixins, libName)
		end
	end
	AceAddon:NewAddon(Gatherer, "GathererReforged", unpack(mixins))
end
