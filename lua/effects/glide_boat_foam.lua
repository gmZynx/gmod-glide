local RandomFloat = math.Rand
local TraceLine = util.TraceLine

local angles = Angle( 270, 0, 0 )
local traceOffset = Vector( 0, 0, 100 )

local ray = {}
local traceData = { mask = MASK_WATER, output = ray }

function EFFECT:Init( data )
    local origin = data:GetOrigin()
    local velocity = data:GetStart() * 0.5
    local scale = data:GetScale()
    local magnitude = data:GetMagnitude()

    local emitter = ParticleEmitter( origin, true )
    if not IsValid( emitter ) then return end

    -- Try to find a water surface above the origin
    traceData.start = origin + traceOffset
    traceData.endpos = origin

    TraceLine( traceData )

    if ray.Hit then
        origin = ray.HitPos
        origin[3] = origin[3] + 2
    end

    local p

    for _ = 1, 2 do
        p = emitter:Add( "effects/splashwake1", origin )

        if p then
            p:SetDieTime( RandomFloat( 1, 2 ) )
            p:SetStartAlpha( 50 * magnitude )
            p:SetEndAlpha( 0 )
            p:SetStartSize( RandomFloat( 40, 60 ) * scale * magnitude )
            p:SetEndSize( RandomFloat( 180, 300 ) * scale * magnitude )

            p:SetAirResistance( 200 )
            p:SetVelocity( velocity )
            p:SetAngles( angles )
            p:SetColor( 255, 255, 255 )
            p:SetCollide( false )
        end
    end

    emitter:Finish()
end

function EFFECT:Think()
    return false
end

function EFFECT:Render()
end
