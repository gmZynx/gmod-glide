local PlayerMeta = FindMetaTable( "Player" )
local EntityMeta = FindMetaTable( "Entity" )
local getNWEntity = EntityMeta.GetNWEntity

function PlayerMeta:GlideGetVehicle()
    return getNWEntity( self, "GlideVehicle", NULL )
end

function PlayerMeta:GlideGetSeatIndex()
    return getNWEntity( self, "GlideSeatIndex", -1 )
end

if SERVER then
    --- Get the player's Glide camera angles.
    function PlayerMeta:GlideGetCameraAngles()
        return self:LocalEyeAngles()
    end

    local TraceLine = util.TraceLine
    local eyePos = EntityMeta.EyePos

    function PlayerMeta:GlideGetAimPos()
        local origin = eyePos( self )

        return TraceLine( {
            start = origin,
            endpos = origin + self:GlideGetCameraAngles():Forward() * 50000,
            filter = { self, self:GlideGetVehicle() }
        } ).HitPos
    end

    --- Utility function to copy the entity creator
    --- or CPPI owner from one entity to another.
    function Glide.CopyEntityCreator( source, target )
        local ply

        if source.CPPIGetOwner then
            ply = source:CPPIGetOwner()
        end

        if type( ply ) == "number" then
            ply = nil
        end

        if not IsValid( ply ) then
            ply = source:GetCreator()
        end

        target:SetCreator( ply or NULL )

        if target.CPPISetOwner then
            target:CPPISetOwner( ply )
        end
    end
end
