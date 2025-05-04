include( "shared.lua" )

DEFINE_BASECLASS( "base_glide" )

ENT.AutomaticFrameAdvance = true

--- Implement this base class function.
function ENT:OnPostInitialize()
    self.streamJSONOverride = nil
    self.enginePower = 0
    self.waterSideSlide = 0
end

--- Override this base class function.
function ENT:OnEngineStateChange( _, lastState, state )
    if state == 1 then
        if self.rfSounds and self.rfSounds.isActive then
            local snd = self:CreateLoopingSound( "start", Glide.GetRandomSound( self.StartSound ), 70, self )
            snd:PlayEx( 1, 100 )
        end

    elseif lastState == 1 and state == 2 then
        self:OnTurnOn()

    elseif state == 0 then
        self:OnTurnOff()
    end
end

local PlaySoundSet = Glide.PlaySoundSet

function ENT:OnWaterStateChange( _, _, state )
    if not self.rfSounds then return end
    if not self.rfSounds.isActive then return end

    local speed = self:GetVelocity():Length()

    if state > 0 and speed > 10 then
        PlaySoundSet( self.FallOnWaterSound, self, speed / 400 )
    end
end

local GetVolume = Glide.Config.GetVolume

--- Implement this base class function.
function ENT:OnTurnOn()
    if self.StartedSound ~= "" then
        Glide.PlaySoundSet( self.StartedSound, self, GetVolume( "carVolume" ), nil, 85 )
    end
end

--- Implement this base class function.
function ENT:OnTurnOff()
    if self.StoppedSound ~= "" then
        Glide.PlaySoundSet( self.StoppedSound, self, GetVolume( "carVolume" ), nil, 85 )
    end

    self:DeactivateSounds()
end

--- Implement this base class function.
function ENT:OnActivateMisc()
    self.enginePower = 0
end

--- Implement this base class function.
function ENT:OnActivateSounds()
    self.waterSideSlide = 0
end

--- Implement this base class function.
function ENT:OnDeactivateSounds()
    if self.stream then
        self.stream:Destroy()
        self.stream = nil
    end
end

--- Implement this base class function.
function ENT:OnUpdateMisc()
    self:OnUpdateAnimations()
end

local Abs = math.abs
local Clamp = math.Clamp
local FrameTime = FrameTime
local ExpDecay = Glide.ExpDecay

--- Implement this base class function.
function ENT:OnUpdateSounds()
    local sounds = self.sounds

    if sounds.start and self:GetEngineState() ~= 1 then
        sounds.start:Stop()
        sounds.start = nil
        Glide.PlaySoundSet( self.StartTailSound, self )
    end

    local dt = FrameTime()
    local isHonking = self:GetIsHonking()

    if isHonking and self.HornSound then
        local volume = GetVolume( "hornVolume" )

        if sounds.horn then
            sounds.horn:ChangeVolume( volume )
        else
            local snd = self:CreateLoopingSound( "horn", self.HornSound, 85, self )
            snd:PlayEx( volume, 100 )
        end

    elseif sounds.horn then
        if sounds.horn:GetVolume() > 0 then
            sounds.horn:ChangeVolume( sounds.horn:GetVolume() - dt * 8 )
        else
            sounds.horn:Stop()
            sounds.horn = nil
        end
    end

    -- Water sounds
    local localVelocity = self:WorldToLocal( self:GetPos() + self:GetVelocity() )
    local speed = localVelocity:Length()
    local waterState = self:GetWaterState()

    if waterState > 0 and speed > 50 then
        local vol = Clamp( speed / 1000, 0, 1 ) * self.FastWaterVolume
        local pitch = self.FastWaterPitch + ( self.FastWaterPitch * vol * 0.5 )

        if sounds.fastWater then
            sounds.fastWater:ChangeVolume( vol )
            sounds.fastWater:ChangePitch( pitch )
        else
            local snd = self:CreateLoopingSound( "fastWater", self.FastWaterLoop, 85, self )
            snd:PlayEx( vol, pitch )
        end

    elseif sounds.fastWater then
        sounds.fastWater:Stop()
        sounds.fastWater = nil
    end

    if waterState > 0 and speed < 300 then
        local vol = 1 - Clamp( speed / 300, 0, 1 )
        vol = vol * self.CalmWaterVolume

        if sounds.calmWater then
            sounds.calmWater:ChangeVolume( vol )
        else
            local snd = self:CreateLoopingSound( "calmWater", self.CalmWaterLoop, 65, self )
            snd:PlayEx( vol, self.CalmWaterPitch )
        end

    elseif sounds.calmWater then
        sounds.calmWater:Stop()
        sounds.calmWater = nil
    end

    local sideSlide = Clamp( Abs( localVelocity[2] / 500 ), 0, 1 )

    sideSlide = ExpDecay( self.waterSideSlide, waterState > 0 and sideSlide or 0, 4, dt )
    self.waterSideSlide = sideSlide

    if sideSlide > 0.1 then
        sideSlide = sideSlide * self.WaterSideSlideVolume

        if sounds.waterSlide then
            sounds.waterSlide:ChangeVolume( sideSlide )
        else
            local snd = self:CreateLoopingSound( "waterSlide", self.WaterSideSlideLoop, 85, self )
            snd:PlayEx( sideSlide, self.WaterSideSlidePitch )
        end

    elseif sounds.waterSlide then
        sounds.waterSlide:Stop()
        sounds.waterSlide = nil
    end

    if not self:IsEngineOn() then return end

    local stream = self.stream

    if not stream then
        self.stream = Glide.CreateEngineStream( self )

        if self.streamJSONOverride then
            self.stream:LoadJSON( self.streamJSONOverride )
        else
            self:OnCreateEngineStream( self.stream )
        end

        self.stream:Play()

        return
    end

    stream.firstPerson = self.isLocalPlayerInFirstPerson

    local inputs = stream.inputs

    inputs.rpmFraction = self:GetEnginePower()
    inputs.throttle = Abs( self:GetEngineThrottle() )

    -- Handle damaged engine sounds
    local health = self:GetEngineHealth()

    if health < 0.4 then
        if sounds.runDamaged then
            sounds.runDamaged:ChangePitch( 100 + inputs.rpmFraction * 20 )
            sounds.runDamaged:ChangeVolume( Clamp( ( 1 - health ) + inputs.throttle, 0, 1 ) * 0.5 )
        else
            local snd = self:CreateLoopingSound( "runDamaged", "glide/engines/run_damaged_1.wav", 75, self )
            snd:PlayEx( 0.5, 100 )
        end

    elseif sounds.runDamaged then
        sounds.runDamaged:Stop()
        sounds.runDamaged = nil
    end
end

local Effect = util.Effect
local EffectData = EffectData
local IsUnderWater = Glide.IsUnderWater

local DEFAULT_ANG = Angle()

--- Implement this base class function.
function ENT:OnUpdateParticles()
    local vel = self:GetVelocity()
    local power = self:GetEnginePower()
    local throttle = self:GetEngineThrottle()

    if throttle > 0.1 then
        local eff = EffectData()
        local dir = -self:GetForward()

        throttle = ( throttle * 0.5 ) + Clamp( power * 2, 0, 1 ) * 0.5

        for _, offset in ipairs( self.PropellerPositions ) do
            offset = self:LocalToWorld( offset )

            if IsUnderWater( offset ) then
                eff:SetOrigin( offset )
                eff:SetStart( vel )
                eff:SetNormal( dir )
                eff:SetScale( 1 )
                eff:SetMagnitude( throttle )
                Effect( "glide_boat_propeller", eff )
            end
        end
    end

    local waterState = self:GetWaterState()
    local speed = vel:Length()

    if waterState > 0 and speed > 50 then
        local right = self:GetRight()
        local mins, maxs = self:OBBMins(), self:OBBMaxs()

        local pos = Vector( mins[1] * 0.8, 0, mins[3] )
        local magnitude = Clamp( speed / 1000, 0, 1 )
        local scale = self.WaterParticlesScale

        local eff = EffectData()
        eff:SetOrigin( self:LocalToWorld( pos ) )
        eff:SetStart( vel )
        eff:SetScale( scale )
        eff:SetMagnitude( magnitude )
        Effect( "glide_boat_foam", eff )

        if waterState > 1 then
            local length = maxs[1] * 0.75

            pos[1] = 0
            pos[2] = mins[2] * 0.75

            eff:SetOrigin( self:LocalToWorld( pos ) )
            eff:SetScale( scale )
            eff:SetNormal( right )
            eff:SetRadius( length )
            Effect( "glide_boat_splash", eff )

            pos[2] = maxs[2] * 0.75

            eff:SetOrigin( self:LocalToWorld( pos ) )
            eff:SetScale( scale )
            eff:SetNormal( -right )
            eff:SetRadius( length )
            Effect( "glide_boat_splash", eff )
        end
    end

    local health = self:GetEngineHealth()
    if health > 0.5 then return end

    local color = Clamp( health * 255, 0, 255 )
    local velocity = self:GetVelocity()
    local scale = 2 - health * 2

    eff = EffectData()

    for _, v in ipairs( self.EngineSmokeStrips ) do
        eff:SetOrigin( self:LocalToWorld( v.offset ) )
        eff:SetAngles( self:LocalToWorldAngles( v.angle or DEFAULT_ANG ) )
        eff:SetStart( velocity )
        eff:SetColor( color )
        eff:SetMagnitude( v.width * 1000 )
        eff:SetScale( scale )
        eff:SetRadius( self.EngineSmokeMaxZVel )
        Effect( "glide_damaged_engine", eff, true, true )
    end
end
