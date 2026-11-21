if SERVER then
AddCSLuaFile()

local NPC_CLASS = "drg_alex_mercer"
local CLEANUP_TIMER = "BecomeAlexMercer.PossessionCleanup"
local ENERGY_TICK = 0.1
local ENERGY_MAX = 1
local ENERGY_NETWORK_KEY = "BecomeAlexMercerEnergy"
local MERCER_CRIT_KEY = "MercerCrit"

local activePossessions = {}
local playerEnergy = {}
local playerViewAngles = {}
local playerMercerHealth = {}
local playerMercerCrit = {}

local EnergyThreshold = CreateConVar("become_alex_mercer_energy_threshold", "0.1",
	{FCVAR_ARCHIVE, FCVAR_NOTIFY}, "变身前所需的最低能量")
local EnergyDrain = CreateConVar("become_alex_mercer_energy_drain", "0.01",
	{FCVAR_ARCHIVE, FCVAR_NOTIFY}, "墨瑟附身期间每秒消耗的能量")
local EnergyRegen = CreateConVar("become_alex_mercer_energy_regen", "0.05",
	{FCVAR_ARCHIVE, FCVAR_NOTIFY}, "非附身状态每秒恢复的能量")
local EnergyKillReward = CreateConVar("become_alex_mercer_energy_kill_reward", "0.2",
	{FCVAR_ARCHIVE, FCVAR_NOTIFY}, "附身期间每击杀一个 NPC 恢复的能量")

local function playerKey(ply)
	return ply:SteamID64() or tostring(ply:UserID())
end

local function notify(ply, message)
	if IsValid(ply) then
		ply:ChatPrint("[Become Alex Mercer] " .. message)
	end
end

hook.Add("EntityTakeDamage", "BecomeAlexMercerExitDamageProtection", function(ent, dmg)
	if not IsValid(ent) or not ent:IsPlayer() or not dmg then return end

	local key = playerKey(ent)
	local mercer = activePossessions[key]
	if not mercer then return end

	if dmg:GetAttacker() == mercer or dmg:GetInflictor() == mercer then
		return true
	end
end)

local function setEnergy(ply, value)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	value = math.Clamp(value, 0, ENERGY_MAX)
	playerEnergy[playerKey(ply)] = value
	ply:SetNW2Float(ENERGY_NETWORK_KEY, value)
	return value
end

local function getEnergy(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return 0 end
	local energy = playerEnergy[playerKey(ply)]
	if energy == nil then
		energy = setEnergy(ply, ENERGY_MAX)
	end
	return energy
end

local function addEnergy(ply, amount)
	if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
	return setEnergy(ply, getEnergy(ply) + math.max(amount or 0, 0))
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

hook.Add("PlayerSpawn", "BecomeAlexMercerEnergyReset", function(ply)
	setEnergy(ply, ENERGY_MAX)
	playerViewAngles[playerKey(ply)] = nil
end)

hook.Add("PlayerDisconnect", "BecomeAlexMercerEnergyCleanup", function(ply)
	playerEnergy[playerKey(ply)] = nil
	playerViewAngles[playerKey(ply)] = nil
	playerMercerHealth[playerKey(ply)] = nil
	playerMercerCrit[playerKey(ply)] = nil
end)

hook.Add("OnNPCKilled", "BecomeAlexMercerEnergyKill", function(victim, attacker, inflictor)
	if not IsValid(victim) then return end

	local function killerPlayer(entity)
		if not IsValid(entity) then return end
		if entity:IsPlayer() then return entity end
		if entity:GetClass() == NPC_CLASS then
			local possessor = entity:GetPossessor()
			if IsValid(possessor) and possessor:IsPlayer() then return possessor end
		end

		local owner = entity:GetOwner()
		if not IsValid(owner) then return end
		if owner:IsPlayer() then return owner end
		if owner:GetClass() == NPC_CLASS then
			local possessor = owner:GetPossessor()
			if IsValid(possessor) and possessor:IsPlayer() then return possessor end
		end
	end

	local ply = killerPlayer(attacker) or killerPlayer(inflictor)
	if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end

	addEnergy(ply, EnergyKillReward:GetFloat())
end)

timer.Create("BecomeAlexMercer.EnergyTick", ENERGY_TICK, 0, function()
	local drain = math.max(EnergyDrain:GetFloat(), 0) * ENERGY_TICK
	local regen = math.max(EnergyRegen:GetFloat(), 0) * ENERGY_TICK

	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and ply:Alive() then
			local energy = getEnergy(ply)
			local key = playerKey(ply)
			local npc = activePossessions[key]
			local transformed = IsValid(npc) and npc:IsPossessed() and npc:GetPossessor() == ply
			local nextEnergy = transformed and energy - drain or energy + regen

			if transformed then
				playerViewAngles[key] = ply:EyeAngles()
			end

			if nextEnergy ~= energy then
				setEnergy(ply, nextEnergy)
			end

			if transformed and nextEnergy <= 0 and IsValid(npc) then
				npc:Dispossess()
			end
		end
	end
end)

local function createMercer(ply)
	local npc = ents.Create(NPC_CLASS)
	if not IsValid(npc) then return end

	npc:SetPos(ply:GetPos())
	npc:SetAngles(ply:EyeAngles())
	npc:Spawn()
	npc:Activate()

	local savedHealth = playerMercerHealth[playerKey(ply)]
	if savedHealth then
		npc:SetHealth(savedHealth)
	end
	local savedCrit = playerMercerCrit[playerKey(ply)]
	if savedCrit then
		npc:SetNW2Float(MERCER_CRIT_KEY, savedCrit)
	end

	return npc
end

local function applyPlayerDisguise(npc, ply)
	local model = ply:GetModel()
	if not model or model == "" or not util.IsValidModel(model) then
		return false
	end

	local bodygroups = {}
	for _, group in ipairs(ply:GetBodyGroups() or {}) do
		bodygroups[#bodygroups + 1] = group.id .. "=" .. ply:GetBodygroup(group.id)
	end

	local kind = "PEDESTRIAN"
	if isfunction(npc.MercerIsMilitary) and npc:MercerIsMilitary(ply) then
		kind = "MILITARY"
	end

	local disguise = {
		mdl = model,
		skin = ply:GetSkin(),
		bg = table.concat(bodygroups, ","),
		kind = kind,
		factions = {},
	}

	if isfunction(npc.MercerApplyDisguise) then
		npc:MercerApplyDisguise(disguise, false)
	else
		npc:SetNW2String("MercerDisguiseModel", disguise.mdl)
		npc:SetNW2Int("MercerDisguiseSkin", disguise.skin)
		npc:SetNW2String("MercerDisguiseBG", disguise.bg)
		npc:SetNW2String("MercerDisguiseKind", disguise.kind)
		npc.MercerDisguiseFactions = disguise.factions
	end

	if isfunction(npc.MercerSetForm) and ALEX_MERCER_DISGUISE then
		npc:MercerSetForm(ALEX_MERCER_DISGUISE, false)
	else
		npc:SetNW2Bool("MercerDisguised", true)
	end

	return true
end

local function preserveExitState(npc)
	local originalOnDispossessed = npc.OnDispossessed

	npc.OnDispossessed = function(self, ply)
		local position = self:GetPos()
		local velocity = self:GetVelocity()
		local mercerEyeAngles = self:EyeAngles()
		local recordedEyeAngles = IsValid(ply) and playerViewAngles[playerKey(ply)]
		local eyeAngles = Angle(recordedEyeAngles and recordedEyeAngles.p or mercerEyeAngles.p, mercerEyeAngles.y,
			mercerEyeAngles.r)
		if IsValid(ply) then
			playerMercerHealth[playerKey(ply)] = self:Health()
			playerMercerCrit[playerKey(ply)] = self:GetNW2Float(MERCER_CRIT_KEY, 0)
			playerViewAngles[playerKey(ply)] = nil
		end

		if isfunction(originalOnDispossessed) then
			originalOnDispossessed(self, ply)
		end

		if IsValid(ply) and ply:Alive() then
			ply:SetPos(position)
			ply:SetEyeAngles(eyeAngles)
			ply:SetLocalVelocity(velocity)

			timer.Simple(0.1, function()
				if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() or ply:InVehicle() then return end
				if isfunction(ply.DrG_IsPossessing) and ply:DrG_IsPossessing() then return end
				ply:SetEyeAngles(eyeAngles)
				ply:SetLocalVelocity(velocity)
			end)
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

	if getEnergy(ply) < math.max(EnergyThreshold:GetFloat(), 0) then
		ply:EmitSound("Buttons.snd40")
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

	local playerVelocity = ply:GetVelocity()
	local result = npc:Possess(ply)
	if result ~= "ok" then
		npc:Remove()
		notify(ply, "Possession failed: " .. tostring(result) .. ".")
		return
	end

	npc:SetAngles(Angle(0, npc:GetAngles().y, 0))
	npc:SetVelocity(playerVelocity)
	activePossessions[key] = npc
	preserveExitState(npc)
	startCleanupTimer()

	timer.Simple(0, function()
		if IsValid(npc) and IsValid(ply) and npc:IsPossessed() and npc:GetPossessor() == ply then
			applyPlayerDisguise(npc, ply)
		end
	end)
end)
end

if CLIENT then
	local BAR_MATERIAL = Material("alex_mercer/hud/health_bar.png", "noclamp smooth")
	local FILL_MATERIAL = Material("alex_mercer/hud/health_fill.png", "noclamp smooth")
	local HEALTH_BAR_X, HEALTH_BAR_Y = 149.85, 71.25
	local HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT = 600, 10
	local ENERGY_WIDTH_RATIO = 0.25
	local ENERGY_GAP = 6
	local ENERGY_HOLD_TIME = 1
	local ENERGY_FADE_TIME = 0.75
	local ENERGY_NETWORK_KEY = "BecomeAlexMercerEnergy"
	local lastEnergy
	local lastEnergyChange = -math.huge

	local function getLocalEnergyDisplay()
		local ply = LocalPlayer()
		if not IsValid(ply) or not ply:Alive() then return end

		local energy = math.Clamp(ply:GetNW2Float(ENERGY_NETWORK_KEY, 1), 0, 1)
		local npc = isfunction(ply.DrG_GetPossessing) and ply:DrG_GetPossessing() or NULL
		local transformed = IsValid(npc) and npc:GetClass() == "drg_alex_mercer"
		local now = RealTime()

		if lastEnergy == nil then
			lastEnergy = energy
			lastEnergyChange = now - (energy >= 0.9995 and ENERGY_HOLD_TIME + ENERGY_FADE_TIME or 0)
		elseif math.abs(energy - lastEnergy) > 0.0005 then
			lastEnergy = energy
			lastEnergyChange = now
		end

		if transformed then
			return energy, 1
		end

		local age = now - lastEnergyChange
		if age <= ENERGY_HOLD_TIME then return energy, 1 end

		local alpha = math.Clamp(1 - (age - ENERGY_HOLD_TIME) / ENERGY_FADE_TIME, 0, 1)
		if alpha <= 0 then return end
		return energy, alpha
	end

	hook.Add("DrawOverlay", "BecomeAlexMercerEnergy", function()
		local energy, alpha = getLocalEnergyDisplay()
		if not energy then return end

		local scale = ScrH() / 720
		local width = HEALTH_BAR_WIDTH * ENERGY_WIDTH_RATIO * scale
		local height = HEALTH_BAR_HEIGHT * scale
		local x = HEALTH_BAR_X * scale
		local y = (HEALTH_BAR_Y - HEALTH_BAR_HEIGHT - ENERGY_GAP) * scale
		local drawAlpha = math.Clamp(math.floor(alpha * 255), 0, 255)

		surface.SetDrawColor(255, 255, 255, drawAlpha)
		surface.SetMaterial(BAR_MATERIAL)
		surface.DrawTexturedRect(x, y, width, height)

		if energy > 0 then
			render.SetScissorRect(math.floor(x), math.floor(y), math.ceil(x + width * energy), math.ceil(y + height), true)
			surface.SetDrawColor(255, 255, 255, drawAlpha)
			surface.SetMaterial(FILL_MATERIAL)
			surface.DrawTexturedRect(x, y, width, height)
			render.SetScissorRect(0, 0, 0, 0, false)
		end

		draw.SimpleText(math.Round(energy * 100) .. "%", "DermaDefaultBold", x + width * 0.5, y - 10 * scale,
			Color(255, 255, 255, drawAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end)
end
