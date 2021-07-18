local startBoxes = {}

if (GG.mapgen_startBoxes) then
	local mapgen_startBoxes = GG.mapgen_startBoxes

	for i = 1, #mapgen_startBoxes do
		local startBox = mapgen_startBoxes[i]
		local nameLong  = "StartBox " .. startBox.symbol
		local nameShort = "StartBox " .. startBox.symbol
		
		startBoxes[i - 1] = {  -- startboxes start with 0 index
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
end

return startBoxes, { 2, 11 }
