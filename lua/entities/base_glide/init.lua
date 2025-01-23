AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "cl_init.lua" )

include( "shared.lua" )
include( "sv_input.lua" )
include( "sv_damage.lua" )
include( "sv_weapons.lua" )
include( "sv_wheels.lua" )

duplicator.RegisterEntityClass( "base_glide", Glide.VehicleFactory, "Data" )

local EntityMeta = FindMetaTable( "Entity" )
local getTable = EntityMeta.GetTable

local TriggerOutput = WireLib and WireLib.TriggerOutput or nil

function ENT:OnEntityCopyTableFinish( data )
    Glide.FilterEntityCopyTable( data, self.DuplicatorNetworkVariables )
end

function ENT:PreEntityCopy()
    Glide.PreEntityCopy( self )
end

function ENT:PostEntityPaste( ply, ent, createdEntities )
    Glide.PostEntityPaste( ply, ent, createdEntities )
end

--- Handle spawning this vehicle from the spawn menu or `gm_spawn` command.
function ENT:SpawnFunction( ply, tr )
    local pos = self.SpawnPositionOffset or Vector( 0, 0, 10 )
    local ang = self.SpawnAngleOffset or Angle( 0, 90, 0 )

    return Glide.VehicleFactory( ply, {
        Pos = tr.HitPos + pos,
        Angle = Angle( 0, ply:EyeAngles().y, 0 ) + ang,
        Class = self.ClassName
    } )
end

function ENT:Initialize()
    -- Setup variables used on all vehicle types.
    self.seats = {}     -- Keep track of all seats we've created
    self.exitPos = {}   -- Per-seat exit offsets
    self.lastDriver = NULL

    self.inputBools = {}        -- Per-seat bool inputs
    self.inputFloats = {}       -- Per-seat float inputs
    self.inputFlyMode = 0           -- Current mouse flying mode
    self.inputManualShift = false   -- Current manual gear shifting setting

    -- Setup collision variables
    self.collisionShakeCooldown = 0

    -- Setup speed variables
    self.localVelocity = Vector()
    self.forwardSpeed = 0
    self.totalSpeed = 0

    -- Setup trace data used for hitscan weapons and other things
    -- that need to ignore the vehicle's chassis and seats.
    self.traceData = {
        filter = { self }
    }

    -- Setup the chassis model and physics
    self:SetModel( self.ChassisModel )
    self:InitializePhysics()
    self:SetUseType( SIMPLE_USE )

    local phys = self:GetPhysicsObject()

    if not IsValid( phys ) then
        self:Remove()
        error( "Failed to setup physics! Vehicle removed!" )
        return
    end

    phys:SetMaterial( "metalvehicle" )
    phys:SetMass( self.ChassisMass )
    phys:EnableDrag( false )
    phys:SetDamping( 0, 0 )
    phys:SetDragCoefficient( 0 )
    phys:SetAngleDragCoefficient( 0 )
    phys:SetBuoyancyRatio( 0.05 )
    phys:EnableMotion( true )
    phys:Wake()

    self:StartMotionController()

    -- Let NPCs see through this vehicle
    self:AddEFlags( EFL_DONTBLOCKLOS )
    self:AddFlags( FL_OBJECT )

    -- Setup weapon systems
    self:WeaponInit()

    -- Setup wheel systems
    self:WheelInit()

    local data = { Color = self:GetSpawnColor() }

    self:SetColor( data.Color )
    duplicator.StoreEntityModifier( self, "colour", data )

    -- Setup wiremod ports
    if WireLib then
        local inputs, outputs = {}, {}

        self:SetupWiremodPorts( inputs, outputs )

        -- Separate input names, types and descriptions
        local inNames, inTypes, inDescr = {}, {}, {}

        for i, v in ipairs( inputs ) do
            inNames[i] = v[1]
            inTypes[i] = v[2]
            inDescr[i] = v[3]
        end

        WireLib.CreateSpecialInputs( self, inNames, inTypes, inDescr )

        -- Separate output names, types and descriptions
        local outNames, outTypes, outDescr = {}, {}, {}

        for i, v in ipairs( outputs ) do
            outNames[i] = v[1]
            outTypes[i] = v[2]
            outDescr[i] = v[3]
        end

        WireLib.CreateSpecialOutputs( self, outNames, outTypes, outDescr )
    end

    -- Let child classes add their own features
    self:OnPostInitialize()

    -- Set health back to defaults
    self:Repair()

    -- Let child classes create things like seats, turrets, etc.
    self:CreateFeatures()

    -- Allow players to shoot fast-moving vehicles when their ping is high
    self:SetLagCompensated( true )
end

function ENT:InitializePhysics()
    self:SetSolid( SOLID_VPHYSICS )
    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:PhysicsInit( SOLID_VPHYSICS )
end

function ENT:OnRemove()
    -- Stop physics processing
    local phys = self:GetPhysicsObject()

    if IsValid( phys ) then
        self:StopMotionController()
    end
end

function ENT:UpdateTransmitState()
    return 2 -- TRANSMIT_PVS
end

function ENT:Use( activator )
    if not IsValid( activator ) then return end
    if not activator:IsPlayer() then return end

    local freeSeat = self:GetClosestAvailableSeat( activator:GetShootPos() )
    if freeSeat then
        activator:SetAllowWeaponsInVehicle( false )
        activator:EnterVehicle( freeSeat )
    end
end

--- Sets the "EngineState" network variable to `1` and calls `ENT:OnTurnOn`.
function ENT:TurnOn()
    if self:GetEngineHealth() > 0 then
        self:SetEngineState( 1 )
        self:OnTurnOn()
    end
end

--- Sets the "EngineState" network variable to `0` and calls `ENT:OnTurnOff`.
function ENT:TurnOff()
    self:SetEngineState( 0 )
    self:OnTurnOff()
end

--- Utility function to setup trace data that
--- ignores the vehicle's chassis and seats.
function ENT:GetTraceData( startPos, endPos )
    local data = self.traceData

    data.start = startPos
    data.endpos = endPos

    return data
end

do
    local maxRagdollTimeCvar = GetConVar( "glide_ragdoll_max_time" )

    --- Kicks out all passengers, then ragdoll them.
    function ENT:RagdollPlayers( time, vel )
        time = time or maxRagdollTimeCvar:GetFloat()
        vel = vel or self:GetVelocity()

        local ply

        for seatIndex, seat in ipairs( self.seats ) do
            ply = seat:GetDriver()

            if IsValid( ply ) and self:CanFallOnCollision( seatIndex ) then
                Glide.RagdollPlayer( ply, vel, time )
            end
        end

        self.hasRagdolledAllPlayers = true
    end
end

--- Makes so only the vehicle creator and prop
--- protection buddies can enter this vehicle.
function ENT:SetLocked( isLocked, doNotNotify )
    self:SetIsLocked( isLocked )

    if doNotNotify then return end

    Glide.SendNotification( self:GetAllPlayers(), {
        text = "#glide.notify." .. ( isLocked and "vehicle_locked" or "vehicle_unlocked" ),
        icon = "materials/glide/icons/" .. ( isLocked and "locked" or "unlocked" ) .. ".png",
        sound = isLocked and "doors/latchlocked2.wav" or "doors/latchunlocked1.wav",
        immediate = true
    } )
end

local IsValid = IsValid

do
    local TraceHull = util.TraceHull

    local TRACE_OFFSET = Vector( 0, 0, -100 )
    local TRACE_MINS = Vector( -16, -16, 0 )
    local TRACE_MAXS = Vector( 16, 16, 50 )

    local function ValidateExitPos( pos, data, vehicle )
        local exitPos = vehicle:LocalToWorld( pos )

        data.mins = TRACE_MINS
        data.maxs = TRACE_MAXS
        data.start = exitPos
        data.endpos = exitPos + TRACE_OFFSET

        -- debugoverlay.Box( data.start, data.mins, data.maxs, 10, Color( 255, 255, 255, 10 ) )
        -- debugoverlay.Line( data.start, data.endpos, 10, Color( 0, 0, 255 ), true )

        local tr = TraceHull( data )

        if tr.Hit then
            if tr.StartSolid then
                return true -- This exit is blocked
            end

            -- debugoverlay.Box( tr.HitPos, data.mins, data.maxs, 10, Color( 0, 255, 0, 30 ) )

            return false, tr.HitPos
        end

        return false, exitPos
    end

    --- Gets the exit position from a seat index.
    function ENT:GetSeatExitPos( index )
        local seat = self.seats[index]

        if not IsValid( seat ) then
            return self:GetPos() -- Not much we can do here...
        end

        -- Try the original exit position first
        local blocked, pos = ValidateExitPos( seat.GlideExitPos, self.traceData, self )

        if blocked then
            -- Try on the other side
            pos = Vector( seat.GlideExitPos[1], -seat.GlideExitPos[2], seat.GlideExitPos[3] )
            blocked, pos = ValidateExitPos( pos, self.traceData, self )
        end

        if blocked then
            -- Okay uh... Can we leave at the back?
            local mins = self:OBBMins()
            blocked, pos = ValidateExitPos( Vector( mins[1] * 1.5, 0, 0 ), self.traceData, self )
        end

        if blocked then
            -- Uhhh... Can we leave at the front?
            local maxs = self:OBBMaxs()
            blocked, pos = ValidateExitPos( Vector( maxs[1] * 2, 0, 0 ), self.traceData, self )
        end

        if blocked then
            -- We're cooked...
            pos = seat:GetPos()
        end

        return pos + Vector( 0, 0, 5 )
    end
end

--- Returns all players that are inside of this vehicle.
function ENT:GetAllPlayers()
    local players = {}
    local driver

    for _, seat in ipairs( self.seats ) do
        driver = seat:GetDriver()

        if IsValid( driver ) then
            players[#players + 1] = driver
        end
    end

    return players
end

--- Gets the driver from a seat index.
function ENT:GetSeatDriver( index )
    local seat = self.seats[index]

    if IsValid( seat ) then
        return seat:GetDriver()
    end
end

--- Gets the first free seat entity, or returns `nil` if none are available.
function ENT:GetFreeSeat()
    local driver

    for i, seat in ipairs( self.seats ) do
        driver = seat:GetDriver()

        if not IsValid( driver ) then
            return seat, i
        end
    end
end

--- Gets the closest available seat to a position.
function ENT:GetClosestAvailableSeat( pos )
    local closestSeat = nil
    local closestDistance = math.huge
    for _, seat in ipairs( self.seats ) do
        if IsValid( seat:GetDriver() ) then continue end
        local distance = seat:GetPos():Distance( pos )
        if distance < closestDistance then
            closestSeat = seat
            closestDistance = distance
        end
    end

    return closestSeat
end

--- Create a new seat.
---
--- `offset` is the seat's position relative to the chassis.
--- `angle` is the seat's angles relative to the chassis.
--- Set `isHidden` to `true` to disable drawing this seat.
function ENT:CreateSeat( offset, angle, exitPos, isHidden )
    local index = #self.seats + 1

    if index > Glide.MAX_SEATS then
        error( "Seat limit reached!" )

        return
    end

    local seat = ents.Create( "prop_vehicle_prisoner_pod" )

    if not IsValid( seat ) then
        self:Remove()
        error( "Failed to spawn a seat! Vehicle removed!" )

        return
    end

    seat:SetModel( "models/nova/airboat_seat.mdl" )
    seat:SetPos( self:LocalToWorld( offset or Vector() ) )
    seat:SetAngles( self:LocalToWorldAngles( angle or Angle( 0, 270, 10 ) ) )
    seat:SetMoveType( MOVETYPE_NONE )
    seat:SetOwner( self )
    seat:Spawn()
    seat:Activate()

    seat:SetKeyValue( "limitview", 0 )
    seat:SetNotSolid( true )
    seat:SetParent( self )
    seat:DrawShadow( false )
    seat:PhysicsDestroy()

    seat.PhysgunDisabled = true
    seat.DoNotDuplicate = true
    seat.DisableDuplicator = true

    if isHidden then
        Glide.HideEntity( seat, true )
    end

    -- Let Glide know it should handle this seat differently
    seat.GlideSeatIndex = index
    seat.GlideExitPos = exitPos
    seat:SetNWInt( "GlideSeatIndex", index )
    self:DeleteOnRemove( seat )

    self.seats[index] = seat

    -- Setup player inputs for this seat
    self.inputBools[index] = {}
    self.inputFloats[index] = {}

    -- Don't let weapon fire or other traces hit this seat
    local filter = self.traceData.filter
    filter[#filter + 1] = seat

    -- Update seat wire outputs
    if TriggerOutput then
        if index == 1 then
            TriggerOutput( self, "DriverSeat", seat )
        else
            local passengerSeats = {}

            for i = 2, #self.seats do
                passengerSeats[i - 1] = self.seats[i]
            end

            TriggerOutput( self, "PassengerSeats", passengerSeats )
        end
    end

    return seat
end

local CurTime = CurTime
local TickInterval = engine.TickInterval

function ENT:Think()
    local selfTbl = getTable( self )

    -- Run again next tick
    self:NextThink( CurTime() )

    -- Update speed variables
    selfTbl.localVelocity = self:WorldToLocal( self:GetPos() + self:GetVelocity() )
    selfTbl.forwardSpeed = selfTbl.localVelocity[1]
    selfTbl.totalSpeed = selfTbl.localVelocity:Length()

    -- If we have at least one seat...
    if #selfTbl.seats > 0 then
        -- Use it to check if we have a driver
        local driver = selfTbl.seats[1]:GetDriver()

        if driver ~= self:GetDriver() then
            self:SetDriver( driver )
            self:ClearLockOnTarget()

            if IsValid( driver ) then
                if TriggerOutput then
                    TriggerOutput( self, "Active", 1 )
                    TriggerOutput( self, "Driver", driver )
                end

                self:OnDriverEnter()
                selfTbl.lastDriver = driver
            else
                if TriggerOutput then
                    TriggerOutput( self, "Active", 0 )
                    TriggerOutput( self, "Driver", NULL )
                end

                self:OnDriverExit()
            end

            selfTbl.hasRagdolledAllPlayers = nil
        end
    end

    -- Update weapons
    if selfTbl.weaponCount > 0 then
        self:WeaponThink()
    end

    -- If necessary, kick passengers when underwater
    if selfTbl.FallOnCollision and self:WaterLevel() > 2 and #self:GetAllPlayers() > 0 then
        self:RagdollPlayers( 3 )
    end

    local dt = TickInterval()

    -- Deal engine fire damage over time
    if self:GetIsEngineOnFire() then
        if self:WaterLevel() > 2 then
            self:SetIsEngineOnFire( false )
        else
            local attacker = IsValid( self.lastDamageAttacker ) and self.lastDamageAttacker or self
            local inflictor = IsValid( self.lastDamageInflictor ) and self.lastDamageInflictor or self

            local dmg = DamageInfo()
            dmg:SetDamage( self.MaxChassisHealth * self.ChassisFireDamageMultiplier * dt )
            dmg:SetAttacker( attacker )
            dmg:SetInflictor( inflictor )
            dmg:SetDamageType( 0 )
            dmg:SetDamageForce( Vector() )
            dmg:SetDamagePosition( self:GetPos() )
            self:TakeDamageInfo( dmg )
        end
    end

    -- Update wheels
    if selfTbl.wheelCount > 0 then
        self:WheelThink( dt )
    end

    -- Let children classes do their own stuff
    self:OnPostThink( dt, selfTbl )

    -- Let children classes update their features
    self:OnUpdateFeatures( dt )

    return true
end

function ENT:UpdateHealthOutputs()
    if not TriggerOutput then return end

    TriggerOutput( self, "MaxChassisHealth", self.MaxChassisHealth )
    TriggerOutput( self, "ChassisHealth", self:GetChassisHealth() )
    TriggerOutput( self, "EngineHealth", self:GetEngineHealth() )
end

function ENT:TriggerInput( name, value )
    if name == "EjectDriver" and value > 0 then
        local seat = self.seats[1]

        if IsValid( seat ) then
            local driver = seat:GetDriver()

            if IsValid( driver ) then
                driver:ExitVehicle()
            end
        end

    elseif name == "LockVehicle" then
        self:SetLocked( value > 0, true )
    end
end

local colors = {
    Color( 180, 70, 70 ),
    Color( 80, 65, 50 ),
    Color( 162, 188, 243 ),
    Color( 214, 106, 53 ),
    Color( 45, 45, 45 ),
    Color( 20, 20, 20 ),
    Color( 100, 100, 100 ),
    Color( 190, 190, 190 ),
    Color( 255, 255, 255 )
}

function ENT:GetSpawnColor()
    local color = colors[math.random( #colors )]
    return Color( color.r, color.g, color.b )
end
