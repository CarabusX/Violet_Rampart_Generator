function gadget:GetInfo()
	return {
		name      = "Violet Rampart Texture Generator",
		desc      = "Generates Violet Rampart textures",
		author    = "Rafal[ZK], based on code from GoogleFrog",
		date      = "July 2021",
		license   = "GNU GPL, v2 or later",
		layer     = 10,
		enabled   = true, --  loaded by default?
	}
end

if (gadgetHandler:IsSyncedCode()) then
	return false
end

--------------------------------------------------------------------------------
-- Unsynced
--------------------------------------------------------------------------------

if (not gl.RenderToTexture) then -- super bad graphic driver
	Spring.Echo("gl.RenderToTexture() function missing! Shutting down.")
	return false
end

local DEBUG = true

local spSetMapSquareTexture = Spring.SetMapSquareTexture

local glTexture         = gl.Texture
local glColor           = gl.Color
local glCreateTexture   = gl.CreateTexture
local glRenderToTexture = gl.RenderToTexture
local glDeleteTexture   = gl.DeleteTexture
local glTexRect         = gl.TexRect
local glRect            = gl.Rect

local max   = math.max
local floor = math.floor

local MAP_X = Game.mapSizeX
local MAP_Z = Game.mapSizeZ
local MAP_FAC_X = 2 / MAP_X
local MAP_FAC_Z = 2 / MAP_Z

local SQUARE_SIZE = 1024
--local SQUARES_X = MAP_X / SQUARE_SIZE
--local SQUARES_Z = MAP_Z / SQUARE_SIZE

local BLOCK_SIZE  = 8
local DRAW_OFFSET_X = 2 * BLOCK_SIZE/MAP_X - 1
local DRAW_OFFSET_Z = 2 * BLOCK_SIZE/MAP_Z - 1

local SQUARE_TEX_SIZE = SQUARE_SIZE/BLOCK_SIZE

local USE_SHADING_TEXTURE = (Spring.GetConfigInt("AdvMapShading") == 1)

--------------------------------------------------------------------------------

local texturePath = 'bitmaps/map/'
local texturePool = {
	[1] = {
		path = texturePath .. 'rock.png'
	},
	[2] = {
		path = texturePath .. 'crystal.png'
	}
	--[1] = "", -- extracted from map
	--[2] = "", -- extracted from map
}

local BOTTOM_TERRAIN_TYPE       = 0
local RAMPART_TERRAIN_TYPE      = 1
local RAMPART_WALL_TERRAIN_TYPE = 2

local mainTexByType = {
	[RAMPART_TERRAIN_TYPE]      = 1,
	[RAMPART_WALL_TERRAIN_TYPE] = 2,
	--[BOTTOM_TERRAIN_TYPE]       = 3,
}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local startedInitializingTextures = false
local initializedTextures = false
local startedGeneratingTextures = false
local visibleTexturesGenerated = false
local visibleTexturesGeneratedAndGroundDetailSet = false
local allWorkFinished = false
local setGroundDetail = false
local prevGroundDetail = false
local gameStarted = false

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local coroutine = coroutine
local coroutine_yield = coroutine.yield
local activeCoroutine

local function StartScript(fn)
	activeCoroutine = coroutine.create(fn)
end

local function Sleep()
	if (not gameStarted) then -- need to finish fast on game start
		coroutine_yield()
	end
end

local function UpdateCoroutines()
	if activeCoroutine then
		if coroutine.status(activeCoroutine) ~= "dead" then
			assert(coroutine.resume(activeCoroutine))
		else
			activeCoroutine = nil
		end
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function createFboTexture(sizeX, sizeY)
    return glCreateTexture(sizeX, sizeY, {
		border = false,
		min_filter = GL.LINEAR,
		mag_filter = GL.LINEAR,
		wrap_s = GL.CLAMP_TO_EDGE,
		wrap_t = GL.CLAMP_TO_EDGE,
		fbo = true
	})
end

local function DrawTextureOnSquare(x, z, srcX, srcZ)
	local x1 = 2*x/SQUARE_SIZE - 1
	local z1 = 2*z/SQUARE_SIZE - 1
	local x2 = 2*(x + SQUARE_SIZE)/SQUARE_SIZE - 1
	local z2 = 2*(z + SQUARE_SIZE)/SQUARE_SIZE - 1
	local srcSizeX = SQUARE_SIZE / MAP_X
	local srcSizeZ = SQUARE_SIZE / MAP_Z
	glTexRect(x1, z1, x2, z2, srcX, srcZ, srcX + srcSizeX, srcZ + srcSizeZ)
end

local function DrawTextureBlock(x, z)
	glTexRect(x*MAP_FAC_X - 1, z*MAP_FAC_Z - 1, x*MAP_FAC_X + DRAW_OFFSET_X, z*MAP_FAC_Z + DRAW_OFFSET_Z)
end

--[[
local function DrawColorBlock(x, z)
	glRect(x*MAP_FAC_X -1, z*MAP_FAC_Z - 1, x*MAP_FAC_X + DRAW_OFFSET_X, z*MAP_FAC_Z + DRAW_OFFSET_Z)
end
--]]

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
	
	gl.DeleteTextureFBO(squareTexture)
	glDeleteTexture(squareTexture)

	return {
		path   = extractedTexture,
		width  = sizeX,
		height = sizeY,		
		maxBlocksY = max(1, floor(sizeY / BLOCK_SIZE))
	}
end

local function ExtractTexturesFromMap()
	--texturePool[1] = ExtractTextureFromPosition(4040, 6160, BLOCK_SIZE, BLOCK_SIZE) --512 -- rampart
	--texturePool[2] = ExtractTextureFromPosition(3880, 6160, BLOCK_SIZE, BLOCK_SIZE) --512 -- wall

	--glRenderToTexture(texturePool[1].path, gl.SaveImage, 0, 0, BLOCK_SIZE, 512, "rock.png")
	--glRenderToTexture(texturePool[2].path, gl.SaveImage, 0, 0, BLOCK_SIZE, 512, "crystal.png")
end

local function InitTexturePool()
	--ExtractTexturesFromMap()

	for i = 1, #texturePool do
		local texture = texturePool[i]

		if (not texture.height) then
			local texInfo = gl.TextureInfo(texture.path)
			texture.width  = texInfo.xsize
			texture.height = texInfo.ysize
			texture.maxBlocksY = max(1, floor(texture.height / BLOCK_SIZE))
		end
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function InitializeBlocksTextures()
	local startTime = Spring.GetTimer()
	local mapTexX, mapTexZ = {}, {}

	for tex = 1, #texturePool do
		mapTexX[tex] = {}
		mapTexZ[tex] = {}
	end

	local mapgen_typeMap = SYNCED.mapgen_typeMap
	if not mapgen_typeMap then
		Spring.Echo("mapgen_typeMap not set")
		return mapTexX, mapTexZ
	end
	
	for x = 0, MAP_X - 1, BLOCK_SIZE do
		local mapgen_typeMapX = mapgen_typeMap[x]
		for z = 0, MAP_Z - 1, BLOCK_SIZE do
			local terrainType = mapgen_typeMapX[z]

			if (terrainType ~= BOTTOM_TERRAIN_TYPE) then			
				local tex = mainTexByType[terrainType]
				
				local index = #mapTexX[tex] + 1
				mapTexX[tex][index] = x
				mapTexZ[tex][index] = z
			end
		end
	end

	local currentTime = Spring.GetTimer()
	Spring.Echo("Map analyzed for blocks textures in: " .. Spring.DiffTimers(currentTime, startTime, true))

	initializedTextures = true
	
	return mapTexX, mapTexZ
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local RATE_LIMIT = 1000000 --12000

local function RateCheckWithTexture(loopCount, texture)
	if loopCount > RATE_LIMIT then
		loopCount = 0
		Spring.ClearWatchDogTimer()
		Sleep()
		glTexture(texture)
	end
	return loopCount + 1
end

local function DrawAllBlocksOnFullTexture(mapTexX, mapTexZ, fullTex)
	local startTime = Spring.GetTimer()
	local loopCount = 0

	glColor(1, 1, 1, 1)
	
	for i = 1, #texturePool do
		local texX = mapTexX[i]
		local texZ = mapTexZ[i]

		Spring.Echo(#texX .. " blocks to be drawn with texture #" .. i)

		local curTexture = texturePool[i].path
		glTexture(curTexture)

		for j = 1, #texX do
			glRenderToTexture(fullTex, DrawTextureBlock, texX[j], texZ[j])
			--loopCount = RateCheckWithTexture(loopCount, curTexture)
		end

		glTexture(false)

		Spring.ClearWatchDogTimer()
		--Sleep()
	end
	
	local currentTime = Spring.GetTimer()
	Spring.Echo("FullTex rendered in: " .. Spring.DiffTimers(currentTime, startTime, true))
end

local function RenderAllVisibleSquareTextures(fullTex)
	Spring.Echo("Starting to render SquareTextures")
	local startTime = Spring.GetTimer()

	for x = 0, MAP_X - 1, SQUARE_SIZE do -- Create square textures for each square
		local sx = floor(x / SQUARE_SIZE)

		for z = 0, MAP_Z - 1, SQUARE_SIZE do
			local sz = floor(z / SQUARE_SIZE)

			local squareTex = createFboTexture(SQUARE_TEX_SIZE, SQUARE_TEX_SIZE)
			--local squareTex = createFboTexture(SQUARE_SIZE, SQUARE_SIZE)

			glTexture(fullTex)
			glRenderToTexture(squareTex, DrawTextureOnSquare, 0, 0, x/MAP_X, z/MAP_Z)
			glTexture(false)

			gl.GenerateMipmap(squareTex)
			Spring.SetMapSquareTexture(sx, sz, squareTex)

			Spring.ClearWatchDogTimer()
		end
	end

	local currentTime = Spring.GetTimer()
	Spring.Echo("All SquareTextures created, rendered and applied in: " .. Spring.DiffTimers(currentTime, startTime, true))
end

local function RenderGGSquareTextures(fullTex)
	Spring.Echo("Starting to create GG.mapgen SquareTextures")
	local startTime = Spring.GetTimer()

	GG.mapgen_squareTexture  = {}
	GG.mapgen_currentTexture = {}

	for x = 0, MAP_X - 1, SQUARE_SIZE do -- Create square textures for each square
		local sx = floor(x / SQUARE_SIZE)
		GG.mapgen_squareTexture [sx] = {}
		GG.mapgen_currentTexture[sx] = {}

		for z = 0, MAP_Z - 1, SQUARE_SIZE do
			local sz = floor(z / SQUARE_SIZE)

			local origTex = createFboTexture(SQUARE_TEX_SIZE, SQUARE_TEX_SIZE)
			--local origTex = createFboTexture(SQUARE_SIZE, SQUARE_SIZE)
			local curTex  = createFboTexture(SQUARE_SIZE, SQUARE_SIZE)
			
			glTexture(fullTex)
			glRenderToTexture(origTex, DrawTextureOnSquare, 0, 0, x/MAP_X, z/MAP_Z)
			glRenderToTexture(curTex , DrawTextureOnSquare, 0, 0, x/MAP_X, z/MAP_Z)
			
			GG.mapgen_squareTexture [sx][sz] = origTex
			GG.mapgen_currentTexture[sx][sz] = curTex

			Spring.ClearWatchDogTimer()
			Sleep()
		end
	end

	glTexture(false)

	local currentTime = Spring.GetTimer()
	Spring.Echo("All GG.mapgen SquareTextures created and rendered in: " .. Spring.DiffTimers(currentTime, startTime, true))
end

local function RenderMinimap(fullTex)
	local fullTexUsedAsMinimap = false

	if USE_SHADING_TEXTURE then
		local startTime = Spring.GetTimer()

		Spring.SetMapShadingTexture("$minimap", fullTex)
		fullTexUsedAsMinimap = true
	
		Spring.ClearWatchDogTimer()

		local currentTime = Spring.GetTimer()
		Spring.Echo("Applied minimap texture in: " .. Spring.DiffTimers(currentTime, startTime, true))
	end

	return fullTexUsedAsMinimap
end

local function GenerateMapTexture(mapTexX, mapTexZ)
	local DrawStart = Spring.GetTimer()
	local startTime = Spring.GetTimer()

	local fullTex = createFboTexture(MAP_X/BLOCK_SIZE, MAP_Z/BLOCK_SIZE)
	if not fullTex then
		return
	end

	local currentTime = Spring.GetTimer()
	Spring.Echo("Generated blank fullTex in: " .. Spring.DiffTimers(currentTime, startTime, true))
	
	local function DrawLoop()
		DrawAllBlocksOnFullTexture(mapTexX, mapTexZ, fullTex)
		RenderAllVisibleSquareTextures(fullTex)
		local fullTexUsedAsMinimap = RenderMinimap(fullTex)

		local DrawEnd = Spring.GetTimer()
		Spring.Echo("Visible map texture generation finished - total time: " .. Spring.DiffTimers(DrawEnd, DrawStart, true))
		if DEBUG then
			Spring.MarkerAddPoint(0, 0, 0, "Visible map texture generation finished", true)
		end
		
		visibleTexturesGenerated = true  -- finished processing of visible textures
		setGroundDetail = true
		Sleep()

		-- invisible part

		RenderGGSquareTextures(fullTex)

		gl.DeleteTextureFBO(fullTex)
		if fullTex and (not fullTexUsedAsMinimap) then
			glDeleteTexture(fullTex)
			fullTex = nil
		end

		local ProcessingEnd = Spring.GetTimer()
		Spring.Echo("Processing finished - total time: " .. Spring.DiffTimers(ProcessingEnd, DrawStart, true))
		if DEBUG then
			Spring.MarkerAddPoint(0, 0, 0, "Processing finished", true)
		end
		
		allWorkFinished = true
	end

	StartScript(DrawLoop)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local mapTexX
local mapTexZ

local updateCount = 0

function gadget:Update(n)
	if setGroundDetail then		
		prevGroundDetail = Spring.GetConfigInt("GroundDetail", 90) -- Default in epic menu
		Spring.Echo("GroundDetail: " .. prevGroundDetail)
		Spring.SendCommands{"GroundDetail " .. math.max(200, prevGroundDetail + 1)}

		setGroundDetail = false
		visibleTexturesGeneratedAndGroundDetailSet = visibleTexturesGenerated and true
	end

	if startedInitializingTextures then
		return
	end

	updateCount = updateCount + 1

	if updateCount >= 3 then  -- skip Update 1 and 2 until things are loaded
		startedInitializingTextures = true

		InitTexturePool()
		mapTexX, mapTexZ = InitializeBlocksTextures()
	end
end

function gadget:DrawGenesis()
	if not initializedTextures then
		return
	end
	if allWorkFinished then
		gadgetHandler:RemoveGadget()
		return
	end
	
	if not activeCoroutine then
		if startedGeneratingTextures then
			return
		end
		
		startedGeneratingTextures = true
		GenerateMapTexture(mapTexX, mapTexZ)
	else
		UpdateCoroutines()
	end
end

function gadget:MousePress(x, y, button)
	return (button == 1) and (not visibleTexturesGeneratedAndGroundDetailSet)
end

function gadget:GameStart()
	gameStarted = true -- finish all processing in next Draw call
end

function gadget:Shutdown()
	if prevGroundDetail then
		Spring.SendCommands{"GroundDetail " .. prevGroundDetail}
		prevGroundDetail = false
	end
end
