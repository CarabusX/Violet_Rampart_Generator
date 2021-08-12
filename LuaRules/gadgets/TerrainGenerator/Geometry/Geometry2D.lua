local min  = math.min
local max  = math.max
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

local function LineCoordsSignedDistance (p, v, x, y) -- positive to the right, negative to the left
	return (-v.x * (y - p.y) + v.y * (x - p.x))
end

local function LineCoordsProjection (p, v, x, y) -- can be negative
	return (v.x * (x - p.x) + v.y * (y - p.y))
end

local function LineVectorLengthProjection (dirV, vx, vy)
	return abs(dirV.x * vx + dirV.y * vy)
end

--------------------------------------------------------------------------------

local function SolveQuadraticEquation(a, b, c)
	if (a == 0) then
		local x = -c / b

		return x
	else
		local delta = b * b - 4 * a * c

		if (delta > 0) then
			local deltaRoot = sqrt(delta)
			local x1 = (-b - deltaRoot) / (2 * a)
			local x2 = (-b + deltaRoot) / (2 * a)

			return x1, x2
		elseif (delta == 0) then
			local x = -b / (2 * a)

			return x
		else
			return nil
		end
	end
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

local CubicFunction2D = createClass()

function CubicFunction2D:new (obj)
	obj = obj or {}
	obj.slope0 = obj.slope0 or 0

	local x0 = obj.x0
	local x1 = obj.x1

	if (x0 ~= x1) then
		local dx        = x1 - x0
		local dSquaredX = x1 * x1 - x0 * x0
		local dy        = obj.y1 - obj.y0

		obj.a = (-2 * dy + (obj.slope0 + obj.slope1) * dx) / (dx * dx * dx)   -- Solved using online solver
		obj.b = (obj.slope1 - obj.slope0 - 3 * obj.a * dSquaredX) / (2 * dx)  -- Solved manually
		obj.c = obj.slope0 - (3 * obj.a * x0 + 2 * obj.b) * x0
		obj.d = obj.y0 - ((obj.a * x0 + obj.b) * x0 + obj.c) * x0
	else
		obj.getYValueAtPos = CubicFunction2D.getYValueAtPos_constant
		obj.getSlopeAtPos  = CubicFunction2D.getSlopeAtPos_constant
	end

	setmetatable(obj, self)
	return obj
end

function CubicFunction2D:getYValueAtPos(x)
	return (((self.a * x + self.b) * x + self.c) * x + self.d)
end

function CubicFunction2D:getSlopeAtPos(x)
	return ((3 * self.a * x + 2 * self.b) * x + self.c)
end

function CubicFunction2D:getYValueAtPos_constant(x)
	return self.y0
end

function CubicFunction2D:getSlopeAtPos_constant(x)
	return self.slope0
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local QuadraticBezier2D = createClass()

function QuadraticBezier2D:new (obj)
	obj = obj or {}
	obj.slope0 = obj.slope0 or 0

	local x0 = obj.x0
	local x1 = obj.x1

	if (x0 ~= x1) then
		local y0 = obj.y0
		local y1 = obj.y1
		local controlX = nil
		
		if (obj.slope0 ~= obj.slope1) then
			controlX = (y0 - y1 + x1 * obj.slope1 - x0 * obj.slope0) / (obj.slope1 - obj.slope0)
		end
		if ((not controlX) or controlX < min(x0, x1) or max(x0, x1) < controlX) then
			return CubicFunction2D:new(obj)  -- Fallback to cubic function
		end

		obj.controlX = controlX
		obj.controlY = y0 + (controlX - x0) * obj.slope0

		obj.xa = x0 + x1 - 2 * controlX
		obj.xb = 2 * (controlX - x0)
		obj.xc = x0

		obj.ya = y0 + y1 - 2 * obj.controlY
		obj.yb = 2 * (obj.controlY - y0)
		obj.yc = y0
	else
		obj.getYValueAtPos = QuadraticBezier2D.getYValueAtPos_constant
	end

	setmetatable(obj, self)
	return obj
end

function QuadraticBezier2D:getYValueAtPos(x)
	local t1, t2 = SolveQuadraticEquation(self.xa, self.xb, self.xc - x)
	local t = (t1 and 0 <= t1 and t1 <= 1) and t1 or t2
	
	if (t) then
		return ((self.ya * t + self.yb) * t + self.yc)
	else
		return self.y0
	end
end

function QuadraticBezier2D:getYValueAtPos_constant(x)
	return self.y0
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local Geom2D = {
    PointCoordsDistance        = PointCoordsDistance,
    PointCoordsSquaredDistance = PointCoordsSquaredDistance,
    PointPointDistance         = PointPointDistance,
    LineCoordsDistance         = LineCoordsDistance,
	LineCoordsSignedDistance   = LineCoordsSignedDistance,
    LineCoordsProjection       = LineCoordsProjection,
    LineVectorLengthProjection = LineVectorLengthProjection
}

return
    Geom2D,
    Vector2D,
    Rotation2D,
	CubicFunction2D,
	QuadraticBezier2D
