-- Max. Engine Stream layers
Glide.MAX_STREAM_LAYERS = 8

-- Default Engine Stream parameters
local DEFAULT_STREAM_PARAMS = {
    pitch = 1,
    volume = 1,
    fadeDist = 1500,

    redlineFrequency = 55,
    redlineStrength = 0.2,

    wobbleFrequency = 25,
    wobbleStrength = 0.13
}

Glide.DEFAULT_STREAM_PARAMS = DEFAULT_STREAM_PARAMS

function Glide.ValidateStreamData( data )
    if type( data ) ~= "table" then
        return false, "Preset is not a table!"
    end

    local keyValues = data.kv

    if keyValues then
        if type( keyValues ) ~= "table" then
            return false, "Preset does not have valid key-value data!"
        end

        for k, v in pairs( keyValues ) do
            if not DEFAULT_STREAM_PARAMS[k] or type( v ) ~= "number" then
                data[k] = nil -- If invalid, just remove KV pair
            end
        end
    end

    local layers = data.layers

    if type( layers ) ~= "table" then
        return false, "Preset does not have valid layer data!"
    end

    local p, c
    local count, max = 0, Glide.MAX_STREAM_LAYERS

    for id, layer in pairs( layers ) do
        if type( layer ) ~= "table" then
            return false, "Preset does not look like sound preset data!"
        end

        p = layer.path
        c = layer.controllers

        if
            type( id ) ~= "string" or
            type( p ) ~= "string" or
            type( c ) ~= "table"
        then
            return false, "Preset does not look like sound preset data!"
        end

        count = count + 1

        if count >= max then
            return false, "Preset data has too many layers!"
        end
    end

    return true
end

-- Misc. sound categories
Glide.MISC_SOUND_CATEGORIES = {
    {
        label = "#tool.glide_misc_sounds.category.engine",
        acceptGlideSoundPresets = true,
        keys = {
            "StartSound",
            "StartTailSound",
            "StartedSound",
            "StoppedSound",
            "ExhaustPopSound"
        }
    },
    {
        label = "#tool.glide_misc_sounds.category.alarms",
        acceptGlideSoundPresets = false,
        keys = {
            "HornSound",
            "ReverseSound",
            "SirenLoopSound"
        }
    },
    {
        label = "#tool.glide_misc_sounds.category.turbo",
        acceptGlideSoundPresets = false,
        keys = {
            "TurboLoopSound",
            "TurboBlowoffSound"
        }
    },
    {
        label = "#tool.glide_misc_sounds.category.brakes",
        acceptGlideSoundPresets = false,
        keys = {
            "BrakeReleaseSound",
            "BrakeSqueakSound"
        }
    }
}

function Glide.GetAllMiscSoundKeys()
    local keys, i = {}, 0

    for _, category in ipairs( Glide.MISC_SOUND_CATEGORIES ) do
        for _, key in ipairs( category.keys ) do
            i = i + 1
            keys[i] = key
        end
    end

    return keys
end

function Glide.ValidateMiscSoundData( data )
    if type( data ) ~= "table" then
        return false, "Preset is not a table!"
    end

    local validKeys = {}

    for _, category in ipairs( Glide.MISC_SOUND_CATEGORIES ) do
        for _, key in ipairs( category.keys ) do
            validKeys[key] = true
        end
    end

    for k, path in pairs( data ) do
        if not validKeys[k] then
            return false, "Preset contains invalid key(s)!"
        end

        if type( path ) ~= "string" then
            return false, "Preset contains invalid file path(s)!"
        end
    end

    return true
end

Glide.MAX_GEAR = 8

local Clamp = math.Clamp

function Glide.ClampGearRatio( ratio )
    return Clamp( ratio, 0.05, 4.0 )
end

local Type = type
local ClampGearRatio = Glide.ClampGearRatio

function Glide.ValidateTransmissionData( data )
    local cleanData = {
        [0] = 0 -- Neutral, this value does nothing
    }

    -- Check if the data has a valid reverse ratio
    if Type( data[-1] ) == "number" then
        cleanData[-1] = ClampGearRatio( data[-1] )
    end

    -- Check if the data has sequential indexes
    local index = 0
    local max = Glide.MAX_GEAR

    while index < max do
        index = index + 1

        if Type( data[index] ) == "number" then
            cleanData[index] = ClampGearRatio( data[index] )
        else
            break
        end
    end

    return cleanData
end

function Glide.IsValidModel( model )
    if type( model ) ~= "string" then
        return false
    end

    if model:sub( -4, -1 ) ~= ".mdl" then
        return false
    end

    if not file.Exists( model, "GAME" ) then
        return false
    end

    return true
end
