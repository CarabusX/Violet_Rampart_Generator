--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- mapinfo.lua
--

local mapinfo = {
	name        = "Violet Rampart Generator",
	shortname   = "VRG10",
	description = "Procedurally generates map for 3-11 way FFA. Water is acidic. Terrain based on Violet Rampart by qray and Azure Rampart by zwzsg. Skybox from Smoth. Texture generation scripts based on Random Crags by GoogleFrog.",
	author      = "Rafal[ZK]",
	version     = "v1.0",
	--mutator   = "deployment";
	mapfile     = "maps/Violet_Rampart_Generator.smf", --// location of smf/sm3 file (optional)
	modtype     = 3, --// 1=primary, 0=hidden, 3=map
	depend      = {"Map Helper v1"},
	replace     = {},

	--startpic   = "", --// deprecated
	--StartMusic = "", --// deprecated

	maphardness     = 500,
	notDeformable   = false,
	gravity         = 100, -- 130
	tidalStrength   = 3,
	maxMetal        = 0.96,
	extractorRadius = 90.0,
	voidWater       = false,
	voidground      = false,
	autoShowMetal   = true,


	smf = {
		-- 45/52 in heightmap texture equals to height 300 (-150 + 450 / 520)
		--minheight = -150,
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

	splats = {
		texScales = {0.013, 0.026, 0.01, 0.05},
 		texMults  = {0.3, 0.55, 0.7, 0.8},			
	},

	water = {
		damage    = 200.0, -- gadget additionally multiplies this by unit footprint area

		--absorb    = {0.0, 0.0, 0.0},
		absorb    = {0.01, 0.01, 0.01},
		baseColor = {0.0, 0.0, 0.3},
		minColor  = {0.0, 0.0, 0.0},

		--planeColor = {0.0, 0.0, 0.0},

		shoreWaves = false,
	},
	
	atmosphere = {
		minWind      = 0.0,
		maxWind      = 0.0,

		fogStart     = 0.9,
		--fogEnd       = 1.2,
		fogColor     = {0.0, 0.0, 0.0},
		
		sunColor     = {0.7, 0.7, 0.7},
		skyColor     = {0.5, 0.5, 0.8},
		skyDir       = {0.0, 1.0, 0.0},
		skyBox       = "skybox.dds",
		cloudDensity = 0.1,
		cloudColor   = {0.1, 0.0, 0.4},
	},

	lighting = {
		--// dynsun
		sunStartAngle = 0.0,
		sunOrbitTime  = 1440.0,
		--sunDir        = {0.0, 0.45, -1.0, 1e9},
		sunDir        = {-0.3, 0.9, 0.3, 1e9},
		--// unit & ground lighting
		groundAmbientColor  = {0.33, 0.33, 0.33},
		groundDiffuseColor  = {0.30, 0.30, 0.40},
		groundSpecularColor = {0.2, 0.2, 0.25},
		groundShadowDensity = 0.8,
		unitAmbientColor    = {0.5, 0.55, 0.6},
		unitDiffuseColor    = {0.55, 0.55, 0.7},
		unitSpecularColor   = {0.4, 0.45, 0.5},
		unitShadowDensity   = 0.8,
		
		--specularExponent    = 100.0,
	},
	
	terrainTypes = {
		[0] = {
			name = "Dark Cold Place (Acid)",
			hardness = 10.0, -- 6.0
			receiveTracks = false,
			moveSpeeds = {
				tank  = 0.5,
				kbot  = 0.5,
				hover = 0.5,
				ship  = 0.5,
				--tank  = 0.0,
				--kbot  = 0.0,
				--hover = 0.0,
				--ship  = 0.0,
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
		[2] = {
			name = "Crystal",
			hardness = 4.0, -- 4.0
			receiveTracks = false,
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