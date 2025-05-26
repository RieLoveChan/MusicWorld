local Gameplay = {}

-- Configuration
local targetY = 150
local noteSpeed = 300
local shapeSize = 50
local timingWindow = 25 -- pixels for hit accuracy (distance from center)

function Gameplay:load()
    print("Gameplay module loaded")

    self.target = {
        x = love.graphics.getWidth() / 2 - shapeSize / 2,
        y = targetY,
        width = shapeSize,
        height = shapeSize,
        color = {1, 0, 0, 1} -- Red
    }
    self.target.centerY = self.target.y + self.target.height / 2

    self.note = {
        x = love.graphics.getWidth() / 2 - shapeSize / 2,
        y = love.graphics.getHeight(),
        width = shapeSize,
        height = shapeSize,
        color = {0, 1, 0, 1}, -- Green
        speed = noteSpeed,
        active = true
    }

    -- Feedback display
    self.feedbackMessage = ""
    self.feedbackTimer = 0
    self.feedbackDuration = 0.75 -- seconds message stays on screen
    
    -- Font for feedback message (optional, but good for styling)
    -- Ensure you have a font file (e.g., "arial.ttf") or use default
    -- self.feedbackFont = love.graphics.newFont("arial.ttf", 36) 
end

function Gameplay:update(dt)
    -- Update feedback timer
    if self.feedbackTimer > 0 then
        self.feedbackTimer = self.feedbackTimer - dt
        if self.feedbackTimer <= 0 then
            self.feedbackMessage = ""
        end
    end

    if self.note.active then
        self.note.y = self.note.y - self.note.speed * dt

        -- Miss condition: Note passed target active zone
        -- The active zone is target.centerY +/- timingWindow
        if self.note.y + self.note.height < self.target.centerY - timingWindow then
            if self.note.active then -- Check again, in case it was hit just before this frame
                print("Missed! (Note passed target)")
                self.feedbackMessage = "Miss!"
                self.feedbackTimer = self.feedbackDuration
                self.note.active = false
            end
        end
    end

    -- Note reset logic
    if not self.note.active then
        -- For now, reset immediately. Could add a delay here.
        self.note.y = love.graphics.getHeight()
        self.note.active = true
        -- Potentially clear feedback if it's tied to a specific note instance
        -- self.feedbackMessage = "" -- Uncomment if feedback should clear on new note
    end
end

function Gameplay:draw()
    -- Draw shapes
    if self.note.active then
        love.graphics.setColor(self.note.color)
        love.graphics.rectangle("fill", self.note.x, self.note.y, self.note.width, self.note.height)
    end

    love.graphics.setColor(self.target.color)
    love.graphics.rectangle("fill", self.target.x, self.target.y, self.target.width, self.target.height)

    -- Draw timing window visualization
    love.graphics.setColor(1,1,0,0.3)
    local windowTop = self.target.centerY - timingWindow
    local windowBottom = self.target.centerY + timingWindow
    love.graphics.rectangle("line", self.target.x - 5, windowTop, self.target.width + 10, windowBottom - windowTop)

    -- Draw feedback message
    if self.feedbackTimer > 0 and self.feedbackMessage ~= "" then
        -- if self.feedbackFont then love.graphics.setFont(self.feedbackFont) end
        local textWidth = (love.graphics.getFont():getWidth(self.feedbackMessage)) -- Use current font
        love.graphics.setColor(1,1,1,1)
        if self.feedbackMessage == "OK!" then
            love.graphics.setColor(0,1,0,1) -- Green for OK
        elseif self.feedbackMessage == "Miss!" then
            love.graphics.setColor(1,0,0,1) -- Red for Miss
        end
        love.graphics.print(self.feedbackMessage, love.graphics.getWidth() / 2 - textWidth / 2, self.target.y + self.target.height + 20)
        love.graphics.setColor(1,1,1,1) -- Reset color
        -- love.graphics.setFont(love.graphics.newFont(12)) -- Reset to default font if you changed it
    end
    
    -- Debug info
    love.graphics.setColor(1,1,1,1)
    love.graphics.print("Note Y: " .. string.format("%.2f", self.note.y), 10, 10)
end

function Gameplay:keypressed(key, scancode, isrepeat)
    if key == "escape" then
        love.event.quit()
    end

    if key == "space" and self.note.active then
        local noteCenterY = self.note.y + self.note.height / 2
        local distance = math.abs(noteCenterY - self.target.centerY)

        if distance <= timingWindow then
            print("OK! Distance: " .. string.format("%.2f", distance))
            self.feedbackMessage = "OK!"
            self.feedbackTimer = self.feedbackDuration
        else
            print("Miss! (Pressed at wrong time) Distance: " .. string.format("%.2f", distance))
            self.feedbackMessage = "Miss!"
            self.feedbackTimer = self.feedbackDuration
        end
        self.note.active = false -- Deactivate note after hit attempt
    end
end

return Gameplay
