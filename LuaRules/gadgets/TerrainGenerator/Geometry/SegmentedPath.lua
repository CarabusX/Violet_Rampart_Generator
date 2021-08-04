local sin = math.sin
local cos = math.cos

-- Localize functions

local PointPointDistance = Geom2D.PointPointDistance

-- Localize classes

local Vector2D = Vector2D

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local LineSegment = createClass()

function LineSegment:new(obj)
	obj = obj or {}
	obj.length      = PointPointDistance(obj.p1, obj.p2)
	obj.frontVector = Vector2D.UnitVectorFromPoints(obj.p1, obj.p2)

	setmetatable(obj, self)
	return obj
end

function LineSegment:getPointOnSegment(advance)
	return {
		x = self.p1.x + self.frontVector.x * advance,
		y = self.p1.y + self.frontVector.y * advance
	}
end

--------------------------------------------------------------------------------

local ArcSegment = createClass()

function ArcSegment:new(obj)
	obj = obj or {}
	obj.length = obj.angularLengthRad * obj.radius

	setmetatable(obj, self)
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

local SegmentedPath = createClass()

function SegmentedPath:new(obj)
	obj = obj or {}
	obj.segments = obj.segments or {}
	obj.totalLength = 0
	for i = 1, #(obj.segments) do
		local segment = obj.segments[i]
		obj.totalLength = obj.totalLength + segment.length
	end

	setmetatable(obj, self)
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

return
    LineSegment,
    ArcSegment,
    SegmentedPath
