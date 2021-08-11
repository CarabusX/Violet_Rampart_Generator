local abs  = math.abs
local sqrt = math.sqrt

-- Localize variables

local RAMPART_OUTER_TYPEMAP_WIDTH = EXPORT.RAMPART_OUTER_TYPEMAP_WIDTH
local BORDER_TYPE_NO_WALL    = EXPORT.BORDER_TYPE_NO_WALL
local BORDER_TYPE_SHARP_EDGE = EXPORT.BORDER_TYPE_SHARP_EDGE
local RAMPART_HEIGHT       = EXPORT.RAMPART_HEIGHT
local RAMPART_TERRAIN_TYPE = EXPORT.RAMPART_TERRAIN_TYPE
local INITIAL_TERRAIN_TYPE = EXPORT.INITIAL_TERRAIN_TYPE

-- Localize functions

local LineCoordsDistance = Geom2D.LineCoordsDistance

local modifyHeightMapForSmoothSlopedShape = EXPORT.modifyHeightMapForSmoothSlopedShape
local modifyHeightMapForSmoothSlopedRing  = EXPORT.modifyHeightMapForSmoothSlopedRing
local modifyHeightMapForFlatShape         = EXPORT.modifyHeightMapForFlatShape
local modifyTypeMapForSmoothSlopedShape   = EXPORT.modifyTypeMapForSmoothSlopedShape
local modifyTypeMapForSmoothSlopedRing    = EXPORT.modifyTypeMapForSmoothSlopedRing
local modifyTypeMapForNotWalledShape      = EXPORT.modifyTypeMapForNotWalledShape

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local TerrainEllipse = createClass()

function TerrainEllipse.initEmpty()
	return {
		center = { x = 0, y = 0 },
		width = 100,
		height = 100,
		frontAngleRad = 0
	}
end

function TerrainEllipse.initializeData(obj)
	obj.frontVector = Vector2D.UnitVectorFromAngle(obj.frontAngleRad)
	obj.rightVector = obj.frontVector:toRotated90()

	obj.angleSin =  obj.frontVector.x
	obj.angleCos = -obj.frontVector.y

	obj.halfWidth  = obj.width  / 2
	obj.halfHeight = obj.height / 2

	return obj
end

function TerrainEllipse:new(obj)
	obj = obj or self.initEmpty()
	obj = self.initializeData(obj)

	setmetatable(obj, self)
	return obj
end

function TerrainEllipse:prepareRotatedInstance(rotation)
	return {		
		center = rotation:getRotatedPoint(self.center),
		width  = self.width,
		height = self.height,
		frontAngleRad = rotation:getRotatedAngle(self.frontAngleRad)
	}
end

function TerrainEllipse:getRotatedInstance(rotation)
	local rotatedObj = self:prepareRotatedInstance(rotation)
	return self.class:new(rotatedObj)
end

function TerrainEllipse:modifiesHeightMap()
	return true
end

function TerrainEllipse:modifiesTypeMap()
	return true
end

function TerrainEllipse:getAABBInternal(horizontalBorderWidth, verticalBorderWidth)
	local center = self.center
	local outerHalfWidth  = self.halfWidth  + horizontalBorderWidth
	local outerHalfHeight = self.halfHeight + verticalBorderWidth
	local rangeX = sqrt(
		outerHalfHeight * outerHalfHeight * self.angleSin * self.angleSin +
		outerHalfWidth  * outerHalfWidth  * self.angleCos * self.angleCos
	)
	local rangeY = sqrt(
		outerHalfHeight * outerHalfHeight * self.angleCos * self.angleCos +
		outerHalfWidth  * outerHalfWidth  * self.angleSin * self.angleSin
	)
	return {
		x1 = center.x - rangeX,
		y1 = center.y - rangeY,
		x2 = center.x + rangeX,
		y2 = center.y + rangeY
	}
end

function TerrainEllipse:canCheckMapSquareNarrowIntersection()
	return false  -- too hard to check this for rotated ellipse
end

function TerrainEllipse:intersectsMapSquare(sx, sz, squareContentPadding, borderWidths)
	return true  -- assumes AABB check already passed
end

--------------------------------------------------------------------------------

local TerrainNonBorderedEllipse = TerrainEllipse:inherit()

function TerrainNonBorderedEllipse.initializeData(obj)
	obj.hasSharpEdge = obj.hasSharpEdge or false

    obj = TerrainNonBorderedEllipse.superClass.initializeData(obj)

    if (obj.hasSharpEdge) then
        obj.typeMapBorderWidth = RAMPART_OUTER_TYPEMAP_WIDTH
        obj.borderType = BORDER_TYPE_SHARP_EDGE
    else
        obj.typeMapBorderWidth = 0
        obj.borderType = BORDER_TYPE_NO_WALL
    end

    return obj
end

function TerrainNonBorderedEllipse:prepareRotatedInstance(rotation)
	local rotatedInstance = TerrainNonBorderedEllipse.superClass.prepareRotatedInstance(self, rotation)
	rotatedInstance.hasSharpEdge = self.hasSharpEdge

	return rotatedInstance
end

function TerrainNonBorderedEllipse:isPointInsideShape (x, y)
	local distanceFromFrontAxis = LineCoordsDistance(self.center, self.frontVector, x, y)
	local distanceFromRightAxis = LineCoordsDistance(self.center, self.rightVector, x, y)
	local relativeDistanceFromFrontAxis = distanceFromFrontAxis / self.halfWidth
	local relativeDistanceFromRightAxis = distanceFromRightAxis / self.halfHeight
	local squaredRelativeDistance = relativeDistanceFromFrontAxis * relativeDistanceFromFrontAxis + relativeDistanceFromRightAxis * relativeDistanceFromRightAxis

	local isInsideShape = (
		squaredRelativeDistance <= 1.0
	)

	return isInsideShape
end

function TerrainNonBorderedEllipse:isPointInsideTypeMap (x, y)
	local outerHalfWidth  = self.halfWidth  + self.typeMapBorderWidth
	local outerHalfHeight = self.halfHeight + self.typeMapBorderWidth

	local distanceFromFrontAxis = LineCoordsDistance(self.center, self.frontVector, x, y)
	local distanceFromRightAxis = LineCoordsDistance(self.center, self.rightVector, x, y)
	local relativeDistanceFromFrontAxis = distanceFromFrontAxis / outerHalfWidth
	local relativeDistanceFromRightAxis = distanceFromRightAxis / outerHalfHeight
	local squaredRelativeDistance = relativeDistanceFromFrontAxis * relativeDistanceFromFrontAxis + relativeDistanceFromRightAxis * relativeDistanceFromRightAxis

	local isInsideShape = (
		squaredRelativeDistance <= 1.0
	)

	return isInsideShape
end

function TerrainNonBorderedEllipse:getAABB(borderWidths)
	return TerrainEllipse.getAABBInternal(self, borderWidths[ self.borderType ], borderWidths[ self.borderType ])
end

--------------------------------------------------------------------------------

local TerrainFlatEllipse = TerrainNonBorderedEllipse:inherit()

TerrainFlatEllipse.modifyHeightMapForShape = modifyHeightMapForFlatShape
TerrainFlatEllipse.modifyTypeMapForShape   = modifyTypeMapForNotWalledShape

function TerrainFlatEllipse.initializeData(obj)
	obj.groundHeight = obj.groundHeight or RAMPART_HEIGHT
	obj.rampartTerrainType  = obj.rampartTerrainType or RAMPART_TERRAIN_TYPE

	return TerrainFlatEllipse.superClass.initializeData(obj)
end

function TerrainFlatEllipse:prepareRotatedInstance(rotation)
	local rotatedInstance = TerrainFlatEllipse.superClass.prepareRotatedInstance(self, rotation)
	rotatedInstance.groundHeight = self.groundHeight
	rotatedInstance.rampartTerrainType = self.rampartTerrainType

	return rotatedInstance
end

TerrainFlatEllipse.isPointInsideShape   = TerrainNonBorderedEllipse.isPointInsideShape
TerrainFlatEllipse.isPointInsideTypeMap = TerrainNonBorderedEllipse.isPointInsideTypeMap

--------------------------------------------------------------------------------

local TerrainSmoothSlopedEllipse = TerrainEllipse:inherit()

TerrainSmoothSlopedEllipse.modifyHeightMapForShape = modifyHeightMapForSmoothSlopedShape
TerrainSmoothSlopedEllipse.modifyTypeMapForShape   = modifyTypeMapForSmoothSlopedShape

function TerrainSmoothSlopedEllipse.initEmpty()
	local obj = TerrainSmoothSlopedEllipse.superClass.initEmpty()
	obj.topGroundHeight = 100
	obj.slopeTopGroundHeight = 80
	obj.slopeBottomGroundHeight = 20
	obj.baseBottomGroundHeight = 0
	obj.slopeTopRelativeSize = 0.2
	obj.baseWidth = 50
	obj.baseSlope = 0.0

	return obj
end

function TerrainSmoothSlopedEllipse.initializeData(obj)
	obj.topTerrainType   = obj.topTerrainType   or INITIAL_TERRAIN_TYPE
	obj.slopeTerrainType = obj.slopeTerrainType or INITIAL_TERRAIN_TYPE
	obj.baseTerrainType  = obj.baseTerrainType  or INITIAL_TERRAIN_TYPE

    obj = TerrainSmoothSlopedEllipse.superClass.initializeData(obj)

	obj.halfTopWidth = obj.halfWidth * obj.slopeTopRelativeSize
	local widthSlope  = (obj.slopeTopGroundHeight - obj.slopeBottomGroundHeight) / (obj.halfWidth - obj.halfTopWidth)
	local heightSlope = widthSlope * (obj.width / obj.height)
	obj.relativeWidthSlopeMult = widthSlope * obj.halfWidth

	obj.topGroundHeightFunction = QuadraticBezier2D:new{
		x0 = 0,
		y0 = obj.topGroundHeight,
		x1 = obj.halfTopWidth,
		y1 = obj.slopeTopGroundHeight,
		slope0 = 0,
		slope1 = -widthSlope
	}
	obj.baseRightGroundHeightFunction = QuadraticBezier2D:new{
		x0 = obj.baseWidth,
		y0 = obj.baseBottomGroundHeight,
		x1 = 0,
		y1 = obj.slopeBottomGroundHeight,
		slope0 = -obj.baseSlope,
		slope1 = -widthSlope
	}
	obj.baseFrontGroundHeightFunction = QuadraticBezier2D:new{
		x0 = obj.baseWidth,
		y0 = obj.baseBottomGroundHeight,
		x1 = 0,
		y1 = obj.slopeBottomGroundHeight,
		slope0 = -obj.baseSlope,
		slope1 = -heightSlope
	}

	obj.hasBaseTerrainType = (obj.baseTerrainType ~= INITIAL_TERRAIN_TYPE)
	obj.typeMapBorderWidth = obj.hasBaseTerrainType and obj.baseWidth or 0

    return obj
end

function TerrainSmoothSlopedEllipse:prepareRotatedInstance(rotation)
	local rotatedInstance = TerrainSmoothSlopedEllipse.superClass.prepareRotatedInstance(self, rotation)
	rotatedInstance.topGroundHeight         = self.topGroundHeight
	rotatedInstance.slopeTopGroundHeight    = self.slopeTopGroundHeight
	rotatedInstance.slopeBottomGroundHeight = self.slopeBottomGroundHeight
	rotatedInstance.baseBottomGroundHeight  = self.baseBottomGroundHeight
	rotatedInstance.slopeTopRelativeSize    = self.slopeTopRelativeSize
	rotatedInstance.baseWidth               = self.baseWidth
	rotatedInstance.baseSlope               = self.baseSlope

	rotatedInstance.topTerrainType   = self.topTerrainType
	rotatedInstance.slopeTerrainType = self.slopeTerrainType
	rotatedInstance.baseTerrainType  = self.baseTerrainType

	rotatedInstance.modifyHeightMapForShape = self.modifyHeightMapForShape
	rotatedInstance.modifyTypeMapForShape   = self.modifyTypeMapForShape

	return rotatedInstance
end

function TerrainSmoothSlopedEllipse:getGroundHeightForPoint (x, y)
	local distanceFromFrontAxis = LineCoordsDistance(self.center, self.frontVector, x, y)
	local distanceFromRightAxis = LineCoordsDistance(self.center, self.rightVector, x, y)
	local relativeDistanceFromFrontAxis = distanceFromFrontAxis / self.halfWidth
	local relativeDistanceFromRightAxis = distanceFromRightAxis / self.halfHeight
	local squaredRelativeDistance = relativeDistanceFromFrontAxis * relativeDistanceFromFrontAxis + relativeDistanceFromRightAxis * relativeDistanceFromRightAxis

	local isInsideSlope = (
		squaredRelativeDistance <= 1.0
	)

	if (isInsideSlope) then
		local relativeDistance = sqrt(squaredRelativeDistance)
		local isTop = (
			relativeDistance < self.slopeTopRelativeSize
		)

		if (isTop) then
			local distanceFromCenter = relativeDistance * self.halfWidth
			local groundHeight = self.topGroundHeightFunction:getYValueAtPos(distanceFromCenter)

			return true, groundHeight
		else
			local groundHeight = self.slopeTopGroundHeight - (relativeDistance - self.slopeTopRelativeSize) * self.relativeWidthSlopeMult

			return true, groundHeight
		end
	else
		local outerHalfWidth  = self.halfWidth  + self.baseWidth
		local outerHalfHeight = self.halfHeight + self.baseWidth
		local relativeOuterDistanceFromFrontAxis = distanceFromFrontAxis / outerHalfWidth
		local relativeOuterDistanceFromRightAxis = distanceFromRightAxis / outerHalfHeight
		local squaredRelativeOuterDistance = relativeOuterDistanceFromFrontAxis * relativeOuterDistanceFromFrontAxis + relativeOuterDistanceFromRightAxis * relativeOuterDistanceFromRightAxis
	
		local isInsideBase = (
			squaredRelativeOuterDistance <= 1.0
		)
		
		if (isInsideBase) then
			local relativeDistance = sqrt(squaredRelativeDistance)
			local relativeDistanceFromBorder = relativeDistance - 1.0
			local borderDistanceMult = (
				relativeDistanceFromFrontAxis * relativeDistanceFromFrontAxis * self.halfWidth +
				relativeDistanceFromRightAxis * relativeDistanceFromRightAxis * self.halfHeight
			) / squaredRelativeDistance
			local distanceFromBorder = relativeDistanceFromBorder * borderDistanceMult

			if (distanceFromBorder <= self.baseWidth) then
				local rightGroundHeight = self.baseRightGroundHeightFunction:getYValueAtPos(distanceFromBorder)
				local frontGroundHeight = self.baseFrontGroundHeightFunction:getYValueAtPos(distanceFromBorder)
				local groundHeight = (
					relativeDistanceFromFrontAxis * relativeDistanceFromFrontAxis * rightGroundHeight +
					relativeDistanceFromRightAxis * relativeDistanceFromRightAxis * frontGroundHeight
				) / squaredRelativeDistance

				return true, groundHeight
			end
		end

		return false
	end
end

function TerrainSmoothSlopedEllipse:getTypeMapInfoForPoint (x, y)
	local distanceFromFrontAxis = LineCoordsDistance(self.center, self.frontVector, x, y)
	local distanceFromRightAxis = LineCoordsDistance(self.center, self.rightVector, x, y)
	local relativeDistanceFromFrontAxis = distanceFromFrontAxis / self.halfWidth
	local relativeDistanceFromRightAxis = distanceFromRightAxis / self.halfHeight
	local squaredRelativeDistance = relativeDistanceFromFrontAxis * relativeDistanceFromFrontAxis + relativeDistanceFromRightAxis * relativeDistanceFromRightAxis

	local isInsideSlope = (
		squaredRelativeDistance <= 1.0
	)

	if (isInsideSlope) then
		local isTop = (
			squaredRelativeDistance < self.slopeTopRelativeSize * self.slopeTopRelativeSize
		)

		return true, true, isTop
	else
		local isInsideBase = false

		if (self.hasBaseTerrainType) then
			local outerHalfWidth  = self.halfWidth  + self.typeMapBorderWidth
			local outerHalfHeight = self.halfHeight + self.typeMapBorderWidth
			local relativeOuterDistanceFromFrontAxis = distanceFromFrontAxis / outerHalfWidth
			local relativeOuterDistanceFromRightAxis = distanceFromRightAxis / outerHalfHeight
			local squaredRelativeOuterDistance = relativeOuterDistanceFromFrontAxis * relativeOuterDistanceFromFrontAxis + relativeOuterDistanceFromRightAxis * relativeOuterDistanceFromRightAxis
		
			isInsideBase = (
				squaredRelativeOuterDistance <= 1.0
			)
		end
		
		return isInsideBase, false, false
	end
end

function TerrainSmoothSlopedEllipse:modifiesTypeMap()
	return (
		self.topTerrainType   ~= INITIAL_TERRAIN_TYPE or
		self.slopeTerrainType ~= INITIAL_TERRAIN_TYPE or
		self.baseTerrainType  ~= INITIAL_TERRAIN_TYPE
	)
end

function TerrainSmoothSlopedEllipse:getAABB(borderWidths)
	local borderWidth = borderWidths.isHeightMap and self.baseWidth or self.typeMapBorderWidth
	return TerrainEllipse.getAABBInternal(self, borderWidth, borderWidth)
end

--------------------------------------------------------------------------------

local TerrainSmoothSlopedEllipseRing = TerrainEllipse:inherit()

TerrainSmoothSlopedEllipseRing.modifyHeightMapForShape = modifyHeightMapForSmoothSlopedRing
TerrainSmoothSlopedEllipseRing.modifyTypeMapForShape   = modifyTypeMapForSmoothSlopedRing

function TerrainSmoothSlopedEllipseRing.initEmpty()
	local obj = TerrainSmoothSlopedEllipseRing.superClass.initEmpty()
	obj.ringWidth = 100
	obj.topGroundHeight = 100
	obj.slopeTopGroundHeight = 80
	obj.slopeBottomGroundHeight = 20
	obj.innerBaseBottomGroundHeight = 0
	obj.outerBaseBottomGroundHeight = 0
	obj.slopeTopRelativeSize = 0.2
	obj.innerBaseWidth = 50
	obj.innerBaseSlope = 0.0
	obj.outerBaseWidth = 50
	obj.outerBaseSlope = 0.0

	return obj
end

function TerrainSmoothSlopedEllipseRing.initializeData(obj)
	obj.topTerrainType       = obj.topTerrainType       or INITIAL_TERRAIN_TYPE
	obj.slopeTerrainType     = obj.slopeTerrainType     or INITIAL_TERRAIN_TYPE
	obj.innerBaseTerrainType = obj.innerBaseTerrainType or INITIAL_TERRAIN_TYPE
	obj.outerBaseTerrainType = obj.outerBaseTerrainType or INITIAL_TERRAIN_TYPE

    obj = TerrainSmoothSlopedEllipseRing.superClass.initializeData(obj)

	obj.halfRingWidth = obj.ringWidth / 2
	obj.halfTopWidth = obj.halfRingWidth * obj.slopeTopRelativeSize
	obj.widthSlope = (obj.slopeTopGroundHeight - obj.slopeBottomGroundHeight) / (obj.halfRingWidth - obj.halfTopWidth)

	obj.topGroundHeightFunction = QuadraticBezier2D:new{
		x0 = 0,
		y0 = obj.topGroundHeight,
		x1 = obj.halfTopWidth,
		y1 = obj.slopeTopGroundHeight,
		slope0 = 0,
		slope1 = -obj.widthSlope
	}
	obj.innerBaseGroundHeightFunction = QuadraticBezier2D:new{
		x0 = obj.innerBaseWidth,
		y0 = obj.innerBaseBottomGroundHeight,
		x1 = 0,
		y1 = obj.slopeBottomGroundHeight,
		slope0 = -obj.innerBaseSlope,
		slope1 = -obj.widthSlope
	}
	obj.outerBaseGroundHeightFunction = QuadraticBezier2D:new{
		x0 = obj.outerBaseWidth,
		y0 = obj.outerBaseBottomGroundHeight,
		x1 = 0,
		y1 = obj.slopeBottomGroundHeight,
		slope0 = -obj.outerBaseSlope,
		slope1 = -obj.widthSlope
	}

	obj.hasInnerBaseTerrainType  = (obj.innerBaseTerrainType ~= INITIAL_TERRAIN_TYPE)
	obj.hasOuterBaseTerrainType  = (obj.outerBaseTerrainType ~= INITIAL_TERRAIN_TYPE)
	obj.innerTypeMapBorderWidth  = (obj.hasInnerBaseTerrainType and 0 or obj.innerBaseWidth)
	obj.outerTypeMapBorderWidth  = obj.innerBaseWidth + obj.ringWidth + (obj.hasOuterBaseTerrainType and obj.outerBaseWidth or 0)
	obj.heightMapBorderWidth     = obj.innerBaseWidth + obj.ringWidth + obj.outerBaseWidth
	obj.ringCenterBorderDistance = obj.innerBaseWidth + obj.halfRingWidth
	obj.ringOuterBorderDistance  = obj.innerBaseWidth + obj.ringWidth

    return obj
end

function TerrainSmoothSlopedEllipseRing:prepareRotatedInstance(rotation)
	local rotatedInstance = TerrainSmoothSlopedEllipseRing.superClass.prepareRotatedInstance(self, rotation)
	rotatedInstance.ringWidth                   = self.ringWidth
	rotatedInstance.topGroundHeight             = self.topGroundHeight
	rotatedInstance.slopeTopGroundHeight        = self.slopeTopGroundHeight
	rotatedInstance.slopeBottomGroundHeight     = self.slopeBottomGroundHeight
	rotatedInstance.innerBaseBottomGroundHeight = self.innerBaseBottomGroundHeight
	rotatedInstance.outerBaseBottomGroundHeight = self.outerBaseBottomGroundHeight
	rotatedInstance.slopeTopRelativeSize        = self.slopeTopRelativeSize
	rotatedInstance.innerBaseWidth              = self.innerBaseWidth
	rotatedInstance.innerBaseSlope              = self.innerBaseSlope
	rotatedInstance.outerBaseWidth              = self.outerBaseWidth
	rotatedInstance.outerBaseSlope              = self.outerBaseSlope

	rotatedInstance.topTerrainType       = self.topTerrainType
	rotatedInstance.slopeTerrainType     = self.slopeTerrainType
	rotatedInstance.innerBaseTerrainType = self.innerBaseTerrainType
	rotatedInstance.outerBaseTerrainType = self.outerBaseTerrainType

	rotatedInstance.modifyHeightMapForShape = self.modifyHeightMapForShape
	rotatedInstance.modifyTypeMapForShape   = self.modifyTypeMapForShape

	return rotatedInstance
end

function TerrainSmoothSlopedEllipseRing:getGroundHeightForPoint (x, y)
	local distanceFromFrontAxis = LineCoordsDistance(self.center, self.frontVector, x, y)
	local distanceFromRightAxis = LineCoordsDistance(self.center, self.rightVector, x, y)

	local outerHalfWidth  = self.halfWidth  + self.heightMapBorderWidth
	local outerHalfHeight = self.halfHeight + self.heightMapBorderWidth
	local relativeOuterDistanceFromFrontAxis = distanceFromFrontAxis / outerHalfWidth
	local relativeOuterDistanceFromRightAxis = distanceFromRightAxis / outerHalfHeight
	local squaredRelativeOuterDistance = relativeOuterDistanceFromFrontAxis * relativeOuterDistanceFromFrontAxis + relativeOuterDistanceFromRightAxis * relativeOuterDistanceFromRightAxis

	local isInsideOuterBase = (
		squaredRelativeOuterDistance <= 1.0
	)

	if (isInsideOuterBase) then
		local relativeDistanceFromFrontAxis = distanceFromFrontAxis / self.halfWidth
		local relativeDistanceFromRightAxis = distanceFromRightAxis / self.halfHeight
		local squaredRelativeDistance = relativeDistanceFromFrontAxis * relativeDistanceFromFrontAxis + relativeDistanceFromRightAxis * relativeDistanceFromRightAxis

		local relativeDistance = sqrt(squaredRelativeDistance)
		local relativeDistanceFromBorder = relativeDistance - 1.0
		local borderDistanceMult = (
			relativeDistanceFromFrontAxis * relativeDistanceFromFrontAxis * self.halfWidth +
			relativeDistanceFromRightAxis * relativeDistanceFromRightAxis * self.halfHeight
		) / squaredRelativeDistance
		local distanceFromBorder = relativeDistanceFromBorder * borderDistanceMult

		isInsideOuterBase = (
			distanceFromBorder <= self.heightMapBorderWidth
		)		
		local isBetweenBases = (
			distanceFromBorder >= 0 and
			isInsideOuterBase
		)

		if (isBetweenBases) then
			local distanceFromRingCenter = abs(distanceFromBorder - self.ringCenterBorderDistance)
			local isInsideSlope = (
				distanceFromRingCenter <= self.halfRingWidth
			)

			if (isInsideSlope) then
				local isTop = (
					distanceFromRingCenter < self.halfTopWidth
				)

				if (isTop) then
					local groundHeight = self.topGroundHeightFunction:getYValueAtPos(distanceFromRingCenter)

					return true, true, groundHeight
				else
					local groundHeight = self.slopeTopGroundHeight - (distanceFromRingCenter - self.halfTopWidth) * self.widthSlope

					return true, true, groundHeight
				end
			else
				local isInnerBase = (
					distanceFromBorder < self.ringCenterBorderDistance
				)
				
				if (isInnerBase) then
					local distanceFromRingBorder = self.innerBaseWidth - distanceFromBorder
					local groundHeight = self.innerBaseGroundHeightFunction:getYValueAtPos(distanceFromRingBorder)

					return true, true, groundHeight
				else
					local distanceFromRingBorder = distanceFromBorder - self.ringOuterBorderDistance
					local groundHeight = self.outerBaseGroundHeightFunction:getYValueAtPos(distanceFromRingBorder)

					return true, true, groundHeight
				end
			end
		end
	end

	return isInsideOuterBase, false
end

function TerrainSmoothSlopedEllipseRing:getTypeMapInfoForPoint (x, y)
	local distanceFromFrontAxis = LineCoordsDistance(self.center, self.frontVector, x, y)
	local distanceFromRightAxis = LineCoordsDistance(self.center, self.rightVector, x, y)

	local outerHalfWidth  = self.halfWidth  + self.outerTypeMapBorderWidth
	local outerHalfHeight = self.halfHeight + self.outerTypeMapBorderWidth
	local relativeOuterDistanceFromFrontAxis = distanceFromFrontAxis / outerHalfWidth
	local relativeOuterDistanceFromRightAxis = distanceFromRightAxis / outerHalfHeight
	local squaredRelativeOuterDistance = relativeOuterDistanceFromFrontAxis * relativeOuterDistanceFromFrontAxis + relativeOuterDistanceFromRightAxis * relativeOuterDistanceFromRightAxis

	local isInsideOuterBase = (
		squaredRelativeOuterDistance <= 1.0
	)

	if (isInsideOuterBase) then
		local relativeDistanceFromFrontAxis = distanceFromFrontAxis / self.halfWidth
		local relativeDistanceFromRightAxis = distanceFromRightAxis / self.halfHeight
		local squaredRelativeDistance = relativeDistanceFromFrontAxis * relativeDistanceFromFrontAxis + relativeDistanceFromRightAxis * relativeDistanceFromRightAxis

		local relativeDistance = sqrt(squaredRelativeDistance)
		local relativeDistanceFromBorder = relativeDistance - 1.0
		local borderDistanceMult = (
			relativeDistanceFromFrontAxis * relativeDistanceFromFrontAxis * self.halfWidth +
			relativeDistanceFromRightAxis * relativeDistanceFromRightAxis * self.halfHeight
		) / squaredRelativeDistance
		local distanceFromBorder = relativeDistanceFromBorder * borderDistanceMult

		isInsideOuterBase = (
			distanceFromBorder <= self.outerTypeMapBorderWidth
		)		
		local isBetweenBases = (
			distanceFromBorder >= self.innerTypeMapBorderWidth and
			isInsideOuterBase
		)

		if (isBetweenBases) then
			local distanceFromRingCenter = abs(distanceFromBorder - self.ringCenterBorderDistance)
			local isInsideSlope = (
				distanceFromRingCenter <= self.halfRingWidth
			)

			if (isInsideSlope) then
				local isTop = (
					distanceFromRingCenter < self.halfTopWidth
				)

				return true, true, true, isTop, false
			else
				local isInnerBase = (
					distanceFromBorder < self.ringCenterBorderDistance
				)

				return true, true, false, false, isInnerBase
			end
		end
	end

	return isInsideOuterBase, false, false, false, false
end

function TerrainSmoothSlopedEllipseRing:modifiesTypeMap()
	return (
		self.topTerrainType       ~= INITIAL_TERRAIN_TYPE or
		self.slopeTerrainType     ~= INITIAL_TERRAIN_TYPE or
		self.innerBaseTerrainType ~= INITIAL_TERRAIN_TYPE or
		self.outerBaseTerrainType ~= INITIAL_TERRAIN_TYPE
	)
end

function TerrainSmoothSlopedEllipseRing:getAABB(borderWidths)
	local borderWidth = borderWidths.isHeightMap and self.heightMapBorderWidth or self.outerTypeMapBorderWidth
	return TerrainEllipse.getAABBInternal(self, borderWidth, borderWidth)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

return
    --TerrainEllipse,
    --TerrainNonBorderedEllipse,
    TerrainFlatEllipse,
	TerrainSmoothSlopedEllipse,
	TerrainSmoothSlopedEllipseRing
