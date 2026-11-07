--!strict
--[[
	Foundation

	Roblox's Foundation looks for controls, on top of the palette's `tint`
	(a see-through blue-grey that works on any surface): input fields, the
	1px outline, and buttons in Foundation's variants with their hover and
	press states.

	  emphasis     Roblox blue, for the main action
	  standard     a tint of the text colour, for everything else
	  subEmphasis  filled with the text colour (a selected chip or tab)
	  alert        standard, with red text (Delete, Ban)

	Call the same function again with a new palette to re-theme.

	Usage:
		Foundation.button(saveButton, palette, "emphasis")
		Foundation.input(searchBox, palette)
		Foundation.stroke(card, palette, "muted")
]]

local Theme = require(script.Parent.Parent.Config.Theme)

type Palette = { [string]: Color3 }

local Foundation = {}

-- Background transparency of the tint, by state, for standard surfaces
local STANDARD = { rest = 0.88, hover = 0.81, press = 0.77 }
local INPUT = 0.92 -- an input field's tint
-- How far a filled button moves toward the tint on hover and press
local FILLED_SHIFT = { rest = 0, hover = 0.1, press = 0.18 }

Foundation.STANDARD = STANDARD

--[=[
	The 1px outline Roblox draws round inputs and cards (named
	"FoundationStroke"). level: "muted" | "default" | "emphasis".
]=]
function Foundation.stroke(gui: GuiObject, palette: Palette, level: string?): UIStroke
	local stroke = gui:FindFirstChild("FoundationStroke") :: UIStroke?
	if not stroke then
		local made = Instance.new("UIStroke")
		made.Name = "FoundationStroke"
		made.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		made.Thickness = 1
		made.Parent = gui
		stroke = made
	end
	local result = stroke :: UIStroke
	result.Color = palette.tint
	result.Transparency = Theme.STROKE[level or "default"]
	return result
end

--[=[
	An input field (TextBox, or a dropdown button): a light tint with the
	default outline.
]=]
function Foundation.input(gui: GuiObject, palette: Palette)
	gui.BackgroundColor3 = palette.tint
	gui.BackgroundTransparency = INPUT
	Foundation.stroke(gui, palette)
end

-- Each button's variant and palette, for its hover and press states
local buttons: { [GuiButton]: { variant: string, palette: Palette, state: string } } = setmetatable(
	{},
	{ __mode = "k" }
) :: any

local function paint(button: GuiButton)
	local info = buttons[button]
	if not info then
		return
	end
	local palette, state = info.palette, info.state
	local textColor: Color3
	if info.variant == "emphasis" or info.variant == "subEmphasis" then
		local fill = if info.variant == "emphasis" then palette.sendButton else palette.messageText
		button.BackgroundColor3 = fill:Lerp(palette.tint, FILLED_SHIFT[state])
		button.BackgroundTransparency = 0
		textColor = if info.variant == "emphasis" then palette.sendButtonText else palette.inputFrame
	else
		button.BackgroundColor3 = palette.tint
		button.BackgroundTransparency = STANDARD[state]
		textColor = if info.variant == "alert" then palette.danger else palette.messageText
	end
	if button:IsA("TextButton") then
		button.TextColor3 = textColor
	end
	button:SetAttribute("Variant", info.variant)
end

--[=[
	Styles a button as a Foundation variant (see the top of this file) and
	gives it hover and press states. Calling it again changes the variant
	or the palette.
]=]
function Foundation.button(button: GuiButton, palette: Palette, variant: string)
	local info = buttons[button]
	if info then
		info.variant = variant
		info.palette = palette
	else
		info = { variant = variant, palette = palette, state = "rest" }
		buttons[button] = info
		button.AutoButtonColor = false
		local function setState(state: string)
			local current = buttons[button]
			if current then
				current.state = state
				paint(button)
			end
		end
		button.MouseEnter:Connect(function()
			setState("hover")
		end)
		button.MouseLeave:Connect(function()
			setState("rest")
		end)
		button.MouseButton1Down:Connect(function()
			setState("press")
		end)
		button.MouseButton1Up:Connect(function()
			setState("hover")
		end)
	end
	paint(button)
end

return Foundation
