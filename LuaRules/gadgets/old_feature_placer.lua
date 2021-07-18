function gadget:GetInfo()
	return {
		name      = "old feature placer",
		desc      = "Spawns Features and Units",
		author    = "Gnome, Smoth",
		date      = "August 2008",
		license   = "PD",
		layer     = 0,
		enabled   = true  --  loaded by default?
	}
end

if (not gadgetHandler:IsSyncedCode()) then
	return false
end

--------------------------------------------------------------------------------
-- Synced
--------------------------------------------------------------------------------

if (Spring.GetGameFrame() >= 1) then
	return false
end


function gadget:Initialize()
	local featuresList

	if VFS.FileExists("mapconfig/featureplacer/config.lua") then
		featuresList = VFS.Include("mapconfig/featureplacer/config.lua")
		Spring.Echo("Features loaded")
	else
		Spring.Echo("Missing file: mapconfig/featureplacer/config.lua")
		Spring.Echo("No features loaded")
	end

	if (featuresList) then
		Spring.Echo("Creating features")

		for _, fDef in ipairs(featuresList) do
			Spring.CreateFeature(fDef.name, fDef.x, Spring.GetGroundHeight(fDef.x, fDef.z), fDef.z, fDef.rot)
		end
	end

	gadgetHandler:RemoveGadget()
end
