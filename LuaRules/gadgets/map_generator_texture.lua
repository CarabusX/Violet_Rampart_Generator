function gadget:GetInfo()
	return {
		name      = "Violet Rampart Texture Generator",
		desc      = "Generates Violet Rampart textures",
		author    = "Rafal[ZK], based on code from GoogleFrog",
		date      = "July 2021",
		license   = "GNU GPL, v2 or later",
		layer     = 1003, -- after ZK Minimap Start Boxes (because of minimap drawing)
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

local VRG_Config = VFS.Include("LuaRules/Configs/map_generator_config.lua")

local DEBUG_MARKERS = VRG_Config.DEBUG_MARKERS  -- enables debug map markers
local GENERATE_MINIMAP = VRG_Config.GENERATE_MINIMAP  -- generates and saves minimap

--------------------------------------------------------------------------------

local spGetTimer            = Spring.GetTimer
local spDiffTimers          = Spring.DiffTimers
local spClearWatchDogTimer  = Spring.ClearWatchDogTimer
local spSetMapSquareTexture = Spring.SetMapSquareTexture

local glPushMatrix       = gl.PushMatrix
local glPopMatrix        = gl.PopMatrix
local glLoadIdentity     = gl.LoadIdentity
local glTranslate        = gl.Translate
local glScale            = gl.Scale
local glCallList         = gl.CallList
local glColor            = gl.Color
local glTexture          = gl.Texture
local glCreateTexture    = gl.CreateTexture
local glRenderToTexture  = gl.RenderToTexture
local glGenerateMipmap   = gl.GenerateMipmap
local glDeleteTexture    = gl.DeleteTexture
local glDeleteTextureFBO = gl.DeleteTextureFBO
local glTexRect          = gl.TexRect
local glRect             = gl.Rect

local min   = math.min
local max   = math.max
local floor = math.floor
local round = math.round

local MAP_X = Game.mapSizeX
local MAP_Z = Game.mapSizeZ

local SQUARE_SIZE = 1024
local NUM_SQUARES_X = MAP_X / SQUARE_SIZE
local NUM_SQUARES_Z = MAP_Z / SQUARE_SIZE

local BLOCK_SIZE = 8
local BLOCKS_PER_SQUARE = SQUARE_SIZE / BLOCK_SIZE
local SQUARE_TEX_SIZE = SQUARE_SIZE / BLOCK_SIZE

local MINIMAP_SIZE_X = 1024
local MINIMAP_SIZE_Y = 1024

local DO_MIPMAPS = true

local DESIRED_GROUND_DETAIL = 200
local MAX_GROUND_DETAIL = 200 -- maximum value accepted by Spring

--------------------------------------------------------------------------------

function MultiplyColorRGB (color, multiplier)
	return {
		color[1] * multiplier,
		color[2] * multiplier,
		color[3] * multiplier,
		color[4]
	}
end

--------------------------------------------------------------------------------

--[[
local texturePath = 'bitmaps/map/'
local texturePool = {
	[1] = {
		path = texturePath .. 'rock.png'
	},
	[2] = {
		path = texturePath .. 'crystal.png'
	}
}
--]]

local ROCK_COLOR    = { 74/255, 59/255,  83/255, 1.0 }
local CRYSTAL_COLOR = { 90/255, 45/255, 174/255, 1.0 }

local colorPool = {
	[1] = MultiplyColorRGB(ROCK_COLOR   , 1.20),  -- { 89/255, 71/255, 100/255, 1.0 }
	[2] = MultiplyColorRGB(ROCK_COLOR   , 1.10),
	[3] = MultiplyColorRGB(CRYSTAL_COLOR, 1.00),
}

local BOTTOM_TERRAIN_TYPE       = 0
local RAMPART_TERRAIN_TYPE      = 1
local RAMPART_DARK_TERRAIN_TYPE = 2
local RAMPART_WALL_TERRAIN_TYPE = 3
local RAMPART_WALL_OUTER_TYPE   = 4

local INITIAL_COLOR_INDEX = 1

local mainTexByTerrainType = {
	[RAMPART_TERRAIN_TYPE]      = 1,
	[RAMPART_DARK_TERRAIN_TYPE] = 2,
	[RAMPART_WALL_TERRAIN_TYPE] = 3,
	[RAMPART_WALL_OUTER_TYPE]   = 3,
	[BOTTOM_TERRAIN_TYPE]       = 1,
}

-- (for minimap generation)
if (GENERATE_MINIMAP) then
	colorPool[0] = { 0.0, 0.0, 0.0, 1.0 }
	mainTexByTerrainType[BOTTOM_TERRAIN_TYPE] = 0
	INITIAL_COLOR_INDEX = 0
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local startedInitializingTextures = false
local initializedTextures = false
local initializedTexturesThisFrame = false
local startedGeneratingTextures = false
local visibleTexturesGenerated = false
local visibleTexturesGeneratedAndGroundDetailSet = false
local allWorkFinished = false
local setGroundDetail = false
local origGroundDetail = false
local gameStarted = false

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local coroutine = coroutine
local coroutine_yield = coroutine.yield

-- 50ms is highest value that doesn't cause disturbing cursor lag
-- 30ms is highest value that actually feels smooth
local INTENSE_MIN_WORKING_TIME    = 50 -- in milliseconds, in effect until visible textures are generated
local BACKGROUND_MIN_WORKING_TIME = 30 -- in milliseconds, in effect when remaining background tasks are worked on
local MIN_WORKING_TIME = INTENSE_MIN_WORKING_TIME
local MIN_ANALYZED_SQUARES_BEFORE_TIME_CHECK = 3 -- about 5-30ms between each check
local MIN_BLOCKS_BEFORE_TIME_CHECK = 40000 -- about 9ms between each check

local updateCoroutine = {}
local drawCoroutine = {}

local isSleeping = false
local lastResumeTime

local function ContinueCoroutine(coroutineData)
	if coroutineData.activeCoroutine then
		if (coroutine.status(coroutineData.activeCoroutine) ~= "dead") then
			spClearWatchDogTimer()

			if (not isSleeping) then  -- otherwise Sleep() sets it later
				lastResumeTime = spGetTimer()
			end

			assert(coroutine.resume(coroutineData.activeCoroutine))
		else
			coroutineData.activeCoroutine = nil
			lastResumeTime = nil  -- it is finished coroutine, so it was not reset in Sleep()
		end
	end
end

local function StartScript(func)
	local coroutineData = {
		activeCoroutine = coroutine.create(func)
	}

	ContinueCoroutine(coroutineData)

	return coroutineData
end

local function Sleep()
	spClearWatchDogTimer()

	if (gameStarted) then -- need to finish work quickly when game started
		return
	end

	lastResumeTime = nil
	isSleeping = true
	coroutine_yield()
	isSleeping = false
	lastResumeTime = spGetTimer() -- done as late as possible before returning back to code execution
end

local function CheckTimeAndSleep()
	if (gameStarted) then -- need to finish work quickly when game started
		spClearWatchDogTimer()
		return
	end

	local currentTime = spGetTimer()
	local timeDiff = spDiffTimers(currentTime, lastResumeTime, true)
	--Spring.Echo("Time since resume: " .. timeDiff)

	if (timeDiff >= MIN_WORKING_TIME) then
		--Spring.Echo("Time since resume: " .. timeDiff)
		Sleep()
		--Spring.Echo("Time in sleep: " .. spDiffTimers(lastResumeTime, currentTime, true))
	end
end

local function CheckTimeAndSleepWithColor(color)
	if (gameStarted) then -- need to finish work quickly when game started
		spClearWatchDogTimer()
		return
	end

	local currentTime = spGetTimer()
	local timeDiff = spDiffTimers(currentTime, lastResumeTime, true)
	--Spring.Echo("Time since resume: " .. timeDiff)

	if (timeDiff >= MIN_WORKING_TIME) then
		glColor(1, 1, 1, 1)
		--Spring.Echo("Time since resume: " .. timeDiff)
		Sleep()
		--Spring.Echo("Time in sleep: " .. spDiffTimers(lastResumeTime, currentTime, true))
		glColor(color)
	end
end

local function CheckTimeAndSleepWithTexture(texture)
	if (gameStarted) then -- need to finish work quickly when game started
		spClearWatchDogTimer()
		return
	end

	local currentTime = spGetTimer()
	local timeDiff = spDiffTimers(currentTime, lastResumeTime, true)
	--Spring.Echo("Time since resume: " .. timeDiff)

	if (timeDiff >= MIN_WORKING_TIME) then
		glTexture(false)
		--Spring.Echo("Time since resume: " .. timeDiff)
		Sleep()
		--Spring.Echo("Time in sleep: " .. spDiffTimers(lastResumeTime, currentTime, true))
		glColor(1, 1, 1, 1)
		glTexture(texture)
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function createFboTexture(sizeX, sizeY, withMapMaps)
    return glCreateTexture(sizeX, sizeY, {
		border = false,
		min_filter = (withMapMaps and GL.LINEAR_MIPMAP_LINEAR) or GL.LINEAR,
		mag_filter = GL.LINEAR,
		wrap_s = GL.CLAMP_TO_EDGE,
		wrap_t = GL.CLAMP_TO_EDGE,
		fbo = true
	})
end

local DRAW_SCALE_X = BLOCK_SIZE * (2 / MAP_X)
local DRAW_SCALE_Z = BLOCK_SIZE * (2 / MAP_Z)
local DRAW_OFFSET_X1 = DRAW_SCALE_X + 1
local DRAW_OFFSET_Z1 = DRAW_SCALE_Z + 1

local function DrawColorBlock(x, z)
	glRect(x * DRAW_SCALE_X - DRAW_OFFSET_X1, z * DRAW_SCALE_Z - DRAW_OFFSET_Z1, x * DRAW_SCALE_X - 1, z * DRAW_SCALE_Z - 1)
end

--[[
local function DrawTextureBlock(x, z)
	glTexRect(x * DRAW_SCALE_X - DRAW_OFFSET_X1, z * DRAW_SCALE_Z - DRAW_OFFSET_Z1, x * DRAW_SCALE_X - 1, z * DRAW_SCALE_Z - 1)
	--glTexRect(x * DRAW_SCALE_X - DRAW_OFFSET_X1, z * DRAW_SCALE_Z - DRAW_OFFSET_Z1, x * DRAW_SCALE_X - 1, z * DRAW_SCALE_Z - 1, 0, 0, 1.0, 8 / 512)
end
--]]

local SQUARE_DRAW_SCALE = 2 / SQUARE_SIZE
local SRC_SQUARE_SIZE_X = SQUARE_SIZE / MAP_X
local SRC_SQUARE_SIZE_Z = SQUARE_SIZE / MAP_Z

local function DrawFullTextureOnSquare(x, z, srcX, srcZ)
	local x1 = x * SQUARE_DRAW_SCALE - 1
	local z1 = z * SQUARE_DRAW_SCALE - 1
	local x2 = (x + SQUARE_SIZE) * SQUARE_DRAW_SCALE - 1
	local z2 = (z + SQUARE_SIZE) * SQUARE_DRAW_SCALE - 1
	glTexRect(x1, z1, x2, z2, srcX, srcZ, srcX + SRC_SQUARE_SIZE_X, srcZ + SRC_SQUARE_SIZE_Z)
end

--------------------------------------------------------------------------------

local function PrintTimeSpent(message, startTime)
	local currentTime = spGetTimer()
	Spring.Echo(message .. string.format("%.0f", round(spDiffTimers(currentTime, startTime, true))) .. "ms")
end

local function AddDebugMarker(text)
	if DEBUG_MARKERS then
		Spring.MarkerAddPoint(MAP_X / 2, 0, MAP_Z / 2 + (debugMarkerOffset or 0), text, true)
		debugMarkerOffset = (debugMarkerOffset or 0) + 80
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--[[
local function InitTexturePool()
	for i = 1, #texturePool do
		local texture = texturePool[i]

		if (not texture.height) then
			local texInfo = gl.TextureInfo(texture.path)
			texture.width  = texInfo.xsize
			texture.height = texInfo.ysize
		end

		--texture.maxBlocksY = max(1, floor(texture.height / BLOCK_SIZE))
	end
end
--]]

--------------------------------------------------------------------------------

local function LoadModifiedTypeMapSquares()
	local startTime = spGetTimer()

	local mapgen_modifiedTypeMapSquares = SYNCED.mapgen_modifiedTypeMapSquares

	if (not mapgen_modifiedTypeMapSquares) then
		Spring.Echo("Error: SYNCED.mapgen_modifiedTypeMapSquares is not set!")
		return
	end

	PrintTimeSpent("SYNCED.mapgen_modifiedTypeMapSquares loaded in: ", startTime)

	--CheckTimeAndSleep()  -- not inside coroutine

	return mapgen_modifiedTypeMapSquares
end

local function LoadTerrainTypeMap()
	local startTime = spGetTimer()

	local mapgen_typeMap = SYNCED.mapgen_typeMap

	if (not mapgen_typeMap) then
		Spring.Echo("Error: SYNCED.mapgen_typeMap is not set!")
		return
	end

	PrintTimeSpent("SYNCED.mapgen_typeMap loaded in: ", startTime)

	CheckTimeAndSleep()

	return mapgen_typeMap
end

local function mapSquareIndexToTypeMapIndexRange (sx)
	local x1 = (sx - 1) * BLOCKS_PER_SQUARE + 1
	local x2 = sx * BLOCKS_PER_SQUARE
	return x1, x2
end

local function ProcessBlocksInModifiedTypeMapSquares (modifiedTypeMapSquares, func)
	for sx = 1, NUM_SQUARES_X do
		local modifiedTypeMapSquaresX = modifiedTypeMapSquares[sx]
		local x1, x2 = mapSquareIndexToTypeMapIndexRange(sx)

		for sz = 1, NUM_SQUARES_Z do
			if (modifiedTypeMapSquaresX[sz] == 1) then
				local z1, z2 = mapSquareIndexToTypeMapIndexRange(sz)

				func(x1, x2, z1, z2)
			end
		end
	end
end

local function AnalyzeTerrainTypeMap(terrainTypeMap, modifiedTypeMapSquares, mapTexX, mapTexZ)
	local startTime = spGetTimer()

	ProcessBlocksInModifiedTypeMapSquares(modifiedTypeMapSquares,
	function (x1, x2, z1, z2)
		for x = x1, x2 do
			local terrainTypeMapX = terrainTypeMap[x]

			for z = z1, z2 do
				local terrainType = terrainTypeMapX[z]
				local tex = mainTexByTerrainType[terrainType]

				if (tex ~= INITIAL_COLOR_INDEX) then
					local index = #mapTexX[tex] + 1
					mapTexX[tex][index] = x
					mapTexZ[tex][index] = z
				end
			end
		end

		--if (sz % MIN_ANALYZED_SQUARES_BEFORE_TIME_CHECK == 0) then
			CheckTimeAndSleep()
		--end
	end)

	PrintTimeSpent("Map analyzed for blocks textures in: ", startTime)
end

local function InitializeBlocksTextures(modifiedTypeMapSquares)
	Spring.Echo("Starting analyze map for blocks textures")
	local AnalyzeStart = spGetTimer()

	local mapTexX = {}
	local mapTexZ = {}
	for tex = 1, #colorPool do
		mapTexX[tex] = {}
		mapTexZ[tex] = {}
	end

	local function AnalyzeLoop()
		--Spring.Echo("Starting analyze loop")

		local terrainTypeMap = LoadTerrainTypeMap()
		if (not terrainTypeMap) or (not modifiedTypeMapSquares) then
			return
		end

		AnalyzeTerrainTypeMap(terrainTypeMap, modifiedTypeMapSquares, mapTexX, mapTexZ)

		PrintTimeSpent("Map analysis for blocks textures finished - total time: ", AnalyzeStart)
		AddDebugMarker("Map analyzed")

		initializedTextures = true
		initializedTexturesThisFrame = true
	end

	updateCoroutine = StartScript(AnalyzeLoop)

	return mapTexX, mapTexZ
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local tempMinimapBackgroundColor = colorPool[INITIAL_COLOR_INDEX]

local tempMinimapFontColor = { 1.0, 1.0, 1.0, 1.0 }
local tempMinimapFontPath  = "fonts/FreeSansBold.otf"
local tempMinimapFontSize  = 65
local tempMinimapText      = { "Loading texture...", "Please wait..." }

local tempMinimapTexture = false
local tempMinimapFont = false
local tempMinimapDisplayList = false

local function CreateAndApplyTempMinimapTexture()
	local tempTexture = createFboTexture(MINIMAP_SIZE_X, MINIMAP_SIZE_Y, false)
	if not tempTexture then
		Spring.Echo("Error: Failed to create tempMinimapTexture!")
		return
	end

	glRenderToTexture(tempTexture, function()
		glColor(tempMinimapBackgroundColor)
		glRect(-1, -1, 1, 1)
		glColor(1, 1, 1, 1)
	end)

	if (GG.DrawBaseSymbolsApi and GG.DrawBaseSymbolsApi.DrawBaseSymbolsOnTexture) then
		GG.DrawBaseSymbolsApi.DrawBaseSymbolsOnTexture(tempTexture)
	end

	Spring.SetMapShadingTexture("$minimap", tempTexture)

	return tempTexture
end

local function DrawTempMinimapLabel(tempMinimapFont)
	local function drawCenteredText(x, y, text)
		local textHeight, textDescender = tempMinimapFont:GetTextHeight(text)
		local textScale    = 1.0 / MINIMAP_SIZE_Y
		local textSizeMult = 1.0 / textHeight

		glPushMatrix()
			glTranslate(0.5, 0.5, 0) -- center of minimap
			glScale(textScale, textScale, 1)
			glTranslate(x, y, 0)
			glScale(textSizeMult, -textSizeMult, 1)
			tempMinimapFont:Print(text, 0, 0, tempMinimapFontSize, "cvo")
		glPopMatrix()
	end

	gl.DepthTest(false)

	glColor(tempMinimapFontColor)
	drawCenteredText(0, -60, tempMinimapText[1])
	drawCenteredText(0,  60, tempMinimapText[2])
	glColor(1, 1, 1, 1)
end

local function InitializeTempMinimapTexture()
	Spring.Echo("Starting to create temporary minimap texture")
	local startTime = spGetTimer()

	local tempMinimapTexture = CreateAndApplyTempMinimapTexture()
	if (not tempMinimapTexture) then
		return
	end

	PrintTimeSpent("Temporary minimap texture created, rendered and applied in: ", startTime)

	return tempMinimapTexture
end

local function InitializeTempMinimapLabel()
	Spring.Echo("Starting to create temporary minimap label")
	local startTime = spGetTimer()

	local tempMinimapFont = gl.LoadFont(tempMinimapFontPath, tempMinimapFontSize, 10, 10)
	local tempMinimapDisplayList = gl.CreateList(DrawTempMinimapLabel, tempMinimapFont)

	PrintTimeSpent("Temporary minimap label created in: ", startTime)

	return tempMinimapFont, tempMinimapDisplayList
end

local function DeleteTempMinimapTexture()
	if (tempMinimapDisplayList) then
		gl.DeleteList(tempMinimapDisplayList)
		tempMinimapDisplayList = false
	end

	if (tempMinimapFont) then
		gl.DeleteFont(tempMinimapFont)
		tempMinimapFont = false
	end

	if (tempMinimapTexture) then
		glDeleteTextureFBO(tempMinimapTexture)
		glDeleteTexture(tempMinimapTexture)
		tempMinimapTexture = false
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function CreateFullTexture()
	local startTime = spGetTimer()

	local fullTex = createFboTexture(MAP_X / BLOCK_SIZE, MAP_Z / BLOCK_SIZE, false)

	if (not fullTex) then
		Spring.Echo("Error: Failed to generate fullTex!")
		return
	end

	local fillColor = colorPool[INITIAL_COLOR_INDEX]

	local pixelSizeX = 2 / (MAP_X / BLOCK_SIZE)
	local pixelSizeY = 2 / (MAP_Z / BLOCK_SIZE)

	glRenderToTexture(fullTex, function()
		glColor(fillColor)
		glRect(-1, -1, 1, 1)

		glColor(0, 0, 0, 1)  -- black border
		glRect(-1, -1, -1 + pixelSizeX,  1)  -- left border
		glRect( 1 - pixelSizeX, -1,  1,  1)  -- right border
		glRect(-1, -1,  1, -1 + pixelSizeY)  -- top border
		glRect(-1,  1 - pixelSizeY,  1,  1)  -- bottom border

		glColor(1, 1, 1, 1)
	end)

	PrintTimeSpent("Generated blank fullTex in: ", startTime)

	return fullTex
end

local function DrawBlocksColorsOnFullTexture(mapTexX, mapTexZ, fullTex)
	local startTime = spGetTimer()

	for i = 1, #colorPool do
		local texX = mapTexX[i]
		local texZ = mapTexZ[i]
		local numBlocks = #texX

		Spring.Echo(numBlocks .. " blocks to be drawn with color #" .. i)

		local curColor = colorPool[i]
		glColor(curColor)

		local j = 1
		while j <= numBlocks do
			local loopEnd = min(j + MIN_BLOCKS_BEFORE_TIME_CHECK - 1, numBlocks)

			glRenderToTexture(fullTex, function()
				while j <= loopEnd do
					DrawColorBlock(texX[j], texZ[j])
					j = j + 1
				end
			end)

			CheckTimeAndSleepWithColor(curColor)
		end
	end

	glColor(1, 1, 1, 1)
	
	PrintTimeSpent("Blocks rendered to fullTex in: ", startTime)
end

--[[
local function DrawBlocksTexturesOnFullTexture(mapTexX, mapTexZ, fullTex)
	local startTime = spGetTimer()

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

			glRenderToTexture(fullTex, function()
				while j <= loopEnd do
					DrawTextureBlock(texX[j], texZ[j])
					j = j + 1
				end
			end)

			CheckTimeAndSleepWithTexture(curTexture)
		end

		glTexture(false)
	end
	
	PrintTimeSpent("Blocks rendered to fullTex in: ", startTime)
end
--]]

local function RenderVisibleSquareTextures(fullTex, modifiedTypeMapSquares)
	Spring.Echo("Starting to render SquareTextures")
	local startTime = spGetTimer()

	local squareTextures = {}

	for sx = 1, NUM_SQUARES_X do
		local modifiedTypeMapSquaresX = modifiedTypeMapSquares[sx]
		squareTextures[sx] = {}

		for sz = 1, NUM_SQUARES_Z do
			if (modifiedTypeMapSquaresX[sz] == 1) then
				local squareTex = createFboTexture(SQUARE_TEX_SIZE, SQUARE_TEX_SIZE, DO_MIPMAPS)
				--local squareTex = createFboTexture(SQUARE_SIZE, SQUARE_SIZE, DO_MIPMAPS)

				glTexture(fullTex)
				glRenderToTexture(squareTex, DrawFullTextureOnSquare, 0, 0, (sx - 1) / NUM_SQUARES_X, (sz - 1) / NUM_SQUARES_Z)
				glTexture(false)

				if DO_MIPMAPS then
					glGenerateMipmap(squareTex)
				end

				squareTextures[sx][sz] = squareTex

				CheckTimeAndSleep()
			end
		end
	end

	PrintTimeSpent("All SquareTextures created and rendered in: ", startTime)

	return squareTextures
end

local function ApplyVisibleSquareTextures(squareTextures, modifiedTypeMapSquares)
	local startTime = spGetTimer()

	for sx = 1, NUM_SQUARES_X do
		local modifiedTypeMapSquaresX = modifiedTypeMapSquares[sx]

		for sz = 1, NUM_SQUARES_Z do
			if (modifiedTypeMapSquaresX[sz] == 1) then
				spSetMapSquareTexture(sx - 1, sz - 1, squareTextures[sx][sz])
			end
		end
	end

	PrintTimeSpent("All SquareTextures applied in: ", startTime)

	CheckTimeAndSleep()
end

local function RenderGGSquareTextures(fullTex, squareTextures, modifiedTypeMapSquares)
	Spring.Echo("Starting to create GG.mapgen SquareTextures")
	local startTime = spGetTimer()

	GG.mapgen_squareTexture  = {}
	GG.mapgen_currentTexture = {}

	glTexture(fullTex)

	for sx = 1, NUM_SQUARES_X do
		local modifiedTypeMapSquaresX = modifiedTypeMapSquares[sx]
		GG.mapgen_squareTexture [sx-1] = {}
		GG.mapgen_currentTexture[sx-1] = {}

		for sz = 1, NUM_SQUARES_Z do
			if (modifiedTypeMapSquaresX[sz] == 1) then
				local curTex  = createFboTexture(SQUARE_SIZE, SQUARE_SIZE, DO_MIPMAPS)
				spClearWatchDogTimer()  -- texture creation can take long because of memory allocation

				glRenderToTexture(curTex, DrawFullTextureOnSquare, 0, 0, (sx - 1) / NUM_SQUARES_X, (sz - 1) / NUM_SQUARES_Z)
				-- gl.GenerateMipmap(curTex) is done in terrain_texture_handler

				GG.mapgen_squareTexture [sx-1][sz-1] = squareTextures[sx][sz]
				GG.mapgen_currentTexture[sx-1][sz-1] = curTex

				CheckTimeAndSleepWithTexture(fullTex)
			end
		end
	end

	glTexture(false)

	PrintTimeSpent("All GG.mapgen SquareTextures created and rendered in: ", startTime)
end

local function RenderMinimap(fullTex)
	local startTime = spGetTimer()

	local minimapTexture = createFboTexture(MAP_X/BLOCK_SIZE, MAP_Z/BLOCK_SIZE, false)
	--local minimapTexture = createFboTexture(MINIMAP_SIZE_X, MINIMAP_SIZE_Y, false) -- produces more artefacts somehow

	glTexture(fullTex)
	glRenderToTexture(minimapTexture, function()
		glTexRect(-1, 1, 1, -1) -- flip Y
	end)
	glTexture(false)

	if (GG.DrawBaseSymbolsApi and GG.DrawBaseSymbolsApi.DrawBaseSymbolsOnTexture) then
		Spring.Echo("Drawing base symbols on minimap texture")
		GG.DrawBaseSymbolsApi.DrawBaseSymbolsOnTexture(minimapTexture)
	end

	Spring.SetMapShadingTexture("$minimap", minimapTexture)
	
	glDeleteTextureFBO(minimapTexture)

	PrintTimeSpent("Applied minimap texture in: ", startTime)

	--CheckTimeAndSleep() -- do not sleep because this is the last operation before setting visibleTexturesGenerated flag
end

local function GenerateMapTexture(mapTexX, mapTexZ, modifiedTypeMapSquares)
	Spring.Echo("Starting generate map texture")
	local DrawStart = spGetTimer()

	local function DrawLoop()
		--Spring.Echo("Starting draw loop")

		-- Visible part
		local fullTex = CreateFullTexture()
		if not fullTex then
			setGroundDetail = true
			allWorkFinished = true
			return
		end

		DrawBlocksColorsOnFullTexture(mapTexX, mapTexZ, fullTex)
		--DrawBlocksTexturesOnFullTexture(mapTexX, mapTexZ, fullTex)
		local squareTextures = RenderVisibleSquareTextures(fullTex, modifiedTypeMapSquares)
		ApplyVisibleSquareTextures(squareTextures, modifiedTypeMapSquares)
		--GG.Tools.SaveFullTexture(fullTex)
		if (GENERATE_MINIMAP) then
			GG.Tools.GenerateAllMinimapsWithLabel(fullTex)
		end
		RenderMinimap(fullTex)

		PrintTimeSpent("Visible map texture generation finished - total time: ", DrawStart)
		AddDebugMarker("Visible map texture generation finished")

		visibleTexturesGenerated = true  -- finished processing of visible textures
		setGroundDetail = true

		Sleep()

		-- Background part
		MIN_WORKING_TIME = BACKGROUND_MIN_WORKING_TIME

		DeleteTempMinimapTexture()
		RenderGGSquareTextures(fullTex, squareTextures, modifiedTypeMapSquares)

		glDeleteTextureFBO(fullTex)
		glDeleteTexture(fullTex)
		fullTex = nil
		squareTextures = nil

		mapTexX = nil
		mapTexZ = nil
		modifiedTypeMapSquares = nil

		PrintTimeSpent("Processing finished - total time: ", DrawStart)		
		AddDebugMarker("Processing finished")
		
		allWorkFinished = true
	end

	drawCoroutine = StartScript(DrawLoop)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local mapTexX
local mapTexZ
local modifiedTypeMapSquares

local updateCount = 0

function gadget:Update(n)
	if setGroundDetail then
		local prevGroundDetail = Spring.GetConfigInt("GroundDetail", 90) -- Default in epic menu
		local newGroundDetail = max(DESIRED_GROUND_DETAIL, prevGroundDetail)

		if (prevGroundDetail == MAX_GROUND_DETAIL) then
			Spring.SendCommands("GroundDetail " .. (MAX_GROUND_DETAIL - 1))
		elseif (newGroundDetail == prevGroundDetail) then
			Spring.SendCommands("GroundDetail " .. (newGroundDetail + 1))
		end
		Spring.SendCommands("GroundDetail " .. newGroundDetail)

		if (newGroundDetail ~= prevGroundDetail) then
			origGroundDetail = prevGroundDetail
		end

		setGroundDetail = false
		visibleTexturesGeneratedAndGroundDetailSet = visibleTexturesGenerated and true
	end

	--if allWorkFinished then
		--return
	--end
	if initializedTextures then
		return
	end

	updateCount = updateCount + 1

	if (updateCount >= 3) then  -- skip Update 1 and 2 until things are loaded
		if (updateCoroutine.activeCoroutine) then
			ContinueCoroutine(updateCoroutine)
		else
			if (not startedInitializingTextures) then
				startedInitializingTextures = true

				--InitTexturePool()
				modifiedTypeMapSquares = LoadModifiedTypeMapSquares()
				mapTexX, mapTexZ = InitializeBlocksTextures(modifiedTypeMapSquares)
			end
		end
	end
end

local drawCount = 0

function gadget:DrawGenesis()
	if allWorkFinished then
		--gadgetHandler:RemoveGadget()
		return
	end	

	drawCount = drawCount + 1

	if (not tempMinimapDisplayList) and (not visibleTexturesGenerated) then
		tempMinimapFont, tempMinimapDisplayList = InitializeTempMinimapLabel()
	end	
	if (drawCount >= 2) and (not tempMinimapTexture) and (not visibleTexturesGenerated) then  -- skip first Draw because for some reason textures rendered then are bugged
		tempMinimapTexture = InitializeTempMinimapTexture()
	end
	
	if (drawCoroutine.activeCoroutine) then
		ContinueCoroutine(drawCoroutine)
	else
		if initializedTexturesThisFrame then  -- do not do any additional work in the frame where InitializeBlocksTextures() was finishing its work
			initializedTexturesThisFrame = false
		elseif initializedTextures and (not startedGeneratingTextures) then
			startedGeneratingTextures = true
			GenerateMapTexture(mapTexX, mapTexZ, modifiedTypeMapSquares)
		end
	end
end

function gadget:DrawInMiniMap(minimapSizeX, minimapSizeY)
	if tempMinimapDisplayList and (not visibleTexturesGenerated) then
		glPushMatrix()
			glLoadIdentity()
			glTranslate(0, 1, 0)
			glScale(1, -1, 1)
			glCallList(tempMinimapDisplayList)
		glPopMatrix()
	end
end

function gadget:MousePress(x, y, button)
	--return (button == 1) and (not visibleTexturesGeneratedAndGroundDetailSet) -- prevents placing of start position
end

function gadget:GameStart()
	gameStarted = true -- finish all processing in next Draw call
end

function gadget:Shutdown()
	if origGroundDetail then
		Spring.SendCommands("GroundDetail " .. origGroundDetail)
		origGroundDetail = false
	end

	DeleteTempMinimapTexture()
end
