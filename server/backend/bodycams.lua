local resourceName = tostring(GetCurrentResourceName())
local bodycamInstances = {}
local bodycamViewers = {}

local function getBodycamConfig()
    return Config and Config.Bodycam or {}
end

local function getOnDutyOfficers()
    local officers = {}
    if not Bridge then return officers end

    for _, player in pairs(Bridge.getAllPlayers() or {}) do
        local data = player.PlayerData
        if data and data.job and data.job.onduty and IsPoliceJob(data.job.name, data.job.type) then
            officers[#officers + 1] = player
        end
    end
    return officers
end

-- Get all bodycams for on-duty officers
Bridge.registerCallback(resourceName .. ':server:getBodycams', function(source)
    local src = source
    Bridge.debug('getBodycams called by source:', src)

    if not CheckAuth(src) then
        Bridge.debug('getBodycams: CheckAuth failed for source:', src)
        return {}
    end

    Bridge.debug('getBodycams: CheckAuth passed for source:', src)
    local bodycams = {}

    local officers = getOnDutyOfficers()
    Bridge.debug('getBodycams: Found on-duty officers:', officers and #officers or 0)

    for _, player in pairs(officers or {}) do
        local playerData = player.PlayerData
        if playerData then
            local bodycamId = tostring(playerData.source)
            local officerName = playerData.charinfo.firstname .. ' ' .. playerData.charinfo.lastname

            if not bodycamInstances[bodycamId] then
                bodycamInstances[bodycamId] = {
                    id = bodycamId,
                    officerName = officerName,
                    callsign = playerData.metadata and playerData.metadata.callsign or 'Unknown',
                    rank = playerData.job.grade and playerData.job.grade.name or 'Officer',
                    playerId = playerData.source,
                    isOnline = true,
                    createdAt = os.time()
                }
                Bridge.debug('Created bodycam on-demand for officer:', officerName, 'ID:', bodycamId)
            else
                local data = bodycamInstances[bodycamId]
                data.officerName = officerName
                data.callsign = playerData.metadata and playerData.metadata.callsign or 'Unknown'
                data.rank = playerData.job.grade and playerData.job.grade.name or 'Officer'
            end
        end
    end

    local instanceCount = 0
    for _ in pairs(bodycamInstances) do
        instanceCount = instanceCount + 1
    end
    Bridge.debug('getBodycams: Total bodycam instances before verification:', instanceCount)
    for bodycamId, _ in pairs(bodycamInstances) do
        Bridge.debug('getBodycams: Bodycam instance found:', bodycamId)
    end

    for bodycamId, data in pairs(bodycamInstances) do
        Bridge.debug('getBodycams: Verifying bodycam:', bodycamId, 'for player:', data.playerId)
        local isStillOnline = false

        local player = Bridge and Bridge.getPlayer(data.playerId) or nil

        if player and player.PlayerData and player.PlayerData.job and player.PlayerData.job.onduty then
            isStillOnline = true
            Bridge.debug('getBodycams: Officer verified as online:', data.officerName)
        end

        Bridge.debug('getBodycams: Officer', data.officerName, 'isStillOnline:', isStillOnline)

        if isStillOnline then
            local viewerCount = 0
            if bodycamViewers[bodycamId] then
                for _ in pairs(bodycamViewers[bodycamId]) do
                    viewerCount = viewerCount + 1
                end
            end

            table.insert(bodycams, {
                id = bodycamId,
                officerName = data.officerName,
                callsign = data.callsign,
                rank = data.rank,
                isOnline = true,
                viewerCount = viewerCount,
            })
            Bridge.debug('getBodycams: Added bodycam to return list:', bodycamId, 'with', viewerCount, 'viewers')
        else
            -- Remove offline bodycam
            bodycamInstances[bodycamId] = nil
            Bridge.debug('getBodycams: Removed offline bodycam:', bodycamId)
        end
    end

    Bridge.debug('getBodycams: Returning', #bodycams, 'bodycams')
    return bodycams
end)

-- View a specific bodycam
Bridge.registerCallback(resourceName .. ':server:viewBodycam', function(source, bodycamId)
    local src = source
    if not CheckAuth(src) then
        return { success = false, error = "Unauthorized" }
    end

    local bodycamData = bodycamInstances[bodycamId]
    if not bodycamData then
        return { success = false, error = "Bodycam not found" }
    end

    local targetSource = bodycamData.playerId
    if not targetSource then
        return { success = false, error = "Invalid target source" }
    end

    local targetPlayer = GetPlayerName(targetSource)
    if not targetPlayer then
        return { success = false, error = "Officer is no longer online" }
    end

    local targetPed = GetPlayerPed(targetSource)
    if not targetPed or targetPed == 0 then
        return { success = false, error = "Unable to access officer's bodycam" }
    end

    local coords = GetEntityCoords(targetPed)
    local heading = GetEntityHeading(targetPed)

    -- Start bodycam view for the requesting player
    TriggerClientEvent(resourceName .. ':client:startCameraView', src, {
        coords = coords,
        rotation = vector3(0.0, 0.0, heading),
        networkId = nil, -- No entity to hide for bodycams
        isBodycam = true,
        targetSource = targetSource
    })

    -- Track this viewer
    if not bodycamViewers[bodycamId] then
        bodycamViewers[bodycamId] = {}
    end
    bodycamViewers[bodycamId][src] = {
        startTime = os.time()
    }
    Bridge.debug('Added viewer', src, 'to bodycam', bodycamId)

    return {
        success = true,
        camera = {
            id = bodycamId,
            label = bodycamData.officerName .. " Bodycam",
            coords = coords,
            rotation = vector3(0.0, 0.0, heading)
        }
    }
end)

-- Clean up bodycam when player disconnects
AddEventHandler('playerDropped', function(reason)
    local playerId = source
    local bodycamId = tostring(playerId)

    if bodycamInstances[bodycamId] then
        bodycamInstances[bodycamId] = nil
        Bridge.debug('Cleaned up bodycam instance for disconnected player:', playerId)
    end

    -- Clean up any viewer entries for this player
    for bcId, viewers in pairs(bodycamViewers) do
        if viewers and viewers[playerId] then
            viewers[playerId] = nil
            Bridge.debug('Removed viewer', playerId, 'from bodycam', bcId, 'due to disconnect')
        end
    end
end)

-- Handle bodycam view deactivation
RegisterNetEvent(resourceName .. ':server:deactivateBodycam', function(bodycamId)
    local playerId = source
    if not CheckAuth(playerId) then return end
    Bridge.debug('Deactivating bodycam for player:', playerId, 'Bodycam ID:', bodycamId)

    if bodycamViewers[bodycamId] then
        Bridge.debug('Found viewer table for bodycam:', bodycamId)
        if bodycamViewers[bodycamId][playerId] then
            local viewDuration = os.time() - bodycamViewers[bodycamId][playerId].startTime
            bodycamViewers[bodycamId][playerId] = nil
            Bridge.debug('Player', playerId, 'stopped viewing bodycam', bodycamId, 'after', viewDuration, 'seconds')

            -- Clean up empty viewer table
            if next(bodycamViewers[bodycamId]) == nil then
                bodycamViewers[bodycamId] = nil
                Bridge.debug('Cleaned up empty viewer table for bodycam:', bodycamId)
            end
        else
            Bridge.debug('Player', playerId, 'was not found in viewers for bodycam:', bodycamId)
        end
    else
        Bridge.debug('No viewer table found for bodycam:', bodycamId)
    end
end)

-- Helper function to create bodycam for officer
local function createOfficerBodycam(playerId, playerData)
    local bodycamId = tostring(playerId)
    local officerName = playerData.charinfo.firstname .. ' ' .. playerData.charinfo.lastname

    bodycamInstances[bodycamId] = {
        id = bodycamId,
        officerName = officerName,
        callsign = (playerData.metadata and playerData.metadata.callsign) or 'Unknown',
        rank = (playerData.job and playerData.job.grade and playerData.job.grade.name) or 'Officer',
        playerId = playerId,
        isOnline = true,
        createdAt = os.time()
    }

    Bridge.debug('Created bodycam for officer:', officerName, 'ID:', bodycamId)
end

-- Helper function to remove bodycam for officer
local function removeOfficerBodycam(playerId)
    local bodycamId = tostring(playerId)

    if bodycamInstances[bodycamId] then
        bodycamInstances[bodycamId] = nil
        Bridge.debug('Removed bodycam for officer going off duty:', playerId)
    end
end

-- Duty change handler — listens to the framework's job-update event.
local function handleDutyChange(playerId, job)
    if not playerId or not job then return end
    if not IsPoliceJob(job.name, job.type) then return end

    if job.onduty then
        local Player = Bridge and Bridge.getPlayer(playerId)
        if Player and Player.PlayerData then
            createOfficerBodycam(playerId, Player.PlayerData)
        end
    else
        removeOfficerBodycam(playerId)
    end
end

-- qb-core and qbx_core both fire QBCore:Server:OnJobUpdate(source, newJob)
RegisterNetEvent(getBodycamConfig().DutyEvent or 'QBCore:Server:OnJobUpdate', function(source, job)
    handleDutyChange(source, job)
end)

-- Seed bodycams for officers already on duty when the resource starts.
CreateThread(function()
    Wait(5000)
    for _, player in pairs(Bridge and Bridge.getAllPlayers() or {}) do
        local pd = player.PlayerData
        if pd and pd.job and pd.job.onduty and IsPoliceJob(pd.job.name, pd.job.type) then
            createOfficerBodycam(pd.source, pd)
        end
    end

    local n = 0
    for _ in pairs(bodycamInstances) do n = n + 1 end
    Bridge.debug('Initialised ' .. n .. ' bodycams')
end)
