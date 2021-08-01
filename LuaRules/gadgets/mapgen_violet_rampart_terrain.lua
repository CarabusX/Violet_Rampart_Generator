function gadget:GetInfo()
	return {
		name      = "Violet Rampart Terrain Generator",
		desc      = "Procedurally generates Violet Rampart heightmap, metalspots, geos and startboxes",
		author    = "Rafal[ZK]",
		date      = "July 2021",
		license   = "GNU GPL, v2 or later",
		layer     = -1000001, -- before mex_spot_finder
		enabled   = true  --  loaded by default?
	}
end

local VRG_Config = VFS.Include("LuaRules/Configs/mapgen_violet_rampart_config.lua")

local ENABLE_SYNCED_PROFILING        = VRG_Config.ENABLE_SYNCED_PROFILING  -- enables profiling of Synced code by running it again in Unsynced context
local VISUALIZE_MODIFIED_MAP_SQUARES = VRG_Config.VISUALIZE_MODIFIED_MAP_SQUARES

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
local spGetMapOptions           = Spring.GetMapOptions
local spClearWatchDogTimer      = Spring.ClearWatchDogTimer
local spEcho                    = Spring.Echo

-- SYNCED only
local spSetHeightMapFunc        = Spring.SetHeightMapFunc
local spLevelHeightMap          = Spring.LevelHeightMap
local spSetHeightMap            = Spring.SetHeightMap
local spSetGameRulesParam       = Spring.SetGameRulesParam
local spSetMapSquareTerrainType = Spring.SetMapSquareTerrainType

-- UNSYNCED only
local spGetTimer                = Spring.GetTimer

--------------------------------------------------------------------------------

local min    = math.min
local max    = math.max
local abs    = math.abs
local floor  = math.floor
local ceil   = math.ceil
local round  = math.round
local sqrt   = math.sqrt
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
local halfSquareSize = squareSize / 2
local NUM_BLOCKS_X = mapSizeX / squareSize
local NUM_BLOCKS_Z = mapSizeZ / squareSize

local MAP_SQUARE_SIZE = 1024
local NUM_SQUARES_X = mapSizeX / MAP_SQUARE_SIZE
local NUM_SQUARES_Z = mapSizeZ / MAP_SQUARE_SIZE
local BLOCKS_PER_SQUARE = MAP_SQUARE_SIZE / squareSize

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
	-- mock Synced API methods
	spSetHeightMapFunc        = function (func) func() end
	spLevelHeightMap          = function () end
	spSetHeightMap            = function () end
	spSetGameRulesParam       = function () end
	spSetMapSquareTerrainType = function () end

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
local CENTER_POLYGON_DESIRED_WIDTH_MIN = 880
local CENTER_POLYGON_DESIRED_WIDTH_FACTOR = 0.45 -- [0.0, 1.0] - by what factor we move center polygon edges towards desired width
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

-- (for minimap generation with 5 bases)
--local OVERWRITE_NUMBER_OF_BASES = 5
--local OVERWRITE_SPADE_ROTATION_ANGLE = 0.0
--local OVERWRITE_INITIAL_ANGLE = 0.0

-- (for minimap generation with 6 bases)
--local OVERWRITE_NUMBER_OF_BASES = 6
--local OVERWRITE_SPADE_ROTATION_ANGLE = 0.0
--local OVERWRITE_INITIAL_ANGLE = 0.5 -- 0.5 -- 0.0

-- (for minimap generation with 7 bases)
--local OVERWRITE_NUMBER_OF_BASES = 7
--local OVERWRITE_SPADE_ROTATION_ANGLE = 0.0
--local OVERWRITE_INITIAL_ANGLE = 0.0

--------------------------------------------------------------------------------

-- wall thickness
local RAMPART_WALL_INNER_TEXTURE_WIDTH = 8 + 4
local RAMPART_WALL_WIDTH = 48
local RAMPART_WALL_OUTER_WIDTH = 8
local RAMPART_WALL_OUTER_TYPEMAP_WIDTH = -4
local RAMPART_WALL_OUTER_TEXTURE_WIDTH = 40 - 4

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

-- terrain types
local BOTTOM_TERRAIN_TYPE       = 0
local RAMPART_TERRAIN_TYPE      = 1
local RAMPART_WALL_TERRAIN_TYPE = 2
local RAMPART_WALL_OUTER_TYPE   = 3

local typeMapValueByTerrainType = {
	[BOTTOM_TERRAIN_TYPE]       = 0,
	[RAMPART_TERRAIN_TYPE]      = 1,
	[RAMPART_WALL_TERRAIN_TYPE] = 2,
	[RAMPART_WALL_OUTER_TYPE]   = 0,
}

local INITIAL_TERRAIN_TYPE   = BOTTOM_TERRAIN_TYPE
local INITIAL_TYPE_MAP_VALUE = typeMapValueByTerrainType[INITIAL_TERRAIN_TYPE]

--------------------------------------------------------------------------------

-- resources
local NUM_SPADE_MEXES = 5
local NUM_SPADE_HANDLE_MEXES = 2
local NUM_CENTER_LANE_MEXES = 3

local SPADE_MEXES_METAL = 2.0
local SPADE_HANDLE_MEXES_METAL = 1.5
local SPADE_ENTRANCE_MEX_METAL = 3.0
local CENTER_LANE_MEXES_METAL = 1.5

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

Vector2D = createClass()

function Vector2D:new (obj)
	obj = obj or {}
	setmetatable(obj, self)
	return obj
end

function Vector2D:getLength()
	return sqrt(self.x * self.x + self.y * self.y)
end

function Vector2D:setLength(newLength)
	local oldLength = self:getLength()
	local mult = newLength / oldLength
	self.x = self.x * mult	
	self.y = self.y * mult
end

function Vector2D.UnitVectorFromDir(dirVector)
	local v = Vector2D:new{
		x = dirVector.x,
		y = dirVector.y
	}
	v:setLength(1.0)
	return v
end

function Vector2D.UnitVectorFromPoints(p1, p2)
	local v = Vector2D:new{
		x = p2.x - p1.x,
		y = p2.y - p1.y
	}
	v:setLength(1.0)
	return v
end

function Vector2D:toRotated90()
	return Vector2D:new{
		x = -self.y,
		y = self.x
	}
end

function Vector2D:toRotated270()
	return Vector2D:new{
		x = self.y,
		y = -self.x
	}
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

Rotation2D = createClass()

function Rotation2D:new (obj)
	obj = obj or {}
	obj.angleSin = sin(obj.angleRad)
	obj.angleCos = cos(obj.angleRad)

	setmetatable(obj, self)
	return obj
end

function Rotation2D:getRotatedPoint(p)
	local dx = p.x - self.centerX
	local dy = p.y - self.centerY
	return {		
		x = self.centerX + dx * self.angleCos - dy * self.angleSin,
		y = self.centerY + dx * self.angleSin + dy * self.angleCos
	}
end

local function pointToMetalSpot(p, metal)
	return {		
		x = p.x,
		z = p.y,
		metal = metal
	}
end

function Rotation2D:getRotatedMetalSpot(spot)
	local spotPoint = {
		x = spot.x,
		y = spot.z
	}
	local rotatedPoint = self:getRotatedPoint(spotPoint)
	return pointToMetalSpot(rotatedPoint, spot.metal)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function clamp(minValue, value, maxValue)
	return min(max(minValue, value), maxValue)
end

local function PointCoordsDistance (p1, x, y)
	local dx = x - p1.x
	local dy = y - p1.y
	return sqrt(dx * dx + dy * dy)
end

local function PointCoordsSquaredDistance (p1, x, y)
	local dx = x - p1.x
	local dy = y - p1.y
	return (dx * dx + dy * dy)
end

local function PointPointDistance (p1, p2)
	local dx = p2.x - p1.x
	local dy = p2.y - p1.y
	return sqrt(dx * dx + dy * dy)
end

local function LineCoordsDistance (p, v, x, y)
	return abs(-v.x * (y - p.y) + v.y * (x - p.x))
end

local function LineCoordsProjection (p, v, x, y) -- can be negative
	return (v.x * (x - p.x) + v.y * (y - p.y))
end

local function LineVectorLengthProjection (dirV, vx, vy)
	return abs(dirV.x * vx + dirV.y * vy)
end

local function AddRandomOffsetInDirection(p, maxOffset, dirVector)
	local offset = (-1.0 + 2.0 * random()) * maxOffset
	return {
		x = p.x + offset * dirVector.x,
		y = p.y + offset * dirVector.y
	}
end

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

local function roundToBuildingCenter (x)
	return (round(((x / squareSize) - 1) / 2) * 2 + 1) * squareSize
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

LineSegment = createClass()

function LineSegment:new(obj)
	obj = obj or {}
	obj.length      = PointPointDistance(obj.p1, obj.p2)
	obj.frontVector = Vector2D.UnitVectorFromPoints(obj.p1, obj.p2)

	setmetatable(obj, self)
	return obj
end

function LineSegment:getPointOnSegment(advance)
	return {
		x = self.p1.x + self.frontVector.x * advance,
		y = self.p1.y + self.frontVector.y * advance
	}
end

--------------------------------------------------------------------------------

ArcSegment = createClass()

function ArcSegment:new(obj)
	obj = obj or {}
	obj.length = obj.angularLengthRad * obj.radius

	setmetatable(obj, self)
	return obj
end

function ArcSegment:getPointOnSegment(advance)
	local angularAdvanceRad = (advance / self.length) * self.angularLengthRad
	local angleRad = self.startAngleRad + angularAdvanceRad
	return {
		x = self.center.x + self.radius * sin(angleRad),
		y = self.center.y - self.radius * cos(angleRad)
	}
end

--------------------------------------------------------------------------------

SegmentedPath = createClass()

function SegmentedPath:new(obj)
	obj = obj or {}
	obj.segments = obj.segments or {}
	obj.totalLength = 0
	for i = 1, #(obj.segments) do
		local segment = obj.segments[i]
		obj.totalLength = obj.totalLength + segment.length
	end

	setmetatable(obj, self)
	return obj
end

function SegmentedPath.ofSegment(segment)
	return SegmentedPath:new{ segments = {segment} }
end

function SegmentedPath.ofSegments(segments)
	return SegmentedPath:new{ segments = segments }
end

function SegmentedPath:addSegment(segment)
	table.insert(self.segments, segment)
	self.totalLength = self.totalLength + segment.length
end

function SegmentedPath:getPointAtAdvance(advance)
	if (#(self.segments) == 0) then
		return nil
	end
	if (advance <= 0) then
		return self.segments[1]:getPointOnSegment(0)
	end

	if (advance < self.totalLength) then
		for i = 1, #(self.segments) do
			local segment = self.segments[i]
			if (advance <= segment.length) then
				return segment:getPointOnSegment(advance)
			else
				advance = advance - segment.length
			end
		end
	end
	
	local lastSegment = self.segments[#self.segments]
	return lastSegment:getPointOnSegment(lastSegment.length)
end

function SegmentedPath:getPointAtRelativeAdvance(relAdvance)
	local advance = relAdvance * self.totalLength
	return self:getPointAtAdvance(advance)
end

function SegmentedPath:getPointsOnPath(numInnerPoints, includeStartAndEnd)
	if (#(self.segments) == 0) then
		return {}
	end

	local points = {}

	if (includeStartAndEnd) then		
		table.insert(points, self:getPointAtAdvance(0))		
	end

	if (numInnerPoints >= 1) then
		local step = self.totalLength / (numInnerPoints + 1)
		for i = 1, numInnerPoints do
			local advance = i * step
			table.insert(points, self:getPointAtAdvance(advance))
		end
	end

	if (includeStartAndEnd) then
		table.insert(points, self:getPointAtAdvance(self.totalLength))		
	end
	
	return points
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
				if (typeMapX[tmz] ~= RAMPART_TERRAIN_TYPE) then -- do not overwrite inner rampart
					typeMapX[tmz] = RAMPART_WALL_TERRAIN_TYPE
				end
			else
				if (typeMapX[tmz] == BOTTOM_TERRAIN_TYPE) then -- do not overwrite rampart or wall
					typeMapX[tmz] = RAMPART_WALL_OUTER_TYPE
				end
			end
		else
			typeMapX[tmz] = RAMPART_TERRAIN_TYPE
		end
	else
		return false
	end

	return true
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
	INTERSECTION_EPSILON = INTERSECTION_EPSILON,
	RAMPART_HEIGHT = RAMPART_HEIGHT,

	-- Export functions

	PointCoordsDistance = PointCoordsDistance,
	PointCoordsSquaredDistance = PointCoordsSquaredDistance,
	PointPointDistance = PointPointDistance,
	LineCoordsDistance = LineCoordsDistance,
	LineCoordsProjection = LineCoordsProjection,
	LineVectorLengthProjection = LineVectorLengthProjection,

	modifyHeightMapForWalledShape       = modifyHeightMapForWalledShape,
	modifyHeightMapForInternalWallShape = modifyHeightMapForInternalWallShape,
	modifyHeightMapForFlatShape         = modifyHeightMapForFlatShape,
	modifyHeightMapForRampShape         = modifyHeightMapForRampShape,
}

--------------------------------------------------------------------------------

RampartFullyWalledRectangle, RampartVerticallyWalledRectangle, RampartFlatRectangle =
	VFS.Include("LuaRules/Gadgets/TerrainGenerator/TerrainShapes/RampartRectangle.lua")
RampartHorizontallyWalledTrapezoid, RampartInternalWallTrapezoid, RampartFlatTrapezoid, RampartRampTrapezoid =
	VFS.Include("LuaRules/Gadgets/TerrainGenerator/TerrainShapes/RampartTrapezoid.lua")
RampartWalledCircle, RampartFlatCircle =
	VFS.Include("LuaRules/Gadgets/TerrainGenerator/TerrainShapes/RampartCircle.lua")

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

local function GenerateMetalSpots(spadePath, spadeHandlePath, laneStartPoint, lanePath, laneRightVector)
	local metalSpots = {}

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
	
	return metalSpots
end

local function GenerateGeoSpots(spadePath, lanePath, laneRightVector)
	local geoSpots = {}

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

	return geoSpots
end

local function GenerateStartBox(spadeHandlePosY, spadeRotation, spadeRotationAngle)
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

	return startBoxPoints, startPoint
end

local function GenerateGeometryForSingleBase(rotationAngle)
	local shapes = {}

	-- base
	local centerLaneEndDistanceFromCenter = max(
		CENTER_LANE_MIN_DISTANCE_FROM_CENTER / cos(rotationAngle / 2),
		CENTER_LANE_END_MIN_DISTANCE_FROM_CENTER,
		(CENTER_LANE_MIN_LENGTH / 2) / sin(rotationAngle / 2)
	)
	local spaceHandleOffsetFromLane = ((CENTER_LANE_WIDTH - SPADE_HANDLE_WIDTH) / 2) / cos(rotationAngle / 2)
	local spadeHandlePosY = centerY - centerLaneEndDistanceFromCenter - spaceHandleOffsetFromLane
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
		width = SPADE_HANDLE_WIDTH,
		extendBottom = spaceHandleOffsetFromLane
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
	local laneExtendHeight = (CENTER_LANE_WIDTH / 2 + RAMPART_WALL_WIDTH_TOTAL) * tan(rotationAngleOrComplement / 2) - RAMPART_WALL_WIDTH_TOTAL
	local laneEndRotation = Rotation2D:new({
		centerX  = centerX,
		centerY  = centerY,
		angleRad = rotationAngle
	})
	local laneStartPoint = { x = centerX, y = centerY - centerLaneEndDistanceFromCenter }
	local laneEndPoint = laneEndRotation:getRotatedPoint(laneStartPoint)
	local laneDistanceFromCenter = centerLaneEndDistanceFromCenter * cos(rotationAngle / 2)
	local laneInnerDistanceFromCenter = laneDistanceFromCenter - (CENTER_LANE_WIDTH / 2 + RAMPART_WALL_OUTER_WIDTH_TOTAL)
	local laneExtendWidth = max(0, laneInnerDistanceFromCenter - CENTER_POLYGON_DESIRED_WIDTH_MIN) * CENTER_POLYGON_DESIRED_WIDTH_FACTOR
	local laneShape = RampartVerticallyWalledRectangle:new{
		p1 = laneStartPoint,
		p2 = laneEndPoint,
		width = CENTER_LANE_WIDTH,
		extendHeight = laneExtendHeight,
		extendRight  = laneExtendWidth
	}
	local laneRightVector = laneShape.rightVector
	table.insert(shapes, laneShape)

	--spEcho("Lane distance from center: " .. laneDistanceFromCenter)
	--spEcho("Lane end distance from center: " .. centerLaneEndDistanceFromCenter)
	--spEcho("Lane length: " .. (shapes[#shapes].height - 2 * laneExtendHeight))

	--spEcho("Lane inner distance from center: " .. laneInnerDistanceFromCenter)
	spEcho("Lane extra width: " .. string.format("%.2f", laneExtendWidth))

	-- resource paths
	local spadePath, spadeHandlePath, lanePath = GenerateResourcePaths(spadeHandlePosY, spadeHandleAnchorPos, spadeRotation, spadeRotationAngle, laneStartPoint, laneEndPoint)

	-- metal spots
	local metalSpots = GenerateMetalSpots(spadePath, spadeHandlePath, laneStartPoint, lanePath, laneRightVector)

	-- geo spots
	local geoSpots = GenerateGeoSpots(spadePath, lanePath, laneRightVector)

	-- start box
	local startBox, startPoint = GenerateStartBox(spadeHandlePosY, spadeRotation, spadeRotationAngle)

	return shapes, metalSpots, geoSpots, startBox, startPoint
end

local function GenerateRampartGeometry(numBases, startBoxNumberByBaseNumber)
	local rotationAngle = rad(360) / numBases
	local initialAngle = random() * rotationAngle
	if (OVERWRITE_INITIAL_ANGLE) then
		initialAngle = OVERWRITE_INITIAL_ANGLE * rotationAngle
	end

	local playerShapes, playerMetalSpots, playerGeoSpots, playerStartBox, playerStartPoint = GenerateGeometryForSingleBase(rotationAngle)
	local rampartShapes = {}
	local metalSpots = {}
	local geoSpots = {}
	local startBoxes = {}
	local baseSymbols = {}

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
			local rotatedMetalSpot = rotation:getRotatedMetalSpot(currentMetalSpot)
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

	return rampartShapes, metalSpots, geoSpots, startBoxes, baseSymbols
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
-- heightMap and typeMap

local function InitHeightMap()
	local startTime = spGetTimer()

	-- heightMap
	local heightMap = {}
	for x = 0, mapSizeX, squareSize do
		heightMap[x] = {}
		local heightMapX = heightMap[x]
		for z = 0, mapSizeZ, squareSize do
			heightMapX[z] = BOTTOM_HEIGHT
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

				spClearWatchDogTimer()
			end
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
					local wasInsideShape = modifyTypeMapForWalledShape(currentShape, typeMapX, tmz, x, z)

					if (wasInsideShape) then
						finishColumnIfOutsideWalls = true
					elseif (finishColumnIfOutsideWalls) then
						break  -- we were in walls and now we are outside, so no more blocks in this column (assumes shape is convex)
					end
				end

				spClearWatchDogTimer()
			end
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
		spLevelHeightMap(0, 0, mapSizeX, mapSizeZ, BOTTOM_HEIGHT) -- this is fast
		spClearWatchDogTimer()

		ProcessBlocksInModifiedHeightMapSquares(modifiedHeightMapSquares,
		function (x1, x2, z1, z2)
			for x = x1, x2, squareSize do
				local heightMapX = heightMap[x]

				for z = z1, z2, squareSize do
					local height = heightMapX[z]
					if (height ~= BOTTOM_HEIGHT) then
						spSetHeightMap(x, z, height)
					end
				end
			end
			spClearWatchDogTimer()
		end)
	end)
	--spEcho('totalHeightMapAmountChanged: ' .. totalHeightMapAmountChanged)

	GG.mapgen_origHeight = heightMap
	OverrideGetGroundOrigHeight()

	spSetGameRulesParam("ground_min_override", BOTTOM_HEIGHT)
	spSetGameRulesParam("ground_max_override", RAMPART_WALL_HEIGHT)

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
				if (typeMapValue ~= INITIAL_TYPE_MAP_VALUE) then
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

--function gadget:Initialize()
do
	local mapOptions = spGetMapOptions()
	InitRandomSeed(mapOptions)
	local numBases, numStartBoxes, startBoxNumberByBaseNumber = InitNumberOfBases(mapOptions)

	spEcho("Starting map terrain generation...")
	local GenerateStart = spGetTimer()

	local rampartShapes, metalSpots, geoSpots, startBoxes, baseSymbols = GenerateRampartGeometry(numBases, startBoxNumberByBaseNumber)
	ApplyMetalSpots(metalSpots)
	ApplyGeoSpots(geoSpots)
	ApplyStartBoxes(startBoxes, numStartBoxes)
	ApplyBaseSymbols(baseSymbols)

	local heightMap, modifiedHeightMapSquares = InitHeightMap()
	local typeMap  , modifiedTypeMapSquares   = InitTypeMap()
	GenerateHeightMap(rampartShapes, heightMap, modifiedHeightMapSquares)
	GenerateTypeMap(rampartShapes, typeMap, modifiedTypeMapSquares)
	ApplyHeightMap(heightMap, modifiedHeightMapSquares)
	ApplyTypeMap(typeMap, modifiedTypeMapSquares)

	heightMap = nil
	typeMap = nil
	modifiedHeightMapSquares = nil
	modifiedTypeMapSquares = nil

	PrintTimeSpent("Finished map terrain generation", " - total time: ", GenerateStart)
end

return false -- unload
