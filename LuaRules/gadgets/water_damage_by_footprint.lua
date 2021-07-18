
function gadget:GetInfo()
	return {
		name    = "Water Damage by Footprint",
		desc    = "Adjusts water damage depending on unit footprint area",
		author  = "Rafal[ZK]",
		date    = "July 2021",
		layer   = -1,
		enabled = true,
	}
end

if (not gadgetHandler:IsSyncedCode()) then
	return false
end

--------------------------------------------------------------------------------
-- Synced
--------------------------------------------------------------------------------

local WATER_DAMAGE_WEAPON_ID = -5

local footprintAreaWithDefaultDamage = 4 * 4 -- Comm footprint area
local multipliersByUnitDef = {}

local function getWaterDamageMultiplier(unitDefID)
	local multiplier = multipliersByUnitDef[unitDefID]

	if (not multiplier) then
		local unitDef = UnitDefs[unitDefID]
		local footprintArea = unitDef.xsize * unitDef.zsize 
		multiplier = footprintArea / footprintAreaWithDefaultDamage
		multipliersByUnitDef[unitDefID] = multiplier
	end

	return multiplier
end

function gadget:UnitPreDamaged_GetWantedWeaponDef()
	return { WATER_DAMAGE_WEAPON_ID }
end

function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID)
	if (weaponDefID == WATER_DAMAGE_WEAPON_ID) then
		local multiplier = getWaterDamageMultiplier(unitDefID)
		damage = damage * multiplier
	end

	return damage
end
