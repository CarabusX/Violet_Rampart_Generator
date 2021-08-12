local min = math.min
local max = math.max

-- Localize variables

local DISTANCE_HUGE = EXPORT.DISTANCE_HUGE

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local BoundedShape = createClass()

function BoundedShape:new(obj)
	obj = obj or {}

	setmetatable(obj, self)
	return obj
end

function BoundedShape:getRotatedInstance(rotation)
	local rotatedObj = {		
		terrainShape  = self.terrainShape :getRotatedInstance(rotation),
		boundingShape = self.boundingShape:getRotatedInstance(rotation)
	}

    return self.class:new(rotatedObj)
end

function BoundedShape:modifiesHeightMap()
	return self.terrainShape:modifiesHeightMap()
end

function BoundedShape:modifiesTypeMap()
	return self.terrainShape:modifiesTypeMap()
end

function BoundedShape:modifyHeightMapForShape (heightMapX, x, z)
    if (self.boundingShape:isPointInsideShape(x, z)) then
        return self.terrainShape:modifyHeightMapForShape(heightMapX, x, z)
    else
        return false
    end
end

function BoundedShape:modifyTypeMapForShape (typeMapX, tmz, x, z)
    if (self.boundingShape:isPointInsideTypeMap(x, z)) then
        return self.terrainShape:modifyTypeMapForShape(typeMapX, tmz, x, z)
    else
        return false
    end
end

function BoundedShape:isPointInsideShape (x, y)
    return (
        self.boundingShape:isPointInsideShape(x, y) and
        self.terrainShape:isPointInsideShape(x, y)
    )
end

function BoundedShape:getDistanceFromBorderForPoint (x, y)
    if (self.boundingShape:isPointInsideShape(x, y)) then
        return self.terrainShape:getDistanceFromBorderForPoint(x, y)
    else
        return DISTANCE_HUGE
    end
end

function BoundedShape:getGroundHeightForPoint (x, y)
    if (self.boundingShape:isPointInsideShape(x, y)) then
        return self.terrainShape:getGroundHeightForPoint(x, y)
    else
        return false, false
    end
end

function BoundedShape:isPointInsideTypeMap (x, y)
    return (
        self.boundingShape:isPointInsideTypeMap(x, y) and
        self.terrainShape:isPointInsideTypeMap(x, y)
    )
end

function BoundedShape:getTypeMapInfoForPoint (x, y)
    if (self.boundingShape:isPointInsideTypeMap(x, y)) then
        return self.terrainShape:getTypeMapInfoForPoint(x, y)
    else
        return false, false
    end
end

function BoundedShape:getAABB(borderWidths)
    local terrainAABB  = self.terrainShape :getAABB(borderWidths)
    local boundingAABB = self.boundingShape:getAABB(borderWidths)

	return {
		x1 = max(terrainAABB.x1, boundingAABB.x1),
		y1 = max(terrainAABB.y1, boundingAABB.y1),
		x2 = min(terrainAABB.x2, boundingAABB.x2),
		y2 = min(terrainAABB.y2, boundingAABB.y2)
	}
end

function BoundedShape:canCheckMapSquareNarrowIntersection()
	return (
        self.boundingShape:canCheckMapSquareNarrowIntersection() or
        self.terrainShape :canCheckMapSquareNarrowIntersection()
    )
end

function BoundedShape:intersectsMapSquare(sx, sz, squareContentPadding, borderWidths)
	return (
        self.boundingShape:intersectsMapSquare(sx, sz, squareContentPadding, borderWidths) and
        self.terrainShape :intersectsMapSquare(sx, sz, squareContentPadding, borderWidths)
    )
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

return
    BoundedShape
