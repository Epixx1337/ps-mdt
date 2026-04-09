-- Exports

-- Check if a job is an LEO job (checks against Config.PoliceJobType from the core)
local function isLEOJob(jobName)
    if not jobName then
        return ps.getJobType() == Config.PoliceJobType
    end
    if Config.PoliceJobs then
        for _, job in ipairs(Config.PoliceJobs) do
            if tostring(job) == tostring(jobName) then
                return true
            end
        end
    end
    return false
end

exports('IsLEOJob', isLEOJob)

-- Check if MDT is open
exports('IsMDTOpen', function() return MDTOpen end)

-- Open MDT with export
exports('OpenMDT', function()
    OpenMDT()
end)

-- Close MDT (delegates to full CloseMDT which handles animation, controls, logout tracking)
exports('CloseMDT', function()
    CloseMDT()
end)

-- Open civilian MDT (profile + legislation view)
exports('openCivilianMDT', function()
    if MDTOpen then return end
    if ps.isDead() then
        ps.notify('You cannot access records right now', 'error')
        return
    end
    MDTOpen = true
    local playerData = ps.getPlayerData()
    SendNUI('setVisible', { visible = true, debugMode = Config.Debug })
    SendNUI('updateAuth', {
        authorized = true,
        playerData = playerData,
        isLEO = false,
        onDuty = true,
        isCivilian = true,
        jobType = 'civilian',
    })
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    toggleControls(true)
end)

-- Civilian MDT target points
CreateThread(function()
    local cfg = Config.CivilianTarget
    if not cfg or not cfg.enabled then return end
    if not Config.CivilianAccess or not Config.CivilianAccess.enabled then return end

    -- Wait for ox_target to be available
    if GetResourceState('ox_target') ~= 'started' then return end

    for i, loc in ipairs(cfg.locations or {}) do
        exports.ox_target:addBoxZone({
            coords = loc.coords,
            size = loc.size or vector3(1.0, 1.0, 2.0),
            rotation = loc.rotation or 0.0,
            debug = Config.Debug,
            options = {
                {
                    name = 'ps-mdt:civilian_access_' .. i,
                    label = cfg.label or 'Access Public Records',
                    icon = cfg.icon or 'fas fa-desktop',
                    onSelect = function()
                        exports[GetCurrentResourceName()]:openCivilianMDT()
                    end,
                },
            },
        })
    end

    ps.debug('Registered ' .. #(cfg.locations or {}) .. ' civilian MDT target(s)')
end)