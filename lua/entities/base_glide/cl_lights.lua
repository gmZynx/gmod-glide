function ENT:OnHeadlightColorChange()
    -- Let UpdateHeadlights recreate the lights
    self.headlightState = 0
end

function ENT:CreateHeadlight( offset, angles, color, texture, fovScale )
    color = color or Color( 255, 255, 255 )

    local state = self.headlightState
    local fov = state > 1 and 85 or 75

    local index = #self.headlights + 1
    local light = ProjectedTexture()

    self.headlights[index] = light

    light:SetConstantAttenuation( 0 )
    light:SetLinearAttenuation( 50 )
    light:SetTexture( texture or "glide/effects/headlight_rect" )
    light:SetBrightness( state > 1 and 8 or 5 )
    light:SetEnableShadows( Glide.Config.headlightShadows )
    light:SetColor( color )
    light:SetNearZ( 10 )
    light:SetFarZ( state > 1 and 3000 or 1500 )
    light:SetFOV( fov * ( fovScale or 1 ) )
    light:SetPos( self:LocalToWorld( offset ) )
    light:SetAngles( self:LocalToWorldAngles( angles or Angle() ) )
    light:Update()
end

function ENT:RemoveHeadlights()
    if not self.headlights then return end

    for _, light in ipairs( self.headlights ) do
        if IsValid( light ) then
            light:Remove()
        end
    end

    self.headlights = {}
end

local IsValid = IsValid
local CurTime = CurTime
local DrawLight = Glide.DrawLight
local DrawLightSprite = Glide.DrawLightSprite

local COLOR_BRAKE = Color( 255, 0, 0, 255 )
local COLOR_REV = Color( 255, 255, 255, 200 )
local COLOR_HEADLIGHT = Color( 255, 255, 255 )

local DEFAULT_BRIGHTNESS = {
    ["signal_left"] = 6,
    ["signal_right"] = 6,
    ["taillight"] = 1
}

local lightState = {
    brake = false,
    reverse = false,
    headlight = false,
    taillight = false,
    signal_left = false,
    signal_right = false
}

--- Draw sprites depending on which type of lights are active.
function ENT:UpdateLights()
    local headlightState = self:GetHeadlightState()

    if headlightState > 0 then
        local colorVec = self:GetHeadlightColor()
        COLOR_HEADLIGHT.r = colorVec[1] * 255
        COLOR_HEADLIGHT.g = colorVec[2] * 255
        COLOR_HEADLIGHT.b = colorVec[3] * 255
    end

    -- Handle projected lights
    if self.headlightState ~= headlightState then
        self.headlightState = headlightState
        self:RemoveHeadlights()

        if headlightState == 0 then return end

        for _, v in ipairs( self.Headlights ) do
            v.angles = v.angles or Angle( 10, 0, 0 )
            self:CreateHeadlight( v.offset, v.angles, v.color or COLOR_HEADLIGHT, v.texture, v.fovScale )
        end
    end

    for i, l in ipairs( self.headlights ) do
        if IsValid( l ) then
            local data = self.Headlights[i]
            l:SetPos( self:LocalToWorld( data.offset ) )
            l:SetAngles( self:LocalToWorldAngles( data.angles ) )
            l:Update()
        end
    end

    -- Handle sprites
    lightState.brake = self:GetIsBraking()
    lightState.reverse = self:IsReversing()
    lightState.headlight = headlightState > 0
    lightState.taillight = headlightState > 0

    local signal = self:GetTurnSignalState()
    local signalBlink = ( CurTime() % self.TurnSignalCycle ) > self.TurnSignalCycle * 0.5

    lightState.signal_left = signal == 1 or signal == 3
    lightState.signal_right = signal == 2 or signal == 3

    local myPos = self:GetPos()
    local pos, dir, ltype, enable

    for _, l in ipairs( self.LightSprites ) do
        pos = self:LocalToWorld( l.offset )
        dir = self:LocalToWorld( l.dir ) - myPos
        ltype = l.type
        enable = lightState[ltype]

        -- Blink "signal_*" light types
        if ltype == "signal_left" or ltype == "signal_right" then
            enable = enable and signalBlink
        end

        -- Allow other types of light to blink with turn signals, if "signal" is set.
        if l.signal and signal > 0 then
            if l.signal == "left" and lightState.signal_left then
                enable = signalBlink

            elseif l.signal == "right" and lightState.signal_right then
                enable = signalBlink
            end
        end

        -- If the light has a `beamType` key, only draw the sprite
        -- if the value of `beamType` matches the current headlight state.
        if
            ( l.beamType == "low" and headlightState ~= 1 ) or
            ( l.beamType == "high" and headlightState ~= 2 )
        then
            enable = false
        end

        if enable and ltype == "headlight" then
            DrawLightSprite( pos, dir, l.size or 30, l.color or COLOR_HEADLIGHT, l.spriteMaterial )

        elseif enable and ( ltype == "taillight" or ltype == "signal_left" or ltype == "signal_right" ) then
            DrawLightSprite( pos, dir, l.size or 30, l.color or COLOR_BRAKE, l.spriteMaterial )
            DrawLight( pos + dir * 10, l.color or COLOR_BRAKE, l.lightRadius, l.lightBrightness or DEFAULT_BRIGHTNESS[ltype] )

        elseif enable and ltype == "brake" then
            DrawLightSprite( pos, dir, l.size or 30, l.color or COLOR_BRAKE, l.spriteMaterial )
            DrawLight( pos + dir * 10, l.color or COLOR_BRAKE, l.lightRadius, l.lightBrightness )

        elseif enable and ltype == "reverse" then
            DrawLightSprite( pos, dir, l.size or 20, l.color or COLOR_REV, l.spriteMaterial )
            DrawLight( pos + dir * 10, l.color or COLOR_REV, l.lightRadius, l.lightBrightness )
        end
    end
end
