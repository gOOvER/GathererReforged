--[[
	Gatherer Reforged Addon for World of Warcraft(tm).
	Version: 1.0.4
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
Gatherer.Var.Version="1.0.4"
if (Gatherer.Var.Version == "<%".."version%>") then
	Gatherer.Var.Version = "1.0.4-DEV"
end
Gatherer.Version = Gatherer.Var.Version

-- Global variables
Gatherer.Var.NoteUpdateInterval = 0.1
Gatherer.Var.NoteCheckInterval = 5.0
Gatherer.Var.Loaded = false
Gatherer.Var.ClosestCheck = 0.4

Gatherer.Var.UpdateWorldMap = -1

Gatherer.Var.Skills = { }
Gatherer.Var.ZoneData = { }
Gatherer.Var.MainMapItem = { }
