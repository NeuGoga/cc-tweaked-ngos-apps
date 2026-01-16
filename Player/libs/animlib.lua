local player = {}
local zlib = require("zlib_decompress")
local base64 = require("base64")
local dfpwm = require("cc.audio.dfpwm") 

function player.play(master_filename, mon)
    local master_file = fs.open(master_filename, "r")
    if not master_file then return end
    local master_anim = textutils.unserializeJSON(master_file.readAll())
    master_file.close()
    
    if not master_anim then return end

    local header = master_anim.header
    local time_per_frame = 1 / (header.fps or 10)
    
    mon = mon or term.current()
    local original_scale = mon.getTextScale()
    mon.setTextScale(header.scale or 0.5)
    
    local mon_width, mon_height = mon.getSize()
    local anim_width, anim_height = header.width, header.height
    local x_offset = math.floor((mon_width - anim_width) / 2)
    local y_offset = math.floor((mon_height - anim_height) / 2)
    
    mon.setCursorPos(1, 1); mon.clear()

    -- State
    local isPaused = false
    local isStopped = false
    local isVisible = true -- Controls Monitor Rendering Only
    
    local audio_file_handle = nil
    local speaker_available = peripheral.find("speaker")
    local decoder = dfpwm.make_decoder()

    if speaker_available and master_anim.audio then
        local audio_path = fs.combine(fs.getDir(master_filename), master_anim.audio)
        if fs.exists(audio_path) then
            audio_file_handle = fs.open(audio_path, "rb")
        end
    end

    -- =============================================
    -- THREAD 1: Monitor Interaction (Touch)
    -- =============================================
    local function monitorInputThread()
        while not isStopped do
            local event, side, x, y = os.pullEvent()
            
            if event == "terminate_playback" then 
                break 
            
            elseif event == "monitor_touch" then
                -- Close [X] (Top Right)
                if y == 1 and x == mon_width then
                    isStopped = true
                    os.queueEvent("terminate_playback")
                    
                -- Minimize [-] (Top Left)
                elseif y == 1 and x == 1 then
                    isVisible = not isVisible
                    if isVisible then
                        mon.setBackgroundColor(colors.black)
                        mon.clear()
                    else
                        -- Optional: Draw a "Paused Rendering" text
                        mon.setBackgroundColor(colors.black)
                        mon.clear()
                        mon.setCursorPos(1,1)
                        mon.setTextColor(colors.gray)
                        mon.write("Rendering Paused (Click to Resume)")
                    end
                end
            end
        end
    end

    -- =============================================
    -- THREAD 2: Video Engine
    -- =============================================
    local function videoThread()
        local empty_text_line = string.rep(" ", header.width)
        local empty_fg_line = string.rep("0", header.width)
        
        local frame_buffer = {}
        for y=1, anim_height do 
            frame_buffer[y] = {}
            for x=1, anim_width do frame_buffer[y][x] = "f" end
        end

        local start_time = os.clock()
        local frames_played = 0

        for _, chunk_filename in ipairs(master_anim.chunks) do
            if isStopped then break end

            local full_path = fs.combine(fs.getDir(master_filename), chunk_filename)
            local f = fs.open(full_path, "rb")
            if not f then break end
            local content = f.readAll()
            f.close()
            
            local chunk_data = textutils.unserializeJSON(zlib.decompress(base64.decode(content:gsub("%s",""))))

            for _, frame in ipairs(chunk_data.frames) do
                if isStopped then break end
                
                while isPaused and not isStopped do
                    sleep(0.1)
                    start_time = os.clock() - (frames_played * time_per_frame)
                end

                if isVisible then
                    if frame.type == "full" then
                        local i = 1
                        for y = 1, header.height do
                            for x = 1, header.width do
                                frame_buffer[y][x] = string.sub(frame.bgs, i, i)
                                i = i + 1
                            end
                        end
                    elseif frame.type == "delta" then
                        for _, change in ipairs(frame.changes) do
                            frame_buffer[change.y][change.x] = change.bg
                        end
                    elseif frame.type == "bin_delta" then
                         local d = frame.data
                        for k = 1, #d, 3 do
                            local x = string.byte(d, k)
                            local y = string.byte(d, k+1)
                            local col = string.sub(d, k+2, k+2)
                            if frame_buffer[y] then frame_buffer[y][x] = col end
                        end
                    end

                    for y = 1, header.height do
                        mon.setCursorPos(1 + x_offset, y + y_offset)
                        local bg_line = table.concat(frame_buffer[y])
                        mon.blit(empty_text_line, empty_fg_line, bg_line)
                    end
                    
                end 

                frames_played = frames_played + 1
                local target_time = start_time + (frames_played * time_per_frame)
                local sleep_duration = target_time - os.clock()

                if sleep_duration > 0 then 
                    sleep(sleep_duration) 
                else
                    os.queueEvent("yield")
                    os.pullEvent("yield")
                end
            end
            pcall(collectgarbage, "collect")
        end
        isStopped = true
        os.queueEvent("terminate_playback")
    end

    -- =============================================
    -- THREAD 3: Audio (Independent)
    -- =============================================
    local function audioThread()
        if not audio_file_handle then return end
        local chunk_size = 6 * 1025

        while not isStopped do
            if isPaused then
                if speaker_available then speaker_available.stop() end
                while isPaused and not isStopped do sleep(0.1) end
            end

            local chunk = audio_file_handle.read(chunk_size)
            if not chunk then break end
            
            local pcm_data = decoder(chunk)
            local play_start_time = os.clock()
            
            while not speaker_available.playAudio(pcm_data) do
                local e = os.pullEvent()
                if e == "terminate_playback" then isStopped = true; break end
                
                if isStopped then break end
                if os.clock() - play_start_time > 0.5 then 
                    os.queueEvent("yield"); os.pullEvent("yield")
                    play_start_time = os.clock()
                end
            end
        end
        if audio_file_handle then audio_file_handle.close() end
        if speaker_available then speaker_available.stop() end
    end

    -- =============================================
    -- THREAD 4: Terminal Input
    -- =============================================

    local function inputThread()
        local w, h = term.getSize()
        
        -- Helper function to draw the bottom status bar
        local function drawStatus()
            term.setCursorPos(1, h)
            term.setBackgroundColor(colors.black)
            term.clearLine()
            
            if isPaused then
                term.setTextColor(colors.orange)
                term.write("PAUSED (Space to Resume)")
            else
                term.setTextColor(colors.lime)
                term.write("PLAYING (Space: Pause | Q: Quit)")
            end
        end
        
        -- 1. Clear the "Loading..." text from app.lua
        term.setBackgroundColor(colors.black)
        term.clear()
        
        drawStatus()

        while not isStopped do
            local event, p1 = os.pullEvent()
            
            if event == "terminate_playback" then 
                break 
                
            elseif event == "key" then
                if p1 == keys.q or p1 == keys.backspace then
                    isStopped = true
                    os.queueEvent("terminate_playback")
                elseif p1 == keys.space then
                    isPaused = not isPaused
                    drawStatus()
                end
            end
        end
    end

    parallel.waitForAll(videoThread, audioThread, inputThread, monitorInputThread)

    mon.setTextScale(original_scale)
    mon.setBackgroundColor(colors.black)
    mon.clear()
end

return player