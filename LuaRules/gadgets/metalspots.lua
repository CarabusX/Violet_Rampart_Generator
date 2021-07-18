 
-- Metal Spot Gadget --------------------------------
-- Erases metal map and places new spots ------------
-----------------------------------------------------

function gadget:GetInfo()
    return {
        name = "Metalspots",
                desc = "Recreates metal map and places metal spots.",
                author = "qray",
                date = "April 2015",
                license = "GPL2",
                layer = -1000,
                enabled = true
    }
end
-----------------------------------------------------------------------------

-- list of one fifth of the spots
local spotpositions = {
    {x=5822,z=3250},
    {x=5811,z=3668},    
    {x=6139,z=3579},    
    {x=4888,z=2642},    
    {x=4596,z=2845},    
    {x=5005,z=3016},    
    {x=6173,z=4397},    
    {x=6668,z=4327},    
    {x=6338,z=4687},    
    {x=5776,z=4803},    
    {x=6849,z=4880},
} 

--local spotpositions = GG.mapgen_mexList


--UNSYNCED-------------------------------------------------------------------
if (not gadgetHandler:IsSyncedCode()) then
    
    -- localize everything (for performance)
    local glPushMatrix = gl.PushMatrix
    local glDepthTest = gl.DepthTest
    local glTexture = gl.Texture
    local glTranslate = gl.Translate
    local glDrawGroundQuad = gl.DrawGroundQuad
    local glTexRect = gl.TexRect
    local glPopMatrix = gl.PopMatrix
    local glColor = gl.Color
    local glBlending = gl.Blending
    local glCulling = gl.Culling
    local glMatrixMode= gl.MatrixMode
    local glPolygonOffset = gl.PolygonOffset
    local glCallList = gl.CallList
    local glCreateList = gl.CreateList

    local GL_SRC_ALPHA = GL.SRC_ALPHA
    local GL_ONE_MINUS_SRC_ALPHA = GL.ONE_MINUS_SRC_ALPHA

    local displayList
    
    function gadget:Initialize()
        displayList = glCreateList(drawPatches)
    end

    function gadget:DrawWorldPreUnit()
        glCallList(displayList)
    end

    function drawPatches()
        local metalSpotWidthhalf=40
        -- Switch to texture matrix mode
        glMatrixMode(GL.TEXTURE)
        
        glPolygonOffset(-24, -1)
        glCulling(GL.BACK)
        glDepthTest(true)
        glTexture(":a:bitmaps/map/metalspot.png" )
        glColor(1, 1, 1, 0.45) 
        glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
        for _, coor in ipairs(spotpositions) do
            glPushMatrix()
            glDrawGroundQuad( coor.x - metalSpotWidthhalf, coor.z - metalSpotWidthhalf, coor.x + metalSpotWidthhalf, coor.z + metalSpotWidthhalf, true, 0.0,0.0, 1.0,1.0)
            glPopMatrix()
        end
        glTexture(false)
        glDepthTest(false)
        glCulling(false)
        glPolygonOffset(false)
        -- Restore Modelview matrix
        glMatrixMode(GL.MODELVIEW)
    end    
    
end
-----------------------------------------------------------------------------
