local max = math.max
local abs = math.abs

-- Localize variables

local MAP_SQUARE_SIZE      = EXPORT.MAP_SQUARE_SIZE
local HALF_MAP_SQUARE_SIZE = MAP_SQUARE_SIZE / 2
local DISTANCE_HUGE        = EXPORT.DISTANCE_HUGE

local RAMPART_WALL_OUTER_TYPEMAP_WIDTH_TOTAL = EXPORT.RAMPART_WALL_OUTER_TYPEMAP_WIDTH_TOTAL
local RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL = EXPORT.RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL
local RAMPART_OUTER_TYPEMAP_WIDTH            = EXPORT.RAMPART_OUTER_TYPEMAP_WIDTH
local BORDER_TYPE_NO_WALL    = EXPORT.BORDER_TYPE_NO_WALL
local BORDER_TYPE_SHARP_EDGE = EXPORT.BORDER_TYPE_SHARP_EDGE
local BORDER_TYPE_WALL       = EXPORT.BORDER_TYPE_WALL
local INTERSECTION_EPSILON = EXPORT.INTERSECTION_EPSILON
local RAMPART_HEIGHT       = EXPORT.RAMPART_HEIGHT
local RAMPART_TERRAIN_TYPE = EXPORT.RAMPART_TERRAIN_TYPE

-- Localize functions

local PointPointDistance         = Geom2D.PointPointDistance
local LineCoordsDistance         = Geom2D.LineCoordsDistance
local LineCoordsProjection       = Geom2D.LineCoordsProjection
local LineVectorLengthProjection = Geom2D.LineVectorLengthProjection

local modifyHeightMapForWalledShape  = EXPORT.modifyHeightMapForWalledShape
local modifyHeightMapForFlatShape    = EXPORT.modifyHeightMapForFlatShape
local modifyTypeMapForWalledShape    = EXPORT.modifyTypeMapForWalledShape
local modifyTypeMapForNotWalledShape = EXPORT.modifyTypeMapForNotWalledShape

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
	obj.rampartTerrainType = obj.rampartTerrainType or RAMPART_TERRAIN_TYPE

	obj.frontVector = Vector2D.UnitVectorFromPoints(obj.p1, obj.p2)
	obj.rightVector = obj.frontVector:toRotated90()
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
		width = self.width,
        rampartTerrainType = self.rampartTerrainType
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
RampartFullyWalledRectangle.modifyTypeMapForShape   = modifyTypeMapForWalledShape

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
RampartVerticallyWalledRectangle.modifyTypeMapForShape   = modifyTypeMapForWalledShape

function RampartVerticallyWalledRectangle.initializeData(obj)
	obj.hasSharpEdge = obj.hasSharpEdge or false

    obj = RampartVerticallyWalledRectangle.superClass.initializeData(obj)

    if (obj.hasSharpEdge) then
        obj.typeMapVerticalBorderWidth = RAMPART_OUTER_TYPEMAP_WIDTH
        obj.verticalBorderType = BORDER_TYPE_SHARP_EDGE
    else
        obj.typeMapVerticalBorderWidth = 0
        obj.verticalBorderType = BORDER_TYPE_NO_WALL
    end

    return obj
end

function RampartVerticallyWalledRectangle:prepareRotatedInstance(rotation)
	local rotatedInstance = self.superClass.prepareRotatedInstance(self, rotation)
	rotatedInstance.hasSharpEdge = self.hasSharpEdge

	return rotatedInstance
end

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
		distanceFromRightAxis <= self.halfHeight + self.typeMapVerticalBorderWidth
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
	return RampartRectangle.getAABBInternal(self, borderWidths[BORDER_TYPE_WALL], borderWidths[ self.verticalBorderType ])
end

function RampartVerticallyWalledRectangle:intersectsMapSquare(sx, sz, squareContentPadding, borderWidths)
	return RampartRectangle.intersectsMapSquareInternal(self, sx, sz, squareContentPadding, borderWidths[BORDER_TYPE_WALL], borderWidths[ self.verticalBorderType ])
end

--------------------------------------------------------------------------------

local RampartNotWalledRectangle = RampartRectangle:inherit()

function RampartNotWalledRectangle.initializeData(obj)
	obj.hasSharpEdge = obj.hasSharpEdge or false

    obj = RampartNotWalledRectangle.superClass.initializeData(obj)

    if (obj.hasSharpEdge) then
        obj.typeMapBorderWidth = RAMPART_OUTER_TYPEMAP_WIDTH
        obj.borderType = BORDER_TYPE_SHARP_EDGE
    else
        obj.typeMapBorderWidth = 0
        obj.borderType = BORDER_TYPE_NO_WALL
    end

    return obj
end

function RampartNotWalledRectangle:prepareRotatedInstance(rotation)
	local rotatedInstance = self.superClass.prepareRotatedInstance(self, rotation)
	rotatedInstance.hasSharpEdge = self.hasSharpEdge

	return rotatedInstance
end

function RampartNotWalledRectangle:isPointInsideShape (x, y)
	local distanceFromFrontAxis = LineCoordsDistance(self.center, self.frontVector, x, y)
	local distanceFromRightAxis = LineCoordsDistance(self.center, self.rightVector, x, y)

	local isInsideShape = (
		distanceFromFrontAxis <= self.halfWidth and
		distanceFromRightAxis <= self.halfHeight
	)

	return isInsideShape
end

function RampartNotWalledRectangle:isPointInsideTypeMap (x, y)
	local distanceFromFrontAxis = LineCoordsDistance(self.center, self.frontVector, x, y)
	local distanceFromRightAxis = LineCoordsDistance(self.center, self.rightVector, x, y)

	local isInsideShape = (
		distanceFromFrontAxis <= self.halfWidth  + self.typeMapBorderWidth and
		distanceFromRightAxis <= self.halfHeight + self.typeMapBorderWidth
	)

	return isInsideShape
end

function RampartNotWalledRectangle:getAABB(borderWidths)
	return RampartRectangle.getAABBInternal(self, borderWidths[ self.borderType ], borderWidths[ self.borderType ])
end

function RampartNotWalledRectangle:intersectsMapSquare(sx, sz, squareContentPadding, borderWidths)
	return RampartRectangle.intersectsMapSquareInternal(self, sx, sz, squareContentPadding, borderWidths[ self.borderType ], borderWidths[ self.borderType ])
end

--------------------------------------------------------------------------------

local RampartFlatRectangle = RampartNotWalledRectangle:inherit()

RampartFlatRectangle.modifyHeightMapForShape = modifyHeightMapForFlatShape
RampartFlatRectangle.modifyTypeMapForShape   = modifyTypeMapForNotWalledShape

function RampartFlatRectangle.initializeData(obj)
	obj.groundHeight = obj.groundHeight or RAMPART_HEIGHT

    return RampartFlatRectangle.superClass.initializeData(obj)
end

function RampartFlatRectangle:prepareRotatedInstance(rotation)
	local rotatedInstance = self.superClass.prepareRotatedInstance(self, rotation)
	rotatedInstance.groundHeight = self.groundHeight

	return rotatedInstance
end

RampartFlatRectangle.isPointInsideShape   = RampartNotWalledRectangle.isPointInsideShape
RampartFlatRectangle.isPointInsideTypeMap = RampartNotWalledRectangle.isPointInsideTypeMap

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

return
    --RampartRectangle,
    RampartFullyWalledRectangle,
    RampartVerticallyWalledRectangle,
    --RampartNotWalledRectangle,
    RampartFlatRectangle
