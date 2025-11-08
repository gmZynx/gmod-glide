local WAB = Glide.WAB or {}
Glide.WAB = WAB

WAB.MAX_STREAMS = 32
WAB.HTML_FILE = "data_static/glide/web_audio_html.txt"
WAB.CVAR_DEBUG = CreateClientConVar( "glide_webaudio_debug", "0", false, false, "", 0, 1 )

cvars.RemoveChangeCallback( "glide_webaudio_debug_toggle" )
cvars.AddChangeCallback( "glide_webaudio_debug", function( _, _, value )
    if IsValid( WAB.panel ) then
        WAB.debugEnabled = tonumber( value ) > 0
        WAB.panel:RunJavascript( ( "debug.setEnabled(%s);" ):format( WAB.debugEnabled and "true" or "false" ) )
    end
end, "glide_webaudio_debug_toggle" )

function WAB.Print( str )
    Glide.Print( "[Web Audio Bridge] %s", str )
end

--- Activates the Web Audio Bridge.
--- Prepares the necessary HTML panel for handling audio.
function WAB.Enable()
    if IsValid( WAB.panel ) then
        return
    end

    WAB.isReady = false
    WAB.Print( "Preparing..." )

    local code = file.Read( WAB.HTML_FILE, "GAME" )
    assert( code ~= nil, "Failed to load Web Audio HTML code!" )

    WAB.panel = vgui.Create( "HTML" )
    WAB.panel:Dock( FILL ) -- TODO: remove this

    WAB.panel.OnFinishLoadingDocument = function()
        WAB.OnHTMLReady()
    end

    WAB.panel.ConsoleMessage = function( _, msg, _, line, _ )
        if not isstring( msg ) then return end

        if isnumber( line ) then
            WAB.Print( ( "[JS:%d]: %s" ):format( line, msg )  )
        else
            WAB.Print( ( "[JS]: %s" ):format( msg )  )
        end
    end

    WAB.panel.OnCallback = function( _, obj, func, args )
        if obj ~= "wab" then return end

        if WAB[func] then
            WAB[func]( unpack( args ) )
        end
    end

    WAB.panel:SetHTML( code )
end

--- Deactivates the Web Audio Bridge.
--- Removes the HTML panel that handles audio.
function WAB.Disable()
    if IsValid( WAB.panel ) then
        WAB.panel:Remove()
        WAB.Print( "Disabled!" )
    end

    hook.Remove( "Think", "WebAudioBridge.Think" )
    timer.Remove( "WAB.AutoRefreshHTML" )

    WAB.isReady = false
    WAB.panel = nil
    WAB.streams = nil
    WAB.streamCount = 0
    WAB.busParameters = nil
    WAB.lastImpulseResponseAudio = nil

    WAB.RemoveAllStreams()
end

function WAB.RemoveAllStreams()
    -- Remove all existing streams so they can be recreated
    -- with the regular EngineStream or Web Audio Brige backend.
    local IsBasedOn = scripted_ents.IsBasedOn

    for _, e in ents.Iterator() do
        if IsValid( e ) and e.GetClass and IsBasedOn( e:GetClass(), "base_glide" ) and e.stream then
            e.stream:Destroy()
            e.stream = nil
        end
    end
end

function WAB.AddCallback( name )
    WAB.panel:NewObjectCallback( "wab", name )
end

function WAB.OnHTMLReady()
    WAB.panel:NewObject( "wab" )
    WAB.AddCallback( "OnStreamCreated" )

    WAB.panel:RunJavascript( ( "DEFAULT_STREAM_PARAMETERS = JSON.parse(`%s`);" ):format(
        Glide.ToJSON( Glide.DEFAULT_STREAM_PARAMS, false )
    ) )

    WAB.debugEnabled = WAB.CVAR_DEBUG:GetInt() > 0

    WAB.panel:RunJavascript( ( "debug.setEnabled(%s);" ):format(
        WAB.debugEnabled and "true" or "false"
    ) )

    WAB.busParameters = {
        ["preGainVolume"] = { 1.0 },
        ["postFilterBandGain"] = { 0.0 },
        ["dryVolume"] = { 1.0 },
        ["wetVolume"] = { 1.0 },
        ["delayTime"] = { 0.1 },
        ["delayFeedback"] = { 0.1, 0.1 },
    }

    WAB.isReady = true
    WAB.streams = {}
    WAB.streamCount = 0
    WAB.Print( "Ready!" )

    -- Watch for changes in the HTML code to auto-reload
    local lastModified = file.Time( WAB.HTML_FILE, "GAME" )

    timer.Create( "WAB.AutoRefreshHTML", 1, 0, function()
        local time = file.Time( WAB.HTML_FILE, "GAME" )

        if time ~= lastModified then
            lastModified = time
            WAB.Restart()
        end
    end )

    local RealTime = RealTime
    local nextThink, lastThink = RealTime(), RealTime()

    hook.Add( "Think", "WebAudioBridge.Think", function()
        local time = RealTime()

        -- Update the listener/engine stream positions
        -- 40 times per second at most.
        if time > nextThink then
            WAB.Think( time - lastThink )

            nextThink = time + 0.025
            lastThink = time
        end
    end )

    WAB.RemoveAllStreams()
end

function WAB.OnStreamCreated( id )
    id = tonumber( id )

    local stream = WAB.streams[id]

    if stream then
        stream.isReady = true
    else
        -- Remove the stream from the JS side
        -- if it no longer exists on the Lua side.
        WAB.RequestStreamDeletion( id )
    end
end

function WAB.RequestStreamCreation( stream )
    if not WAB.isReady then return end

    local id = stream.id
    if WAB.streams[id] then return end

    stream.isReady = false
    stream.isWebPlaying = false
    stream.position = Vector()

    WAB.streams[id] = stream
    WAB.streamCount = WAB.streamCount + 1
    WAB.panel:RunJavascript( ( "manager.createStream('%s');" ):format( tostring( id ) ) )
end

function WAB.RequestStreamDeletion( id )
    if not WAB.isReady then return end

    if WAB.streams[id] then
        WAB.streams[id] = nil
        WAB.streamCount = WAB.streamCount - 1
    end

    WAB.panel:RunJavascript( ( "manager.destroyStream('%s');" ):format( tostring( id ) ) )
end

function WAB.SetBusParameter( name, value, time )
    assert( type( value ) == "number", "Bus parameter value must be a number!" )

    if WAB.busParameters[name] then
        WAB.busParameters[name] = { value, time }
    end
end

-- Set which audio file will be used to apply effects with the ConvolverNode.
-- Just the file name is needed here, you can find them in `sound/glide/webaudio`.
function WAB.SetConvolverInpulseResponseAudio( fileName )
    if WAB.isReady then
        fileName = fileName == nil and "undefined" or "'" .. fileName .. "'"
        WAB.panel:RunJavascript( ( "manager.setConvolverInpulseResponseAudio(%s);" ):format( fileName ) )
    end
end

function WAB.SetDebugRowValue( id, value )
    if WAB.isReady then
        WAB.panel:RunJavascript( ( "debug.setRowValue('%s', '%s');" ):format( id, tostring( value ) ) )
    end
end

do
    local CHECK_DIRECTIONS = {
        Vector( 5000, 0, 0 ), -- North
        Vector( 0, 5000, 0 ), -- West
        Vector( -5000, 0, 0 ), -- South
        Vector( 0, -5000, 0 ), -- East
        Vector( 0, 0, 3000 ) -- Up
    }

    local ray = {}

    local traceData = {
        output = ray,
        mask = MASK_NPCWORLDSTATIC,
        collisiongroup = COLLISION_GROUP_WORLD
    }

    local TraceLine = util.TraceLine
    local dirIndex, accumulatedSize = 0, 0
    local lastSize, lastOpenCeiling = 1, 1

    function WAB.UpdateRoomValues( origin )
        dirIndex = dirIndex + 1

        if dirIndex > 5 then
            dirIndex = 1
            lastSize = accumulatedSize / 5
            accumulatedSize = 0
        end

        traceData.start = origin
        traceData.endpos = origin + CHECK_DIRECTIONS[dirIndex]

        TraceLine( traceData )

        local isAir = ray.HitSky or not ray.Hit

        if dirIndex > 4 then
            lastOpenCeiling = isAir and 1 or ray.Fraction
        end

        accumulatedSize = accumulatedSize + ( isAir and 1 or ray.Fraction )

        return lastSize, lastOpenCeiling
    end
end

local lines = {}
local lineIndex = 0

local function AddLine( str, ... )
    lineIndex = lineIndex + 1
    lines[lineIndex] = str:format( ... )
end

local Round = math.Round
local Clamp = math.Clamp
local ExpDecay = Glide.ExpDecay

local JS_SET_PARAM = "manager.setBusParameter('%s', %f);"
local JS_CHANGE_PARAM = "manager.changeBusParameter('%s', %f, %f);"
local JS_UPDATE_LISTENER = "manager.updateListener(%.2f, %.2f, %.2f, %.2f, %.2f, %.2f, %.2f, %.2f, %.2f);";
local JS_UPDATE_STREAM = "manager.setStreamData('%s', %.2f, %.2f, %.2f, %.2f, %.2f, %.1f, %s);"

local ROOM_INPULSE_RESPONSES = {
    -- Max. room size, Audio (closed ceiling), Audio (open ceiling)
    { 0.3, "1.8s_99w_900hz_30m.wav", "1.8s_99w_100hz_30m.wav" },
    { 0.6, "2.8s_99w_900hz_30m.wav", "2.8s_99w_100hz_30m.wav" },
    { 0.8, "3.8s_99w_900hz_30m.wav", "3.8s_99w_100hz_30m.wav" },
    { 1.0, "4.8s_99w_900hz_30m.wav", "4.8s_99w_100hz_30m.wav" },
}

local ROOM_ECHO_DELAYS = {
    -- Max. room size, Echo delay
    { 0.05, 0.02 },
    { 0.2, 0.04 },
    { 0.3, 0.1 },
    { 0.6, 0.2 },
    { 1.0, 0.3 },
}

local GetVolume = Glide.Config.GetVolume
local updateEffectsTimer = 0

function WAB.Think( dt )
    local pos = MainEyePos()
    local muffleSound = Glide.Camera.muffleSound

    -- Update room effects
    local lastRoomSize = WAB.lastRoomSize or 0
    local lastRoomOpenCeiling = WAB.lastRoomOpenCeiling or 0
    local roomSize, roomOpenCeiling = WAB.UpdateRoomValues( pos )

    lastRoomSize = ExpDecay( lastRoomSize, roomSize, 25, dt )
    lastRoomOpenCeiling = ExpDecay( lastRoomOpenCeiling, roomOpenCeiling, 20, dt )

    WAB.lastRoomSize = lastRoomSize
    WAB.lastRoomOpenCeiling = lastRoomOpenCeiling

    if WAB.debugEnabled then
        WAB.SetDebugRowValue( "roomSize", lastRoomSize )
        WAB.SetDebugRowValue( "roomCeiling", lastRoomOpenCeiling )
        WAB.SetDebugRowValue( "streamCount", WAB.streamCount )
    end

    updateEffectsTimer = updateEffectsTimer + dt

    if updateEffectsTimer > 0.2 then
        local changeTime = updateEffectsTimer * 0.9
        local delayTime = 0.4
        local delayFeedback = Clamp( ( 1 - lastRoomSize ) * ( 1 - lastRoomOpenCeiling ) * 0.9, 0.05, 0.6 )

        if muffleSound then
            delayTime = 0.03
            delayFeedback = 0.5
        else
            for _, v in ipairs( ROOM_ECHO_DELAYS ) do
                if lastRoomSize < v[1] then
                    delayTime = v[2]
                    break
                end
            end
        end

        WAB.SetBusParameter( "postFilterBandGain", muffleSound and -20.0 or 0.0 )
        WAB.SetBusParameter( "delayTime", delayTime )
        WAB.SetBusParameter( "delayFeedback", delayFeedback, changeTime )

        local impulseResponseAudio = ROOM_INPULSE_RESPONSES[1][2]

        for _, v in ipairs( ROOM_INPULSE_RESPONSES ) do
            if lastRoomSize < v[1] then
                impulseResponseAudio = v[lastRoomOpenCeiling < 0.6 and 2 or 3]
                break
            end
        end

        if WAB.lastImpulseResponseAudio ~= impulseResponseAudio then
            WAB.lastImpulseResponseAudio = impulseResponseAudio
            WAB.SetConvolverInpulseResponseAudio( impulseResponseAudio )
        end

        updateEffectsTimer = 0
    end

    local wetMultiplier = ( 1 - lastRoomSize ) * ( 0.5 + ( 0.4 - lastRoomOpenCeiling * 0.6 ) )

    WAB.SetBusParameter( "preGainVolume", GetVolume( "carVolume" ) )
    WAB.SetBusParameter( "dryVolume", Round( Clamp( 1 - wetMultiplier * 0.1, 0.5, 1.0 ) * 1.15, 2 ) )
    WAB.SetBusParameter( "wetVolume", Round( Clamp( wetMultiplier * 2.5, 0.1, 1.5 ), 2 ) )

    --[[
        Create one big Javascript snippet, which will:
        - Update the listener position
        - Update bus parameters
        - Update all active stream parameters
    ]]

    lineIndex = 0
    table.Empty( lines )

    for name, data in pairs( WAB.busParameters ) do
        if data[2] then
            AddLine( JS_CHANGE_PARAM, name, Round( data[1], 3 ), Round( data[2], 3 ) )
        else
            AddLine( JS_SET_PARAM, name, Round( data[1], 3 ) )
        end
    end

    -- Update listener position and orientation
    local ang = MainEyeAngles()
    local fw = ang:Forward()
    local up = ang:Up()

    AddLine( JS_UPDATE_LISTENER,
        pos[1], pos[2], pos[3],
        fw[1], fw[2], fw[3],
        up[1], up[2], up[3]
    )

    -- Update all streams
    for id, stream in pairs( WAB.streams ) do
        if stream.isReady then
            -- If the stream preset has changed,
            -- send the full preset JSON to JS once.
            if stream.updateWebJSON then
                WAB.panel:RunJavascript( ( "manager.setStreamJSON('%s', `%s`);" ):format( id, stream.updateWebJSON ) )
                stream.updateWebJSON = nil
            end

            if stream.isWebPlaying ~= stream.isPlaying then
                stream.isWebPlaying = stream.isPlaying
                WAB.panel:RunJavascript( ( "manager.setStreamPlaying('%s', %s);" ):format( id, stream.isPlaying and "true" or "false" ) )
            end

            local position = stream.position
            local inputs = stream.inputs

            AddLine( JS_UPDATE_STREAM, id,
                position[1], position[2], position[3],
                inputs.throttle, inputs.rpmFraction, inputs.redline, stream.isRedlining
            )

            if stream.wobbleTime > 0 then
                AddLine( "manager.setStreamWobbleTime('%s', %.2f);", id, stream.wobbleTime )
                stream.wobbleTime = 0
            end
        end
    end

    WAB.panel:RunJavascript( table.concat( lines, "\n" ) )
end

function WAB.Restart()
    WAB:Disable()

    timer.Create( "WAB.AutoRefreshPanel", 0.5, 1, function()
        WAB:Enable()
    end )
end
