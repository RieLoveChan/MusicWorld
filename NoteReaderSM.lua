-- NoteReaderSM.lua
-- A parser for StepMania (.sm) files, adapted for Love2D.
-- Based on concepts from StepMania's NotesLoaderSM.cpp.

local NoteReaderSM = {}

--[[-------------------------------------------------------------------------
-- String Utilities
---------------------------------------------------------------------------]]

local function trim(s)
    if type(s) ~= "string" then return s end
    return string.gsub(s, "^%s*(.-)%s*$", "%1")
end

-- Splits a string by a separator.
-- Note: For simple character separators. Complex patterns might need more robust splitting.
local function split(str, sep)
    if type(str) ~= "string" then return {} end
    if sep == nil then sep = "%s" end
    local t = {}
    local pattern = "([^" .. sep .. "]+)"
    if sep == "" then -- Split into characters if sep is empty string
        pattern = "."
    end
    for k in string.gmatch(str, pattern) do
        table.insert(t, k)
    end
    return t
end


--[[-------------------------------------------------------------------------
-- Tag Value Parsers
---------------------------------------------------------------------------]]

-- Parses beat=value,beat=value,... style lists.
-- valueConverter is an optional function to convert the 'value' part.
local function parseBeatEqualsValueList(valueString, valueConverter, valueName)
    valueConverter = valueConverter or tonumber
    valueName = valueName or "value"
    local items = {}
    if not valueString or trim(valueString) == "" then return items end

    for part in string.gmatch(valueString, "[^,]+") do
        part = trim(part)
        local beatStr, valStr = string.match(part, "^([^=]+)=(.*)$")
        if beatStr and valStr then
            local beat = tonumber(trim(beatStr))
            local val = valueConverter(trim(valStr))
            if beat ~= nil and val ~= nil then
                local entry = { beat = beat }
                entry[valueName] = val
                table.insert(items, entry)
            else
                print("Warning: Could not parse beat-value pair: " .. part .. " (beat=" .. tostring(beat) .. ", val=" .. tostring(val) .. ")")
            end
        else
            print("Warning: Malformed beat-value entry: " .. part)
        end
    end
    table.sort(items, function(a,b) return a.beat < b.beat end)
    return items
end

local function parseBPMs(valueString)
    local bpms = {}
    if not valueString or trim(valueString) == "" then return bpms end
    for part in string.gmatch(valueString, "[^,]+") do
        part = trim(part)
        local beatStr, bpmStr = string.match(part, "^([^=]+)=(.*)$")
        if beatStr and bpmStr then
            local beat = tonumber(trim(beatStr))
            local bpm = tonumber(trim(bpmStr))
            if beat ~= nil and bpm ~= nil and bpm > 0 then
                table.insert(bpms, { beat = beat, bpm = bpm })
            else
                print("Warning: Invalid BPM entry: " .. part .. " (BPM must be > 0)")
            end
        else
            print("Warning: Malformed BPM entry: " .. part)
        end
    end
    table.sort(bpms, function(a,b) return a.beat < b.beat end)
    return bpms
end

local function parseStopsOrDelays(valueString, tagName)
    tagName = tagName or "Stop/Freeze/Delay"
    local items = {}
    if not valueString or trim(valueString) == "" then return items end
    for part in string.gmatch(valueString, "[^,]+") do
        part = trim(part)
        local beatStr, durationStr = string.match(part, "^([^=]+)=(.*)$")
        if beatStr and durationStr then
            local beat = tonumber(trim(beatStr))
            local duration = tonumber(trim(durationStr))
            if beat ~= nil and duration ~= nil and duration > 0 then
                table.insert(items, { beat = beat, duration = duration })
            else
                print("Warning: Invalid " .. tagName .. " entry: " .. part .. " (duration must be > 0)")
            end
        else
            print("Warning: Malformed " .. tagName .. " entry: " .. part)
        end
    end
    table.sort(items, function(a,b) return a.beat < b.beat end)
    return items
end

local function parseWarps(valueString)
    local warps = {}
    if not valueString or trim(valueString) == "" then return warps end
    for part in string.gmatch(valueString, "[^,]+") do
        part = trim(part)
        local beatStr, lengthStr = string.match(part, "^([^=]+)=(.*)$")
        if beatStr and lengthStr then
            local beat = tonumber(trim(beatStr))
            local length = tonumber(trim(lengthStr))
            -- Warp length in SM5 must be positive. Negative length warps are bugs or from older/custom formats.
            if beat ~= nil and length ~= nil and length > 0 then
                table.insert(warps, { beat = beat, length = length })
            else
                print("Warning: Invalid Warp entry: " .. part .. " (length must be > 0)")
            end
        else
            print("Warning: Malformed Warp entry: " .. part)
        end
    end
    table.sort(warps, function(a,b) return a.beat < b.beat end)
    return warps
end

local function parseTimeSignatures(valueString)
    local timeSignatures = {}
    if not valueString or trim(valueString) == "" then return timeSignatures end
    for part in string.gmatch(valueString, "[^,]+") do
        part = trim(part)
        local beatStr, numStr, denStr = string.match(part, "^([^=]+)=([^=]+)=([^=]+)$")
        if beatStr and numStr and denStr then
            local beat = tonumber(trim(beatStr))
            local num = tonumber(trim(numStr))
            local den = tonumber(trim(denStr))
            if beat ~= nil and num ~= nil and den ~= nil and num > 0 and den > 0 then
                table.insert(timeSignatures, { beat = beat, numerator = num, denominator = den })
            else
                print("Warning: Invalid TimeSignature entry: " .. part)
            end
        else
            print("Warning: Malformed TimeSignature entry: " .. part)
        end
    end
    table.sort(timeSignatures, function(a,b) return a.beat < b.beat end)
    return timeSignatures
end

local function parseTickCounts(valueString)
    return parseBeatEqualsValueList(valueString, tonumber, "ticks")
end

local function parseLabels(valueString)
    return parseBeatEqualsValueList(valueString, trim, "label")
end

local function parseSpeeds(valueString)
    local speeds = {}
    if not valueString or trim(valueString) == "" then return speeds end
    for part in string.gmatch(valueString, "[^,]+") do
        part = trim(part)
        local beatStr, ratioStr, durationStr, unitStr = string.match(part, "^([^=]+)=([^=]+)=([^=]+)(?:=([^=]+))?$")
        if beatStr and ratioStr and durationStr then
            local beat = tonumber(trim(beatStr))
            local ratio = tonumber(trim(ratioStr))
            local duration = tonumber(trim(durationStr))
            local unit = tonumber(unitStr or "0") -- Default to 0 (beats)

            if beat ~= nil and ratio ~= nil and duration ~= nil and unit ~= nil then
                if ratio <= 0 then print("Warning: Speed ratio must be positive: " .. part); goto continue_speed end
                if duration < 0 then print("Warning: Speed duration must be non-negative: " .. part); goto continue_speed end
                if unit ~= 0 and unit ~= 1 then print("Warning: Speed unit must be 0 (beats) or 1 (seconds): " .. part); goto continue_speed end
                
                table.insert(speeds, {
                    beat = beat,
                    ratio = ratio,
                    duration = duration,
                    unitIsSeconds = (unit == 1)
                })
            else
                print("Warning: Invalid Speed entry (numeric conversion failed): " .. part)
            end
        else
            print("Warning: Malformed Speed entry: " .. part)
        end
        ::continue_speed::
    end
    table.sort(speeds, function(a,b) return a.beat < b.beat end)
    return speeds
end

local function parseScrolls(valueString)
    local scrolls = {}
    if not valueString or trim(valueString) == "" then return scrolls end
    for part in string.gmatch(valueString, "[^,]+") do
        part = trim(part)
        local beatStr, ratioStr = string.match(part, "^([^=]+)=(.*)$")
        if beatStr and ratioStr then
            local beat = tonumber(trim(beatStr))
            local ratio = tonumber(trim(ratioStr))
            if beat ~= nil and ratio ~= nil then
                table.insert(scrolls, { beat = beat, ratio = ratio })
            else
                print("Warning: Invalid Scroll entry (numeric conversion): " .. part)
            end
        else
            print("Warning: Malformed Scroll entry: " .. part)
        end
    end
    table.sort(scrolls, function(a,b) return a.beat < b.beat end)
    return scrolls
end

local function parseFakeRegions(valueString) -- For #FAKES tag (regions), not individual fake notes
    local fakes = {}
    if not valueString or trim(valueString) == "" then return fakes end
    for part in string.gmatch(valueString, "[^,]+") do
        part = trim(part)
        local beatStr, lengthStr = string.match(part, "^([^=]+)=(.*)$")
        if beatStr and lengthStr then
            local beat = tonumber(trim(beatStr))
            local length = tonumber(trim(lengthStr))
            if beat ~= nil and length ~= nil and length > 0 then
                table.insert(fakes, { beat = beat, length = length })
            else
                print("Warning: Invalid Fake Region entry: " .. part .. " (length must be > 0)")
            end
        else
            print("Warning: Malformed Fake Region entry: " .. part)
        end
    end
    table.sort(fakes, function(a,b) return a.beat < b.beat end)
    return fakes
end

-- Simplified parser for BGCHANGES/FGCHANGES. Full format is complex.
-- Format: beat=filename=rate=transition=effect=color1=color2=color3=colorduration=colorcalc
local function parseBG_FG_Changes(valueString, tagName)
    tagName = tagName or "BG/FG Change"
    local changes = {}
    if not valueString or trim(valueString) == "" then return changes end
    
    for entryStr in string.gmatch(valueString, "[^,]+") do
        entryStr = trim(entryStr)
        local params = split(entryStr, "=")

        if #params >= 1 then -- Must have at least a beat
            local beat = tonumber(params[1])
            if beat == nil then
                print("Warning: Invalid " .. tagName .. " entry, beat is not a number: " .. entryStr)
                goto continue_change
            end

            local change = {
                beat = beat,
                fileName = trim(params[2] or ""),
                rate = tonumber(params[3]) or 1.0,
                transitionType = trim(params[4] or ""),
                effect = trim(params[5] or ""),
                -- For simplicity, not parsing color strings or other advanced params yet
                -- color1 = trim(params[6] or ""),
                -- color2 = trim(params[7] or ""),
                -- file2 (for some effects) = trim(params[8] or ""), -- Indexing might vary based on effect
            }
            table.insert(changes, change)
        else
            print("Warning: Malformed " .. tagName .. " entry: " .. entryStr)
        end
        ::continue_change::
    end
    table.sort(changes, function(a,b) return a.beat < b.beat end)
    return changes
end


--[[-------------------------------------------------------------------------
-- Notes Data Parser (#NOTES:)
---------------------------------------------------------------------------]]
local function parseNotesData(linesIterator, chartTable)
    -- Helper to get the next significant line from the iterator
    local function getNextNonCommentLine(iter)
        for l in iter do
            l = trim(l)
            if string.sub(l, 1, 2) ~= "//" and #l > 0 then
                return l
            end
        end
        return nil -- EOF or no more valid lines
    end

    -- 1. Game type (e.g., dance-single)
    chartTable.gameType = getNextNonCommentLine(linesIterator)
    if not chartTable.gameType then print("Warning: Unexpected end of file or missing gameType for chart."); return false end
    chartTable.gameType = trim(string.gsub(chartTable.gameType, ":$", "")) -- Remove trailing colon if present

    -- 2. Description (e.g., difficulty name - Beginner, Hard, Challenge)
    chartTable.description = getNextNonCommentLine(linesIterator)
    if not chartTable.description then print("Warning: Unexpected end of file or missing description for chart '" .. chartTable.gameType .. "'."); return false end
    chartTable.description = trim(string.gsub(chartTable.description, ":$", ""))

    -- 3. Difficulty class (e.g., Easy, Medium, Hard - often same as description)
    chartTable.difficultyClass = getNextNonCommentLine(linesIterator)
    if not chartTable.difficultyClass then print("Warning: Unexpected end of file or missing difficultyClass for chart '" .. chartTable.description .. "'."); return false end
    chartTable.difficultyClass = trim(string.gsub(chartTable.difficultyClass, ":$", ""))

    -- 4. Difficulty meter (a number)
    local meterStr = getNextNonCommentLine(linesIterator)
    if not meterStr then print("Warning: Unexpected end of file or missing difficultyMeter for chart '" .. chartTable.description .. "'."); return false end
    chartTable.difficultyMeter = tonumber(trim(string.gsub(meterStr, ":$", "")))
    if not chartTable.difficultyMeter then
        print("Warning: Invalid difficulty meter value '" .. meterStr .. "' for chart '" .. chartTable.description .. "'. Defaulting to 0.")
        chartTable.difficultyMeter = 0
    end

    -- 5. Radar values (comma-separated floats)
    local radarValuesString = getNextNonCommentLine(linesIterator)
    if not radarValuesString then print("Warning: Unexpected end of file or missing radarValues for chart '" .. chartTable.description .. "'."); return false end
    radarValuesString = trim(string.gsub(radarValuesString, ":$", ""))
    chartTable.radarValues = {}
    for valStr in string.gmatch(radarValuesString, "[^,]+") do
        local val = tonumber(trim(valStr))
        if val then
            table.insert(chartTable.radarValues, val)
        else
            print("Warning: Invalid radar value '" .. valStr .. "' in chart '" .. chartTable.description .. "'.")
        end
    end

    -- 6. Actual note data
    chartTable.notes = {}
    local currentMeasure = {}
    for line in linesIterator do
        line = trim(line)

        if string.sub(line, 1, 2) == "//" then -- Skip comments within note data
            goto continue_notedata_loop
        end

        if line == ";" then -- End of current chart's notes
            if #currentMeasure > 0 then
                table.insert(chartTable.notes, currentMeasure)
            end
            return true -- Successfully parsed this chart's notes
        
        elseif line == "," then -- End of current measure
            -- Add the measure, even if it's empty (represented by an empty table)
            table.insert(chartTable.notes, currentMeasure)
            currentMeasure = {}
        
        elseif #line > 0 then -- A line of note data (e.g., "1000", "0M10")
            -- Validate characters? For now, just store the string.
            -- Note characters: 0, 1, 2, 3, 4, M, L, F, K (K is keysound, often ignored for gameplay)
            -- Ensure the line only contains valid note characters or is appropriate for the gameType?
            -- For now, assume valid characters.
            table.insert(currentMeasure, line)
        
        -- elseif #line == 0 then -- Empty line, often ignored or treated as padding.
            -- Do nothing, effectively skipping empty lines within measures.
        end
        ::continue_notedata_loop::
    end

    -- If EOF was hit before a ';'. This is technically an malformed notes section.
    if #currentMeasure > 0 then
        table.insert(chartTable.notes, currentMeasure)
    end
    print("Warning: Note data for chart '" .. chartTable.description .. "' did not end with ';'. EOF reached.")
    return false -- Indicates notes might be incomplete or improperly terminated
end


--[[-------------------------------------------------------------------------
-- Main SM File Loader
---------------------------------------------------------------------------]]
function NoteReaderSM.load(filePath)
    local file = io.open(filePath, "r")
    if not file then
        print("Error: Could not open file: " .. filePath)
        return nil, "Could not open file: " .. filePath
    end

    local song = {
        -- Header information
        title = "", subtitle = "", artist = "",
        titleTranslit = "", subtitleTranslit = "", artistTranslit = "",
        genre = "", credit = "", banner = "", background = "",
        lyricsPath = "", cdTitle = "", music = "",
        offset = 0, sampleStart = 0, sampleLength = 0,
        selectable = true, -- Default to YES

        -- Timing data
        bpms = {}, stops = {}, delays = {}, warps = {},
        timeSignatures = {}, tickCounts = {}, labels = {},
        speeds = {}, scrolls = {}, fakes = {}, -- Fake regions

        -- Background/Foreground changes
        bgChanges = {}, fgChanges = {},

        -- Charts
        charts = {},

        -- Unknown tags, for debugging or future use
        unknownTags = {}
    }

    local linesIterator = file:lines()

    for lineContent in linesIterator do
        local line = trim(lineContent)

        -- Skip comments and empty lines
        if string.sub(line, 1, 2) == "//" or #line == 0 then
            goto continue_main_loop
        end

        -- Match #TAG:VALUE; (semicolon is optional for most tags, but crucial for #NOTES end)
        -- The value can be empty.
        local tag, value = string.match(line, "^#([^:]+):([^;]*);?$")

        if tag then
            tag = string.upper(trim(tag))
            value = trim(value or "") -- Ensure value is a string

            if tag == "NOTES" or tag == "NOTES2" then
                local newChart = {
                    gameType = nil, description = nil, difficultyClass = nil,
                    difficultyMeter = 0, radarValues = {}, notes = {}
                }
                -- The 'value' part of the #NOTES: line itself is sometimes used for the game type,
                -- or the first piece of metadata. However, the C++ parser often expects these
                -- on subsequent lines. parseNotesData is designed to read them from linesIterator.
                -- If 'value' is not empty, it might be the gameType.
                -- For now, parseNotesData handles reading all 6 metadata items from the iterator.
                
                local success = parseNotesData(linesIterator, newChart)
                
                -- Add chart if parsing was successful or if it contains some minimal data
                if success or newChart.description or #newChart.notes > 0 then
                    table.insert(song.charts, newChart)
                else
                    print("Warning: A chart section was encountered but not parsed successfully or was empty.")
                end
                -- linesIterator is now positioned after the parsed notes section.
            
            -- Process other known tags
            elseif tag == "TITLE" then song.title = value
            elseif tag == "SUBTITLE" then song.subtitle = value
            elseif tag == "ARTIST" then song.artist = value
            elseif tag == "TITLETRANSLIT" then song.titleTranslit = value
            elseif tag == "SUBTITLETRANSLIT" then song.subtitleTranslit = value
            elseif tag == "ARTISTTRANSLIT" then song.artistTranslit = value
            elseif tag == "GENRE" then song.genre = value
            elseif tag == "CREDIT" then song.credit = value
            elseif tag == "BANNER" then song.banner = value
            elseif tag == "BACKGROUND" then song.background = value
            elseif tag == "LYRICSPATH" then song.lyricsPath = value
            elseif tag == "CDTITLE" then song.cdTitle = value
            elseif tag == "MUSIC" then song.music = value
            elseif tag == "OFFSET" then song.offset = tonumber(value) or 0
            elseif tag == "SAMPLESTART" then song.sampleStart = tonumber(value) or 0
            elseif tag == "SAMPLELENGTH" then song.sampleLength = tonumber(value) or 0
            elseif tag == "SELECTABLE" then
                if string.upper(value) == "YES" then song.selectable = true
                elseif string.upper(value) == "NO" then song.selectable = false
                else song.selectable = value -- Could be ROSETTA:xxx or other specific values
                end
            elseif tag == "BPMS" then song.bpms = parseBPMs(value)
            elseif tag == "STOPS" or tag == "FREEZES" then song.stops = parseStopsOrDelays(value, tag)
            elseif tag == "DELAYS" then song.delays = parseStopsOrDelays(value, tag)
            elseif tag == "WARPS" then song.warps = parseWarps(value)
            elseif tag == "TIMESIGNATURES" then song.timeSignatures = parseTimeSignatures(value)
            elseif tag == "TICKCOUNTS" then song.tickCounts = parseTickCounts(value)
            elseif tag == "LABELS" then song.labels = parseLabels(value)
            elseif tag == "SPEEDS" then song.speeds = parseSpeeds(value)
            elseif tag == "SCROLLS" then song.scrolls = parseScrolls(value)
            elseif tag == "FAKES" then song.fakes = parseFakeRegions(value) -- Note: This is for #FAKES regions, not individual F notes.
            elseif tag == "BGCHANGES" then song.bgChanges = parseBG_FG_Changes(value, "BGChange")
            elseif tag == "FGCHANGES" then song.fgChanges = parseBG_FG_Changes(value, "FGChange")
            -- Other tags from SM5 spec that might be useful:
            -- ATTACKS, COMBOS (often for mods), KEYSOUNDS
            else
                print("Info: Unknown or unhandled SM tag: #" .. tag .. ":" .. value)
                song.unknownTags[tag] = value
            end
        else
            -- Line is not a comment, not empty, and not a recognized #TAG:VALUE; line.
            -- This could be a malformed line in the SM file.
            -- If this occurs outside a #NOTES section (which parseNotesData handles), it's an anomaly.
            print("Warning: Unrecognized line in SM file (expected a #Tag:Value; line): " .. line)
        end
        ::continue_main_loop::
    end

    file:close()
    return song
end

return NoteReaderSM

--[[
Example Usage (in a Love2D project, e.g., main.lua):

local NoteReaderSM = require("NoteReaderSM") -- Assuming NoteReaderSM.lua is in the same directory or LÖVE path

function love.load()
    local songData = NoteReaderSM.load("path/to/your/song.sm")
    if songData then
        print("Song Title: " .. songData.title)
        print("Artist: " .. songData.artist)
        print("Offset: " .. songData.offset)

        if songData.bpms and #songData.bpms > 0 then
            print("First BPM change: beat " .. songData.bpms[1].beat .. " to " .. songData.bpms[1].bpm .. " BPM")
        end

        print(#songData.charts .. " chart(s) found:")
        for i, chart in ipairs(songData.charts) do
            print(string.format("  Chart %d: %s - %s (Meter: %s)",
                i, chart.gameType, chart.description, tostring(chart.difficultyMeter)))
            if chart.notes and #chart.notes > 0 then
                print(string.format("    First measure of chart %d has %d rows/lines.", i, #chart.notes[1]))
                -- For example, print the first row of the first measure:
                -- if chart.notes[1] and #chart.notes[1] > 0 then
                --     print("      First row: " .. chart.notes[1][1])
                -- end
            end
        end
    else
        print("Failed to load SM file.")
    end
end

]]

