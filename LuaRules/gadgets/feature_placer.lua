function gadget:GetInfo()
	return {
		name      = "Feature Placer",
		desc      = "Places features for metal spots and geo vents",
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

local GEO_FEATURE_NAME      = "geovent"
local MEX_SPOT_FEATURE_NAME = "mexspot"

local ENABLE_METAL_SPOT_FEATURES = true
local MIN_METAL_FOR_FEATURE = 3.0

--------------------------------------------------------------------------------

local function placeGeoVentFeatures()
	local geoVents = GG.mapgen_geoList or {}

	for i = 1, #geoVents do
		local geo = geoVents[i]
		local posY = Spring.GetGroundHeight(geo.x, geo.z)  -- (smoke is emitted below center for some reason)
		Spring.CreateFeature(GEO_FEATURE_NAME, geo.x, posY, geo.z, math.random(65536))
	end
end

local function placeMetalSpotFeatures()
	local metalSpots = GG.metalSpots or {}

	for i = 1, #metalSpots do
		local spot = metalSpots[i]

		if (not MIN_METAL_FOR_FEATURE) or (MIN_METAL_FOR_FEATURE <= spot.metal) then
			local feature = Spring.CreateFeature(MEX_SPOT_FEATURE_NAME, spot.x, spot.y, spot.z, math.random(65536))
			Spring.SetFeatureAlwaysVisible (feature, true)
			Spring.SetFeatureNoSelect (feature, true)
			Spring.SetFeatureCollisionVolumeData (feature,
				0, 0, 0,
				0, 0, 0,
				0, 0, 0
			)
		end
	end
end

function gadget:Initialize()
	placeGeoVentFeatures()

	if (ENABLE_METAL_SPOT_FEATURES) then
		placeMetalSpotFeatures()
	end

	gadgetHandler:RemoveGadget()
end
