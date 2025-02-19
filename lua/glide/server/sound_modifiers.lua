--[[
    Keep track of entities with sound or engine stream modifiers, and
    sync their values with players that have loaded and spawned in the server.
]]

local active = Glide.activeSoundModifiers or {}
Glide.activeSoundModifiers = active

local function TrackVehicle( vehicle, modType, modData )
    modData = util.Compress( modData )

    local index = #active + 1

    -- Check if the vehicle is on the mods list already
    for i, mod in ipairs( active ) do
        if mod.vehicle == vehicle and mod.type == modType then
            index = i
            break
        end
    end

    active[index] = {
        vehicle = vehicle,
        type = modType,
        data = modData,
        synced = {}
    }
end

local WriteUInt = net.WriteUInt
local WriteData = net.WriteData
local WriteEntity = net.WriteEntity
local Send = net.Send

local function SendEntityModifierTo( ply, mod )
    local size = #mod.data

    Glide.StartCommand( Glide.CMD_SYNC_SOUND_ENTITY_MODIFIER, false )
    WriteEntity( mod.vehicle )
    WriteUInt( mod.type, 3 )
    WriteUInt( size, 16 )
    WriteData( mod.data )
    Send( ply )
end

local Remove = table.remove

timer.Create( "Glide.UpdateModSync", 1, 0, function()
    local players = player.GetHumans()

    -- Reverse loop to cleanup invalid entities
    local mod, synced

    for i = #active, 1, -1 do
        mod = active[i]

        if IsValid( mod.vehicle ) then
            -- Sync modifiers with clients
            for _, ply in ipairs( players ) do
                synced = mod.synced

                -- If we have not synced this modifier to this player yet...
                if not synced[ply] and ply.GlideLoaded then
                    synced[ply] = true
                    SendEntityModifierTo( ply, mod )
                end
            end
        else
            -- Remove invalid entries
            Remove( active, i )
        end
    end
end )

hook.Add( "PlayerDisconnected", "Glide.CleanupModSync", function( ply )
    for _, mod in ipairs( active ) do
        mod.synced[ply] = nil
    end
end )

-- Since `PlayerInitialSpawn` is called before the player is ready
-- to receive net events, we have to use `ClientSignOnStateChanged` instead.
hook.Add( "ClientSignOnStateChanged", "Glide.MarkPlayerAsLoaded", function( user, _, new )
    if new ~= SIGNONSTATE_FULL then return end

    -- We can only retrieve the player entity after this hook runs, so lets use a timer.
    -- It could have been 0 seconds, its just higher here to put less strain on the network.
    timer.Simple( 3, function()
        local ply = Player( user )

        if IsValid( ply ) and not ply:IsBot() then
            ply.GlideLoaded = true
        end
    end )
end )

local SUPPORTED_VEHICLE_TYPES = {
    [Glide.VEHICLE_TYPE.CAR] = true,
    [Glide.VEHICLE_TYPE.MOTORCYCLE] = true,
    [Glide.VEHICLE_TYPE.TANK] = true
}

local function IsGlideVehicle( ent )
    return IsValid( ent ) and ent.IsGlideVehicle and SUPPORTED_VEHICLE_TYPES[ent.VehicleType]
end

--[[
    Register a entity modifier to save an Engine Stream preset
]]

function Glide.ApplyEngineStreamModifier( ply, ent, data )
    if not IsGlideVehicle( ent ) then return false end

    data = data.json
    if type( data ) ~= "string" then return end
    if #data > Glide.MAX_JSON_SIZE then return end

    data = Glide.FromJSON( data )
    if not data then return end

    local success, message = Glide.ValidateStreamData( data )

    if not success then
        Glide.Print( "Failed to apply engine stream entity modifier from %s <%s>: %s", ply:Nick(), ply:SteamID(), message )
        return false
    end

    data = Glide.ToJSON( data )
    TrackVehicle( ent, 1, data )

    duplicator.StoreEntityModifier( ent, "glide_engine_stream", { json = data } )
end

duplicator.RegisterEntityModifier( "glide_engine_stream", Glide.ApplyEngineStreamModifier )

function Glide.RemoveEngineStreamModifier( ent )
    if not IsGlideVehicle( ent ) then return end

    duplicator.ClearEntityModifier( ent, "glide_engine_stream" )
    TrackVehicle( ent, 1, Glide.ToJSON( { clear = true } ) )
end

--[[
    Register a entity modifier to apply misc. sounds
]]

function Glide.ApplyMiscSoundsModifier( ply, ent, data )
    if not IsGlideVehicle( ent ) then return false end

    data = data.json
    if type( data ) ~= "string" then return end
    if #data > Glide.MAX_JSON_SIZE then return end

    data = Glide.FromJSON( data )
    if not data then return end

    local success, message = Glide.ValidateMiscSoundData( data )

    if not success then
        Glide.Print( "Failed to apply misc. sounds entity modifier from %s <%s>: %s", ply:Nick(), ply:SteamID(), message )
        return false
    end

    data = Glide.ToJSON( data )
    TrackVehicle( ent, 2, data )

    duplicator.StoreEntityModifier( ent, "glide_misc_sounds", { json = data } )
end

duplicator.RegisterEntityModifier( "glide_misc_sounds", Glide.ApplyMiscSoundsModifier )

function Glide.RemoveMiscSoundsModifier( ent )
    if not IsGlideVehicle( ent ) then return end

    duplicator.ClearEntityModifier( ent, "glide_misc_sounds" )
    TrackVehicle( ent, 2, Glide.ToJSON( { clear = true } ) )
end
