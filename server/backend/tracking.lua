local resourceName = tostring(GetCurrentResourceName())

local function getOfficerTrackers()
    local officers = {}
    if not Bridge then return officers end

    for _, player in pairs(Bridge.getAllPlayers()) do
        local data = player.PlayerData
        if data and data.job and data.job.onduty and IsPoliceJob(data.job.name, data.job.type) then
            local ped = GetPlayerPed(data.source)
            if ped and ped ~= 0 then
                local coords = GetEntityCoords(ped)
                officers[#officers + 1] = {
                    citizenid = data.citizenid,
                    name      = (data.charinfo.firstname .. ' ' .. data.charinfo.lastname),
                    callsign  = data.metadata and data.metadata.callsign or nil,
                    rank      = data.job.grade and data.job.grade.name or 'Officer',
                    coords    = { x = coords.x, y = coords.y, z = coords.z },
                    heading   = GetEntityHeading(ped),
                }
            end
        end
    end
    return officers
end

local function getVehicleTrackers()
    local vehicles, seen = {}, {}
    if not Bridge then return vehicles end

    for _, player in pairs(Bridge.getAllPlayers()) do
        local data = player.PlayerData
        if data and data.job and data.job.onduty and IsPoliceJob(data.job.name, data.job.type) then
            local ped = GetPlayerPed(data.source)
            if ped and ped ~= 0 then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh and veh ~= 0 and not seen[veh] then
                    seen[veh] = true
                    local coords = GetEntityCoords(veh)
                    vehicles[#vehicles + 1] = {
                        plate   = GetVehicleNumberPlateText(veh),
                        coords  = { x = coords.x, y = coords.y, z = coords.z },
                        heading = GetEntityHeading(veh),
                    }
                end
            end
        end
    end
    return vehicles
end

local function getBodycamTrackers()
    local bodycams = {}
    if not Bridge then return bodycams end

    for _, player in pairs(Bridge.getAllPlayers()) do
        local data = player.PlayerData
        if data and data.job and data.job.onduty and IsPoliceJob(data.job.name, data.job.type) then
            local ped = GetPlayerPed(data.source)
            if ped and ped ~= 0 then
                local coords = GetEntityCoords(ped)
                bodycams[#bodycams + 1] = {
                    citizenid = data.citizenid,
                    name      = (data.charinfo.firstname .. ' ' .. data.charinfo.lastname),
                    callsign  = data.metadata and data.metadata.callsign or nil,
                    coords    = { x = coords.x, y = coords.y, z = coords.z },
                    heading   = GetEntityHeading(ped),
                }
            end
        end
    end
    return bodycams
end

Bridge.registerCallback(resourceName .. ':server:getTracking', function(source)
    local src = source
    if not CheckAuth(src) then return { officers = {}, vehicles = {}, bodycams = {} } end

    return {
        officers = getOfficerTrackers(),
        vehicles = getVehicleTrackers(),
        bodycams = getBodycamTrackers(),
    }
end)
