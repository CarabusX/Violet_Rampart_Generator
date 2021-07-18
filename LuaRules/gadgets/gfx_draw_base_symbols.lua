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
local BASE_SYMBOL_COLOR = { 1.0, 1.0, 1.0, 1.0 }
local BASE_SYMBOL_ALPHA = 0.125
local BASE_SYMBOL_MINIMAP_ALPHA = 0.60
local BASE_SYMBOL_MINIMAP_SCALE = 2.00

local MIN_HEIGHTMAP_UPDATE_PERIOD = 6

--------------------------------------------------------------------------------

local glLoadFont         = gl.LoadFont
local glCreateTexture    = gl.CreateTexture
local glRenderToTexture  = gl.RenderToTexture
local glDeleteTexture    = gl.DeleteTexture
local glDeleteTextureFBO = gl.DeleteTextureFBO
local glMatrixMode       = gl.MatrixMode
local glPushMatrix       = gl.PushMatrix
local glPopMatrix        = gl.PopMatrix
local glTranslate        = gl.Translate
local glScale            = gl.Scale
local glRect             = gl.Rect
local glPolygonOffset    = gl.PolygonOffset
local glCulling          = gl.Culling
local glDepthTest        = gl.DepthTest
local glBlending         = gl.Blending
local glTexture          = gl.Texture
local glColor            = gl.Color
local glDrawGroundQuad   = gl.DrawGroundQuad
local glTexRect          = gl.TexRect

local glCreateList = gl.CreateList
local glCallList   = gl.CallList
local glDeleteList = gl.DeleteList

local GL_TEXTURE = GL.TEXTURE
local GL_MODELVIEW = GL.MODELVIEW
local GL_BACK = GL.BACK
local GL_SRC_ALPHA = GL.SRC_ALPHA
local GL_ONE_MINUS_SRC_ALPHA = GL.ONE_MINUS_SRC_ALPHA

local mapSizeX = Game.mapSizeX
local mapSizeZ = Game.mapSizeZ

--------------------------------------------------------------------------------

local HALF_BASE_SYMBOL_WIDTH  = BASE_SYMBOL_WIDTH  / 2
local HALF_BASE_SYMBOL_HEIGHT = BASE_SYMBOL_HEIGHT / 2

local HALF_BASE_SYMBOL_MINIMAP_WIDTH  = HALF_BASE_SYMBOL_WIDTH  * BASE_SYMBOL_MINIMAP_SCALE
local HALF_BASE_SYMBOL_MINIMAP_HEIGHT = HALF_BASE_SYMBOL_HEIGHT * BASE_SYMBOL_MINIMAP_SCALE

local bases

local symbolTextures = {}
local symbolTexturesCreated = false
local symbolDisplayListCreated = false
local displayList = false

GG.DrawBaseSymbolsApi = GG.DrawBaseSymbolsApi or {}

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
					glColor(BASE_SYMBOL_COLOR)
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

	gl.DeleteFont(symbolFont)
end

local function createSymbolTexturesIfNeeded()
	if (not symbolTexturesCreated) then
		symbolTexturesCreated = true
		createSymbolTextures()
	end
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
	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
	glColor(1, 1, 1, BASE_SYMBOL_ALPHA)

	for i = 1, #bases do
		local base = bases[i]
		local symbol = base.symbol

		if (symbol) then
			glTexture(symbolTextures[symbol])
			glDrawGroundQuad(
				base.x - HALF_BASE_SYMBOL_WIDTH, base.z - HALF_BASE_SYMBOL_HEIGHT,
				base.x + HALF_BASE_SYMBOL_WIDTH, base.z + HALF_BASE_SYMBOL_HEIGHT,
				false, 0.0, 0.0, 1.0, 1.0
			)
		end
	end

	glTexture(false)
	glColor(1, 1, 1, 1)
	glBlending(false)
	glDepthTest(false)
	glCulling(false)
	glPolygonOffset(false)
end

function GG.DrawBaseSymbolsApi.DrawBaseSymbolsOnTexture(mapTexture)
	createSymbolTexturesIfNeeded()

	glMatrixMode(GL_TEXTURE)
	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
	glColor(1, 1, 1, BASE_SYMBOL_MINIMAP_ALPHA)

	glRenderToTexture(mapTexture, function()
		glPushMatrix()
		glTranslate(-1, -1, 0)
		glScale(2 / mapSizeX, 2 / mapSizeZ, 1)
	
		for i = 1, #bases do
			local base = bases[i]
			local symbol = base.symbol
	
			if (symbol) then
				glTexture(symbolTextures[symbol])
				glTexRect(
					base.x - HALF_BASE_SYMBOL_MINIMAP_WIDTH, base.z - HALF_BASE_SYMBOL_MINIMAP_HEIGHT,
					base.x + HALF_BASE_SYMBOL_MINIMAP_WIDTH, base.z + HALF_BASE_SYMBOL_MINIMAP_HEIGHT,
					0.0, 0.0, 1.0, 1.0
				)
			end
		end

		glPopMatrix()
	end)

	glTexture(false)
	glColor(1, 1, 1, 1)
	glBlending(false)
	glMatrixMode(GL_MODELVIEW)
end

local function createDisplayList()
	if (displayList) then
		glDeleteList(displayList)
	end
	displayList = glCreateList(drawBaseSymbols)
end

--------------------------------------------------------------------------------

local lastRequestedUpdateFrame = -math.huge
local updateRequestedFrame = false
local frameNumber = -1

function gadget:Initialize()
	bases = SYNCED.mapgen_baseSymbols

	if (not bases) then
		gadgetHandler:RemoveGadget()
		return
	end
end

local drawCount = 0

function gadget:DrawGenesis()
	drawCount = drawCount + 1

	if (drawCount < 2) then  -- skip first Draw because for some reason textures rendered then are bugged
		return
	end

	if (not symbolDisplayListCreated) then
		symbolDisplayListCreated = true
		createSymbolTexturesIfNeeded()

		updateRequestedFrame = false
		createDisplayList()
	elseif (updateRequestedFrame and lastRequestedUpdateFrame + MIN_HEIGHTMAP_UPDATE_PERIOD <= frameNumber) then
		if (updateRequestedFrame >= 0) then
			lastRequestedUpdateFrame = updateRequestedFrame
		end
		updateRequestedFrame = false

		-- Update display to take terraform into account
		createDisplayList()
	end
end

function gadget:GameFrame(frame)
	frameNumber = frame
end

function gadget:UnsyncedHeightMapUpdate(x1, z1, x2, z2)
	updateRequestedFrame = frameNumber
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
