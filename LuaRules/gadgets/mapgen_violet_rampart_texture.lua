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

local spSetMapSquareTexture = Spring.SetMapSquareTexture

local glTexture         = gl.Texture
local glColor           = gl.Color
local glCreateTexture   = gl.CreateTexture
local glRenderToTexture = gl.RenderToTexture
local glDeleteTexture   = gl.DeleteTexture
local glTexRect         = gl.TexRect
local glRect            = gl.Rect

local GL_RGBA = 0x1908
local GL_RGBA32F = 0x8814

local max   = math.max
local floor = math.floor

local MAP_X = Game.mapSizeX
local MAP_Z = Game.mapSizeZ
local MAP_FAC_X = 2 / MAP_X
local MAP_FAC_Z = 2 / MAP_Z

local SQUARE_SIZE = 1024
local SQUARES_X = MAP_X / SQUARE_SIZE
local SQUARES_Z = MAP_Z / SQUARE_SIZE

local BLOCK_SIZE  = 8
local DRAW_OFFSET_X = 2 * BLOCK_SIZE/MAP_X - 1
local DRAW_OFFSET_Z = 2 * BLOCK_SIZE/MAP_Z - 1

local USE_SHADING_TEXTURE = (Spring.GetConfigInt("AdvMapShading") == 1)

local SPLAT_DETAIL_TEX_POOL = {
	{0.0, 0.0, 0.0, 0.0},
	{0.0, 0.0, 1.0, 1.0},
}
local INITIAL_SPLAT = 1

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local initialized, mapFullyProcessed = false, false
local setGroundDetail = false
local prevGroundDetail = false

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local coroutine = coroutine
local Sleep     = coroutine.yield
local activeCoroutine

local function StartScript(fn)
	local co = coroutine.create(fn)
	activeCoroutine = co
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

local RATE_LIMIT = 1000000 --12000

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

local function DrawTexBlock(x, z)
	glTexRect(x*MAP_FAC_X - 1, z*MAP_FAC_Z - 1, x*MAP_FAC_X + DRAW_OFFSET_X, z*MAP_FAC_Z + DRAW_OFFSET_Z)
end

local function DrawColorBlock(x, z)
	glRect(x*MAP_FAC_X -1, z*MAP_FAC_Z - 1, x*MAP_FAC_X + DRAW_OFFSET_X, z*MAP_FAC_Z + DRAW_OFFSET_Z)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function RateCheckWithTexture(loopCount, texture)
	if loopCount > RATE_LIMIT then
		loopCount = 0
		Spring.ClearWatchDogTimer()
		Sleep()
		glTexture(texture)
	end
	return loopCount + 1
end

local function RateCheckWithColor(loopCount, color)
	if loopCount > RATE_LIMIT then
		loopCount = 0
		Spring.ClearWatchDogTimer()
		Sleep()
		glColor(color)
	end
	return loopCount + 1
end

local function SetMapTexture(texturePool, mapTexX, mapTexZ, splatTexX, splatTexZ)
	local DrawStart = Spring.GetTimer()

	local usedsplat
	local usedgrass
	local usedminimap
	
	local startTime0 = Spring.GetTimer()

	local fullTex = createFboTexture(MAP_X/BLOCK_SIZE, MAP_Z/BLOCK_SIZE)
	if not fullTex then
		return
	end
	
	Spring.Echo("Generated blank fullTex")
	local splatTex = USE_SHADING_TEXTURE and gl.CreateTexture(MAP_X/BLOCK_SIZE, MAP_Z/BLOCK_SIZE,
		{
			format = GL_RGBA32F,
			border = false,
			min_filter = GL.LINEAR,
			mag_filter = GL.LINEAR,
			wrap_s = GL.CLAMP_TO_EDGE,
			wrap_t = GL.CLAMP_TO_EDGE,
			fbo = true,
		}
	)

	if USE_SHADING_TEXTURE then
		glColor(SPLAT_DETAIL_TEX_POOL[1])
		glRenderToTexture(splatTex, function()
			glRect(-1, -1, 1, 1)
		end)
		glColor(1, 1, 1, 1)
	end
	Spring.Echo("Generated blank splatTex")

	local currentTime = Spring.GetTimer()
	Spring.Echo("Generated blank textures in: " .. Spring.DiffTimers(currentTime, startTime0, true))
	
	local function DrawLoop()
		local loopCount = 0

		glColor(1, 1, 1, 1)
		local startTime1 = Spring.GetTimer()
		for i = 1, #texturePool do
			local texX = mapTexX[i]
			local texZ = mapTexZ[i]

			Spring.Echo(#texX .. " blocks to be drawn with texture " .. i)
			local curTexture = texturePool[i].path
			glTexture(curTexture)
			for j = 1, #texX do
				glRenderToTexture(fullTex, DrawTexBlock, texX[j], texZ[j])
				loopCount = RateCheckWithTexture(loopCount, curTexture)
			end
			Spring.ClearWatchDogTimer()
			Sleep()
		end
		glTexture(false)
		
		local currentTime = Spring.GetTimer()
		Spring.Echo("FullTex rendered in: " .. Spring.DiffTimers(currentTime, startTime1, true))
		
		if USE_SHADING_TEXTURE then
			local startTime2 = Spring.GetTimer()
			for i = 1, #SPLAT_DETAIL_TEX_POOL do
				local texX = splatTexX[i]
				local texZ = splatTexZ[i]

				local curColor = SPLAT_DETAIL_TEX_POOL[i]
				glColor(curColor)
				for j = 1, #texX do
					glRenderToTexture(splatTex, DrawColorBlock, texX[j], texZ[j])
					loopCount = RateCheckWithColor(loopCount, curColor)
				end
				Spring.ClearWatchDogTimer()
				Sleep()
			end
			currentTime = Spring.GetTimer()
			Spring.Echo("SplatTex rendered in: " .. Spring.DiffTimers(currentTime, startTime2, true))
			glColor(1, 1, 1, 1)
		end

		Spring.Echo("Starting to render SquareTextures")
		
		local texOut = fullTex
		
		GG.mapgen_squareTexture  = {}
		GG.mapgen_currentTexture = {}

		local startTime3 = Spring.GetTimer()
		local SQUARE_TEX_SIZE = SQUARE_SIZE/BLOCK_SIZE

		for x = 0, MAP_X - 1, SQUARE_SIZE do -- Create square textures for each square
			local sx = floor(x/SQUARE_SIZE)
			GG.mapgen_squareTexture[sx]  = {}
			GG.mapgen_currentTexture[sx] = {}

			for z = 0, MAP_Z - 1, SQUARE_SIZE do
				local sz = floor(z/SQUARE_SIZE)
				local squareTex = createFboTexture(SQUARE_TEX_SIZE, SQUARE_TEX_SIZE)
				--local squareTex = createFboTexture(SQUARE_SIZE, SQUARE_SIZE)
				local origTex = createFboTexture(SQUARE_TEX_SIZE, SQUARE_TEX_SIZE)
				--local origTex = createFboTexture(SQUARE_SIZE, SQUARE_SIZE)
				local curTex = createFboTexture(SQUARE_SIZE, SQUARE_SIZE)

				glTexture(texOut)
				
				glRenderToTexture(squareTex, DrawTextureOnSquare, 0, 0, x/MAP_X, z/MAP_Z)
				glRenderToTexture(origTex  , DrawTextureOnSquare, 0, 0, x/MAP_X, z/MAP_Z)
				glRenderToTexture(curTex   , DrawTextureOnSquare, 0, 0, x/MAP_X, z/MAP_Z)
				
				GG.mapgen_squareTexture[sx][sz]  = origTex
				GG.mapgen_currentTexture[sx][sz] = curTex
				
				glTexture(false)
				gl.GenerateMipmap(squareTex)
				Spring.SetMapSquareTexture(sx, sz, squareTex)

				Spring.ClearWatchDogTimer()
			end
		end
		currentTime = Spring.GetTimer()
		Spring.Echo("All squareTex created, rendered and applied in: " .. Spring.DiffTimers(currentTime, startTime3, true))

		--gl.DrawGroundQuad

		local startTime4 = Spring.GetTimer()
		if USE_SHADING_TEXTURE then
			Spring.SetMapShadingTexture("$grass", texOut)
			usedgrass = texOut
			Spring.SetMapShadingTexture("$minimap", texOut)
			usedminimap = texOut
			Spring.Echo("Applied grass and minimap textures")
		end
		gl.DeleteTextureFBO(fullTex)
		
		if texOut and texOut ~= usedgrass and texOut ~= usedminimap then
			glDeleteTexture(texOut)
			texOut = nil
		end
		
		if USE_SHADING_TEXTURE then
			texOut = splatTex
			Spring.SetMapShadingTexture("$ssmf_splat_distr", texOut)
			usedsplat = texOut
			Spring.Echo("Applied splat texture")
			gl.DeleteTextureFBO(splatTex)
			if texOut and texOut ~= usedsplat then
				glDeleteTexture(texOut)
				if splatTex and texOut == splatTex then
					splatTex = nil
				end
				texOut = nil
			end
			if splatTex and splatTex ~= usedsplat then
				glDeleteTexture(splatTex)
				splatTex = nil
			end
		end
		currentTime = Spring.GetTimer()
		Spring.Echo("Applied grass, minimap and splat textures in: " .. Spring.DiffTimers(currentTime, startTime4, true))

		local DrawEnd = currentTime
		Spring.Echo("Map texture generation total time: " .. Spring.DiffTimers(DrawEnd, DrawStart, true))
		
		mapFullyProcessed = true
		setGroundDetail = true
	end
	
	StartScript(DrawLoop)
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

local function ExtractTexturesFromMap()
	texturePool[1] = ExtractTextureFromPosition(4040, 6160, BLOCK_SIZE, BLOCK_SIZE) --512 -- rampart
	texturePool[2] = ExtractTextureFromPosition(3880, 6160, BLOCK_SIZE, BLOCK_SIZE) --512 -- wall

	--gl.RenderToTexture(texturePool[1].path, gl.SaveImage, 0, 0, BLOCK_SIZE, 512, "rock.png")
	--gl.RenderToTexture(texturePool[2].path, gl.SaveImage, 0, 0, BLOCK_SIZE, 512, "crystal.png")
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

local BOTTOM_TERRAIN_TYPE       = 0
local RAMPART_TERRAIN_TYPE      = 1
local RAMPART_WALL_TERRAIN_TYPE = 2

local mainTexByType = {
	[RAMPART_TERRAIN_TYPE]      = 1,
	[RAMPART_WALL_TERRAIN_TYPE] = 2,
	--[BOTTOM_TERRAIN_TYPE]       = 3,
}

local splatTexByType = {
	[RAMPART_TERRAIN_TYPE]      = 1,
	[RAMPART_WALL_TERRAIN_TYPE] = 2,
	--[BOTTOM_TERRAIN_TYPE]       = 3,
}

local function InitializeTextures(useSplat)
	local startTime = Spring.GetTimer()
	local mapTexX, mapTexZ = {}, {}
	local splatTexX, splatTexZ = {}, {}

	for tex = 1, #texturePool do
		mapTexX[tex] = {}
		mapTexZ[tex] = {}
	end
	if useSplat then
		for splat = 1, #SPLAT_DETAIL_TEX_POOL do
			splatTexX[splat] = {}
			splatTexZ[splat] = {}
		end
	end

	local mapgen_typeMap = SYNCED.mapgen_typeMap
	if not mapgen_typeMap then
		Spring.Echo("mapgen_typeMap not set")
		return mapTexX, mapTexZ, splatTexX, splatTexZ
	end
	
	for x = 0, MAP_X - 1, BLOCK_SIZE do
		local mapgen_typeMapX = mapgen_typeMap[x]
		for z = 0, MAP_Z - 1, BLOCK_SIZE do
			local terrainType = mapgen_typeMapX[z]

			if (terrainType ~= BOTTOM_TERRAIN_TYPE) then			
				local tex = mainTexByType[terrainType]
				local splat = splatTexByType[terrainType]
				
				local index = #mapTexX[tex] + 1
				mapTexX[tex][index] = x
				mapTexZ[tex][index] = z

				if useSplat and splat and splat ~= INITIAL_SPLAT then
					local index = #splatTexX[splat] + 1
					splatTexX[splat][index] = x
					splatTexZ[splat][index] = z
				end
			end
		end
	end

	local currentTime = Spring.GetTimer()
	Spring.Echo("Map analyzed for textures in: " .. Spring.DiffTimers(currentTime, startTime, true))
	
	return mapTexX, mapTexZ, splatTexX, splatTexZ
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local mapTexX, mapTexZ, splatTexX, splatTexZ

function gadget:DrawGenesis()
	if not initialized then
		return
	end
	if mapFullyProcessed then
		gadgetHandler:RemoveGadget()
		return
	end
	
	if activeCoroutine then
		UpdateCoroutines()
	else
		InitTexturePool()
		SetMapTexture(texturePool, mapTexX, mapTexZ, splatTexX, splatTexZ)
	end
end

function gadget:MousePress(x, y, button)
	return (button == 1) and (not mapFullyProcessed)
end

local function MakeMapTexture()
	if (not gl.RenderToTexture) then --super bad graphic driver
		mapFullyProcessed = true
		return
	end
	mapTexX, mapTexZ, splatTexX, splatTexZ = InitializeTextures(USE_SHADING_TEXTURE)
	initialized = true
end

local updateCount = 0
function gadget:Update(n)
	if setGroundDetail then		
		prevGroundDetail = Spring.GetConfigInt("GroundDetail", 90) -- Default in epic menu
		Spring.Echo("GroundDetail: " .. prevGroundDetail)
		Spring.SendCommands{"GroundDetail " .. math.max(200, prevGroundDetail + 1)}
		setGroundDetail = false
	end

	if not updateCount then
		return
	end
	updateCount = updateCount + 1
	if updateCount > 2 then
		updateCount = false
		MakeMapTexture()
	end
end

function gadget:Shutdown()
	if prevGroundDetail then
		Spring.SendCommands{"GroundDetail " .. prevGroundDetail}
		prevGroundDetail = false
	end
end
