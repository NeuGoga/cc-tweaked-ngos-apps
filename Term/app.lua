local w, h = term.getSize()

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

print("NgOS Terminal")
print("Type 'exit' to close.")

local realVersion = os.version
os.version = function() return "" end


shell.run("shell")

os.version = realVersion