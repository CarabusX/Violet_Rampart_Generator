local GEO_FEATURE_NAME = "geovent"

local featuresList = {}

for i = 1, #GG.mapgen_geoList do
	local geoSpot = GG.mapgen_geoList[i]

	table.insert(featuresList, {
		name = GEO_FEATURE_NAME,
		x = geoSpot.x,
		z = geoSpot.z,
		rot = math.random(65536)
    })
end

return featuresList
