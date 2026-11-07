--!
-- NewMessageDialog
-- The "New message" modal: search your Roblox friends or type any username
-- to start a direct message. People see DMs when they open this place with
-- Team Chat, since messages are shared through the place.
--!

local Theme = require(script.Parent.Parent.Parent.Config.Theme)
local BadgeIcons = require(script.Parent.Parent.Components.BadgeIcons)
local Foundation = require(script.Parent.Parent.Common.Foundation)
local Language = require(script.Parent.Parent.Parent.Core.Language)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)

local FONTS = Theme.FONTS
local MAX_SHOWN = 60 -- friends listed at once (search narrows it down)

local NewMessageDialog = {}

local function trim(text: string): string
	return (string.gsub(text, "^%s*@?(.-)%s*$", "%1"))
end

--!
-- kit: a ModalKit. opts: {
--   getThemeColors: () -> palette,
--   getHandlers: () -> { getFriends, resolveUser, onPick }?,
--     getFriends(callback({ {userId, username, displayName} }))
--     resolveUser(username, callback(userId?, exactName?))
--     onPick(userId, username)
--     isVerified(userId) -> boolean   -- optional: shows the verified badge
-- }
-- Returns { open, close, isVisible, recolor }
--!
function NewMessageDialog.create(kit, opts)
	local modal =
		kit.createModal({ name = "NewMessageDialog", title = "New message", iconKey = "newMessage", zIndex = 20 })
	Language.bind(modal.title, "Text", "newMessage.title")
	local card = modal.card
	local z = modal.contentZIndex
	local colors = opts.getThemeColors()

	local friends: { table } = {}
	local friendsLoaded = false
	local lookupToken = 0

	local function corner(gui: GuiObject, radius: number)
		local c = Instance.new("UICorner")
		c.CornerRadius = if radius < 0 then UDim.new(1, 0) else UDim.new(0, radius)
		c.Parent = gui
	end

	local function label(name: string, parent: Instance, props): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.BorderSizePixel = 0
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextTruncate = Enum.TextTruncate.AtEnd
		l.ZIndex = z
		for key, value in pairs(props) do
			(l :: any)[key] = value
		end
		l.Parent = parent
		return l
	end

	local search = Instance.new("TextBox")
	search.Name = "Search"
	search.Size = UDim2.new(1, 0, 0, 38)
	Foundation.input(search, colors)
	search.TextColor3 = colors.dialogInputText
	Language.bind(search, "PlaceholderText", "newMessage.search")
	search.PlaceholderColor3 = colors.placeholder
	search.FontFace = FONTS.body
	search.TextSize = 14
	search.Text = ""
	search.ClearTextOnFocus = false
	search.TextXAlignment = Enum.TextXAlignment.Left
	search.BorderSizePixel = 0
	search.LayoutOrder = 2
	search.ZIndex = z
	search.Parent = card
	corner(search, 8)
	local searchPadding = Instance.new("UIPadding")
	searchPadding.PaddingLeft = UDim.new(0, 10)
	searchPadding.PaddingRight = UDim.new(0, 10)
	searchPadding.Parent = search

	local note = label("Note", card, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = colors.timestamp,
		FontFace = FONTS.body,
		TextSize = 12,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		LayoutOrder = 3,
	})
	Language.bind(note, "Text", "newMessage.note")

	local list = Instance.new("Frame")
	list.Name = "People"
	list.Size = UDim2.new(1, 0, 0, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.BackgroundTransparency = 1
	list.LayoutOrder = 4
	list.ZIndex = z
	list.Parent = card
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 2)
	listLayout.Parent = list

	local rowColors = {} -- rows to recolor: { row, name, sub, circle? }
	local rowActions: { [TextButton]: () -> () } = {} -- what clicking (or Enter) does
	local friendRowCount = 0

	local function personRow(
		order: number,
		title: string,
		subtitle: string,
		userId: number?,
		iconKey: string?
	): TextButton
		local row = Instance.new("TextButton")
		row.Name = "Person"
		row.Text = ""
		row.AutoButtonColor = false
		row.Size = UDim2.new(1, 0, 0, 44)
		row.BackgroundColor3 = colors.menuItemHover
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.LayoutOrder = order
		row.ZIndex = z
		row.Parent = list
		corner(row, 8)

		local avatar
		if userId then
			avatar = Instance.new("ImageLabel")
			avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150"
			avatar.BackgroundColor3 = colors.menuItemHover
		else
			avatar = Instance.new("TextLabel")
			avatar.BackgroundColor3 = colors.sendButton
			avatar.TextColor3 = colors.sendButtonText
			avatar.TextSize = 18
			Icons.apply(avatar, iconKey or "newMessage")
		end
		avatar.Name = "Avatar"
		avatar.AnchorPoint = Vector2.new(0, 0.5)
		avatar.Position = UDim2.new(0, 6, 0.5, 0)
		avatar.Size = UDim2.fromOffset(32, 32)
		avatar.BorderSizePixel = 0
		avatar.ZIndex = z
		avatar.Parent = row
		corner(avatar, -1)

		local handlers = opts.getHandlers()
		local verified = userId ~= nil
			and handlers ~= nil
			and handlers.isVerified ~= nil
			and handlers.isVerified(userId)
		local name = label("NameLabel", row, {
			Position = UDim2.fromOffset(48, 5),
			Size = UDim2.new(1, -54, 0, 18),
			RichText = true,
			Text = Icons.escape(title) .. BadgeIcons.verifiedSuffix(verified, 13),
			TextColor3 = colors.messageText,
			FontFace = FONTS.semibold,
			TextSize = 14,
		})
		local sub = label("Sub", row, {
			Position = UDim2.fromOffset(48, 23),
			Size = UDim2.new(1, -54, 0, 15),
			Text = subtitle,
			TextColor3 = colors.timestamp,
			FontFace = FONTS.body,
			TextSize = 12,
		})

		row.MouseEnter:Connect(function()
			row.BackgroundTransparency = 0
		end)
		row.MouseLeave:Connect(function()
			row.BackgroundTransparency = 1
		end)
		table.insert(rowColors, { row = row, name = name, sub = sub, avatar = avatar, isIcon = userId == nil })
		return row
	end

	local function pick(userId: number, username: string)
		local handlers = opts.getHandlers()
		modal.close()
		if handlers then
			handlers.onPick(userId, username)
		end
	end

	local function clearRows()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		table.clear(rowColors)
		table.clear(rowActions)
		friendRowCount = 0
	end

	local function onClick(row: TextButton, action: () -> ())
		rowActions[row] = action
		row.MouseButton1Click:Connect(action)
	end

	local heading -- section heading above the friends ("FRIENDS — 12")

	local function render()
		clearRows()
		local query = trim(search.Text)
		local lowered = string.lower(query)
		local order = 0

		-- Anyone by username
		if string.match(query, "^[%w_]+$") and #query >= 3 and #query <= 20 then
			order += 1
			local row = personRow(
				order,
				Language.t("newMessage.messageUser", { name = query }),
				Language.t("newMessage.lookUp"),
				nil,
				"newMessage"
			)
			onClick(row, function()
				lookupToken += 1
				local token = lookupToken
				row.Sub.Text = Language.t("newMessage.lookingUp")
				local handlers = opts.getHandlers()
				if not handlers then
					return
				end
				handlers.resolveUser(query, function(userId, exactName)
					if token ~= lookupToken or not row.Parent then
						return
					end
					if userId then
						pick(userId, exactName or query)
					else
						row.Sub.Text = Language.t("newMessage.notFound", { name = query })
					end
				end)
			end)
		end

		order += 1
		heading = label("FriendsHeading", list, {
			Size = UDim2.new(1, 0, 0, 24),
			TextColor3 = colors.timestamp,
			FontFace = FONTS.bold,
			TextSize = 12,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			LayoutOrder = order,
		})

		if not friendsLoaded then
			heading.Text = Language.t("newMessage.friendsHeading")
			order += 1
			label("Status", list, {
				Size = UDim2.new(1, 0, 0, 30),
				Text = Language.t("newMessage.loading"),
				TextColor3 = colors.timestamp,
				FontFace = FONTS.body,
				TextSize = 13,
				LayoutOrder = order,
			})
			return
		end

		local matches = {}
		for _, friend in ipairs(friends) do
			if
				lowered == ""
				or string.find(string.lower(friend.username), lowered, 1, true)
				or string.find(string.lower(friend.displayName or ""), lowered, 1, true)
			then
				table.insert(matches, friend)
			end
		end
		heading.Text = Language.t("newMessage.friendsHeading") .. " \u{2014} " .. tostring(#matches)

		if #matches == 0 then
			order += 1
			label("Status", list, {
				Size = UDim2.new(1, 0, 0, 30),
				Text = if #friends == 0
					then Language.t("newMessage.noFriends")
					else Language.t("newMessage.noMatch", { query = query }),
				TextColor3 = colors.timestamp,
				FontFace = FONTS.body,
				TextSize = 13,
				LayoutOrder = order,
			})
			return
		end

		for index, friend in ipairs(matches) do
			if index > MAX_SHOWN then
				order += 1
				label("More", list, {
					Size = UDim2.new(1, 0, 0, 24),
					Text = Language.t("newMessage.more", { count = #matches - MAX_SHOWN }),
					TextColor3 = colors.timestamp,
					FontFace = FONTS.body,
					TextSize = 12,
					LayoutOrder = order,
				})
				break
			end
			order += 1
			local display = friend.displayName or friend.username
			local row = personRow(order, display, "@" .. friend.username, friend.userId)
			friendRowCount += 1
			onClick(row, function()
				pick(friend.userId, friend.username)
			end)
		end
	end

	search:GetPropertyChangedSignal("Text"):Connect(render)
	-- Enter in the search box: the only matching friend, otherwise the first
	-- row (the "Message @username" lookup when a username was typed)
	search.FocusLost:Connect(function(enterPressed)
		if not enterPressed then
			return
		end
		local rows = {}
		for row in pairs(rowActions) do
			table.insert(rows, row)
		end
		table.sort(rows, function(x, y)
			return x.LayoutOrder < y.LayoutOrder
		end)
		local target = rows[1]
		if friendRowCount == 1 then
			for _, row in ipairs(rows) do
				if row.Avatar:IsA("ImageLabel") then
					target = row
				end
			end
		end
		if target then
			rowActions[target]()
		end
	end)

	local dialog = {}

	-- `query`: start with this in the search box (searching from the sidebar)
	function dialog.open(query: string?)
		search.Text = query or ""
		render()
		modal.open()
		local handlers = opts.getHandlers()
		if handlers and not friendsLoaded then
			handlers.getFriends(function(loaded)
				friends = loaded
				friendsLoaded = true
				if modal.isVisible() then
					render()
				end
			end)
		end
		pcall(function()
			search:CaptureFocus()
		end)
	end

	dialog.close = modal.close
	dialog.isVisible = modal.isVisible

	function dialog.recolor()
		colors = opts.getThemeColors()
		Foundation.input(search, colors)
		search.TextColor3 = colors.dialogInputText
		search.PlaceholderColor3 = colors.placeholder
		note.TextColor3 = colors.timestamp
		if modal.isVisible() then
			render()
		end
	end

	return dialog
end

return NewMessageDialog
