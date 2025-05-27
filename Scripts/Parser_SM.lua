-- Scripts/Parser_SM.lua
local Parser_SM = {}

-- (deepcopy and parseBeatValuePairs functions remain the same)
function deepcopy(orig) local orig_type = type(orig) local copy if orig_type == 'table' then copy = {} for orig_key, orig_value in next, orig, nil do copy[deepcopy(orig_key)] = deepcopy(orig_value) end setmetatable(copy, deepcopy(getmetatable(orig))) else copy = orig end return copy end
local function parseBeatValuePairs(valueString) local items = {} if valueString and valueString ~= "" then for pair in valueString:gmatch("([^,]+)") do local beat, val = pair:match("([^=]+)=(.+)") if beat and val then local numBeat = tonumber(beat) local numVal = tonumber(val) if numBeat ~= nil and numVal ~= nil then table.insert(items, { beat = numBeat, value = numVal }) else print("Warning: Could not parse beat-value pair: " .. pair) end else print("Warning: Malformed beat-value pair: " .. pair) end end table.sort(items, function(a, b) return a.beat < b.beat end) end return items end

local function calculateTimeBasedNotes(beatBasedNotes, bpms, stops, offset)
    local timeBasedNotes = {}
    if #bpms == 0 then
        print("Error in calculateTimeBasedNotes: No BPMs provided.")
        return timeBasedNotes -- Return empty if no BPMs, should have been caught earlier
    end

    local events = {}
    for _, bpmEvent in ipairs(bpms) do
        table.insert(events, { beat = bpmEvent.beat, type = "bpm", value = bpmEvent.bpm })
    end
    for _, stopEvent in ipairs(stops) do
        table.insert(events, { beat = stopEvent.beat, type = "stop", value = stopEvent.duration })
    end
    for _, noteEvent in ipairs(beatBasedNotes) do
        table.insert(events, { beat = noteEvent.beat, type = "note", lane = noteEvent.lane, originalType = noteEvent.type })
    end

    -- Sort events: by beat, then by type (bpm -> stop -> note) to ensure correct processing order
    table.sort(events, function(a, b)
        if a.beat ~= b.beat then
            return a.beat < b.beat
        else
            -- Prioritize BPM changes, then stops, then notes at the same beat
            local typePriority = { bpm = 1, stop = 2, note = 3 }
            return typePriority[a.type] < typePriority[b.type]
        end
    end)

    local currentTime = offset or 0.0 -- Start with the song's offset
    local lastProcessBeat = 0.0
    local currentBPM = -1 -- Will be set by the first relevant BPM event

    -- Determine initial BPM: Find the BPM for beat 0 or the earliest beat.
    -- This logic ensures that currentBPM is set before processing any events that rely on it.
    local initialBpmSet = false
    for _, event in ipairs(events) do
        if event.type == "bpm" then
            if event.beat <= 0 then -- If a BPM is at or before beat 0
                currentBPM = event.value
                lastProcessBeat = event.beat -- Important: adjust lastProcessBeat if BPM is before 0
                initialBpmSet = true
                break -- Found the definitive BPM for beat 0 or earliest point
            end
            if not initialBpmSet then -- If no BPM at beat 0 yet, take the first one encountered
                 currentBPM = event.value
                 -- lastProcessBeat will be set to this event's beat in the main loop if it's the first event
                 initialBpmSet = true 
                 -- Do not break, continue to see if there's one closer to beat 0
            end
        end
    end
    
    if not initialBpmSet and #bpms > 0 then 
        -- Fallback if all BPMs are after the first note/event (unlikely in valid SM)
        currentBPM = bpms[1].bpm 
        print("Warning: No BPM defined at or before the first event. Using first listed BPM: " .. currentBPM)
    elseif not initialBpmSet then
        print("Critical Error: No BPMs available to start timing calculations.")
        return {} -- Cannot proceed
    end


    for _, event in ipairs(events) do
        if event.beat > lastProcessBeat then
            local timeElapsed = (event.beat - lastProcessBeat) * (60.0 / currentBPM)
            currentTime = currentTime + timeElapsed
        end
        -- If event.beat is not > lastProcessBeat, it means it's at the same beat.
        -- currentTime should already be correct up to this beat due to prior events or initialization.
        
        lastProcessBeat = event.beat

        if event.type == "bpm" then
            currentBPM = event.value
        elseif event.type == "stop" then
            currentTime = currentTime + event.value -- Add stop duration
        elseif event.type == "note" then
            table.insert(timeBasedNotes, {
                time = currentTime,
                lane = event.lane,
                type = event.originalType
            })
        end
    end
    return timeBasedNotes
end

function Parser_SM.loadSongData(filePath, targetGametype, targetDifficulty)
    -- (Previous code for file reading, metadata, bpms, stops, chart selection, raw notes parsing)
    targetGametype = targetGametype or "dance-single"; targetDifficulty = targetDifficulty or "Medium"
    print(string.format("Parser_SM.loadSongData: File='%s', TargetChart='%s - %s'", filePath, targetGametype, targetDifficulty))
    local file = io.open(filePath, "r"); if not file then print("Error: Could not open file: " .. filePath); return nil end
    local songData = { title = "", subtitle = "", artist = "", banner = "", background = "", cdtitle = "", music = "", offset = 0.0, sampleStart = 0.0, sampleLength = 10.0, displayBpm = "", bpms = {}, stops = {}, chart = { found = false, gametype = "", description = "", difficulty = "", meter = 0, grooveRadar = "", rawData = "", beatBasedNotes = {}, timeBasedNotes = {} } }
    local lines = {}; for line in file:lines() do table.insert(lines, line) end; file:close()
    local i = 1
    while i <= #lines do
        local line = lines[i]:match("^%s*(.-)%s*$")
        if line:sub(1, 2) == "//" then -- Comment
        elseif line:sub(1, 1) == "#" then
            local tag, value = line:match("^#([^:]*):([^;]*);?$"); if tag then value = value or "" end
            if tag and value ~= nil then
                tag = tag:upper()
                if tag == "TITLE" then songData.title = value elseif tag == "SUBTITLE" then songData.subtitle = value elseif tag == "ARTIST" then songData.artist = value elseif tag == "BANNER" then songData.banner = value elseif tag == "BACKGROUND" then songData.background = value elseif tag == "CDTITLE" then songData.cdtitle = value elseif tag == "MUSIC" then songData.music = value elseif tag == "OFFSET" then songData.offset = tonumber(value) or songData.offset elseif tag == "SAMPLESTART" then songData.sampleStart = tonumber(value) or songData.sampleStart elseif tag == "SAMPLELENGTH" then songData.sampleLength = tonumber(value) or songData.sampleLength elseif tag == "DISPLAYBPM" then songData.displayBpm = value
                elseif tag == "BPMS" then local pB = parseBeatValuePairs(value); for _, item in ipairs(pB) do table.insert(songData.bpms, {beat=item.beat, bpm=item.value}) end
                elseif tag == "STOPS" then local pS = parseBeatValuePairs(value); for _, item in ipairs(pS) do table.insert(songData.stops, {beat=item.beat, duration=item.value}) end
                elseif tag == "NOTES" or tag == "NOTES2" then
                    if songData.chart.found then i=i+1; goto cloop end; if i+5 > #lines then i=i+1; goto cloop end
                    local cgt = (lines[i+1]:match("^%s*(.-):%s*$") or ""):match("^%s*(.-)%s*$"); local cd = (lines[i+2]:match("^%s*(.-):%s*$") or ""):match("^%s*(.-)%s*$"); local cdiff = (lines[i+3]:match("^%s*(.-):%s*$") or ""):match("^%s*(.-)%s*$"); local cms = (lines[i+4]:match("^%s*(%d*):%s*$") or ""); local cgr = (lines[i+5]:match("^%s*(.-):%s*$") or ""):match("^%s*(.-)%s*$")
                    if cgt == targetGametype and cdiff == targetDifficulty then
                        songData.chart.found = true; songData.chart.gametype = cgt; songData.chart.description = cd; songData.chart.difficulty = cdiff; songData.chart.meter = tonumber(cms) or 0; songData.chart.grooveRadar = cgr
                        local rnl = {}; i=i+6; while i <= #lines do local nl = lines[i]:match("^%s*(.-)%s*$"); if nl == ";" then break end table.insert(rnl, nl); i=i+1 end; songData.chart.rawData = table.concat(rnl, "
")
                    else i=i+6; while i <= #lines do if lines[i]:match("^%s*%;%s*$") then break end i=i+1 end end
                end
            end
        end
        ::cloop:: i=i+1
    end
    if songData.title=="" then print("Err: #TITLE missing: "..filePath); return nil end; if songData.music=="" then print("Err: #MUSIC missing: "..filePath); return nil end; if #songData.bpms==0 then print("Err: #BPMS missing/invalid: "..filePath); return nil end
    if not songData.chart.found then print(string.format("Err: Chart '%s-%s' not found: %s",targetGametype,targetDifficulty,filePath)); return nil end; if songData.chart.rawData=="" then print(string.format("Err: Chart notes empty for '%s-%s': %s",targetGametype,targetDifficulty,filePath)); return nil end
    
    local currentBeat = 0.0; for mi, mData in ipairs(songData.chart.rawData:gmatch("([^,]+)")) do local lns={}; local nLns=0; for lStr in mData:gmatch("[^
]+") do if lStr:match("%S") then table.insert(lns,lStr);nLns=nLns+1 end end
        if nLns>0 then local bpl=4.0/nLns; for li,lsc in ipairs(lns) do for ci=1,#lsc do local ch=lsc:sub(ci,ci); if ch=="1" then table.insert(songData.chart.beatBasedNotes,{beat=currentBeat,lane=ci,type="1"})end end; currentBeat=currentBeat+bpl end
        else currentBeat=currentBeat+4.0 end
    end; table.sort(songData.chart.beatBasedNotes,function(a,b)return a.beat<b.beat end)
    if #songData.chart.beatBasedNotes==0 and songData.chart.rawData~="" then print(string.format("Warn: No tap notes in chart '%s-%s': %s",targetGametype,targetDifficulty,filePath)) end

    -- Perform beat-to-time conversion
    songData.chart.timeBasedNotes = calculateTimeBasedNotes(songData.chart.beatBasedNotes, songData.bpms, songData.stops, songData.offset)

    if #songData.chart.timeBasedNotes == 0 and #songData.chart.beatBasedNotes > 0 then
        print(string.format("Warning: Time-based note conversion resulted in 0 notes, but beat-based notes were present for %s chart '%s - %s'. Check BPMs/Offset.", filePath, targetGametype, targetDifficulty))
    end
    
    print(string.format("Successfully parsed %d beat-based and %d time-based tap notes for: %s (%s)", #songData.chart.beatBasedNotes, #songData.chart.timeBasedNotes, songData.title, songData.chart.difficulty))
    return songData
end

return Parser_SM
