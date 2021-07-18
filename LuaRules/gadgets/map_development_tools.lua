function gadget:GetInfo()
	return {
		name      = "Map Development Tools",
		desc      = "Helper tools for map development",
		author    = "Rafal[ZK]",
		date      = "July 2021",
		license   = "GNU GPL, v2 or later",
		layer     = math.huge,
		enabled   = true, --  loaded by default?
	}
end

if (gadgetHandler:IsSyncedCode()) then
	return false
end

--------------------------------------------------------------------------------
-- Unsynced
--------------------------------------------------------------------------------

local glColor            = gl.Color
local glTexture          = gl.Texture
local glCreateTexture    = gl.CreateTexture
local glRenderToTexture  = gl.RenderToTexture
local glDeleteTexture    = gl.DeleteTexture
local glDeleteTextureFBO = gl.DeleteTextureFBO
local glRect             = gl.Rect
local glTexRect          = gl.TexRect
local glSaveImage        = gl.SaveImage

local GL_RGB = 0x1907

local floor = math.floor

local mapSizeX = Game.mapSizeX
local mapSizeZ = Game.mapSizeZ
local SQUARE_SIZE = 1024
local BLOCK_SIZE  = 8

local MINIMAP_SIZE_X = 1024
local MINIMAP_SIZE_Y = 1024

GG.Tools = GG.Tools or {}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function createFboTexture(sizeX, sizeY)
    return glCreateTexture(sizeX, sizeY, {
		format = GL_RGB,
		border = false,
		min_filter = GL.LINEAR,
		mag_filter = GL.LINEAR,
		wrap_s = GL.CLAMP_TO_EDGE,
		wrap_t = GL.CLAMP_TO_EDGE,
		fbo = true
	})
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function CreateEmptyMapTextureImage(mapDimX, mapDimY, fillColor)
	local sizeX = mapDimX * 512
	local sizeY = mapDimY * 512

	local fillColor = fillColor or { 0, 0, 0, 1 }

	local mapTexture = createFboTexture(sizeX, sizeY)
	if (not mapTexture) then
		return
	end

	glRenderToTexture(mapTexture, function()
		glColor(fillColor)
		glRect(-1, -1, 1, 1)
		glColor(1, 1, 1, 1)
	end)

	glRenderToTexture(mapTexture, glSaveImage, 0, 0, sizeX, sizeY, "output/texture" .. mapDimX .. "x" .. mapDimY .. ".png", { alpha = false, yflip = false })
	
	glDeleteTextureFBO(mapTexture)
	glDeleteTexture(mapTexture)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function CreateHeightmapImage(mapDimX, mapDimY, minHeight, fillHeight, maxHeight)
	local HEIGHT_MAP_TILE_SIZE = 8
	local sizeX = mapDimX * (512 / HEIGHT_MAP_TILE_SIZE) + 1
	local sizeY = mapDimY * (512 / HEIGHT_MAP_TILE_SIZE) + 1

	local scaleX = (2 / (sizeX - 1))
	local scaleY = (2 / (sizeY - 1))

	local function drawPoint(x, y)
		glRect(x, y, x + scaleX, y + scaleY)
	end

	local minColor  = minHeight  / 255.0
	local fillColor = fillHeight / 255.0
	local maxColor  = maxHeight  / 255.0

	local heightMapTexture = createFboTexture(sizeX, sizeY)
	if (not heightMapTexture) then
		return
	end

	glRenderToTexture(heightMapTexture, function()
		glColor(fillColor, fillColor, fillColor, 1)
		glRect(-1, -1, 1, 1)
		glColor(minColor, minColor, minColor, 1)
		drawPoint(-1, -1)
		glColor(maxColor, maxColor, maxColor, 1)
		drawPoint(-1 + 1 * scaleX, -1)
		glColor(1, 1, 1, 1)
	end)
	
	glRenderToTexture(heightMapTexture, glSaveImage, 0, 0, sizeX, sizeY, "output/heightmap" .. fillHeight .. ".bmp", { alpha = false, yflip = false })
	
	glDeleteTextureFBO(heightMapTexture)
	glDeleteTexture(heightMapTexture)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function SaveMinimap()
	local texInfo = gl.TextureInfo("$minimap")
	local minimapTexture = createFboTexture(texInfo.xsize, texInfo.ysize)

	glTexture("$minimap")
	glRenderToTexture(minimapTexture, function()
		glTexRect(-1, -1, 1, 1)	
	end)
	glTexture(false)

	glRenderToTexture(minimapTexture, glSaveImage, 0, 0, texInfo.xsize, texInfo.ysize, "output/minimap.png", { alpha = false })
	
	glDeleteTextureFBO(minimapTexture)
	glDeleteTexture(minimapTexture)
end

function GG.Tools.SaveFullTexture(fullTex)
	glRenderToTexture(fullTex, gl.SaveImage, 0, 0, mapSizeX/BLOCK_SIZE, mapSizeZ/BLOCK_SIZE, "output/fulltex.png", { alpha = false, yflip = false })
end

local function GenerateMinimapWithLabel(fullTex, fileName, fontColor)
	fileName  = fileName  or "minimapWithLabel.png"
	fontColor = fontColor or { 1.0, 1.0, 0.0, 1.0 }

	--local fullTexPadding = 0.12 -- for map with 5 bases
	--local fullTexPadding = 0.10 -- for map with 6 bases
	local fullTexPadding = 0.08 -- for map with 7 bases

	local labelText = { "RANDOM", "GENERATOR", "FOR 3-11 PLAYERS" }
	local fontPath  = "fonts/FreeSansBold.otf"
	local fontSize  = 110

	local minimapTexture = createFboTexture(MINIMAP_SIZE_X, MINIMAP_SIZE_Y)
	local font = gl.LoadFont(fontPath, fontSize, 5, 5)

	glTexture(fullTex)
	glRenderToTexture(minimapTexture, function()
		glTexRect(-1, -1, 1, 1, fullTexPadding, fullTexPadding, 1 - fullTexPadding, 1 - fullTexPadding)	
	end)
	glTexture(false)

	gl.MatrixMode(GL.TEXTURE)

	local function drawText(x, y, text, textSize)
		local textHeight, textDescender = font:GetTextHeight(text)
		local textScale = (2.0 / MINIMAP_SIZE_Y)
		local textSizeMult = (textSize or 1.0) / textHeight

		gl.PushMatrix()
			gl.Scale(textScale, textScale, 1)
			gl.Translate(x, y, 0)
			gl.Scale(textSizeMult, -textSizeMult, 1)
			font:Print(text, 0, 0, fontSize, "cvo") -- ignores color because of outline
			font:Print(text, 0, 0, fontSize, "cv")  -- draw colored part again
		gl.PopMatrix()
	end

	glColor(fontColor)

	glRenderToTexture(minimapTexture, function()
		drawText(0, -200, labelText[1])
		drawText(0,   10, labelText[2])
		drawText(0,  210, labelText[3], 70 / 110)
	end)

	glColor(1, 1, 1, 1)
	gl.MatrixMode(GL.MODELVIEW)

	glRenderToTexture(minimapTexture, glSaveImage, 0, 0, MINIMAP_SIZE_X, MINIMAP_SIZE_Y, "output/" .. fileName, { alpha = false, yflip = false })

	gl.DeleteFont(font)
	glDeleteTextureFBO(minimapTexture)
	glDeleteTexture(minimapTexture)
end

function GG.Tools.GenerateAllMinimapsWithLabel(fullTex)
	GenerateMinimapWithLabel(fullTex, "minimap_white.png" , { 1.0, 1.0, 1.0, 1.0 })
	GenerateMinimapWithLabel(fullTex, "minimap_yellow.png", { 1.0, 1.0, 0.0, 1.0 })
	GenerateMinimapWithLabel(fullTex, "minimap_green.png" , { 0.0, 1.0, 0.0, 1.0 })
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function ExtractTextureFromPosition(x, z, sizeX, sizeZ)
	local squareTexture = createFboTexture(SQUARE_SIZE, SQUARE_SIZE)
	local extractedTexture = createFboTexture(sizeX, sizeZ)

	local squareX = floor(x / SQUARE_SIZE)
	local squareZ = floor(z / SQUARE_SIZE)
	Spring.GetMapSquareTexture(squareX, squareZ, 0, squareTexture)

	glTexture(squareTexture)
	glRenderToTexture(extractedTexture, function()
		local srcX = (x % SQUARE_SIZE) / SQUARE_SIZE
		local srcZ = (z % SQUARE_SIZE) / SQUARE_SIZE
		local srcSizeX = sizeX / SQUARE_SIZE
		local srcSizeZ = sizeZ / SQUARE_SIZE
		glTexRect(-1, -1, 1, 1, srcX, srcZ, srcX + srcSizeX, srcZ + srcSizeZ)		
	end)
	glTexture(false)
	
	glDeleteTextureFBO(squareTexture)
	glDeleteTexture(squareTexture)

	return {
		path   = extractedTexture,
		width  = sizeX,
		height = sizeY
	}
end

local function ExtractTexturesFromMap()
	local rampartTexture = ExtractTextureFromPosition(4040, 6160, BLOCK_SIZE, 512) -- rampart
	local wallTexture    = ExtractTextureFromPosition(3880, 6160, BLOCK_SIZE, 512) -- wall

	glRenderToTexture(rampartTexture.path, glSaveImage, 0, 0, BLOCK_SIZE, 512, "rock.png")
	glRenderToTexture(wallTexture   .path, glSaveImage, 0, 0, BLOCK_SIZE, 512, "crystal.png")
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local modifiedHeightMapSquares
local modifiedTypeMapSquares

local function LoadModifiedHeightMapSquares()
	if (not modifiedHeightMapSquares) then
		modifiedHeightMapSquares = SYNCED.mapgen_modifiedHeightMapSquares
	end

	return modifiedHeightMapSquares
end

local function LoadModifiedTypeMapSquares()
	if (not modifiedTypeMapSquares) then
		modifiedTypeMapSquares = SYNCED.mapgen_modifiedTypeMapSquares
	end

	return modifiedTypeMapSquares
end

local function DrawModifiedMapSquares(modifiedMapSquares, yPos, squarePadding)
	local mapSquareAlpha = 0.8 -- when over water
	--local mapSquareAlpha = 0.3 -- when over land
	local modifiedSquareColor   = { 0.0, 1.0, 0.0, mapSquareAlpha }
	local inAABBSquareColor     = { 1.0, 0.4, 0.0, mapSquareAlpha }
	local unmodifiedSquareColor = { 1.0, 0.0, 0.0, mapSquareAlpha }

	gl.MatrixMode(GL.MODELVIEW)

	gl.Culling(false)
	gl.DepthTest(true)
	gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)

	gl.PushMatrix()
	gl.Translate(0, yPos, 0)
	gl.Rotate(90, 1, 0, 0) -- from XY plane to XZ plane

	for sx = 1, #modifiedMapSquares do
		local modifiedMapSquaresX = modifiedMapSquares[sx]

		for sz = 1, #modifiedMapSquaresX do
			if (modifiedMapSquaresX[sz] >= 1) then
				glColor(modifiedSquareColor)
			elseif (modifiedMapSquaresX[sz] == 0) then  -- is in AABB of the shape, but eliminated by narrow check
				glColor(inAABBSquareColor)
			else
				glColor(unmodifiedSquareColor)
			end

			glRect(
				(sx - 1) * SQUARE_SIZE + squarePadding,
				(sz - 1) * SQUARE_SIZE + squarePadding,
				sx * SQUARE_SIZE - squarePadding,
				sz * SQUARE_SIZE - squarePadding
			)
		end
	end

	gl.PopMatrix()

	glColor(1, 1, 1, 1)
	gl.Blending(false)
	gl.DepthTest(false)
	gl.Culling(false)
	   
	gl.MatrixMode(GL.MODELVIEW)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local gameStarted = false
local allWorkFinished = false

function gadget:GameStart()
	gameStarted = true -- finish all processing in next Draw call
end

function gadget:DrawGenesis()
	if allWorkFinished then
		gadgetHandler:RemoveGadget()
		return
	end

	if (gameStarted) then  -- ensure everything is already generated
		allWorkFinished = true

		--CreateEmptyMapTextureImage(8, 8) -- can fail for large textures
		--CreateHeightmapImage(24, 24, 0, 45, 52)
		--SaveMinimap()
		--ExtractTexturesFromMap()
	end
end

function gadget:DrawWorldPreUnit()
	DrawModifiedMapSquares(LoadModifiedTypeMapSquares()  , 10, 4)
	DrawModifiedMapSquares(LoadModifiedHeightMapSquares(), 11, 32)
end
