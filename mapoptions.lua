----------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------------
-- File:        MapOptions.lua
-- Description: Custom MapOptions file that makes possible to set up variable options before game starts, like ModOptions.lua
-- Author:      SirArtturi, Lurker, Smoth, jK
----------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------------
--	NOTES:
--	- using an enumerated table lets you specify the options order
--
--	These keywords must be lowercase for LuaParser to read them.
--
--	key:		the string used in the script.txt
--	name:		the displayed name
--	desc:		the description (could be used as a tooltip)
--	type:		the option type
--	def:		the default value
--	min:		minimum value for number options
--	max:		maximum value for number options
--	step:		quantization step, aligned to the def value
--	maxlen:		the maximum string length for string options
--	items:		array of item strings for list options
--	scope:		'all', 'player', 'team', 'allyteam'			<<< not supported yet >>>
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local options = {
	{
		key  = 'MapGeneration',
		name = 'Map Generation Settings',
		desc = '',
		type = 'section',
	},

--// Options

	--// Map generation
	{
		key  = "seed",
		name = "Random Seed",
		desc = "Controls random seed used in procedural generattion",
		type = "number",
		def  = 0,
		min  = 0,
		max  = 1000000,
	},
	{
		key  = "numBases",
		name = "Number of bases to create",
		desc = "Defaults to number of teams",
		type = "number",
		def  = 0,
		min  = 3,
		max  = 11,
	},

}

return options