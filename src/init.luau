--!strict
--Services
--Packages
local Package = script
local Packages = Package.Parent
local Maid = require(Packages:WaitForChild("Maid"))

--Modules
--Types
type Maid = Maid.Maid
--Constants
local LUM_LIMIT = 0.03928
local LUM_DENOM = 12.92
local LUM_OFFSET = 0.055
local LUM_OFFSET_DENOM = 1.055
local R_WEIGHT = 0.2126
local G_WEIGHT = 0.7152
local B_WEIGHT = 0.0722
local L_EXP = 2.4
local MIN_HEX_DIFFERENCE = 100 / 255
local BLACK_COLOR = Color3.fromHex("#000")
local WHITE_COLOR = Color3.fromHex("#FFF")
local CONTRAST_RATIO = 4.5

--Class
-- Types
export type FocusInstance = Model | BasePart | Folder
export type Sketcher = {
	__index: Sketcher,
	_Maid: Maid,
	_RenderMaid: Maid,
	_IsAlive: boolean,
	_Color: Color3, 
	_IsClipped: boolean,
	_IsOutlined: boolean,
	_Transparency: number,
	_TextSize: number,
	_Diameter: number,
	SetLabel: (self: Sketcher, position: Vector3, text: string, color: Color3?, textSize: number?, transparency: number?, isClipped: boolean?, isOutlined: boolean?) -> ((pos: Vector3, txt: string) -> nil), 
	SetHighlight: (self: Sketcher, focus: FocusInstance, color: Color3?, transparency: number?, isClipped: boolean?, isOutlined: boolean?) -> ((focus: FocusInstance) -> nil), 
	SetLine: (self: Sketcher, start: Vector3, finish: Vector3, color: Color3?, diameter: number?, transparency: number?) -> ((start: Vector3, finish: Vector3) -> nil), 
	SetRay: (self: Sketcher, origin: Vector3, direction: Vector3, color: Color3?, diameter: number?, transparency: number?) -> ((origin: Vector3, direction: Vector3) -> nil), 
	SetPoint: (self: Sketcher, origin: Vector3, color: Color3?, diameter: number?, transparency: number?) -> ((origin: Vector3) -> nil),
	Destroy: (self: Sketcher) -> nil,
	Clear: (self: Sketcher) -> nil,
	new: (color: Color3?, diameter: number?, transparency: number?, isClipped: boolean?, isOutlined: boolean?, textSize: number?) -> Sketcher,
}

-- Class
local Sketcher: Sketcher = {} :: any
Sketcher.__index = Sketcher

function getContrastRatio(foreground: Color3, background: Color3): number
	local function getRelativeLuminance(color: Color3): number
		local function solveSpace(v: number): number
			if v < LUM_LIMIT then
				return v / LUM_DENOM
			else
				return ((v + LUM_OFFSET) / LUM_OFFSET_DENOM) ^ L_EXP
			end
		end
		return R_WEIGHT * solveSpace(color.R) + G_WEIGHT * solveSpace(color.G) + B_WEIGHT * solveSpace(color.B)
	end

	local _fH, _fS, fV = foreground:ToHSV()
	local _bH, _bS, bV = background:ToHSV()

	local fLum = getRelativeLuminance(foreground)
	local bLum = getRelativeLuminance(background)

	local lighterRelativeLuminance: number
	local darkerRelativeLuminance: number
	if fV < bV then
		lighterRelativeLuminance = bLum
		darkerRelativeLuminance = fLum
	else
		lighterRelativeLuminance = fLum
		darkerRelativeLuminance = bLum
	end

	return (lighterRelativeLuminance + 0.05) / (darkerRelativeLuminance + 0.05)
end

function checkContrast(
	color: Color3,
	background: Color3
): boolean
	local minRatio = CONTRAST_RATIO
	local ratio = getContrastRatio(color, background)
	return ratio >= minRatio
end

-- https://github.com/alex-page/a11ycolor/blob/main/index.js
function getReadableColor(
	color: Color3,
	background: Color3
): Color3

	-- Check the ratio straight away, if it passes return the value as hex
	if checkContrast(color, background) then
		return color
	end

	-- Ratio didn't pass so we need to find the nearest color
	local isBlackContrast = checkContrast(BLACK_COLOR, background)
	local isWhiteContrast = checkContrast(WHITE_COLOR, background)

	local cH, cS, cV = color:ToHSV()
	local minValue = 0
	local maxValue = 1
	local isDarkColor = false

	-- If black and white both pass on the background
	if isBlackContrast and isWhiteContrast then
		-- Change the min lightness if the color is light
		if cV >= 0.5 then
			minValue = cV
		else -- Change the max lightness if the color is dark
			maxValue = cV
			isDarkColor = true
		end
	elseif isBlackContrast then -- If our colour passes contrast on black
		maxValue = cV
		isDarkColor = true
	else -- Colour doesn't meet contrast pass on black
		minValue = cV
	end

	-- The color to return
	local finalColor: Color3?

	-- Binary search until we find the colour that meets contrast
	local prevColor: Color3?
	while not finalColor do
		local midValue = (minValue + maxValue) / 2
		local midColor = Color3.fromHSV(cH, cS, midValue)
		if checkContrast(midColor, background) then
			if maxValue - minValue <= MIN_HEX_DIFFERENCE then
				finalColor = midColor
			elseif isDarkColor then
				minValue = midValue
			else
				maxValue = midValue
			end
		elseif isDarkColor then
			maxValue = midValue
		else
			minValue = midValue
		end
		if prevColor == midColor then
			break
		end
		prevColor = midColor
	end
	return finalColor or color
end


function Sketcher:Destroy()
	if not self._IsAlive then return end
	self._IsAlive = false
	self._Maid:Destroy()
	local t: any = self
	for k, v in pairs(t) do
		t[k] = nil
	end
	setmetatable(t, nil)
	return nil
end

function Sketcher:Clear()
	self._RenderMaid:DoCleaning()
	return nil
end

function Sketcher:SetLabel(position: Vector3, text: string, color: Color3?, textSize: number?, transparency: number?, isClipped: boolean?, isOutlined: boolean?)
	color = color or self._Color
	assert(color ~= nil)

	isOutlined = if isOutlined == nil then self._IsOutlined else isOutlined
	assert(isOutlined ~= nil)
	
	isClipped = if isClipped == nil then self._IsClipped else isClipped
	assert(isClipped ~= nil)

	transparency = transparency or self._Transparency
	assert(transparency ~= nil)

	textSize = textSize or self._TextSize
	assert(textSize ~= nil)


	local part = self._RenderMaid:GiveTask(Instance.new("Part"))
	part.Shape = Enum.PartType.Ball
	part.Name = "SketcherLabel"
	part.Size = Vector3.new(1,1,1) * 0.05
	part.Position = position
	part.Transparency = 1
	part.Anchored = true
	part.CanTouch = false
	part.CanQuery = false
	part.CanCollide = false
	part.Locked = true
	part.Archivable = false
	part.Parent = workspace.CurrentCamera

	local billboardGui = self._RenderMaid:GiveTask(Instance.new("BillboardGui"))
	billboardGui.Archivable = false
	billboardGui.AlwaysOnTop = not isClipped
	billboardGui.Parent = part

	local textLabel = self._RenderMaid:GiveTask(Instance.new("TextLabel"))
	textLabel.Font = Enum.Font.Code
	textLabel.Text = text
	textLabel.TextSize = textSize
	textLabel.AnchorPoint = Vector2.new(0.5,0.5)
	textLabel.Position = UDim2.fromScale(0.5,0.5)
	textLabel.Size = UDim2.fromScale(0,0)
	textLabel.AutomaticSize = Enum.AutomaticSize.XY
	textLabel.TextTransparency = transparency
	textLabel.Archivable = false

	local contrastColor = getReadableColor(Color3.new(0.5,0.5,0.5), color)

	if isOutlined then
		textLabel.TextColor3 = color
		textLabel.BackgroundTransparency = 1

		local uiStroke = self._RenderMaid:GiveTask(Instance.new("UIStroke"))
		uiStroke.Archivable = false
		uiStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		uiStroke.LineJoinMode = Enum.LineJoinMode.Round
		uiStroke.Thickness = math.max(math.round(textSize * 0.1), 1)
		uiStroke.Transparency = transparency
		uiStroke.Color = contrastColor
		uiStroke.Parent = textLabel
	else
		textLabel.TextColor3 = contrastColor
		textLabel.BackgroundColor3 = color
		textLabel.BackgroundTransparency = transparency

		local uiPadding = self._RenderMaid:GiveTask(Instance.new("UIPadding"))
		uiPadding.Archivable = false
		uiPadding.PaddingTop = UDim.new(0,math.floor(textSize * 0.5))
		uiPadding.PaddingBottom = uiPadding.PaddingTop
		uiPadding.PaddingRight = UDim.new(0,math.floor(textSize * 0.75))
		uiPadding.PaddingLeft = uiPadding.PaddingRight
		uiPadding.Parent = textLabel
	
	end

	textLabel.Parent = billboardGui

	return function(pos: Vector3, txt: string)

	end
end

function Sketcher:SetHighlight(focus: FocusInstance, color: Color3?, transparency: number?, isClipped: boolean?, isOutlined: boolean?)
	color = color or self._Color
	assert(color ~= nil)

	isClipped = if isClipped == nil then self._IsClipped else isClipped
	assert(isClipped ~= nil)

	isOutlined = if isOutlined == nil then self._IsOutlined else isOutlined
	assert(isOutlined ~= nil)

	transparency = transparency or self._Transparency
	assert(transparency ~= nil)

	local highlight: Highlight = self._RenderMaid:GiveTask(Instance.new("Highlight"))
	highlight.Name = "SketcherHighlight"
	highlight.DepthMode = if isClipped then Enum.HighlightDepthMode.Occluded else Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = color
	highlight.FillTransparency = transparency
	highlight.OutlineColor = Color3.new(1,1,1)
	highlight.OutlineTransparency = highlight.FillTransparency
	highlight.Adornee = focus
	highlight.Archivable = false
	highlight.Parent = workspace.CurrentCamera

	return function(foc: FocusInstance)
		highlight.Adornee = foc
	end
end

function Sketcher:SetLine(start: Vector3, finish: Vector3, color: Color3?, diameter: number?, transparency: number?)
	color = color or self._Color
	assert(color ~= nil)

	diameter = diameter or self._Diameter
	assert(diameter ~= nil)

	transparency = transparency or self._Transparency
	assert(transparency ~= nil)

	local dist = (start - finish).Magnitude

	local part = self._RenderMaid:GiveTask(Instance.new("Part"))
	part.Shape = Enum.PartType.Cylinder
	part.Name = "SketcherVector"
	part.Size = Vector3.new(dist, diameter, diameter)
	part.CFrame = CFrame.new(start, finish) * CFrame.new(0,0,-dist/2) * CFrame.Angles(0,math.rad(90),0)
	part.Transparency = transparency
	part.Color = color
	part.Anchored = true
	part.CanTouch = false
	part.CanQuery = false
	part.CanCollide = false
	part.Locked = true
	part.Archivable = false
	part.Parent = workspace.CurrentCamera

	if part.Transparency == 0 then
		self:SetHighlight(part, color, transparency, false, true)
	end

	return function(begin: Vector3, finish: Vector3)
		local mag = (start - finish).Magnitude
		part.Size = Vector3.new(mag, diameter, diameter)
		part.CFrame = CFrame.new(start, finish) * CFrame.new(0,0,mag) * CFrame.Angles(0,math.rad(90),0)
	end
end

function Sketcher:SetRay(origin: Vector3, direction: Vector3, color: Color3?, diameter: number?, transparency: number?)
	local updateLine = self:SetLine(origin, origin + direction, color, diameter, transparency)
	return function(ori: Vector3, dir: Vector3)
		updateLine(ori, origin + direction)
	end
end
function Sketcher:SetPoint(origin: Vector3, color: Color3?, diameter: number?, transparency: number?)
	color = color or self._Color
	assert(color ~= nil)

	diameter = diameter or self._Diameter
	assert(diameter ~= nil)

	transparency = transparency or self._Transparency
	assert(transparency ~= nil)

	local part = self._RenderMaid:GiveTask(Instance.new("Part"))
	part.Shape = Enum.PartType.Ball
	part.Name = "SketcherPoint"
	part.Size = Vector3.new(1,1,1) * diameter
	part.Position = origin
	part.Transparency = transparency
	part.Color = color
	part.Anchored = true
	part.CanTouch = false
	part.CanQuery = false
	part.CanCollide = false
	part.Locked = true
	part.Archivable = false
	part.Parent = workspace.CurrentCamera

	if part.Transparency == 0 then
		self:SetHighlight(part, color, transparency, false, true)
	end


	return function(pos: Vector3)
		part.Position = pos
	end
end

function Sketcher.new(color: Color3?, diameter: number?, transparency: number?, isClipped: boolean?, isOutlined: boolean?, textSize: number?)
	local maid = Maid.new()

	local self: Sketcher = setmetatable({}, Sketcher) :: any
	self._IsAlive = true
	self._Maid = maid
	self._RenderMaid = maid:GiveTask(Maid.new())
	self._Color = color or Color3.new(1,0,0)
	self._Diameter = diameter or 0.2
	self._Transparency = transparency or 0.35
	self._TextSize = textSize or 11
	self._IsOutlined = if isOutlined == nil then false else isOutlined
	self._IsClipped = if isClipped == nil then false else isClipped

	return self
end

return Sketcher

