local w, h = term.getSize()
local currentPath = "/"
local scrollOffset = 0
local fileList = {}

local C_BG = colors.black
local C_HEADER = colors.gray
local C_HEADER_TXT = colors.white
local C_DIR = colors.yellow
local C_FILE = colors.white
local C_EXE = colors.lime
local C_MEDIA = colors.cyan
local C_DIM = colors.lightGray

local function getExt(filename)
    return filename:match("^.+(%..+)$")
end

local function formatSize(num)
    if num >= 1048576 then return string.format("%.1fM", num/1048576) end
    if num >= 1024 then return string.format("%.1fk", num/1024) end
    return tostring(num)
end

local function sortFiles(a, b)
    if a.isDir and not b.isDir then return true end
    if not a.isDir and b.isDir then return false end
    return a.name:lower() < b.name:lower()
end

local function scan()
    fileList = {}
    local rawList = fs.list(currentPath)
    
    for _, name in ipairs(rawList) do
        local fullPath = fs.combine(currentPath, name)
        table.insert(fileList, {
            name = name,
            isDir = fs.isDir(fullPath),
            size = fs.getSize(fullPath),
            path = fullPath
        })
    end
    
    table.sort(fileList, sortFiles)
    
    if currentPath ~= "" and currentPath ~= "/" then
        table.insert(fileList, 1, {
            name = "..",
            isDir = true,
            size = 0,
            path = fs.getDir(currentPath)
        })
    end
end

local function openItem(item)
    if item.isDir then
        currentPath = item.path
        scrollOffset = 0
        scan()
    else
        local ext = getExt(item.name)
        
        if ext == ".lua" then
            shell.run("edit", item.path)
            
        elseif ext == ".txt" or ext == ".json" or ext == ".cfg" then
            shell.run("edit", item.path)
            
        else
            shell.run(item.path)
        end
        
        term.setBackgroundColor(C_BG)
        term.clear()
    end
end

local function draw()
    term.setBackgroundColor(C_BG)
    term.clear()
    
    term.setCursorPos(1, 1)
    term.setBackgroundColor(C_HEADER)
    term.setTextColor(C_HEADER_TXT)
    term.clearLine()
    
    local displayPath = currentPath
    if displayPath == "" then displayPath = "/" end
    if #displayPath > w - 2 then displayPath = "..." .. string.sub(displayPath, -(w-5)) end
    
    term.write(" " .. displayPath)
    
    local availableRows = h - 2
    for i = 1, availableRows do
        local index = i + scrollOffset
        if index <= #fileList then
            local item = fileList[index]
            local y = i + 1
            
            term.setCursorPos(2, y)
            term.setBackgroundColor(C_BG)
            
            if item.isDir then
                term.setTextColor(C_DIR)
                if item.name == ".." then
                    term.write("^  ..")
                else
                    term.write("D  " .. item.name)
                end
            else
                -- Color coding
                local ext = getExt(item.name)
                if ext == ".lua" then term.setTextColor(C_EXE)
                elseif ext == ".mcanim" or ext == ".dfpwm" then term.setTextColor(C_MEDIA)
                else term.setTextColor(C_FILE) end
                
                term.write("   " .. item.name)
                
                if w > 20 then
                    local sizeStr = formatSize(item.size) .. "b"
                    term.setTextColor(C_DIM)
                    term.setCursorPos(w - #sizeStr, y)
                    term.write(sizeStr)
                end
            end
        end
    end
    
    if #fileList > availableRows then
        term.setCursorPos(w, 2)
        term.setTextColor(C_DIM)
        term.write("^")
        term.setCursorPos(w, h)
        term.write("v")
    end
end

scan()

while true do
    draw()
    local event, p1, x, y = os.pullEvent()
    
    if event == "mouse_scroll" then
        if p1 == 1 and scrollOffset + (h-2) < #fileList then
            scrollOffset = scrollOffset + 1
        elseif p1 == -1 and scrollOffset > 0 then
            scrollOffset = scrollOffset - 1
        end
        
    elseif event == "mouse_click" then
        if y > 1 and y <= h then
            local index = (y - 1) + scrollOffset
            if index > 0 and index <= #fileList then
                openItem(fileList[index])
                scan()
            end
        end
        
    elseif event == "key" then
        if p1 == keys.backspace or p1 == keys.left then
             if currentPath ~= "" and currentPath ~= "/" then
                currentPath = fs.getDir(currentPath)
                scrollOffset = 0
                scan()
            end
        elseif p1 == keys.f5 then
            scan()
        end
    end
end