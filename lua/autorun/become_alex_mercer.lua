if SERVER then
AddCSLuaFile()

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

		if isfunction(originalOnDispossessed) then
			originalOnDispossessed(self, ply)
		end

		if IsValid(ply) and ply:Alive() then
			ply:SetPos(position)
			ply:SetLocalVelocity(velocity)
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

concommand.Add("become_alex_mercer", function(ply, _, args)
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

	local duration = tonumber(args and args[1])
	if not duration or duration <= 0 or duration ~= duration or duration == math.huge then
		duration = 0
	end

	local playerVelocity = ply:GetVelocity()
	local result = npc:Possess(ply)
	if result ~= "ok" then
		npc:Remove()
		notify(ply, "Possession failed: " .. tostring(result) .. ".")
		return
	end

	npc:SetVelocity(playerVelocity)
	activePossessions[key] = npc
	preserveExitState(npc)
	startCleanupTimer()

	npc:SetNW2Float("BecomeAlexMercerDuration", duration)
	npc:SetNW2Float("BecomeAlexMercerEndTime", duration > 0 and CurTime() + duration or 0)

	if duration > 0 then
		timer.Simple(duration, function()
			if IsValid(npc) and IsValid(ply) and npc:IsPossessed() and npc:GetPossessor() == ply then
				npc:Dispossess()
			end
		end)
	end

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
	local TIMER_WIDTH_RATIO = 0.25
	local TIMER_GAP = 6

	local function getTimerData()
		local ply = LocalPlayer()
		if not IsValid(ply) or not isfunction(ply.DrG_GetPossessing) then return end

		local npc = ply:DrG_GetPossessing()
		if not IsValid(npc) or npc:GetClass() ~= "drg_alex_mercer" then return end

		local duration = npc:GetNW2Float("BecomeAlexMercerDuration", 0)
		if duration <= 0 then
			return duration, 1, 0
		end

		local remaining = math.max(npc:GetNW2Float("BecomeAlexMercerEndTime", 0) - CurTime(), 0)
		return duration, math.Clamp(remaining / duration, 0, 1), remaining
	end

	hook.Add("DrawOverlay", "BecomeAlexMercerTimer", function()
		local duration, fraction, remaining = getTimerData()
		if not duration then return end

		local scale = ScrH() / 720
		local width = HEALTH_BAR_WIDTH * TIMER_WIDTH_RATIO * scale
		local height = HEALTH_BAR_HEIGHT * scale
		local x = HEALTH_BAR_X * scale
		local y = (HEALTH_BAR_Y - HEALTH_BAR_HEIGHT - TIMER_GAP) * scale

		surface.SetDrawColor(255, 255, 255, 255)
		surface.SetMaterial(BAR_MATERIAL)
		surface.DrawTexturedRect(x, y, width, height)

		if fraction > 0 then
			render.SetScissorRect(math.floor(x), math.floor(y), math.ceil(x + width * fraction), math.ceil(y + height), true)
			surface.SetMaterial(FILL_MATERIAL)
			surface.DrawTexturedRect(x, y, width, height)
			render.SetScissorRect(0, 0, 0, 0, false)
		end

		if duration > 0 then
			draw.SimpleText(string.format("%.1f", remaining), "DermaDefaultBold", x + width * 0.5, y - 10 * scale,
				Color(255, 255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end)
end
