function gadget:GetInfo()
	return {
		name      = "Fata Morgana Terrain Generator",
		desc      = "Procedurally generates Fata Morgana heightmap, metalspots, geos and startboxes",
		author    = "Rafal[ZK]",
		date      = "August 2021",
		license   = "GNU GPL, v2 or later",
		layer     = -1000001, -- before mex_spot_finder
		enabled   = true  --  loaded by default?
	}
end

local VRG_Config = VFS.Include("LuaRules/Configs/map_generator_config.lua")

local ENABLE_SYNCED_PROFILING        = VRG_Config.ENABLE_SYNCED_PROFILING  -- enables profiling of Synced code by running it again in Unsynced context
local VISUALIZE_MODIFIED_MAP_SQUARES = VRG_Config.VISUALIZE_MODIFIED_MAP_SQUARES
local GENERATE_MINIMAP               = VRG_Config.GENERATE_MINIMAP  -- generates and saves minimap

if (not gadgetHandler:IsSyncedCode()) then
	if (not ENABLE_SYNCED_PROFILING) then
		return false
	end
end

--------------------------------------------------------------------------------
-- Synced
--------------------------------------------------------------------------------

if (Spring.GetGameFrame() >= 1) then
	return false
end

-- all contexts
local spGetMapOptions      = Spring.GetMapOptions
local spClearWatchDogTimer = Spring.ClearWatchDogTimer
local spEcho               = Spring.Echo

-- UNSYNCED only
local spGetTimer           = Spring.GetTimer

--------------------------------------------------------------------------------

local min    = math.min
local max    = math.max
local abs    = math.abs
local floor  = math.floor
local ceil   = math.ceil
local round  = math.round
local deg    = math.deg
local rad    = math.rad
local sin    = math.sin
local cos    = math.cos
local tan    = math.tan
local random = math.random

local mapSizeX = Game.mapSizeX
local mapSizeZ = Game.mapSizeZ
local centerX  = mapSizeX / 2
local centerY  = mapSizeZ / 2

local squareSize = Game.squareSize
local MAP_SQUARE_SIZE = 1024

local DISTANCE_HUGE = 1e6

--------------------------------------------------------------------------------
-- profiling related

local PrintTimeSpent

if (gadgetHandler:IsSyncedCode()) then
	-- mock Unsynced API methods
	spGetTimer = function () return nil end

	PrintTimeSpent = function (message, timeMessage, startTime)
		spEcho(message)
	end
else
	-- profiling utils
	local origSpEcho = spEcho

	spEcho = function (...)
		origSpEcho("[UNSYNCED] " .. select(1, ...), select(2, ...))
	end

	PrintTimeSpent = function (message, timeMessage, startTime)
		local currentTime = spGetTimer()
		spEcho(message .. timeMessage .. string.format("%.0f", round(Spring.DiffTimers(currentTime, startTime, true))) .. "ms")
	end
end

--------------------------------------------------------------------------------
-- CONFIG

-- map geometry
local CENTER_LANE_MIN_DISTANCE_FROM_CENTER = 900 -- limiting factor for 3 players
local CENTER_LANE_END_MIN_DISTANCE_FROM_CENTER = 1600 -- limiting factor for 4 or 5 players
local CENTER_LANE_MIN_LENGTH = 1900 -- limiting factor for >= 6 players
local CENTER_LANE_WIDTH = 900
local CENTER_POLYGON_DESIRED_WIDTH_MIN = 790
local CENTER_POLYGON_DESIRED_WIDTH_FACTOR = 0.30 -- [0.0, 1.0] - by what factor we move center polygon edges towards desired width
local CENTER_ENTRANCE_RELATIVE_WIDTH = 1.0 / 3.0 -- [0.0, 1.0] - relative to inner length of center wall
local CENTER_RAMP_MAX_SLOPE_ANGLE = 1.5 * 18 -- max slope for tanks (from movedefs)
local CENTER_RAMP_LENGTH_MULT = 1.30 -- increase ramp length to decrease slope, so there is some tolerance to map deformation
local CENTER_FLAT_AREA_MIN_WIDTH = 64
local CENTER_LANE_MEX_MAX_PERPENDICULAR_OFFSET = 0 -- 0.2 * CENTER_LANE_WIDTH
local CENTER_LANE_GEO_MAX_PERPENDICULAR_OFFSET = 0.25 * CENTER_LANE_WIDTH
local SPADE_ROTATION_MIN_NONZERO_ANGLE = 7.5
local SPADE_HANDLE_WIDTH  = 550
local SPADE_HANDLE_HEIGHT = 1100 --1500
local SPADE_WIDTH  = 1200
local SPADE_HEIGHT = 800
local SPADE_RESOURCE_PATH_RADIUS = 350
local SPADE_VISUAL_CENTER_OFFSET = 120 --124.94482 -- offset of visual center of spade from center of spade rectangle

--------------------------------------------------------------------------------
-- overwrite certain values for local testing or minimap generation

-- (no overwrite)
--local OVERWRITE_NUMBER_OF_BASES = false       -- false | [3, 11]
--local OVERWRITE_SPADE_ROTATION_ANGLE = false  -- false | [-1.0, 1.0]
--local OVERWRITE_INITIAL_ANGLE = false         -- false | [ 0.0, 1.0]

-- (for local testing)
local OVERWRITE_NUMBER_OF_BASES = 7
local OVERWRITE_SPADE_ROTATION_ANGLE = false
local OVERWRITE_INITIAL_ANGLE = false

-- (for preformance profiling)
--local OVERWRITE_NUMBER_OF_BASES = 7
--local OVERWRITE_SPADE_ROTATION_ANGLE = 0.0
--local OVERWRITE_INITIAL_ANGLE = 0.3

if (GENERATE_MINIMAP) then
	-- (for minimap generation with 5 bases)
	--OVERWRITE_NUMBER_OF_BASES = 5
	--OVERWRITE_SPADE_ROTATION_ANGLE = 0.0
	--OVERWRITE_INITIAL_ANGLE = 0.0

	-- (for minimap generation with 6 bases)
	--OVERWRITE_NUMBER_OF_BASES = 6
	--OVERWRITE_SPADE_ROTATION_ANGLE = 0.0
	--OVERWRITE_INITIAL_ANGLE = 0.5 -- 0.5 -- 0.0

	-- (for minimap generation with 7 bases)
	OVERWRITE_NUMBER_OF_BASES = 7
	OVERWRITE_SPADE_ROTATION_ANGLE = 0.0
	OVERWRITE_INITIAL_ANGLE = 0.0
end

--------------------------------------------------------------------------------

-- wall thickness
local RAMPART_WALL_INNER_TEXTURE_WIDTH = 8 + 4
local RAMPART_WALL_WIDTH = 48
local RAMPART_WALL_OUTER_WIDTH = 8
local RAMPART_WALL_OUTER_TYPEMAP_WIDTH = -4
local RAMPART_WALL_OUTER_TEXTURE_WIDTH = 40 - 4

if (GENERATE_MINIMAP) then
	RAMPART_WALL_OUTER_TEXTURE_WIDTH = 24 - 4
end

local RAMPART_WALL_WIDTH_TOTAL               = RAMPART_WALL_INNER_TEXTURE_WIDTH + RAMPART_WALL_WIDTH
local RAMPART_WALL_OUTER_WIDTH_TOTAL         = RAMPART_WALL_INNER_TEXTURE_WIDTH + RAMPART_WALL_WIDTH + RAMPART_WALL_OUTER_WIDTH
local RAMPART_WALL_OUTER_TYPEMAP_WIDTH_TOTAL = RAMPART_WALL_INNER_TEXTURE_WIDTH + RAMPART_WALL_WIDTH + RAMPART_WALL_OUTER_WIDTH + RAMPART_WALL_OUTER_TYPEMAP_WIDTH
local RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL = RAMPART_WALL_INNER_TEXTURE_WIDTH + RAMPART_WALL_WIDTH + RAMPART_WALL_OUTER_WIDTH + RAMPART_WALL_OUTER_TEXTURE_WIDTH

local RAMPART_OUTER_TYPEMAP_WIDTH = 4

local BORDER_TYPE_NO_WALL       = 1
local BORDER_TYPE_WALL          = 2
local BORDER_TYPE_INTERNAL_WALL = 3

local RAMPART_HEIGHTMAP_BORDER_WIDTHS = {
	[BORDER_TYPE_NO_WALL]       = 0,
	[BORDER_TYPE_WALL]          = RAMPART_WALL_OUTER_WIDTH_TOTAL,
	[BORDER_TYPE_INTERNAL_WALL] = 0
}

local RAMPART_TYPEMAP_BORDER_WIDTHS = {
	[BORDER_TYPE_NO_WALL]       = RAMPART_OUTER_TYPEMAP_WIDTH,
	[BORDER_TYPE_WALL]          = RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL,
	[BORDER_TYPE_INTERNAL_WALL] = RAMPART_WALL_INNER_TEXTURE_WIDTH
}

local INTERSECTION_EPSILON = 0.001

-- heightmap
local BOTTOM_HEIGHT         = -200
local RAMPART_CENTER_HEIGHT =   20
local RAMPART_HEIGHT        =  300
local RAMPART_WALL_HEIGHT   =  370 -- 380
--local BOTTOM_HEIGHT         = 100
--local RAMPART_CENTER_HEIGHT = 320
--local RAMPART_HEIGHT        = 600
--local RAMPART_WALL_HEIGHT   = 670
local RAMPART_WALL_OUTER_HEIGHT = 1

local MAP_INITIAL_HEIGHT =   20
local INITIAL_HEIGHT     =   20
local MIN_HEIGHT         = -200
local MAX_HEIGHT         =  650

-- terrain types
local OUTSIDE_TERRAIN_TYPE  = 0
local DESERT_TERRAIN_TYPE   = 1
local MOUNTAIN_TERRAIN_TYPE = 2

local INITIAL_TERRAIN_TYPE = OUTSIDE_TERRAIN_TYPE

-- old
local BOTTOM_TERRAIN_TYPE       = 0
local RAMPART_TERRAIN_TYPE      = 1
local RAMPART_DARK_TERRAIN_TYPE = 2
local RAMPART_WALL_TERRAIN_TYPE = 3
local RAMPART_WALL_OUTER_TYPE   = 4

local OUTSIDE_TYPEMAP_VALUE  = 0
local DESERT_TYPEMAP_VALUE   = 1
local MOUNTAIN_TYPEMAP_VALUE = 2

-- old
local BOTTOM_TYPEMAP_VALUE       = 0
local RAMPART_TYPEMAP_VALUE      = 1
local RAMPART_WALL_TYPEMAP_VALUE = 2

local typeMapValueByTerrainType = {
	[OUTSIDE_TERRAIN_TYPE]  = OUTSIDE_TYPEMAP_VALUE,
	[DESERT_TERRAIN_TYPE]   = DESERT_TYPEMAP_VALUE,
	[MOUNTAIN_TERRAIN_TYPE] = MOUNTAIN_TYPEMAP_VALUE,
}

--------------------------------------------------------------------------------

-- resources
local NUM_SPADE_MEXES = 5
local NUM_SPADE_HANDLE_MEXES = 2
local NUM_CENTER_LANE_MEXES = 3
local MIN_BASES_FOR_CENTER_MEX = 6

local SPADE_MEXES_METAL = 2.0
local SPADE_HANDLE_MEXES_METAL = 1.5
local SPADE_ENTRANCE_MEX_METAL = 3.0
local CENTER_LANE_MEXES_METAL = 1.5
local CENTER_MEX_METAL = 4.0

local ADD_BASE_GEO = true
local ADD_CENTER_LANE_GEO = true

--------------------------------------------------------------------------------

-- start boxes
local START_BOX_PADDING = 32

local BASE_SYMBOLS = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K" }

-- end of CONFIG
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function inheritClass (baseClass)
	local subClass = {}

	subClass.__index = subClass
	subClass.class = subClass
	subClass.superClass = baseClass
	setmetatable(subClass, baseClass)

    return subClass
end

function createClass()
	local class = {}

	class.__index = class
	class.class = class
	class.inherit = inheritClass

	return class
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function clamp(minValue, value, maxValue)
	return min(max(minValue, value), maxValue)
end

local function AddRandomOffsetInDirection(p, maxOffset, dirVector)
	local offset = (-1.0 + 2.0 * random()) * maxOffset
	return {
		x = p.x + offset * dirVector.x,
		y = p.y + offset * dirVector.y
	}
end

local function pointToMetalSpot(p, metal)
	return {		
		x = p.x,
		z = p.y,
		metal = metal
	}
end

local function getRotatedMetalSpot(spot, rotation)
	local spotPoint = {
		x = spot.x,
		y = spot.z
	}
	local rotatedPoint = rotation:getRotatedPoint(spotPoint)
	return pointToMetalSpot(rotatedPoint, spot.metal)
end

local function roundToBuildingCenter (x)
	return (round(((x / squareSize) - 1) / 2) * 2 + 1) * squareSize
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Helper method for applying height values at specific point of walled shape or its border

local function modifyHeightMapForWalledShape (self, heightMapX, x, z)
	local distanceFromBorder = self:getDistanceFromBorderForPoint(x, z)
	local isInRampart = (distanceFromBorder <= 0)

	if (isInRampart) then  -- rampart area is largest so it is most likely to be inside it
		heightMapX[z] = RAMPART_HEIGHT
	else
		local isAnyWalls = (distanceFromBorder <= RAMPART_WALL_OUTER_WIDTH_TOTAL)

		if (isAnyWalls) then
			local isInnerWalls = (distanceFromBorder <  RAMPART_WALL_INNER_TEXTURE_WIDTH)
			local isWalls      = (distanceFromBorder <= RAMPART_WALL_WIDTH_TOTAL)

			if (isInnerWalls) then
				-- for smoothed walls
				--local innerWallFactor = distanceFromBorder / RAMPART_WALL_INNER_TEXTURE_WIDTH
				--local newHeight = (innerWallFactor * RAMPART_WALL_HEIGHT) + ((1.0 - innerWallFactor) * RAMPART_HEIGHT)
				local newHeight = RAMPART_HEIGHT
				if (heightMapX[z] < RAMPART_HEIGHT or newHeight < heightMapX[z]) then -- do not overwrite inner rampart
					heightMapX[z] = newHeight
				end
			elseif (isWalls) then
				if (heightMapX[z] ~= RAMPART_HEIGHT) then -- do not overwrite inner rampart
					heightMapX[z] = RAMPART_WALL_HEIGHT
				end
			else  -- isOuterWalls
				-- for smoothed walls
				--local outerWallFactor = (RAMPART_WALL_OUTER_WIDTH_TOTAL - distanceFromBorder) / RAMPART_WALL_OUTER_WIDTH
				--local newHeight = (outerWallFactor * RAMPART_WALL_HEIGHT) + ((1.0 - outerWallFactor) * RAMPART_WALL_OUTER_HEIGHT)
				local newHeight = RAMPART_WALL_OUTER_HEIGHT
				if (heightMapX[z] < newHeight) then -- do not overwrite rampart or wall
					heightMapX[z] = newHeight
				end
			end
		else
			return false
		end
	end

	return true
end

-- Helper method for applying height values at specific point of internal wall shape

local function modifyHeightMapForInternalWallShape (self, heightMapX, x, z)
	local isInsideShape = self:isPointInsideShape(x, z)

	if (isInsideShape) then
		heightMapX[z] = RAMPART_WALL_HEIGHT
	end

	return isInsideShape
end

-- Helper method for applying height values at specific point of flat shape

local function modifyHeightMapForFlatShape (self, heightMapX, x, z)
	local isInsideShape = self:isPointInsideShape(x, z)

	if (isInsideShape) then
		local newHeight = self.groundHeight
		if (heightMapX[z] < newHeight or RAMPART_HEIGHT < heightMapX[z]) then
			heightMapX[z] = newHeight
		end
	end

	return isInsideShape
end

-- Helper method for applying height values at specific point of ramp shape

local function modifyHeightMapForRampShape (self, heightMapX, x, z)
	local isInsideShape, newHeight = self:getGroundHeightForPoint(x, z)

	if (isInsideShape) then
		if (heightMapX[z] < newHeight or RAMPART_HEIGHT < heightMapX[z]) then
			heightMapX[z] = newHeight
		end
	end

	return isInsideShape
end

--------------------------------------------------------------------------------
-- Helper method for applying typemap values at specific point of walled shape or its border

local function modifyTypeMapForWalledShape (self, typeMapX, tmz, x, z)
	local isAnyTerrainType, isWallsTexture, isWallsTerrainType = self:getTypeMapInfoForPoint(x, z)

	if (isAnyTerrainType) then
		if (isWallsTexture) then
			if (isWallsTerrainType) then
				local oldTerrainType  = typeMapX[tmz]
				local oldTypeMapValue = typeMapValueByTerrainType[oldTerrainType]

				if (oldTypeMapValue ~= RAMPART_TYPEMAP_VALUE) then -- do not overwrite inner rampart
					typeMapX[tmz] = RAMPART_WALL_TERRAIN_TYPE
				end
			else
				if (typeMapX[tmz] == BOTTOM_TERRAIN_TYPE) then -- do not overwrite rampart or wall
					typeMapX[tmz] = RAMPART_WALL_OUTER_TYPE
				end
			end
		else
			typeMapX[tmz] = self.rampartTerrainType
		end
	else
		return false
	end

	return true
end

-- Helper method for applying typemap values at specific point of internal wall shape

local function modifyTypeMapForInternalWallShape (self, typeMapX, tmz, x, z)
	local isInsideShape = self:isPointInsideTypeMap(x, z)

	if (isInsideShape) then
		typeMapX[tmz] = RAMPART_WALL_TERRAIN_TYPE
	end

	return isInsideShape
end

-- Helper method for applying typemap values at specific point of not walled shape

local function modifyTypeMapForNotWalledShape (self, typeMapX, tmz, x, z)
	local isInsideShape = self:isPointInsideTypeMap(x, z)

	if (isInsideShape) then
		typeMapX[tmz] = self.rampartTerrainType
	end

	return isInsideShape
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Export some variables and functions to included files

EXPORT = {
	-- Export variables

	MAP_SQUARE_SIZE = MAP_SQUARE_SIZE,
	DISTANCE_HUGE = DISTANCE_HUGE,
	RAMPART_WALL_INNER_TEXTURE_WIDTH = RAMPART_WALL_INNER_TEXTURE_WIDTH,
	RAMPART_WALL_OUTER_TYPEMAP_WIDTH_TOTAL = RAMPART_WALL_OUTER_TYPEMAP_WIDTH_TOTAL,
	RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL = RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL,
	RAMPART_OUTER_TYPEMAP_WIDTH = RAMPART_OUTER_TYPEMAP_WIDTH,
	BORDER_TYPE_NO_WALL = BORDER_TYPE_NO_WALL,
	BORDER_TYPE_WALL = BORDER_TYPE_WALL,
	BORDER_TYPE_INTERNAL_WALL = BORDER_TYPE_INTERNAL_WALL,
	RAMPART_HEIGHTMAP_BORDER_WIDTHS = RAMPART_HEIGHTMAP_BORDER_WIDTHS,
	RAMPART_TYPEMAP_BORDER_WIDTHS = RAMPART_TYPEMAP_BORDER_WIDTHS,
	INTERSECTION_EPSILON = INTERSECTION_EPSILON,
	RAMPART_HEIGHT = RAMPART_HEIGHT,
	MAP_INITIAL_HEIGHT = MAP_INITIAL_HEIGHT,
	INITIAL_HEIGHT = INITIAL_HEIGHT,
	MIN_HEIGHT = MIN_HEIGHT,
	MAX_HEIGHT = MAX_HEIGHT,
	RAMPART_TERRAIN_TYPE = RAMPART_TERRAIN_TYPE,
	INITIAL_TERRAIN_TYPE = INITIAL_TERRAIN_TYPE,
	typeMapValueByTerrainType = typeMapValueByTerrainType,

	-- Export functions

	spGetTimer     = spGetTimer,
	PrintTimeSpent = PrintTimeSpent,

	modifyHeightMapForWalledShape       = modifyHeightMapForWalledShape,
	modifyHeightMapForInternalWallShape = modifyHeightMapForInternalWallShape,
	modifyHeightMapForFlatShape         = modifyHeightMapForFlatShape,
	modifyHeightMapForRampShape         = modifyHeightMapForRampShape,
	modifyTypeMapForWalledShape         = modifyTypeMapForWalledShape,
	modifyTypeMapForInternalWallShape   = modifyTypeMapForInternalWallShape,
	modifyTypeMapForNotWalledShape      = modifyTypeMapForNotWalledShape,
}

--------------------------------------------------------------------------------

Geom2D, Vector2D, Rotation2D =
	VFS.Include("LuaRules/Gadgets/TerrainGenerator/Geometry/Geometry2D.lua")

LineSegment, ArcSegment, SegmentedPath =
	VFS.Include("LuaRules/Gadgets/TerrainGenerator/Geometry/SegmentedPath.lua")

--------------------------------------------------------------------------------

RampartFullyWalledRectangle, RampartVerticallyWalledRectangle, RampartFlatRectangle =
	VFS.Include("LuaRules/Gadgets/TerrainGenerator/TerrainShapes/RampartRectangle.lua")
RampartHorizontallyWalledTrapezoid, RampartInternalWallTrapezoid, RampartFlatTrapezoid, RampartRampTrapezoid =
	VFS.Include("LuaRules/Gadgets/TerrainGenerator/TerrainShapes/RampartTrapezoid.lua")
RampartWalledCircle, RampartFlatCircle =
	VFS.Include("LuaRules/Gadgets/TerrainGenerator/TerrainShapes/RampartCircle.lua")

--------------------------------------------------------------------------------

TerrainGenerator =
	VFS.Include("LuaRules/Gadgets/TerrainGenerator/TerrainGenerator.lua")

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- map options

local function InitRandomSeed(mapOptions)
	local randomSeed

	if mapOptions and mapOptions.seed and tonumber(mapOptions.seed) ~= 0 then
		randomSeed = tonumber(mapOptions().seed)
	else
		randomSeed = random(1, 1000000)
	end

	math.randomseed(randomSeed)
	spEcho("Using map generation random seed: " .. tostring(randomSeed))
end

--------------------------------------------------------------------------------
-- teams setup

local function getNonGaiaAllyTeamsList(allyTeamsList)
	local gaiaTeamID = Spring.GetGaiaTeamID()

	local nonGaiaAllyTeamsList = {}

	for i = 1, #allyTeamsList do
		local allyTeamID = allyTeamsList[i]
		local teamList = Spring.GetTeamList(allyTeamID)

		for j = 1, #teamList do
			local teamID = teamList[j]
			if (teamID ~= gaiaTeamID) then
				table.insert(nonGaiaAllyTeamsList, allyTeamID)
				break
			end
		end
	end

	return nonGaiaAllyTeamsList
end

local function InitNumberOfBases(mapOptions)
	local allyTeamsList = Spring.GetAllyTeamList()
	local playerList = Spring.GetPlayerList()

	local nonGaiaAllyTeamsList = getNonGaiaAllyTeamsList(allyTeamsList)
	local numAllyTeams = #nonGaiaAllyTeamsList
	local numPlayers = #playerList

	local numBases = clamp(2, numAllyTeams, 11)
	if (numBases <= 2) then
		numBases = 4
	end

	if mapOptions and mapOptions.numBases and tonumber(mapOptions.numBases) ~= 0 then
		local configNumBases = tonumber(mapOptions().numBases)
		if (3 <= configNumBases and configNumBases <= 11) then
			numBases = configNumBases
		end
	end

	if (OVERWRITE_NUMBER_OF_BASES) then
		numBases = OVERWRITE_NUMBER_OF_BASES
	end

	local numStartBoxes

	if (numPlayers >= 2) then
		numStartBoxes = clamp(2, numAllyTeams, numBases)
	else
		numStartBoxes = numBases -- Always create all startBoxes when in local game
	end

	local startBoxNumberByBaseNumber = {}

	if (numStartBoxes < numBases) then
		local basesPerStartBox = numBases / numStartBoxes
		local firstBaseOffset = 1 + basesPerStartBox * random()
		for i = 1, numStartBoxes do
			local baseNumber = floor(firstBaseOffset + (i - 1) * basesPerStartBox)
			startBoxNumberByBaseNumber[baseNumber] = i
		end
	else
		for i = 1, numBases do
			startBoxNumberByBaseNumber[i] = i
		end
	end

	return numBases, numStartBoxes, startBoxNumberByBaseNumber
end

--------------------------------------------------------------------------------
-- map geometry

--[[
local function GenerateSpadeRotationAngle(spadeRotationRange)
	local spadeRotationAngle = (-0.5 + random()) * spadeRotationRange
	if (OVERWRITE_SPADE_ROTATION_ANGLE) then
		spadeRotationAngle = OVERWRITE_SPADE_ROTATION_ANGLE * 0.5 * spadeRotationRange
	end

	local roundedSpadeRotationAngle = spadeRotationAngle
	local roundedMessage = ""

	if (abs(spadeRotationAngle) < rad(SPADE_ROTATION_MIN_NONZERO_ANGLE)) then
		roundedSpadeRotationAngle = 0.0
		roundedMessage = ", rounded to: " .. string.format("%.2f", deg(roundedSpadeRotationAngle))
	end

	spEcho(
		"Spade rotation angle: " .. string.format("%.2f", deg(spadeRotationAngle)) ..
		roundedMessage ..
		" (Min: " .. string.format("%.2f", deg(-0.5 * spadeRotationRange)) ..
		", Max: " .. string.format("%.2f", deg(0.5 * spadeRotationRange)) .. ")")

	return roundedSpadeRotationAngle	
end
--]]

--[[
local function GenerateResourcePaths(spadeHandlePosY, spadeHandleAnchorPos, spadeRotation, spadeRotationAngle, laneStartPoint, laneEndPoint)
	local spadeResourcePathPadding = (SPADE_WIDTH / 2) - SPADE_RESOURCE_PATH_RADIUS
	local spadeResourcePathPosY = spadeHandlePosY - SPADE_HANDLE_HEIGHT - spadeResourcePathPadding

	local spadePath = SegmentedPath.ofSegments({
		LineSegment:new{ 
			p1 = spadeRotation:getRotatedPoint({ x = centerX - SPADE_RESOURCE_PATH_RADIUS, y = spadeResourcePathPosY }),
			p2 = spadeRotation:getRotatedPoint({ x = centerX - SPADE_RESOURCE_PATH_RADIUS, y = spadeHandlePosY - SPADE_HANDLE_HEIGHT - SPADE_HEIGHT })
		},
		ArcSegment:new{
			center = spadeRotation:getRotatedPoint({ x = centerX, y = spadeHandlePosY - SPADE_HANDLE_HEIGHT - SPADE_HEIGHT }),
			radius = SPADE_RESOURCE_PATH_RADIUS,
			startAngleRad = spadeRotationAngle - rad(90),
			angularLengthRad = rad(180)
		},
		LineSegment:new{ 
			p1 = spadeRotation:getRotatedPoint({ x = centerX + SPADE_RESOURCE_PATH_RADIUS, y = spadeHandlePosY - SPADE_HANDLE_HEIGHT - SPADE_HEIGHT }),
			p2 = spadeRotation:getRotatedPoint({ x = centerX + SPADE_RESOURCE_PATH_RADIUS, y = spadeResourcePathPosY })
		}
	})

	local spadeHandlePath = SegmentedPath.ofSegments({
		LineSegment:new{ 
			p1 = laneStartPoint,
			p2 = spadeHandleAnchorPos
		},
		LineSegment:new{ 
			p1 = spadeHandleAnchorPos,
			p2 = spadeRotation:getRotatedPoint({ x = centerX, y = spadeResourcePathPosY })
		}
	})

	local lanePath = SegmentedPath.ofSegment(
		LineSegment:new{
			p1 = laneStartPoint,
			p2 = laneEndPoint
		}
	)

	return spadePath, spadeHandlePath, lanePath
end
--]]

local function GenerateMetalSpots(numBases, spadePath, spadeHandlePath, laneStartPoint, lanePath, laneRightVector)
	local uniqueMetalSpots = {}
	local metalSpots = {}

	--[[
	local spadePathPoints = spadePath:getPointsOnPath(NUM_SPADE_MEXES - 2, true)
	for _, point in ipairs(spadePathPoints) do
		table.insert(metalSpots, pointToMetalSpot(point, SPADE_MEXES_METAL))
	end

	local spadeHandlePathPoints = spadeHandlePath:getPointsOnPath(NUM_SPADE_HANDLE_MEXES, false)
	for _, point in ipairs(spadeHandlePathPoints) do
		table.insert(metalSpots, pointToMetalSpot(point, SPADE_HANDLE_MEXES_METAL))
	end

	table.insert(metalSpots, pointToMetalSpot(laneStartPoint, SPADE_ENTRANCE_MEX_METAL))

	local lanePathPoints = lanePath:getPointsOnPath(NUM_CENTER_LANE_MEXES, false)
	for _, point in ipairs(lanePathPoints) do
		point = AddRandomOffsetInDirection(point, CENTER_LANE_MEX_MAX_PERPENDICULAR_OFFSET, laneRightVector)
		table.insert(metalSpots, pointToMetalSpot(point, CENTER_LANE_MEXES_METAL))
	end
	
	if (numBases >= MIN_BASES_FOR_CENTER_MEX) then
		local point = { x = centerX, y = centerY }
		table.insert(uniqueMetalSpots, pointToMetalSpot(point, CENTER_MEX_METAL))
	end
	--]]

	return uniqueMetalSpots, metalSpots
end

local function GenerateGeoSpots(spadePath, lanePath, laneRightVector)
	local uniqueGeoSpots = {}
	local geoSpots = {}

	--[[
	if (ADD_BASE_GEO) then
		local spadeGeoMexNumber = random(0, NUM_SPADE_MEXES - 2)
		local spadeGeoRelAdvance = (spadeGeoMexNumber + 1.0/3.0 + (1.0/3.0)*random()) / (NUM_SPADE_MEXES - 1)
		local spadeGeoPos = spadePath:getPointAtRelativeAdvance(spadeGeoRelAdvance)
		table.insert(geoSpots, spadeGeoPos)
	end

	if (ADD_CENTER_LANE_GEO) then
		local laneGeoMexNumber = random(floor(NUM_CENTER_LANE_MEXES / 2), ceil(NUM_CENTER_LANE_MEXES / 2))
		local laneGeoRelAdvance = (laneGeoMexNumber + 1.0/3.0 + (1.0/3.0)*random()) / (NUM_CENTER_LANE_MEXES + 1)
		local laneGeoPos = lanePath:getPointAtRelativeAdvance(laneGeoRelAdvance)
		laneGeoPos = AddRandomOffsetInDirection(laneGeoPos, CENTER_LANE_GEO_MAX_PERPENDICULAR_OFFSET, laneRightVector)
		table.insert(geoSpots, laneGeoPos)
	end
	--]]

	return uniqueGeoSpots, geoSpots
end

local function GenerateStartBox(spadeHandlePosY, spadeRotation, spadeRotationAngle)
	local startBoxPoints = {
		{ x = centerX - 100, y = 0 },
		{ x = centerX + 100, y = 0 },
		{ x = centerX + 100, y = 200 },
		{ x = centerX - 100, y = 200 },
	}
	local startPoint = { x = centerX, y = 100 }

	--[[
	local startBoxPathRadius = (SPADE_WIDTH / 2) - START_BOX_PADDING
	local startBoxFirstPoint = spadeRotation:getRotatedPoint({ x = centerX - startBoxPathRadius, y = spadeHandlePosY - SPADE_HANDLE_HEIGHT - START_BOX_PADDING })
	local startBoxLastPoint  = spadeRotation:getRotatedPoint({ x = centerX + startBoxPathRadius, y = spadeHandlePosY - SPADE_HANDLE_HEIGHT - START_BOX_PADDING })

	local startBoxPath = SegmentedPath.ofSegment(
		ArcSegment:new{
			center = spadeRotation:getRotatedPoint({ x = centerX, y = spadeHandlePosY - SPADE_HANDLE_HEIGHT - SPADE_HEIGHT }),
			radius = startBoxPathRadius,
			startAngleRad = spadeRotationAngle - rad(90),
			angularLengthRad = rad(180)
		}
	)
	local startBoxPathPoints = startBoxPath:getPointsOnPath(20 - 1, true)

	local startBoxPoints = {}

	table.insert(startBoxPoints, startBoxFirstPoint)
	for _, point in ipairs(startBoxPathPoints) do
		table.insert(startBoxPoints, point)
	end
	table.insert(startBoxPoints, startBoxLastPoint)

	local startPoint = spadeRotation:getRotatedPoint({ x = centerX, y = spadeHandlePosY - SPADE_HANDLE_HEIGHT - (SPADE_HEIGHT / 2) - SPADE_VISUAL_CENTER_OFFSET })
	--]]

	return startBoxPoints, startPoint
end

local function GeneratePlayableAreaShape(numBases)
	local playableAreaRadius = min(mapSizeX, mapSizeZ) / 2 - squareSize
	local playableAreaShape = RampartFlatCircle:new{
		center = { x = centerX, y = centerY },
		radius = playableAreaRadius,
		groundHeight = INITIAL_HEIGHT,
		rampartTerrainType = DESERT_TERRAIN_TYPE
	}

	return playableAreaShape
end

local function GenerateGeometryForSingleBase(numBases, rotationAngle)
	local uniqueShapes = {}
	local shapes = {}

	--[[
	-- base
	local centerLaneEndDistanceFromCenter = max(
		CENTER_LANE_MIN_DISTANCE_FROM_CENTER / cos(rotationAngle / 2),
		CENTER_LANE_END_MIN_DISTANCE_FROM_CENTER,
		(CENTER_LANE_MIN_LENGTH / 2) / sin(rotationAngle / 2)
	)
	local spadeHandleOffsetFromLane = ((CENTER_LANE_WIDTH - SPADE_HANDLE_WIDTH) / 2) / cos(rotationAngle / 2)
	local spadeHandlePosY = centerY - centerLaneEndDistanceFromCenter - spadeHandleOffsetFromLane
	local spadeHandleAnchorPos = { x = centerX, y = spadeHandlePosY }	
	local rotationAngleOrComplement = min(rotationAngle, rad(180) - rotationAngle)
	local spadeRotationRange = rotationAngleOrComplement
	local spadeRotationAngle = GenerateSpadeRotationAngle(spadeRotationRange)
	local spadeRotation = Rotation2D:new({
		centerX  = centerX,
		centerY  = spadeHandlePosY,
		angleRad = spadeRotationAngle
	})
	table.insert(shapes, RampartVerticallyWalledRectangle:new{
		p1 = spadeHandleAnchorPos,
		p2 = spadeRotation:getRotatedPoint({ x = centerX, y = spadeHandlePosY - SPADE_HANDLE_HEIGHT }),
		width = SPADE_HANDLE_WIDTH
	})
	table.insert(shapes, RampartFullyWalledRectangle:new{
		p1 = spadeRotation:getRotatedPoint({ x = centerX, y = spadeHandlePosY - SPADE_HANDLE_HEIGHT }),
		p2 = spadeRotation:getRotatedPoint({ x = centerX, y = spadeHandlePosY - SPADE_HANDLE_HEIGHT - SPADE_HEIGHT }),
		width = SPADE_WIDTH
	})
	table.insert(shapes, RampartWalledCircle:new{
		center = spadeRotation:getRotatedPoint({ x = centerX, y = spadeHandlePosY - SPADE_HANDLE_HEIGHT - SPADE_HEIGHT }),
		radius = SPADE_WIDTH / 2
	})

	-- lane
	local laneEndRotation = Rotation2D:new({
		centerX  = centerX,
		centerY  = centerY,
		angleRad = rotationAngle
	})
	local laneStartPoint = { x = centerX, y = centerY - centerLaneEndDistanceFromCenter }
	local laneEndPoint = laneEndRotation:getRotatedPoint(laneStartPoint)

	local laneRotation = Rotation2D:new({
		centerX  = centerX,
		centerY  = centerY,
		angleRad = rotationAngle / 2
	})
	local laneDistanceFromCenter = centerLaneEndDistanceFromCenter * cos(rotationAngle / 2)
	local laneOuterDistanceFromCenter = laneDistanceFromCenter + CENTER_LANE_WIDTH / 2
	local laneInnerDistanceFromCenter = laneDistanceFromCenter - CENTER_LANE_WIDTH / 2
	local centerPolygonWidth = laneInnerDistanceFromCenter - (RAMPART_WALL_WIDTH_TOTAL + RAMPART_WALL_INNER_TEXTURE_WIDTH)
	local laneExtendWidth = max(0, centerPolygonWidth - CENTER_POLYGON_DESIRED_WIDTH_MIN) * CENTER_POLYGON_DESIRED_WIDTH_FACTOR

	laneInnerDistanceFromCenter = laneDistanceFromCenter - (CENTER_LANE_WIDTH / 2 + laneExtendWidth)
	centerPolygonWidth = laneInnerDistanceFromCenter - (RAMPART_WALL_WIDTH_TOTAL + RAMPART_WALL_INNER_TEXTURE_WIDTH)
	local laneOuterEdgeLength     = 2 * (laneOuterDistanceFromCenter * tan(rotationAngle / 2))
	local laneInnerEdgeLength     = 2 * (laneInnerDistanceFromCenter * tan(rotationAngle / 2))
	local centerPolygonEdgeLength = 2 * (centerPolygonWidth * tan(rotationAngle / 2))

	local laneShape = RampartHorizontallyWalledTrapezoid:new{
		p1 = laneRotation:getRotatedPoint({ x = centerX, y = centerY - laneOuterDistanceFromCenter }),
		p2 = laneRotation:getRotatedPoint({ x = centerX, y = centerY - laneInnerDistanceFromCenter }),
		width1 = laneOuterEdgeLength + INTERSECTION_EPSILON,
		width2 = laneInnerEdgeLength + INTERSECTION_EPSILON
	}
	local laneRightVector = laneShape.frontVector
	table.insert(shapes, laneShape)

	local centerRampRotation = laneRotation
	local centerRampLengthMult = (1.0 / tan(rad(CENTER_RAMP_MAX_SLOPE_ANGLE))) * CENTER_RAMP_LENGTH_MULT
	local centerRampDesiredLength = (RAMPART_HEIGHT - RAMPART_CENTER_HEIGHT) * centerRampLengthMult
	local centerRampMaxLength = max(0, centerPolygonWidth - CENTER_FLAT_AREA_MIN_WIDTH)
	local centerRampLength = min(centerRampDesiredLength, centerRampMaxLength)
	local centerRampLowerHeight = RAMPART_HEIGHT - floor(centerRampLength / centerRampLengthMult)
	local centerFlatAreaWidth = centerPolygonWidth - centerRampLength

	if (centerFlatAreaWidth > 0) then
		local centerFlatAreaRadius = centerFlatAreaWidth / cos(rotationAngle / 2)

		table.insert(uniqueShapes, RampartFlatCircle:new{
			center = { x = centerX, y = centerY },
			radius = centerFlatAreaRadius,
			groundHeight = centerRampLowerHeight,
			rampartTerrainType = RAMPART_DARK_TERRAIN_TYPE
		})
	end
	if (centerRampLength > 0) then
		local centerFlatAreaEdgeWidth = 2 * (centerFlatAreaWidth * tan(rotationAngle / 2))

		table.insert(shapes, RampartRampTrapezoid:new{
			p1 = centerRampRotation:getRotatedPoint({ x = centerX, y = centerY - centerPolygonWidth }),
			p2 = centerRampRotation:getRotatedPoint({ x = centerX, y = centerY - centerFlatAreaWidth }),
			width1 = centerPolygonEdgeLength + INTERSECTION_EPSILON,
			width2 = centerFlatAreaEdgeWidth + INTERSECTION_EPSILON,
			groundHeight1 = RAMPART_HEIGHT,
			groundHeight2 = centerRampLowerHeight,
			rampartTerrainType = RAMPART_DARK_TERRAIN_TYPE
		})
	end

	local centerEntranceStartY = centerY - laneInnerDistanceFromCenter
	local centerEntranceEndY   = centerY - centerPolygonWidth
	local centerEntranceWallStartY = centerEntranceStartY + RAMPART_WALL_INNER_TEXTURE_WIDTH
	local centerEntranceWallEndY   = centerEntranceEndY   - RAMPART_WALL_INNER_TEXTURE_WIDTH
	local centerPolygonInnerWallLength = 2 * ((centerPolygonWidth + RAMPART_WALL_INNER_TEXTURE_WIDTH) * tan(rotationAngle / 2))
	local centerPolygonOuterWallLength = 2 * ((centerPolygonWidth + RAMPART_WALL_WIDTH_TOTAL) * tan(rotationAngle / 2))
	local centerEntranceWidth = centerPolygonInnerWallLength * CENTER_ENTRANCE_RELATIVE_WIDTH - 2 * RAMPART_WALL_INNER_TEXTURE_WIDTH

	table.insert(shapes, RampartFlatTrapezoid:new{
		p1 = centerRampRotation:getRotatedPoint({ x = centerX, y = centerEntranceWallEndY }),
		p2 = centerRampRotation:getRotatedPoint({ x = centerX, y = centerEntranceEndY }),
		width1 = centerPolygonInnerWallLength + INTERSECTION_EPSILON,
		width2 = centerPolygonEdgeLength      + INTERSECTION_EPSILON
	})
	table.insert(shapes, RampartInternalWallTrapezoid:new{
		p1 = centerRampRotation:getRotatedPoint({ x = centerX, y = centerEntranceWallStartY }),
		p2 = centerRampRotation:getRotatedPoint({ x = centerX, y = centerEntranceWallEndY }),
		width1 = centerPolygonOuterWallLength + INTERSECTION_EPSILON,
		width2 = centerPolygonInnerWallLength + INTERSECTION_EPSILON,
		hasVerticalOuterTexture = false
	})
	table.insert(shapes, RampartVerticallyWalledRectangle:new{
		p1 = centerRampRotation:getRotatedPoint({ x = centerX, y = centerEntranceStartY }),
		p2 = centerRampRotation:getRotatedPoint({ x = centerX, y = centerEntranceEndY }),
		width = centerEntranceWidth
	})

	--spEcho("Lane distance from center: " .. laneDistanceFromCenter)
	--spEcho("Lane end distance from center: " .. centerLaneEndDistanceFromCenter)
	--spEcho("Lane length: " .. shapes[#shapes].height)

	--spEcho("Lane inner distance from center: " .. laneInnerDistanceFromCenter)
	spEcho("Lane extra width: " .. string.format("%.2f", laneExtendWidth))

	-- resource paths
	local spadePath, spadeHandlePath, lanePath = GenerateResourcePaths(spadeHandlePosY, spadeHandleAnchorPos, spadeRotation, spadeRotationAngle, laneStartPoint, laneEndPoint)
	--]]

	-- metal spots
	local uniqueMetalSpots, metalSpots = GenerateMetalSpots(numBases, spadePath, spadeHandlePath, laneStartPoint, lanePath, laneRightVector)

	-- geo spots
	local uniqueGeoSpots, geoSpots = GenerateGeoSpots(spadePath, lanePath, laneRightVector)

	-- start box
	local startBox, startPoint = GenerateStartBox(spadeHandlePosY, spadeRotation, spadeRotationAngle)

	return uniqueShapes, shapes, uniqueMetalSpots, metalSpots, uniqueGeoSpots, geoSpots, startBox, startPoint
end

-- Fix last base being the first from top clockwise
local function FixLastBaseClockwiseOrder(numBases, rotationAngle, initialAngle, playerStartPoint)
	local lastBaseRotationAngle = initialAngle + (numBases - 1) * rotationAngle
	local lastBaseRotation = Rotation2D:new({
		centerX  = centerX,
		centerY  = centerY,
		angleRad = lastBaseRotationAngle
	})

	local lastBaseStartPoint = lastBaseRotation:getRotatedPoint(playerStartPoint)

	if (lastBaseStartPoint.x >= centerX) then  -- Last base is past 12 o'clock
		initialAngle = initialAngle - rotationAngle  -- Rotate all bases by one base to the left
	end

	return initialAngle
end

local function GenerateRampartGeometry(numBases, startBoxNumberByBaseNumber)
	local rotationAngle = rad(360) / numBases
	local initialAngle = random() * rotationAngle
	if (OVERWRITE_INITIAL_ANGLE) then
		initialAngle = OVERWRITE_INITIAL_ANGLE * rotationAngle
	end

	local playableAreaShape = GeneratePlayableAreaShape(numBases)
	local uniqueShapes, playerShapes, uniqueMetalSpots, playerMetalSpots, uniqueGeoSpots, playerGeoSpots, playerStartBox, playerStartPoint = GenerateGeometryForSingleBase(numBases, rotationAngle)
	local rampartShapes = uniqueShapes
	local metalSpots = uniqueMetalSpots
	local geoSpots = uniqueGeoSpots
	local startBoxes = {}
	local baseSymbols = {}

	-- Fix last base being the first from top clockwise
	initialAngle = FixLastBaseClockwiseOrder(numBases, rotationAngle, initialAngle, playerStartPoint)

	local rotations = {}

	for i = 1, numBases do
		local currentRotationAngle = initialAngle + (i - 1) * rotationAngle
		local rotation = Rotation2D:new({
			centerX  = centerX,
			centerY  = centerY,
			angleRad = currentRotationAngle
		})
		rotations[i] = rotation
	end

	for j = 1, #playerShapes do
		local currentShape = playerShapes[j]

		for i = 1, numBases do
			local rotation = rotations[i]
			local rotatedShape = currentShape:getRotatedInstance(rotation)
			table.insert(rampartShapes, rotatedShape)
		end
	end

	for i = 1, numBases do
		local rotation = rotations[i]

		for j = 1, #playerMetalSpots do
			local currentMetalSpot = playerMetalSpots[j]
			local rotatedMetalSpot = getRotatedMetalSpot(currentMetalSpot, rotation)
			table.insert(metalSpots, rotatedMetalSpot)
		end

		for j = 1, #playerGeoSpots do
			local currentGeoSpot = playerGeoSpots[j]
			local rotatedGeoSpot = rotation:getRotatedPoint(currentGeoSpot)
			table.insert(geoSpots, rotatedGeoSpot)
		end

		local rotatedStartPoint = rotation:getRotatedPoint(playerStartPoint)
		local currentBaseSymbol = BASE_SYMBOLS[i]
		
		local startBoxNumber = startBoxNumberByBaseNumber[i]
		if (startBoxNumber) then
			local startBoxPoints = {}

			for j = 1, #playerStartBox do
				local currentPoint = playerStartBox[j]
				local rotatedPoint = rotation:getRotatedPoint(currentPoint)
				table.insert(startBoxPoints, rotatedPoint)
			end

			startBoxes[startBoxNumber] = {
				box        = startBoxPoints,
				startPoint = rotatedStartPoint,
				symbol     = currentBaseSymbol
			}
		end

		table.insert(baseSymbols, {
			x = rotatedStartPoint.x,
			z = rotatedStartPoint.y,
			symbol = currentBaseSymbol
		})
	end

	spClearWatchDogTimer()

	spEcho("Map geometry info generated. Number of shapes: " .. #rampartShapes)

	return playableAreaShape, rampartShapes, metalSpots, geoSpots, startBoxes, baseSymbols
end

--------------------------------------------------------------------------------

local function ApplyMetalSpots(metalSpots)
	for i = 1, #metalSpots do
		local spot = metalSpots[i]
		spot.x = roundToBuildingCenter(spot.x)
		spot.z = roundToBuildingCenter(spot.z)
	end

	GG.mapgen_mexList = metalSpots
	_G.mapgen_mexList = metalSpots

	spEcho("MetalSpots saved")
end

local function ApplyGeoSpots(geoSpots)
	for i = 1, #geoSpots do
		local geoSpot = geoSpots[i]
		geoSpots[i] = {
			x = roundToBuildingCenter(geoSpot.x),
			z = roundToBuildingCenter(geoSpot.y)
		}
	end

	GG.mapgen_geoList = geoSpots
	_G.mapgen_geoList = geoSpots
end

local function ApplyStartBoxes(startBoxes, numStartBoxes)
	for i = 1, numStartBoxes do
		startBoxes[i]            = startBoxes[i] or {}
		startBoxes[i].box        = startBoxes[i].box or {}
		startBoxes[i].startPoint = startBoxes[i].startPoint or { x = 0, y = 0 }
		startBoxes[i].symbol     = startBoxes[i].symbol or tostring(i)

		local startBoxPoints = startBoxes[i].box
		for j = 1, #startBoxPoints do
			local point = startBoxPoints[j]
			startBoxPoints[j] = { point.x, point.y }
		end
		
		local startPoint = startBoxes[i].startPoint
		startBoxes[i].startPoint = { startPoint.x, startPoint.y }
	end

	GG.mapgen_startBoxes = startBoxes
end

local function ApplyBaseSymbols(baseSymbols)
	_G.mapgen_baseSymbols = baseSymbols
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--function gadget:Initialize()
do
	local mapOptions = spGetMapOptions()
	InitRandomSeed(mapOptions)
	local numBases, numStartBoxes, startBoxNumberByBaseNumber = InitNumberOfBases(mapOptions)

	spEcho("Starting map terrain generation...")
	local GenerateStart = spGetTimer()

	local playableAreaShape, rampartShapes, metalSpots, geoSpots, startBoxes, baseSymbols = GenerateRampartGeometry(numBases, startBoxNumberByBaseNumber)
	ApplyMetalSpots(metalSpots)
	ApplyGeoSpots(geoSpots)
	ApplyStartBoxes(startBoxes, numStartBoxes)
	ApplyBaseSymbols(baseSymbols)

	local TG = TerrainGenerator

	local heightMap, modifiedHeightMapSquares = TG.InitHeightMap()
	local typeMap  , modifiedTypeMapSquares   = TG.InitTypeMap()
	TG.GeneratePlayableArea(playableAreaShape, typeMap, modifiedTypeMapSquares)
	TG.GenerateHeightMap(rampartShapes, heightMap, modifiedHeightMapSquares)
	TG.GenerateTypeMap(rampartShapes, typeMap, modifiedTypeMapSquares)
	TG.ApplyHeightMap(heightMap, modifiedHeightMapSquares)
	TG.ApplyTypeMap(typeMap, modifiedTypeMapSquares)

	heightMap = nil
	typeMap = nil
	modifiedHeightMapSquares = nil
	modifiedTypeMapSquares = nil

	PrintTimeSpent("Finished map terrain generation", " - total time: ", GenerateStart)
end

return false -- unload
