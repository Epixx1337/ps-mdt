local resourceName = tostring(GetCurrentResourceName())

local function _isDojJob(jobName)
    if not jobName or not Config.DojJobs then return false end
    for _, name in ipairs(Config.DojJobs) do
        if name == jobName then return true end
    end
    return false
end

RegisterNUICallback('checkAuth', function(_, cb)
    local jobType = Bridge.getJobType()
    local jobName = Bridge.getJob() and Bridge.getJob().name or ''
    local isDoj = _isDojJob(jobName) or (Config.DojJobType and jobType == Config.DojJobType)
    local isAuthorized = jobType == Config.PoliceJobType or jobType == Config.MedicalJobType or isDoj
    local mdtJobType = isDoj and 'doj' or (jobType == Config.MedicalJobType and 'ems' or 'leo')
    local onDuty = Bridge.getJobDuty() or false
    local playerData = Bridge.getPlayerData()

    local isCivilian = false
    if not isAuthorized and Config.CivilianAccess and Config.CivilianAccess.enabled then
        isCivilian = true
    end

    cb({
        authorized = isCivilian or (isAuthorized and (isDoj or onDuty)),
        playerData = type(playerData) == 'table' and {
            citizenid = playerData.citizenid,
            job = playerData.job,
            charinfo = playerData.charinfo,
        } or nil,
        isLEO = isAuthorized,
        onDuty = isCivilian or isDoj or onDuty or false,
        jobType = isCivilian and 'civilian' or mdtJobType,
        isCivilian = isCivilian,
    })
end)

-- Separate NUI callback for fetching permissions (non-blocking)
RegisterNUICallback('getMyPermissions', function(_, cb)
    if not MDTOpen then
        cb({ permissions = {}, isBoss = false })
        return
    end

    local result = Bridge.callback(resourceName .. ':server:getMyPermissions')
    cb(result or { permissions = {}, isBoss = false })
end)

function NUIUpdateAuth()
    local jobType = Bridge.getJobType()
    local jobName = Bridge.getJob() and Bridge.getJob().name or ''
    local isDoj = _isDojJob(jobName) or (Config.DojJobType and jobType == Config.DojJobType)
    local isAuthorized = jobType == Config.PoliceJobType or jobType == Config.MedicalJobType or isDoj
    local mdtJobType = isDoj and 'doj' or (jobType == Config.MedicalJobType and 'ems' or 'leo')
    local playerData = Bridge.getPlayerData()
    SendNUI('updateAuth', {
        authorized = isAuthorized and (Bridge.getJobDuty() or false),
        playerData = type(playerData) == 'table' and {
            citizenid = playerData.citizenid,
            job = playerData.job,
            charinfo = playerData.charinfo,
        } or nil,
        isLEO = isAuthorized,
        onDuty = Bridge.getJobDuty() or false,
        jobType = mdtJobType,
    })
end

RegisterNUICallback('closeUI', function(_, cb)
    -- Bridge.debug('MDT closeUI triggered via NUI callback')
    PlayMDTSound('close')
    cb({})
    CloseMDT()
end)

RegisterNUICallback('signOut', function(_, cb)
    -- Bridge.debug('MDT signOut triggered via NUI callback')
    PlayMDTSound('close')
    cb({})
    CloseMDT()
    Bridge.notify('Signed out of MDT', 'success')
end)

RegisterNUICallback('toggleDuty', function(_, cb)
    -- Bridge.debug('MDT toggleDuty triggered via NUI callback')
    PlayMDTSound('buttonClick')
    cb({})
    TriggerServerEvent('mdt:server:toggleDuty')
end)

-- JOB DATA -----------------------------------------------
RegisterNUICallback('getJobData', function(_, cb)

    local jobData = Bridge.callback(resourceName .. ':server:getJobData')
     Bridge.debug('[getJobData] Triggered NUI callback on client', jobData)
    cb(jobData or {})
end)

-- REPORT STATISTICS ---------------------------------------
RegisterNUICallback('getReportStatistics', function(_, cb)
    if not MDTOpen then
        cb({ success = false, message = 'MDT is not open' })
        return
    end
    local reportStats = Bridge.callback(resourceName .. ':server:getReportStatistics')
    cb(reportStats)
end)



-- TIME STATISTICS -----------------------------------------
RegisterNUICallback('getTimeStatistics', function(_, cb)
    if not MDTOpen then
        cb({ success = false, message = 'MDT is not open' })
        return
    end
    local timeStats = Bridge.callback(resourceName .. ':server:getTimeStatistics')
    -- Bridge.debug('[getTimeStatistics] Triggered NUI callback on client', timeStats)
    cb(timeStats)
end)


-- ACTIVE WARRANTS -----------------------------------------
RegisterNUICallback('getActiveWarrants', function(_, cb)
    if not MDTOpen then
        cb({ success = false, message = 'MDT is not open' })
        return
    end
    local activeWarrants = Bridge.callback(resourceName .. ':server:getActiveWarrants')

    -- Bridge.debug('[getActiveWarrants] Triggered NUI callback on client',activeWarrants)
    cb(activeWarrants)
end)

-- View Warrant
RegisterNUICallback('viewWarrant', function(data, cb)
    cb({})
    TriggerServerEvent(resourceName..':server:viewWarrant', data.warrantId)
    -- Bridge.debug(('Viewing Warrant ID: %s'):format(data.warrantId))
end)



-- BULLETIN BOARD ----------------------------------------
RegisterNUICallback('getBulletins', function(_, cb)
    if not MDTOpen then
        cb({ success = false, message = 'MDT is not open' })
        return
    end
    local bulletins = Bridge.callback(resourceName .. ':server:getBulletins')
     Bridge.debug('[getBulletins] Triggered NUI callback on client',bulletins )
    cb(bulletins)
end)


RegisterNUICallback('createBulletin', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    if not data or not data.content or data.content == '' then
        cb({ success = false, message = 'Content is required' })
        return
    end
    local result = Bridge.callback(resourceName .. ':server:createBulletin', data)
    cb(result or { success = false })
end)

RegisterNUICallback('deleteBulletin', function(data, cb)
    if not MDTOpen then cb({ success = false }) return end
    if not data or not data.id then
        cb({ success = false, message = 'Missing bulletin ID' })
        return
    end
    local result = Bridge.callback(resourceName .. ':server:deleteBulletin', data)
    cb(result or { success = false })
end)

-- RECENT REPORTS -------------------------------------

RegisterNUICallback('getRecentReports', function(data, cb)
    if not MDTOpen then
        cb({ success = false, message = 'MDT is not open' })
        return
    end
    local page = data and data.page or nil
    local limit = data and data.limit or nil
    local recentReports = Bridge.callback(resourceName .. ':server:getRecentReports', page, limit)
    cb(recentReports)
end)

-- ACTIVE BOLOS ---------------------------------------

RegisterNUICallback('getActiveBolos', function(_, cb)
    if not MDTOpen then
        cb({ success = false, message = 'MDT is not open' })
        return
    end
    local activeBolos = Bridge.callback(resourceName .. ':server:getActiveBolos')
    cb(activeBolos)
end)

-- View Report
RegisterNUICallback('viewReport', function(data, cb)
    cb({})
    TriggerServerEvent(resourceName..':server:viewReport', data.reportId)
    -- Bridge.debug(('Viewing Report ID: %s'):format(data.reportId))
end)

-- ACTIVE UNITS ---------------------------------------

RegisterNUICallback('getActiveUnits', function(_, cb)
    if not MDTOpen then
        cb({ success = false, message = 'MDT is not open' })
        return
    end
    local activeUnits = Bridge.callback(resourceName .. ':server:getActiveUnits')
    -- Bridge.debug('[getActiveUnits] Active Units Data:', activeUnits)
    cb(activeUnits)
end)


-- DISPATCH -------------------------------------------

-- Build player data for attaching to dispatch
local function buildPlayerData()
    return {
        charinfo = {
            firstname = Bridge.getCharInfo('firstname'),
            lastname = Bridge.getCharInfo('lastname'),
        },
        metadata = {
            callsign = Bridge.getMetadata('callsign'),
        },
        citizenid = Bridge.getIdentifier(),
        job = {
            type = Bridge.getJobData('type'),
            name = Bridge.getJobData('name'),
            label = Bridge.getJobData('label'),
        },
    }
end

RegisterNUICallback('getRecentDispatches', function(_, cb)
    local dispatches = GetRecentDispatch()
    cb(dispatches or {})
end)

-- Real-time dispatch listener (from ps-dispatch)
RegisterNetEvent('ps-dispatch:client:notify', function(data)
    if not MDTOpen then return end
    if not data then return end
    SendNUI('updateRecentDispatches', GetRecentDispatch() or {})
end)

RegisterNUICallback('getUsageMetrics', function(_, cb)
    if not MDTOpen then
        cb({ success = false, message = 'MDT is not open' })
        return
    end

    local result = Bridge.callback(resourceName .. ':server:getUsageMetrics')
    cb(result or {})
end)

RegisterNUICallback("attachToDispatch", function(data, cb)
    if not MDTOpen then cb({}) return end
    local playerData = buildPlayerData()
    TriggerServerEvent('ps-dispatch:server:attach', data, playerData)
    cb(GetRecentDispatch())
    -- Bridge.debug('Attached to Dispatch Call: ' .. json.encode(data))
end)

RegisterNUICallback("detachFromDispatch", function(data, cb)
    if not MDTOpen then cb({}) return end
    local playerData = buildPlayerData()
    TriggerServerEvent('ps-dispatch:server:detach', data, playerData)
    Wait(100) -- wait to make sure non 1of1 servers have time to alter a server side table faster than the cb :kek:
    cb(GetRecentDispatch())
    -- Bridge.debug('Detached from Dispatch Call: ' .. json.encode(data))
end)

RegisterNUICallback("routeToDispatch", function(data, cb)
    local coords = data.coords or data.origin
    if not coords then
        cb('ok')
        Bridge.notify('No location data for this dispatch', 'error')
        return
    end
    local x = tonumber(coords.x) or tonumber(coords[1])
    local y = tonumber(coords.y) or tonumber(coords[2])
    if not x or not y then
        cb('ok')
        Bridge.notify('Invalid location data', 'error')
        return
    end
    SetNewWaypoint(x, y)
    cb('ok')
    Bridge.notify('Set Route to Dispatch Location', 'success')
end)
