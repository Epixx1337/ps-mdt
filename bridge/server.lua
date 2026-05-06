--[[
    Server-side bridge.

    Replaces ps_lib + the previous Framework.* shim with a single `Bridge`
    global that auto-detects qbx_core or qb-core and exposes a unified API.

    All player/job/money/shared-data lookups, lib.callback wrappers, and
    logging primitives live here.
]]

if not IsDuplicityVersion() then return end

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
local sharedCache = {}

-- ============================================================================
-- Console logging  (Bridge.debug / Bridge.info / Bridge.warn / Bridge.error / Bridge.success)
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
-- Callbacks  (lib.callback wrappers — match ps_lib semantics)
-- ============================================================================

function Bridge.registerCallback(name, fn)
    lib.callback.register(name, fn)
end

-- Server → Client: Bridge.callback(name, source, [cb,] ...)
function Bridge.callback(name, source, ...)
    local args = { ... }
    local cb
    if type(args[1]) == 'function' then
        cb = args[1]
        table.remove(args, 1)
    end
    if cb then
        lib.callback(name, source, cb, table.unpack(args))
    else
        return lib.callback.await(name, source, table.unpack(args))
    end
end

-- ============================================================================
-- Player getters
-- ============================================================================

if Bridge.isQBX then
    function Bridge.getPlayer(source)
        return exports.qbx_core:GetPlayer(source)
    end

    function Bridge.getPlayerByIdentifier(citizenid)
        return exports.qbx_core:GetPlayerByCitizenId(citizenid)
            or exports.qbx_core:GetOfflinePlayer(citizenid)
    end

    function Bridge.getOfflinePlayer(citizenid)
        return exports.qbx_core:GetOfflinePlayer(citizenid)
    end

    function Bridge.getAllPlayers()
        return exports.qbx_core:GetQBPlayers() or {}
    end
else
    function Bridge.getPlayer(source)
        return QBCore.Functions.GetPlayer(source)
    end

    function Bridge.getPlayerByIdentifier(citizenid)
        return QBCore.Functions.GetPlayerByCitizenId(citizenid)
            or (QBCore.Functions.GetOfflinePlayerByCitizenId
                and QBCore.Functions.GetOfflinePlayerByCitizenId(citizenid))
    end

    function Bridge.getOfflinePlayer(citizenid)
        if QBCore.Functions.GetOfflinePlayerByCitizenId then
            return QBCore.Functions.GetOfflinePlayerByCitizenId(citizenid)
        end
        return nil
    end

    function Bridge.getAllPlayers()
        return QBCore.Functions.GetQBPlayers() or {}
    end
end

Bridge.getPlayerByCid = Bridge.getPlayerByIdentifier

function Bridge.getLicense(source)
    if GetConvarInt('sv_fxdkMode', 0) == 1 then return 'license:fxdk' end
    return GetPlayerIdentifierByType(source, 'license')
end

function Bridge.getIdentifier(source)
    local p = Bridge.getPlayer(tonumber(source) or source)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end
Bridge.getCid = Bridge.getIdentifier

function Bridge.getSource(citizenid)
    local p = Bridge.getPlayerByIdentifier(citizenid)
    return p and p.PlayerData and p.PlayerData.source or nil
end

function Bridge.getPlayerData(source)
    local p = Bridge.getPlayer(source) or Bridge.getPlayerByIdentifier(source)
    return p and p.PlayerData or nil
end

local function fullName(player)
    if not player or not player.PlayerData or not player.PlayerData.charinfo then return nil end
    local ci = player.PlayerData.charinfo
    return (ci.firstname or '') .. ' ' .. (ci.lastname or '')
end

function Bridge.getPlayerName(source)
    return fullName(Bridge.getPlayer(source) or Bridge.getPlayerByIdentifier(source))
end
Bridge.getName = Bridge.getPlayerName

function Bridge.getPlayerNameByIdentifier(citizenid)
    return fullName(Bridge.getPlayerByIdentifier(citizenid)) or 'Unknown Person'
end
Bridge.getPlayerNameByCid = Bridge.getPlayerNameByIdentifier

function Bridge.getMetadata(source, key)
    local data = Bridge.getPlayerData(source)
    return data and data.metadata and data.metadata[key] or nil
end

function Bridge.setMetadata(source, key, value)
    if Bridge.isQBX then
        exports.qbx_core:SetMetadata(source, key, value)
    else
        local p = QBCore.Functions.GetPlayer(source)
        if p and p.Functions and p.Functions.SetMetaData then
            p.Functions.SetMetaData(key, value)
        end
    end
end

function Bridge.getCharInfo(source, info)
    local data = Bridge.getPlayerData(source)
    return data and data.charinfo and data.charinfo[info] or nil
end

function Bridge.isOnline(citizenid)
    return Bridge.getPlayerByIdentifier(citizenid) ~= nil
end

-- ============================================================================
-- Job / grade / duty / boss
-- ============================================================================

local function jobOf(source)
    local data = Bridge.getPlayerData(source)
    return data and data.job or nil
end

function Bridge.getJob(source)         return jobOf(source) end
function Bridge.getJobName(source)     local j = jobOf(source) return j and j.name end
function Bridge.getJobType(source)     local j = jobOf(source) return j and j.type end
function Bridge.getJobDuty(source)     local j = jobOf(source) return j and j.onduty end
function Bridge.getJobData(source, k)  local j = jobOf(source) return j and j[k] end
function Bridge.getJobGrade(source)    local j = jobOf(source) return j and j.grade end
function Bridge.getJobGradeLevel(src)  local j = jobOf(src)    return j and j.grade and j.grade.level end
function Bridge.getJobGradeName(src)   local j = jobOf(src)    return j and j.grade and j.grade.name end
function Bridge.getJobGradePay(src)    local j = jobOf(src)    return j and j.grade and j.grade.payment end
function Bridge.isBoss(source)         local j = jobOf(source) return j and j.isboss end

function Bridge.getJobCount(jobName)
    local n = 0
    for _, p in pairs(Bridge.getAllPlayers()) do
        local j = (type(p) == 'table' and p.PlayerData and p.PlayerData.job) or jobOf(p)
        if j and j.name == jobName and j.onduty then n = n + 1 end
    end
    return n
end

function Bridge.getJobTypeCount(jobType)
    local n = 0
    for _, p in pairs(Bridge.getAllPlayers()) do
        local j = (type(p) == 'table' and p.PlayerData and p.PlayerData.job) or jobOf(p)
        if j and j.type == jobType and j.onduty then n = n + 1 end
    end
    return n
end

function Bridge.setJob(source, jobName, grade)
    if Bridge.isQBX then
        local cid = Bridge.getIdentifier(source)
        if not cid then return end
        -- AddPlayerToJob is required because SetPlayerPrimaryJob only works
        -- if the player already holds the job. 'unemployed' is the default
        -- and cannot be added explicitly.
        if jobName ~= 'unemployed' then
            exports.qbx_core:AddPlayerToJob(cid, jobName, grade or 0)
        end
        exports.qbx_core:SetPlayerPrimaryJob(cid, jobName)
    else
        local p = QBCore.Functions.GetPlayer(source)
        if p and p.Functions and p.Functions.SetJob then
            p.Functions.SetJob(jobName, grade or 0)
        end
    end
end

function Bridge.setJobDuty(source, duty)
    if Bridge.isQBX then
        exports.qbx_core:SetJobDuty(source, duty)
    else
        local p = QBCore.Functions.GetPlayer(source)
        if p and p.Functions and p.Functions.SetJobDuty then
            p.Functions.SetJobDuty(duty)
        end
    end
end

-- ============================================================================
-- Shared data — jobs / vehicles / weapons / items
-- ============================================================================

function Bridge.getSharedJobs()
    if Bridge.isQBX then
        if not sharedCache.jobs then sharedCache.jobs = exports.qbx_core:GetJobs() or {} end
        return sharedCache.jobs
    end
    return QBCore.Shared.Jobs or {}
end
Bridge.getJobTable = Bridge.getSharedJobs

function Bridge.getSharedJob(jobName)
    return Bridge.getSharedJobs()[jobName]
end

function Bridge.getSharedJobData(jobName, key)
    local job = Bridge.getSharedJob(jobName)
    return job and job[key] or nil
end

function Bridge.getSharedJobGrade(jobName, grade)
    local job = Bridge.getSharedJob(jobName)
    if not job or not job.grades then return nil end
    return job.grades[grade] or job.grades[tostring(grade)]
end

function Bridge.getSharedJobGradeData(jobName, grade, key)
    local g = Bridge.getSharedJobGrade(jobName, grade)
    return g and g[key] or nil
end

function Bridge.getAllJobs()
    local list = {}
    for k in pairs(Bridge.getSharedJobs()) do list[#list + 1] = k end
    return list
end

function Bridge.jobExists(jobName)
    return Bridge.getSharedJobs()[jobName] ~= nil
end

function Bridge.getSharedVehicles()
    if Bridge.isQBX then
        if not sharedCache.vehicles then sharedCache.vehicles = exports.qbx_core:GetVehiclesByName() or {} end
        return sharedCache.vehicles
    end
    return QBCore.Shared.Vehicles or {}
end

function Bridge.getSharedVehicle(model)
    return Bridge.getSharedVehicles()[model]
end
Bridge.getVehicleByModel = Bridge.getSharedVehicle

function Bridge.getSharedVehicleData(model, key)
    local v = Bridge.getSharedVehicle(model)
    return v and v[key] or nil
end

function Bridge.getSharedWeapons()
    if Bridge.isQBX then
        if not sharedCache.weapons then sharedCache.weapons = exports.qbx_core:GetWeapons() or {} end
        return sharedCache.weapons
    end
    return QBCore.Shared.Weapons or {}
end

function Bridge.getWeaponByHash(hash)
    if type(hash) == 'string' then hash = GetHashKey(hash) end
    return Bridge.getSharedWeapons()[hash]
end

function Bridge.getSharedWeaponData(hash, key)
    local w = Bridge.getWeaponByHash(hash)
    return w and w[key] or nil
end

function Bridge.getSharedItems()
    if not sharedCache.items then
        if GetResourceState('ox_inventory') == 'started' then
            local ok, items = pcall(function() return exports.ox_inventory:Items() end)
            if ok and items then sharedCache.items = items end
        end
        if not sharedCache.items and not Bridge.isQBX and QBCore and QBCore.Shared then
            sharedCache.items = QBCore.Shared.Items
        end
        sharedCache.items = sharedCache.items or {}
    end
    return sharedCache.items
end

function Bridge.getItemLabel(item)
    local data = Bridge.getSharedItems()[item]
    return (data and data.label) or item
end

function Bridge.getItemWeight(item)
    local data = Bridge.getSharedItems()[item]
    return (data and data.weight) or 0
end

function Bridge.getItemByName(player, itemName)
    if not player or not itemName then return nil end
    local src = (player.PlayerData and player.PlayerData.source) or player.source
    if src and GetResourceState('ox_inventory') == 'started' then
        local ok, slot = pcall(function() return exports.ox_inventory:GetSlotWithItem(src, itemName) end)
        if ok then return slot end
    end
    if player.Functions and player.Functions.GetItemByName then
        return player.Functions.GetItemByName(itemName)
    end
    if player.PlayerData and player.PlayerData.items then
        for _, it in pairs(player.PlayerData.items) do
            if it.name == itemName then return it end
        end
    end
    return nil
end

function Bridge.createUseable(item, fn)
    if not item or not fn then return end
    if Bridge.isQBX then
        exports.qbx_core:CreateUseableItem(item, fn)
    else
        QBCore.Functions.CreateUseableItem(item, fn)
    end
end

-- ============================================================================
-- Money
-- ============================================================================

function Bridge.addMoney(source, kind, amount, reason)
    kind   = kind   or 'cash'
    amount = amount or 0
    reason = reason or 'mdt-add'
    if Bridge.isQBX then
        return exports.qbx_core:AddMoney(source, kind, amount, reason)
    end
    local p = QBCore.Functions.GetPlayer(source)
    if not p then return false end
    return p.Functions.AddMoney(kind, amount, reason) and true or false
end

function Bridge.removeMoney(source, kind, amount, reason)
    kind   = kind   or 'cash'
    amount = amount or 0
    reason = reason or 'mdt-remove'
    if Bridge.isQBX then
        return exports.qbx_core:RemoveMoney(source, kind, amount, reason)
    end
    local p = QBCore.Functions.GetPlayer(source)
    if not p then return false end
    return p.Functions.RemoveMoney(kind, amount, reason) and true or false
end

function Bridge.getMoney(source, kind)
    kind = kind or 'cash'
    if Bridge.isQBX then return exports.qbx_core:GetMoney(source, kind) end
    local p = QBCore.Functions.GetPlayer(source)
    return (p and p.PlayerData.money and p.PlayerData.money[kind]) or 0
end

-- ============================================================================
-- Position / distance / nearby
-- ============================================================================

function Bridge.getEntityCoords(source)
    return GetEntityCoords(GetPlayerPed(source))
end

function Bridge.getDistance(source, location)
    local p = GetEntityCoords(GetPlayerPed(source))
    return #(p - vector3(location.x, location.y, location.z))
end

function Bridge.checkDistance(source, location, distance)
    return Bridge.getDistance(source, location) <= (distance or 2.5)
end

function Bridge.getNearbyPlayers(source, distance)
    distance = distance or 10.0
    local out, here = {}, GetEntityCoords(GetPlayerPed(source))
    for _, p in pairs(Bridge.getAllPlayers()) do
        local src = (type(p) == 'table' and p.PlayerData and p.PlayerData.source) or p
        local dist = #(GetEntityCoords(GetPlayerPed(src)) - here)
        if dist < distance then
            out[#out + 1] = {
                value    = Bridge.getIdentifier(src),
                label    = Bridge.getPlayerName(src),
                source   = src,
                distance = dist,
            }
        end
    end
    return out
end

-- ============================================================================
-- Group / vehicle ownership / permissions
-- ============================================================================

function Bridge.getGroupMembers(group, groupType)
    if Bridge.isQBX then
        return exports.qbx_core:GetGroupMembers(group, groupType) or {}
    end
    return {}
end

function Bridge.vehicleOwner(plate)
    local row = MySQL.query.await('SELECT citizenid FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
    return row and row[1] and row[1].citizenid or false
end

function Bridge.hasPermission(source, permission)
    return IsPlayerAceAllowed(source, permission) and true or false
end

-- ============================================================================
-- Notifications  (server → client via ox_lib)
-- ============================================================================

function Bridge.notify(source, text, kind, time)
    if not source or not text then return end
    TriggerClientEvent('ox_lib:notify', source, {
        description = text,
        type        = kind or 'info',
        duration    = time or 5000,
    })
end

-- ============================================================================
-- Duty toggle  (replaces ps_lib's toggleDuty event)
-- ============================================================================

RegisterNetEvent('mdt:server:toggleDuty', function()
    local src = source
    Bridge.setJobDuty(src, not Bridge.getJobDuty(src))
end)

-- ============================================================================
-- PascalCase aliases (legacy Framework.* call sites)
-- ============================================================================

Bridge.GetPlayer            = Bridge.getPlayer
Bridge.GetPlayerByCitizenId = Bridge.getPlayerByIdentifier
Bridge.GetAllPlayers        = Bridge.getAllPlayers
Bridge.GetOfflinePlayer     = Bridge.getOfflinePlayer
Bridge.SetMetaData          = Bridge.setMetadata
Bridge.GetMetaData          = Bridge.getMetadata
Bridge.GetItemByName        = Bridge.getItemByName
Bridge.GetSharedJobs        = Bridge.getSharedJobs
Bridge.GetSharedVehicles    = Bridge.getSharedVehicles
Bridge.GetSharedWeapons     = Bridge.getSharedWeapons
Bridge.GetSharedItems       = Bridge.getSharedItems
Bridge.GetVehicleByModel    = Bridge.getVehicleByModel
Bridge.GetWeaponByHash      = Bridge.getWeaponByHash
Bridge.GetGroupMembers      = Bridge.getGroupMembers
