local resourceName = tostring(GetCurrentResourceName())

-- Detect jail resource
local jailType = Config.Jail or 'auto'
if jailType == 'auto' then
    if GetResourceState('xt-prison') == 'started' then
        jailType = 'xt-prison'
    else
        jailType = 'qb-prison'
    end
end

local function sendPlayerToJail(src, targetSource, citizenId, sentence)
    if jailType == 'xt-prison' then
        local sent = lib.callback.await('xt-prison:client:enterJail', targetSource, sentence)
        if not sent then
            return false, 'xt-prison failed to jail player'
        end
        return true
    end

    -- Default: qb-prison / standard QBCore jail
    if not Bridge then
        return false, 'Core framework not available'
    end

    local OtherPlayer = Bridge.GetPlayer(targetSource)
    if not OtherPlayer then
        return false, 'Could not find target player'
    end

    local currentDate = os.date('*t')
    if currentDate.day == 31 then
        currentDate.day = 30
    end

    Bridge.SetMetaData(targetSource, 'injail', sentence)
    Bridge.SetMetaData(targetSource, 'criminalrecord', {
        ['hasRecord'] = true,
        ['date'] = currentDate
    })
    TriggerClientEvent('police:client:SendToJail', targetSource, sentence)
    return true
end

-- Send to Jail
Bridge.registerCallback(resourceName .. ':server:sendToJail', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end

    payload = payload or {}
    local citizenId = payload.citizenId
    local sentence = tonumber(payload.sentence)

    if not citizenId or not sentence or sentence <= 0 then
        return { success = false, message = 'Missing citizen ID or invalid sentence' }
    end

    local targetPlayer = Bridge.getPlayerByIdentifier(citizenId)
    if not targetPlayer then
        return { success = false, message = 'Player must be online to send to jail' }
    end

    local targetSource = targetPlayer.source or (targetPlayer.PlayerData and targetPlayer.PlayerData.source)
    if not targetSource then
        return { success = false, message = 'Could not resolve player source' }
    end

    local success, err = sendPlayerToJail(src, targetSource, citizenId, sentence)
    if not success then
        return { success = false, message = err or 'Failed to send to jail' }
    end

    Bridge.notify(src, 'Sent to jail for ' .. sentence .. ' months', 'success')

    if Bridge.auditLog then
        Bridge.auditLog(src, 'sent_to_jail', 'citizen', citizenId, {
            sentence = sentence,
        })
    end

    return { success = true, message = 'Sent to jail for ' .. sentence .. ' months' }
end)

Bridge.registerCallback(resourceName .. ':server:giveCitation', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end

    payload = payload or {}
    local citizenId = payload.citizenId
    local fine = tonumber(payload.fine) or 0
    local reportId = payload.reportId

    if not citizenId then
        return { success = false, message = 'Missing citizen ID' }
    end
    if fine <= 0 then
        return { success = false, message = 'Invalid fine amount' }
    end

    local Player = Bridge.getPlayerByIdentifier(citizenId)
    if not Player then
        return { success = false, message = 'Player must be online to issue a fine' }
    end

    local playerSrc = Player.source or (Player.PlayerData and Player.PlayerData.source)
    if not playerSrc then
        return { success = false, message = 'Could not resolve player source' }
    end

    local removed = Bridge.removeMoney(playerSrc, 'bank', fine, 'mdt-fine')
    if not removed then
        return { success = false, message = 'Could not deduct fine (insufficient funds)' }
    end

    Bridge.notify(playerSrc, '$' .. fine .. ' fine deducted from your bank account', 'error')
    Bridge.notify(src, '$' .. fine .. ' fine issued successfully', 'success')

    if Bridge.auditLog then
        local officerName = Bridge.getPlayerName(src) or 'Unknown Officer'
        Bridge.auditLog(src, 'fine_issued', 'citizen', citizenId, {
            fine = fine,
            reportId = reportId,
            officerName = officerName,
        })
    end

    return { success = true, message = '$' .. fine .. ' fine issued' }
end)
