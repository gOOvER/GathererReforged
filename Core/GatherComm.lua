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

local lib = Gatherer.Comm

local function safeRegisterPrefix(prefix)
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

function Gatherer.Comm.OnLoad()
	-- register prefixes
	safeRegisterPrefix("GathX")
	safeRegisterPrefix("Gatherer")
	if Gatherer.Integrations and Gatherer.Integrations.RegisterSharingPrefixes then
		Gatherer.Integrations.RegisterSharingPrefixes()
	end
end

local sendOfferer
local acceptFrom = {}

local commVersion = 2

local lastHarvest = {}
local lastMessage = ""
local lastSentMessage = ""
local lastSentTime = 0

local function isSelfSender(who)
	if not Gatherer.IsSafeString(who) then return false end
	local myName = UnitName("player")
	if not Gatherer.IsSafeString(myName) then return false end
	if who == myName then return true end
	local cleanWho = (who:match("^([^%-]+)") or who):match("^%s*(.-)%s*$")
	local cleanMe = (myName:match("^([^%-]+)") or myName):match("^%s*(.-)%s*$")
	if cleanWho:lower() == cleanMe:lower() then return true end
	-- Support servers with character surnames where UnitName("player") and chat sender may differ by surname
	if cleanWho:lower():sub(1, #cleanMe + 1) == (cleanMe:lower() .. " ") then return true end
	if cleanMe:lower():sub(1, #cleanWho + 1) == (cleanWho:lower() .. " ") then return true end
	if Ambiguate and Ambiguate(who, "none") == myName then return true end
	return false
end
Gatherer.Comm.IsSelfSender = isSelfSender

function Gatherer.Comm.Send( objectId, gatherType, indoorNode, gatherZ, gatherX, gatherY, nodeIndex )
	if ( type(objectId) == "number" ) then
		local zoneToken = Gatherer.ZoneTokens.GetZoneToken(gatherZ)
		
		-- Check if this node has been just broadcast by us
		if not (lastHarvest and lastHarvest.z == zoneToken and lastHarvest.o == objectId and lastHarvest.i == nodeIndex) then
			-- Ok, so lets broadcast this node
			local guildAlert, raidAlert, raidType
			local objName = Gatherer.Util.GetNodeName(objectId) or ""
			local sendMessage = strjoin(";", objectId, tostring(zoneToken), tostring(indoorNode and true or false), gatherX, gatherY, tostring(gatherType or ""), objName)
			sendMessage = strjoin(":", commVersion, sendMessage)
			lastMessage = sendMessage
			lastSentMessage = sendMessage
			lastSentTime = GetTime and GetTime() or 0
			if Gatherer.Config.GetSetting("guild.enable") then
				if ( IsInGuild() ) then
					safeSendAddonMessage("GathX", sendMessage, "GUILD")
					if Gatherer.Integrations and Gatherer.Integrations.BroadcastToExternalAddons then
						Gatherer.Integrations.BroadcastToExternalAddons("GUILD", nil, objectId, gatherType, zoneToken, gatherX, gatherY)
					end
					if (Gatherer.Config.GetSetting("guild.print.send")) then guildAlert = true end
				end
			end
			if (Gatherer.Config.GetSetting("raid.enable")) then
				local groupChannel
				if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) then
					groupChannel = "INSTANCE_CHAT"
					raidType = "GROUP"
				elseif IsInRaid and IsInRaid() then
					groupChannel = "RAID"
					raidType = "GROUP"
				elseif (IsInGroup and IsInGroup()) or (GetNumGroupMembers and GetNumGroupMembers() > 0) then
					groupChannel = "PARTY"
					raidType = "GROUP"
				end
				if groupChannel then
					safeSendAddonMessage("GathX", sendMessage, groupChannel)
					if Gatherer.Integrations and Gatherer.Integrations.BroadcastToExternalAddons then
						Gatherer.Integrations.BroadcastToExternalAddons(groupChannel, nil, objectId, gatherType, zoneToken, gatherX, gatherY)
					end
					if (raidType and Gatherer.Config.GetSetting("raid.print.send")) then raidAlert = true end
				end
			end
			
			if Gatherer.Config.GetSetting("personal.print") then
				Gatherer.Util.ChatPrint(_tr("NODE_ADD", objName))
			end
			if (guildAlert or raidAlert) then
				local whom
				if guildAlert then
					whom = "GUILD"
				else
					whom = raidType
				end
				if (guildAlert and raidAlert) then
					Gatherer.Util.ChatPrint(_tr("COMM_NODE_SEND_TWO", objName, _tr("GUILD"), _tr("GROUP")))
				else
					Gatherer.Util.ChatPrint(_tr("COMM_NODE_SEND", objName, _tr(whom)))
				end
			end
		end
		lastHarvest.z = zoneToken
		lastHarvest.o = objectId
		lastHarvest.i = nodeIndex
	end
end

function Gatherer.Comm.SendMsg( sendType, target, objectId, gatherType, indoorNode, gatherZ, gatherX, gatherY )
	local zoneToken = Gatherer.ZoneTokens.GetZoneToken(gatherZ)
	local objName = Gatherer.Util.GetNodeName(objectId) or ""
	local sendMessage = strjoin(";", objectId, tostring(zoneToken), tostring(indoorNode and true or false), gatherX, gatherY, tostring(gatherType or ""), objName)
	sendMessage = strjoin(":", commVersion, sendMessage)
	lastMessage = sendMessage
	lastSentMessage = sendMessage
	lastSentTime = GetTime and GetTime() or 0
	safeSendAddonMessage("GathX", sendMessage, sendType, target)
end

function Gatherer.Comm.Receive( message, how, who )
	local setting = Gatherer.Config.GetSetting
	local msgtype = "raid"

	-- Ignore our own echoed broadcasts
	if isSelfSender(who) then
		return
	end
	if message == lastSentMessage and lastSentTime > 0 and ((GetTime and GetTime() or 0) - lastSentTime) < 15 then
		return
	end

	-- check if the player is on our sharing blacklist
	local blacklisted = Gatherer.Config.SharingBlacklist_IsPlayerIgnored(who)
	if ( blacklisted ) then
		return
	end

	if ( message ~= lastMessage ) then
		if (how == "GUILD") then msgtype = "guild" end
		if (how == "WHISPER") then
			msgtype = "whisper"
			if not ( acceptFrom[who:lower()] ) then
				return
			end
		elseif ( not (setting(msgtype..".enable") and setting(msgtype..".receive")) ) then
			return
		end
		
		lastMessage = message
		local commVersion, data = strsplit(":", message, 2)
		commVersion = tonumber(commVersion)
		local objectID, zoneToken, gatherX, gatherY, sentType, sentName
		local indoorNode = false
		if ( commVersion == 2 or commVersion == 3 ) then
			objectID, zoneToken, indoorNode, gatherX, gatherY, sentType, sentName = strsplit(";", data)
			objectID = tonumber(objectID)
			indoorNode = (indoorNode == "true" and true or false)
			gatherX = tonumber(gatherX)
			gatherY = tonumber(gatherY)
		end
		local gatherType = objectID and Gatherer.Nodes.Objects[objectID]
		if ( not gatherType and objectID and sentType and sentType ~= "" and Gatherer.Nodes and Gatherer.Nodes.RegisterDynamicNode ) then
			Gatherer.Nodes.RegisterDynamicNode(sentName ~= "" and sentName or ("Node #" .. tostring(objectID)), sentType, nil, objectID)
			gatherType = Gatherer.Nodes.Objects[objectID] or sentType
		end
		zoneToken = Gatherer.ZoneTokens.GetZoneToken(zoneToken)
		if ( objectID and gatherType and zoneToken and gatherX and gatherY ) then
			Gatherer.Storage.MassImportMode = (how == "WHISPER")
			Gatherer.Api.AddGather(objectID, gatherType, indoorNode, who, nil, nil, false, nil, zoneToken, gatherX, gatherY)
			Gatherer.Storage.MassImportMode = false
			if Gatherer.Integrations and Gatherer.Integrations.MirrorNodeToGatherMate2 then
				Gatherer.Integrations.MirrorNodeToGatherMate2(objectID, gatherType, zoneToken, gatherX, gatherY)
			end
			local objName = Gatherer.Util.GetNodeName(objectID);
			if ( how == "WHISPER" ) then
				Gatherer.Report.SendFeedback(who, "RECV", objectID)
			elseif ( setting(msgtype..".print.recv") ) then
				local localizedZoneName = Gatherer.ZoneTokens.ZoneNames[zoneToken]
				if ( not localizedZoneName ) then
					local gatherC, gatherZ = Gatherer.ZoneTokens.GetContinentAndZone(zoneToken)
					if ( gatherC and gatherZ ) then
						localizedZoneName = select(2*gatherZ, GetMapZones(gatherC))
					end
				end
				localizedZoneName = localizedZoneName or tostring(zoneToken)
				local howKey = (how == "INSTANCE_CHAT") and "GROUP" or how
				Gatherer.Util.ChatPrint(_tr("COMM_RECEIVE_NODE", objName, localizedZoneName, who, _tr(howKey)))
			end
		end
		
	end
end

StaticPopupDialogs["GATHERER_COMM_REQUESTSEND"] = {
	text = _trL("MASS_SHARING_GATHERER_COMM_REQUESTSEND"),
	button1 = _trL("YES"),
	button2 = _trL("NO"),
	OnAccept = function()
			StaticPopupDialogs["GATHERER_COMM_REQUESTSEND"].accepted = 1
			Gatherer.Comm.SendFeedback("ACCEPT")
	end,
	OnCancel = function()
			StaticPopupDialogs["GATHERER_COMM_REQUESTSEND"].accepted = -2
			Gatherer.Comm.SendFeedback("REJECT")
	end,
	OnShow = function()
		StaticPopupDialogs["GATHERER_COMM_REQUESTSEND"].accepted = nil
	end,
	OnHide = function()
		if StaticPopupDialogs["GATHERER_COMM_REQUESTSEND"].accepted == nil then
			Gatherer.Comm.SendFeedback("TIMEOUT")
			StaticPopupDialogs["GATHERER_COMM_REQUESTSEND"].accepted = -1
		end
	end,
	timeout = 60,
	whileDead = 1,
	exclusive = 1,
	showAlert = 1,
	hideOnEscape = 1
};

function Gatherer.Comm.SendFeedback(reply)
	safeSendAddonMessage("Gatherer", "SENDNODES:"..reply, "WHISPER", sendOfferer)
	Gatherer.Report.SendFeedback(sendOfferer, reply)
	if (reply == "ACCEPT") then
		acceptFrom[sendOfferer:lower()] = true
		Gatherer.Report.SendFeedback(sendOfferer, "ACCEPTED")
	end
	if (reply ~= "PROMPT") then
		sendOfferer = nil
	end
end

function Gatherer.Comm.General( msg, how, who )
	if ( isSelfSender(who) ) then
		return
	end
	local cmd, a,b,c,d = strsplit(":", msg)
	if ( msg == "VER" ) then
		safeSendAddonMessage("Gatherer", "VER:"..Gatherer.Var.Version, how, who)
	elseif ( cmd == "SENDNODES" ) then
		-- check if the player is on our sharing blacklist
		local blacklisted = Gatherer.Config.SharingBlacklist_IsPlayerIgnored(who)
		if ( blacklisted ) then
			local tmp = sendOfferer
			sendOfferer = who
			Gatherer.Comm.SendFeedback("REJECT")
			sendOfferer = tmp
			return
		end
		if (Gatherer.Report.IsOpen()) then
			if (a == "OFFER") then
				local count = tonumber(b) or 0
				if (count > 0) then
					if (sendOfferer) then
						safeSendAddonMessage("Gatherer", "SENDNODES:BUSY", "WHISPER", who)
					else
						sendOfferer = who
						safeSendAddonMessage("Gatherer", "SENDNODES:PROMPT", "WHISPER", who)
						StaticPopup_Show("GATHERER_COMM_REQUESTSEND", who, count)
					end
				end
			elseif (a == "DONE") then
				if (acceptFrom[who:lower()]) then
					acceptFrom[who:lower()] = nil
					Gatherer.Report.SendFeedback(who, a)
					safeSendAddonMessage("Gatherer", "SENDNODES:COMPLETE", "WHISPER", who)
				end
			elseif (a == "PAUSE") then
				if (acceptFrom[who:lower()]) then
					safeSendAddonMessage("Gatherer", "SENDNODES:CONTINUE", "WHISPER", who)
				end
			elseif (a == "CONTINUE") then
				Gatherer.Report.SendFeedback(who, a)
			elseif (a == "ABORTED") then
				Gatherer.Report.SendFeedback(who, a)
			elseif (a == "COMPLETE") then
				Gatherer.Report.SendFeedback(who, a)
			end
		elseif (a == "OFFER") then
			safeSendAddonMessage("Gatherer", "SENDNODES:CLOSED", "WHISPER", who)
		end
		if (a == "PROMPT" or a == "ACCEPT" or a == "REJECT" or a == "BUSY" or a == "TIMEOUT") then
			Gatherer.Report.SendFeedback(who, a)
		end
	end
end
