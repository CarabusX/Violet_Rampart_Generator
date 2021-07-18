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
