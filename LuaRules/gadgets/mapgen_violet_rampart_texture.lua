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

local min   = math.min
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

local INTENSE_MIN_WORKING_TIME = 50 -- in milliseconds
local BACKGROUND_MIN_WORKING_TIME = 30 -- in milliseconds
local MIN_WORKING_TIME = INTENSE_MIN_WORKING_TIME
local MIN_ANALYZED_COLUMMS_BEFORE_TIME_CHECK = 50 -- about 5-30ms each
local MIN_BLOCKS_BEFORE_TIME_CHECK = 2000 -- about 10ms each

local activeCoroutine
local isSleeping
local lastResumeTime

local function StartScript(fn)
	activeCoroutine = coroutine.create(fn)
end

local function UpdateCoroutines()
	if activeCoroutine then
		if coroutine.status(activeCoroutine) ~= "dead" then
			if (not isSleeping) then
				lastResumeTime = Spring.GetTimer()
			end

			assert(coroutine.resume(activeCoroutine))
		else
			activeCoroutine = nil
		end
	end
end

local function Sleep()
	if (not gameStarted) then -- need to finish fast on game start
		lastResumeTime = nil
		isSleeping = true
		coroutine_yield()
		isSleeping = false
		lastResumeTime = Spring.GetTimer()
	end
end

local function CheckTimeAndSleep()
	local currentTime = Spring.GetTimer()
	local timeDiff = Spring.DiffTimers(currentTime, lastResumeTime, true)
	--Spring.Echo(timeDiff)

	if timeDiff >= MIN_WORKING_TIME then
		Spring.ClearWatchDogTimer()
		Sleep()
	end
end

local function CheckTimeAndSleepWithTexture(texture)
	local currentTime = Spring.GetTimer()
	local timeDiff = Spring.DiffTimers(currentTime, lastResumeTime, true)
	--Spring.Echo(timeDiff)

	if timeDiff >= MIN_WORKING_TIME then
		Spring.ClearWatchDogTimer()

		glTexture(false)
		Sleep()
		glTexture(texture)
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

local function AddDebugMarker(text)
	if DEBUG then
		Spring.MarkerAddPoint(MAP_X / 2, 0, MAP_Z / 2 + (debugMarkerOffset or 0), text, true)
		debugMarkerOffset = (debugMarkerOffset or 0) + 80
	end
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
	Spring.Echo("Starting analyze map for blocks textures")
	local startTime = Spring.GetTimer()

	local mapTexX = {}
	local mapTexZ = {}
	for tex = 1, #texturePool do
		mapTexX[tex] = {}
		mapTexZ[tex] = {}
	end

	local mapgen_typeMap = SYNCED.mapgen_typeMap
	if not mapgen_typeMap then
		Spring.Echo("mapgen_typeMap not set")
		return mapTexX, mapTexZ
	end
	
	local function AnalyzeLoop()
		Spring.Echo("Starting analyze loop")

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

			if ((x / BLOCK_SIZE) % MIN_ANALYZED_COLUMMS_BEFORE_TIME_CHECK == 0) then
				CheckTimeAndSleep()
			end
		end

		local currentTime = Spring.GetTimer()
		Spring.Echo("Map analyzed for blocks textures in: " .. Spring.DiffTimers(currentTime, startTime, true))
		AddDebugMarker("Map analyzed")

		initializedTextures = true	
	end

	StartScript(AnalyzeLoop)
	
	return mapTexX, mapTexZ
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function DrawAllBlocksOnFullTexture(mapTexX, mapTexZ, fullTex)
	local startTime = Spring.GetTimer()

	glColor(1, 1, 1, 1)
	
	for i = 1, #texturePool do
		local texX = mapTexX[i]
		local texZ = mapTexZ[i]
		local numBlocks = #texX

		Spring.Echo(numBlocks .. " blocks to be drawn with texture #" .. i)

		local curTexture = texturePool[i].path
		glTexture(curTexture)

		local j = 1
		while j <= numBlocks do
			local loopEnd = min(j + MIN_BLOCKS_BEFORE_TIME_CHECK - 1, numBlocks)

			while j <= loopEnd do
				glRenderToTexture(fullTex, DrawTextureBlock, texX[j], texZ[j])
				j = j + 1
			end

			CheckTimeAndSleepWithTexture(curTexture)
		end

		glTexture(false)
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

			CheckTimeAndSleep()
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

	glTexture(fullTex)

	for x = 0, MAP_X - 1, SQUARE_SIZE do -- Create square textures for each square
		local sx = floor(x / SQUARE_SIZE)
		GG.mapgen_squareTexture [sx] = {}
		GG.mapgen_currentTexture[sx] = {}

		for z = 0, MAP_Z - 1, SQUARE_SIZE do
			local sz = floor(z / SQUARE_SIZE)

			local origTex = createFboTexture(SQUARE_TEX_SIZE, SQUARE_TEX_SIZE)
			--local origTex = createFboTexture(SQUARE_SIZE, SQUARE_SIZE)		
			glRenderToTexture(origTex, DrawTextureOnSquare, 0, 0, x/MAP_X, z/MAP_Z)
			GG.mapgen_squareTexture [sx][sz] = origTex

			CheckTimeAndSleepWithTexture(fullTex)

			local curTex  = createFboTexture(SQUARE_SIZE, SQUARE_SIZE)
			glRenderToTexture(curTex , DrawTextureOnSquare, 0, 0, x/MAP_X, z/MAP_Z)			
			GG.mapgen_currentTexture[sx][sz] = curTex

			CheckTimeAndSleepWithTexture(fullTex)
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

		local currentTime = Spring.GetTimer()
		Spring.Echo("Applied minimap texture in: " .. Spring.DiffTimers(currentTime, startTime, true))

		--CheckTimeAndSleep()
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
		AddDebugMarker("Visible map texture generation finished")
		
		visibleTexturesGenerated = true  -- finished processing of visible textures
		setGroundDetail = true

		Sleep()

		-- Background part
		MIN_WORKING_TIME = BACKGROUND_MIN_WORKING_TIME

		RenderGGSquareTextures(fullTex)

		gl.DeleteTextureFBO(fullTex)
		if fullTex and (not fullTexUsedAsMinimap) then
			glDeleteTexture(fullTex)
			fullTex = nil
		end

		local ProcessingEnd = Spring.GetTimer()
		Spring.Echo("Processing finished - total time: " .. Spring.DiffTimers(ProcessingEnd, DrawStart, true))		
		AddDebugMarker("Processing finished")
		
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
	if allWorkFinished then
		gadgetHandler:RemoveGadget()
		return
	end
	
	if activeCoroutine then
		UpdateCoroutines()
	else
		if initializedTextures and (not startedGeneratingTextures) then
			startedGeneratingTextures = true
			GenerateMapTexture(mapTexX, mapTexZ)
		end
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
