-- Sound definitions
local MDTSounds = {
    open = {
        audioName = 'ATM_WINDOW',
        audioRef = 'HUD_FRONTEND_DEFAULT_SOUNDSET'
    },
    close = {
        audioName = 'BACK',
        audioRef = 'HUD_FRONTEND_DEFAULT_SOUNDSET'
    },
    buttonClick = {
        audioName = 'SELECT',
        audioRef = 'HUD_FRONTEND_DEFAULT_SOUNDSET'
    },
}

-- Play sound based on input
function PlayMDTSound(soundType)
    if not MDTSounds[soundType] then
        Bridge.debug('Unknown MDT sound type:', soundType)
        return
    end

    local sound = MDTSounds[soundType]
    Bridge.playSound({
        audioName = sound.audioName,
        audioRef = sound.audioRef
    })

    Bridge.debug('Playing MDT sound:', soundType)
end