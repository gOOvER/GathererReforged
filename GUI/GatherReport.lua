--[[
	Gatherer Reforged Addon for World of Warcraft(tm).
	Modernized Gatherables Report UI & Shared UI Style Library
	Version: 1.0.0
	Author: gOOvER
	License: GNU General Public License v3.0 (GPL-3.0)
]]

local THROTTLE_COUNT = 10
local THROTTLE_RATE = 0.25

-- Data indices
local ZONE      = 1
local ID        = 2
local INDEX     = 3
local POSX      = 4
local POSY      = 5
local COUNT     = 6
local HARVESTED = 7
local INSPECTED = 8
local SOURCE    = 9
local GTYPE     = 10
local INDOORS   = 11

local _tr = Gatherer.Locale.Tr
local _trL = Gatherer.Locale.TrLocale
local Map = Gatherer.Map

--------------------------------------------------------------------------------
-- Shared Modern Dark-Gold UI Style Library (Gatherer.UIStyle)
--------------------------------------------------------------------------------
Gatherer.UIStyle = Gatherer.UIStyle or {}
local UIStyle = Gatherer.UIStyle

local WHITE_TEX = "Interface\\Buttons\\WHITE8X8"

UIStyle._fontListeners = UIStyle._fontListeners or {}

function UIStyle.GetFontSize()
	local sz = 13
	if Gatherer and Gatherer.Config and Gatherer.Config.GetSetting then
		sz = tonumber(Gatherer.Config.GetSetting("ui.fontSize", 13)) or 13
	end
	return math.min(math.max(math.floor(sz), 10), 18)
end

function UIStyle.SetFontSize(size)
	size = math.min(math.max(math.floor(tonumber(size) or 13), 10), 18)
	if Gatherer and Gatherer.Config and Gatherer.Config.SetSetting then
		Gatherer.Config.SetSetting("ui.fontSize", size)
	end
	for _, fn in ipairs(UIStyle._fontListeners) do
		pcall(fn, size)
	end
	return size
end

function UIStyle.RegisterFontListener(fn)
	if type(fn) == "function" then
		table.insert(UIStyle._fontListeners, fn)
	end
end

function UIStyle.ApplyFont(fontString, delta, overrideFlags)
	if not fontString or not fontString.GetFont or not fontString.SetFont then return end
	local fontPath, _, fontFlags = fontString:GetFont()
	if not fontPath then
		fontPath, _, fontFlags = GameFontNormal:GetFont()
	end
	if fontPath then
		local targetSize = math.max(9, UIStyle.GetFontSize() + (delta or 0))
		fontString:SetFont(fontPath, targetSize, overrideFlags ~= nil and overrideFlags or (fontFlags or ""))
	end
end

function UIStyle.ApplyBox(f, bgR, bgG, bgB, bgA, brR, brG, brB, brA)
	if not f.SetBackdrop then return end
	f:SetBackdrop({
		bgFile = WHITE_TEX,
		edgeFile = WHITE_TEX,
		tile = false,
		edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	f:SetBackdropColor(bgR or 0.08, bgG or 0.09, bgB or 0.12, bgA or 0.96)
	f:SetBackdropBorderColor(brR or 0.24, brG or 0.27, brB or 0.34, brA or 1)
end

function UIStyle.CreateHeader(parent, titleText, iconTexture, onClose)
	local header = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	header:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, -1)
	header:SetHeight(38)
	UIStyle.ApplyBox(header, 0.11, 0.13, 0.17, 1, 0.22, 0.25, 0.32, 1)

	-- Subtle gold bottom accent line
	local accent = header:CreateTexture(nil, "OVERLAY")
	accent:SetColorTexture(0.79, 0.64, 0.15, 0.85)
	accent:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
	accent:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
	accent:SetHeight(1)

	local icon = header:CreateTexture(nil, "ARTWORK")
	icon:SetSize(22, 22)
	icon:SetPoint("LEFT", header, "LEFT", 12, 0)
	icon:SetTexture(iconTexture or 133939)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
	title:SetText(titleText)
	title:SetTextColor(1, 0.85, 0.25)
	header.Title = title

	local badge = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	badge:SetPoint("RIGHT", header, "RIGHT", -46, 0)
	badge:SetTextColor(0.65, 0.72, 0.82)
	header.Badge = badge

	local closeBtn = CreateFrame("Button", nil, header, BackdropTemplateMixin and "BackdropTemplate" or nil)
	closeBtn:SetSize(26, 26)
	closeBtn:SetPoint("RIGHT", header, "RIGHT", -8, 0)
	UIStyle.ApplyBox(closeBtn, 0.18, 0.14, 0.16, 1, 0.38, 0.26, 0.30, 1)
	local closeIcon = closeBtn:CreateTexture(nil, "OVERLAY")
	closeIcon:SetSize(14, 14)
	closeIcon:SetPoint("CENTER", 0, 0)
	closeIcon:SetTexture("Interface\\Buttons\\UI-StopButton")
	closeIcon:SetVertexColor(0.92, 0.75, 0.78, 1)
	closeBtn.Icon = closeIcon
	closeBtn:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.68, 0.18, 0.22, 1)
		self:SetBackdropBorderColor(0.95, 0.35, 0.40, 1)
		closeIcon:SetVertexColor(1, 1, 1, 1)
	end)
	closeBtn:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.18, 0.14, 0.16, 1)
		self:SetBackdropBorderColor(0.38, 0.26, 0.30, 1)
		closeIcon:SetVertexColor(0.92, 0.75, 0.78, 1)
	end)
	closeBtn:SetScript("OnClick", onClose)
	header.CloseButton = closeBtn

	-- Font Size Controls (A- | 13pt | A+)
	local fontPlusBtn = UIStyle.CreateButton(header, 28, 24, "A+", "default")
	fontPlusBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
	header.FontPlusBtn = fontPlusBtn

	local fontIndicator = CreateFrame("Frame", nil, header, BackdropTemplateMixin and "BackdropTemplate" or nil)
	fontIndicator:SetSize(38, 24)
	fontIndicator:SetPoint("RIGHT", fontPlusBtn, "LEFT", -3, 0)
	UIStyle.ApplyBox(fontIndicator, 0.08, 0.10, 0.13, 1, 0.22, 0.25, 0.32, 1)
	local fontLabel = fontIndicator:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fontLabel:SetPoint("CENTER", 0, 0)
	fontLabel:SetTextColor(0.95, 0.80, 0.28)
	fontLabel:SetText(UIStyle.GetFontSize() .. "pt")
	header.FontLabel = fontLabel

	local fontMinusBtn = UIStyle.CreateButton(header, 28, 24, "A-", "default")
	fontMinusBtn:SetPoint("RIGHT", fontIndicator, "LEFT", -3, 0)
	header.FontMinusBtn = fontMinusBtn

	badge:ClearAllPoints()
	badge:SetPoint("RIGHT", fontMinusBtn, "LEFT", -10, 0)

	fontMinusBtn:SetScript("OnClick", function()
		UIStyle.SetFontSize(UIStyle.GetFontSize() - 1)
	end)
	fontPlusBtn:SetScript("OnClick", function()
		UIStyle.SetFontSize(UIStyle.GetFontSize() + 1)
	end)

	UIStyle.RegisterFontListener(function(newSize)
		if header.FontLabel then
			header.FontLabel:SetText(newSize .. "pt")
		end
		UIStyle.ApplyFont(title, 2)
		UIStyle.ApplyFont(badge, 0)
	end)
	UIStyle.ApplyFont(title, 2)
	UIStyle.ApplyFont(badge, 0)

	header:EnableMouse(true)
	header:SetScript("OnMouseDown", function()
		if parent:IsMovable() then parent:StartMoving() end
	end)
	header:SetScript("OnMouseUp", function()
		if parent:IsMovable() then
			parent:StopMovingOrSizing()
			if parent.OnMoved then parent:OnMoved() end
		end
	end)

	return header
end

function UIStyle.FormatIconText(iconTexture, text)
	if not iconTexture then return text or "" end
	if type(iconTexture) == "number" or not tostring(iconTexture):find("UI%-GroupLoot") then
		return string.format("|T%s:13:13:0:0:64:64:5:59:5:59|t  %s", tostring(iconTexture), text or "")
	else
		return string.format("|T%s:13:13:0:0|t  %s", tostring(iconTexture), text or "")
	end
end

function UIStyle.CreateButton(parent, width, height, text, variant, iconTexture)
	local btn = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	if width then btn:SetWidth(width) end
	btn:SetHeight(height or 26)
	btn._iconTexture = iconTexture

	local schemes = {
		default = {
			bg = { 0.15, 0.18, 0.23, 1 },
			br = { 0.27, 0.31, 0.39, 1 },
			hoverBg = { 0.21, 0.25, 0.33, 1 },
			hoverBr = { 0.83, 0.68, 0.21, 1 },
			txt = { 0.92, 0.94, 0.98 },
		},
		primary = {
			bg = { 0.24, 0.20, 0.09, 1 },
			br = { 0.78, 0.63, 0.16, 1 },
			hoverBg = { 0.33, 0.27, 0.12, 1 },
			hoverBr = { 0.98, 0.82, 0.28, 1 },
			txt = { 1.00, 0.88, 0.35 },
		},
		danger = {
			bg = { 0.24, 0.11, 0.13, 1 },
			br = { 0.62, 0.22, 0.26, 1 },
			hoverBg = { 0.36, 0.15, 0.18, 1 },
			hoverBr = { 0.90, 0.32, 0.36, 1 },
			txt = { 1.00, 0.65, 0.68 },
		},
	}
	local s = schemes[variant or "default"] or schemes.default
	btn._scheme = s

	UIStyle.ApplyBox(btn, s.bg[1], s.bg[2], s.bg[3], s.bg[4], s.br[1], s.br[2], s.br[3], s.br[4])

	btn._minWidth = width or 60
	btn._baseHeight = height or 26

	local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("CENTER", btn, "CENTER", 0, 0)
	UIStyle.ApplyFont(label, 0)
	label:SetText(UIStyle.FormatIconText(iconTexture, text))
	label:SetTextColor(s.txt[1], s.txt[2], s.txt[3])
	btn.Label = label

	function btn:UpdateSize()
		UIStyle.ApplyFont(label, 0)
		local textW = label:GetStringWidth() or 0
		if textW > 0 then
			self:SetWidth(math.max(self._minWidth or 60, math.ceil(textW + 24)))
		elseif self._minWidth then
			self:SetWidth(self._minWidth)
		end
		self:SetHeight(math.max(self._baseHeight or 26, UIStyle.GetFontSize() + 13))
	end

	function btn:SetText(t)
		label:SetText(UIStyle.FormatIconText(self._iconTexture, t))
		self:UpdateSize()
	end
	function btn:GetFontString()
		return label
	end
	btn:UpdateSize()
	UIStyle.RegisterFontListener(function()
		if btn and btn.UpdateSize then
			btn:UpdateSize()
		end
	end)

	local function refreshState(self, hovered)
		if not self:IsEnabled() then
			self:SetBackdropColor(0.10, 0.11, 0.14, 0.85)
			self:SetBackdropBorderColor(0.18, 0.20, 0.25, 0.85)
			label:SetTextColor(0.42, 0.45, 0.50)
		elseif hovered then
			self:SetBackdropColor(s.hoverBg[1], s.hoverBg[2], s.hoverBg[3], s.hoverBg[4])
			self:SetBackdropBorderColor(s.hoverBr[1], s.hoverBr[2], s.hoverBr[3], s.hoverBr[4])
			label:SetTextColor(1, 1, 1)
		else
			self:SetBackdropColor(s.bg[1], s.bg[2], s.bg[3], s.bg[4])
			self:SetBackdropBorderColor(s.br[1], s.br[2], s.br[3], s.br[4])
			label:SetTextColor(s.txt[1], s.txt[2], s.txt[3])
		end
	end

	btn:SetScript("OnEnter", function(self) refreshState(self, true) end)
	btn:SetScript("OnLeave", function(self) refreshState(self, false) end)
	hooksecurefunc(btn, "Enable", function(self) refreshState(self, false) end)
	hooksecurefunc(btn, "Disable", function(self) refreshState(self, false) end)

	return btn
end

function UIStyle.CreateFilterPill(parent, text, defaultActive, onToggle)
	local pill = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	pill:SetHeight(24)
	pill.active = (defaultActive ~= false)

	local dotBorder = pill:CreateTexture(nil, "BORDER")
	dotBorder:SetSize(8, 8)
	dotBorder:SetPoint("LEFT", pill, "LEFT", 9, 0)
	dotBorder:SetColorTexture(0.05, 0.06, 0.08, 1)

	local dot = pill:CreateTexture(nil, "ARTWORK")
	dot:SetSize(6, 6)
	dot:SetPoint("CENTER", dotBorder, "CENTER", 0, 0)
	pill.Dot = dot

	local label = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", dotBorder, "RIGHT", 6, 0)
	label:SetText(text)
	pill.Label = label

	local function updateVisual()
		if pill.active then
			UIStyle.ApplyBox(pill, 0.13, 0.23, 0.19, 1, 0.18, 0.68, 0.46, 1)
			dot:SetColorTexture(0.0, 1.0, 0.59, 1)
			label:SetTextColor(0.92, 0.98, 0.95)
		else
			UIStyle.ApplyBox(pill, 0.12, 0.14, 0.18, 1, 0.24, 0.27, 0.34, 1)
			dot:SetColorTexture(0.32, 0.36, 0.44, 1)
			label:SetTextColor(0.56, 0.60, 0.68)
		end
		local w = math.max((label:GetStringWidth() or 50) + 32, 68)
		pill:SetWidth(w)
	end

	function pill:SetChecked(val)
		pill.active = (val and val ~= 0) and true or false
		updateVisual()
	end
	function pill:GetChecked()
		return pill.active
	end

	pill:SetScript("OnClick", function(self)
		self.active = not self.active
		updateVisual()
		if onToggle then onToggle(self, self.active) end
	end)
	pill:SetScript("OnEnter", function(self)
		if self.active then
			self:SetBackdropBorderColor(0.30, 0.88, 0.62, 1)
		else
			self:SetBackdropBorderColor(0.45, 0.50, 0.62, 1)
		end
	end)
	pill:SetScript("OnLeave", function() updateVisual() end)

	updateVisual()
	return pill
end

function UIStyle.CreateEditBox(parent, width, height, placeholderText)
	local box = CreateFrame("EditBox", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	if width then box:SetWidth(width) end
	box:SetHeight(height or 26)
	box:SetAutoFocus(false)
	box:ClearFocus()
	box:SetMultiLine(false)
	box:SetTextInsets(8, 22, 4, 4)
	box:SetFontObject("GameFontHighlightSmall")
	UIStyle.ApplyBox(box, 0.06, 0.07, 0.09, 1, 0.24, 0.27, 0.35, 1)

	local placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	placeholder:SetPoint("LEFT", box, "LEFT", 8, 0)
	placeholder:SetText(placeholderText or "")
	placeholder:SetTextColor(0.45, 0.50, 0.58)
	box.Placeholder = placeholder

	local clearBtn = CreateFrame("Button", nil, box)
	clearBtn:SetSize(16, 16)
	clearBtn:SetPoint("RIGHT", box, "RIGHT", -4, 0)
	local clearTxt = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	clearTxt:SetPoint("CENTER", 0, 0)
	clearTxt:SetText("×")
	clearTxt:SetTextColor(0.55, 0.60, 0.68)
	clearBtn:Hide()
	clearBtn:SetScript("OnEnter", function() clearTxt:SetTextColor(1, 0.35, 0.35) end)
	clearBtn:SetScript("OnLeave", function() clearTxt:SetTextColor(0.55, 0.60, 0.68) end)
	clearBtn:SetScript("OnClick", function()
		box:SetText("")
		box:ClearFocus()
		if box.OnValueChanged then box:OnValueChanged("") end
	end)
	box.ClearButton = clearBtn

	local function syncPlaceholder()
		local txt = box:GetText() or ""
		if txt == "" and not box:HasFocus() then
			placeholder:Show()
		else
			placeholder:Hide()
		end
		if txt ~= "" then
			clearBtn:Show()
		else
			clearBtn:Hide()
		end
	end

	box:SetScript("OnEditFocusGained", function(self)
		self:SetBackdropBorderColor(0.83, 0.68, 0.21, 1)
		placeholder:Hide()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		self:SetBackdropBorderColor(0.24, 0.27, 0.35, 1)
		syncPlaceholder()
	end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnTextChanged", function(self, userInput)
		syncPlaceholder()
		if self.OnValueChanged then self:OnValueChanged(self:GetText() or "", userInput) end
	end)

	syncPlaceholder()
	return box
end

--------------------------------------------------------------------------------
-- Gatherer.Report Window Implementation
--------------------------------------------------------------------------------
Gatherer.Report = {}
local private = {}
local public = Gatherer.Report

local REPORT_LINES = 21
local ROW_HEIGHT = 21

private.frame = CreateFrame("Frame", "GathererReportFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
local frame = private.frame
public.Frame = frame

function public.Show()
	Gatherer.Config.HideOptions()
	if Gatherer.NodeSearch and Gatherer.NodeSearch.Hide then
		Gatherer.NodeSearch.Hide()
	end
	frame:Show()
	public.NeedsUpdate(0.05)
end

function public.Hide()
	frame:Hide()
end

function public.Toggle()
	if frame:IsShown() then
		public.Hide()
	else
		public.Show()
	end
end

function public.IsOpen()
	return frame:IsVisible() and true or false
end

private.needsUpdate = false
function public.NeedsUpdate(delay)
	private.needsUpdate = delay or 0.1
end

frame:Hide()
frame:SetSize(960, 620)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
frame:SetFrameStrata("DIALOG")
frame:SetToplevel(true)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
UIStyle.ApplyBox(frame, 0.07, 0.08, 0.11, 0.97, 0.26, 0.30, 0.38, 1)
frame:SetScript("OnShow", function() public.NeedsUpdate(0.02) end)
table.insert(UISpecialFrames, "GathererReportFrame")

function frame:OnMoved()
	Gatherer.Config.SetSetting("report.left", frame:GetLeft())
	Gatherer.Config.SetSetting("report.top", frame:GetTop())
end

frame.Updater = CreateFrame("Frame", nil, UIParent)
frame.Updater:SetScript("OnUpdate", function(_, delay) private.UpdateHandler(delay) end)

-- 1. Top Header Bar
frame.Header = UIStyle.CreateHeader(
	frame,
	"Gatherer Reforged  |cff667080—|r  |cffffffff" .. _tr("REPORT_TITLE") .. "|r",
	133939,
	function() public.Hide() end
)

-- 2. Toolbar (Search Input + Filter Scope Pills + Category Tabs)
frame.Toolbar = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
frame.Toolbar:SetPoint("TOPLEFT", frame.Header, "BOTTOMLEFT", 10, -8)
frame.Toolbar:SetPoint("TOPRIGHT", frame.Header, "BOTTOMRIGHT", -10, -8)
frame.Toolbar:SetHeight(36)
UIStyle.ApplyBox(frame.Toolbar, 0.10, 0.12, 0.15, 1, 0.20, 0.23, 0.29, 1)

frame.SearchBox = UIStyle.CreateEditBox(frame.Toolbar, 240, 24, _tr("UI_SEARCH_PLACEHOLDER"))
frame.SearchBox:SetPoint("LEFT", frame.Toolbar, "LEFT", 8, 0)
frame.SearchBox.OnValueChanged = function()
	public.NeedsUpdate(0.15)
end

-- Scope Filter Pills (populated via Gatherer.Report.AddButton in ReportFilters.lua)
private.LastButton = nil
private.SearchButtons = {}
function public.AddButton(buttonName, filterFn)
	if private.SearchButtons[buttonName] then
		private.SearchButtons[buttonName].filter = filterFn
		return
	end
	local pill = UIStyle.CreateFilterPill(frame.Toolbar, buttonName, true, function(self)
		private.SearchButtonClickHandler(self)
	end)
	if private.LastButton then
		pill:SetPoint("LEFT", private.LastButton, "RIGHT", 5, 0)
	else
		pill:SetPoint("LEFT", frame.SearchBox, "RIGHT", 10, 0)
	end
	pill.filter = filterFn
	pill.active = true
	private.SearchButtons[buttonName] = pill
	private.LastButton = pill
end

-- Category Filter Buttons on the right side of the Toolbar
private.activeCategory = "ALL"
private.categoryButtons = {}
local CATEGORIES = {
	{ key = "ALL",  label = _tr("UI_CAT_ALL") },
	{ key = "HERB", label = _tr("UI_CAT_HERB") },
	{ key = "MINE", label = _tr("UI_CAT_MINE") },
	{ key = "OPEN", label = _tr("UI_CAT_OPEN") },
	{ key = "ARCH", label = _tr("UI_CAT_ARCH") },
}

local prevCatBtn
for i = #CATEGORIES, 1, -1 do
	local cat = CATEGORIES[i]
	local cBtn = CreateFrame("Button", nil, frame.Toolbar, BackdropTemplateMixin and "BackdropTemplate" or nil)
	cBtn:SetHeight(24)
	local cLbl = cBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cLbl:SetPoint("CENTER", 0, 0)
	cLbl:SetText(cat.label)
	cBtn:SetWidth(math.max((cLbl:GetStringWidth() or 40) + 16, 52))
	if not prevCatBtn then
		cBtn:SetPoint("RIGHT", frame.Toolbar, "RIGHT", -8, 0)
	else
		cBtn:SetPoint("RIGHT", prevCatBtn, "LEFT", -4, 0)
	end
	prevCatBtn = cBtn
	cBtn.key = cat.key
	cBtn.Label = cLbl
	cBtn:SetScript("OnClick", function()
		private.activeCategory = cat.key
		private.UpdateCategoryButtons()
		public.NeedsUpdate(0.02)
	end)
	private.categoryButtons[cat.key] = cBtn
end

function private.UpdateCategoryButtons()
	for key, btn in pairs(private.categoryButtons) do
		if key == private.activeCategory then
			UIStyle.ApplyBox(btn, 0.26, 0.21, 0.09, 1, 0.85, 0.68, 0.18, 1)
			btn.Label:SetTextColor(1, 0.88, 0.30)
		else
			UIStyle.ApplyBox(btn, 0.13, 0.15, 0.19, 1, 0.22, 0.25, 0.32, 1)
			btn.Label:SetTextColor(0.68, 0.72, 0.80)
		end
	end
end
private.UpdateCategoryButtons()

-- 3. Bottom Footer Bar
frame.Footer = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
frame.Footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
frame.Footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
frame.Footer:SetHeight(36)
UIStyle.ApplyBox(frame.Footer, 0.10, 0.12, 0.15, 1, 0.20, 0.23, 0.29, 1)

frame.NodeSearch = UIStyle.CreateButton(frame.Footer, 165, 24, _tr("LABEL_DENSITY_REPORT"), "default", 134436)
frame.NodeSearch:SetPoint("LEFT", frame.Footer, "LEFT", 8, 0)
frame.NodeSearch:SetScript("OnClick", function()
	frame:Hide()
	Gatherer.NodeSearch.Show()
end)

frame.Config = UIStyle.CreateButton(frame.Footer, 145, 24, _tr("LABEL_CONFIG"), "default", 136243)
frame.Config:SetPoint("LEFT", frame.NodeSearch, "RIGHT", 8, 0)
frame.Config:SetScript("OnClick", function()
	public.Hide()
	Gatherer.Config.Show()
end)

frame.FooterHint = frame.Footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
frame.FooterHint:SetPoint("LEFT", frame.Config, "RIGHT", 16, 0)
frame.FooterHint:SetText(_tr("UI_FOOTER_HINT_REPORT"))

frame.Done = UIStyle.CreateButton(frame.Footer, 100, 24, _tr("DONE"), "primary")
frame.Done:SetPoint("RIGHT", frame.Footer, "RIGHT", -8, 0)
frame.Done:SetScript("OnClick", function() public.Hide() end)

-- 4. Results Table Container (Left)
frame.Results = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
frame.Results:SetPoint("TOPLEFT", frame.Toolbar, "BOTTOMLEFT", 0, -8)
frame.Results:SetPoint("BOTTOMLEFT", frame.Footer, "TOPLEFT", 0, 8)
frame.Results:SetWidth(705)
UIStyle.ApplyBox(frame.Results, 0.08, 0.09, 0.12, 1, 0.22, 0.25, 0.32, 1)

-- Table Column Header Bar
frame.Results.Header = CreateFrame("Frame", nil, frame.Results, BackdropTemplateMixin and "BackdropTemplate" or nil)
frame.Results.Header:SetPoint("TOPLEFT", frame.Results, "TOPLEFT", 1, -1)
frame.Results.Header:SetPoint("TOPRIGHT", frame.Results, "TOPRIGHT", -1, -1)
frame.Results.Header:SetHeight(26)
UIStyle.ApplyBox(frame.Results.Header, 0.13, 0.15, 0.20, 1, 0.22, 0.25, 0.32, 1)

local COLUMNS = {
	{ key = "Type",   title = _tr("REPORT_COLUMN_HEADER_TYPE"),   x = 10,  width = 215, align = "LEFT",  sortKey = "name" },
	{ key = "Region", title = _tr("REPORT_COLUMN_HEADER_REGION"), x = 230, width = 165, align = "LEFT",  sortKey = "zone" },
	{ key = "Coords", title = _tr("UI_COL_COORDS"),               x = 400, width = 72,  align = "LEFT",  sortKey = "coords" },
	{ key = "Dist",   title = _tr("REPORT_COLUMN_HEADER_DIST"),   x = 476, width = 56,  align = "RIGHT", sortKey = "dist" },
	{ key = "Value",  title = _tr("UI_COL_VALUE"),                x = 538, width = 78,  align = "RIGHT", sortKey = "value" },
	{ key = "Source", title = _tr("REPORT_COLUMN_HEADER_SOURCE"), x = 622, width = 60,  align = "LEFT",  sortKey = "source" },
}

private.sortBy = "name"
private.sortAsc = true

for _, col in ipairs(COLUMNS) do
	local colBtn = CreateFrame("Button", nil, frame.Results.Header)
	colBtn:SetPoint("TOPLEFT", frame.Results.Header, "TOPLEFT", col.x, 0)
	colBtn:SetSize(col.width, 26)
	local colTxt = colBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	if col.align == "RIGHT" then
		colTxt:SetPoint("RIGHT", colBtn, "RIGHT", -4, 0)
	else
		colTxt:SetPoint("LEFT", colBtn, "LEFT", 2, 0)
	end
	colTxt:SetJustifyH(col.align)
	colTxt:SetText(col.title)
	colTxt:SetTextColor(0.92, 0.78, 0.30)
	colBtn.Text = colTxt
	colBtn:SetScript("OnEnter", function() colTxt:SetTextColor(1, 0.95, 0.65) end)
	colBtn:SetScript("OnLeave", function() colTxt:SetTextColor(0.92, 0.78, 0.30) end)
	colBtn:SetScript("OnClick", function()
		if private.sortBy == col.sortKey then
			private.sortAsc = not private.sortAsc
		else
			private.sortBy = col.sortKey
			private.sortAsc = true
		end
		private.SortCurrentResults()
		private.UpdateResults()
	end)
	frame.Results.Header[col.key] = colBtn
end

-- ScrollFrame
frame.Results.Scroll = CreateFrame("ScrollFrame", "GathererResultsScroll", frame.Results, "FauxScrollFrameTemplate")
frame.Results.Scroll:SetPoint("TOPLEFT", frame.Results.Header, "BOTTOMLEFT", 0, -2)
frame.Results.Scroll:SetPoint("BOTTOMRIGHT", frame.Results, "BOTTOMRIGHT", -24, 4)
frame.Results.Scroll:SetScript("OnVerticalScroll", function(self, offset)
	FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function()
		private.UpdateResults()
	end)
end)

-- Empty State Overlay
frame.Results.EmptyState = CreateFrame("Frame", nil, frame.Results)
frame.Results.EmptyState:SetPoint("TOPLEFT", frame.Results.Header, "BOTTOMLEFT", 0, 0)
frame.Results.EmptyState:SetPoint("BOTTOMRIGHT", frame.Results, "BOTTOMRIGHT", 0, 0)
frame.Results.EmptyState:Hide()

local emptyTitle = frame.Results.EmptyState:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
emptyTitle:SetPoint("CENTER", frame.Results.EmptyState, "CENTER", 0, 26)
emptyTitle:SetText(_tr("UI_EMPTY_TITLE"))

local emptySub = frame.Results.EmptyState:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
emptySub:SetPoint("TOP", emptyTitle, "BOTTOM", 0, -8)
emptySub:SetText(_tr("UI_EMPTY_SUB"))

local emptyImportBtn = UIStyle.CreateButton(frame.Results.EmptyState, 280, 28, _tr("UI_IMPORT_GM2_BTN"), "primary", 132596)
emptyImportBtn:SetPoint("TOP", emptySub, "BOTTOM", 0, -16)
emptyImportBtn:SetScript("OnClick", function()
	if Gatherer.Integrations and Gatherer.Integrations.ImportGatherMate2 then
		Gatherer.Integrations.ImportGatherMate2(true)
		public.NeedsUpdate(0.05)
	end
end)

-- Table Rows
for i = 1, REPORT_LINES do
	local row = CreateFrame("Button", nil, frame.Results)
	frame.Results[i] = row
	row:SetHeight(ROW_HEIGHT)
	if i == 1 then
		row:SetPoint("TOPLEFT", frame.Results.Header, "BOTTOMLEFT", 1, -2)
	else
		row:SetPoint("TOPLEFT", frame.Results[i - 1], "BOTTOMLEFT", 0, 0)
	end
	row:SetPoint("RIGHT", frame.Results, "RIGHT", -24, 0)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	row.Bg = row:CreateTexture(nil, "BACKGROUND")
	row.Bg:SetAllPoints()
	if i % 2 == 0 then
		row.Bg:SetColorTexture(0.09, 0.11, 0.14, 0.90)
	else
		row.Bg:SetColorTexture(0.07, 0.08, 0.11, 0.90)
	end

	row.MarkBar = row:CreateTexture(nil, "OVERLAY")
	row.MarkBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.MarkBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.MarkBar:SetWidth(3)
	row.MarkBar:SetColorTexture(0.95, 0.78, 0.20, 1)
	row.MarkBar:Hide()

	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(16, 16)
	row.Icon:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local function makeCell(x, w, align)
		local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", row, "LEFT", x, 0)
		fs:SetWidth(w)
		fs:SetHeight(ROW_HEIGHT - 2)
		fs:SetJustifyH(align or "LEFT")
		if fs.SetWordWrap then fs:SetWordWrap(false) end
		return fs
	end

	row.Type   = makeCell(28,  195, "LEFT")
	row.Region = makeCell(230, 165, "LEFT")
	row.Coords = makeCell(400, 72,  "LEFT")
	row.Dist   = makeCell(476, 56,  "RIGHT")
	row.Value  = makeCell(538, 78,  "RIGHT")
	row.Source = makeCell(622, 60,  "LEFT")

	local function updateRowBg(self, hovered)
		if self.isMarked then
			self.Bg:SetColorTexture(0.24, 0.20, 0.09, 0.95)
			self.MarkBar:Show()
		elseif hovered then
			self.Bg:SetColorTexture(0.16, 0.20, 0.27, 0.95)
			self.MarkBar:Hide()
		elseif i % 2 == 0 then
			self.Bg:SetColorTexture(0.09, 0.11, 0.14, 0.90)
			self.MarkBar:Hide()
		else
			self.Bg:SetColorTexture(0.07, 0.08, 0.11, 0.90)
			self.MarkBar:Hide()
		end
	end
	row.UpdateRowBg = updateRowBg

	row:SetScript("OnEnter", function(self)
		if not self.pos then return end
		updateRowBg(self, true)
		local resultsData = private.results.data[self.pos]
		if resultsData then
			local z, n, idx, x, y, count = resultsData[ZONE], resultsData[ID], resultsData[INDEX], resultsData[POSX], resultsData[POSY], resultsData[COUNT]
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:ClearLines()
			GameTooltip:AddLine(Gatherer.Util.GetNodeName(n), 1, 0.85, 0.25)
			GameTooltip:AddDoubleLine(_tr("UI_TOOLTIP_ZONE"), tostring(Gatherer.ZoneTokens.ZoneNames[z] or z), 0.75, 0.80, 0.88, 1, 1, 1)
			GameTooltip:AddDoubleLine(_tr("UI_TOOLTIP_COORDS"), string.format("%.1f, %.1f", x * 100, y * 100), 0.75, 0.80, 0.88, 1, 1, 1)
			GameTooltip:AddDoubleLine(_tr("UI_TOOLTIP_HARVESTED"), tostring(count or 1) .. "x", 0.75, 0.80, 0.88, 0, 1, 0.6)
			if Gatherer.Integrations and Gatherer.Integrations.GetNodeValue then
				local unitPrice, _, priceSource = Gatherer.Integrations.GetNodeValue(n)
				if unitPrice and unitPrice > 0 then
					GameTooltip:AddDoubleLine(string.format(_tr("UI_TOOLTIP_MARKET_VALUE"), tostring(priceSource or "AH")), Gatherer.Integrations.FormatMoney(unitPrice), 0.75, 0.80, 0.88, 1, 1, 1)
				end
			end
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(_tr("UI_TOOLTIP_LEFT_CLICK_MARK"), 0.7, 0.7, 0.7)
			GameTooltip:AddLine(_tr("UI_TOOLTIP_RIGHT_CLICK_WAYPOINT"), 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		updateRowBg(self, false)
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self, button)
		local pos = self.pos
		if not pos then return end
		local resultsData = private.results.data[pos]
		if not resultsData then return end
		local z, n, idx, x, y, s, g, indoor =
			resultsData[ZONE], resultsData[ID], resultsData[INDEX],
			resultsData[POSX], resultsData[POSY], resultsData[SOURCE],
			resultsData[GTYPE], resultsData[INDOORS]

		if button == "RightButton" or IsShiftKeyDown() then
			local mapID = Gatherer.ZoneTokens.GetZoneMapIDAndFloor(z)
			local nodeName = Gatherer.Util.GetNodeName(n)
			if mapID and x and y then
				if _G.TomTom and type(_G.TomTom.AddWaypoint) == "function" then
					pcall(_G.TomTom.AddWaypoint, _G.TomTom, mapID, x, y, { title = nodeName, from = "GathererReforged" })
					Gatherer.Util.ChatPrint(string.format(_tr("UI_WAYPOINT_TOMTOM_SET"), nodeName, x * 100, y * 100))
				elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
					pcall(function()
						C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
						if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
							C_SuperTrack.SetSuperTrackedUserWaypoint(true)
						end
					end)
					Gatherer.Util.ChatPrint(string.format(_tr("UI_WAYPOINT_MAP_SET"), nodeName, x * 100, y * 100))
				end
			end
			return
		end

		local sig = strjoin(":", z, n, idx, g, tostring(indoor))
		if private.results.mark[sig] then
			private.results.mark[sig] = nil
		else
			private.results.mark[sig] = strjoin(":", x, y)
		end
		private.UpdateResults()
	end)
end

-- 5. Right Sidebar (Actions, Mass-Sharing & Session Summary)
frame.Actions = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
frame.Actions:SetPoint("TOPLEFT", frame.Results, "TOPRIGHT", 10, 0)
frame.Actions:SetPoint("BOTTOMRIGHT", frame.Footer, "TOPRIGHT", 0, 8)
UIStyle.ApplyBox(frame.Actions, 0.09, 0.11, 0.14, 1, 0.22, 0.25, 0.32, 1)

local function createSectionTitle(parent, yOffset, text)
	local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOffset)
	lbl:SetText(text)
	lbl:SetTextColor(0.92, 0.78, 0.28)
	local div = parent:CreateTexture(nil, "ARTWORK")
	div:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -4)
	div:SetPoint("RIGHT", parent, "RIGHT", -12, 0)
	div:SetHeight(1)
	div:SetColorTexture(0.22, 0.25, 0.32, 1)
	return lbl
end

-- Section A: Selection Controls
createSectionTitle(frame.Actions, -12, _tr("UI_SIDEBAR_SELECTION"))

frame.Actions.SelectCount = frame.Actions:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
frame.Actions.SelectCount:SetPoint("TOPLEFT", frame.Actions, "TOPLEFT", 12, -34)
frame.Actions.SelectCount:SetPoint("RIGHT", frame.Actions, "RIGHT", -12, 0)
frame.Actions.SelectCount:SetJustifyH("LEFT")
frame.Actions.SelectCount:SetText(_tr("REPORT_MARKED_NODES_COUNT", 0))

frame.Actions.SelectAll = UIStyle.CreateButton(frame.Actions, nil, 25, _tr("REPORT_MARK_THESE"), "default")
frame.Actions.SelectAll:SetPoint("TOPLEFT", frame.Actions, "TOPLEFT", 12, -54)
frame.Actions.SelectAll:SetPoint("RIGHT", frame.Actions, "RIGHT", -12, 0)
frame.Actions.SelectAll:SetScript("OnClick", function()
	for pos = 1, private.results.size do
		local resultsData = private.results.data[pos]
		local z, n, i, x, y, _, g, indoor = resultsData[ZONE], resultsData[ID], resultsData[INDEX], resultsData[POSX], resultsData[POSY], resultsData[SOURCE], resultsData[GTYPE], resultsData[INDOORS]
		local sig = strjoin(":", z, n, i, g, tostring(indoor))
		private.results.mark[sig] = strjoin(":", x, y)
	end
	private.UpdateResults()
end)

frame.Actions.SelectNone = UIStyle.CreateButton(frame.Actions, nil, 25, _tr("REPORT_UNMARK_THESE"), "default")
frame.Actions.SelectNone:SetPoint("TOPLEFT", frame.Actions.SelectAll, "BOTTOMLEFT", 0, -5)
frame.Actions.SelectNone:SetPoint("RIGHT", frame.Actions, "RIGHT", -12, 0)
frame.Actions.SelectNone:SetScript("OnClick", function()
	for pos = 1, private.results.size do
		local resultsData = private.results.data[pos]
		local z, n, i, _, _, _, g, indoor = resultsData[ZONE], resultsData[ID], resultsData[INDEX], resultsData[POSX], resultsData[POSY], resultsData[SOURCE], resultsData[GTYPE], resultsData[INDOORS]
		local sig = strjoin(":", z, n, i, g, tostring(indoor))
		private.results.mark[sig] = nil
	end
	private.UpdateResults()
end)

frame.Actions.SelectClear = UIStyle.CreateButton(frame.Actions, nil, 25, _tr("REPORT_UNMARK_ALL"), "default")
frame.Actions.SelectClear:SetPoint("TOPLEFT", frame.Actions.SelectNone, "BOTTOMLEFT", 0, -5)
frame.Actions.SelectClear:SetPoint("RIGHT", frame.Actions, "RIGHT", -12, 0)
frame.Actions.SelectClear:SetScript("OnClick", function()
	for sig in pairs(private.results.mark) do
		private.results.mark[sig] = nil
	end
	private.UpdateResults()
end)

-- Section B: Whisper Mass-Sharing & Deletion
createSectionTitle(frame.Actions, -152, _tr("UI_SIDEBAR_TRANSFER"))

frame.Actions.SendEdit = UIStyle.CreateEditBox(frame.Actions, nil, 26, _tr("UI_SEND_PLAYER_PLACEHOLDER"))
frame.Actions.SendEdit:SetPoint("TOPLEFT", frame.Actions, "TOPLEFT", 12, -176)
frame.Actions.SendEdit:SetPoint("RIGHT", frame.Actions, "RIGHT", -12, 0)

StaticPopupDialogs["GATHERER_REPORT_TRANSMIT"] = {
	text = _trL("MASS_SHARING_GATHERER_REPORT_TRANSMIT"),
	button1 = _trL("YES"),
	button2 = _trL("NO"),
	OnAccept = function()
		local dialog = StaticPopupDialogs["GATHERER_REPORT_TRANSMIT"]
		Gatherer.Report.ConfirmNodeTransmit(dialog.who, dialog.howmany)
	end,
	timeout = 0,
	whileDead = 1,
	exclusive = 1,
	showAlert = 1,
	hideOnEscape = 1,
}

local function safeSendAddonMessage(prefix, text, chatType, target)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		pcall(C_ChatInfo.SendAddonMessage, prefix, text, chatType, target)
	elseif _G.SendAddonMessage then
		pcall(_G.SendAddonMessage, prefix, text, chatType, target)
	end
end

function public.ConfirmNodeTransmit(who, howmany)
	howmany = tonumber(howmany) or 0
	if who and howmany > 0 then
		safeSendAddonMessage("Gatherer", ("SENDNODES:OFFER:%d"):format(howmany), "WHISPER", who)
		private.sendingTo = who:lower()
	end
end

frame.Actions.SendSelected = UIStyle.CreateButton(frame.Actions, nil, 26, _tr("REPORT_SEND_MARKED"), "primary", 133464)
frame.Actions.SendSelected:SetPoint("TOPLEFT", frame.Actions.SendEdit, "BOTTOMLEFT", 0, -6)
frame.Actions.SendSelected:SetPoint("RIGHT", frame.Actions, "RIGHT", -12, 0)
frame.Actions.SendSelected:SetScript("OnClick", function(me)
	local who = (frame.Actions.SendEdit:GetText() or ""):trim()
	if who ~= "" then
		StaticPopupDialogs["GATHERER_REPORT_TRANSMIT"].howmany = me.count
		StaticPopupDialogs["GATHERER_REPORT_TRANSMIT"].who = who
		StaticPopup_Show("GATHERER_REPORT_TRANSMIT", me.count, who)
	end
end)
frame.Actions.SendSelected:Disable()

StaticPopupDialogs["GATHERER_REPORT_DELETE"] = {
	text = _trL("REPORT_DELETE_CONFIRMATION"),
	button1 = _trL("YES"),
	button2 = _trL("NO"),
	OnAccept = function()
		Gatherer.Report.ConfirmNodeDeletes()
	end,
	timeout = 0,
	whileDead = 1,
	exclusive = 1,
	showAlert = 1,
	hideOnEscape = 1,
}

function public.ConfirmNodeDeletes()
	local deleteList = {}
	for sig, data in pairs(private.results.mark) do
		local z, n, i, g, indoor = strsplit(":", sig)
		local x, y = strsplit(":", data)
		z = tonumber(z) or z; n = tonumber(n) or n; i = tonumber(i); x = tonumber(x); y = tonumber(y); indoor = (indoor == "true")
		local px, py = Gatherer.Storage.GetNodeInfo(z, g, i)
		if px and py and math.abs(x - px) < 0.001 and math.abs(y - py) < 0.001 then
			table.insert(deleteList, { z, n, g, i })
		end
	end
	table.sort(deleteList, function(a, b) return a[4] > b[4] end)
	for i = 1, #deleteList do
		Gatherer.Storage.RemoveGatherFromNode(unpack(deleteList[i]))
	end
end

frame.Actions.DeleteSelected = UIStyle.CreateButton(frame.Actions, nil, 26, _tr("REPORT_DELETE_MARKED"), "danger", "Interface\\Buttons\\UI-GroupLoot-Pass-Up")
frame.Actions.DeleteSelected:SetPoint("TOPLEFT", frame.Actions.SendSelected, "BOTTOMLEFT", 0, -8)
frame.Actions.DeleteSelected:SetPoint("RIGHT", frame.Actions, "RIGHT", -12, 0)
frame.Actions.DeleteSelected:SetScript("OnClick", function(me)
	StaticPopup_Show("GATHERER_REPORT_DELETE", me.count)
end)
frame.Actions.DeleteSelected:Disable()

frame.Actions.SendStatus = frame.Actions:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
frame.Actions.SendStatus:SetPoint("TOPLEFT", frame.Actions.DeleteSelected, "BOTTOMLEFT", 0, -8)
frame.Actions.SendStatus:SetPoint("RIGHT", frame.Actions, "RIGHT", -12, 0)
frame.Actions.SendStatus:SetJustifyH("LEFT")
frame.Actions.SendStatus:SetTextColor(0.35, 0.75, 1.0)
frame.Actions.SendStatus:SetText("")

-- Section C: Live Session & Quick Import Card
createSectionTitle(frame.Actions, -315, _tr("UI_SIDEBAR_SESSION"))

frame.Actions.SessionSummary = frame.Actions:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
frame.Actions.SessionSummary:SetPoint("TOPLEFT", frame.Actions, "TOPLEFT", 12, -340)
frame.Actions.SessionSummary:SetPoint("RIGHT", frame.Actions, "RIGHT", -12, 0)
frame.Actions.SessionSummary:SetJustifyH("LEFT")
frame.Actions.SessionSummary:SetSpacing(3)

frame.Actions.ImportGM2Btn = UIStyle.CreateButton(frame.Actions, nil, 25, _tr("UI_IMPORT_GM2_SHORT"), "default", 132596)
frame.Actions.ImportGM2Btn:SetPoint("TOPLEFT", frame.Actions, "TOPLEFT", 12, -412)
frame.Actions.ImportGM2Btn:SetPoint("RIGHT", frame.Actions, "RIGHT", -12, 0)
frame.Actions.ImportGM2Btn:SetScript("OnClick", function()
	if Gatherer.Integrations and Gatherer.Integrations.ImportGatherMate2 then
		Gatherer.Integrations.ImportGatherMate2(true)
		public.NeedsUpdate(0.05)
	end
end)

frame.Actions.MarkTip = frame.Actions:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
frame.Actions.MarkTip:SetPoint("TOPLEFT", frame.Actions.ImportGM2Btn, "BOTTOMLEFT", 0, -10)
frame.Actions.MarkTip:SetPoint("RIGHT", frame.Actions, "RIGHT", -12, 0)
frame.Actions.MarkTip:SetPoint("BOTTOM", frame.Actions, "BOTTOM", 0, 10)
frame.Actions.MarkTip:SetJustifyV("TOP")
frame.Actions.MarkTip:SetJustifyH("LEFT")
frame.Actions.MarkTip:SetTextColor(0.52, 0.56, 0.64)
frame.Actions.MarkTip:SetText(_tr("REPORT_MARKING_NOTE"))

local tip = {}
local function setStatus(status, noTip)
	frame.Actions.SendStatus:SetText(status or "")
	if noTip == true then return end
	while #tip > 12 do table.remove(tip, 1) end
	table.insert(tip, status)
	frame.Actions.MarkTip:SetText(strjoin("\n", unpack(tip)))
end

--------------------------------------------------------------------------------
-- Filtering, Sorting & Updating Results
--------------------------------------------------------------------------------
private.results = {
	size = 0,
	data = {},
	mark = {},
}

function private.SortCurrentResults()
	local size = private.results.size
	if size <= 1 then return end
	local list = {}
	for i = 1, size do
		list[i] = private.results.data[i]
	end
	local sortBy = private.sortBy
	local asc = private.sortAsc
	table.sort(list, function(a, b)
		local va, vb
		if sortBy == "zone" then
			va = tostring(Gatherer.ZoneTokens.ZoneNames[a[ZONE]] or a[ZONE] or "")
			vb = tostring(Gatherer.ZoneTokens.ZoneNames[b[ZONE]] or b[ZONE] or "")
		elseif sortBy == "coords" then
			va = (a[POSX] or 0) * 1000 + (a[POSY] or 0)
			vb = (b[POSX] or 0) * 1000 + (b[POSY] or 0)
		elseif sortBy == "dist" then
			va = a[12] or 999999
			vb = b[12] or 999999
		elseif sortBy == "value" then
			va = a[13] or 0
			vb = b[13] or 0
		elseif sortBy == "source" then
			va = tostring(a[SOURCE] or "")
			vb = tostring(b[SOURCE] or "")
		else
			va = tostring(Gatherer.Util.GetNodeName(a[ID]) or "")
			vb = tostring(Gatherer.Util.GetNodeName(b[ID]) or "")
		end
		if va == vb then
			return (a[INDEX] or 0) < (b[INDEX] or 0)
		end
		if asc then
			return va < vb
		else
			return va > vb
		end
	end)
	for i = 1, size do
		private.results.data[i] = list[i]
	end
end

function private.UpdateResults()
	local size = private.results.size
	frame.Header.Badge:SetText(string.format(_tr("UI_BADGE_NODES"), size))

	if size == 0 then
		frame.Results.EmptyState:Show()
		frame.Results.Scroll:Hide()
	else
		frame.Results.EmptyState:Hide()
	end

	local offset = 0
	if size <= REPORT_LINES then
		frame.Results.Scroll:Hide()
	else
		frame.Results.Scroll:Show()
		FauxScrollFrame_Update(frame.Results.Scroll, size, REPORT_LINES, ROW_HEIGHT)
		offset = FauxScrollFrame_GetOffset(frame.Results.Scroll)
	end

	for line = 1, REPORT_LINES do
		local row = frame.Results[line]
		local pos = offset + line
		if pos > size then
			row.pos = nil
			row.isMarked = false
			row:Hide()
		else
			local resultsData = private.results.data[pos]
			local z, n, i, x, y, s, g, indoor =
				resultsData[ZONE], resultsData[ID], resultsData[INDEX],
				resultsData[POSX], resultsData[POSY], resultsData[SOURCE],
				resultsData[GTYPE], resultsData[INDOORS]

			local d = resultsData[12]
			local val = resultsData[13] or 0
			local tex = Gatherer.Util.GetGatherTexture(n)
			local sig = strjoin(":", z, n, i, g, tostring(indoor))

			row.pos = pos
			row.isMarked = private.results.mark[sig] ~= nil
			row.Icon:SetTexture(tex)
			row.Type:SetText(Gatherer.Util.GetNodeName(n))
			row.Region:SetText(Gatherer.ZoneTokens.ZoneNames[z] or tostring(z))
			row.Coords:SetText(string.format("|cffb0b8c4%.1f, %.1f|r", (x or 0) * 100, (y or 0) * 100))
			row.Dist:SetText(d and d < 999990 and string.format("%d", d) or "|cff555c68—|r")
			row.Value:SetText(val > 0 and Gatherer.Integrations and Gatherer.Integrations.FormatMoney(val) or "|cff555c68—|r")
			row.Source:SetText(s ~= "" and s or _tr("UI_SOURCE_OWN"))
			row:UpdateRowBg(false)
			row:Show()
		end
	end

	local markcount = 0
	for sig, loc in pairs(private.results.mark) do
		local z, n, i, g, indoor = strsplit(":", sig)
		local x, y = strsplit(":", loc)
		z = tonumber(z) or z; n = tonumber(n) or n; i = tonumber(i); x = tonumber(x); y = tonumber(y); indoor = (indoor == "true")
		local px, py = Gatherer.Storage.GetNodeInfo(z, g, i)
		if px and py and math.abs(x - px) < 0.001 and math.abs(y - py) < 0.001 then
			markcount = markcount + 1
		else
			private.results.mark[sig] = nil
		end
	end

	if markcount > 0 then
		frame.Actions.SendSelected:Enable()
		frame.Actions.DeleteSelected:Enable()
	else
		frame.Actions.SendSelected:Disable()
		frame.Actions.DeleteSelected:Disable()
	end
	frame.Actions.SendSelected.count = markcount
	frame.Actions.DeleteSelected.count = markcount
	frame.Actions.SelectCount:SetText(_tr("REPORT_MARKED_NODES_COUNT", markcount))

	-- Update Live Session Summary in Sidebar
	if Gatherer.Integrations and Gatherer.Integrations.Session then
		local sum = Gatherer.Integrations.Session.GetSummary()
		local mins = math.floor(sum.elapsed / 60)
		local secs = sum.elapsed % 60
		frame.Actions.SessionSummary:SetText(string.format(
			_tr("UI_SESSION_SUMMARY_FMT"),
			mins, secs, sum.nodes, sum.nodesPerHour,
			Gatherer.Integrations.FormatMoney(sum.totalValue),
			Gatherer.Integrations.FormatMoney(sum.goldPerHour)
		))
	end
end

function GathererResultsScroll()
	private.UpdateResults()
end

local function filter(searchString, ...)
	local show = false
	local f, s, var = string.gmatch(searchString, "%S+")
	while true do
		local match = f(s, var)
		var = match
		if var == nil then
			break
		end

		local firstChar = match:sub(1, 1)
		local mustMatch, mustNotMatch = false, false
		if firstChar == "+" then
			mustMatch = true
			match = match:sub(2)
		elseif firstChar == "-" then
			mustNotMatch = true
			match = match:sub(2)
		end

		if match:sub(1, 1) == '"' then
			local nextToken = f(s, var)
			while nextToken do
				match = match .. " " .. nextToken
				if nextToken:sub(-1) == '"' then
					break
				end
				nextToken = f(s, var)
			end
			match = match:sub(2, #match - 1)
		end

		local tokenShow = false
		for _, button in pairs(private.SearchButtons) do
			if button.active and button.filter(match, ...) then
				if mustNotMatch then
					return false
				end
				show = true
				tokenShow = true
				break
			end
		end
		if mustMatch and not tokenShow then
			return false
		end
	end
	return show
end

function public.SetSearchFilter(searchText, categoryKey)
	if categoryKey then
		private.activeCategory = categoryKey
		private.UpdateCategoryButtons()
	end
	if searchText ~= nil then
		frame.SearchBox:SetText(searchText)
	end
	public.NeedsUpdate(0.02)
end

function public.UpdateDisplay()
	local parameter = frame.SearchBox:GetText() or ""
	local activeCat = private.activeCategory or "ALL"

	private.results.size = 0
	local storage = Gatherer.Storage
	local pc, pz, px, py = Map:GetCurrentPlayerPosition()

	for _, zone in storage.GetAreaIndices() do
		local mapID, mapFloor = Gatherer.ZoneTokens.GetZoneMapIDAndFloor(zone)
		for _, gType in pairs(Gatherer.Constants.SupportedGatherTypes) do
			if activeCat == "ALL" or activeCat == gType then
				for index, posX, posY, inspected, indoors in storage.ZoneGatherNodes(zone, gType) do
					for _, id, count, harvested, source in storage.GetNodeGatherNames(zone, gType, index) do
						if source == "REQUIRE" then
							source = _tr("NOTE_UNSKILLED")
						elseif source == "IMPORTED" then
							source = _tr("NOTE_IMPORTED")
						elseif not source then
							source = ""
						end

						if (parameter == "") or filter(parameter, zone, id, index, posX, posY, count, harvested, inspected, source, gType) then
							local size = private.results.size + 1
							if not private.results.data[size] then
								private.results.data[size] = {}
							end
							local data = private.results.data[size]
							data[ZONE]      = zone
							data[ID]        = id
							data[INDEX]     = index
							data[POSX]      = posX
							data[POSY]      = posY
							data[COUNT]     = count
							data[HARVESTED] = harvested
							data[INSPECTED] = inspected
							data[SOURCE]    = source
							data[GTYPE]     = gType
							data[INDOORS]   = indoors
							data[12]        = (mapID and pc and px and Map:ComputeDistance(mapID, mapFloor or 0, posX, posY, pc, pz, px, py)) or 999999
							data[13]        = (Gatherer.Integrations and Gatherer.Integrations.GetNodeValue and select(1, Gatherer.Integrations.GetNodeValue(id))) or 0
							private.results.size = size
						end
					end
				end
			end
		end
	end
	private.needsUpdate = false
	private.SortCurrentResults()
	private.UpdateResults()
end

function private.SearchButtonClickHandler(button)
	button.active = button:GetChecked() and true or false
	public.NeedsUpdate(0.05)
end

local checkUpdate = 0
function private.UpdateHandler(delay)
	if frame:IsVisible() and private.needsUpdate then
		private.needsUpdate = private.needsUpdate - delay
		if private.needsUpdate < 0 then
			private.needsUpdate = false
			public.UpdateDisplay()
		end
	end
	checkUpdate = checkUpdate + delay
	if checkUpdate > THROTTLE_RATE then
		private.SendNodes()
		checkUpdate = 0
	end
end

private.queue = {}
function public.SendFeedback(who, action)
	if not who then return end

	if private.sendingTo and who:lower() == private.sendingTo then
		if action == "PROMPT" then
			setStatus(_tr("MASS_SHARING_ASKING"))
		elseif action == "ACCEPT" then
			setStatus(_tr("MASS_SHARING_SENDING"))
			local list = {}
			for sig, data in pairs(private.results.mark) do
				table.insert(list, sig .. ":" .. data)
			end
			table.insert(private.queue, { to = who, list = list, pos = 1 })
		elseif action == "REJECT" then
			setStatus(_tr("MASS_SHARING_REJECT"))
		elseif action == "TIMEOUT" then
			setStatus(_tr("MASS_SHARING_TIMEOUT"))
		elseif action == "BUSY" then
			setStatus(_tr("MASS_SHARING_BUSY"))
		elseif action == "CLOSED" then
			setStatus(_tr("MASS_SHARING_CLOSED"))
		elseif action == "COMPLETE" then
			setStatus(_tr("MASS_SHARING_COMPLETE"))
		elseif action == "CONTINUE" then
			if private.queue and private.queue[1] and private.queue[1].paused then
				private.queue[1].paused = nil
			end
		end
	end
	if private.recvFrom and who:lower() == private.recvFrom:lower() then
		if action == "RECV" then
			setStatus(_tr("MASS_SHARING_RECEIVED_COUNT", private.recvCount), true)
			private.recvCount = private.recvCount + 1
		elseif action == "DONE" then
			setStatus(_tr("MASS_SHARING_DONE", private.recvCount))
			private.recvFrom = nil
			private.recvCount = 0
		elseif action == "ABORTED" then
			setStatus(_tr("MASS_SHARING_ABORTED", private.recvCount))
			private.recvFrom = nil
			private.recvCount = 0
		end
		private.UpdateResults()
	end
	if action == "ACCEPTED" then
		setStatus(_tr("MASS_SHARING_ACCEPTED"))
		private.recvFrom = who
		private.recvCount = 0
	end
end

function private.SendNodes()
	if private.queue and private.queue[1] then
		local q = private.queue[1]
		local who = q.to
		if q.paused then
			if time() - q.paused > 30 then
				table.remove(private.queue, 1)
				safeSendAddonMessage("Gatherer", "SENDNODES:ABORTED", "WHISPER", who)
				setStatus(_tr("MASS_SHARING_ABORT"))
			end
			return
		end
		local size = #(q.list)
		local start = q.pos
		local limit = math.min(size, start + THROTTLE_COUNT)
		for pos = start, limit do
			local z, n, i, g, indoor, x, y = strsplit(":", q.list[pos])
			z = tonumber(z) or z; n = tonumber(n) or n; i = tonumber(i); x = tonumber(x); y = tonumber(y); indoor = (indoor == "true")
			local px, py = Gatherer.Storage.GetNodeInfo(z, g, i)
			if px and py and math.abs(x - px) < 0.001 and math.abs(y - py) < 0.001 then
				Gatherer.Comm.SendMsg("WHISPER", who, n, g, indoor, z, x, y)
			end
			setStatus(_tr("MASS_SHARING_SENT", pos - 1), true)
			q.pos = pos
		end
		if limit == size then
			table.remove(private.queue, 1)
			safeSendAddonMessage("Gatherer", "SENDNODES:DONE", "WHISPER", who)
		else
			safeSendAddonMessage("Gatherer", "SENDNODES:PAUSE", "WHISPER", who)
			q.paused = time()
		end
	end
end
