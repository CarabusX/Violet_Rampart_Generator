function gadget:GetInfo()
	return {
		name    = "Fix LOS view colors",
		desc    = "Adjusts LOS view colors so map and minimap are not completely black",
		author  = "Rafal[ZK]",
		date    = "July 2021",
		license = "GPL v3 or later",
		layer   = 1002, -- before Violet Rampart Texture Generator
		enabled = true
	}
end

if (gadgetHandler:IsSyncedCode()) then
	return false
end

--------------------------------------------------------------------------------
-- Unsynced
--------------------------------------------------------------------------------

local LOS_VIEW_ALWAYS_COLOR_MIN = { 0.40, 0.40, 0.40 }
local LOS_VIEW_LOS_COLOR        = { 0.20, 0.20, 0.20 }

local max = math.max

--------------------------------------------------------------------------------

function MaxColorRGB (color1, color2)
	return {
		max(color1[1], color2[1]),
		max(color1[2], color2[2]),
		max(color1[3], color2[3])
	}
end

function EqualsColorRGB (color1, color2)
	return
		(color1[1] == color2[1]) and
		(color1[2] == color2[2]) and
		(color1[3] == color2[3])
end

--------------------------------------------------------------------------------

local function setCorrectLosViewColors()
	local alwaysColor, losColor, radarColor, jamColor, radarColor2 = Spring.GetLosViewColors()
	local alwaysColorUpdated = MaxColorRGB(LOS_VIEW_ALWAYS_COLOR_MIN, alwaysColor)
	local losColorUpdated    = LOS_VIEW_LOS_COLOR

	if (not EqualsColorRGB(alwaysColor, alwaysColorUpdated)) or
	   (not EqualsColorRGB(losColor, losColorUpdated)) then
		Spring.SetLosViewColors(alwaysColorUpdated, losColorUpdated, radarColor, jamColor, radarColor2)
		Spring.Echo("LosViewColors set")
	end
end

--------------------------------------------------------------------------------

local updateLosViewColors = false

function gadget:Initialize()
	setCorrectLosViewColors()
end

function gadget:GameStart()
	updateLosViewColors = true
end

function gadget:DrawGenesis()
	if updateLosViewColors then
		setCorrectLosViewColors()
		updateLosViewColors = false

		gadgetHandler:RemoveGadget()
	end
end
