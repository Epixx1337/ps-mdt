--[[
    Client-side bridge.

    Exposes the same `Bridge` global that server-side code uses (with
    client-relevant methods only) — auto-detects qbx_core vs qb-core.

    Includes notify/anim/keybinds/sounds/vehicle helpers + lib.callback
    wrappers for client → server callbacks.
]]

if IsDuplicityVersion() then return end

Bridge = Bridge or {}

-- ============================================================================
-- Framework detection
-- ============================================================================

if GetResourceState('qbx_core') == 'started' then
    Bridge.name  = 'qbx'
    Bridge.isQBX = true
elseif GetResourceState('qb-core') == 'started' then
    Bridge.name  = 'qb'
    Bridge.isQBX = false
else
    print('^1[mdt-bridge]^0 No supported framework detected (qbx_core / qb-core).')
    Bridge = nil
    return
end

local QBCore = (not Bridge.isQBX) and exports['qb-core']:GetCoreObject() or nil

-- ============================================================================
-- Console logging
-- ============================================================================

local function handleException(_, value)
    if type(value) == 'function' then return tostring(value) end
    return nil
end

local function formatArgs(...)
    local args = { ... }
    local out  = {}
    local opts = { sort_keys = true, indent = true, exception = handleException }
    for i = 1, select('#', ...) do
        local v = args[i]
        if type(v) == 'table'   then out[#out + 1] = json.encode(v, opts)
        elseif type(v) == 'boolean' then out[#out + 1] = tostring(v)
        elseif v == nil         then out[#out + 1] = 'nil'
        else                          out[#out + 1] = tostring(v)
        end
    end
    return table.concat(out, ' ')
end

function Bridge.debug(...)   print('^6[DEBUG]^0 '   .. formatArgs(...)) end
function Bridge.info(...)    print('^4[INFO]^0 '    .. formatArgs(...)) end
function Bridge.warn(...)    print('^3[WARN]^0 '    .. formatArgs(...)) end
function Bridge.error(...)   print('^1[ERROR]^0 '   .. formatArgs(...)) end
function Bridge.success(...) print('^2[SUCCESS]^0 ' .. formatArgs(...)) end

-- ============================================================================
-- Player / job getters (no source on client)
-- ============================================================================

function Bridge.getPlayerData()
    if Bridge.isQBX then return QBX and QBX.PlayerData or {} end
    return QBCore.Functions.GetPlayerData() or {}
end

function Bridge.getPlayer()
    return PlayerPedId()
end

function Bridge.getIdentifier()
    local pd = Bridge.getPlayerData()
    return pd and pd.citizenid or nil
end
Bridge.getCid = Bridge.getIdentifier

function Bridge.getMetadata(meta)
    local pd = Bridge.getPlayerData()
    return pd and pd.metadata and pd.metadata[meta] or nil
end

function Bridge.getCharInfo(info)
    local pd = Bridge.getPlayerData()
    return pd and pd.charinfo and pd.charinfo[info] or nil
end

function Bridge.getPlayerName()
    local pd = Bridge.getPlayerData()
    if not pd or not pd.charinfo then return nil end
    return (pd.charinfo.firstname or '') .. ' ' .. (pd.charinfo.lastname or '')
end
Bridge.getName = Bridge.getPlayerName

function Bridge.getCoords()
    return GetEntityCoords(PlayerPedId())
end

function Bridge.getJob()
    local pd = Bridge.getPlayerData()
    return pd and pd.job or nil
end

function Bridge.getJobName()      local j = Bridge.getJob() return j and j.name end
function Bridge.getJobType()      local j = Bridge.getJob() return j and j.type end
function Bridge.getJobDuty()      local j = Bridge.getJob() return j and j.onduty end
function Bridge.getJobData(k)     local j = Bridge.getJob() return j and j[k] end
function Bridge.getJobGrade()     local j = Bridge.getJob() return j and j.grade end
function Bridge.getJobGradeName() local j = Bridge.getJob() return j and j.grade and j.grade.name end
function Bridge.getJobGradePay()  local j = Bridge.getJob() return j and j.grade and j.grade.payment end
function Bridge.isBoss()          local j = Bridge.getJob() return j and j.isboss end

function Bridge.getMoneyData()
    local pd = Bridge.getPlayerData()
    return pd and pd.money or {}
end

function Bridge.getMoney(kind)
    return Bridge.getMoneyData()[kind or 'cash'] or 0
end

function Bridge.getAllMoney()
    local out = {}
    for k, v in pairs(Bridge.getMoneyData()) do
        out[#out + 1] = { name = k, amount = v }
    end
    return out
end

function Bridge.isDead()
    if Bridge.isQBX and GetResourceState('qbx_medical') == 'started' then
        local ok, dead     = pcall(function() return exports.qbx_medical:IsDead() end)
        local ok2, lstand  = pcall(function() return exports.qbx_medical:IsLaststand() end)
        if (ok and dead) or (ok2 and lstand) then return true end
        return false
    end
    return Bridge.getMetadata('isdead') or Bridge.getMetadata('inlaststand') or false
end

function Bridge.getVehicleLabel(model)
    local hash = type(model) == 'number' and model or GetEntityModel(model)
    if Bridge.isQBX then
        local data = exports.qbx_core:GetVehiclesByName(hash)
        if data then return data.name end
    else
        local data = QBCore.Shared.Vehicles and QBCore.Shared.Vehicles[hash]
        if data then return data.name end
    end
    return GetDisplayNameFromVehicleModel(hash)
end

-- ============================================================================
-- Notifications  (use ox_lib — works for both frameworks)
-- ============================================================================

function Bridge.notify(text, kind, time)
    if not text then return end
    lib.notify({
        description = text,
        type        = kind or 'info',
        duration    = time or 5000,
    })
end

-- ============================================================================
-- Asset requests  (model / animdict / particle)
-- ============================================================================

function Bridge.requestModel(model, timeout)
    timeout = timeout or 15000
    local hash = type(model) == 'number' and model or GetHashKey(model)
    local started = GetGameTimer()
    RequestModel(hash)
    while not HasModelLoaded(hash) do
        if GetGameTimer() - started > timeout then return false end
        Wait(0)
    end
    return true
end

function Bridge.requestAnim(dict, timeout)
    timeout = timeout or 15000
    local started = GetGameTimer()
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() - started > timeout then return false end
        Wait(0)
    end
    return true
end

function Bridge.requestPTFX(dict, timeout)
    timeout = timeout or 15000
    local started = GetGameTimer()
    RequestNamedPtfxAsset(dict)
    while not HasNamedPtfxAssetLoaded(dict) do
        if GetGameTimer() - started > timeout then return false end
        Wait(0)
    end
    return true
end

-- ============================================================================
-- Keybinds
-- ============================================================================

local registeredKeybinds = {}

function Bridge.addKeybind(key, command)
    if registeredKeybinds[key] then
        registeredKeybinds[key].disabled = false
        return
    end
    registeredKeybinds[key] = { command = command, disabled = false }
    RegisterCommand(key, function()
        if not registeredKeybinds[key].disabled then
            ExecuteCommand(registeredKeybinds[key].command)
        end
    end, false)
    RegisterKeyMapping(key, 'Keybind for ' .. key, 'keyboard', key)
end

function Bridge.removeKeybind(key)
    if registeredKeybinds[key] then registeredKeybinds[key].disabled = true end
end

-- ============================================================================
-- Audio  (replaces ps_lib's PlaySound)
-- ============================================================================

local function loadAudioBank(bank)
    if not bank then return end
    local timeout = 500
    while not RequestScriptAudioBank(bank, false) do
        if timeout == 0 then return false end
        timeout = timeout - 1
        Wait(0)
    end
    return true
end

local function releaseAudioBank(bank)
    if bank then ReleaseNamedScriptAudioBank(bank) end
end

function Bridge.playSound(data)
    if not data or not data.audioName then return end
    if type(data.audioName) == 'string' then data.audioName = { data.audioName } end
    loadAudioBank(data.audioBank)
    for i = 1, #data.audioName do
        local id = GetSoundId()
        PlaySoundFrontend(id, data.audioName[i], data.audioRef, false)
        ReleaseSoundId(id)
    end
    releaseAudioBank(data.audioBank)
end

function Bridge.playSoundFromCoords(data)
    if not data or not data.audioName or not data.coords then return end
    if type(data.audioName) == 'string' then data.audioName = { data.audioName } end
    loadAudioBank(data.audioBank)
    for i = 1, #data.audioName do
        local id = GetSoundId()
        PlaySoundFromCoord(id, data.audioName[i], data.coords.x, data.coords.y, data.coords.z, data.audioRef, false, data.range or 50.0, false)
        ReleaseSoundId(id)
    end
    releaseAudioBank(data.audioBank)
end

-- ============================================================================
-- Vehicle helpers
-- ============================================================================

function Bridge.spawnVehicle(model, callback, coords, warp)
    if Bridge.isQBX then
        local hash = type(model) == 'number' and model or GetHashKey(model)
        lib.requestModel(hash)
        local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, coords.w or 0.0, true, false)
        SetModelAsNoLongerNeeded(hash)
        if veh and veh ~= 0 then
            SetVehicleNeedsToBeHotwired(veh, false)
            SetVehRadioStation(veh, 'OFF')
            SetEntityAsMissionEntity(veh, true, true)
            if warp then TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1) end
            NetworkFadeInEntity(veh, true)
        end
        if callback then callback(veh) end
    else
        QBCore.Functions.SpawnVehicle(model, callback, coords, warp)
    end
end

function Bridge.setVehicleProperties(vehicle, properties)
    if not properties then return end
    if Bridge.isQBX then
        lib.setVehicleProperties(vehicle, properties)
    else
        QBCore.Functions.SetVehicleProperties(vehicle, properties)
    end
end

function Bridge.getVehicleProperties(vehicle)
    if Bridge.isQBX then
        return lib.getVehicleProperties(vehicle)
    end
    if QBCore.Functions.GetVehicleProperties then
        return QBCore.Functions.GetVehicleProperties(vehicle)
    end
    return nil
end

function Bridge.getPlate(vehicle)
    if not vehicle or vehicle == 0 then return '' end
    if Bridge.isQBX then
        return GetVehicleNumberPlateText(vehicle):gsub('^%s+', ''):gsub('%s+$', '')
    end
    return QBCore.Functions.GetPlate(vehicle)
end

-- ============================================================================
-- Callbacks  (lib.callback wrappers)
-- ============================================================================

function Bridge.registerCallback(name, fn)
    lib.callback.register(name, fn)
end

-- Client → Server: Bridge.callback(name, [cb,] ...)
function Bridge.callback(name, ...)
    local args = { ... }
    local cb
    if type(args[1]) == 'function' then
        cb = args[1]
        table.remove(args, 1)
    end
    if cb then
        lib.callback(name, false, cb, table.unpack(args))
    else
        return lib.callback.await(name, false, table.unpack(args))
    end
end

-- ============================================================================
-- PascalCase aliases  (legacy Framework.* call sites in client/impound_spawn)
-- ============================================================================

Bridge.SpawnVehicle         = Bridge.spawnVehicle
Bridge.SetVehicleProperties = Bridge.setVehicleProperties
Bridge.GetVehicleProperties = Bridge.getVehicleProperties
Bridge.GetPlate             = Bridge.getPlate
Bridge.TriggerCallback      = function(name, cb, ...) return Bridge.callback(name, cb, ...) end
