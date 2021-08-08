local abs  = math.abs
local sqrt = math.sqrt
local sin  = math.sin
local cos  = math.cos

local PI   = math.pi
local TWO_PI = 2 * PI

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local Vector2D = createClass()

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

function Vector2D.UnitVectorFromAngle(angleRad)
	local v = Vector2D:new{
		x =  sin(angleRad),
		y = -cos(angleRad)
	}
	return v
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

local Rotation2D = createClass()

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

function Rotation2D:getRotatedAngle(angleRad)
	return ((angleRad + self.angleRad) % TWO_PI)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local Geom2D = {
    PointCoordsDistance        = PointCoordsDistance,
    PointCoordsSquaredDistance = PointCoordsSquaredDistance,
    PointPointDistance         = PointPointDistance,
    LineCoordsDistance         = LineCoordsDistance,
    LineCoordsProjection       = LineCoordsProjection,
    LineVectorLengthProjection = LineVectorLengthProjection
}

return
    Geom2D,
    Vector2D,
    Rotation2D
