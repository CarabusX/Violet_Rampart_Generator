local max = math.max
local abs = math.abs

-- Localize variables

local MAP_SQUARE_SIZE      = EXPORT.MAP_SQUARE_SIZE
local HALF_MAP_SQUARE_SIZE = MAP_SQUARE_SIZE / 2
local DISTANCE_HUGE        = EXPORT.DISTANCE_HUGE

local RAMPART_WALL_OUTER_TYPEMAP_WIDTH_TOTAL = EXPORT.RAMPART_WALL_OUTER_TYPEMAP_WIDTH_TOTAL
local RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL = EXPORT.RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL
local RAMPART_OUTER_TYPEMAP_WIDTH            = EXPORT.RAMPART_OUTER_TYPEMAP_WIDTH
local BORDER_TYPE_NO_WALL  = EXPORT.BORDER_TYPE_NO_WALL
local BORDER_TYPE_WALL     = EXPORT.BORDER_TYPE_WALL
local INTERSECTION_EPSILON = EXPORT.INTERSECTION_EPSILON
local RAMPART_HEIGHT       = EXPORT.RAMPART_HEIGHT

-- Localize functions

local PointPointDistance         = EXPORT.PointPointDistance
local LineCoordsDistance         = EXPORT.LineCoordsDistance
local LineCoordsProjection       = EXPORT.LineCoordsProjection
local LineVectorLengthProjection = EXPORT.LineVectorLengthProjection

local modifyHeightMapForWalledShape = EXPORT.modifyHeightMapForWalledShape
local modifyHeightMapForFlatShape   = EXPORT.modifyHeightMapForFlatShape

-- Localize classes

local Vector2D = Vector2D

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local RampartRectangle = createClass()

function RampartRectangle.initEmpty()
	return {
		p1 = { x = 0, y = 0 },
		p2 = { x = 0, y = 0 },
		width = 0
	}
end

function RampartRectangle.initializeData(obj)
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
	if (obj.extendBottom and obj.extendBottom > 0) then
		obj.p1 = {
			x = obj.p1.x - obj.frontVector.x * obj.extendBottom,
			y = obj.p1.y - obj.frontVector.y * obj.extendBottom
		}
	end
	if (obj.extendRight and obj.extendRight > 0) then
		local rightOffset = 0.5 * obj.extendRight
		obj.p1 = {
			x = obj.p1.x + obj.rightVector.x * rightOffset,
			y = obj.p1.y + obj.rightVector.y * rightOffset
		}
		obj.p2 = {
			x = obj.p2.x + obj.rightVector.x * rightOffset,
			y = obj.p2.y + obj.rightVector.y * rightOffset
		}
		obj.width = obj.width + obj.extendRight
	end
	obj.center      = {
		x = (obj.p1.x + obj.p2.x) / 2,
		y = (obj.p1.y + obj.p2.y) / 2
	}
	obj.height      = PointPointDistance(obj.p1, obj.p2)
	obj.halfWidth   = obj.width  / 2
	obj.halfHeight  = obj.height / 2

    return obj
end

function RampartRectangle:new(obj)
	obj = obj or self.initEmpty()
	obj = self.initializeData(obj)

	setmetatable(obj, self)
	return obj
end

function RampartRectangle:prepareRotatedInstance(rotation)
	return {		
		p1    = rotation:getRotatedPoint(self.p1),
		p2    = rotation:getRotatedPoint(self.p2),
		width = self.width
	}
end

function RampartRectangle:getRotatedInstance(rotation)
	local rotatedObj = self:prepareRotatedInstance(rotation)
	return self.class:new(rotatedObj)
end

--[[
function RampartRectangle:getPointInLocalSpace(localX, localY)
	return {
		self.center.x + self.rightVector.x * localX + self.frontVector.x * localY,
		self.center.y + self.rightVector.y * localX + self.frontVector.y * localY
	}
end
--]]

function RampartRectangle:getAABBInternal(horizontalBorderWidth, verticalBorderWidth)
	local center = self.center
	local outerHalfWidth  = self.halfWidth  + horizontalBorderWidth
	local outerHalfHeight = self.halfHeight + verticalBorderWidth
	local rangeX = abs(self.frontVector.x) * outerHalfHeight + abs(self.rightVector.x) * outerHalfWidth
	local rangeY = abs(self.frontVector.y) * outerHalfHeight + abs(self.rightVector.y) * outerHalfWidth
	return {
		x1 = center.x - rangeX,
		y1 = center.y - rangeY,
		x2 = center.x + rangeX,
		y2 = center.y + rangeY
	}
end

function RampartRectangle:canCheckMapSquareNarrowIntersection()
	return true
end

function RampartRectangle:intersectsMapSquareInternal(sx, sz, squareContentPadding, horizontalBorderWidth, verticalBorderWidth)
	local squareCenterX = (sx - 0.5) * MAP_SQUARE_SIZE
	local squareCenterY = (sz - 0.5) * MAP_SQUARE_SIZE
	local squareCenterProjectionOnFrontAxis = LineCoordsProjection(self.center, self.frontVector, squareCenterX, squareCenterY)
	local squareCenterProjectionOnRightAxis = LineCoordsProjection(self.center, self.rightVector, squareCenterX, squareCenterY)

	local halfSquareSizePadded = HALF_MAP_SQUARE_SIZE - squareContentPadding
	local halfSquareDiagonalProjection
	if (self.frontVector.x * self.frontVector.y >= 0) then
		halfSquareDiagonalProjection = LineVectorLengthProjection(self.frontVector, halfSquareSizePadded, halfSquareSizePadded)
	else
		halfSquareDiagonalProjection = LineVectorLengthProjection(self.frontVector, halfSquareSizePadded, -halfSquareSizePadded)
	end

	local outerHalfWidth  = self.halfWidth  + horizontalBorderWidth + INTERSECTION_EPSILON
	local outerHalfHeight = self.halfHeight + verticalBorderWidth   + INTERSECTION_EPSILON

	return (
		squareCenterProjectionOnRightAxis - halfSquareDiagonalProjection <=  outerHalfWidth  and
		squareCenterProjectionOnRightAxis + halfSquareDiagonalProjection >= -outerHalfWidth  and
		squareCenterProjectionOnFrontAxis - halfSquareDiagonalProjection <=  outerHalfHeight and
		squareCenterProjectionOnFrontAxis + halfSquareDiagonalProjection >= -outerHalfHeight
	)
end

--------------------------------------------------------------------------------

local RampartFullyWalledRectangle = RampartRectangle:inherit()

RampartFullyWalledRectangle.modifyHeightMapForShape = modifyHeightMapForWalledShape

function RampartFullyWalledRectangle:getDistanceFromBorderForPoint (x, y)
	local distanceFromFrontAxis = LineCoordsDistance(self.center, self.frontVector, x, y)
	local distanceFromRightAxis = LineCoordsDistance(self.center, self.rightVector, x, y)
	local distanceFromBorder = max(
		distanceFromFrontAxis - self.halfWidth,
		distanceFromRightAxis - self.halfHeight
	)

	return distanceFromBorder
end

function RampartFullyWalledRectangle:getTypeMapInfoForPoint (x, y)
	local halfWidth  = self.halfWidth
	local halfHeight = self.halfHeight
	local distanceFromFrontAxis = LineCoordsDistance(self.center, self.frontVector, x, y)
	local distanceFromRightAxis = LineCoordsDistance(self.center, self.rightVector, x, y)

	local isInOuterWallsTexture = (
		distanceFromFrontAxis <= halfWidth  + RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL and
		distanceFromRightAxis <= halfHeight + RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL
	)
	local isInOuterWallsTypemap = isInOuterWallsTexture and (
		distanceFromFrontAxis <= halfWidth  + RAMPART_WALL_OUTER_TYPEMAP_WIDTH_TOTAL and
		distanceFromRightAxis <= halfHeight + RAMPART_WALL_OUTER_TYPEMAP_WIDTH_TOTAL
	)
	local isRampart = isInOuterWallsTypemap and (
		distanceFromFrontAxis < halfWidth  and
		distanceFromRightAxis < halfHeight
	)
	local isWallsTexture     = (isInOuterWallsTexture and not isRampart)
	local isWallsTerrainType = (isInOuterWallsTypemap and not isRampart)

	return isInOuterWallsTexture, isWallsTexture, isWallsTerrainType
end

function RampartFullyWalledRectangle:getAABB(borderWidths)
	return RampartRectangle.getAABBInternal(self, borderWidths[BORDER_TYPE_WALL], borderWidths[BORDER_TYPE_WALL])
end

function RampartFullyWalledRectangle:intersectsMapSquare(sx, sz, squareContentPadding, borderWidths)
	return RampartRectangle.intersectsMapSquareInternal(self, sx, sz, squareContentPadding, borderWidths[BORDER_TYPE_WALL], borderWidths[BORDER_TYPE_WALL])
end

--------------------------------------------------------------------------------

local RampartVerticallyWalledRectangle = RampartRectangle:inherit()

RampartVerticallyWalledRectangle.modifyHeightMapForShape = modifyHeightMapForWalledShape

function RampartVerticallyWalledRectangle:getDistanceFromBorderForPoint (x, y)
	local distanceFromFrontAxis = LineCoordsDistance(self.center, self.frontVector, x, y)
	local distanceFromRightAxis = LineCoordsDistance(self.center, self.rightVector, x, y)
	local distanceFromBorder = (
		(distanceFromRightAxis <= self.halfHeight) and
		(distanceFromFrontAxis - self.halfWidth) or
		DISTANCE_HUGE
	)

	return distanceFromBorder
end

function RampartVerticallyWalledRectangle:getTypeMapInfoForPoint (x, y)
	local halfWidth = self.halfWidth
	local distanceFromFrontAxis = LineCoordsDistance(self.center, self.frontVector, x, y)
	local distanceFromRightAxis = LineCoordsDistance(self.center, self.rightVector, x, y)

	local isInOuterWallsTexture = (
		distanceFromFrontAxis <= halfWidth + RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL and
		distanceFromRightAxis <= self.halfHeight + RAMPART_OUTER_TYPEMAP_WIDTH
	)
	local isInOuterWallsTypemap = isInOuterWallsTexture and (
		distanceFromFrontAxis <= halfWidth + RAMPART_WALL_OUTER_TYPEMAP_WIDTH_TOTAL
	)
	local isRampart = isInOuterWallsTypemap and (
		distanceFromFrontAxis < halfWidth
	)
	local isWallsTexture     = (isInOuterWallsTexture and not isRampart)
	local isWallsTerrainType = (isInOuterWallsTypemap and not isRampart)

	return isInOuterWallsTexture, isWallsTexture, isWallsTerrainType
end

function RampartVerticallyWalledRectangle:getAABB(borderWidths)
	return RampartRectangle.getAABBInternal(self, borderWidths[BORDER_TYPE_WALL], borderWidths[BORDER_TYPE_NO_WALL])
end

function RampartVerticallyWalledRectangle:intersectsMapSquare(sx, sz, squareContentPadding, borderWidths)
	return RampartRectangle.intersectsMapSquareInternal(self, sx, sz, squareContentPadding, borderWidths[BORDER_TYPE_WALL], borderWidths[BORDER_TYPE_NO_WALL])
end

--------------------------------------------------------------------------------

local RampartNotWalledRectangle = RampartRectangle:inherit()

function RampartNotWalledRectangle:isPointInsideShape (x, y)
	local distanceFromFrontAxis = LineCoordsDistance(self.center, self.frontVector, x, y)
	local distanceFromRightAxis = LineCoordsDistance(self.center, self.rightVector, x, y)

	local isInsideShape = (
		distanceFromFrontAxis <= self.halfWidth and
		distanceFromRightAxis <= self.halfHeight
	)

	return isInsideShape
end

function RampartNotWalledRectangle:getTypeMapInfoForPoint (x, y)
	local distanceFromFrontAxis = LineCoordsDistance(self.center, self.frontVector, x, y)
	local distanceFromRightAxis = LineCoordsDistance(self.center, self.rightVector, x, y)

	local isRampart = (
		distanceFromFrontAxis <= self.halfWidth  + RAMPART_OUTER_TYPEMAP_WIDTH and
		distanceFromRightAxis <= self.halfHeight + RAMPART_OUTER_TYPEMAP_WIDTH
	)

	return isRampart, false, false
end

function RampartNotWalledRectangle:getAABB(borderWidths)
	return RampartRectangle.getAABBInternal(self, borderWidths[BORDER_TYPE_NO_WALL], borderWidths[BORDER_TYPE_NO_WALL])
end

function RampartNotWalledRectangle:intersectsMapSquare(sx, sz, squareContentPadding, borderWidths)
	return RampartRectangle.intersectsMapSquareInternal(self, sx, sz, squareContentPadding, borderWidths[BORDER_TYPE_NO_WALL], borderWidths[BORDER_TYPE_NO_WALL])
end

--------------------------------------------------------------------------------

local RampartFlatRectangle = RampartNotWalledRectangle:inherit()

RampartFlatRectangle.modifyHeightMapForShape = modifyHeightMapForFlatShape

function RampartFlatRectangle.initializeData(obj)
	obj.groundHeight = obj.groundHeight or RAMPART_HEIGHT

    return RampartFlatRectangle.superClass.initializeData(obj)
end

function RampartFlatRectangle:prepareRotatedInstance(rotation)
	local rotatedInstance = self.superClass.prepareRotatedInstance(self, rotation)
	rotatedInstance.groundHeight = self.groundHeight

	return rotatedInstance
end

RampartFlatRectangle.isPointInsideShape     = RampartNotWalledRectangle.isPointInsideShape
RampartFlatRectangle.getTypeMapInfoForPoint = RampartNotWalledRectangle.getTypeMapInfoForPoint

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

return
    --RampartRectangle,
    RampartFullyWalledRectangle,
    RampartVerticallyWalledRectangle,
    --RampartNotWalledRectangle,
    RampartFlatRectangle
