local commands = {}

commands[Glide.CMD_CREATE_EXPLOSION] = function()
    local pos = net.ReadVector()
    local normal = net.ReadVector()
    local explosionType = net.ReadUInt( 2 )

    Glide.CreateExplosion( pos, normal, explosionType )
end

commands[Glide.CMD_INCOMING_DANGER] = function()
    local dangerType = net.ReadUInt( 3 )

    if dangerType == Glide.DANGER_TYPE.LOCK_ON then
        Glide.LockOnHandler:OnIncomingLockOn()

    elseif dangerType == Glide.DANGER_TYPE.MISSILE then
        Glide.LockOnHandler:OnIncomingMissile( net.ReadUInt( 32 ) )

        if IsValid( Glide.currentVehicle ) and Glide.IsAircraft( Glide.currentVehicle ) then
            Glide.ShowKeyTip(
                "#glide.notify.tip.countermeasures",
                Glide.Config.binds["aircraft_controls"]["countermeasures"],
                "materials/glide/icons/rocket.png"
            )
        end
    end
end

commands[Glide.CMD_VIEW_PUNCH] = function()
    Glide.Camera:ViewPunch( net.ReadFloat() )
end

commands[Glide.CMD_NOTIFY] = function()
    local data = Glide.ReadTable()

    if string.sub( data.text, 1, 1 ) == "#" then
        data.text = language.GetPhrase( data.text )
    end

    Glide.Notify( data )
end

commands[Glide.CMD_SYNC_SOUND_ENTITY_MODIFIER] = function()
    local modEntity = net.ReadEntity()
    if not IsValid( modEntity ) then return end

    local modType = net.ReadUInt( 3 )
    local modSize = net.ReadUInt( 16 )
    local modData = net.ReadData( modSize )

    if not modData then return end

    modData = util.Decompress( modData )
    if not modData then return end

    local shouldClear = Glide.FromJSON( modData ).clear == true

    -- Entity modifier: Engine Stream preset
    if modType == 1 then
        if shouldClear then
            modEntity.streamJSONOverride = nil
        else
            modEntity.streamJSONOverride = modData
        end

        if modEntity.stream then
            modEntity.stream:Destroy()
            modEntity.stream = nil
        end

    -- Entity modifier: Misc. Sounds
    elseif modType == 2 then

        -- Stop existing sounds
        local sounds = modEntity.sounds

        if sounds then
            for k, snd in pairs( sounds ) do
                snd:Stop()
                sounds[k] = nil
            end
        end

        local data = Glide.FromJSON( modData )
        local originalSounds = modEntity._originalSounds or {}
        modEntity._originalSounds = originalSounds

        -- Restore original sounds
        for k, path in pairs( originalSounds ) do
            modEntity[k] = path
        end

        if shouldClear then return end

        -- Apply custom sounds
        for k, path in pairs( data ) do
            originalSounds[k] = modEntity[k]
            modEntity[k] = path
        end
    end
end

net.Receive( "glide.command", function()
    local cmd = net.ReadUInt( Glide.CMD_SIZE )

    if commands[cmd] then
        commands[cmd]()
    end
end )
