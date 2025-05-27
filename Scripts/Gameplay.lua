-- Scripts/Gameplay.lua
local Gameplay = {}
local Parser_SM = require("Scripts.Parser_SM") -- Corrected module name

-- Configuration (existing)
local noteSpeed = 300 
local numLanes = 4
local laneKeys = {"a", "s", "w", "d"} 
local targetY = 150
local shapeSize = 50
local timingWindow = 25

function Gameplay:load()
    print("Gameplay module loaded")

    -- Attempt to load song data
    -- *** IMPORTANT: Worker needs to ensure "Songs/PARANOiA/PARANOiA.sm" exists with content from the URL ***
    self.currentSongData = Parser_SM.loadSongData("Songs/PARANOiA/PARANOiA.sm", "dance-single", "Medium") 

    if not self.currentSongData or not self.currentSongData.chart or not self.currentSongData.chart.timeBasedNotes then
        print("FATAL: Could not load chart data for Gameplay. Halting.")
        -- In a real game, switch to an error state or menu. For now, just stop.
        self.notesToPlay = {} -- Empty list to prevent errors
        love.event.quit("fatal_chart_load_error") 
    else
        self.notesToPlay = self.currentSongData.chart.timeBasedNotes
        print(string.format("--- Gameplay: Song '%s' loaded with %d notes. First note at %.2fs ---", 
            self.currentSongData.title, #self.notesToPlay, #self.notesToPlay > 0 and self.notesToPlay[1].time or 0))
    end

    self.songTime = 0.0  -- Time elapsed in the song (seconds)
    self.nextNoteIndex = 1 -- Index of the next note to spawn from self.notesToPlay

    -- Lane setup (existing)
    local screenWidth = love.graphics.getWidth()
    local totalLaneAreaWidth = screenWidth * 0.6 
    local laneGap = 20 
    self.laneWidth = (totalLaneAreaWidth - (laneGap * (numLanes - 1))) / numLanes
    local lanesStartX = (screenWidth - totalLaneAreaWidth) / 2
    self.lanePositionsX = {} 
    for i = 1, numLanes do
        self.lanePositionsX[i] = lanesStartX + (i - 1) * (self.laneWidth + laneGap) + self.laneWidth / 2
    end
    
    self.targets = {}
    for i = 1, numLanes do
        self.targets[i] = { x = self.lanePositionsX[i] - shapeSize / 2, y = targetY, width = shapeSize, height = shapeSize, color = {1,0,0,0.7}, centerY = targetY + shapeSize / 2, lane = i }
    end

    -- Single on-screen note object (reused)
    self.note = {
        x = 0, y = love.graphics.getHeight(), width = shapeSize, height = shapeSize,
        color = {0,1,0,1}, speed = noteSpeed, active = false, currentLane = 0, type = "1"
    }

    self.feedbackMessage = ""
    self.feedbackTimer = 0
    self.feedbackDuration = 0.75
end

function Gameplay:update(dt)
    self.songTime = self.songTime + dt

    -- Update feedback timer (existing)
    if self.feedbackTimer > 0 then
        self.feedbackTimer = self.feedbackTimer - dt
        if self.feedbackTimer <= 0 then self.feedbackMessage = "" end
    end

    -- Chart-driven note spawning
    if self.notesToPlay and self.nextNoteIndex <= #self.notesToPlay then
        local noteChartData = self.notesToPlay[self.nextNoteIndex]
        -- Check if it's time to spawn this note AND the note slot is free
        if self.songTime >= noteChartData.time then
            if not self.note.active then 
                self.note.currentLane = noteChartData.lane
                -- Validate lane number from chart data (should be 1-4 for dance-single)
                if self.note.currentLane >= 1 and self.note.currentLane <= numLanes then
                    self.note.x = self.lanePositionsX[self.note.currentLane] - self.note.width / 2
                    self.note.y = love.graphics.getHeight() -- Start from bottom
                    self.note.active = true
                    self.note.type = noteChartData.type -- Store note type (e.g., "1")
                    
                    print(string.format("Chart Note Spawned: SongTime=%.2f, NoteChartTime=%.2f, Lane=%d", self.songTime, noteChartData.time, self.note.currentLane))
                    
                    self.nextNoteIndex = self.nextNoteIndex + 1
                else
                    print(string.format("Warning: Chart note has invalid lane %d at time %.2f. Skipping.", noteChartData.lane, noteChartData.time))
                    self.nextNoteIndex = self.nextNoteIndex + 1 -- Skip invalid note
                end
            -- else
                -- Note slot is not free, and a new note is due.
                -- This means the player might have missed the previous one if it's still active past its hit window,
                -- or the chart is very dense. For a single on-screen note system, this new note is effectively skipped
                -- or delayed until the current note is cleared.
                -- The current logic will simply not spawn it this frame; it will be re-evaluated next frame.
                -- If a note is missed and passes the target, it becomes inactive, freeing the slot.
                -- If a note is hit, it becomes inactive, freeing the slot.
                -- print(string.format("Note Overlap/Delay: New note at %.2fs due, but current note still active. New note will attempt spawn next frame.", noteChartData.time))
            end
        end
    end

    -- Update active on-screen note (existing logic)
    if self.note.active then
        self.note.y = self.note.y - self.note.speed * dt
        
        -- Ensure currentTarget is valid before accessing its properties
        if self.note.currentLane >= 1 and self.note.currentLane <= numLanes then
            local currentTarget = self.targets[self.note.currentLane]
            if self.note.y + self.note.height < currentTarget.centerY - timingWindow then
                if self.note.active then 
                    print("Missed by passing! (Note passed target in lane " .. self.note.currentLane .. ") SongTime: " .. self.songTime)
                    self.feedbackMessage = "Miss!"
                    self.feedbackTimer = self.feedbackDuration
                    self.note.active = false -- Note becomes inactive
                end
            end
        else
            -- This case should ideally not be reached if lane validation at spawn time is robust.
            -- If it is, it means an active note has an invalid lane. Deactivate it to be safe.
            print("Warning: Active note has invalid lane: " .. self.note.currentLane .. ". Deactivating.")
            self.note.active = false
        end
    end
end

function Gameplay:draw()
    for i = 1, numLanes do
        local target = self.targets[i]; love.graphics.setColor(target.color)
        love.graphics.rectangle("fill", target.x, target.y, target.width, target.height)
        love.graphics.setColor(1,1,0,0.3); local wt = target.centerY-timingWindow; local wb = target.centerY+timingWindow
        love.graphics.rectangle("line", target.x-5, wt, target.width+10, wb-wt)
    end
    if self.note.active then
        love.graphics.setColor(self.note.color)
        love.graphics.rectangle("fill", self.note.x, self.note.y, self.note.width, self.note.height)
    end
    if self.feedbackTimer > 0 and self.feedbackMessage ~= "" then
        local font = love.graphics.getFont(); local tw = font:getWidth(self.feedbackMessage)
        local fc = {1,1,1,1}; if self.feedbackMessage == "OK!" then fc = {0,1,0,1} elseif self.feedbackMessage == "Miss!" then fc = {1,0,0,1} end
        love.graphics.setColor(fc)
        love.graphics.print(self.feedbackMessage, love.graphics.getWidth()/2 - tw/2, targetY + shapeSize + 20)
        love.graphics.setColor(1,1,1,1)
    end
    love.graphics.print("Song Time: " .. string.format("%.2f", self.songTime), 10, 10)
    if self.notesToPlay and self.nextNoteIndex <= #self.notesToPlay then
        love.graphics.print("Next Note Time: " .. string.format("%.2f", self.notesToPlay[self.nextNoteIndex].time), 10, 30)
    else love.graphics.print("No more notes or chart not loaded.", 10, 30) end
    if self.note.active then love.graphics.print("Active Note Lane: " .. self.note.currentLane, 10, 50) end
end

function Gameplay:keypressed(key, scancode, isrepeat)
    if key == "escape" then love.event.quit() end
    local pressedLane = nil
    for i=1,numLanes do if key==laneKeys[i] then pressedLane=i; break end end
    if pressedLane then
        if self.note.active and self.note.currentLane == pressedLane then
            local noteCenterY = self.note.y + self.note.height/2; 
            -- Ensure currentTarget is valid before accessing its properties
            if self.note.currentLane >= 1 and self.note.currentLane <= numLanes then
                 local targetCenterY = self.targets[pressedLane].centerY
                 local distance = math.abs(noteCenterY - targetCenterY)
                 if distance <= timingWindow then self.feedbackMessage = "OK!"; print("OK! Lane " .. pressedLane .. " SongTime: " .. self.songTime)
                 else self.feedbackMessage = "Miss!"; print("Miss! (Timing) Lane " .. pressedLane .. " SongTime: " .. self.songTime) end
                 self.feedbackTimer = self.feedbackDuration; self.note.active = false
            else
                print("Warning: Keypress on active note with invalid lane: " .. self.note.currentLane)
                self.note.active = false -- Deactivate to be safe
            end
        elseif self.note.active and self.note.currentLane ~= pressedLane then
            self.feedbackMessage = "Miss!"; print("Miss! (Wrong Lane) Pressed " .. pressedLane .. ", note in " .. self.note.currentLane .. " SongTime: " .. self.songTime); self.feedbackTimer = self.feedbackDuration
        else -- Note not active or already handled (pressed key for an empty target)
            -- This feedback can be noisy if player presses keys when no note is there.
            -- self.feedbackMessage = "Miss!"; print("Miss! (No active note in lane " .. pressedLane .. ")"); self.feedbackTimer = self.feedbackDuration
            print("Key press for lane " .. pressedLane .. " but no note active or note already handled. SongTime: " .. self.songTime)
        end
    end
end

return Gameplay
