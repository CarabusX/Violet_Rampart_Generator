local sqrt = math.sqrt

-- Localize variables

local RAMPART_OUTER_TYPEMAP_WIDTH = EXPORT.RAMPART_OUTER_TYPEMAP_WIDTH
local BORDER_TYPE_NO_WALL    = EXPORT.BORDER_TYPE_NO_WALL
local BORDER_TYPE_SHARP_EDGE = EXPORT.BORDER_TYPE_SHARP_EDGE
local RAMPART_HEIGHT       = EXPORT.RAMPART_HEIGHT
local RAMPART_TERRAIN_TYPE = EXPORT.RAMPART_TERRAIN_TYPE

-- Localize functions

local LineCoordsDistance = Geom2D.LineCoordsDistance

local modifyHeightMapForFlatShape    = EXPORT.modifyHeightMapForFlatShape
local modifyTypeMapForNotWalledShape = EXPORT.modifyTypeMapForNotWalledShape

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
--------------------------------------------------------------------------------

return
    --TerrainEllipse,
    --TerrainNonBorderedEllipse,
    TerrainFlatEllipse
