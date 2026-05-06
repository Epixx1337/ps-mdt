
-- Command to set the Message of the Day (MOTD) - stores as a bulletin
local motdCommandName = (Config and Config.Commands and Config.Commands.MessageOfTheDay and Config.Commands.MessageOfTheDay.command) or 'motd'
local motdEnabled = Config and Config.Commands and Config.Commands.MessageOfTheDay and Config.Commands.MessageOfTheDay.enabled ~= false

if motdEnabled then
    RegisterCommand(motdCommandName, function(source, args, rawCommand)
        local src = source
        if not src or src == 0 then return end

        if not IsPoliceJob(Bridge.getJobName(src), Bridge.getJobType(src)) or not Bridge.isBoss(src) then
            Bridge.notify(src, 'You do not have permission to use this command', 'error')
            return
        end

        local newMessage = table.concat(args, " ")
        if not newMessage or newMessage == "" then
            Bridge.notify(src, 'Please provide a message', 'error')
            return
        end

        -- Remove any existing MOTD bulletin and insert the new one
        pcall(MySQL.query.await, "DELETE FROM mdt_bulletins WHERE content LIKE '[MOTD]%'")
        local ok, err = pcall(MySQL.insert.await, 'INSERT INTO mdt_bulletins (content) VALUES (?)', { '[MOTD] ' .. newMessage })
        if not ok then
            Bridge.warn('Failed to save MOTD: ' .. tostring(err))
            Bridge.notify(src, 'Failed to save Message of the Day', 'error')
            return
        end

        Cache.invalidate('dashboard:bulletins')
        Bridge.notify(src, 'Message of the Day updated successfully', 'success')

        -- Notify online police officers
        local players = Bridge.getAllPlayers()
        for _, player in pairs(players) do
            if IsPoliceJob(Bridge.getJobName(player), Bridge.getJobType(player)) and src ~= player then
                Bridge.notify(player, 'Message of the Day has been updated', 'info')
            end
        end
    end, false)
end
