function gadget:GetInfo()
	return {
		name      = "Violet Rampart Terrain Generator",
		desc      = "Generates Violet Rampart heightmap, metalspots, geos and startboxes",
		author    = "Rafal[ZK]",
		date      = "July 2021",
		license   = "PD",
		layer     = -1000001, -- before mex_spot_finder
		enabled   = true  --  loaded by default?
	}
end

--------------------------------------------------------------------------------
-- Synced
--------------------------------------------------------------------------------

if (not gadgetHandler:IsSyncedCode()) then
  return false
end

if (Spring.GetGameFrame() >= 1) then
  return false
end

local GetMapOptions           = Spring.GetMapOptions
local spGetGroundHeight       = Spring.GetGroundHeight
local SetHeightMap            = Spring.SetHeightMap
local SetSmoothMesh           = Spring.SetSmoothMesh
local SetMapSquareTerrainType = Spring.SetMapSquareTerrainType

local min    = math.min
local max    = math.max
local abs    = math.abs
local floor  = math.floor
local ceil   = math.ceil
local sqrt   = math.sqrt
local sin    = math.sin
local cos    = math.cos
local random = math.random

local mapSizeX   = Game.mapSizeX
local mapSizeZ   = Game.mapSizeZ
local squareSize = Game.squareSize

local centerX = mapSizeX / 2
local centerY = mapSizeZ / 2

--------------------------------------------------------------------------------
-- CONFIG

-- map geometry
local CENTER_LANE_MIN_DISTANCE_FROM_CENTER = 900 -- limiting factor for 3 players
local CENTER_LANE_END_MIN_DISTANCE_FROM_CENTER = 1600 -- limiting factor for 4 or 5 players
local CENTER_LANE_MIN_LENGTH = 1900 -- limiting factor for >= 6 players
local CENTER_LANE_WIDTH = 900
local CENTER_LANE_MEX_MAX_PERPENDICULAR_OFFSET = 0 -- 0.2 * CENTER_LANE_WIDTH
local CENTER_LANE_GEO_MAX_PERPENDICULAR_OFFSET = 0.2 * CENTER_LANE_WIDTH
local SPADE_HANDLE_WIDTH  = 600
local SPADE_HANDLE_HEIGHT = 1100 --1500
local SPADE_WIDTH  = 1200
local SPADE_HEIGHT = 800
local SPADE_RESOURCE_PATH_RADIUS = 350

--------------------------------------------------------------------------------

-- wall thickness
local RAMPART_WALL_INNER_TEXTURE_WIDTH = 8
local RAMPART_WALL_WIDTH = 48
local RAMPART_WALL_OUTER_WIDTH = 8
local RAMPART_WALL_OUTER_TEXTURE_WIDTH = 32

local RAMPART_WALL_WIDTH_TOTAL               = RAMPART_WALL_INNER_TEXTURE_WIDTH + RAMPART_WALL_WIDTH
local RAMPART_WALL_OUTER_WIDTH_TOTAL         = RAMPART_WALL_INNER_TEXTURE_WIDTH + RAMPART_WALL_WIDTH + RAMPART_WALL_OUTER_WIDTH
local RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL = RAMPART_WALL_INNER_TEXTURE_WIDTH + RAMPART_WALL_WIDTH + RAMPART_WALL_OUTER_WIDTH + RAMPART_WALL_OUTER_TEXTURE_WIDTH

-- heightmap
local BOTTOM_HEIGHT       = -150
local RAMPART_HEIGHT      =  300
local RAMPART_WALL_HEIGHT =  370 -- 380
local RAMPART_WALL_OUTER_HEIGHT = 1

-- terrain types
local BOTTOM_TERRAIN_TYPE       = 0
local RAMPART_TERRAIN_TYPE      = 1
local RAMPART_WALL_TERRAIN_TYPE = 2

local INITIAL_TERRAIN_TYPE = BOTTOM_TERRAIN_TYPE

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

-- end of CONFIG
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

Vector2D = {}

function Vector2D:new (obj)
	obj = obj or {}
	setmetatable(obj, self)
	self.__index = self
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

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

Rotation2D = {}

function Rotation2D:new (obj)
	obj = obj or {}
	obj.angleSin = sin(obj.angleRad)
	obj.angleCos = cos(obj.angleRad)

	setmetatable(obj, self)
	self.__index = self
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
	local spotPoint = { x = spot.x, y = spot.z }
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

local function PointPointDistance (p1, p2)
	local dx = p2.x - p1.x
	local dy = p2.y - p1.y
	return sqrt(dx * dx + dy * dy)
end

local function LineCoordsDistance (p, v, x, y)
	return abs(v.x * (p.y - y) - (p.x - x) * v.y)
end

local function AddRandomOffsetInDirection(p, maxOffset, dirVector)
	local offset = (-1.0 + 2.0 * math.random()) * maxOffset
	return {
		x = p.x + offset * dirVector.x,
		y = p.y + offset * dirVector.y
	}
end

local function roundUpToBlock (x)
	return ceil(x / squareSize) * squareSize
end

local function roundDownToBlock (x)
	return floor(x / squareSize) * squareSize
end

local function aabbToBlocksRange (aabb)
	return {		
		x1 = max(0       , roundUpToBlock  (aabb.x1)),
		y1 = max(0       , roundUpToBlock  (aabb.y1)),
		x2 = min(mapSizeX, roundDownToBlock(aabb.x2)),
		y2 = min(mapSizeZ, roundDownToBlock(aabb.y2))
	}
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

LineSegment = {}

function LineSegment:new(obj)
	obj = obj or {}
	obj.length      = PointPointDistance(obj.p1, obj.p2)
	obj.frontVector = Vector2D.UnitVectorFromPoints(obj.p1, obj.p2)

	setmetatable(obj, self)
	self.__index = self
	return obj
end

function LineSegment:getPointOnSegment(advance)
	return {
		x = self.p1.x + self.frontVector.x * advance,
		y = self.p1.y + self.frontVector.y * advance
	}
end

--------------------------------------------------------------------------------

ArcSegment = {}

function ArcSegment:new(obj)
	obj = obj or {}
	obj.length = obj.angularLengthRad * obj.radius

	setmetatable(obj, self)
	self.__index = self
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

SegmentedPath = {}

function SegmentedPath:new(obj)
	obj = obj or {}
	obj.segments = obj.segments or {}
	obj.totalLength = 0
	for i = 1, #(obj.segments) do
		local segment = obj.segments[i]
		obj.totalLength = obj.totalLength + segment.length
	end

	setmetatable(obj, self)
	self.__index = self
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

RampartRectangle = {}

function RampartRectangle:new(obj)
	obj = obj or {}
	obj.center      = {
		x = (obj.p1.x + obj.p2.x) / 2,
		y = (obj.p1.y + obj.p2.y) / 2
	}
	obj.frontVector = Vector2D.UnitVectorFromPoints(obj.p1, obj.p2)
	obj.rightVector = obj.frontVector:toRotated90()
	if (obj.extendHeight and obj.extendHeight > 0) then
		obj.p1 = {
			x = obj.p1.x - obj.frontVector.x * obj.extendHeight,
			y = obj.p1.y - obj.frontVector.y * obj.extendHeight
		}
		obj.p2 = {
			x = obj.p2.x + obj.frontVector.x * obj.extendHeight,
			y = obj.p2.y + obj.frontVector.y * obj.extendHeight
		}
	end
	obj.height      = PointPointDistance(obj.p1, obj.p2)

	setmetatable(obj, self)
	self.__index = self
	return obj
end

function RampartRectangle:getRotatedInstance(rotation)
	return RampartRectangle:new{		
		p1    = rotation:getRotatedPoint(self.p1),
		p2    = rotation:getRotatedPoint(self.p2),
		width = self.width
	}
end

function RampartRectangle:getPointInLocalSpace(localX, localY)
	return {
		self.center.x + self.rightVector.x * localX + self.frontVector.x * localY,
		self.center.y + self.rightVector.y * localX + self.frontVector.y * localY
	}
end

function RampartRectangle:isPointInsideOrOnWall (x, y)
	local halfWidth  = self.width  / 2
	local halfHeight = self.height / 2
	local distanceFromFrontAxis = LineCoordsDistance(self.center, self.frontVector, x, y)
	local distanceFromRightAxis = LineCoordsDistance(self.center, self.rightVector, x, y)

	local isInOuterWallsTexture = (
		distanceFromFrontAxis <= halfWidth  + RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL and
		distanceFromRightAxis <= halfHeight + RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL
	)
	local isInsideOuterWalls = isInOuterWallsTexture and (
		distanceFromFrontAxis <= halfWidth  + RAMPART_WALL_OUTER_WIDTH_TOTAL and
		distanceFromRightAxis <= halfHeight + RAMPART_WALL_OUTER_WIDTH_TOTAL
	)
	local isInWalls = isInsideOuterWalls and (
		distanceFromFrontAxis <= halfWidth  + RAMPART_WALL_WIDTH_TOTAL and
		distanceFromRightAxis <= halfHeight + RAMPART_WALL_WIDTH_TOTAL
	)
	local isInsideInnerWalls = isInWalls and (
		distanceFromFrontAxis < halfWidth  + RAMPART_WALL_INNER_TEXTURE_WIDTH and
		distanceFromRightAxis < halfHeight + RAMPART_WALL_INNER_TEXTURE_WIDTH
	)
	local isRampart = isInsideInnerWalls and (
		distanceFromFrontAxis < halfWidth  and
		distanceFromRightAxis < halfHeight
	)
	local isOuterWalls = (isInsideOuterWalls and not isInWalls)
	local isInnerWalls = (isInsideInnerWalls and not isRampart)
	local isWallsTexture = (isInOuterWallsTexture and not isRampart)

	--[[
	local outerWallFactor = isOuterWalls and min(
		halfWidth  + RAMPART_WALL_OUTER_WIDTH_TOTAL - distanceFromFrontAxis,
		halfHeight + RAMPART_WALL_OUTER_WIDTH_TOTAL - distanceFromRightAxis
	) / RAMPART_WALL_OUTER_WIDTH
	local innerWallFactor = isInnerWalls and min(
		distanceFromFrontAxis - halfWidth,
		distanceFromRightAxis - halfHeight
	) / RAMPART_WALL_INNER_TEXTURE_WIDTH
	]]--
	local outerWallFactor = 0.0
	local innerWallFactor = 0.0

	return isRampart, isInnerWalls, isInWalls, isOuterWalls, isInOuterWallsTexture, isWallsTexture, innerWallFactor, outerWallFactor
end

function RampartRectangle:getAABB()
	local outerHalfWidth  = self.width  / 2 + RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL
	local outerHalfHeight = self.height / 2 + RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL
	local rangeX = abs(self.frontVector.x) * outerHalfHeight + abs(self.rightVector.x) * outerHalfWidth
	local rangeY = abs(self.frontVector.y) * outerHalfHeight + abs(self.rightVector.y) * outerHalfWidth
	return {
		x1 = self.center.x - rangeX,
		y1 = self.center.y - rangeY,
		x2 = self.center.x + rangeX,
		y2 = self.center.y + rangeY
	}
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

RampartCircle = {}

function RampartCircle:new(obj)
	obj = obj or {}

	setmetatable(obj, self)
	self.__index = self
	return obj
end

function RampartCircle:getRotatedInstance(rotation)
	return RampartCircle:new{		
		center = rotation:getRotatedPoint(self.center),
		radius = self.radius
	}
end

function RampartCircle:isPointInsideOrOnWall (x, y)
	local distanceFromCenter = PointCoordsDistance(self.center, x, y)

	local isInOuterWallsTexture = (
		distanceFromCenter <= self.radius + RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL
	)
	local isInsideOuterWalls = isInOuterWallsTexture and (
		distanceFromCenter <= self.radius + RAMPART_WALL_OUTER_WIDTH_TOTAL
	)
	local isInWalls = isInsideOuterWalls and (
		distanceFromCenter <= self.radius + RAMPART_WALL_WIDTH_TOTAL
	)
	local isInsideInnerWalls = isInWalls and (
		distanceFromCenter < self.radius + RAMPART_WALL_INNER_TEXTURE_WIDTH
	)
	local isRampart = isInsideInnerWalls and (
		distanceFromCenter < self.radius
	)
	local isOuterWalls = (isInsideOuterWalls and not isInWalls)
	local isInnerWalls = (isInsideInnerWalls and not isRampart)
	local isWallsTexture = (isInOuterWallsTexture and not isRampart)

	--[[
	local outerWallFactor = isOuterWalls and (
		(self.radius + RAMPART_WALL_OUTER_WIDTH_TOTAL - distanceFromCenter) / RAMPART_WALL_OUTER_WIDTH
	)
	local innerWallFactor = isInnerWalls and (
		(distanceFromCenter - self.radius) / RAMPART_WALL_INNER_TEXTURE_WIDTH
	)
	]]--
	local outerWallFactor = 0.0
	local innerWallFactor = 0.0

	return isRampart, isInnerWalls, isInWalls, isOuterWalls, isInOuterWallsTexture, isWallsTexture, innerWallFactor, outerWallFactor
end

function RampartCircle:getAABB()
	local outerRadius = self.radius + RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL
	return {
		x1 = self.center.x - outerRadius,
		y1 = self.center.y - outerRadius,
		x2 = self.center.x + outerRadius,
		y2 = self.center.y + outerRadius
	}
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- map options

local function InitRandomSeed(mapOptions)
	local randomSeed

	if mapOptions and mapOptions.seed and tonumber(mapOptions.seed) ~= 0 then
		randomSeed = tonumber(mapOptions().seed)
	else
		randomSeed = math.random(1, 1000000)
	end

	math.randomseed(randomSeed)
	Spring.Echo("Using map generation random seed: " .. tostring(randomSeed))
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

	--local numBases = clamp(2, numAllyTeams, 11)
	local numBases = 7
	if (numBases <= 2) then
		numBases = 4
	end

	if mapOptions and mapOptions.numBases and tonumber(mapOptions.numBases) ~= 0 then
		local configNumBases = tonumber(mapOptions().numBases)
		if (3 <= configNumBases and configNumBases <= 11) then
			numBases = configNumBases
		end
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
			startAngleRad = spadeRotationAngle - math.rad(90),
			angularLengthRad = math.rad(180)
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
			startAngleRad = spadeRotationAngle - math.rad(90),
			angularLengthRad = math.rad(180)
		}
	)
	local startBoxPathPoints = startBoxPath:getPointsOnPath(20 - 1, true)

	local startBoxPoints = {}

	table.insert(startBoxPoints, startBoxFirstPoint)
	for _, point in ipairs(startBoxPathPoints) do
		table.insert(startBoxPoints, point)
	end
	table.insert(startBoxPoints, startBoxLastPoint)

	local startPoint = spadeRotation:getRotatedPoint({ x = centerX, y = spadeHandlePosY - SPADE_HANDLE_HEIGHT - (SPADE_HEIGHT / 2) })

	return startBoxPoints, startPoint
end

local function GenerateShapesForOnePlayer(rotationAngle)
	local shapes = {}

	-- base
	local centerLaneEndDistanceFromCenter = max(
		CENTER_LANE_MIN_DISTANCE_FROM_CENTER / math.cos(rotationAngle / 2),
		CENTER_LANE_END_MIN_DISTANCE_FROM_CENTER,
		(CENTER_LANE_MIN_LENGTH / 2) / math.sin(rotationAngle / 2)
	)
	local spaceHandleOffsetFromLane = ((CENTER_LANE_WIDTH - SPADE_HANDLE_WIDTH) / 2) / math.cos(rotationAngle / 2)
	local spadeHandlePosY = centerY - centerLaneEndDistanceFromCenter - spaceHandleOffsetFromLane
	local spadeHandleAnchorPos = { x = centerX, y = spadeHandlePosY }	
	local rotationAngleOrComplement = min(rotationAngle, math.rad(180) - rotationAngle)
	local spadeRotationRange = rotationAngleOrComplement
	local spadeRotationAngle = (-0.5 + math.random()) * spadeRotationRange
	local spadeRotation = Rotation2D:new({
		centerX  = centerX,
		centerY  = spadeHandlePosY,
		angleRad = spadeRotationAngle
	})
	table.insert(shapes, RampartRectangle:new{
		p1 = spadeHandleAnchorPos,
		p2 = spadeRotation:getRotatedPoint({ x = centerX, y = spadeHandlePosY - SPADE_HANDLE_HEIGHT }),
		width = SPADE_HANDLE_WIDTH
	})
	table.insert(shapes, RampartRectangle:new{
		p1 = spadeRotation:getRotatedPoint({ x = centerX, y = spadeHandlePosY - SPADE_HANDLE_HEIGHT }),
		p2 = spadeRotation:getRotatedPoint({ x = centerX, y = spadeHandlePosY - SPADE_HANDLE_HEIGHT - SPADE_HEIGHT }),
		width = SPADE_WIDTH
	})
	table.insert(shapes, RampartCircle:new{
		center = spadeRotation:getRotatedPoint({ x = centerX, y = spadeHandlePosY - SPADE_HANDLE_HEIGHT - SPADE_HEIGHT }),
		radius = SPADE_WIDTH / 2
	})

	-- lane
	local laneExtendHeight = (CENTER_LANE_WIDTH / 2) * math.tan(rotationAngleOrComplement / 2)
	local laneEndRotation = Rotation2D:new({
		centerX  = centerX,
		centerY  = centerY,
		angleRad = rotationAngle
	})
	local laneStartPoint = { x = centerX, y = centerY - centerLaneEndDistanceFromCenter }
	local laneEndPoint = laneEndRotation:getRotatedPoint(laneStartPoint)
	local laneShape = RampartRectangle:new{
		p1 = laneStartPoint,
		p2 = laneEndPoint,
		width = CENTER_LANE_WIDTH,
		extendHeight = laneExtendHeight
	}
	local laneRightVector = laneShape.rightVector
	table.insert(shapes, laneShape)
	--Spring.Echo("lane distance from center: " .. PointCoordsDistance(shapes[#shapes].center, centerX, centerY))
	--Spring.Echo("lane end distance from center: " .. centerLaneEndDistanceFromCenter)
	--Spring.Echo("lane length: " .. (shapes[#shapes].height - 2 * laneExtendHeight))

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

local function InitRampartShapes(numBases, startBoxNumberByBaseNumber)
	local rotationAngle = math.rad(360) / numBases
	local initialAngle = math.random() * rotationAngle

	local playerShapes, playerMetalSpots, playerGeoSpots, playerStartBox, playerStartPoint = GenerateShapesForOnePlayer(rotationAngle)
	local rampartShapes = {}
	local metalSpots = {}
	local geoSpots = {}
	local startBoxes = {}

	for i = 1, numBases do
		local currentRotationAngle = initialAngle + (i - 1) * rotationAngle
		local rotation = Rotation2D:new({
			centerX  = centerX,
			centerY  = centerY,
			angleRad = currentRotationAngle
		})

		for j = 1, #playerShapes do
			local currentShape = playerShapes[j]
			local rotatedShape = currentShape:getRotatedInstance(rotation)
			table.insert(rampartShapes, rotatedShape)
		end

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
		
		local startBoxNumber = startBoxNumberByBaseNumber[i]
		if (startBoxNumber) then
			local startBoxPoints = {}

			for j = 1, #playerStartBox do
				local currentPoint = playerStartBox[j]
				local rotatedPoint = rotation:getRotatedPoint(currentPoint)
				table.insert(startBoxPoints, rotatedPoint)
			end
			
			local rotatedStartPoint = rotation:getRotatedPoint(playerStartPoint)

			startBoxes[startBoxNumber] = {
				box        = startBoxPoints,
				startPoint = rotatedStartPoint
			}
		end
	end

	Spring.Echo("Map geometry info generated")

	return rampartShapes, metalSpots, geoSpots, startBoxes
end

--------------------------------------------------------------------------------

local function ApplyMetalSpots(metalSpots)
	--[[for i = 1, #metalSpots do
		local spot = metalSpots[i]
		--spot.y = spGetGroundHeight(spot.x, spot.z)
		spot.y = RAMPART_HEIGHT
	end--]]

	GG.mapgen_mexList = metalSpots

	Spring.Echo("MetalSpots saved")
end

local function ApplyGeoSpots(geoSpots)
	GG.mapgen_geoList = geoSpots
end

local function ApplyStartBoxes(startBoxes, numStartBoxes)
	for i = 1, numStartBoxes do
		startBoxes[i]            = startBoxes[i] or {}
		startBoxes[i].box        = startBoxes[i].box or {}
		startBoxes[i].startPoint = startBoxes[i].startPoint or {}

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

--------------------------------------------------------------------------------
-- heightmap

local function InitHeightMapAndTypeMap()
	local heightMap = {}
	local typeMap = {}
	for x = 0, mapSizeX, squareSize do
		heightMap[x] = {}
		typeMap[x] = {}
		local heightMapX = heightMap[x]
		local typeMapX = typeMap[x]
		for z = 0, mapSizeZ, squareSize do
			heightMapX[z] = BOTTOM_HEIGHT
			typeMapX[z] = BOTTOM_TERRAIN_TYPE
		end
		Spring.ClearWatchDogTimer()
	end

	return heightMap, typeMap
end

local function GenerateShapeHeightMapAndTypeMap (currentShape, heightMap, typeMap)
	local aabb = currentShape:getAABB()
	local blocksRange = aabbToBlocksRange(aabb)
	local x1, x2, y1, y2 = blocksRange.x1, blocksRange.x2, blocksRange.y1, blocksRange.y2

	for x = x1, x2, squareSize do
		local heightMapX = heightMap[x]
		local typeMapX = typeMap[x]
		for z = y1, y2, squareSize do
			local isRampart, isInnerWalls, isInWalls, isOuterWalls, isAnyTexture, isWallsTexture, innerWallFactor, outerWallFactor = currentShape:isPointInsideOrOnWall(x, z)
			if (isAnyTexture) then
				if (isRampart) then
					heightMapX[z] = RAMPART_HEIGHT
				elseif (isInnerWalls) then
					--local newHeight = (innerWallFactor * RAMPART_WALL_HEIGHT) + ((1.0 - innerWallFactor) * RAMPART_HEIGHT)
					local newHeight = RAMPART_HEIGHT
					if (heightMapX[z] < RAMPART_HEIGHT or newHeight < heightMapX[z]) then -- do not overwrite inner rampart
						heightMapX[z] = newHeight
					end
				elseif (isInWalls) then
					if (heightMapX[z] ~= RAMPART_HEIGHT) then -- do not overwrite inner rampart
						heightMapX[z] = RAMPART_WALL_HEIGHT
					end
				elseif (isOuterWalls) then
					--local newHeight = (outerWallFactor * RAMPART_WALL_HEIGHT) + ((1.0 - outerWallFactor) * RAMPART_WALL_OUTER_HEIGHT)
					local newHeight = RAMPART_WALL_OUTER_HEIGHT
					if (heightMapX[z] < newHeight) then -- do not overwrite rampart or wall
						heightMapX[z] = newHeight
					end
				end
				if (isWallsTexture) then
					if (typeMapX[z] ~= RAMPART_TERRAIN_TYPE) then -- do not overwrite inner rampart
						typeMapX[z] = RAMPART_WALL_TERRAIN_TYPE
					end
				else
					typeMapX[z] = RAMPART_TERRAIN_TYPE
				end
			end
		end
		Spring.ClearWatchDogTimer()
	end
end

local function GenerateHeightMapAndTypeMap (rampartShapes, heightMap, typeMap)
	for i = 1, #rampartShapes do
		GenerateShapeHeightMapAndTypeMap(rampartShapes[i], heightMap, typeMap)
		Spring.ClearWatchDogTimer()
	end

	Spring.Echo("HeightMap and TypeMap generated")
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

local function ApplyHeightMap (heightMap)
	local totalHeightMapAmountChanged = Spring.SetHeightMapFunc(function()
		Spring.LevelHeightMap(0, 0, mapSizeX, mapSizeZ, BOTTOM_HEIGHT) -- this is fast

		for x = 0, mapSizeX, squareSize do
			local heightMapX = heightMap[x]
			for z = 0, mapSizeZ, squareSize do
				local height = heightMapX[z]
				if (height ~= BOTTOM_HEIGHT) then
					SetHeightMap(x, z, height)
				end
			end
			Spring.ClearWatchDogTimer()
		end
	end)
	--Spring.Echo('totalHeightMapAmountChanged: ' .. totalHeightMapAmountChanged)

	GG.mapgen_origHeight = heightMap
	OverrideGetGroundOrigHeight()

	Spring.SetGameRulesParam("ground_min_override", BOTTOM_HEIGHT)
	Spring.SetGameRulesParam("ground_max_override", RAMPART_WALL_HEIGHT)

	Spring.Echo("HeightMap updated")
end

-- typemap

local function ApplyTypeMap (typeMap)
	for x = 0, mapSizeX - 1, squareSize do
		local typeMapX = typeMap[x]
		for z = 0, mapSizeZ - 1, squareSize do
			local terrainType = typeMapX[z]
			if (terrainType ~= INITIAL_TERRAIN_TYPE) then
				SetMapSquareTerrainType(x, z, terrainType)
			end
		end
		Spring.ClearWatchDogTimer()
	end

	_G.mapgen_typeMap = typeMap

	Spring.Echo("TypeMap updated")
end

--------------------------------------------------------------------------------

--function gadget:Initialize()
do
	local mapOptions = Spring.GetMapOptions()
	InitRandomSeed(mapOptions)
	local numBases, numStartBoxes, startBoxNumberByBaseNumber = InitNumberOfBases(mapOptions)

	Spring.Echo("Starting map terrain generation...")

	local rampartShapes, metalSpots, geoSpots, startBoxes = InitRampartShapes(numBases, startBoxNumberByBaseNumber)
	ApplyMetalSpots(metalSpots)
	ApplyGeoSpots(geoSpots)
	ApplyStartBoxes(startBoxes, numStartBoxes)

	local heightMap, typeMap = InitHeightMapAndTypeMap()
	GenerateHeightMapAndTypeMap(rampartShapes, heightMap, typeMap)
	ApplyHeightMap(heightMap)
	ApplyTypeMap(typeMap)

	heightMap = nil
	typeMap = nil

	Spring.Echo("Finished map terrain generation")
end

return false --unload
