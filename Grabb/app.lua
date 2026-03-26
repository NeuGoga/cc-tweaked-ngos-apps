local w, h = term.getSize()

local C_BG = colors.black
local C_ACCENT = colors.cyan
local C_TEXT = colors.white
local C_DIM = colors.gray
local C_ERR = colors.red
local C_DIR = colors.yellow

local repo = ""
local tree = {}
local currentPath = ""
local selected = {}
local scrollOffset = 0
local statusMsg = ""
local view = "welcome"

local function parseURL(input)
    local match = input:match("github%.com/([^/]+/[^/]+)")
    if match then return match end
    if input:match("^[^/]+/[^/]+$") then return input end
    return nil
end

local function fetchFullTree()
    local url = string.format("https://api.github.com/repos/%s/git/trees/main?recursive=1", repo)
    local resp = http.get(url)
    
    if not resp then
        url = string.format("https://api.github.com/repos/%s/git/trees/master?recursive=1", repo)
        resp = http.get(url)
    end
    
    if not resp then 
        statusMsg = "Error: Repo not found or API limit reached."
        return false 
    end
    
    local data = textutils.unserializeJSON(resp.readAll())
    resp.close()
    
    if not data or not data.tree then 
        statusMsg = "Error: Invalid repository data."
        return false 
    end
    
    tree = data.tree
    statusMsg = ""
    return true
end

local function getVisibleItems()
    local items = {}
    local pattern = "^" .. (currentPath == "" and "" or currentPath .. "/") .. "([^/]+)$"
    for _, item in ipairs(tree) do
        local name = item.path:match(pattern)
        if name then
            table.insert(items, { 
                name = name, 
                fullPath = item.path, 
                type = (item.type == "tree" and "dir" or "file") 
            })
        end
    end
    table.sort(items, function(a, b) 
        if a.type ~= b.type then return a.type == "dir" end 
        return a.name:lower() < b.name:lower() 
    end)
    return items
end

local function performDownload()
    term.setBackgroundColor(C_BG)
    term.clear()
    term.setCursorPos(1,1)
    term.setTextColor(C_TEXT)
    
    local toDownload = {}
    for path, isSel in pairs(selected) do
        if isSel then
            for _, item in ipairs(tree) do
                if item.type == "blob" and (item.path == path or item.path:sub(1, #path + 1) == path .. "/") then
                    table.insert(toDownload, item.path)
                end
            end
        end
    end

    if #toDownload == 0 then 
        print("Nothing selected!")
        sleep(1)
        return 
    end

    print("Downloading " .. #toDownload .. " files...")
    for i, relPath in ipairs(toDownload) do
        local rawUrl = string.format("https://raw.githubusercontent.com/%s/main/%s", repo, relPath)
        
        term.setTextColor(C_DIM)
        write(string.format("[%d/%d] %s... ", i, #toDownload, fs.getName(relPath)))
        
        local r = http.get(rawUrl, nil, true)
        if not r then r = http.get(rawUrl:gsub("/main/", "/master/"), nil, true) end

        if r then
            local localPath = fs.combine("/media", relPath)
            
            local ok, err = pcall(function()
                local dir = fs.getDir(localPath)
                if not fs.exists(dir) then fs.makeDir(dir) end
                
                local f = fs.open(localPath, "wb")
                if not f then error("Cannot open file (Disk full?)") end
                f.write(r.readAll())
                f.close()
            end)
            r.close()
            
            if ok then
                term.setTextColor(colors.lime)
                print("OK")
            else
                term.setTextColor(colors.red)
                print("ERR")
                term.setTextColor(colors.orange)
                print("   " .. tostring(err))
            end
        else
            term.setTextColor(colors.red)
            print("FAIL")
        end
    end
    
    term.setTextColor(C_TEXT)
    print("\nDownload finished.")
    print("Press Enter to return.")
    read()
    
    selected = {}
    view = "browsing"
end

local function doWelcome()
    term.setBackgroundColor(C_BG)
    term.clear()
    
    term.setTextColor(C_ACCENT)
    local logo = {
        "   _____           _     _     ",
        "  / ____|         | |   | |    ",
        " | |  __ _ __ __ _| |__ | |__  ",
        " | | |_ | '__/ _` | '_ \\| '_ \\ ",
        " | |__| | | | (_| | |_) | |_) |",
        "  \\_____|_|  \\__,_|_.__/|_.__/ "
    }
    for i, line in ipairs(logo) do
        term.setCursorPos(math.floor((w - #line)/2), 1 + i)
        print(line)
    end
    
    term.setTextColor(C_DIM)
    local sub = "Download folders from GitHub."
    term.setCursorPos(math.floor((w - #sub)/2), 9)
    print(sub)
    
    term.setTextColor(C_DIM)
    term.setCursorPos(2, 15)
    print("Examples:")
    print(" > NeuGoga/cc-tweaked-ngos-apps")
    print(" > https://github.com/user/repo")
    
    term.setTextColor(C_TEXT)
    term.setCursorPos(2, 11)
    print("Enter GitHub URL or User/Repo:")
    term.setCursorPos(2, 12)
    term.setTextColor(C_ACCENT)
    term.write("> ")
    
    if statusMsg ~= "" then
        term.setCursorPos(2, 13)
        term.setTextColor(C_ERR)
        term.clearLine()
        term.write(statusMsg)
    end
    
    term.setCursorPos(4, 12)
    term.setTextColor(C_TEXT)
    term.setCursorBlink(true)
    local input = read()
    term.setCursorBlink(false)
    
    if input and input ~= "" then
        local parsed = parseURL(input)
        if parsed then
            repo = parsed
            term.setCursorPos(2, 13)
            term.setTextColor(C_ACCENT)
            term.clearLine()
            term.write("Fetching repository...")
            
            if fetchFullTree() then
                view = "browsing"
                currentPath = ""
                selected = {}
                scrollOffset = 0
            end
        else
            statusMsg = "Invalid Repo Format!"
        end
    end
end

local function drawBrowser()
    term.setBackgroundColor(C_BG)
    term.clear()
    
    term.setCursorPos(1,1)
    term.setBackgroundColor(C_DIM)
    term.setTextColor(C_TEXT)
    term.clearLine()
    term.write(" Grabb | " .. repo)
    
    term.setCursorPos(1,2)
    term.setBackgroundColor(C_BG)
    term.setTextColor(C_ACCENT)
    term.clearLine()
    term.write(" /" .. currentPath)
    
    local visible = getVisibleItems()
    local listY = 4
    
    if currentPath ~= "" then
        term.setCursorPos(2, listY)
        term.setTextColor(C_DIR)
        term.write("^  [ .. ]")
        listY = listY + 1
    end

    for i = 1 + scrollOffset, #visible do
        if listY > h - 1 then break end
        local item = visible[i]
        term.setCursorPos(2, listY)
        
        if selected[item.fullPath] then
            term.setTextColor(C_ACCENT)
            term.write("[*] ")
        else
            term.setTextColor(C_DIM)
            term.write("[ ] ")
        end
        
        if item.type == "dir" then
            term.setTextColor(C_DIR)
            term.write("D ")
        else
            term.setTextColor(C_TEXT)
            term.write("  ")
        end
        
        term.write(item.name)
        item.renderY = listY
        listY = listY + 1
    end
    
    term.setCursorPos(1, h)
    term.setBackgroundColor(C_ACCENT)
    term.setTextColor(C_BG)
    term.write(" [ Download ] ")
    
    term.setCursorPos(w - 14, h)
    term.setBackgroundColor(C_DIM)
    term.setTextColor(C_TEXT)
    term.write(" [ Change Repo ] ")
end

while true do
    if view == "welcome" then
        doWelcome()
    elseif view == "browsing" then
        drawBrowser()
        local event, btn, x, y = os.pullEvent()
        
        if event == "mouse_click" then
            if y == h then
                if x < 15 then 
                    performDownload()
                elseif x > w - 15 then 
                    view = "welcome"
                    repo = "" 
                    statusMsg = ""
                end
            
            elseif y >= 4 and y < h then
                local visible = getVisibleItems()
                local listYStart = (currentPath == "" and 4 or 5)
                
                if y == 4 and currentPath ~= "" then
                    local parts = {}
                    for p in currentPath:gmatch("[^/]+") do table.insert(parts, p) end
                    table.remove(parts)
                    currentPath = table.concat(parts, "/")
                    scrollOffset = 0
                else
                    local idx = (y - listYStart) + 1 + scrollOffset
                    if idx > 0 and idx <= #visible then
                        local item = visible[idx]
                        if x < 6 then 
                            selected[item.fullPath] = not selected[item.fullPath]
                        elseif item.type == "dir" then 
                            currentPath = item.fullPath
                            scrollOffset = 0 
                        end
                    end
                end
            end
            
        elseif event == "mouse_scroll" then
            if btn == 1 then 
                scrollOffset = scrollOffset + 1
            elseif scrollOffset > 0 then 
                scrollOffset = scrollOffset - 1 
            end
            
        elseif event == "key" and btn == keys.b then
            if currentPath ~= "" then
                local parts = {}
                for p in currentPath:gmatch("[^/]+") do table.insert(parts, p) end
                table.remove(parts)
                currentPath = table.concat(parts, "/")
                scrollOffset = 0
            else
                view = "welcome"
                repo = ""
                statusMsg = ""
            end
        end
    end
end