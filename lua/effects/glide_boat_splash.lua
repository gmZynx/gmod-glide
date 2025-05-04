local RandomFloat = math.Rand
local TraceLine = util.TraceLine

local gravity = Vector( 0, 0, 0 )
local startVel = Vector( 0, 0, 0 )
local traceOffset = Vector( 0, 0, 50 )
local WORLD_UP = Vector( 0, 0, 1 )

local ray = {}
local traceData = { mask = MASK_WATER, output = ray }

function EFFECT:Init( data )
    local origin = data:GetOrigin()
    local velocity = data:GetStart() * 0.75
    local normal = data:GetNormal()
    local scale = data:GetScale()
    local magnitude = data:GetMagnitude()
    local length = data:GetRadius()

    local emitter = ParticleEmitter( origin, false )
    if not IsValid( emitter ) then return end

    -- Try to find a water surface above the origin
    traceData.start = origin + traceOffset
    traceData.endpos = origin

    TraceLine( traceData )

    if ray.Hit then
        origin = ray.HitPos
    end

    local right = WORLD_UP:Cross( normal )
    local p

    for _ = 1, 8 do
        p = emitter:Add( "effects/splash4", origin + right * RandomFloat( -length, length ) )

        if p then
            p:SetDieTime( 0.5 )
            p:SetStartAlpha( 100 * magnitude )
            p:SetEndAlpha( 0 )
            p:SetStartSize( 5 * scale )
            p:SetEndSize( 35 * scale )
            p:SetRoll( RandomFloat( -1, 1 ) )

            startVel[3] = RandomFloat( 100, 300 ) * scale * magnitude
            gravity[3] = RandomFloat( 800, 1200 ) * -scale

            p:SetAirResistance( 200 )
            p:SetGravity( gravity )
            p:SetVelocity( velocity + startVel + normal * RandomFloat( 150, 350 ) * scale * magnitude )
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
