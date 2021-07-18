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

local GL_RGB  = 0x1907

local floor = math.floor

local mapSizeX = Game.mapSizeX
local mapSizeZ = Game.mapSizeZ
local SQUARE_SIZE = 1024
local BLOCK_SIZE  = 8

GG.Tools = GG.Tools or {}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function createFboTexture(sizeX, sizeY)
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
	local wallTexture = ExtractTextureFromPosition(3880, 6160, BLOCK_SIZE, 512) -- wall

	glRenderToTexture(rampartTexture.path, glSaveImage, 0, 0, BLOCK_SIZE, 512, "rock.png")
	glRenderToTexture(wallTexture   .path, glSaveImage, 0, 0, BLOCK_SIZE, 512, "crystal.png")
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
