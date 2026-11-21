if not SERVER then return end

local NPC_CLASS = "drg_alex_mercer"
local CLEANUP_TIMER = "BecomeAlexMercer.PossessionCleanup"

local activePossessions = {}

local function playerKey(ply)
	return ply:SteamID64() or tostring(ply:UserID())
end

local function notify(ply, message)
	if IsValid(ply) then
		ply:ChatPrint("[Become Alex Mercer] " .. message)
	end
end

local function cleanupPossessions()
	for key, npc in pairs(activePossessions) do
		if not IsValid(npc) or not npc:IsPossessed() then
			if IsValid(npc) then
				npc:Remove()
			end
			activePossessions[key] = nil
		end
	end

	if next(activePossessions) == nil then
		timer.Remove(CLEANUP_TIMER)
	end
end

local function startCleanupTimer()
	if timer.Exists(CLEANUP_TIMER) then return end
	timer.Create(CLEANUP_TIMER, 0.1, 0, cleanupPossessions)
end

local function createMercer(ply)
	local npc = ents.Create(NPC_CLASS)
	if not IsValid(npc) then return end

	npc:SetPos(ply:GetPos())
	npc:SetAngles(Angle(0, ply:EyeAngles().y, 0))
	npc:Spawn()
	npc:Activate()

	return npc
end

local function preserveExitPosition(npc)
	local originalOnDispossessed = npc.OnDispossessed

	npc.OnDispossessed = function(self, ply)
		local position = self:GetPos()

		if isfunction(originalOnDispossessed) then
			originalOnDispossessed(self, ply)
		end

		if IsValid(ply) and ply:Alive() then
			ply:SetPos(position)
		end
	end
end

local function removePrevious(ply, key)
	local previous = activePossessions[key]
	if not IsValid(previous) then
		activePossessions[key] = nil
		return
	end

	if previous:IsPossessed() and previous:GetPossessor() == ply then
		previous:Dispossess()
	end
	if IsValid(previous) then
		previous:Remove()
	end
	activePossessions[key] = nil
end

concommand.Add("become_alex_mercer", function(ply)
	if not IsValid(ply) or not ply:IsPlayer() then
		print("[Become Alex Mercer] This command must be run by a player.")
		return
	end

	if not isfunction(ply.DrG_IsPossessing) then
		notify(ply, "DrGBase possession is not loaded.")
		return
	end

	if not scripted_ents.GetStored(NPC_CLASS) then
		notify(ply, NPC_CLASS .. " is not installed.")
		return
	end

	local possessionEnabled = GetConVar("drgbase_possession_enable")
	if possessionEnabled and not possessionEnabled:GetBool() then
		notify(ply, "DrGBase possession is disabled.")
		return
	end

	if not ply:Alive() then
		notify(ply, "You must be alive.")
		return
	end

	if ply:InVehicle() then
		notify(ply, "Exit your vehicle first.")
		return
	end

	local key = playerKey(ply)
	local current = activePossessions[key]
	if IsValid(current) and current:IsPossessed() then
		notify(ply, "You are already Alex Mercer.")
		return
	end

	removePrevious(ply, key)

	if ply:DrG_IsPossessing() then
		notify(ply, "Exit your current possession first.")
		return
	end

	local npc = createMercer(ply)
	if not IsValid(npc) then
		notify(ply, "Failed to create " .. NPC_CLASS .. ".")
		return
	end

	if not npc.IsDrGNextbot or not isfunction(npc.Possess) then
		npc:Remove()
		notify(ply, "The spawned entity is not a DrGBase nextbot.")
		return
	end

	local result = npc:Possess(ply)
	if result ~= "ok" then
		npc:Remove()
		notify(ply, "Possession failed: " .. tostring(result) .. ".")
		return
	end

	activePossessions[key] = npc
	preserveExitPosition(npc)
	startCleanupTimer()
end)
