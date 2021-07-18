function gadget:GetInfo()
	return {
		name    = "Metal Spots Decals",
		desc    = "Draws a decal on each metal spot",
		author  = "Bluestone (based on the Lua Metal Spots widget by Cheesecan), edited by Rafal[ZK]",
		date    = "April 2014, edited July 2021",
		license = "GPL v3 or later",
		layer   = 4, -- before ZK Lua Metal Decals
		enabled = true
	}
end

if (gadgetHandler:IsSyncedCode()) then
	return false
end

--------------------------------------------------------------------------------
-- Unsynced
--------------------------------------------------------------------------------

--local MEX_TEXTURE = "luaui/images/metal_spot.png"
local MEX_TEXTURE = ":ac:bitmaps/map/metalspot.png"
local MEX_WIDTH   = 80
local MEX_HEIGHT  = 80

local MEX_MIN_ALPHA = 0.60
local MEX_MAX_ALPHA = 1.00
local MEX_METAL_FOR_MIN_ALPHA = 1.5
local MEX_METAL_FOR_MAX_ALPHA = 3.0

--------------------------------------------------------------------------------

local glMatrixMode     = gl.MatrixMode
local glPolygonOffset  = gl.PolygonOffset
local glCulling        = gl.Culling
local glDepthTest      = gl.DepthTest
local glBlending       = gl.Blending
local glTexture        = gl.Texture
local glColor          = gl.Color
local glPushMatrix     = gl.PushMatrix
local glPopMatrix      = gl.PopMatrix
local glTranslate      = gl.Translate
local glRotate         = gl.Rotate
local glDrawGroundQuad = gl.DrawGroundQuad

local glCreateList = gl.CreateList
local glCallList   = gl.CallList
local glDeleteList = gl.DeleteList

local GL_TEXTURE   = GL.TEXTURE
local GL_MODELVIEW = GL.MODELVIEW
local GL_BACK      = GL.BACK
local GL_SRC_ALPHA = GL.SRC_ALPHA
local GL_ONE_MINUS_SRC_ALPHA = GL.ONE_MINUS_SRC_ALPHA

local min = math.min
local max = math.max

--------------------------------------------------------------------------------

local HALF_MEX_WIDTH  = MEX_WIDTH  / 2
local HALF_MEX_HEIGHT = MEX_HEIGHT / 2

local metalSpots
local mexRotations = {}

local displayList = false

local function clamp(minValue, value, maxValue)
	return min(max(minValue, value), maxValue)
end

local function drawMetalPatches()
	-- Switch to texture matrix mode
	glMatrixMode(GL_TEXTURE)
	   
	glPolygonOffset(-24, -1) -- (-25, -2)
	glCulling(GL_BACK)
	glDepthTest(true)
	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
	glTexture(MEX_TEXTURE)

	for i = 1, #metalSpots do
		local spot = metalSpots[i]
		mexRotations[i] = mexRotations[i] or (360 * math.random())

		local mexAlphaFactor = (spot.metal - MEX_METAL_FOR_MIN_ALPHA) / (MEX_METAL_FOR_MAX_ALPHA - MEX_METAL_FOR_MIN_ALPHA)
		mexAlphaFactor = clamp(0.0, mexAlphaFactor, 1.0)
		local mexAlpha = MEX_MIN_ALPHA + mexAlphaFactor * (MEX_MAX_ALPHA - MEX_MIN_ALPHA)

		glColor(1, 1, 1, mexAlpha)
		glPushMatrix()
			glTranslate(0.5, 0.5, 0)
			glRotate(mexRotations[i], 0, 0, 1)
			glDrawGroundQuad(
				spot.x - HALF_MEX_WIDTH, spot.z - HALF_MEX_HEIGHT,
				spot.x + HALF_MEX_WIDTH, spot.z + HALF_MEX_HEIGHT,
				false, -0.5, -0.5, 0.5, 0.5
			)
		glPopMatrix()
	end

	glColor(1, 1, 1, 1)
	glTexture(false)
	glBlending(false)
	glDepthTest(false)
	glCulling(false)
	glPolygonOffset(false)
	   
	-- Restore Modelview matrix
	glMatrixMode(GL_MODELVIEW)
end

local function createDisplayList()
	if (displayList) then
		glDeleteList(displayList)
	end
	displayList = glCreateList(drawMetalPatches)
end

function gadget:Initialize()
	metalSpots = SYNCED.mapgen_mexList

	if not metalSpots then
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
