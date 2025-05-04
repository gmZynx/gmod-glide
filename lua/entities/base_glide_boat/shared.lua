ENT.Type = "anim"
ENT.Base = "base_glide"

ENT.PrintName = "Glide Boat"
ENT.Author = "StyledStrike"
ENT.AdminOnly = false
ENT.AutomaticFrameAdvance = true

-- Change vehicle type
ENT.VehicleType = Glide.VEHICLE_TYPE.BOAT
ENT.CanSwitchHeadlights = true

--[[
    For boats, the values on Get/SetEngineState mean:

    0 - Off
    1 - Starting
    2 - Running
]]

DEFINE_BASECLASS( "base_glide" )

--- Override this base class function.
function ENT:SetupDataTables()
    BaseClass.SetupDataTables( self )

    self:NetworkVar( "Float", "Steering" )
    self:NetworkVar( "Float", "EngineThrottle" )
    self:NetworkVar( "Float", "EnginePower" )

    self:NetworkVar( "Bool", "IsHonking" )

    -- 0: Not on water
    -- 1: At least one buoyancy point is on water
    -- 2: At least half of the buoyancy points are on water
    self:NetworkVar( "Int", "WaterState" )

    if CLIENT then
        self:NetworkVarNotify( "WaterState", self.OnWaterStateChange )
    end
end

--- Implement this base class function.
function ENT:UpdatePlayerPoseParameters( ply )
    ply:SetPlaybackRate( 1 )

    if CLIENT and ply == self:GetDriver() then
        ply:SetPoseParameter( "vehicle_steer", self:GetSteering() )
        ply:InvalidateBoneCache()
    end

    return true
end

--- Override this base class function.
function ENT:IsEngineOn()
    return self:GetEngineState() > 1
end

if CLIENT then
    ENT.MaxSoundDistance = 4000
    ENT.MaxMiscDistance = 4000

    -- Locations where propeller particle effects are emitted
    ENT.PropellerPositions = {}

    -- Size multiplier for water foam/splash effects
    ENT.WaterParticlesScale = 1

    -- Sounds
    ENT.StartSound = "Glide.Engine.BikeStart2"
    ENT.StartTailSound = "Glide.Engine.CarStartTail"
    ENT.StartedSound = ""
    ENT.StoppedSound = "glide/engines/shut_down_1.wav"
    ENT.HornSound = "glide/horns/car_horn_med_8.wav"

    ENT.FallOnWaterSound = "Glide.Collision.BoatLandOnWater"

    ENT.WaterSideSlideLoop = ")ambient/levels/canals/dam_water_loop2.wav"
    ENT.WaterSideSlideVolume = 0.8
    ENT.WaterSideSlidePitch = 255

    ENT.FastWaterLoop = "vehicles/airboat/pontoon_fast_water_loop1.wav"
    ENT.FastWaterPitch = 110
    ENT.FastWaterVolume = 0.5

    ENT.CalmWaterLoop = ")vehicles/airboat/pontoon_stopped_water_loop1.wav"
    ENT.CalmWaterPitch = 100
    ENT.CalmWaterVolume = 0.9

    --- Override this base class function.
    function ENT:GetCameraType( _seatIndex )
        return 0 -- Glide.CAMERA_TYPE.CAR
    end

    function ENT:AllowFirstPersonMuffledSound( _seatIndex )
        return false
    end

    function ENT:AllowWindSound( _seatIndex )
        return true, 0.8
    end

    -- Strips/lines where smoke particles are spawned when the engine is damaged
    ENT.EngineSmokeStrips = {}
    ENT.EngineSmokeMaxZVel = 40

    -- Children classes can override this function
    -- to update animations (the steering wheel for example).
    function ENT:OnUpdateAnimations()
        self:SetPoseParameter( "vehicle_steer", self:GetSteering() )
        self:InvalidateBoneCache()
    end

    -- Children classes should override this
    -- function to add engine sounds to the stream.
    function ENT:OnCreateEngineStream( _stream ) end
end

if SERVER then
    ENT.ChassisMass = 1000
    ENT.CollisionDamageMultiplier = 0.4
    ENT.SoftCollisionSound = "Glide.Collision.BoatHard"

    -- How long does it take for the vehicle to start up?
    ENT.StartupTime = 0.9

    -- If you have not overritten `ENT:GetBuoyancyOffsets`,
    -- this variable moves the auto-generated points on the Z axis.
    ENT.BuoyancyPointsZOffset = 5

    -- If you have not overritten `ENT:GetBuoyancyOffsets`,
    -- this variable spaces out the auto-generated points on the X axis.
    ENT.BuoyancyPointsXSpacing = 0.6

    -- If you have not overritten `ENT:GetBuoyancyOffsets`,
    -- this variable spaces out the auto-generated points on the Y axis.
    ENT.BuoyancyPointsYSpacing = 0.6

    -- Boat drag & force constants.
    -- All of these only apply while on water.
    ENT.BoatParams = {
        waterLinearDrag = Vector( 0.2, 1.5, 0.02 ), -- (Forward, right, up)
        waterAngularDrag = Vector( -5, -20, -15 ), -- (Roll, pitch, yaw)

        buoyancy = 6,
        buoyancyDepth = 30,

        turbulanceForce = 100,   -- Force to wobble the boat
        alignForce = 800,
        maxSpeed = 1000,

        engineForce = 500,
        engineLiftForce = 1300,

        turnForce = 1200,
        rollForce = 200
    }

    --- Calculate relative positions on the boat where buoyancy forces are applied.
    --- Children classes can safely override this function
    --- if they want to manually specify these offsets.
    function ENT:GetBuoyancyOffsets()
        local phys = self:GetPhysicsObject()
        if not IsValid( phys ) then return {} end

        local center = phys:GetMassCenter()
        local mins, maxs = phys:GetAABB()
        local size = ( maxs - mins ) * 0.5

        local spacingX = self.BuoyancyPointsXSpacing
        local spacingY = self.BuoyancyPointsYSpacing

        center[3] = center[3] - self.BuoyancyPointsZOffset

        return {
            center + Vector( size[1] * spacingX, size[2] * spacingY, 0 ), -- Front left
            center + Vector( size[1] * spacingX, size[2] * -spacingY, 0 ), -- Front right
            center + Vector( size[1] * -spacingX, size[2] * spacingY, 0 ), -- Rear left
            center + Vector( size[1] * -spacingX, size[2] * -spacingY, 0 ) -- Rear right
        }
    end
end
