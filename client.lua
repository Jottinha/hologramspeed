-- HologramSpeed (versao simplificada): apenas o velocimetro holografico.
--
-- Removidos: temas, perfis salvos (KVP) e comandos de offset/rotate.
-- Foco em robustez contra respawns/teleportes (ex.: rodadas do outrun):
--   * a entidade do holograma e marcada como mission entity, entao o engine
--     nao a despawna sozinha por population cleanup;
--   * o modelo fica carregado (e um box minusculo) em vez de ser liberado;
--   * a textura DUI e REAPLICADA a cada (re)criacao -> nunca reaparece em branco.
-- Esses tres pontos corrigem o "para de funcionar depois de um tempo".

-- Constantes
local ResourceName       = GetCurrentResourceName()
local HologramURI        = string.format("nui://%s/ui/hologram.html", ResourceName)
local AttachmentOffset   = vec3(2.5, -1.0, 0.85)
local AttachmentRotation = vec3(0.0, 0.0, -15.0)
local HologramModel      = `hologram_box_model`
local UpdateFrequency    = 50 -- ms entre updates (50 = 20x/seg, imperceptivel)

-- Estado
local duiObject       = false -- objeto DUI (criado uma unica vez)
local duiIsReady      = false -- setado quando o JS termina de carregar
local hologramObject  = 0     -- entidade ancora do DUI (0 = inexistente)
local attachedVehicle = 0     -- veiculo ao qual o holograma esta anexado
local displayEnabled  = true  -- liga/desliga via /hsp
local usingMetric     = ShouldUseMetricMeasurements()

local function EnsureDuiMessage(data)
	if duiObject and duiIsReady then
		SendDuiMessage(duiObject, json.encode(data))
		return true
	end
	return false
end

local function SendChatMessage(message)
	TriggerEvent('chat:addMessage', { args = { message } })
end

-- Cria a DUI e registra a textura runtime que sera espelhada no modelo.
local function InitialiseDui()
	duiObject = CreateDui(HologramURI, 512, 512)
	repeat Wait(0) until duiIsReady
	EnsureDuiMessage { useMetric = usingMetric, display = false }

	local txdHandle = CreateRuntimeTxd("HologramDUI")
	CreateRuntimeTextureFromDuiHandle(txdHandle, "DUI", GetDuiHandle(duiObject))
end

-- Garante o modelo carregado, com timeout (evita busy-wait infinito).
local function EnsureModel()
	if HasModelLoaded(HologramModel) then return true end
	RequestModel(HologramModel)
	local waited = 0
	while not HasModelLoaded(HologramModel) and waited < 5000 do
		Wait(50)
		waited = waited + 50
	end
	return HasModelLoaded(HologramModel)
end

-- (Re)cria o holograma. SEMPRE reaplica a textura e marca como mission entity.
local function CreateHologram(vehicle)
	hologramObject = CreateVehicle(HologramModel, GetEntityCoords(vehicle), 0.0, false, true)
	SetEntityAsMissionEntity(hologramObject, true, true) -- impede cleanup do engine
	SetVehicleIsConsideredByPlayer(hologramObject, false)
	SetVehicleEngineOn(hologramObject, true, true)
	SetEntityCollision(hologramObject, false, false)
	-- Reaplicar todo recriar e o que corrige o holograma reaparecer "em branco".
	AddReplaceTexture("hologram_box_model", "p_hologram_box", "HologramDUI", "DUI")
end

local function AttachHologram(vehicle)
	AttachEntityToEntity(
		hologramObject, vehicle, GetEntityBoneIndexByName(vehicle, "chassis"),
		AttachmentOffset, AttachmentRotation,
		false, false, false, false, false, true
	)
	attachedVehicle = vehicle
end

-- Destroi com seguranca e zera os handles (nunca deixa entidade orfa).
local function DestroyHologram()
	if hologramObject ~= 0 then
		if DoesEntityExist(hologramObject) then
			DeleteVehicle(hologramObject)
		end
		hologramObject  = 0
		attachedVehicle = 0
	end
end

-- Toggle (global, exportado no fxmanifest como 'ToggleDisplay')
function ToggleDisplay()
	displayEnabled = not displayEnabled
	SendChatMessage("Velocimetro holografico " .. (displayEnabled and "^2ativado^r" or "^1desativado^r") .. ".")
end

RegisterCommand("hsp", function()
	ToggleDisplay()
end, false)

RegisterKeyMapping("hsp", "Alternar Velocimetro Holografico", "keyboard", "grave") -- tecla: `

RegisterNUICallback("duiIsReady", function(_, cb)
	duiIsReady = true
	cb({ ok = true })
end)

TriggerEvent('chat:addSuggestion', '/hsp', 'Liga/desliga o velocimetro holografico')

-- Loop principal
CreateThread(function()
	-- NUI exige nome de recurso em minusculas.
	if string.lower(ResourceName) ~= ResourceName then
		print(string.format("[hologramspeed] renomeie a pasta do recurso para minusculas: '%s'.", string.lower(ResourceName)))
		return
	end

	if not IsModelInCdimage(HologramModel) or not IsModelAVehicle(HologramModel) then
		SendChatMessage("^1[hologramspeed] modelo `hologram_box_model` nao encontrado. Os arquivos stream/data foram instalados?^r")
		return
	end

	InitialiseDui()

	-- Acompanha mudanca de metrico/imperial nas configuracoes do FiveM.
	CreateThread(function()
		while true do
			Wait(2000)
			local m = ShouldUseMetricMeasurements()
			if m ~= usingMetric and EnsureDuiMessage { useMetric = m } then
				usingMetric = m
			end
		end
	end)

	-- Tolerancia antes de destruir o holograma em interrupcoes curtas (ex.:
	-- teleporte do outrun, que tira o player do carro por ate ~3s).
	local GRACE_MS        = 4000
	local notDrivingSince = 0 -- ms de quando deixou de dirigir; 0 = dirigindo

	while true do
		local ped       = PlayerPedId()
		local vehicle   = GetVehiclePedIsIn(ped, false)
		local isDriver  = vehicle ~= 0
			and DoesEntityExist(vehicle)
			and GetPedInVehicleSeat(vehicle, -1) == ped

		if isDriver and EnsureModel() then
			notDrivingSince = 0

			-- (Re)cria so se nao existir; senao reaproveita o mesmo holograma.
			if hologramObject == 0 or not DoesEntityExist(hologramObject) then
				DestroyHologram() -- limpa handle orfao antes de criar
				CreateHologram(vehicle)
				AttachHologram(vehicle)
			elseif attachedVehicle ~= vehicle then
				-- Trocou de carro (ex.: respawn de rodada): so re-anexa.
				AttachHologram(vehicle)
			end

			SetEntityVisible(hologramObject, true, false)

			EnsureDuiMessage {
				display  = displayEnabled,
				rawSpeed = GetEntitySpeed(vehicle),
				rpm      = GetVehicleCurrentRpm(vehicle),
				gear     = GetVehicleCurrentGear(vehicle),
			}

			Wait(displayEnabled and UpdateFrequency or 500)
		elseif hologramObject ~= 0 and DoesEntityExist(hologramObject) then
			-- Nao dirigindo, mas o holograma existe: pode ser interrupcao curta.
			-- Segura por GRACE_MS so escondendo, pra reanexar rapido no carro novo.
			if notDrivingSince == 0 then
				notDrivingSince = GetGameTimer()
			end

			if GetGameTimer() - notDrivingSince < GRACE_MS then
				SetEntityVisible(hologramObject, false, false)
				EnsureDuiMessage { display = false }
				Wait(100)
			else
				DestroyHologram()
				EnsureDuiMessage { display = false }
				notDrivingSince = 0
				Wait(500)
			end
		else
			-- A pe e sem holograma: nada a fazer, checa devagar.
			EnsureDuiMessage { display = false }
			notDrivingSince = 0
			Wait(500)
		end
	end
end)

-- Limpeza ao parar o recurso
AddEventHandler("onResourceStop", function(resource)
	if resource ~= ResourceName then return end

	displayEnabled = false
	DestroyHologram()
	RemoveReplaceTexture("hologram_box_model", "p_hologram_box")

	if duiObject then
		DestroyDui(duiObject)
		duiObject = false
	end
end)
