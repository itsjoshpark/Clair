on modStr(m)
	set s to ""
	if m is missing value then return ""
	-- AX modifiers: 0=cmd, bit1 shift, bit2 option, bit4 control, bit8 no-cmd
	if (m div 4) mod 2 = 1 then set s to s & "Ctrl+"
	if (m div 2) mod 2 = 1 then set s to s & "Opt+"
	if m mod 2 = 1 then set s to s & "Shift+"
	if (m div 8) mod 2 = 0 then set s to s & "Cmd+"
	return s
end modStr
on walk(theMenu, prefix)
	set out to ""
	tell application "System Events"
		repeat with mi in (menu items of theMenu)
			try
				set n to name of mi
				if n is not missing value then
					set k to ""
					try
						set c to value of attribute "AXMenuItemCmdChar" of mi
						if c is not missing value then
							set m to value of attribute "AXMenuItemCmdModifiers" of mi
							set k to my modStr(m) & c
						end if
					end try
					try
						set g to value of attribute "AXMenuItemCmdGlyph" of mi
						if g is not missing value and k is "" then set k to "glyph" & g
					end try
					set out to out & prefix & n & "	" & k & linefeed
					try
						if exists menu 1 of mi then set out to out & my walk(menu 1 of mi, prefix & n & " > ")
					end try
				end if
			end try
		end repeat
	end tell
	return out
end walk
tell application "System Events"
	tell process "Arc"
		set res to ""
		repeat with mbi in (menu bar items of menu bar 1)
			set res to res & my walk(menu 1 of mbi, (name of mbi) & " > ")
		end repeat
	end tell
end tell
return res
