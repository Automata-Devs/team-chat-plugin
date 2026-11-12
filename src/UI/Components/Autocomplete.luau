--[[
	Autocomplete

	The command / emoji / member suggestion menu above the message box: a small
	title (COMMANDS, EMOJI or MEMBERS), the suggestion rows and a hint, styled like the chat's
	other menus. ChatUI fills it (updateAutocomplete) and shows the highlighted
	row with setSelected. While a command's arguments are typed, the same menu
	lists them (createArgItem), with the one being typed highlighted.
]]

local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Language = require(script.Parent.Parent.Parent.Core.Language)

local FONTS = Theme.FONTS

local Autocomplete = {}

local ITEM_HEIGHT = 32
local MAX_ITEMS = 8
local ICON_SIZE = 22
local Z = 15 -- the menu; rows Z + 1, their content Z + 2

local function textLabel(props): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = Z + 2
	for key, value in pairs(props) do
		label[key] = value
	end
	return label
end

local function roundCorners(gui: GuiObject, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = gui
end

--[=[
	Creates the (hidden) menu inside container.
]=]
function Autocomplete.create(themeColors, container)
	local frame = Instance.new("Frame")
	frame.Name = "Autocomplete"
	frame.Size = UDim2.new(1, -10, 0, 0)
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.new(0, 5, 1, -(Theme.INPUT_HEIGHT + 8))
	frame.BackgroundColor3 = themeColors.menuBack
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = Z
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Parent = container
	roundCorners(frame, UDim.new(0, 8))

	local stroke = Instance.new("UIStroke")
	stroke.Name = "AutoStroke"
	stroke.Color = themeColors.menuBorder
	stroke.Thickness = 1
	stroke.Parent = frame

	local shadow = Instance.new("UIShadow")
	shadow.BlurRadius = UDim.new(0, 12)
	shadow.Color = Color3.fromRGB(0, 0, 0)
	shadow.Transparency = 0.5
	shadow.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.Parent = frame

	local title = textLabel({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 20),
		Text = "",
		FontFace = FONTS.bold,
		TextSize = 11,
		TextColor3 = themeColors.timestamp,
		LayoutOrder = 0,
		Parent = frame,
	})
	local titlePadding = Instance.new("UIPadding")
	titlePadding.PaddingLeft = UDim.new(0, 6)
	titlePadding.Parent = title

	-- Studio sends plugins no key events: rows are picked by Tab or a click
	local hint = textLabel({
		Name = "Hint",
		RichText = true,
		Size = UDim2.new(1, 0, 0, 20),
		Text = Language.t("autocomplete.hint"),
		FontFace = FONTS.body,
		TextSize = 11,
		TextColor3 = themeColors.timestamp,
		LayoutOrder = MAX_ITEMS + 1,
		Parent = frame,
	})
	local hintPadding = Instance.new("UIPadding")
	hintPadding.PaddingLeft = UDim.new(0, 6)
	hintPadding.Parent = hint

	return frame
end

--[=[
	The usual hint under the rows, in the current language.
]=]
function Autocomplete.defaultHint(): string
	return Language.t("autocomplete.hint")
end

--[=[
	Sets the line under the rows (rich text; defaultHint() normally).
]=]
function Autocomplete.setHint(frame, text: string)
	local hint = frame:FindFirstChild("Hint")
	if hint then
		hint.Text = text
	end
end

--[=[
	Sets the small title above the rows ("Commands" / "Emoji").
]=]
function Autocomplete.setTitle(frame, text: string)
	local title = frame:FindFirstChild("Title")
	if title then
		title.Text = string.upper(text)
	end
end

-- A row: rounded button whose content is laid out left to right
local function createRow(index: number, themeColors): TextButton
	local item = Instance.new("TextButton")
	item.Name = "Item_" .. index
	item.Size = UDim2.new(1, 0, 0, ITEM_HEIGHT)
	item.BackgroundColor3 = themeColors.menuItemHover
	item.BackgroundTransparency = 1 -- setSelected shows the highlighted row
	item.Text = ""
	item.AutoButtonColor = false
	item.BorderSizePixel = 0
	item.ZIndex = Z + 1
	item.LayoutOrder = index
	roundCorners(item, UDim.new(0, 6))

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = item

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = item
	return item
end

--[=[
	Creates a command row: code icon, "/name", muted description and, for
	commands that need a rank, a small rank pill on the right.
	cmd: { name, description, rank, aliases }
]=]
function Autocomplete.createItem(index, cmd, themeColors, getRankName)
	local item = createRow(index, themeColors)

	local iconTile = Instance.new("Frame")
	iconTile.Name = "IconTile"
	iconTile.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	iconTile.BackgroundColor3 = themeColors.sendButton
	iconTile.BackgroundTransparency = 0.85
	iconTile.BorderSizePixel = 0
	iconTile.LayoutOrder = 1
	iconTile.ZIndex = Z + 2
	iconTile.Parent = item
	roundCorners(iconTile, UDim.new(0, 6))

	local icon = textLabel({
		Name = "Icon",
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = iconTile,
	})
	Icons.apply(icon, "command")
	icon.TextSize = 14
	icon.TextColor3 = themeColors.sendButton

	textLabel({
		Name = "CmdName",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "/" .. cmd.name,
		FontFace = FONTS.mono,
		TextSize = 13,
		TextColor3 = themeColors.sendButton,
		LayoutOrder = 2,
		Parent = item,
	})

	local desc = textLabel({
		Name = "CmdDesc",
		Size = UDim2.fromScale(0, 1),
		Text = cmd.description or "",
		FontFace = FONTS.body,
		TextSize = 12,
		TextColor3 = themeColors.timestamp,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 3,
		Parent = item,
	})
	local fill = Instance.new("UIFlexItem")
	fill.FlexMode = Enum.UIFlexMode.Fill -- takes the space left between the name and the rank
	fill.Parent = desc

	if cmd.rank and cmd.rank > 0 then
		local rank = textLabel({
			Name = "CmdRank",
			Size = UDim2.fromOffset(0, 18),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = getRankName(cmd.rank),
			FontFace = FONTS.bold,
			TextSize = 10,
			TextColor3 = themeColors.timestamp,
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundTransparency = 0.85,
			BackgroundColor3 = themeColors.timestamp,
			LayoutOrder = 4,
			Parent = item,
		})
		roundCorners(rank, UDim.new(1, 0))
		local rankPadding = Instance.new("UIPadding")
		rankPadding.PaddingLeft = UDim.new(0, 7)
		rankPadding.PaddingRight = UDim.new(0, 7)
		rankPadding.Parent = rank
	end

	return item
end

--[=[
	Creates an argument row for the command being typed: its name, an
	"optional" pill when it can be left out, and its description on the right.
	arg: { name, description, optional }
]=]
function Autocomplete.createArgItem(index, arg, themeColors)
	local item = createRow(index, themeColors)
	item.AutoButtonColor = false

	textLabel({
		Name = "CmdName",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = arg.name,
		FontFace = FONTS.mono,
		TextSize = 13,
		TextColor3 = themeColors.sendButton,
		LayoutOrder = 1,
		Parent = item,
	})

	if arg.optional then
		local pill = textLabel({
			Name = "CmdRank", -- recolored like the rank pill
			Size = UDim2.fromOffset(0, 18),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = "optional",
			FontFace = FONTS.bold,
			TextSize = 10,
			TextColor3 = themeColors.timestamp,
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundTransparency = 0.85,
			BackgroundColor3 = themeColors.timestamp,
			LayoutOrder = 2,
			Parent = item,
		})
		roundCorners(pill, UDim.new(1, 0))
		local pillPadding = Instance.new("UIPadding")
		pillPadding.PaddingLeft = UDim.new(0, 7)
		pillPadding.PaddingRight = UDim.new(0, 7)
		pillPadding.Parent = pill
	end

	local desc = textLabel({
		Name = "CmdDesc",
		Size = UDim2.fromScale(0, 1),
		Text = arg.description or "",
		FontFace = FONTS.body,
		TextSize = 12,
		TextColor3 = themeColors.timestamp,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 3,
		Parent = item,
	})
	local fill = Instance.new("UIFlexItem")
	fill.FlexMode = Enum.UIFlexMode.Fill
	fill.Parent = desc

	return item
end

--[=[
	Creates an emoji row: the emoji and its ":name:".
	entry: { name, emoji }
]=]
function Autocomplete.createEmojiItem(index, entry, themeColors)
	local item = createRow(index, themeColors)

	textLabel({
		Name = "EmojiChar",
		Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
		Text = entry.emoji,
		Font = Theme.FONT,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		Parent = item,
	})

	local name = textLabel({
		Name = "CmdName",
		Size = UDim2.fromScale(0, 1),
		Text = ":" .. entry.name .. ":",
		FontFace = FONTS.mono,
		TextSize = 13,
		TextColor3 = themeColors.messageText,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
		Parent = item,
	})
	local fill = Instance.new("UIFlexItem")
	fill.FlexMode = Enum.UIFlexMode.Fill
	fill.Parent = name

	return item
end

--[=[
	Creates a member row for @mentions: their avatar (with a green dot when
	they're here), display name, and @username on the right. The @everyone row
	has an "@" tile and says what it does.
	member: { userId, username, displayName, online } or { everyone = true }
]=]
function Autocomplete.createMemberItem(index, member, themeColors)
	local item = createRow(index, themeColors)

	if member.everyone then
		local tile = Instance.new("Frame")
		tile.Name = "IconTile"
		tile.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
		tile.BackgroundColor3 = themeColors.sendButton
		tile.BackgroundTransparency = 0.8
		tile.BorderSizePixel = 0
		tile.ZIndex = Z + 2
		tile.LayoutOrder = 1
		tile.Parent = item
		roundCorners(tile, UDim.new(1, 0))
		textLabel({
			Name = "Icon",
			Size = UDim2.fromScale(1, 1),
			Text = "@",
			FontFace = FONTS.bold,
			TextSize = 13,
			TextColor3 = themeColors.sendButton,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = tile,
		})
	else
		local avatar = Instance.new("ImageLabel")
		avatar.Name = "MemberAvatar"
		avatar.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
		avatar.BackgroundColor3 = themeColors.menuItemHover
		avatar.BorderSizePixel = 0
		avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(member.userId) .. "&w=48&h=48"
		avatar.ZIndex = Z + 2
		avatar.LayoutOrder = 1
		avatar.Parent = item
		roundCorners(avatar, UDim.new(1, 0))
		if member.online then
			local dot = Instance.new("Frame")
			dot.Name = "Status"
			dot.AnchorPoint = Vector2.new(1, 1)
			dot.Position = UDim2.new(1, 1, 1, 1)
			dot.Size = UDim2.fromOffset(8, 8)
			dot.BackgroundColor3 = themeColors.success
			dot.BorderSizePixel = 0
			dot.ZIndex = Z + 3
			dot.Parent = avatar
			roundCorners(dot, UDim.new(1, 0))
			local ring = Instance.new("UIStroke")
			ring.Name = "Ring"
			ring.Thickness = 2
			ring.Color = themeColors.menuBack
			ring.Parent = dot
		end
	end

	local name = textLabel({
		Name = "CmdName",
		Size = UDim2.fromScale(0, 1),
		Text = if member.everyone then "@everyone" else member.displayName or member.username,
		FontFace = FONTS.semibold,
		TextSize = 14,
		TextColor3 = themeColors.messageText,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
		Parent = item,
	})
	local fill = Instance.new("UIFlexItem")
	fill.FlexMode = Enum.UIFlexMode.Fill
	fill.Parent = name

	textLabel({
		Name = "CmdDesc",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = if member.everyone then Language.t("mention.everyoneHint") else "@" .. member.username,
		FontFace = FONTS.body,
		TextSize = 12,
		TextColor3 = themeColors.timestamp,
		TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = 3,
		Parent = item,
	})
	item:SetAttribute("Member", true)

	return item
end

--[=[
	Creates an object row for #tags: Studio's icon for its class, its name,
	and where it is on the right (e.g. "Workspace.Map").
]=]
function Autocomplete.createObjectItem(index, instance: Instance, themeColors)
	local item = createRow(index, themeColors)

	local icon = Instance.new("ImageLabel")
	icon.Name = "ClassIcon"
	icon.Size = UDim2.fromOffset(16, 16)
	icon.BackgroundTransparency = 1
	icon.ZIndex = Z + 2
	icon.LayoutOrder = 1
	icon.Parent = item
	local ok, classIcon = pcall(function()
		return game:GetService("StudioService"):GetClassIcon(instance.ClassName)
	end)
	if ok and type(classIcon) == "table" then
		icon.Image = classIcon.Image
		icon.ImageRectOffset = classIcon.ImageRectOffset
		icon.ImageRectSize = classIcon.ImageRectSize
	end

	local name = textLabel({
		Name = "CmdName",
		Size = UDim2.fromScale(0, 1),
		Text = instance.Name,
		FontFace = FONTS.semibold,
		TextSize = 14,
		TextColor3 = themeColors.messageText,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
		Parent = item,
	})
	local fill = Instance.new("UIFlexItem")
	fill.FlexMode = Enum.UIFlexMode.Fill
	fill.Parent = name

	textLabel({
		Name = "CmdDesc",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = if instance.Parent and instance.Parent ~= game then instance.Parent:GetFullName() else "",
		FontFace = FONTS.body,
		TextSize = 12,
		TextColor3 = themeColors.timestamp,
		TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = 3,
		Parent = item,
	})
	item:SetAttribute("Object", true)

	return item
end

--[=[
	Highlights row number index (the others are transparent).
]=]
function Autocomplete.setSelected(frame, index: number?)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("TextButton") and child.Name:match("^Item_%d+$") then
			child.BackgroundTransparency = if tonumber(child.Name:match("%d+")) == index then 0 else 1
		end
	end
end

--[=[
	Re-applies the current palette to the menu and its rows.
]=]
function Autocomplete.recolor(frame, themeColors)
	frame.BackgroundColor3 = themeColors.menuBack
	local stroke = frame:FindFirstChild("AutoStroke")
	if stroke then
		stroke.Color = themeColors.menuBorder
	end
	for _, name in ipairs({ "Title", "Hint" }) do
		local label = frame:FindFirstChild(name)
		if label then
			label.TextColor3 = themeColors.timestamp
		end
	end

	for _, item in ipairs(frame:GetChildren()) do
		if item:IsA("TextButton") and item.Name:match("^Item_%d+$") then
			item.BackgroundColor3 = themeColors.menuItemHover
			local plainName = item:FindFirstChild("EmojiChar") ~= nil
				or item:GetAttribute("Member") == true
				or item:GetAttribute("Object") == true
			local name = item:FindFirstChild("CmdName")
			if name then
				name.TextColor3 = if plainName then themeColors.messageText else themeColors.sendButton
			end
			local desc = item:FindFirstChild("CmdDesc")
			if desc then
				desc.TextColor3 = themeColors.timestamp
			end
			local rank = item:FindFirstChild("CmdRank")
			if rank then
				rank.TextColor3 = themeColors.timestamp
				rank.BackgroundColor3 = themeColors.timestamp
			end
			local tile = item:FindFirstChild("IconTile")
			if tile then
				tile.BackgroundColor3 = themeColors.sendButton
				tile.Icon.TextColor3 = themeColors.sendButton
			end
		end
	end
end

Autocomplete.ITEM_HEIGHT = ITEM_HEIGHT
Autocomplete.MAX_ITEMS = MAX_ITEMS

return Autocomplete
