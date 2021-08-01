local min  = math.min
local max  = math.max
local abs  = math.abs
local sqrt = math.sqrt

-- Localize variables

local MAP_SQUARE_SIZE      = EXPORT.MAP_SQUARE_SIZE
local HALF_MAP_SQUARE_SIZE = MAP_SQUARE_SIZE / 2
local DISTANCE_HUGE        = EXPORT.DISTANCE_HUGE

local RAMPART_WALL_INNER_TEXTURE_WIDTH       = EXPORT.RAMPART_WALL_INNER_TEXTURE_WIDTH
local RAMPART_WALL_OUTER_TYPEMAP_WIDTH_TOTAL = EXPORT.RAMPART_WALL_OUTER_TYPEMAP_WIDTH_TOTAL
local RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL = EXPORT.RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL
local RAMPART_OUTER_TYPEMAP_WIDTH = EXPORT.RAMPART_OUTER_TYPEMAP_WIDTH
local BORDER_TYPE_NO_WALL       = EXPORT.BORDER_TYPE_NO_WALL
local BORDER_TYPE_WALL          = EXPORT.BORDER_TYPE_WALL
local BORDER_TYPE_INTERNAL_WALL = EXPORT.BORDER_TYPE_INTERNAL_WALL
local INTERSECTION_EPSILON      = EXPORT.INTERSECTION_EPSILON
local RAMPART_HEIGHT            = EXPORT.RAMPART_HEIGHT

-- Localize functions

local PointPointDistance         = EXPORT.PointPointDistance
local LineCoordsDistance         = EXPORT.LineCoordsDistance
local LineCoordsProjection       = EXPORT.LineCoordsProjection
local LineVectorLengthProjection = EXPORT.LineVectorLengthProjection

local modifyHeightMapForWalledShape       = EXPORT.modifyHeightMapForWalledShape
local modifyHeightMapForInternalWallShape = EXPORT.modifyHeightMapForInternalWallShape
local modifyHeightMapForFlatShape         = EXPORT.modifyHeightMapForFlatShape
local modifyHeightMapForRampShape         = EXPORT.modifyHeightMapForRampShape

-- Localize classes

local Vector2D = Vector2D

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local RampartTrapezoid = createClass()

function RampartTrapezoid.initEmpty()
	return {
		p1 = { x = 0, y = 0 },
		p2 = { x = 0, y = 0 },
		width1 = 0,
		width2 = 0
	}
end

function RampartTrapezoid.initializeData(obj)
	obj.frontVector = Vector2D.UnitVectorFromPoints(obj.p1, obj.p2)
	obj.rightVector = obj.frontVector:toRotated90()
	obj.center      = {
		x = (obj.p1.x + obj.p2.x) / 2,
		y = (obj.p1.y + obj.p2.y) / 2
	}
	obj.height      = PointPointDistance(obj.p1, obj.p2)
	obj.halfWidth1  = obj.width1 / 2
	obj.halfWidth2  = obj.width2 / 2
	obj.halfHeight  = obj.height / 2
	obj.maxHalfWidth       = max(obj.halfWidth1, obj.halfWidth2)
	obj.centerHalfWidth    = (obj.halfWidth1 + obj.halfWidth2) / 2
	obj.halfWidthIncrement = (obj.halfWidth2 - obj.halfWidth1) / obj.height
	obj.borderWidthToWidthMult = sqrt(1.0 + obj.halfWidthIncrement * obj.halfWidthIncrement)

	obj.rightEdgePoint = {
		x = obj.center.x + obj.centerHalfWidth * obj.rightVector.x,
		y = obj.center.y + obj.centerHalfWidth * obj.rightVector.y
	}
	obj.leftEdgePoint = {
		x = obj.center.x - obj.centerHalfWidth * obj.rightVector.x,
		y = obj.center.y - obj.centerHalfWidth * obj.rightVector.y
	}
	obj.rightEdgeNormal = Vector2D.UnitVectorFromDir({
		x = obj.frontVector.x + obj.halfWidthIncrement * obj.rightVector.x,
		y = obj.frontVector.y + obj.halfWidthIncrement * obj.rightVector.y
	}):toRotated90()
	obj.leftEdgeNormal = Vector2D.UnitVectorFromDir({
		x = obj.frontVector.x - obj.halfWidthIncrement * obj.rightVector.x,
		y = obj.frontVector.y - obj.halfWidthIncrement * obj.rightVector.y
	}):toRotated270()

    return obj
end

function RampartTrapezoid:new(obj)
	obj = obj or self.initEmpty()
	obj = self.initializeData(obj)

	setmetatable(obj, self)
	return obj
end

function RampartTrapezoid:prepareRotatedInstance(rotation)
	return {		
		p1     = rotation:getRotatedPoint(self.p1),
		p2     = rotation:getRotatedPoint(self.p2),
		width1 = self.width1,
		width2 = self.width2
	}
end

function RampartTrapezoid:getRotatedInstance(rotation)
	local rotatedObj = self:prepareRotatedInstance(rotation)
	return self.class:new(rotatedObj)
end

function RampartTrapezoid:getAABBInternal(horizontalBorderWidth, verticalBorderWidth)
	local center = self.center
	local outerHalfHeight = self.halfHeight + verticalBorderWidth
	local centerOuterHalfWidth = self.centerHalfWidth + horizontalBorderWidth * self.borderWidthToWidthMult
	local outerHalfWidth1 = centerOuterHalfWidth - outerHalfHeight * self.halfWidthIncrement
	local outerHalfWidth2 = centerOuterHalfWidth + outerHalfHeight * self.halfWidthIncrement

	local frontAdvanceX = self.frontVector.x * outerHalfHeight
	local frontAdvanceY = self.frontVector.y * outerHalfHeight
	local rangeX1 = abs(self.rightVector.x) * outerHalfWidth1
	local rangeX2 = abs(self.rightVector.x) * outerHalfWidth2
	local rangeY1 = abs(self.rightVector.y) * outerHalfWidth1
	local rangeY2 = abs(self.rightVector.y) * outerHalfWidth2

	return {
		x1 = center.x + min(-frontAdvanceX - rangeX1, frontAdvanceX - rangeX2),
		y1 = center.y + min(-frontAdvanceY - rangeY1, frontAdvanceY - rangeY2),
		x2 = center.x + max(-frontAdvanceX + rangeX1, frontAdvanceX + rangeX2),
		y2 = center.y + max(-frontAdvanceY + rangeY1, frontAdvanceY + rangeY2)
	}
end

function RampartTrapezoid:canCheckMapSquareNarrowIntersection()
	return true
end

function RampartTrapezoid:intersectsMapSquareInternal(sx, sz, squareContentPadding, horizontalBorderWidth, verticalBorderWidth)
	local squareCenterX = (sx - 0.5) * MAP_SQUARE_SIZE
	local squareCenterY = (sz - 0.5) * MAP_SQUARE_SIZE
	local squareCenterProjectionOnFrontAxis       = LineCoordsProjection(self.center        , self.frontVector    , squareCenterX, squareCenterY)
	local squareCenterProjectionOnRightEdgeNormal = LineCoordsProjection(self.rightEdgePoint, self.rightEdgeNormal, squareCenterX, squareCenterY)
	local squareCenterProjectionOnLeftEdgeNormal  = LineCoordsProjection(self.leftEdgePoint , self.leftEdgeNormal , squareCenterX, squareCenterY)

	local halfSquareSizePadded = HALF_MAP_SQUARE_SIZE - squareContentPadding

	local halfSquareDiagonalProjectionOnFrontAxis
	if (self.frontVector.x * self.frontVector.y >= 0) then
		halfSquareDiagonalProjectionOnFrontAxis = LineVectorLengthProjection(self.frontVector, halfSquareSizePadded, halfSquareSizePadded)
	else
		halfSquareDiagonalProjectionOnFrontAxis = LineVectorLengthProjection(self.frontVector, halfSquareSizePadded, -halfSquareSizePadded)
	end

	local halfSquareDiagonalProjectionOnRightEdgeNormal
	if (self.rightEdgeNormal.x * self.rightEdgeNormal.y >= 0) then
		halfSquareDiagonalProjectionOnRightEdgeNormal = LineVectorLengthProjection(self.rightEdgeNormal, halfSquareSizePadded, halfSquareSizePadded)
	else
		halfSquareDiagonalProjectionOnRightEdgeNormal = LineVectorLengthProjection(self.rightEdgeNormal, halfSquareSizePadded, -halfSquareSizePadded)
	end

	local halfSquareDiagonalProjectionOnLeftEdgeNormal
	if (self.leftEdgeNormal.x * self.leftEdgeNormal.y >= 0) then
		halfSquareDiagonalProjectionOnLeftEdgeNormal = LineVectorLengthProjection(self.leftEdgeNormal, halfSquareSizePadded, halfSquareSizePadded)
	else
		halfSquareDiagonalProjectionOnLeftEdgeNormal = LineVectorLengthProjection(self.leftEdgeNormal, halfSquareSizePadded, -halfSquareSizePadded)
	end

	local outerHalfHeight = self.halfHeight + verticalBorderWidth + INTERSECTION_EPSILON
	local horizontalBorderWidth = horizontalBorderWidth + INTERSECTION_EPSILON

	return (
		squareCenterProjectionOnFrontAxis - halfSquareDiagonalProjectionOnFrontAxis <=  outerHalfHeight and
		squareCenterProjectionOnFrontAxis + halfSquareDiagonalProjectionOnFrontAxis >= -outerHalfHeight and
		squareCenterProjectionOnRightEdgeNormal - halfSquareDiagonalProjectionOnRightEdgeNormal <= horizontalBorderWidth and
		squareCenterProjectionOnLeftEdgeNormal  - halfSquareDiagonalProjectionOnLeftEdgeNormal  <= horizontalBorderWidth
	)
end

--------------------------------------------------------------------------------

local RampartHorizontallyWalledTrapezoid = RampartTrapezoid:inherit()

RampartHorizontallyWalledTrapezoid.modifyHeightMapForShape = modifyHeightMapForWalledShape

function RampartHorizontallyWalledTrapezoid:getDistanceFromBorderForPoint (x, y)
	local distanceFromFrontAxis = LineCoordsDistance  (self.center, self.frontVector, x, y)
	local projectionOnFrontAxis = LineCoordsProjection(self.center, self.frontVector, x, y)
	local distanceFromBorder = (
		(distanceFromFrontAxis <= self.centerHalfWidth + projectionOnFrontAxis * self.halfWidthIncrement) and
		(abs(projectionOnFrontAxis) - self.halfHeight) or
		DISTANCE_HUGE
	)

	return distanceFromBorder
end

function RampartHorizontallyWalledTrapezoid:getTypeMapInfoForPoint (x, y)
	local halfHeight = self.halfHeight
	local distanceFromFrontAxis = LineCoordsDistance  (self.center, self.frontVector, x, y)
	local projectionOnFrontAxis = LineCoordsProjection(self.center, self.frontVector, x, y)
    local distanceFromRightAxis = abs(projectionOnFrontAxis)

	local isInOuterWallsTexture = (
        distanceFromRightAxis <= halfHeight + RAMPART_WALL_OUTER_TEXTURE_WIDTH_TOTAL and
		distanceFromFrontAxis <= self.centerHalfWidth + projectionOnFrontAxis * self.halfWidthIncrement + RAMPART_OUTER_TYPEMAP_WIDTH * self.borderWidthToWidthMult
	)
	local isInOuterWallsTypemap = isInOuterWallsTexture and (
        distanceFromRightAxis <= halfHeight + RAMPART_WALL_OUTER_TYPEMAP_WIDTH_TOTAL
	)
	local isRampart = isInOuterWallsTypemap and (
        distanceFromRightAxis < halfHeight
	)
	local isWallsTexture     = (isInOuterWallsTexture and not isRampart)
	local isWallsTerrainType = (isInOuterWallsTypemap and not isRampart)

	return isInOuterWallsTexture, isWallsTexture, isWallsTerrainType
end

function RampartHorizontallyWalledTrapezoid:getAABB(borderWidths)
	return RampartTrapezoid.getAABBInternal(self, borderWidths[BORDER_TYPE_NO_WALL], borderWidths[BORDER_TYPE_WALL])
end

function RampartHorizontallyWalledTrapezoid:intersectsMapSquare(sx, sz, squareContentPadding, borderWidths)
	return RampartTrapezoid.intersectsMapSquareInternal(self, sx, sz, squareContentPadding, borderWidths[BORDER_TYPE_NO_WALL], borderWidths[BORDER_TYPE_WALL])
end

--------------------------------------------------------------------------------

local RampartInternalWallTrapezoid = RampartTrapezoid:inherit()

RampartInternalWallTrapezoid.modifyHeightMapForShape = modifyHeightMapForInternalWallShape

function RampartInternalWallTrapezoid:isPointInsideShape (x, y)
	local distanceFromFrontAxis = LineCoordsDistance  (self.center, self.frontVector, x, y)
	local projectionOnFrontAxis = LineCoordsProjection(self.center, self.frontVector, x, y)

	local isInsideShape = (
		abs(projectionOnFrontAxis) <= self.halfHeight and
		distanceFromFrontAxis <= self.centerHalfWidth + projectionOnFrontAxis * self.halfWidthIncrement
	)

	return isInsideShape
end

function RampartInternalWallTrapezoid:getTypeMapInfoForPoint (x, y)
	local distanceFromFrontAxis = LineCoordsDistance  (self.center, self.frontVector, x, y)
	local projectionOnFrontAxis = LineCoordsProjection(self.center, self.frontVector, x, y)

	local isWallsTexture = (
        abs(projectionOnFrontAxis) <= self.halfHeight + RAMPART_WALL_INNER_TEXTURE_WIDTH and
		distanceFromFrontAxis <= self.centerHalfWidth + projectionOnFrontAxis * self.halfWidthIncrement + RAMPART_WALL_INNER_TEXTURE_WIDTH * self.borderWidthToWidthMult
	)
	local isWallsTerrainType = isWallsTexture

	return isWallsTexture, isWallsTexture, isWallsTerrainType
end

function RampartInternalWallTrapezoid:getAABB(borderWidths)
	return RampartTrapezoid.getAABBInternal(self, borderWidths[BORDER_TYPE_INTERNAL_WALL], borderWidths[BORDER_TYPE_INTERNAL_WALL])
end

function RampartInternalWallTrapezoid:intersectsMapSquare(sx, sz, squareContentPadding, borderWidths)
	return RampartTrapezoid.intersectsMapSquareInternal(self, sx, sz, squareContentPadding, borderWidths[BORDER_TYPE_INTERNAL_WALL], borderWidths[BORDER_TYPE_INTERNAL_WALL])
end

--------------------------------------------------------------------------------

local RampartNotWalledTrapezoid = RampartTrapezoid:inherit()

function RampartNotWalledTrapezoid:isPointInsideShape (x, y)
	local distanceFromFrontAxis = LineCoordsDistance  (self.center, self.frontVector, x, y)
	local projectionOnFrontAxis = LineCoordsProjection(self.center, self.frontVector, x, y)

	local isInsideShape = (
		abs(projectionOnFrontAxis) <= self.halfHeight and
		distanceFromFrontAxis <= self.centerHalfWidth + projectionOnFrontAxis * self.halfWidthIncrement
	)

	return isInsideShape
end

function RampartNotWalledTrapezoid:getTypeMapInfoForPoint (x, y)
	local distanceFromFrontAxis = LineCoordsDistance  (self.center, self.frontVector, x, y)
	local projectionOnFrontAxis = LineCoordsProjection(self.center, self.frontVector, x, y)

	local isRampart = (
		abs(projectionOnFrontAxis) <= self.halfHeight + RAMPART_OUTER_TYPEMAP_WIDTH and
		distanceFromFrontAxis <= self.centerHalfWidth + projectionOnFrontAxis * self.halfWidthIncrement + RAMPART_OUTER_TYPEMAP_WIDTH * self.borderWidthToWidthMult and
		distanceFromFrontAxis <= self.maxHalfWidth + RAMPART_OUTER_TYPEMAP_WIDTH  -- don't add too much typeMap on acute corners
	)

	return isRampart, false, false
end

function RampartNotWalledTrapezoid:getAABB(borderWidths)
	return RampartTrapezoid.getAABBInternal(self, borderWidths[BORDER_TYPE_NO_WALL], borderWidths[BORDER_TYPE_NO_WALL])
end

function RampartNotWalledTrapezoid:intersectsMapSquare(sx, sz, squareContentPadding, borderWidths)
	return RampartTrapezoid.intersectsMapSquareInternal(self, sx, sz, squareContentPadding, borderWidths[BORDER_TYPE_NO_WALL], borderWidths[BORDER_TYPE_NO_WALL])
end

--------------------------------------------------------------------------------

local RampartFlatTrapezoid = RampartNotWalledTrapezoid:inherit()

RampartFlatTrapezoid.modifyHeightMapForShape = modifyHeightMapForFlatShape

function RampartFlatTrapezoid.initializeData(obj)
	obj.groundHeight = obj.groundHeight or RAMPART_HEIGHT

	return RampartFlatTrapezoid.superClass.initializeData(obj)
end

function RampartFlatTrapezoid:prepareRotatedInstance(rotation)
	local rotatedInstance = self.superClass.prepareRotatedInstance(self, rotation)
	rotatedInstance.groundHeight = self.groundHeight

	return rotatedInstance
end

RampartFlatTrapezoid.isPointInsideShape     = RampartNotWalledTrapezoid.isPointInsideShape
RampartFlatTrapezoid.getTypeMapInfoForPoint = RampartNotWalledTrapezoid.getTypeMapInfoForPoint

--------------------------------------------------------------------------------

local RampartRampTrapezoid = RampartNotWalledTrapezoid:inherit()

RampartRampTrapezoid.modifyHeightMapForShape = modifyHeightMapForRampShape

function RampartRampTrapezoid.initEmpty()
	local obj = RampartRampTrapezoid.superClass.initEmpty()
	obj.groundHeight1 = RAMPART_HEIGHT
	obj.groundHeight2 = 0

	return obj
end

function RampartRampTrapezoid.initializeData(obj)
	obj = RampartRampTrapezoid.superClass.initializeData(obj)

	obj.centerGroundHeight    = (obj.groundHeight1 + obj.groundHeight2) / 2
	obj.groundHeightIncrement = (obj.groundHeight2 - obj.groundHeight1) / obj.height

    return obj
end

function RampartRampTrapezoid:prepareRotatedInstance(rotation)
	local rotatedInstance = self.superClass.prepareRotatedInstance(self, rotation)
	rotatedInstance.groundHeight1 = self.groundHeight1
	rotatedInstance.groundHeight2 = self.groundHeight2

	return rotatedInstance
end

function RampartRampTrapezoid:getGroundHeightForPoint (x, y)
	local distanceFromFrontAxis = LineCoordsDistance  (self.center, self.frontVector, x, y)
	local projectionOnFrontAxis = LineCoordsProjection(self.center, self.frontVector, x, y)

	local isInsideShape = (
		abs(projectionOnFrontAxis) <= self.halfHeight and
		distanceFromFrontAxis <= self.centerHalfWidth + projectionOnFrontAxis * self.halfWidthIncrement
	)
	local groundHeight = isInsideShape and (
		self.centerGroundHeight + projectionOnFrontAxis * self.groundHeightIncrement
	)

	return isInsideShape, groundHeight
end

RampartRampTrapezoid.getTypeMapInfoForPoint = RampartNotWalledTrapezoid.getTypeMapInfoForPoint

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

return
    --RampartTrapezoid,
    RampartHorizontallyWalledTrapezoid,
    RampartInternalWallTrapezoid,
    --RampartNotWalledTrapezoid,
    RampartFlatTrapezoid,
    RampartRampTrapezoid
