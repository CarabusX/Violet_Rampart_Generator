local max = math.max
local abs = math.abs

-- Localize variables

local MAP_SQUARE_SIZE      = EXPORT.MAP_SQUARE_SIZE
local HALF_MAP_SQUARE_SIZE = MAP_SQUARE_SIZE / 2

local RAMPART_WALL_OUTER_TYPEMAP_WIDTH_TOTAL = EXPORT.RAMPART_WALL_OUTER_TYPEMAP_WIDTH_TOTAL
local RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL = EXPORT.RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL
local BORDER_TYPE_WALL     = EXPORT.BORDER_TYPE_WALL
local INTERSECTION_EPSILON = EXPORT.INTERSECTION_EPSILON

-- Localize functions

local PointCoordsDistance        = EXPORT.PointCoordsDistance
local PointCoordsSquaredDistance = EXPORT.PointCoordsSquaredDistance

local modifyHeightMapForWalledShape = EXPORT.modifyHeightMapForWalledShape

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local RampartCircle = {}

function RampartCircle.initEmpty()
	return {
		center = { x = 0, y = 0 },
		radius = 0
	}
end

function RampartCircle:new(obj)
	obj = obj or self.initEmpty()

	setmetatable(obj, self)
	self.__index = self
	self.class = self
	return obj
end

function RampartCircle:prepareRotatedInstance(rotation)
	return {		
		center = rotation:getRotatedPoint(self.center),
		radius = self.radius
	}
end

function RampartCircle:getRotatedInstance(rotation)
	local rotatedObj = self:prepareRotatedInstance(rotation)
	return self.class:new(rotatedObj)
end

function RampartCircle:getAABBInternal(borderWidth)
	local center = self.center
	local outerRadius = self.radius + borderWidth
	return {
		x1 = center.x - outerRadius,
		y1 = center.y - outerRadius,
		x2 = center.x + outerRadius,
		y2 = center.y + outerRadius
	}
end

function RampartCircle:canCheckMapSquareNarrowIntersection()
	return true
end

function RampartCircle:intersectsMapSquareInternal(sx, sz, squareContentPadding, borderWidth)
	local squareCenterX = (sx - 0.5) * MAP_SQUARE_SIZE
	local squareCenterY = (sz - 0.5) * MAP_SQUARE_SIZE
	local halfSquareSizePadded = HALF_MAP_SQUARE_SIZE - squareContentPadding
	local distX = max(0, abs(self.center.x - squareCenterX) - halfSquareSizePadded)
	local distY = max(0, abs(self.center.y - squareCenterY) - halfSquareSizePadded)

	local outerRadius = self.radius + borderWidth + INTERSECTION_EPSILON

	return (distX * distX + distY * distY <= outerRadius * outerRadius)
end

--------------------------------------------------------------------------------

local RampartWalledCircle = RampartCircle:new()

RampartWalledCircle.modifyHeightMapForShape = modifyHeightMapForWalledShape

function RampartWalledCircle:getDistanceFromBorderForPoint (x, y)
	local distanceFromCenter = PointCoordsDistance(self.center, x, y)
	local distanceFromBorder = distanceFromCenter - self.radius

	return distanceFromBorder
end

function RampartWalledCircle:getTypeMapInfoForPoint (x, y)
	local squaredDistanceFromCenter = PointCoordsSquaredDistance(self.center, x, y)

	local radius = self.radius
	local outerRadius = radius + RAMPART_WALL_OUTER_TYPEMAP_WIDTH_TOTAL
	local outerTextureRadius = radius + RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL

	local isInOuterWallsTexture = (
		squaredDistanceFromCenter <= outerTextureRadius * outerTextureRadius
	)
	local isInOuterWallsTypemap = isInOuterWallsTexture and (
		squaredDistanceFromCenter <= outerRadius * outerRadius
	)
	local isRampart = isInOuterWallsTypemap and (
		squaredDistanceFromCenter < radius * radius
	)
	local isWallsTexture     = (isInOuterWallsTexture and not isRampart)
	local isWallsTerrainType = (isInOuterWallsTypemap and not isRampart)

	return isInOuterWallsTexture, isWallsTexture, isWallsTerrainType
end

function RampartWalledCircle:getAABB(borderWidths)
	return RampartCircle.getAABBInternal(self, borderWidths[BORDER_TYPE_WALL])
end

function RampartWalledCircle:intersectsMapSquare(sx, sz, squareContentPadding, borderWidths)
	return RampartCircle.intersectsMapSquareInternal(self, sx, sz, squareContentPadding, borderWidths[BORDER_TYPE_WALL])
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

return
    --RampartCircle,
    RampartWalledCircle
