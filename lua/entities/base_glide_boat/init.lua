AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )

include( "shared.lua" )

DEFINE_BASECLASS( "base_glide" )

--- Implement this base class function.
function ENT:OnPostInitialize()
    -- Setup variables used on all boats
    self.inputSteerInstant = 0
    self:SetupBuoyancyPoints()

    self:SetEngineThrottle( 0 )
    self:SetEnginePower( 0 )

    self:SetIsHonking( false )
    self:SetWaterState( 0 )

    -- Make boats more slidey on land
    local phys = self:GetPhysicsObject()

    if IsValid( phys ) then
        phys:SetMaterial( "glass" )
    end
end

--- Implement this base class function.
function ENT:OnDriverEnter()
    if self.startupTimer then return end

    if self:GetEngineState() < 2 then
        self:TurnOn()
    end
end

--- Implement this base class function.
function ENT:OnDriverExit()
    self:SetIsHonking( false )

    if self.hasRagdolledAllPlayers then
        BaseClass.OnDriverExit( self )
    else
        self:TurnOff()
    end
end

--- Implement this base class function.
function ENT:OnSeatInput( seatIndex, action, pressed )
    if seatIndex > 1 then return end

    if action == "horn" then
        self:SetIsHonking( pressed )
    end

    if not pressed then return end

    if action == "toggle_engine" then
        if self:GetEngineState() == 0 then
            self:TurnOn()
        else
            self:TurnOff()
        end
    end
end

--- Override this base class function.
function ENT:OnTakeDamage( dmginfo )
    BaseClass.OnTakeDamage( self, dmginfo )

    if self:GetEngineHealth() <= 0 and self:GetEngineState() == 2 then
        self:TurnOff()
    end
end

--- Override this base class function.
function ENT:TurnOn()
    if self:GetEngineState() < 1 then
        self:SetEngineState( 1 )
    end
end

--- Override this base class function.
function ENT:TurnOff()
    BaseClass.TurnOff( self )

    self:SetEnginePower( 0 )
    self:SetEngineThrottle( 0 )
    self:SetIsHonking( false )

    self.startupTimer = nil
end

function ENT:OnReloaded()
    self:SetupBuoyancyPoints()
end

function ENT:SetupBuoyancyPoints()
    local offsets = self:GetBuoyancyOffsets()
    local points = {}

    for i, offset in ipairs( offsets ) do
        points[i] = {
            offset = offset,
            isUnderWater = false
        }
    end

    self.buoyancyPoints = points
    self.buoyancyPointsCount = #points
end

local Abs = math.abs
local Clamp = math.Clamp
local WORLD_UP = Vector( 0, 0, 1 )

local ExpDecay = Glide.ExpDecay
local IsUnderWater = Glide.IsUnderWater
local GetDevMode = Glide.GetDevMode

--- Implement this base class function.
function ENT:OnPostThink( dt, selfTbl )
    local state = self:GetEngineState()
    local health = self:GetEngineHealth()

    -- Attempt to start the engine
    if state == 1 then
        if selfTbl.startupTimer then
            if CurTime() > selfTbl.startupTimer then
                selfTbl.startupTimer = nil

                if health > 0 then
                    self:SetEngineState( 2 )
                    self:OnTurnOn()
                else
                    self:SetEngineState( 0 )
                end
            end
        else
            local startupTime = health < 0.5 and math.Rand( 1, 2 ) or selfTbl.StartupTime
            selfTbl.startupTimer = CurTime() + startupTime
        end
    end

    if self:IsEngineOn() then
        self:UpdateEngine( dt, selfTbl )

        -- Make sure the physics stay awake when necessary,
        -- otherwise the driver's input won't do anything.
        local phys = self:GetPhysicsObject()

        if IsValid( phys ) and phys:IsAsleep() then
            local driverInput = self:GetInputFloat( 1, "accelerate" ) + self:GetInputFloat( 1, "brake" ) + self:GetInputFloat( 1, "steer" )

            if Abs( driverInput ) > 0.01 then
                phys:Wake()
            end
        end
    end

    -- Update steer input
    local inputSteer = self:GetInputFloat( 1, "steer" )
    selfTbl.inputSteerInstant = inputSteer
    self:SetSteering( ExpDecay( self:GetSteering(), inputSteer, 8, dt ) )

    -- Update buoyancy points
    local underWaterPoints = 0

    for _, point in ipairs( selfTbl.buoyancyPoints ) do
        point.isUnderWater = IsUnderWater( self:LocalToWorld( point.offset ) )

        if point.isUnderWater then
            underWaterPoints = underWaterPoints + 1
        end
    end

    local waterState = underWaterPoints < 1 and 0 or (
        underWaterPoints > selfTbl.buoyancyPointsCount * 0.5 and 2 or 1
    )

    self:SetWaterState( waterState )

    -- Check if the boat is fully upside down
    if waterState == 2 and self:GetUp():Dot( WORLD_UP ) < 0 then
        self:SetEngineThrottle( 0 )
        self:SetEnginePower( 0 )

        -- Damage the engine over time
        if health > 0 then
            self:TakeEngineDamage( dt * 0.2 )

        elseif self:GetEngineState() == 2 then
            self:TurnOff()
        end

        -- Kick passengers
        if #self:GetAllPlayers() > 0 then
            self:RagdollPlayers()
        end
    end

    -- Draw buoyancy debug overlays, if `developer` cvar is active
    if GetDevMode() then
        for _, point in ipairs( selfTbl.buoyancyPoints ) do
            debugoverlay.Cross( self:LocalToWorld( point.offset ), 8, 0.1, Color( 50, point.isUnderWater and 255 or 150, 255 ), true )
        end
    end
end

function ENT:UpdateEngine( dt, selfTbl )
    local waterState = self:GetWaterState()
    local speed = selfTbl.forwardSpeed
    local throttle = 0

    if Abs( speed ) > 20 or waterState > 0 then
        throttle = self:GetInputFloat( 1, "accelerate" ) - self:GetInputFloat( 1, "brake" )
    end

    self:SetEngineThrottle( ExpDecay( self:GetEngineThrottle(), throttle, 5, dt ) )

    local power = Abs( throttle )

    if throttle < 0 then
        power = power * Clamp( -speed / self.BoatParams.maxSpeed * 4, 0, 1 )
        power = power * 0.4

    elseif waterState > 0 then
        power = power * ( 0.4 + Clamp( Abs( speed ) / self.BoatParams.maxSpeed, 0, 1 ) * 0.6 )
        power = power * ( waterState > 1 and 0.6 or 1 )
    end

    self:SetEnginePower( ExpDecay( self:GetEnginePower(), power, 2 + power * 2, dt ) )
end

local mass, effectiveness
local linearImp, angularImp

local function AddForceOffset( outLin, outAng, phys, dt, pos, f )
    linearImp, angularImp = phys:CalculateForceOffset( f * mass * effectiveness, pos )

    outLin[1] = outLin[1] + linearImp[1] / dt
    outLin[2] = outLin[2] + linearImp[2] / dt
    outLin[3] = outLin[3] + linearImp[3] / dt

    outAng[1] = outAng[1] + angularImp[1] / dt
    outAng[2] = outAng[2] + angularImp[2] / dt
    outAng[3] = outAng[3] + angularImp[3] / dt
end

local function AddForce( out, f )
    out[1] = out[1] + f[1] * mass * effectiveness
    out[2] = out[2] + f[2] * mass * effectiveness
    out[3] = out[3] + f[3] * mass * effectiveness
end

local function LimitInputWithAngle( value, ang, maxAng )
    if ang > maxAng then
        value = value * ( 1 - Clamp( ( ang - maxAng ) / 20, 0, 1 ) )
    end

    return value
end

local CurTime = CurTime
local Cos = math.cos
local TraceLine = util.TraceLine

local ray = {}
local traceData = { mask = MASK_WATER, output = ray }
local fw, rt, vel, speed

function ENT:OnSimulatePhysics( phys, dt, outLin, outAng )
    if self:IsPlayerHolding() then return end

    -- Don't apply any of the other forces
    -- if no buoyancy points are under water.
    if self:GetWaterState() < 1 then return end

    effectiveness = 1.0
    mass = phys:GetMass()

    fw = self:GetForward()
    rt = fw:Cross( WORLD_UP )

    vel = phys:GetVelocity()
    speed = self:WorldToLocal( phys:GetPos() + vel )[1]

    local params = self.BoatParams

    -- Buoyancy forces
    local upDrag = -params.waterLinearDrag[3]
    local upDepth = params.buoyancyDepth
    local pointVel, offset, buoyancyForce

    for _, point in ipairs( self.buoyancyPoints ) do
        if point.isUnderWater then
            offset = self:LocalToWorld( point.offset )
            pointVel = phys:GetVelocityAtPoint( offset )

            -- Check how far from the surface this point is
            traceData.start = offset + WORLD_UP * upDepth
            traceData.endpos = offset

            TraceLine( traceData )

            buoyancyForce = params.buoyancy * ( 1 - ray.Fraction )
            buoyancyForce = buoyancyForce + WORLD_UP:Dot( pointVel ) * upDrag

            AddForceOffset( outLin, outAng, phys, dt, offset, WORLD_UP * buoyancyForce )
        end
    end

    local tightTurn = self:GetInputBool( 1, "handbrake" )

    -- Drag forces
    AddForce( outLin, fw * Clamp( speed, -500, 500 ) * -params.waterLinearDrag[1] * ( tightTurn and 2 or 1 ) )
    AddForce( outLin, rt * rt:Dot( vel ) * -params.waterLinearDrag[2] * ( tightTurn and 2 or 1 ) )

    local angDrag = params.waterAngularDrag
    local angVel = phys:GetAngleVelocity()

    outAng[1] = outAng[1] + angVel[1] * angDrag[1] * mass * effectiveness
    outAng[2] = outAng[2] + angVel[2] * angDrag[2] * mass * effectiveness
    outAng[3] = outAng[3] + angVel[3] * angDrag[3] * mass * effectiveness

    -- Try to align the boat towards the direction of movement
    if not tightTurn then
        vel:Normalize()
        outAng[3] = outAng[3] - vel:Dot( rt ) * params.alignForce * mass * effectiveness
    end

    -- Turbulance
    local t = CurTime()
    outAng[1] = outAng[1] + Cos( t * 1.5 ) * params.turbulanceForce * mass
    outAng[2] = outAng[2] + Cos( t * 2 ) * params.turbulanceForce * 2 * mass

    -- Engine and steering forces
    local angles = self:GetAngles()
    local throttle = self:GetEngineThrottle()

    if throttle > 0 and speed < params.maxSpeed then
        AddForce( outLin, fw * params.engineForce * throttle )

        throttle = LimitInputWithAngle( throttle, Abs( angles[1] ), 10 )
        outAng[2] = outAng[2] - params.engineLiftForce * mass * effectiveness * throttle

    elseif throttle < 0 and speed > params.maxSpeed * -0.25 then
        AddForce( outLin, fw * params.engineForce * throttle )
    end

    local inputSteer = self.inputSteerInstant * Clamp( ( Abs( speed ) - 20 ) / 200, 0, 1 )

    if speed < 0 then
        inputSteer = -inputSteer
    end

    outAng[3] = outAng[3] - params.turnForce * inputSteer * mass * effectiveness

    inputSteer = LimitInputWithAngle( inputSteer, Abs( angles[3] ), 30 )
    outAng[1] = outAng[1] + params.rollForce * inputSteer * mass * effectiveness * ( tightTurn and 2 or 1 )
end
