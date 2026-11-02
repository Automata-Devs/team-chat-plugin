--!
-- PollManager
-- Handles poll creation and vote casting for the chat system.
-- Operates on the shared ChatState module.
--!

local HttpService = game:GetService("HttpService")

local TimeFormatter = require(script.Parent.Parent.Parent.Utils.TimeFormatter)
local ChatState = require(script.Parent.ChatState)

local PollManager = {}

--!
-- Sends a poll message with the given question and options.
--!
function PollManager.sendPoll(question: string, options: {string})
	local folder = ChatState.getActiveFolder()
	local message = Instance.new("Folder")
	message.Name = "poll_" .. TimeFormatter.generateId()
	message:SetAttribute("Sender", ChatState.currentUsername)
	message:SetAttribute("SenderId", ChatState.currentUserId)
	message:SetAttribute("Timestamp", os.time())
	message:SetAttribute("Content", "")
	message:SetAttribute("MessageType", ChatState.MESSAGE_TYPE_POLL)
	message:SetAttribute("Question", question)
	message:SetAttribute("Options", HttpService:JSONEncode(options))

	-- Initialize votes: one empty voter list per option
	local votes = {}
	for _ in ipairs(options) do
		table.insert(votes, {})
	end
	message:SetAttribute("Votes", HttpService:JSONEncode(votes))
	message.Parent = folder
	ChatState.saveHistory()
end

--!
-- Casts a vote on a poll message. Removes the voter's previous vote if any.
-- Clicking the current choice again toggles the vote off.
--!
function PollManager.castVote(timestamp: number, optionIndex: number)
	local folder = ChatState.getActiveFolder()
	for _, child in ipairs(folder:GetChildren()) do
		if child:GetAttribute("Timestamp") == timestamp
			and (child:GetAttribute("MessageType") or ChatState.MESSAGE_TYPE_TEXT) == ChatState.MESSAGE_TYPE_POLL then

			local votesJson = child:GetAttribute("Votes") or "[]"
			local ok, votes = pcall(function()
				return HttpService:JSONDecode(votesJson)
			end)
			if not ok or not votes then return end

			if optionIndex < 1 or optionIndex > #votes then return end

			-- Clicking the current choice again toggles that vote off.
			local isDeselecting = false
			for i, voters in ipairs(votes) do
				for j = #voters, 1, -1 do
					if voters[j] == ChatState.currentUsername then
						if i == optionIndex then isDeselecting = true end
						table.remove(voters, j)
					end
				end
			end

			-- Otherwise move the vote to the newly selected option.
			if not isDeselecting then
				table.insert(votes[optionIndex], ChatState.currentUsername)
			end

			child:SetAttribute("Votes", HttpService:JSONEncode(votes))
			ChatState.saveHistory()
			return
		end
	end
end

return PollManager