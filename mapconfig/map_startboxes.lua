local startBoxes = {}

for i = 1, #GG.mapgen_startBoxes do
	local startBox = GG.mapgen_startBoxes[i]
	local nameLong  = "StartBox" .. i
    local nameShort = "StartBox" .. i
	
	startBoxes[#startBoxes + 1] = {
		boxes = {
			startBox.box
		},
		startpoints = {
			startBox.startPoint
		},
		nameLong  = nameLong, 
		nameShort = nameShort
	}	
end

return startBoxes, { 2, 11 }
