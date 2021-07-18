function gadget:GetInfo() return {
	name    = "Ghetto Feature Placer",
	desc    = "because i cant be arsed figuring out how to use the regular one",
	author  = "Sprung",
	date    = "2015",
	license = "PD",
	layer   = math.huge,
	enabled = true,
} end

if (not gadgetHandler:IsSyncedCode()) then return end

function gadget:Initialize()
	local spots = GG.metalSpots or {}
	for i = 1, #spots do
		local spot = spots[i]
		local f = Spring.CreateFeature ("mexspot", spot.x, spot.y, spot.z, math.random(65536), -1)
		Spring.SetFeatureAlwaysVisible (f, true)
		Spring.SetFeatureNoSelect (f, true)
		Spring.SetFeatureCollisionVolumeData (f,
			0, 0, 0,
			0, 0, 0,
			0, 0, 0
		)
	end
end
