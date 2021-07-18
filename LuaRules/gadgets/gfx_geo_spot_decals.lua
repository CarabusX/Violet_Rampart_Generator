function gadget:GetInfo()
	return {
		name    = "Geo Spots Decals",
		desc    = "Draws a decal on each geo spot",
		author  = "Rafal[ZK] (based on the Lua Metal Spots widget by Bluestone)",
		date    = "July 2021",
		license = "GPL v3 or later",
		layer   = 6, -- after Lua Metal Decals
		enabled = true
	}
end

if (gadgetHandler:IsSyncedCode()) then
	return false
end

--------------------------------------------------------------------------------
-- Unsynced
--------------------------------------------------------------------------------

local GEO_TEXTURE  = ":ac:bitmaps/map/geohole.png"
local GEO_WIDTH    = 32
local GEO_HEIGHT   = 32

local GEO_ALPHA = 1.00

local ROTATE_GEO = false

--------------------------------------------------------------------------------

local glMatrixMode     = gl.MatrixMode
local glPolygonOffset  = gl.PolygonOffset
local glCulling        = gl.Culling
local glDepthTest      = gl.DepthTest
local glTexture        = gl.Texture
local glColor          = gl.Color
local glPushMatrix     = gl.PushMatrix
local glTranslate      = gl.Translate
local glRotate         = gl.Rotate
local glDrawGroundQuad = gl.DrawGroundQuad
local glPopMatrix      = gl.PopMatrix

local glCreateList = gl.CreateList
local glCallList   = gl.CallList
local glDeleteList = gl.DeleteList

local GL_TEXTURE = GL.TEXTURE
local GL_MODELVIEW = GL.MODELVIEW
local GL_BACK = GL.BACK

--------------------------------------------------------------------------------

local HALF_GEO_WIDTH  = GEO_WIDTH  / 2
local HALF_GEO_HEIGHT = GEO_HEIGHT / 2

local geoSpots
local geoRotations = {}

local displayList = false

function drawGeos()
	-- Switch to texture matrix mode
	glMatrixMode(GL_TEXTURE)
	   
	glPolygonOffset(-26, -3) -- (-25, -2)
	glCulling(GL_BACK)
	glDepthTest(true)
	glTexture(GEO_TEXTURE)
	glColor(1, 1, 1, GEO_ALPHA)

	for i = 1, #geoSpots do
		local geo = geoSpots[i]
		geoRotations[i] = geoRotations[i] or (360 * math.random())

		glPushMatrix()
		glTranslate(0.5, 0.5, 0)
		if (ROTATE_GEO) then
			glRotate(geoRotations[i], 0, 0, 1)
		end
		glDrawGroundQuad(
			geo.x - HALF_GEO_WIDTH, geo.z - HALF_GEO_HEIGHT,
			geo.x + HALF_GEO_WIDTH, geo.z + HALF_GEO_HEIGHT,
			false, -0.5, -0.5, 0.5, 0.5)
		glPopMatrix()
	end

	glColor(1, 1, 1, 1)
	glTexture(false)
	glDepthTest(false)
	glCulling(false)
	glPolygonOffset(false)
	   
	-- Restore Modelview matrix
	glMatrixMode(GL_MODELVIEW)
end

function createDisplayList()
	if (displayList) then
		glDeleteList(displayList)
	end
	displayList = glCreateList(drawGeos)
end

function gadget:Initialize()
	geoSpots = SYNCED.mapgen_geoList

	if not geoSpots then
		gadgetHandler:RemoveGadget()
		return
	end

	createDisplayList()
end

function gadget:GameFrame(n)
	if (n % 15 == 0) then
		-- Update display to take terraform into account
		createDisplayList()
	end
end

function gadget:DrawWorldPreUnit()
	--local mode = Spring.GetMapDrawMode()
	--if (mode ~= "height" and mode ~= "pathTraversability") then
		glCallList(displayList)
	--end
end

function gadget:Shutdown()
	if (displayList) then
		glDeleteList(displayList)
	end
end
