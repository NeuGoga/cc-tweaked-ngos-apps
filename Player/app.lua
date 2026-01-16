local runningProgram = shell.getRunningProgram()
local appDir = fs.getDir(runningProgram)
local libDir = "/apps/Player/libs"

-- Prepend our local lib folder to package.path
-- This ensures require() looks here FIRST, overriding any system libs
package.path = libDir .. "/?.lua;" .. package.path

local animlib = require("animlib")

-- UI Constants & Setup
local UI_HEADER = colors.yellow
local UI_TEXT = colors.white
local UI_ACCENT = colors.cyan
local UI_BG = colors.black
local UI_ERROR = colors.red
local UI_DIM = colors.gray

local MEDIA_DIR = "/media"

local mon = _G.SystemMonitor or peripheral.find("monitor")
local speaker = peripheral.find("speaker")

local scroll_offset = 0
local anims_list = {}

local function drawIdleScreen()
    if mon then
        local w, h = mon.getSize()
        mon.setBackgroundColor(colors.black)
        mon.clear()
        mon.setTextColor(colors.gray)
        mon.setTextScale(0.5)
        local text = "Waiting for media input..."
        mon.setCursorPos(math.floor((w - #text)/2) + 1, math.floor(h/2))
        mon.write(text)
    end
end

drawIdleScreen()

-- Scanning Logic (Scans the root directory for .mcanim)
local function scanForAnimations()
    -- Create directory if missing
    if not fs.exists(MEDIA_DIR) then
        fs.makeDir(MEDIA_DIR)
    end

    local found = {}
    local list = fs.list(MEDIA_DIR)
    table.sort(list)
    
    -- Scan inside the media folder
    for _, folderName in ipairs(list) do
        -- Path: /media
        local fullFolderPath = fs.combine(MEDIA_DIR, folderName)
        
        if fs.isDir(fullFolderPath) then
            local subList = fs.list(fullFolderPath)
            for _, subItem in ipairs(subList) do
                if subItem:sub(-7) == ".mcanim" then
                    local rawName = subItem:sub(1, -8)
                    local cleanName = rawName:gsub("^anim_", ""):gsub("^vis_", ""):gsub("_", " ")
                    
                    table.insert(found, {
                        path = fs.combine(fullFolderPath, subItem),
                        name = cleanName,
                        display_str = "[Play] " .. cleanName
                    })
                end
            end
        end
    end
    return found
end

-- Drawing Logic
local function drawMenu()
    term.setBackgroundColor(UI_BG)
    term.clear()
    
    term.setCursorPos(1,1)
    term.setTextColor(UI_HEADER)
    term.write("=== Animation Player ===")
    
    term.setCursorPos(1,2)
    term.setTextColor(UI_DIM)
    term.write((mon and "MONITOR OK" or "NO MON") .. " | " .. (speaker and "SPK OK" or "NO SPK"))

    term.setCursorPos(1,3)
    term.setTextColor(UI_HEADER)
    term.write(string.rep("-", 20))

    local w, h = term.getSize()
    local available_lines = h - 4
    
    if #anims_list == 0 then
        term.setCursorPos(1, 5)
        term.setTextColor(UI_ERROR)
        term.write("No animations found!")
    else
        for i = 1, available_lines do
            local index = i + scroll_offset
            if index <= #anims_list then
                local anim = anims_list[index]
                term.setCursorPos(1, 3 + i)
                term.setTextColor(UI_ACCENT)
                term.write("[Play] ")
                term.setTextColor(UI_TEXT)
                term.write(anim.name)
            end
        end
    end
end

-- Main Loop
anims_list = scanForAnimations()

while true do
    drawMenu()
    drawIdleScreen()
    local event, p1, x, y = os.pullEvent()
    
    if event == "app_visibility" and p1 == "hide" then
        repeat local e, s = os.pullEvent("app_visibility") until s == "show"
    
    elseif event == "mouse_scroll" then
        if p1 == 1 and scroll_offset + (term.getSize()-4) < #anims_list then
            scroll_offset = scroll_offset + 1
        elseif p1 == -1 and scroll_offset > 0 then
            scroll_offset = scroll_offset - 1
        end

    elseif event == "mouse_click" then
        local w, h = term.getSize()
        
        -- Clicked List Item
        local list_y = y - 3
        local clicked_index = list_y + scroll_offset
        
        if y >= 4 and y < h and clicked_index <= #anims_list and clicked_index > 0 then
            local selected = anims_list[clicked_index]
            
            term.setCursorPos(1, y)
            term.clearLine()
            term.setTextColor(colors.lime)
            term.write(">> Loading...")
            
            if mon then mon.clear() end
            sleep(0.1)

            local ok, err = pcall(animlib.play, selected.path, mon)
            
            if mon then mon.clear() end
            drawIdleScreen()
            
            if not ok then
                term.setBackgroundColor(colors.black)
                term.clear()
                term.setCursorPos(1,1)
                print("Error: " .. tostring(err))
                print("Press any key...")
                os.pullEvent("key")
            end
        end
    end
end