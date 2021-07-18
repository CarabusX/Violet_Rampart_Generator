function gadget:GetInfo() return {
	name    = "Metal Spot Feature Placer",
	desc    = "Places metal spot features",
	author  = "Sprung",
	date    = "2015",
	license = "PD",
	layer   = math.huge,
	enabled = true,
} end

if (not gadgetHandler:IsSyncedCode()) then
	return false
end

--------------------------------------------------------------------------------
-- Synced
--------------------------------------------------------------------------------

local MEX_SPOT_FEATURE_NAME = "mexspot"

function gadget:Initialize()
	local metalSpots = GG.metalSpots or {}
	for i = 1, #metalSpots do
		local spot = metalSpots[i]
		local feature = Spring.CreateFeature (MEX_SPOT_FEATURE_NAME, spot.x, spot.y, spot.z, math.random(65536), -1)
		Spring.SetFeatureAlwaysVisible (feature, true)
		Spring.SetFeatureNoSelect (feature, true)
		Spring.SetFeatureCollisionVolumeData (feature,
			0, 0, 0,
			0, 0, 0,
			0, 0, 0
		)
	end

	gadgetHandler:RemoveGadget()
end
