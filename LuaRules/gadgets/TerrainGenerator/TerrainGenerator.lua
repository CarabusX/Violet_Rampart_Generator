local min   = math.min
local max   = math.max
local floor = math.floor
local ceil  = math.ceil

-- Localize variables

local mapSizeX = Game.mapSizeX
local mapSizeZ = Game.mapSizeZ

local squareSize     = Game.squareSize
local halfSquareSize = squareSize / 2
local NUM_BLOCKS_X   = mapSizeX / squareSize
local NUM_BLOCKS_Z   = mapSizeZ / squareSize

local MAP_SQUARE_SIZE   = EXPORT.MAP_SQUARE_SIZE
local NUM_SQUARES_X     = mapSizeX / MAP_SQUARE_SIZE
local NUM_SQUARES_Z     = mapSizeZ / MAP_SQUARE_SIZE
local BLOCKS_PER_SQUARE = MAP_SQUARE_SIZE / squareSize

local RAMPART_HEIGHTMAP_BORDER_WIDTHS = EXPORT.RAMPART_HEIGHTMAP_BORDER_WIDTHS
local RAMPART_TYPEMAP_BORDER_WIDTHS   = EXPORT.RAMPART_TYPEMAP_BORDER_WIDTHS

local MAP_INITIAL_HEIGHT = EXPORT.MAP_INITIAL_HEIGHT
local INITIAL_HEIGHT     = EXPORT.INITIAL_HEIGHT
local MIN_HEIGHT         = EXPORT.MIN_HEIGHT
local MAX_HEIGHT         = EXPORT.MAX_HEIGHT

local typeMapValueByTerrainType = EXPORT.typeMapValueByTerrainType
local INITIAL_TERRAIN_TYPE      = EXPORT.INITIAL_TERRAIN_TYPE
local INITIAL_TYPEMAP_VALUE     = typeMapValueByTerrainType[INITIAL_TERRAIN_TYPE]

-- Localize functions

-- all contexts
local spClearWatchDogTimer      = Spring.ClearWatchDogTimer

-- SYNCED only
local spSetHeightMapFunc        = Spring.SetHeightMapFunc
local spLevelHeightMap          = Spring.LevelHeightMap
local spSetHeightMap            = Spring.SetHeightMap
local spSetGameRulesParam       = Spring.SetGameRulesParam
local spSetMapSquareTerrainType = Spring.SetMapSquareTerrainType

-- overridden
local spGetTimer     = EXPORT.spGetTimer
local PrintTimeSpent = EXPORT.PrintTimeSpent

--------------------------------------------------------------------------------
-- profiling related

if (not gadgetHandler:IsSyncedCode()) then
	-- mock Synced API methods
	spSetHeightMapFunc        = function (func) func() end
	spLevelHeightMap          = function () end
	spSetHeightMap            = function () end
	spSetGameRulesParam       = function () end
	spSetMapSquareTerrainType = function () end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Helper methods for conversions between positions, blocks and map squares

local function posToMapSquareIndexUp (x)
	local heightMapPos = ceil(x / squareSize) * squareSize
	return ceil(x / MAP_SQUARE_SIZE)  -- can return 0, must be clamped later
end

local function posToMapSquareIndexDown (x)
	local heightMapPos = floor(x / squareSize) * squareSize
	return ceil(x / MAP_SQUARE_SIZE)  -- can return 0, must be clamped later
end

local function posToTypeMapSquareIndexUp (x)
	local typeMapIndex = ceil(x / squareSize + 0.5)
	return ceil(typeMapIndex / BLOCKS_PER_SQUARE)
end

local function posToTypeMapSquareIndexDown (x)
	local typeMapIndex = floor(x / squareSize + 0.5)
	return ceil(typeMapIndex / BLOCKS_PER_SQUARE)
end

local function roundUpToBlock (x)
	return ceil(x / squareSize) * squareSize
end

local function roundDownToBlock (x)
	return floor(x / squareSize) * squareSize
end

local function posToTypeMapIndexUp (x)
	return ceil(x / squareSize + 0.5)
end

local function posToTypeMapIndexDown (x)
	return floor(x / squareSize + 0.5)
end

local function aabbToHeightMapSquaresRange (aabb)
	return {
		x1 = max(1            , posToMapSquareIndexUp  (aabb.x1)),
		y1 = max(1            , posToMapSquareIndexUp  (aabb.y1)),
		x2 = min(NUM_SQUARES_X, posToMapSquareIndexDown(aabb.x2)),
		y2 = min(NUM_SQUARES_Z, posToMapSquareIndexDown(aabb.y2))
	}
end

local function aabbToTypeMapSquaresRange (aabb)
	return {
		x1 = max(1            , posToTypeMapSquareIndexUp  (aabb.x1)),
		y1 = max(1            , posToTypeMapSquareIndexUp  (aabb.y1)),
		x2 = min(NUM_SQUARES_X, posToTypeMapSquareIndexDown(aabb.x2)),
		y2 = min(NUM_SQUARES_Z, posToTypeMapSquareIndexDown(aabb.y2))
	}
end

local function aabbToHeightMapBlocksRange (aabb)
	return {
		x1 = max(0       , roundUpToBlock  (aabb.x1)),
		y1 = max(0       , roundUpToBlock  (aabb.y1)),
		x2 = min(mapSizeX, roundDownToBlock(aabb.x2)),
		y2 = min(mapSizeZ, roundDownToBlock(aabb.y2))
	}
end

local function aabbToTypeMapIndexRange (aabb)
	return {
		x1 = max(1           , posToTypeMapIndexUp  (aabb.x1)),
		y1 = max(1           , posToTypeMapIndexUp  (aabb.y1)),
		x2 = min(NUM_BLOCKS_X, posToTypeMapIndexDown(aabb.x2)),
		y2 = min(NUM_BLOCKS_Z, posToTypeMapIndexDown(aabb.y2))
	}
end

local function mapSquareIndexToHeightMapBlocksRange (sx)
	local x1 = (sx == 1) and 0 or ((sx - 1) * MAP_SQUARE_SIZE + squareSize)  -- square 1 is one block larger (it additionally includes block 0)
	local x2 = sx * MAP_SQUARE_SIZE
	return x1, x2
end

local function mapSquareIndexRangeToHeightMapBlocksRange (sx1, sx2)
	local x1 = (sx1 == 1) and 0 or ((sx1 - 1) * MAP_SQUARE_SIZE + squareSize)  -- square 1 is one block larger (it additionally includes block 0)
	local x2 = sx2 * MAP_SQUARE_SIZE
	return x1, x2
end

local function mapSquareIndexToTypeMapIndexRange (sx)
	local x1 = (sx - 1) * BLOCKS_PER_SQUARE + 1
	local x2 = sx * BLOCKS_PER_SQUARE
	return x1, x2
end

local function mapSquareIndexRangeToTypeMapIndexRange (sx1, sx2)
	local x1 = (sx1 - 1) * BLOCKS_PER_SQUARE + 1
	local x2 = sx2 * BLOCKS_PER_SQUARE
	return x1, x2
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Initialize heightMap and typeMap

local function InitHeightMap()
	local startTime = spGetTimer()

	-- heightMap
	local heightMap = {}
	for x = 0, mapSizeX, squareSize do
		heightMap[x] = {}
		local heightMapX = heightMap[x]
		for z = 0, mapSizeZ, squareSize do
			heightMapX[z] = INITIAL_HEIGHT
		end
		spClearWatchDogTimer()
	end

	-- heightMap squares info
	local modifiedHeightMapSquares = {}
	for sx = 1, NUM_SQUARES_X do
		modifiedHeightMapSquares[sx] = {}
		local modifiedHeightMapSquaresX = modifiedHeightMapSquares[sx]

		for sz = 1, NUM_SQUARES_Z do
			modifiedHeightMapSquaresX[sz] = -1
		end
	end

	PrintTimeSpent("HeightMap initialized", " in: ", startTime)
	spClearWatchDogTimer()

	return heightMap, modifiedHeightMapSquares
end

local function InitTypeMap()
	local startTime = spGetTimer()

	-- typeMap
	local typeMap = {}
	for x = 1, NUM_BLOCKS_X do
		typeMap[x] = {}
		local typeMapX = typeMap[x]

		for z = 1, NUM_BLOCKS_Z do
			typeMapX[z] = INITIAL_TERRAIN_TYPE
		end
		spClearWatchDogTimer()
	end

	-- typeMap squares info
	local modifiedTypeMapSquares = {}
	for sx = 1, NUM_SQUARES_X do
		modifiedTypeMapSquares[sx] = {}
		local modifiedTypeMapSquaresX = modifiedTypeMapSquares[sx]

		for sz = 1, NUM_SQUARES_Z do
			modifiedTypeMapSquaresX[sz] = -1
		end
	end

	PrintTimeSpent("TypeMap initialized", " in: ", startTime)
	spClearWatchDogTimer()

	return typeMap, modifiedTypeMapSquares
end

--------------------------------------------------------------------------------
-- Generate heightMap and typeMap

local function MarkModifiedMapSquaresForShape (modifiedMapSquares, squaresRange, currentShape, borderWidths, squareContentPadding)
	local sx1, sx2, sy1, sy2 = squaresRange.x1, squaresRange.x2, squaresRange.y1, squaresRange.y2
	local shapeMapSquares = {}

	if (currentShape:canCheckMapSquareNarrowIntersection()) then  -- perform narrow checks
		for sx = sx1, sx2 do
			local modifiedMapSquaresX = modifiedMapSquares[sx]

			shapeMapSquares[sx] = { sy1 = false, sy2 = false }
			local shapeMapSquaresX = shapeMapSquares[sx]

			for sz = sy1, sy2 do
				if (currentShape:intersectsMapSquare(sx, sz, squareContentPadding, borderWidths)) then
					modifiedMapSquaresX[sz] = 1

					shapeMapSquaresX.sy1 = shapeMapSquaresX.sy1 or sz
					shapeMapSquaresX.sy2 = sz
				elseif (modifiedMapSquaresX[sz] == -1) then
					modifiedMapSquaresX[sz] = 0  -- is in AABB of the shape, but eliminated by narrow check
				end
			end
		end
	else  -- skip narrow checks
		for sx = sx1, sx2 do
			local modifiedMapSquaresX = modifiedMapSquares[sx]
			shapeMapSquares[sx] = { sy1 = sy1, sy2 = sy2 }
	
			for sz = sy1, sy2 do
				modifiedMapSquaresX[sz] = 1
			end
		end
	end

	return shapeMapSquares
end

local function getHeightMapBlocksRangeLimitedByMapSquares (blocksRange, sx, syRange)
	local sbx1, sbx2 = mapSquareIndexToHeightMapBlocksRange(sx)
	local sby1, sby2 = mapSquareIndexRangeToHeightMapBlocksRange(syRange.sy1, syRange.sy2)

	local x1 = max(sbx1, blocksRange.x1)
	local x2 = min(blocksRange.x2, sbx2)
	local y1 = max(sby1, blocksRange.y1)
	local y2 = min(blocksRange.y2, sby2)

	return x1, x2, y1, y2
end

local function getTypeMapIndexRangeLimitedByMapSquares (indexRange, sx, syRange)
	local six1, six2 = mapSquareIndexToTypeMapIndexRange(sx)
	local siy1, siy2 = mapSquareIndexRangeToTypeMapIndexRange(syRange.sy1, syRange.sy2)

	local x1 = max(six1, indexRange.x1)
	local x2 = min(indexRange.x2, six2)
	local y1 = max(siy1, indexRange.y1)
	local y2 = min(indexRange.y2, siy2)

	return x1, x2, y1, y2
end

local function GeneratePlayableArea(playableAreaShape, typeMap, modifiedTypeMapSquares)
	local startTime = spGetTimer()

	local aabb = playableAreaShape:getAABB(RAMPART_TYPEMAP_BORDER_WIDTHS)
	local squaresRange = aabbToTypeMapSquaresRange(aabb)
	local indexRange   = aabbToTypeMapIndexRange(aabb)
	local sx1, sx2 = squaresRange.x1, squaresRange.x2

	local shapeMapSquaresYRanges = MarkModifiedMapSquaresForShape(modifiedTypeMapSquares, squaresRange, playableAreaShape, RAMPART_TYPEMAP_BORDER_WIDTHS, halfSquareSize)

	for sx = sx1, sx2 do
		local syRange = shapeMapSquaresYRanges[sx]

		if (syRange.sy1 ~= false) then
			local x1, x2, y1, y2 = getTypeMapIndexRangeLimitedByMapSquares(indexRange, sx, syRange)

			for tmx = x1, x2 do
				local typeMapX = typeMap[tmx]
				local x = tmx * squareSize - halfSquareSize
				local finishColumnIfOutsideWalls = false

				for tmz = y1, y2 do
					local z = tmz * squareSize - halfSquareSize
					local wasInsideShape = playableAreaShape:modifyTypeMapForShape(typeMapX, tmz, x, z)

					if (wasInsideShape) then
						finishColumnIfOutsideWalls = true
					elseif (finishColumnIfOutsideWalls) then
						break  -- we were in walls and now we are outside, so no more blocks in this column (assumes shape is convex)
					end
				end
			end

            spClearWatchDogTimer()
		end
	end

	PrintTimeSpent("Playable area generated", " in: ", startTime)
end

local function GenerateHeightMapForShape (currentShape, heightMap, modifiedHeightMapSquares)
	local aabb = currentShape:getAABB(RAMPART_HEIGHTMAP_BORDER_WIDTHS)
	local squaresRange = aabbToHeightMapSquaresRange(aabb)
	local blocksRange  = aabbToHeightMapBlocksRange(aabb)
	local sx1, sx2 = squaresRange.x1, squaresRange.x2

	local shapeMapSquaresYRanges = MarkModifiedMapSquaresForShape(modifiedHeightMapSquares, squaresRange, currentShape, RAMPART_HEIGHTMAP_BORDER_WIDTHS, 0)

	for sx = sx1, sx2 do
		local syRange = shapeMapSquaresYRanges[sx]

		if (syRange.sy1 ~= false) then
			local x1, x2, y1, y2 = getHeightMapBlocksRangeLimitedByMapSquares(blocksRange, sx, syRange)

			for x = x1, x2, squareSize do
				local heightMapX = heightMap[x]
				local finishColumnIfOutsideWalls = false

				for z = y1, y2, squareSize do
					local wasInsideShape = currentShape:modifyHeightMapForShape(heightMapX, x, z)

					if (wasInsideShape) then
						finishColumnIfOutsideWalls = true
					elseif (finishColumnIfOutsideWalls) then
						break  -- we were in walls and now we are outside, so no more blocks in this column (assumes shape is convex)
					end
				end
			end

            spClearWatchDogTimer()
		end
	end
end

local function GenerateTypeMapForShape (currentShape, typeMap, modifiedTypeMapSquares)
	local aabb = currentShape:getAABB(RAMPART_TYPEMAP_BORDER_WIDTHS)
	local squaresRange = aabbToTypeMapSquaresRange(aabb)
	local indexRange   = aabbToTypeMapIndexRange(aabb)
	local sx1, sx2 = squaresRange.x1, squaresRange.x2

	local shapeMapSquaresYRanges = MarkModifiedMapSquaresForShape(modifiedTypeMapSquares, squaresRange, currentShape, RAMPART_TYPEMAP_BORDER_WIDTHS, halfSquareSize)

	for sx = sx1, sx2 do
		local syRange = shapeMapSquaresYRanges[sx]

		if (syRange.sy1 ~= false) then
			local x1, x2, y1, y2 = getTypeMapIndexRangeLimitedByMapSquares(indexRange, sx, syRange)

			for tmx = x1, x2 do
				local typeMapX = typeMap[tmx]
				local x = tmx * squareSize - halfSquareSize
				local finishColumnIfOutsideWalls = false

				for tmz = y1, y2 do
					local z = tmz * squareSize - halfSquareSize
					local wasInsideShape = currentShape:modifyTypeMapForShape(typeMapX, tmz, x, z)

					if (wasInsideShape) then
						finishColumnIfOutsideWalls = true
					elseif (finishColumnIfOutsideWalls) then
						break  -- we were in walls and now we are outside, so no more blocks in this column (assumes shape is convex)
					end
				end
			end

            spClearWatchDogTimer()
		end
	end
end

local function GenerateHeightMap (rampartShapes, heightMap, modifiedHeightMapSquares)
	local startTime = spGetTimer()

	for i = 1, #rampartShapes do
		GenerateHeightMapForShape(rampartShapes[i], heightMap, modifiedHeightMapSquares)
	end

	PrintTimeSpent("HeightMap generated", " in: ", startTime)
end

local function GenerateTypeMap (rampartShapes, typeMap, modifiedTypeMapSquares)
	local startTime = spGetTimer()

	for i = 1, #rampartShapes do
		GenerateTypeMapForShape(rampartShapes[i], typeMap, modifiedTypeMapSquares)
	end

	PrintTimeSpent("TypeMap generated", " in: ", startTime)
end

--------------------------------------------------------------------------------
-- Apply heightMap and typeMap

local function ProcessBlocksInModifiedHeightMapSquares (modifiedHeightMapSquares, func)
	for sx = 1, NUM_SQUARES_X do
		local modifiedHeightMapSquaresX = modifiedHeightMapSquares[sx]
		local x1, x2 = mapSquareIndexToHeightMapBlocksRange(sx)

		for sz = 1, NUM_SQUARES_Z do
			if (modifiedHeightMapSquaresX[sz] == 1) then
				local z1, z2 = mapSquareIndexToHeightMapBlocksRange(sz)

				func(x1, x2, z1, z2)
			end
		end
	end
end

local function ProcessBlocksInModifiedTypeMapSquares (modifiedTypeMapSquares, func)
	for sx = 1, NUM_SQUARES_X do
		local modifiedTypeMapSquaresX = modifiedTypeMapSquares[sx]
		local x1, x2 = mapSquareIndexToTypeMapIndexRange(sx)

		for sz = 1, NUM_SQUARES_Z do
			if (modifiedTypeMapSquaresX[sz] == 1) then
				local z1, z2 = mapSquareIndexToTypeMapIndexRange(sz)

				func(x1, x2, z1, z2)
			end
		end
	end
end

local function OverrideGetGroundOrigHeight()
	local oldGetGroundOrigHeight = Spring.GetGroundOrigHeight

	Spring.GetGroundOrigHeight = function(x, z)
		local mapgen_origHeight = GG.mapgen_origHeight
		if (mapgen_origHeight and mapgen_origHeight[x] and mapgen_origHeight[x][z]) then
			return mapgen_origHeight[x][z]
		end

		return oldGetGroundOrigHeight(x, z)
	end
end

local function ApplyHeightMap (heightMap, modifiedHeightMapSquares)
	local startTime = spGetTimer()

	local totalHeightMapAmountChanged = spSetHeightMapFunc(function()
		if (INITIAL_HEIGHT ~= MAP_INITIAL_HEIGHT) then
			spLevelHeightMap(0, 0, mapSizeX, mapSizeZ, INITIAL_HEIGHT) -- this is fast
			spClearWatchDogTimer()
		else
			spSetHeightMap(0, mapSizeZ, INITIAL_HEIGHT) -- reset minHeight and maxHeight points
			spSetHeightMap(squareSize, mapSizeZ, INITIAL_HEIGHT)
		end

		ProcessBlocksInModifiedHeightMapSquares(modifiedHeightMapSquares,
		function (x1, x2, z1, z2)
			for x = x1, x2, squareSize do
				local heightMapX = heightMap[x]

				for z = z1, z2, squareSize do
					local height = heightMapX[z]
					if (height ~= INITIAL_HEIGHT) then
						spSetHeightMap(x, z, height)
					end
				end
			end
			spClearWatchDogTimer()
		end)
	end)
	--Spring.Echo('totalHeightMapAmountChanged: ' .. totalHeightMapAmountChanged)

	GG.mapgen_origHeight = heightMap
	OverrideGetGroundOrigHeight()

	spSetGameRulesParam("ground_min_override", MIN_HEIGHT)
	spSetGameRulesParam("ground_max_override", MAX_HEIGHT)

	if VISUALIZE_MODIFIED_MAP_SQUARES then
		_G.mapgen_modifiedHeightMapSquares = modifiedHeightMapSquares
	end

	PrintTimeSpent("HeightMap applied", " in: ", startTime)
end

local function ApplyTypeMap (typeMap, modifiedTypeMapSquares)
	local startTime = spGetTimer()

	ProcessBlocksInModifiedTypeMapSquares(modifiedTypeMapSquares,
	function (x1, x2, z1, z2)
		for x = x1, x2 do
			local typeMapX = typeMap[x]
			local tmx = (x - 1) * squareSize

			for z = z1, z2 do
				local terrainType  = typeMapX[z]
				local typeMapValue = typeMapValueByTerrainType[terrainType]

				if (typeMapValue ~= INITIAL_TYPEMAP_VALUE) then
					local tmz = (z - 1) * squareSize
					spSetMapSquareTerrainType(tmx, tmz, typeMapValue)
				end
			end
		end
		spClearWatchDogTimer()
	end)

	_G.mapgen_typeMap = typeMap
	_G.mapgen_modifiedTypeMapSquares = modifiedTypeMapSquares

	PrintTimeSpent("TypeMap applied", " in: ", startTime)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local TerrainGenerator = {
    InitHeightMap        = InitHeightMap,
    InitTypeMap          = InitTypeMap,
    GeneratePlayableArea = GeneratePlayableArea,
    GenerateHeightMap    = GenerateHeightMap,
    GenerateTypeMap      = GenerateTypeMap,
    ApplyHeightMap       = ApplyHeightMap,
    ApplyTypeMap         = ApplyTypeMap
}

return TerrainGenerator
