--[[
	Messages/PollMessage

	A poll card: header, question, one bar per answer with its share of the
	votes, and a summary. updateVotes() refreshes the bars when votes change.
]]

local RichText = require(script.Parent.Parent.Parent.Util.RichText)
local Shared = require(script.Parent.Shared)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local FONT = Theme.FONT
local FONTS = Theme.FONTS

local PollMessage = {}

--!
-- Creates a poll container (Frame) with question, options, and vote bars.
--!
function PollMessage.create(sender, timestamp, pollData, themeColors, replyRef)
	local card = Instance.new("Frame")
	card.Name = "Poll_" .. tostring(timestamp)
	card.Size = UDim2.new(1, -4, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = timestamp
	card.BackgroundColor3 = themeColors.inputFrame
	card.BorderSizePixel = 0

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 9)
	cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = themeColors.divider
	cardStroke.Transparency = 0.35
	cardStroke.Parent = card
	local cardPadding = Instance.new("UIPadding")
	cardPadding.PaddingTop = UDim.new(0, 10)
	cardPadding.PaddingBottom = UDim.new(0, 10)
	cardPadding.PaddingLeft = UDim.new(0, 10)
	cardPadding.PaddingRight = UDim.new(0, 10)
	cardPadding.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 7)
	layout.Parent = card

	local layoutOrder = 1

	-- Reply reference (if present)
	if replyRef and replyRef.sender then
		local replyRow = Shared.createReplyReference(replyRef, themeColors)
		replyRow.LayoutOrder = layoutOrder
		replyRow.Parent = card
		layoutOrder = layoutOrder + 1
	end

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 17)
	header.BackgroundTransparency = 1
	header.Font = FONT
	header.TextSize = 12
	header.TextColor3 = themeColors.timestamp
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.RichText = true
	header.Text = RichText.buildPollHeader(sender, timestamp, themeColors)
	header.LayoutOrder = layoutOrder
	header.Parent = card

	layoutOrder = layoutOrder + 1

	local question = Instance.new("TextLabel")
	question.Name = "Question"
	question.Size = UDim2.new(1, 0, 0, 0)
	question.AutomaticSize = Enum.AutomaticSize.Y
	question.BackgroundTransparency = 1
	question.FontFace = FONTS.heading
	question.TextSize = 15
	question.TextColor3 = themeColors.messageText
	question.TextXAlignment = Enum.TextXAlignment.Left
	question.TextYAlignment = Enum.TextYAlignment.Top
	question.TextWrapped = true
	question.Text = pollData.question or "" -- plain text label: no escaping needed
	question.LayoutOrder = layoutOrder
	question.Parent = card

	layoutOrder = layoutOrder + 1

	local summary = Instance.new("TextLabel")
	summary.Name = "VoteSummary"
	summary.Size = UDim2.new(1, 0, 0, 16)
	summary.BackgroundTransparency = 1
	summary.Font = FONT
	summary.TextSize = 12
	summary.TextColor3 = themeColors.timestamp
	summary.TextXAlignment = Enum.TextXAlignment.Left
	summary.Text = "0 votes  ·  Select an option"
	summary.LayoutOrder = layoutOrder
	summary.Parent = card

	layoutOrder = layoutOrder + 1

	for i, option in ipairs(pollData.options) do
		local row = Instance.new("TextButton")
		row.Name = "Option_" .. i
		row.Size = UDim2.new(1, 0, 0, 38)
		row.BackgroundColor3 = themeColors.pollBar
		row.Text = ""
		row.AutoButtonColor = true
		row.LayoutOrder = layoutOrder
		row.BorderSizePixel = 0
		row.ClipsDescendants = true
		row.Parent = card
		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 7)
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
		barCorner.CornerRadius = UDim.new(0, 7)
		barCorner.Parent = bar

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, -94, 1, 0)
		label.Position = UDim2.new(0, 11, 0, 0)
		label.BackgroundTransparency = 1
		label.Text = option
		label.TextColor3 = themeColors.pollBarText
		label.Font = Enum.Font.BuilderSansMedium
		label.TextSize = 14
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.ZIndex = 2
		label.Parent = row

		local result = Instance.new("TextLabel")
		result.Name = "VoteCount"
		result.Size = UDim2.new(0, 78, 1, 0)
		result.Position = UDim2.new(1, -88, 0, 0)
		result.BackgroundTransparency = 1
		result.Text = "0%  ·  0"
		result.TextColor3 = themeColors.pollBarText
		result.FontFace = FONTS.mono
		result.TextSize = 12
		result.TextXAlignment = Enum.TextXAlignment.Right
		result.ZIndex = 2
		result.Parent = row

		layoutOrder = layoutOrder + 1
	end
	return card
end

function PollMessage.updateVotes(container, pollData, _themeColors)
	local totalVotes = 0
	for _, voters in ipairs(pollData.votes or {}) do
		totalVotes += #voters
	end
	local summary = container:FindFirstChild("VoteSummary")
	if summary then
		summary.Text = tostring(totalVotes)
			.. (totalVotes == 1 and " vote" or " votes")
			.. (totalVotes == 0 and "  ·  Select an option" or "  ·  Click an option to change your vote")
	end
	for i = 1, #pollData.options do
		local row = container:FindFirstChild("Option_" .. i)
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
