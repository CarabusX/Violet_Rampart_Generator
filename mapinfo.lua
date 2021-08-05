--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- mapinfo.lua
--

local mapinfo = {
	name        = "Fata Morgana Generator",
	shortname   = "FMG10",
	description = "Procedurally generates map for 3-11 way FFA. Terrain based on FataMorganaV2 by BasiC. Skybox from Smoth. Texture generation scripts based on Random Crags by GoogleFrog.",
	author      = "Rafal[ZK]",
	version     = "v1.0",
	--mutator   = "deployment";
	mapfile     = "maps/Fata_Morgana_Generator.smf", --// location of smf/sm3 file (optional)
	modtype     = 3, --// 1=primary, 0=hidden, 3=map
	depend      = {"Map Helper v1"},
	replace     = {},

	--startpic   = "", --// deprecated
	--StartMusic = "", --// deprecated

	maphardness     = 2000,
	notDeformable   = false,
	gravity         = 100, -- 125
	tidalStrength   = 18,
	maxMetal        = 2.45,
	extractorRadius = 90,
	voidWater       = false,
	voidground      = false,
	autoShowMetal   = true,

	smf = {
		-- 50/57 in heightmap texture equals to height 300 (-200 + 500 / 570)
		--minheight = -200,
		--maxheight =  370,
		minimapTex = "minimap.png",
		--smtFileName0 = "",
	},

	resources = {
		--grassBladeTex = "",
		--grassShadingTex = "",
		--detailTex = "",
		--specularTex = "",
		--splatDetailTex = "",
		--splatDistrTex = "",
		--skyReflectModTex = "",
		--detailNormalTex = "",
		--lightEmissionTex = "",
    	--parallaxHeightTex = "",
	},

	water = {
		absorb    = {0.2, 0.2, 0.2},
		baseColor = {0.3, 0.25, 0.0},
		minColor  = {0.26, 0.21, 0.0},

		planeColor = {0.2, 0.15, 0.0},

		surfaceColor = {0.3, 0.25, 0.0},
		surfaceAlpha = 0.1,
		
		perlinLacunarity = 0.1,
		perlinAmplitude  = 0.3,
	},
	
	atmosphere = {
		minWind      = 8,
		maxWind      = 13,

		fogStart     = 0.12,
		fogColor     = {1.0, 0.97, 0.7},
		
		sunColor     = {1.0, 1.0, 1.0},
		skyColor     = {0.7, 0.8, 1.0},
		skyDir       = {0.0, 1.0, 0.0},
		skyBox       = "skybox.dds",
		cloudDensity = 0.1,
		cloudColor   = {1.0, 1.0, 1.0},
	},

	lighting = {
		--// dynsun
		sunDir = {0.3, 0.9, 0.5},

		--// unit & ground lighting
		groundAmbientColor  = {0.6, 0.6, 0.6},
		groundDiffuseColor  = {0.7, 0.7, 0.7},
		groundShadowDensity = 0.8,
		unitAmbientColor    = {0.8, 0.8, 0.8},
		unitDiffuseColor    = {1.0, 1.0, 1.0},
		unitShadowDensity   = 0.3,
	},
	
	terrainTypes = {
		[0] = {
			name = "Dark Cold Place",
			hardness = 10.0,
			receiveTracks = false,
			moveSpeeds = {
				tank  = 0.0,
				kbot  = 0.0,
				hover = 0.0,
				ship  = 0.0,
			},
		},
		[1] = {
			name = "Rock",
			hardness = 1.0,
			receiveTracks = true,
			moveSpeeds = {
				tank  = 1.0,
				kbot  = 1.0,
				hover = 1.0,
				ship  = 1.0,
			},
		},
    },

}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Helper

local function lowerkeys(ta)
	local fix = {}
	for i,v in pairs(ta) do
		if (type(i) == "string") then
			if (i ~= i:lower()) then
				fix[#fix+1] = i
			end
		end
		if (type(v) == "table") then
			lowerkeys(v)
		end
	end
	
	for i=1,#fix do
		local idx = fix[i]
		ta[idx:lower()] = ta[idx]
		ta[idx] = nil
	end
end

lowerkeys(mapinfo)

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Map Options

if (Spring) then
	local function tmerge(t1, t2)
		for i,v in pairs(t2) do
			if (type(v) == "table") then
				t1[i] = t1[i] or {}
				tmerge(t1[i], v)
			else
				t1[i] = v
			end
		end
	end

	-- make code safe in unitsync
	if (not Spring.GetMapOptions) then
		Spring.GetMapOptions = function() return {} end
	end
	function tobool(val)
		local t = type(val)
		if (t == 'nil') then
			return false
		elseif (t == 'boolean') then
			return val
		elseif (t == 'number') then
			return (val ~= 0)
		elseif (t == 'string') then
			return ((val ~= '0') and (val ~= 'false'))
		end
		return false
	end

	getfenv()["mapinfo"] = mapinfo
		local files = VFS.DirList("mapconfig/mapinfo/", "*.lua")
		table.sort(files)
		for i=1,#files do
			local newcfg = VFS.Include(files[i])
			if newcfg then
				lowerkeys(newcfg)
				tmerge(mapinfo, newcfg)
			end
		end
	getfenv()["mapinfo"] = nil
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

return mapinfo

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------