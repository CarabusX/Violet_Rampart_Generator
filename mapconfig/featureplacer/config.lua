local featuresList = {}

for i = 1, #GG.mapgen_geoList do
	local geoSpot = GG.mapgen_geoList[i]

	table.insert(featuresList, {
		name = 'geovent',
		x = geoSpot.x,
		z = geoSpot.y,
		rot = math.random(65536)
    })
end

return {
    unitlist = {},
    buildinglist = {},
    objectlist = featuresList
}
