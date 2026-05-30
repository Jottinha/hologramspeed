-- Events
RegisterNetEvent('HologramSpeed:SetTheme')

-- Constants
local ResourceName       = GetCurrentResourceName()
local HologramURI        = string.format("nui://%s/ui/hologram.html", ResourceName)
local AttachmentOffset   = vec3(2.5, -1, 0.85)
local AttachmentRotation = vec3(0, 0, -15)
local HologramModel      = `hologram_box_model`
local UpdateFrequency    = 50 -- ms entre updates do velocimetro (0 = todo frame; 50ms = 20x/seg, imperceptível)
local SettingKey         = string.format("%s:profile", GetCurrentServerEndpoint()) -- The key to store the current theme setting in. As themes are per server, this key is also.
local DBG                = false -- Enables debug information, not very useful unless you know what you are doing!

-- Variables
local duiObject                    = false -- The DUI object, used for messaging and is destroyed when the resource is stopped
local duiIsReady                   = false -- Set by a callback triggered by DUI once the javascript has fully loaded
local hologramObject               = 0 -- The current DUI anchor. 0 when one does not exist
local attachedVehicle              = 0 -- O veículo ao qual o holograma está anexado no momento (0 = nenhum)
local usingMetric, shouldUseMetric = ShouldUseMetricMeasurements() -- Used to track the status of the metric measurement setting
local textureReplacementMade       = false -- Due to some weirdness with the experimental replace texture native, we need to make the replacement after the anchor has been spawned in-game

-- Preferences
local displayEnabled = true
local currentTheme   = GetConvar("hsp_defaultTheme", "default")

function DebugPrint(...)
	if DBG then
		print(...)
	end
end

function EnsureDuiMessage(data)
	if duiObject and duiIsReady then
		SendDuiMessage(duiObject, json.encode(data))
		return true
	end

	return false
end

function SendChatMessage(message)
	TriggerEvent('chat:addMessage', {args = {message}})
end

function LoadPlayerProfile()
	local jsonData = GetResourceKvpString(SettingKey)
	if jsonData ~= nil then
		jsonData           = json.decode(jsonData)
		displayEnabled     = jsonData.displayEnabled
		currentTheme       = jsonData.currentTheme
		AttachmentOffset   = vec3(jsonData.attachmentOffset.x, jsonData.attachmentOffset.y, jsonData.attachmentOffset.z)
		AttachmentRotation = vec3(jsonData.attachmentRotation.x, jsonData.attachmentRotation.y, jsonData.attachmentRotation.z)
	end
end

function SavePlayerProfile()
	local jsonData = {
		displayEnabled     = displayEnabled,
		currentTheme       = currentTheme,
		attachmentOffset   = AttachmentOffset,
		attachmentRotation = AttachmentRotation,
	}
	SetResourceKvp(SettingKey, json.encode(jsonData))
end

function ToggleDisplay()
	displayEnabled = not displayEnabled
	SendChatMessage("Holographic speedometer " .. (displayEnabled and "^2enabled^r" or "^1disabled^r") .. ".") 
	SavePlayerProfile()
end

function SetTheme(newTheme)
	if newTheme ~= currentTheme then
		EnsureDuiMessage {theme = newTheme}
		SendChatMessage(newTheme == "default" and "Holographic speedometer theme ^5reset^r." or ("Holographic speedometer theme set to ^5" .. newTheme .. "^r."))
		currentTheme = newTheme
		SavePlayerProfile()
	end
end

function UpdateEntityAttach()
	local playerPed, currentVehicle
	playerPed = PlayerPedId()
	if IsPedInAnyVehicle(playerPed) and hologramObject ~= 0 and DoesEntityExist(hologramObject) then
		currentVehicle = GetVehiclePedIsIn(playerPed, false)
		-- Attach the hologram to the vehicle
		AttachEntityToEntity(hologramObject, currentVehicle, GetEntityBoneIndexByName(currentVehicle, "chassis"), AttachmentOffset, AttachmentRotation, false, false, false, false, false, true)
		attachedVehicle = currentVehicle
		DebugPrint(string.format("DUI anchor %s attached to %s", hologramObject, currentVehicle))
	end
end

-- Destrói o holograma com segurança e zera os handles.
-- Sempre usar isto antes de recriar para nunca vazar entidades órfãs.
function DestroyHologram()
	if hologramObject ~= 0 then
		if DoesEntityExist(hologramObject) then
			DeleteVehicle(hologramObject)
		end
		hologramObject  = 0
		attachedVehicle = 0
	end
end

function CheckRange(x, y, z, minVal, maxVal)
	if x == nil or y == nil or z == nil or minVal == nil or maxVal == nil then
		return false
	else
		return not (x < minVal or x > maxVal or y < minVal or y > maxVal or z < minVal or z > maxVal)
	end
end


-- Command Handler

function CommandHandler(args)

	local msgErr = "^1The the acceptable range for ^0%s ^1is ^0%f^1 ~ ^0%f^1, reset to default setting.^r"
	local msgSuc = "^2Speedometer ^0%s ^2changed to ^0%f, %f, %f^r"
	
	if args[1] == "theme" then
		if #args >= 2 then
			TriggerServerEvent('HologramSpeed:CheckTheme', args[2])
		else
			SendChatMessage("^1Invalid theme! ^0Usage: /hsp theme <name>^r")
		end
	elseif args[1] == "offset" then
		local nx, ny, nz = 2.5, -1, 0.85
		if #args >= 4 then
			nx, ny, nz = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
			if not CheckRange(nx, ny, nz, -5.0, 5.0) then
				nx, ny, nz = 2.5, -1, 0.85
				SendChatMessage(string.format(msgErr, args[1], -5.0, 5.0))
			end
		else
			SendChatMessage("Offset reset. To change the offset, use: /hsp offset <X> <Y> <Z>")
		end
		AttachmentOffset = vec3(nx, ny, nz)
		UpdateEntityAttach()
		SavePlayerProfile()
		SendChatMessage(string.format(msgSuc, args[1], nx, ny, nz))
	elseif args[1] == "rotate" then
		local nx, ny, nz = 0, 0, -15
		if #args >= 4 then
			nx, ny, nz = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
			if not CheckRange(nx, ny, nz, -45.0, 45.0) then
				nx, ny, nz = 0, 0, -15
				SendChatMessage(string.format(msgErr, args[1], -45.0, 45.0))
			end
		else
			SendChatMessage("Rotation reset. To change the rotation, use: /hsp rotate <X> <Y> <Z>")
		end
		AttachmentRotation = vec3(nx, ny, nz)
		UpdateEntityAttach()
		SavePlayerProfile()
		SendChatMessage(string.format(msgSuc, args[1], nx, ny, nz))
	else
		SendChatMessage("^1Usage: ^0/hsp <theme|offset|rotate> [args...]^r")
	end
end


-- Initialise the DUI. We only need to do this once.

function InitialiseDui()
	DebugPrint("Initialising...")

	duiObject = CreateDui(HologramURI, 512, 512)

	DebugPrint("\tDUI created")

	repeat Wait(0) until duiIsReady

	DebugPrint("\tDUI available")

	EnsureDuiMessage {
		useMetric = usingMetric,
		display = false,
		theme = currentTheme
	}

	DebugPrint("\tDUI initialised")

	local txdHandle  = CreateRuntimeTxd("HologramDUI")
	local duiHandle  = GetDuiHandle(duiObject)
	local duiTexture = CreateRuntimeTextureFromDuiHandle(txdHandle, "DUI", duiHandle)
	DebugPrint("\tRuntime texture created")

	DebugPrint("Done!")
end


-- Create hologram entity

function CreateHologram(HologramModel, currentVehicle)
	-- Create the hologram objec
	hologramObject = CreateVehicle(HologramModel, GetEntityCoords(currentVehicle), 0.0, false, true)
	SetVehicleIsConsideredByPlayer(hologramObject, false)
	SetVehicleEngineOn(hologramObject, true, true)
	SetEntityCollision(hologramObject, false, false)
	DebugPrint("DUI anchor created "..tostring(hologramObject))
	return hologramObject
end


-- Get the attachment offset by vehicle class (or return default if it doesn't match anything)

function GetAttachmentByVehicle(currentVehicle)
	local vc = GetVehicleClass(currentVehicle)
	--[[ Examples, uncomment it if you like
    if(vc == 8 or vc == 13) then
		return vec3(1.5, -0.5, 0.85)
	end
	if(vc == 10 or vc == 20) then
		return vec3(2.5, 1.5, 2.5)
	end
	if(vc == 16) then
		return vec3(2.5, 1.5, 1.5)
	end
	if(vc == 15) then
		return vec3(2.5, 1, 1.5)
	end
	if(vc == 14) then
		return vec3(2.5, 0, 2)
	end
    ]]--
	return AttachmentOffset
end


-- Attach hologram entity to the vehicle

function AttachHologramToVehicle(hologramObject, currentVehicle)
	-- Attach the hologram to the vehicle
	AttachEntityToEntity(hologramObject, currentVehicle, GetEntityBoneIndexByName(currentVehicle, "chassis"), GetAttachmentByVehicle(currentVehicle), AttachmentRotation, false, false, false, false, false, true)
	DebugPrint(string.format("DUI anchor %s attached to %s", hologramObject, currentVehicle))
end


-- Network events

AddEventHandler('HologramSpeed:SetTheme', function(theme)
	SetTheme(theme)
end)


-- Register command

RegisterCommand("hsp", function(_, args)	
	if #args == 0 then
		ToggleDisplay()
	else
		CommandHandler(args)
	end
end, false)


-- Register a callback for when the DUI JS has loaded completely

RegisterNUICallback("duiIsReady", function(_, cb)
	duiIsReady = true
    cb({ok = true})
end)


-- Add chat suggestion

TriggerEvent('chat:addSuggestion', '/hsp', 'Toggle the holographic speedometer', {
    { name = "command",  help = "Allow command: theme, offset, rotate" },
})


-- Register keyboard mapping

RegisterKeyMapping("hsp", "Toggle Holographic Speedometer", "keyboard", "grave") -- default: `


-- Main Loop

CreateThread(function()

	-- Sanity checks
	if string.lower(ResourceName) ~= ResourceName then
        print(string.format("[WARNING] you should rename your HologramSpeed resource folder name to '%s'.", string.lower(ResourceName)))
		return
	end

	if not IsModelInCdimage(HologramModel) or not IsModelAVehicle(HologramModel) then
		SendChatMessage("^1Could not find `hologram_box_model` in the game... ^rHave you installed the resource correctly?")
		return
	end
	
	LoadPlayerProfile()
	
	InitialiseDui()

	-- This thread watches for changes to the user's preferred measurement system
	CreateThread(function()	
		while true do
			Wait(1000)
	
			shouldUseMetric = ShouldUseMetricMeasurements()
	
			if usingMetric ~= shouldUseMetric and EnsureDuiMessage {useMetric = shouldUseMetric} then
				usingMetric = shouldUseMetric
			end
		end
	end)

	-- Garante que o modelo do holograma esteja carregado, com timeout.
	-- Retorna false se não conseguir carregar (evita busy-wait infinito).
	local function ensureHologramModel()
		if HasModelLoaded(HologramModel) then return true end
		RequestModel(HologramModel)
		local waited = 0
		while not HasModelLoaded(HologramModel) and waited < 5000 do
			Wait(50)
			waited = waited + 50
		end
		return HasModelLoaded(HologramModel)
	end

	-- Loop único e idempotente:
	--   * revalida o veículo a cada tick (nunca opera sobre handle 0/deletado);
	--   * mantém UM ÚNICO holograma, reaproveitado entre carros (re-anexa em vez
	--     de recriar) — sem vazar entidades;
	--   * calcula display todo frame, então nunca fica preso em display=false.
	-- Tolerancia antes de destruir o holograma em interrupcoes curtas (ex.:
	-- teleporte do outrun, que tira o player do carro por ate ~3s).
	local GRACE_MS        = 4000
	local notDrivingSince = 0 -- ms de quando deixou de dirigir; 0 = dirigindo

	while true do
		local playerPed      = PlayerPedId()
		local currentVehicle = GetVehiclePedIsIn(playerPed, false)
		local isDriver       = currentVehicle ~= 0
			and DoesEntityExist(currentVehicle)
			and GetPedInVehicleSeat(currentVehicle, -1) == playerPed

		if isDriver and ensureHologramModel() then
			notDrivingSince = 0

			-- (Re)cria o holograma só se ele não existir; senão reaproveita.
			if hologramObject == 0 or not DoesEntityExist(hologramObject) then
				DestroyHologram() -- limpa qualquer handle órfão antes de criar
				hologramObject = CreateHologram(HologramModel, currentVehicle)
				AttachHologramToVehicle(hologramObject, currentVehicle)
				attachedVehicle = currentVehicle

				-- Odd hacky fix for people who's textures won't replace properly
				if not textureReplacementMade then
					AddReplaceTexture("hologram_box_model", "p_hologram_box", "HologramDUI", "DUI")
					DebugPrint("Texture replacement made")
					textureReplacementMade = true
				end
				SetModelAsNoLongerNeeded(HologramModel)
			elseif attachedVehicle ~= currentVehicle then
				-- Trocou de carro (ex.: respawn de rodada do outrun): só re-anexa.
				AttachHologramToVehicle(hologramObject, currentVehicle)
				attachedVehicle = currentVehicle
				DebugPrint("DUI anchor re-anexado ao novo veículo "..tostring(currentVehicle))
			end

			-- reexibe caso tenha sido escondido durante uma janela de grace
			SetEntityVisible(hologramObject, true, false)

			local vehicleSpeed = GetEntitySpeed(currentVehicle)
			EnsureDuiMessage {
				display  = displayEnabled,
				rpm      = GetVehicleCurrentRpm(currentVehicle),
				gear     = GetVehicleCurrentGear(currentVehicle),
				abs      = (GetVehicleWheelSpeed(currentVehicle, 0) == 0.0) and (vehicleSpeed > 0.0),
				hBrake   = GetVehicleHandbrake(currentVehicle),
				rawSpeed = vehicleSpeed,
			}

			Wait(displayEnabled and UpdateFrequency or 500)
		elseif hologramObject ~= 0 and DoesEntityExist(hologramObject) then
			-- Nao esta dirigindo MAS o holograma existe: pode ser interrupcao curta
			-- (teleporte do outrun). Segura por GRACE_MS antes de destruir, mantendo
			-- a entidade viva e so escondendo o display ate reanexar no carro novo.
			if notDrivingSince == 0 then
				notDrivingSince = GetGameTimer()
			end

			if GetGameTimer() - notDrivingSince < GRACE_MS then
				SetEntityVisible(hologramObject, false, false)
				EnsureDuiMessage {display = false}
				Wait(100) -- checa rapido pra reanexar assim que o warp terminar
			else
				DestroyHologram()
				EnsureDuiMessage {display = false}
				notDrivingSince = 0
				Wait(500)
			end
		else
			-- A pe e sem holograma: nada a fazer, checa devagar.
			EnsureDuiMessage {display = false}
			notDrivingSince = 0
			Wait(500)
		end
	end
end)
 
-- Resource cleanup

AddEventHandler("onResourceStop", function(resource)
	if resource == ResourceName then
		DebugPrint("Cleaning up...")

		displayEnabled = false
		DebugPrint("\tDisplay disabled")

		DestroyHologram()
		DebugPrint("\tDUI anchor deleted")

		RemoveReplaceTexture("hologram_box_model", "p_hologram_box")
		DebugPrint("\tReplace texture removed")

		if duiObject then
			DebugPrint("\tDUI browser destroyed")
			DestroyDui(duiObject)
			duiObject = false
		end
	end
end)
