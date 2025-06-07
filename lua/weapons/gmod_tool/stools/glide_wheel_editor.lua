TOOL.Category = "Glide"
TOOL.Name = "#tool.glide_wheel_editor.name"

TOOL.Information = {
    { name = "left" },
    { name = "left_use", icon2 = "gui/e.png" },
    { name = "right" },
}

TOOL.ClientConVar = {
    radius = 15,
    model = "models/props_vehicles/apc_tire001.mdl",

    scale_x = 1,
    scale_y = 1,
    scale_z = 1,

    offset_x = 0,
    offset_y = 0,
    offset_z = 0
}

local IsValid = IsValid

local function IsGlideVehicle( ent )
    return IsValid( ent ) and ent.IsGlideVehicle
end

do
    local function GetClosestWheel( pos, radius )
        local wheels = ents.FindByClass( "glide_wheel" )
        if #wheels < 1 then return end

        radius = radius or 200

        local closestDist = radius * radius
        local dist, closestWheel

        for _, w in ipairs( wheels ) do
            dist = pos:DistToSqr( w:GetPos() )

            if dist < closestDist then
                closestDist = dist
                closestWheel = w
            end
        end

        return closestWheel
    end

    local traceData = {
        filter = { "player" },
        mask = MASK_NPCSOLID,
        mins = Vector( -10, -10, -10 ),
        maxs = Vector( 10, 10, 10 ),
    }

    function TOOL:GetAimingAtWheel()
        local ply = self:GetOwner()

        traceData.start = ply:EyePos()
        traceData.endpos = traceData.start + ply:GetAimVector() * 1000

        local tr = util.TraceHull( traceData )
        return GetClosestWheel( tr.HitPos )
    end
end

local ApplyVehicleWheelParameters

if SERVER then
    local ValidateNumber = Glide.ValidateNumber
    local IsValidModel = Glide.IsValidModel

    local function ApplyWheelParameters( wheel, params )
        -- Proceed only if we've a valid model
        local model = params.model
        if not IsValidModel( model ) then return end

        local modelData = list.Get( "GlideWheelModels" )[model]
        if not modelData then return end

        local scale = ( modelData.scale or Vector( 1, 1, 0.35 ) ) * Vector(
            ValidateNumber( params.scaleX, 0.1, 5, 1 ),
            ValidateNumber( params.scaleY, 0.1, 5, 1 ),
            ValidateNumber( params.scaleZ, 0.1, 5, 1 )
        )

        local offset = ( modelData.offset or Vector( 0, 0, 0 ) ) + Vector(
            ValidateNumber( params.offsetX, -10, 10, 0 ),
            ValidateNumber( params.offsetY, -10, 10, 0 ),
            ValidateNumber( params.offsetZ, -10, 10, 0 )
        )

        local radius = wheel:GetRadius()
        local angle = modelData.angle or Angle( 0, 0, 270 )

        if type( params.radius ) == "number" then
            radius = ValidateNumber( params.radius, 10, 50, 15 )
        end

        -- Unset `useModelSize`
        if wheel.params.useModelSize then
            wheel.params.useModelSize = nil
            wheel.params.baseModelRadius = nil
            wheel.params.radius = radius
        end

        wheel.params.model = model
        wheel:SetModel( model )

        wheel.params.modelScale = scale
        wheel:ChangeRadius( radius )

        -- Flip the model offset/angle depending on which side of the vehicle it is
        if wheel.params.basePos[2] < 0 then
            wheel:SetModelOffset( -offset )
            wheel:SetModelAngle( angle + Angle( 0, 180, 0 ) )
        else
            wheel:SetModelOffset( offset )
            wheel:SetModelAngle( angle )
        end
    end

    ApplyVehicleWheelParameters = function( _ply, ent, paramsPerWheel )
        if not IsGlideVehicle( ent ) then return false end

        -- Make sure the target vehicle has at least one wheel
        local wheels = ent.wheels
        if type( wheels ) ~= "table" then return false end
        if #wheels < 1 then return false end

        local filteredParamsPerWheel = {}

        for index, params in pairs( paramsPerWheel ) do
            if type( index ) == "number" then
                -- Check if a wheel with this index exists
                local wheel = wheels[index]

                if wheel and not wheel.GlideIsHidden then
                    -- Apply parameters to this wheel
                    ApplyWheelParameters( wheel, params )

                    -- This can be saved
                    filteredParamsPerWheel[index] = params
                end
            end
        end

        duplicator.StoreEntityModifier( ent, "glide_wheel_params", filteredParamsPerWheel )

        return true
    end

    duplicator.RegisterEntityModifier( "glide_wheel_params", ApplyVehicleWheelParameters )
end

function TOOL:LeftClick()
    local wheel = self:GetAimingAtWheel()
    if not IsValid( wheel ) then return false end

    local vehicle = wheel:GetParent()
    if not IsGlideVehicle( vehicle ) then return false end

    if SERVER then
        local ply = self:GetOwner()

        if wheel.GlideIsHidden then
            Glide.SendNotification( ply, {
                text = "#tool.glide_wheel_editor.vehicle_model",
                icon = "materials/icon16/cancel.png",
                sound = "glide/ui/radar_alert.wav",
                immediate = true
            } )

            return false
        end

        local paramsPerWheel = {}

        if type( vehicle.EntityMods["glide_wheel_mods"] ) == "table" then
            paramsPerWheel = table.Copy( vehicle.EntityMods["glide_wheel_mods"] )
        end

        local setOnAllWheels = ply:KeyDown( IN_USE )

        for index, w in ipairs( vehicle.wheels ) do
            if wheel == w or setOnAllWheels then
                paramsPerWheel[index] = {
                    model = self:GetClientInfo( "model" ),
                    radius = self:GetClientNumber( "radius", 15 ),

                    scaleX = self:GetClientNumber( "scale_x", 1 ),
                    scaleY = self:GetClientNumber( "scale_y", 1 ),
                    scaleZ = self:GetClientNumber( "scale_z", 1 ),

                    offsetX = self:GetClientNumber( "offset_x", 1 ),
                    offsetY = self:GetClientNumber( "offset_y", 1 ),
                    offsetZ = self:GetClientNumber( "offset_z", 1 ),
                }

                if not setOnAllWheels then
                    break
                end
            end
        end

        return ApplyVehicleWheelParameters( ply, vehicle, paramsPerWheel )
    end

    return true
end

function TOOL:RightClick()
    local wheel = self:GetAimingAtWheel()
    if not IsValid( wheel ) then return false end

    if SERVER then
        local ply = self:GetOwner()

        ply:ConCommand( "glide_wheel_editor_radius " .. wheel:GetRadius() )
        ply:ConCommand( "glide_wheel_editor_model " .. wheel:GetModel() )
    end

    return true
end

function TOOL:Reload()
    return false
end

if not CLIENT then return end

local matWireframe = Material( "models/wireframe" )

function TOOL:DrawHUD()
    local wheel = self:GetAimingAtWheel()
    if not IsValid( wheel ) then return end

    local pulse = 0.6 + math.sin( RealTime() * 8 ) * 0.4

    cam.Start3D()
    render.SetColorMaterialIgnoreZ()
    render.SetColorModulation( 0, pulse * 0.4, pulse )
    render.SuppressEngineLighting( true )
    render.ModelMaterialOverride( matWireframe )

    wheel:SetupBones()
    wheel:DrawModel()

    render.ModelMaterialOverride( nil )
    render.SuppressEngineLighting( false )
    render.SetColorModulation( 1, 1, 1 )
    cam.End3D()
end

function TOOL.BuildCPanel( panel )
    local models = {}

    for path, _ in pairs( list.Get( "GlideWheelModels" ) ) do
        models[path] = { convar = path }
    end

    panel:AddControl( "slider", {
        Label = "#tool.glide_wheel_editor.radius",
        command = "glide_wheel_editor_radius",
        min = 10,
        max = 50
    } )

    panel:Help( "#tool.glide_wheel_editor.scale" )
    panel:NumSlider( "X", "glide_wheel_editor_scale_x", 0.1, 5, 2 )
    panel:NumSlider( "Y", "glide_wheel_editor_scale_y", 0.1, 5, 2 )
    panel:NumSlider( "Z", "glide_wheel_editor_scale_z", 0.1, 5, 2 )

    panel:Help( "#tool.glide_wheel_editor.offset" )
    panel:NumSlider( "X", "glide_wheel_editor_offset_x", -10, 10, 1 )
    panel:NumSlider( "Y", "glide_wheel_editor_offset_y", -10, 10, 1 )
    panel:NumSlider( "Z", "glide_wheel_editor_offset_z", -10, 10, 1 )

    panel:PropSelect( "#tool.glide_wheel_editor.model", "glide_wheel_editor_model", models, 5 )
end
