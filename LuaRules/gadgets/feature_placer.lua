function gadget:GetInfo()
	return {
		name      = "Feature Placer",
		desc      = "Places features for geo vents",
		author    = "Rafal[ZK], based on code by Gnome, Smoth, Sprung",
		date      = "July 2021",
		license   = "PD",
		layer     = 0,
		enabled   = true  --  loaded by default?
	}
end

if (not gadgetHandler:IsSyncedCode()) then
	return false
end

--------------------------------------------------------------------------------
-- Synced
--------------------------------------------------------------------------------

if (Spring.GetGameFrame() >= 1) then
	return false
end

local GEO_FEATURE_NAME = "geovent"

--------------------------------------------------------------------------------

local function placeGeoVentFeatures()
	local geoVents = GG.mapgen_geoList or {}

	for i = 1, #geoVents do
		local geo = geoVents[i]
		local posY = Spring.GetGroundHeight(geo.x, geo.z)  -- (smoke is emitted below center for some reason)
		Spring.CreateFeature(GEO_FEATURE_NAME, geo.x, posY, geo.z, math.random(65536))
	end
end

function gadget:Initialize()
	placeGeoVentFeatures()

	gadgetHandler:RemoveGadget()
end
