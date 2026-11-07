--[[
	Messages/PollMessage

	A poll, Discord style: the author header (avatar, name, time) and under
	it a card with the question, how many voted, and one bar per answer with
	its share of the votes. updateVotes() refreshes the bars when votes change.

	The row is a normal message row (so it groups and highlights like one);
	the card inside it is named "PollCard" and holds Question, VoteSummary
	and Option_<i>.
]]

local Author = require(script.Parent.Author)
local Shared = require(script.Parent.Shared)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONT = Theme.FONT
local FONTS = Theme.FONTS

local CARD_MAX_WIDTH = 460

local PollMessage = {}

--[=[
	The card of a poll row (nil for other rows).
]=]
function PollMessage.cardOf(container: Instance): Frame?
	return container:FindFirstChild("PollCard") :: Frame?
end

--!
-- Creates a poll row: author header and the poll card.
--!
function PollMessage.create(sender, timestamp, pollData, themeColors, replyRef, senderId)
	local container = Instance.new("Frame")
	container.Name = "Poll_" .. tostring(timestamp)
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.LayoutOrder = timestamp
	container.BorderSizePixel = 0

	local containerLayout = Instance.new("UIListLayout")
	containerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	containerLayout.Padding = UDim.new(0, 2)
	containerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	containerLayout.Parent = container

	Shared.addMessageSurface(container, themeColors)
	if replyRef and replyRef.sender then
		local replyRow = Shared.createReplyReference(replyRef, themeColors, true)
		replyRow.LayoutOrder = -1
		replyRow.Parent = container
	end
	Author.attach(container, sender, senderId, timestamp, themeColors)

	local card = Instance.new("Frame")
	card.Name = "PollCard"
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = themeColors.inputFrame
	card.BorderSizePixel = 0
	card.LayoutOrder = 1
	card.Parent = container
	local width = Instance.new("UISizeConstraint")
	width.MaxSize = Vector2.new(CARD_MAX_WIDTH, math.huge)
	width.Parent = card

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 8)
	cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = themeColors.divider
	cardStroke.Transparency = 0.35
	cardStroke.Parent = card
	local cardPadding = Instance.new("UIPadding")
	cardPadding.PaddingTop = UDim.new(0, 12)
	cardPadding.PaddingBottom = UDim.new(0, 12)
	cardPadding.PaddingLeft = UDim.new(0, 12)
	cardPadding.PaddingRight = UDim.new(0, 12)
	cardPadding.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = card

	local question = Instance.new("TextLabel")
	question.Name = "Question"
	question.Size = UDim2.new(1, 0, 0, 0)
	question.AutomaticSize = Enum.AutomaticSize.Y
	question.BackgroundTransparency = 1
	question.FontFace = FONTS.heading
	question.TextSize = 16
	question.TextColor3 = themeColors.messageText
	question.TextXAlignment = Enum.TextXAlignment.Left
	question.TextYAlignment = Enum.TextYAlignment.Top
	question.TextWrapped = true
	question.Text = pollData.question or "" -- plain text label: no escaping needed
	question.LayoutOrder = 1
	question.Parent = card

	local summary = Instance.new("TextLabel")
	summary.Name = "VoteSummary"
	summary.Size = UDim2.new(1, 0, 0, 16)
	summary.BackgroundTransparency = 1
	summary.Font = FONT
	summary.TextSize = 12
	summary.TextColor3 = themeColors.timestamp
	summary.TextXAlignment = Enum.TextXAlignment.Left
	summary.Text = "0 votes  ·  Select an option"
	summary.LayoutOrder = 2
	summary.Parent = card

	for i, option in ipairs(pollData.options) do
		local row = Instance.new("TextButton")
		row.Name = "Option_" .. i
		row.Size = UDim2.new(1, 0, 0, 40)
		row.BackgroundColor3 = themeColors.pollBar
		row.Text = ""
		row.AutoButtonColor = true
		row.LayoutOrder = 2 + i
		row.BorderSizePixel = 0
		row.ClipsDescendants = true
		row.Parent = card
		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 8)
		rowCorner.Parent = row

		local bar = Instance.new("Frame")
		bar.Name = "VoteBar"
		bar.Size = UDim2.new(0, 0, 1, 0)
		bar.BackgroundColor3 = themeColors.pollBarVoted
		bar.BackgroundTransparency = 0.58
		bar.BorderSizePixel = 0
		bar.ZIndex = 1
		bar.Parent = row
		local barCorner = Instance.new("UICorner")
		barCorner.CornerRadius = UDim.new(0, 8)
		barCorner.Parent = bar

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, -94, 1, 0)
		label.Position = UDim2.new(0, 12, 0, 0)
		label.BackgroundTransparency = 1
		label.Text = option
		label.TextColor3 = themeColors.pollBarText
		label.FontFace = FONTS.semibold
		label.TextSize = 14
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.ZIndex = 2
		label.Parent = row

		local result = Instance.new("TextLabel")
		result.Name = "VoteCount"
		result.Size = UDim2.new(0, 78, 1, 0)
		result.Position = UDim2.new(1, -90, 0, 0)
		result.BackgroundTransparency = 1
		result.Text = "0%  ·  0"
		result.TextColor3 = themeColors.pollBarText
		result.FontFace = FONTS.semibold
		result.TextSize = 12
		result.TextXAlignment = Enum.TextXAlignment.Right
		result.ZIndex = 2
		result.Parent = row
	end
	return container
end

function PollMessage.updateVotes(container, pollData, _themeColors)
	local card = PollMessage.cardOf(container) or container
	local totalVotes = 0
	for _, voters in ipairs(pollData.votes or {}) do
		totalVotes += #voters
	end
	local summary = card:FindFirstChild("VoteSummary")
	if summary then
		summary.Text = tostring(totalVotes)
			.. (totalVotes == 1 and " vote" or " votes")
			.. (totalVotes == 0 and "  ·  Select an option" or "  ·  Click an option to change your vote")
	end
	for i = 1, #pollData.options do
		local row = card:FindFirstChild("Option_" .. i)
		if row then
			local bar = row:FindFirstChild("VoteBar")
			local result = row:FindFirstChild("VoteCount")
			local count = pollData.votes and pollData.votes[i] and #pollData.votes[i] or 0
			local pct = totalVotes > 0 and count / totalVotes or 0
			if bar then
				bar.Size = UDim2.new(pct, 0, 1, 0)
			end
			if result then
				result.Text = string.format("%d%%  ·  %d", math.floor(pct * 100 + 0.5), count)
			end
		end
	end
end

return PollMessage
