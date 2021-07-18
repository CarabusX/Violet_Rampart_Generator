function gadget:GetInfo()
	return {
		name    = "Draw Base Symbol",
		desc    = "Draws a symbol on ground in each starting base",
		author  = "Rafal[ZK] (based on the Lua Metal Spots widget by Bluestone)",
		date    = "July 2021",
		license = "GPL v3 or later",
		layer   = 3,
		enabled = true
	}
end

if (gadgetHandler:IsSyncedCode()) then
	return false
end

--------------------------------------------------------------------------------
-- Unsynced
--------------------------------------------------------------------------------

local BASE_SYMBOL_WIDTH  = 160
local BASE_SYMBOL_HEIGHT = 160

local BASE_SYMBOL_FONT  = "fonts/FreeSansBold.otf"
local BASE_SYMBOL_COLOR = { 1.0, 1.0, 1.0, 0.125 }

--------------------------------------------------------------------------------

local glLoadFont         = gl.LoadFont
local glCreateTexture    = gl.CreateTexture
local glRenderToTexture  = gl.RenderToTexture
local glDeleteTexture    = gl.DeleteTexture
local glDeleteTextureFBO = gl.DeleteTextureFBO
local glMatrixMode       = gl.MatrixMode
local glPushMatrix       = gl.PushMatrix
local glScale            = gl.Scale
local glPopMatrix        = gl.PopMatrix
local glRect             = gl.Rect
local glPolygonOffset    = gl.PolygonOffset
local glCulling          = gl.Culling
local glDepthTest        = gl.DepthTest
local glTexture          = gl.Texture
local glColor            = gl.Color
local glBlending         = gl.Blending
local glDrawGroundQuad   = gl.DrawGroundQuad

local glCreateList = gl.CreateList
local glCallList   = gl.CallList
local glDeleteList = gl.DeleteList

local GL_TEXTURE = GL.TEXTURE
local GL_MODELVIEW = GL.MODELVIEW
local GL_BACK = GL.BACK
local GL_SRC_ALPHA = GL.SRC_ALPHA
local GL_ONE_MINUS_SRC_ALPHA = GL.ONE_MINUS_SRC_ALPHA

--------------------------------------------------------------------------------

local HALF_BASE_SYMBOL_WIDTH  = BASE_SYMBOL_WIDTH  / 2
local HALF_BASE_SYMBOL_HEIGHT = BASE_SYMBOL_HEIGHT / 2

local bases

local symbolTextures = {}
local symbolTexturesCreated = false
local displayList = false

--------------------------------------------------------------------------------

local function createFboTexture(sizeX, sizeY)
    return glCreateTexture(sizeX, sizeY, {
		border = false,
		min_filter = GL.LINEAR,
		mag_filter = GL.LINEAR,
		wrap_s = GL.CLAMP_TO_EDGE,
		wrap_t = GL.CLAMP_TO_EDGE,
		fbo = true
	})
end

local function createSymbolTextures()
	local symbolFont = glLoadFont(BASE_SYMBOL_FONT, BASE_SYMBOL_HEIGHT, 0, 0)

	glMatrixMode(GL_TEXTURE)

	for i = 1, #bases do
		local symbol = bases[i].symbol

		if symbol and (not symbolTextures[symbol]) then
			local symbolTexture = createFboTexture(BASE_SYMBOL_WIDTH, BASE_SYMBOL_HEIGHT)

			glRenderToTexture(symbolTexture, function()
				local textHeight, textDescender = symbolFont:GetTextHeight(symbol)
				local textScale = 2 / (BASE_SYMBOL_HEIGHT * (textHeight + textDescender + 0.04))  -- offset because bottom of "C" letter was slighty cut
				glPushMatrix()
				glScale(textScale, -textScale, 1)
				glColor(BASE_SYMBOL_COLOR[1], BASE_SYMBOL_COLOR[2], BASE_SYMBOL_COLOR[3], 1)
				symbolFont:Print(symbol, 0, 0, BASE_SYMBOL_HEIGHT, "cv")
				glPopMatrix()
			end)

			symbolTextures[symbol] = symbolTexture

			--glRenderToTexture(symbolTexture, gl.SaveImage, 0, 0, BASE_SYMBOL_WIDTH, BASE_SYMBOL_HEIGHT, "output/symbol_" .. symbol .. ".png", { yflip = false })
			glDeleteTextureFBO(symbolTexture)
		end
	end

	glColor(1, 1, 1, 1)
	glMatrixMode(GL_MODELVIEW)
end

local function deleteSymbolTextures()
	for _, symbolTexture in pairs(symbolTextures) do
		if (symbolTexture) then
			glDeleteTexture(symbolTexture)
		end
	end
end

--------------------------------------------------------------------------------

local function drawBaseSymbols()
	glPolygonOffset(-23, -2) -- (-23, -1)
	glCulling(GL_BACK)
	glDepthTest(true)
	glColor(1, 1, 1, BASE_SYMBOL_COLOR[4])
	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

	for i = 1, #bases do
		local base = bases[i]
		local symbol = base.symbol

		if (symbol) then
			glTexture(symbolTextures[symbol])
			glDrawGroundQuad(
				base.x - HALF_BASE_SYMBOL_WIDTH, base.z - HALF_BASE_SYMBOL_HEIGHT,
				base.x + HALF_BASE_SYMBOL_WIDTH, base.z + HALF_BASE_SYMBOL_HEIGHT,
				false, 0.0, 0.0, 1.0, 1.0)
		end
	end

	glTexture(false)
	glColor(1, 1, 1, 1)
	glDepthTest(false)
	glCulling(false)
	glPolygonOffset(false)
end

local function createDisplayList()
	if (displayList) then
		glDeleteList(displayList)
	end
	displayList = glCreateList(drawBaseSymbols)
end

function gadget:Initialize()
	bases = SYNCED.mapgen_baseSymbols

	if not bases then
		gadgetHandler:RemoveGadget()
		return
	end
end

local drawCount = 0

function gadget:DrawGenesis()
	if symbolTexturesCreated then
		return
	end

	drawCount = drawCount + 1

	if drawCount >= 2 then  -- skip first Draw because for some reason textures rendered then are bugged
		symbolTexturesCreated = true
		createSymbolTextures()
		createDisplayList()
	end
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
		if (displayList) then
			glCallList(displayList)
		end
	--end
end

function gadget:Shutdown()
	if (displayList) then
		glDeleteList(displayList)
		deleteSymbolTextures()
	end
end
