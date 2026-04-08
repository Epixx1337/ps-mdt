--- Resolve which job list and job type to use for the roster based on the requesting player's department.
local function resolveRosterJobs(source)
    local playerJobType = ps.getJobType(source)
    local playerJobName = ps.getJobName(source)

    if playerJobType == Config.MedicalJobType then
        return (Config.MedicalJobs or { 'ambulance' }), Config.MedicalJobType
    end

    if playerJobType == Config.DojJobType or (Config.DojJobs and playerJobName) then
        for _, name in ipairs(Config.DojJobs or {}) do
            if name == playerJobName then
                return Config.DojJobs, Config.DojJobType
            end
        end
    end

    return (Config.PoliceJobs or { 'police' }), Config.PoliceJobType
end

--- Check if a job name or type matches a given job list and job type.
local function isMatchingJob(jobName, jobType, jobList, targetJobType)
    if jobType and targetJobType and tostring(jobType) == tostring(targetJobType) then
        return true
    end
    if jobName and jobList then
        local check = tostring(jobName)
        for _, job in ipairs(jobList) do
            if tostring(job) == check then
                return true
            end
        end
    end
    return false
end

local function getRadioChannel(playerSource)
    if not playerSource then return 0 end
    local channel = 0
    pcall(function()
        channel = Player(playerSource).state.radioChannel or 0
    end)
    return tonumber(channel) or 0
end

local function getCertifications(citizenid, filterJobType)
    EnsureProfileExists(citizenid)

    local profile = MySQL.single.await('SELECT certifications FROM mdt_profiles WHERE citizenid = ?', { citizenid })
    if not profile then
        return {}
    end

    if profile.certifications and profile.certifications ~= '' then
        local ok, decoded = pcall(json.decode, profile.certifications)
        if ok and type(decoded) == 'table' then
            if not filterJobType then
                return decoded
            end
            -- Filter certifications to only show tags matching the viewer's department
            local allowedTags = {}
            local tagRows = MySQL.query.await(
                'SELECT name FROM mdt_tags WHERE type IN (?, ?) AND (job_type = ? OR job_type = ?)',
                { 'officer', 'both', filterJobType, 'all' }
            ) or {}
            for _, row in ipairs(tagRows) do
                allowedTags[row.name] = true
            end
            local filtered = {}
            for _, cert in ipairs(decoded) do
                if allowedTags[cert] then
                    filtered[#filtered + 1] = cert
                end
            end
            return filtered
        end
    end

    return {}
end

local function buildRosterFromFramework(jobList, targetJobType)
    local rosterList = {}
    local activeUnits = {}
    local members = {}

    -- Use GetGroupMembers if available (QBox)
    for _, jobName in ipairs(jobList) do
        local groupMembers = Framework.GetGroupMembers(jobName, 'job') or {}
        for _, member in ipairs(groupMembers) do
            if member.citizenid then
                members[member.citizenid] = true
            end
        end
    end

    for _, player in ipairs(Framework.GetAllPlayers()) do
        local data = player.PlayerData or nil
        if data and data.job then
            if isMatchingJob(data.job.name, data.job.type, jobList, targetJobType) then
                members[data.citizenid] = true
            end
        end
    end

    for _, row in ipairs(MySQL.query.await('SELECT citizenid, job FROM players', {}) or {}) do
        local job = row.job and json.decode(row.job) or {}
        if isMatchingJob(job.name, job.type, jobList, targetJobType) then
            members[row.citizenid] = true
        end
    end

    for citizenid, _ in pairs(members) do
        local onlinePlayer = Framework.GetPlayerByCitizenId(citizenid)
        local player = onlinePlayer or Framework.GetOfflinePlayer(citizenid)
        if player and player.PlayerData then
            local data = player.PlayerData
            local job = data.job or {}
            local callsign = data.metadata and data.metadata.callsign or 'N/A'
            local fullname = data.charinfo and (data.charinfo.firstname .. ' ' .. data.charinfo.lastname) or 'Unknown'
            local rank = job.grade and job.grade.name or 'Officer'
            local department = job.name or 'police'
            local certifications = getCertifications(citizenid, targetJobType)

            local onlineSrc = onlinePlayer and (onlinePlayer.PlayerData and onlinePlayer.PlayerData.source or onlinePlayer.source) or nil
            rosterList[#rosterList + 1] = {
                id = #rosterList + 1,
                citizenid = citizenid,
                callsign = callsign,
                firstName = data.charinfo and data.charinfo.firstname or 'N/A',
                lastName = data.charinfo and data.charinfo.lastname or 'N/A',
                rank = rank,
                department = department,
                status = (onlinePlayer and job.onduty) and 'On Duty' or 'Off Duty',
                certifications = certifications,
                badgeNumber = callsign,
                radioChannel = getRadioChannel(onlineSrc)
            }

            if rosterList[#rosterList].status == 'On Duty' then
                activeUnits[#activeUnits + 1] = {
                    id = rosterList[#rosterList].id,
                    badgeNumber = rosterList[#rosterList].badgeNumber,
                    callsign = rosterList[#rosterList].callsign,
                    firstName = rosterList[#rosterList].firstName,
                    lastName = rosterList[#rosterList].lastName,
                }
            end
        end
    end

    return {
        roster = rosterList,
        activeUnits = activeUnits
    }
end

local function checkDuty(citizenid, jobList, targetJobType)
    local player = ps.getPlayerByIdentifier(citizenid)
    if not player then return 'Off Duty' end

    local src = player.source or (player.PlayerData and player.PlayerData.source)
    if not src then return 'Off Duty' end

    if isMatchingJob(ps.getJobName(src), ps.getJobType(src), jobList, targetJobType) and ps.getJobDuty(src) then
        return 'On Duty'
    end
    return 'Off Duty'
end

ps.registerCallback('ps-mdt:server:getRosterList', function(source)
    local jobList, targetJobType = resolveRosterJobs(source)

    if Framework and Framework.isQBX then
        return buildRosterFromFramework(jobList, targetJobType)
    end

    local rosterList = {}
    local activeUnits = {}
    local jobLookup = {}
    for _, jobName in ipairs(jobList) do
        jobLookup[tostring(jobName)] = true
    end

    local employees = {}
    if GetResourceState('ps-multijob') == 'started' and exports['ps-multijob'] then
        for _, jobName in ipairs(jobList) do
            local list = exports['ps-multijob']:getEmployees(jobName) or {}
            for _, employee in pairs(list) do
                if employee and employee.citizenid then
                    employees[employee.citizenid] = employee
                end
            end
        end
    end

    for _, citizen in pairs(MySQL.query.await('SELECT citizenid, charinfo, job, metadata FROM players', {}) or {}) do
        local citizenid = citizen.citizenid
        local charinfo = citizen.charinfo and json.decode(citizen.charinfo) or {}
        local job = citizen.job and json.decode(citizen.job) or {}
        local metadata = citizen.metadata and json.decode(citizen.metadata) or {}
        local jobName = job.name and tostring(job.name) or nil
        local isMatch = (jobName and jobLookup[jobName]) or (job.type and targetJobType and tostring(job.type) == tostring(targetJobType))
        if isMatch then
            local employee = employees[citizenid] or {}
            local callsign = metadata.callsign or 'N/A'
            local firstName = charinfo.firstname or 'N/A'
            local lastName = charinfo.lastname or 'N/A'
            local rank = job.grade and job.grade.name or employee.grade and ps.getSharedJobGradeData(jobName or 'police', employee.grade, 'name') or 'Officer'
            local status = checkDuty(citizenid, jobList, targetJobType)
            local onlinePlayer = ps.getPlayerByIdentifier(citizenid)
            local onlineSrc = onlinePlayer and (onlinePlayer.source or (onlinePlayer.PlayerData and onlinePlayer.PlayerData.source)) or nil
            rosterList[#rosterList + 1] = {
                id = #rosterList + 1,
                citizenid = citizenid,
                callsign = callsign,
                firstName = firstName,
                lastName = lastName,
                rank = rank,
                department = jobName or employee.job or 'unknown',
                status = status,
                certifications = getCertifications(citizenid, targetJobType),
                badgeNumber = callsign,
                radioChannel = getRadioChannel(onlineSrc)
            }
            if status == 'On Duty' then
                activeUnits[#activeUnits + 1] = {
                    id = rosterList[#rosterList].id,
                    badgeNumber = rosterList[#rosterList].badgeNumber,
                    callsign = rosterList[#rosterList].callsign,
                    firstName = rosterList[#rosterList].firstName,
                    lastName = rosterList[#rosterList].lastName,
                }
            end
        end
    end
    return {
        roster = rosterList,
        activeUnits = activeUnits
    }
end)

-- Get available officer tags/certifications (filtered by job type)
ps.registerCallback('ps-mdt:server:getOfficerTags', function(source)
    local src = source
    if not CheckAuth(src) then return {} end

    local jobType = ps.getJobType(src)
    local rows
    if jobType and (jobType == 'leo' or jobType == 'ems' or jobType == 'doj') then
        rows = MySQL.query.await([[
            SELECT id, name, color FROM mdt_tags
            WHERE type IN ('officer', 'both')
              AND (job_type = ? OR job_type = 'all' OR job_type IS NULL)
            ORDER BY name ASC
        ]], { jobType })
    else
        rows = MySQL.query.await([[
            SELECT id, name, color FROM mdt_tags
            WHERE type IN ('officer', 'both')
            ORDER BY name ASC
        ]])
    end
    return rows or {}
end)

-- Update officer certifications
ps.registerCallback('ps-mdt:server:updateOfficerCertifications', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
    if not CheckPermission(src, 'roster_manage_certifications') then
        return { success = false, message = 'No permission to manage certifications' }
    end

    payload = payload or {}
    local citizenid = payload.citizenid
    local certifications = payload.certifications

    if not citizenid or type(certifications) ~= 'table' then
        return { success = false, message = 'Invalid payload' }
    end

    EnsureProfileExists(citizenid)

    local encoded = json.encode(certifications)
    MySQL.update.await('UPDATE mdt_profiles SET certifications = ? WHERE citizenid = ?', { encoded, citizenid })

    return { success = true }
end)

-- Get job grades for a specific department
ps.registerCallback('ps-mdt:server:getJobGrades', function(source, payload)
    local src = source
    if not CheckAuth(src) then return {} end
    if not CheckPermission(src, 'roster_manage_officers') then return {} end

    payload = payload or {}
    local jobName = payload.job or 'police'

    local jobData = ps.getSharedJob(jobName)
    if not jobData or not jobData.grades then return {} end

    local grades = {}
    for gradeKey, gradeValue in pairs(jobData.grades) do
        grades[#grades + 1] = {
            grade = tonumber(gradeKey) or 0,
            name = gradeValue.name or ('Grade ' .. gradeKey),
            isBoss = gradeValue.isboss == true or gradeValue.isBoss == true or gradeValue.boss == true,
        }
    end

    table.sort(grades, function(a, b) return a.grade < b.grade end)
    return grades
end)

-- Promote/demote an officer (change their job grade)
ps.registerCallback('ps-mdt:server:promoteOfficer', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
    if not CheckPermission(src, 'roster_manage_officers') then
        return { success = false, message = 'No permission to manage officers' }
    end

    payload = payload or {}
    local citizenid = payload.citizenid
    local jobName = payload.job
    local newGrade = tonumber(payload.grade)

    if not citizenid or not jobName or not newGrade then
        return { success = false, message = 'Missing required fields' }
    end

    -- Validate the grade exists
    local gradeData = ps.getSharedJobGrade(jobName, newGrade)
    if not gradeData then
        return { success = false, message = 'Invalid grade for this job' }
    end

    -- Find the target player (must be online for QBCore SetJob)
    local targetPlayer = ps.getPlayerByIdentifier(citizenid)
    if not targetPlayer then
        return { success = false, message = 'Officer must be online to change rank' }
    end

    local targetSrc = targetPlayer.source or (targetPlayer.PlayerData and targetPlayer.PlayerData.source)
    if not targetSrc then
        return { success = false, message = 'Could not resolve officer source' }
    end

    -- Don't allow changing your own rank
    if targetSrc == src then
        return { success = false, message = 'You cannot change your own rank' }
    end

    ps.setJob(targetSrc, jobName, newGrade)

    local gradeName = gradeData.name or ('Grade ' .. newGrade)

    if ps.auditLog then
        ps.auditLog(src, 'officer_promoted', 'officers', citizenid, {
            job = jobName,
            grade = newGrade,
            gradeName = gradeName,
        })
    end

    return { success = true, message = 'Officer rank updated to ' .. gradeName }
end)

-- Fire an officer (set their job to unemployed)
ps.registerCallback('ps-mdt:server:fireOfficer', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
    if not CheckPermission(src, 'roster_manage_officers') then
        return { success = false, message = 'No permission to manage officers' }
    end

    payload = payload or {}
    local citizenid = payload.citizenid

    if not citizenid then
        return { success = false, message = 'Missing citizen ID' }
    end

    local targetPlayer = ps.getPlayerByIdentifier(citizenid)
    if not targetPlayer then
        return { success = false, message = 'Officer must be online to be terminated' }
    end

    local targetSrc = targetPlayer.source or (targetPlayer.PlayerData and targetPlayer.PlayerData.source)
    if not targetSrc then
        return { success = false, message = 'Could not resolve officer source' }
    end

    -- Don't allow firing yourself
    if targetSrc == src then
        return { success = false, message = 'You cannot fire yourself' }
    end

    ps.setJob(targetSrc, 'unemployed', 0)

    if ps.auditLog then
        ps.auditLog(src, 'officer_fired', 'officers', citizenid, {})
    end

    return { success = true, message = 'Officer has been terminated' }
end)

-- Update officer callsign (wrapper around existing setCallsign for NUI)
ps.registerCallback('ps-mdt:server:updateOfficerCallsign', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end
    if not CheckPermission(src, 'roster_manage_officers') then
        return { success = false, message = 'No permission to manage officers' }
    end

    payload = payload or {}
    local citizenid = payload.citizenid
    local newCallsign = payload.callsign

    if not citizenid or not newCallsign or newCallsign == '' then
        return { success = false, message = 'Missing citizen ID or callsign' }
    end

    -- Use the existing setCallsign callback logic
    if not Framework then
        return { success = false, message = 'Core framework not available' }
    end

    local Player = Framework.GetPlayerByCitizenId(citizenid)
    if not Player then
        return { success = false, message = 'Officer must be online to update callsign' }
    end

    Framework.SetMetaData(Player.PlayerData.source, 'callsign', newCallsign)

    local resourceName = GetCurrentResourceName()
    TriggerClientEvent(resourceName .. ':client:updateCallsign', Player.PlayerData.source, newCallsign)

    MySQL.update.await('UPDATE mdt_profiles SET callsign = ? WHERE citizenid = ?', { newCallsign, citizenid })

    if ps.auditLog then
        ps.auditLog(src, 'callsign_changed', 'officers', citizenid, { callsign = newCallsign })
    end

    return { success = true, message = 'Callsign updated to ' .. newCallsign }
end)
