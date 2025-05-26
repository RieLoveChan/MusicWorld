function love.load()
    -- Window setup
    love.window.setTitle("Rhythm Game")
    love.window.setMode(1920, 1080, {resizable=false, vsync=true})

    -- Game state management
    GameState = {}
    GameState.current = nil

    -- Load gameplay state
    Gameplay = require("Gameplay") -- Loads Gameplay.lua

    -- For now, directly assign Gameplay as we only have one state.
    -- Later, we'll have a proper state switcher.
    -- GameState.switch(Gameplay) -- This would be ideal
    GameState.current = Gameplay 
    
    if GameState.current and GameState.current.load then
        GameState.current:load() -- Use colon for method call
    end
end

function love.update(dt)
    if GameState.current and GameState.current.update then
        GameState.current:update(dt) -- Use colon for method call
    end
end

function love.draw()
    if GameState.current and GameState.current.draw then
        GameState.current:draw() -- Use colon for method call
    else
        love.graphics.print("Error: No current game state to draw.", 100, 100)
        -- If Gameplay module failed to load, GameState.current might be nil or not the expected table
        love.graphics.print("Is Gameplay.lua present and correct?", 100, 120) 
    end
end

function love.keypressed(key, scancode, isrepeat)
    if GameState.current and GameState.current.keypressed then
        GameState.current:keypressed(key, scancode, isrepeat) -- Use colon for method call
    end
end

-- Placeholder for a more robust game state switcher
-- function GameState.switch(state)
--     if GameState.current and GameState.current.leave then
--         GameState.current:leave()
--     end
--     GameState.current = state
--     if GameState.current and GameState.current.enter then
--         GameState.current:enter()
--     else
--         -- Fallback to load if enter doesn't exist for simple states
--         if GameState.current and GameState.current.load then
--             GameState.current:load()
--         end
--     end
-- end
