--!strict
--[[
	SyntaxHighlight

	Colours Lua/Luau in ```lua code blocks (UI/MessageText): keywords,
	strings, numbers, comments, function calls and Roblox globals, in
	colours for the light or dark theme. Returns RichText.

	Usage:
		if SyntaxHighlight.isSupported("luau") then
			label.Text = SyntaxHighlight.highlight(code, palette)
		end
]]

local SyntaxHighlight = {}

-- Lua/Luau keywords
local KEYWORDS = {
	["and"] = true,
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["goto"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["until"] = true,
	["while"] = true,
	-- Luau additions
	["continue"] = true,
	["export"] = true,
	["type"] = true,
}

-- Lua/Luau built-in globals and functions
local BUILTINS = {
	-- Basic functions
	["print"] = true,
	["warn"] = true,
	["error"] = true,
	["assert"] = true,
	["type"] = true,
	["tostring"] = true,
	["tonumber"] = true,
	["next"] = true,
	["pairs"] = true,
	["ipairs"] = true,
	["select"] = true,
	["pcall"] = true,
	["xpcall"] = true,
	["require"] = true,
	["typeof"] = true,
	["rawget"] = true,
	["rawset"] = true,
	["rawequal"] = true,
	["setmetatable"] = true,
	["getmetatable"] = true,
	-- String
	["string"] = true,
	["table"] = true,
	["math"] = true,
	["os"] = true,
	["io"] = true,
	["debug"] = true,
	["coroutine"] = true,
	["utf8"] = true,
	["_G"] = true,
	["_VERSION"] = true,
	-- Luau globals
	["game"] = true,
	["workspace"] = true,
	["script"] = true,
	["plugin"] = true,
	["Enum"] = true,
	["Vector2"] = true,
	["Vector3"] = true,
	["CFrame"] = true,
	["Color3"] = true,
	["UDim2"] = true,
	["UDim"] = true,
	["Rect"] = true,
	["Instance"] = true,
	["ColorSequence"] = true,
	["NumberSequence"] = true,
	["NumberRange"] = true,
	["PhysicalProperties"] = true,
	["TweenInfo"] = true,
	["RaycastParams"] = true,
	["OverlapParams"] = true,
	["Random"] = true,
	["DateTime"] = true,
	["task"] = true,
	["bit32"] = true,
	["buffer"] = true,
}

-- Types
local TYPES = {
	["string"] = true,
	["number"] = true,
	["boolean"] = true,
	["table"] = true,
	["function"] = true,
	["thread"] = true,
	["userdata"] = true,
	["nil"] = true,
	["any"] = true,
	["never"] = true,
	["unknown"] = true,
}

-- Token colours for dark and light chats (GitHub's code colours)
local COLORS = {
	dark = {
		keyword = "#FF7B72",
		builtin = "#FFA657",
		type = "#79C0FF",
		string = "#A5D6FF",
		number = "#79C0FF",
		comment = "#8B949E",
		call = "#D2A8FF",
	},
	light = {
		keyword = "#CF222E",
		builtin = "#953800",
		type = "#0550AE",
		string = "#0A3069",
		number = "#0550AE",
		comment = "#6E7781",
		call = "#8250DF",
	},
}

-- Escape HTML entities for RichText
local function escape(text: string): string
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

-- Check if a word is a keyword
local function isKeyword(word: string): boolean
	return KEYWORDS[word] == true
end

-- Check if a word is a builtin
local function isBuiltin(word: string): boolean
	return BUILTINS[word] == true
end

-- Check if a word is a type
local function isType(word: string): boolean
	return TYPES[word] == true
end

-- Tokenize Lua/Luau code
local function tokenize(code: string): { { type: string, text: string } }
	local tokens = {}
	local i = 1
	local len = #code

	while i <= len do
		local char = string.sub(code, i, i)

		-- Whitespace
		if string.match(char, "%s") then
			local start = i
			while i <= len and string.match(string.sub(code, i, i), "%s") do
				i += 1
			end
			table.insert(tokens, { type = "whitespace", text = string.sub(code, start, i - 1) })
			continue
		end

		-- Comments (-- or --[[ ]])
		if char == "-" and i + 1 <= len and string.sub(code, i + 1, i + 1) == "-" then
			if i + 2 <= len and string.sub(code, i + 2, i + 2) == "[" then
				-- Long comment --[[ ... ]]
				local start = i
				i += 3
				while i <= len do
					if string.sub(code, i, i) == "]" and i + 1 <= len and string.sub(code, i + 1, i + 1) == "]" then
						i += 2
						break
					end
					i += 1
				end
				table.insert(tokens, { type = "comment", text = string.sub(code, start, i - 1) })
			else
				-- Line comment -- ...
				local start = i
				while i <= len and string.sub(code, i, i) ~= "\n" do
					i += 1
				end
				table.insert(tokens, { type = "comment", text = string.sub(code, start, i - 1) })
			end
			continue
		end

		-- Strings (single, double, or long [[ ]])
		if char == '"' or char == "'" then
			local quote = char
			local start = i
			i += 1
			while i <= len do
				local c = string.sub(code, i, i)
				if c == "\\" then
					i += 2 -- Skip escaped character
				elseif c == quote then
					i += 1
					break
				else
					i += 1
				end
			end
			table.insert(tokens, { type = "string", text = string.sub(code, start, i - 1) })
			continue
		end

		if char == "[" and i + 1 <= len and string.sub(code, i + 1, i + 1) == "[" then
			-- Long string [[ ... ]]
			local start = i
			i += 2
			while i <= len do
				if string.sub(code, i, i) == "]" and i + 1 <= len and string.sub(code, i + 1, i + 1) == "]" then
					i += 2
					break
				end
				i += 1
			end
			table.insert(tokens, { type = "string", text = string.sub(code, start, i - 1) })
			continue
		end

		-- Numbers
		if
			string.match(char, "%d")
			or (char == "." and i + 1 <= len and string.match(string.sub(code, i + 1, i + 1), "%d"))
		then
			local start = i
			local hasDot = false
			while i <= len do
				local c = string.sub(code, i, i)
				if string.match(c, "%d") then
					i += 1
				elseif
					c == "."
					and not hasDot
					and i + 1 <= len
					and string.match(string.sub(code, i + 1, i + 1), "%d")
				then
					hasDot = true
					i += 1
				elseif c == "e" or c == "E" then
					i += 1
					if i <= len and (string.sub(code, i, i) == "+" or string.sub(code, i, i) == "-") then
						i += 1
					end
				else
					break
				end
			end
			table.insert(tokens, { type = "number", text = string.sub(code, start, i - 1) })
			continue
		end

		-- Identifiers, keywords, builtins
		if string.match(char, "[%a_]") then
			local start = i
			while i <= len and string.match(string.sub(code, i, i), "[%w_]") do
				i += 1
			end
			local word = string.sub(code, start, i - 1)
			local tokenType = "identifier"
			if isKeyword(word) then
				tokenType = "keyword"
			elseif isBuiltin(word) then
				tokenType = "builtin"
			elseif isType(word) then
				tokenType = "type"
			elseif string.match(code, "^%s*[%(\"'{]", i) then
				tokenType = "call" -- print(...), foo "x", bar { }
			end
			table.insert(tokens, { type = tokenType, text = word })
			continue
		end

		-- Operators and punctuation
		local twoChar = string.sub(code, i, i + 1)
		if
			twoChar == "=="
			or twoChar == "~="
			or twoChar == "<="
			or twoChar == ">="
			or twoChar == ".."
			or twoChar == "::"
		then
			table.insert(tokens, { type = "operator", text = twoChar })
			i += 2
			continue
		end

		local singleChar = char
		if string.match(singleChar, "[%+%-%%%*%/%^%=%<%>%{%}%[%]%(%)%,%;%:%.]") then
			table.insert(tokens, { type = "punctuation", text = singleChar })
			i += 1
			continue
		end

		-- Unknown character, just advance
		table.insert(tokens, { type = "identifier", text = char })
		i += 1
	end

	return tokens
end

--[=[
	The code as RichText with its tokens coloured for the palette's theme
	(a light chat when its text is dark).
]=]
function SyntaxHighlight.highlight(code: string, palette: { [string]: Color3 }?): string
	local parts = {}
	for _, span in ipairs(SyntaxHighlight.spans(code, palette)) do
		if span.color then
			table.insert(parts, string.format('<font color="%s">%s</font>', span.color, escape(span.text)))
		else
			table.insert(parts, escape(span.text))
		end
	end
	return table.concat(parts)
end

--[=[
	The code as pieces of text with their colour ("#RRGGBB", or nil for
	plain), for building RichText runs (Util/MarkdownSource).
]=]
function SyntaxHighlight.spans(code: string, palette: { [string]: Color3 }?): { { text: string, color: string? } }
	local text = palette and palette.messageText
	local light = text ~= nil and (text.R + text.G + text.B) / 3 < 0.5
	local colors = if light then COLORS.light else COLORS.dark
	local spans = {}
	for _, token in ipairs(tokenize(code)) do
		table.insert(spans, { text = token.text, color = colors[token.type] })
	end
	return spans
end

--[=[
	Whether a ``` language name is one this highlights (lua, luau).
]=]
function SyntaxHighlight.isSupported(lang: string?): boolean
	local name = string.lower(lang or "")
	return name == "lua" or name == "luau"
end

return SyntaxHighlight
