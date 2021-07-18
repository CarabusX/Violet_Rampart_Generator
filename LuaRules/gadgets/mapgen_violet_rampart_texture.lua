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

local DEBUG = true

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
local MAP_FAC_X = 2 / MAP_X
local MAP_FAC_Z = 2 / MAP_Z

local SQUARE_SIZE = 1024
local NUM_SQUARES_X = MAP_X / SQUARE_SIZE
local NUM_SQUARES_Z = MAP_Z / SQUARE_SIZE

local BLOCK_SIZE  = 8
local DRAW_OFFSET_X = 2 * BLOCK_SIZE/MAP_X - 1
local DRAW_OFFSET_Z = 2 * BLOCK_SIZE/MAP_Z - 1

local SQUARE_TEX_SIZE = SQUARE_SIZE/BLOCK_SIZE

local MINIMAP_SIZE_X = 1024
local MINIMAP_SIZE_Y = 1024

local USE_SHADING_TEXTURE = (Spring.GetConfigInt("AdvMapShading") == 1)

local DO_MIPMAPS = true

local DESIRED_GROUND_DETAIL = 200
local MAX_GROUND_DETAIL = 200 -- max allowed by Spring

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

local colorPool = {
	[1] = { 74/255, 59/255,  83/255, 1.0 },
	[2] = { 90/255, 45/255, 174/255, 1.0 },
	--[3] = { 0.0, 0.0, 0.0, 1.0 },
}

local BOTTOM_TERRAIN_TYPE       = 0
local RAMPART_TERRAIN_TYPE      = 1
local RAMPART_WALL_TERRAIN_TYPE = 2

local mainTexByTerrainType = {
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
local origGroundDetail = false
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
		if (coroutine.status(activeCoroutine) ~= "dead") then
			if (not isSleeping) then
				lastResumeTime = spGetTimer()
			end

			assert(coroutine.resume(activeCoroutine))
		else
			activeCoroutine = nil
		end
	end
end

local function Sleep()
	if (not gameStarted) then -- need to finish fast when game started
		lastResumeTime = nil
		isSleeping = true
		coroutine_yield()
		isSleeping = false
		lastResumeTime = spGetTimer()
	end
end

local function CheckTimeAndSleep()
	local currentTime = spGetTimer()
	local timeDiff = spDiffTimers(currentTime, lastResumeTime, true)
	--Spring.Echo(timeDiff)

	if timeDiff >= MIN_WORKING_TIME then
		spClearWatchDogTimer()
		Sleep()
	end
end

local function CheckTimeAndSleepWithColor(color)
	local currentTime = spGetTimer()
	local timeDiff = spDiffTimers(currentTime, lastResumeTime, true)
	--Spring.Echo(timeDiff)

	if timeDiff >= MIN_WORKING_TIME then
		spClearWatchDogTimer()

		glColor(1, 1, 1, 1)
		Sleep()
		glColor(color)
	end
end

local function CheckTimeAndSleepWithTexture(texture)
	local currentTime = spGetTimer()
	local timeDiff = spDiffTimers(currentTime, lastResumeTime, true)
	--Spring.Echo(timeDiff)

	if timeDiff >= MIN_WORKING_TIME then
		spClearWatchDogTimer()

		glTexture(false)
		Sleep()
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

local function DrawTextureOnSquare(x, z, srcX, srcZ)
	local x1 = 2*x/SQUARE_SIZE - 1
	local z1 = 2*z/SQUARE_SIZE - 1
	local x2 = 2*(x + SQUARE_SIZE)/SQUARE_SIZE - 1
	local z2 = 2*(z + SQUARE_SIZE)/SQUARE_SIZE - 1
	local srcSizeX = SQUARE_SIZE / MAP_X
	local srcSizeZ = SQUARE_SIZE / MAP_Z
	glTexRect(x1, z1, x2, z2, srcX, srcZ, srcX + srcSizeX, srcZ + srcSizeZ)
end

--[[
local function DrawTextureBlock(x, z)
	glTexRect(x*MAP_FAC_X - 1, z*MAP_FAC_Z - 1, x*MAP_FAC_X + DRAW_OFFSET_X, z*MAP_FAC_Z + DRAW_OFFSET_Z)
	--glTexRect(x*MAP_FAC_X - 1, z*MAP_FAC_Z - 1, x*MAP_FAC_X + DRAW_OFFSET_X, z*MAP_FAC_Z + DRAW_OFFSET_Z, 0, 0, 1.0, 8 / 512)
end
--]]

local function DrawColorBlock(x, z)
	glRect(x*MAP_FAC_X - 1, z*MAP_FAC_Z - 1, x*MAP_FAC_X + DRAW_OFFSET_X, z*MAP_FAC_Z + DRAW_OFFSET_Z)
end

local function PrintTimeSpent(message, startTime)
	local currentTime = spGetTimer()
	Spring.Echo(message .. string.format("%.0f", round(spDiffTimers(currentTime, startTime, true))) .. "ms")
end

local function AddDebugMarker(text)
	if DEBUG then
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

local function InitializeBlocksTextures()
	Spring.Echo("Starting analyze map for blocks textures")
	local startTime = spGetTimer()

	local mapTexX = {}
	local mapTexZ = {}
	for tex = 1, #colorPool do
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
					local tex = mainTexByTerrainType[terrainType]
					
					local index = #mapTexX[tex] + 1
					mapTexX[tex][index] = x
					mapTexZ[tex][index] = z
				end
			end

			if ((x / BLOCK_SIZE) % MIN_ANALYZED_COLUMMS_BEFORE_TIME_CHECK == 0) then
				CheckTimeAndSleep()
			end
		end

		PrintTimeSpent("Map analyzed for blocks textures in: ", startTime)
		AddDebugMarker("Map analyzed")

		initializedTextures = true	
	end

	StartScript(AnalyzeLoop)
	
	return mapTexX, mapTexZ
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local tempMinimapBackgroundColor = colorPool[1]

local tempMinimapFontColor = { 1.0, 1.0, 1.0, 1.0 }
local tempMinimapFontPath  = "fonts/FreeSansBold.otf"
local tempMinimapFontSize  = 65
local tempMinimapText      = { "Loading texture...", "Please wait..." }

local tempMinimapTexture = false
local tempMinimapFont = false
local tempMinimapDisplayList = false

local function CreateAndApplyTempMinimapTexture()
	if USE_SHADING_TEXTURE then
		local tempTexture = createFboTexture(MINIMAP_SIZE_X, MINIMAP_SIZE_Y, false)
		if not tempTexture then
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

			while j <= loopEnd do
				glRenderToTexture(fullTex, DrawColorBlock, texX[j], texZ[j])
				j = j + 1
			end

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

			while j <= loopEnd do
				glRenderToTexture(fullTex, DrawTextureBlock, texX[j], texZ[j])
				j = j + 1
			end

			CheckTimeAndSleepWithTexture(curTexture)
		end

		glTexture(false)
	end
	
	PrintTimeSpent("Blocks rendered to fullTex in: ", startTime)
end
--]]

local function RenderVisibleSquareTextures(fullTex)
	Spring.Echo("Starting to render SquareTextures")
	local startTime = spGetTimer()

	local squareTextures = {}

	for sx = 0, NUM_SQUARES_X - 1 do
		squareTextures[sx] = {}

		for sz = 0, NUM_SQUARES_Z - 1 do
			local squareTex = createFboTexture(SQUARE_TEX_SIZE, SQUARE_TEX_SIZE, DO_MIPMAPS)
			--local squareTex = createFboTexture(SQUARE_SIZE, SQUARE_SIZE, DO_MIPMAPS)

			glTexture(fullTex)
			glRenderToTexture(squareTex, DrawTextureOnSquare, 0, 0, sx/NUM_SQUARES_X, sz/NUM_SQUARES_Z)
			glTexture(false)

			if DO_MIPMAPS then
				glGenerateMipmap(squareTex)
			end

			squareTextures[sx][sz] = squareTex

			CheckTimeAndSleep()
		end
	end

	PrintTimeSpent("All SquareTextures created and rendered in: ", startTime)

	return squareTextures
end

local function ApplyVisibleSquareTextures(squareTextures)
	local startTime = spGetTimer()

	for sx = 0, NUM_SQUARES_X - 1 do
		for sz = 0, NUM_SQUARES_Z - 1 do
			spSetMapSquareTexture(sx, sz, squareTextures[sx][sz])
		end
	end

	PrintTimeSpent("All SquareTextures applied in: ", startTime)

	CheckTimeAndSleep()
end

local function RenderGGSquareTextures(fullTex, squareTextures)
	Spring.Echo("Starting to create GG.mapgen SquareTextures")
	local startTime = spGetTimer()

	GG.mapgen_squareTexture  = {}
	GG.mapgen_currentTexture = {}

	glTexture(fullTex)

	for sx = 0, NUM_SQUARES_X - 1 do
		GG.mapgen_squareTexture [sx] = {}
		GG.mapgen_currentTexture[sx] = {}

		for sz = 0, NUM_SQUARES_Z - 1 do
			local curTex  = createFboTexture(SQUARE_SIZE, SQUARE_SIZE, DO_MIPMAPS)
			glRenderToTexture(curTex , DrawTextureOnSquare, 0, 0, sx/NUM_SQUARES_X, sz/NUM_SQUARES_Z)
			-- gl.GenerateMipmap(curTex) is done in terrain_texture_handler

			GG.mapgen_squareTexture [sx][sz] = squareTextures[sx][sz]
			GG.mapgen_currentTexture[sx][sz] = curTex

			CheckTimeAndSleepWithTexture(fullTex)
		end
	end

	glTexture(false)

	PrintTimeSpent("All GG.mapgen SquareTextures created and rendered in: ", startTime)
end

local function RenderMinimap(fullTex)
	local fullTexUsedAsMinimap = false

	if USE_SHADING_TEXTURE then
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

		--Spring.SetMapShadingTexture("$minimap", fullTex)
		--fullTexUsedAsMinimap = true

		PrintTimeSpent("Applied minimap texture in: ", startTime)

		--CheckTimeAndSleep() -- do not sleep because this is the last operation before setting visibleTexturesGenerated flag
	end

	return fullTexUsedAsMinimap
end

local function GenerateMapTexture(mapTexX, mapTexZ)
	local DrawStart = spGetTimer()
	local startTime = DrawStart

	local fullTex = createFboTexture(MAP_X/BLOCK_SIZE, MAP_Z/BLOCK_SIZE, false)
	if not fullTex then
		return
	end

	PrintTimeSpent("Generated blank fullTex in: ", startTime)
	
	local function DrawLoop()
		-- Visible part
		DrawBlocksColorsOnFullTexture(mapTexX, mapTexZ, fullTex)
		--DrawBlocksTexturesOnFullTexture(mapTexX, mapTexZ, fullTex)
		local squareTextures = RenderVisibleSquareTextures(fullTex)
		ApplyVisibleSquareTextures(squareTextures)
		--GG.Tools.SaveFullTexture(fullTex)
		--GG.Tools.GenerateMinimapWithLabel(fullTex)		
		local fullTexUsedAsMinimap = RenderMinimap(fullTex)

		PrintTimeSpent("Visible map texture generation finished - total time: ", DrawStart)
		AddDebugMarker("Visible map texture generation finished")

		visibleTexturesGenerated = true  -- finished processing of visible textures
		setGroundDetail = true

		Sleep()

		-- Background part
		MIN_WORKING_TIME = BACKGROUND_MIN_WORKING_TIME

		DeleteTempMinimapTexture()
		RenderGGSquareTextures(fullTex, squareTextures)

		glDeleteTextureFBO(fullTex)
		if (not fullTexUsedAsMinimap) then
			glDeleteTexture(fullTex)
			fullTex = nil
		end

		PrintTimeSpent("Processing finished - total time: ", DrawStart)		
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
	if allWorkFinished then
		return
	end

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

	if startedInitializingTextures then
		return
	end

	updateCount = updateCount + 1

	if (updateCount >= 3) then  -- skip Update 1 and 2 until things are loaded
		startedInitializingTextures = true

		--InitTexturePool()
		mapTexX, mapTexZ = InitializeBlocksTextures()
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
	
	if activeCoroutine then
		UpdateCoroutines()
	else
		if initializedTextures and (not startedGeneratingTextures) then
			startedGeneratingTextures = true
			GenerateMapTexture(mapTexX, mapTexZ)
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
