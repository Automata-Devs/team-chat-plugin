--[[
	Messages/Recolor

	Re-themes an existing message (any kind) after the palette or the display
	settings changed.
]]

local Announcement = require(script.Parent.Announcement)
local Author = require(script.Parent.Author)
local AttachmentCards = require(script.Parent.Parent.Components.AttachmentCards)
local EmbedManager = require(script.Parent.Parent.Embeds.EmbedManager)
local MentionPills = require(script.Parent.Parent.MentionPills)
local MessageText = require(script.Parent.Parent.MessageText)
local RichText = require(script.Parent.Parent.Parent.Util.RichText)
local Shared = require(script.Parent.Shared)

local Recolor = {}

--!
-- Re-renders an existing message container with new theme colors.
--!
function Recolor.apply(container, themeColors)
	local reply = container:FindFirstChild("ReplyReference")
	if reply then
		Shared.renderReplyLabel(reply) -- names / verified badges may have come in
		Shared.recolorReply(reply, themeColors)
	end
	local sender = container:GetAttribute("Sender")
	local content = container:GetAttribute("Content")
	local timestamp = container:GetAttribute("Timestamp")
	if not sender or not timestamp then
		return
	end
	if content == nil then
		content = ""
	end

	if container:GetAttribute("HoverHighlight") then
		container.BackgroundColor3 = themeColors.menuItemHover
	end
	Shared.recolorOnlyYouNote(container, themeColors)
	if container:GetAttribute("HoverHighlight") then
		-- Re-checked every time: your display name may have loaded since
		Shared.applyMention(container, themeColors, content)
	end

	if container:GetAttribute("IsPoll") then
		container.BackgroundColor3 = themeColors.inputFrame
		local headerLabel = container:FindFirstChild("Header")
		if headerLabel and sender and timestamp then
			headerLabel.Text = RichText.buildPollHeader(sender, timestamp, themeColors)
		end
		local questionLabel = container:FindFirstChild("Question")
		if questionLabel then
			questionLabel.TextColor3 = themeColors.messageText
		end
		local summaryLabel = container:FindFirstChild("VoteSummary")
		if summaryLabel then
			summaryLabel.TextColor3 = themeColors.timestamp
		end
	end

	if container:GetAttribute("IsAnnouncement") then
		container.BackgroundColor3 = themeColors.inputFrame
		local accentBar = container:FindFirstChild("AccentBar")
		if accentBar then
			accentBar.BackgroundColor3 = themeColors.sendButton
		end
		local headerLabel = container:FindFirstChild("Header")
		if headerLabel and sender and timestamp then
			headerLabel.Text = Announcement.buildHeader(sender, timestamp, themeColors)
		end
		local bodyLabel = container:FindFirstChild("Body")
		if bodyLabel then
			bodyLabel.TextColor3 = themeColors.messageText
		end
	end

	local textLabel = container:FindFirstChild("TextContent")
	if textLabel and textLabel:IsA("TextLabel") then
		MentionPills.recolor(textLabel, themeColors)
		textLabel.TextColor3 = themeColors.messageText
		if container:FindFirstChild("Author") then
			MessageText.set(textLabel, content, themeColors, { edited = container:GetAttribute("Edited") == true })
		else
			textLabel.Text = RichText.buildMessage(sender, content, timestamp, themeColors)
		end
	end

	Author.render(container, themeColors)

	local imageLabel = container:FindFirstChild("ImageAttachment")
	if imageLabel and imageLabel:IsA("ImageLabel") then
		imageLabel.BackgroundColor3 = themeColors.scrollBack
		imageLabel.BorderColor3 = themeColors.imageBorder
	end

	EmbedManager.recolor(container, themeColors)

	AttachmentCards.recolor(container, themeColors)

	local videoFrame = container:FindFirstChild("VideoPlayer")
	if videoFrame and videoFrame:IsA("VideoFrame") then
		local loadingLabel = videoFrame:FindFirstChild("LoadingLabel")
		if loadingLabel then
			loadingLabel.TextColor3 = themeColors.loadingText
		end
		local errorLabel = videoFrame:FindFirstChild("ErrorLabel")
		if errorLabel then
			errorLabel.TextColor3 = themeColors.loadingText
		end
		local progressFill = videoFrame:FindFirstChild("ControlsBar")
		if progressFill then
			local fill = progressFill:FindFirstChild("ProgressBg")
			if fill then
				local fillBar = fill:FindFirstChild("ProgressFill")
				if fillBar then
					fillBar.BackgroundColor3 = themeColors.sendButton
				end
			end
		end
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("TextButton") and string.match(child.Name, "^Option_%d+$") then
			child.BackgroundColor3 = themeColors.pollBar
			local voteBar = child:FindFirstChild("VoteBar")
			if voteBar then
				voteBar.BackgroundColor3 = themeColors.pollBarVoted
			end
			local label = child:FindFirstChild("Label")
			if label then
				label.TextColor3 = themeColors.pollBarText
			end
			local voteCount = child:FindFirstChild("VoteCount")
			if voteCount then
				voteCount.TextColor3 = themeColors.pollBarText
			end
		end
	end
end

return Recolor
