--!
-- MessageEvents
-- Registers callbacks for incoming chat messages, file messages,
-- poll messages, and poll vote updates via the shared ChatState folder.
--!

local HttpService = game:GetService("HttpService")

local ChatState = require(script.Parent.ChatState)
local Lifetime = require(script.Parent.Parent.Parent.Core.Lifetime)

local MessageEvents = {}

--!
-- Builds the reply reference table from a message folder's ReplyTo
-- attributes, or returns nil if the message is not a reply.
--!
local function buildReplyRef(child: Instance)
	local replyToTimestamp = child:GetAttribute("ReplyToTimestamp")
	if not replyToTimestamp then
		return nil
	end
	return {
		timestamp = replyToTimestamp,
		sender = child:GetAttribute("ReplyToSender"),
		content = child:GetAttribute("ReplyToContent"),
	}
end

--!
-- Registers a callback for new incoming text messages.
--!
function MessageEvents.onMessageReceived(callback: (string, number, string, string?, number, string?, table?) -> ()): RBXScriptConnection?
	local folder = ChatState.getFolder()
	return Lifetime.connect(folder.ChildAdded, function(child)
		local msgType = child:GetAttribute("MessageType") or ChatState.MESSAGE_TYPE_TEXT
		if msgType == ChatState.MESSAGE_TYPE_POLL or msgType == ChatState.MESSAGE_TYPE_FILE then return end
		local sender = child:GetAttribute("Sender") or "Unknown"
		local senderId = child:GetAttribute("SenderId") or 0
		local timestamp = child:GetAttribute("Timestamp") or os.time()
		local content = child:GetAttribute("Content") or ""
		local imageUrl = child:GetAttribute("ImageUrl")
		local replyRef = buildReplyRef(child)
		callback(sender, timestamp, content, imageUrl, senderId, msgType, replyRef)
	end)
end

--!
-- Registers a callback for new incoming file messages.
--!
function MessageEvents.onFileReceived(callback: (string, number, string, string, string, string, table?) -> ()): RBXScriptConnection?
	local folder = ChatState.getFolder()
	return Lifetime.connect(folder.ChildAdded, function(child)
		local msgType = child:GetAttribute("MessageType") or ChatState.MESSAGE_TYPE_TEXT
		if msgType ~= ChatState.MESSAGE_TYPE_FILE then return end
		local sender = child:GetAttribute("Sender") or "Unknown"
		local timestamp = child:GetAttribute("Timestamp") or os.time()
		local fileName = child:GetAttribute("FileName") or "file"
		local fileUrl = child:GetAttribute("FileUrl") or ""
		local fileType = child:GetAttribute("FileType") or "Other"
		local content = child:GetAttribute("Content") or ""
		-- 7th argument is the reply reference (nil when not a reply), as the UI expects
		callback(sender, timestamp, fileName, fileUrl, fileType, content, buildReplyRef(child))
	end)
end

--!
-- Registers a callback for new incoming poll messages.
--!
function MessageEvents.onPollReceived(callback: (string, number, table, number) -> ()): RBXScriptConnection?
	local folder = ChatState.getFolder()
	return Lifetime.connect(folder.ChildAdded, function(child)
		local msgType = child:GetAttribute("MessageType") or ChatState.MESSAGE_TYPE_TEXT
		if msgType ~= ChatState.MESSAGE_TYPE_POLL then return end
		local sender = child:GetAttribute("Sender") or "Unknown"
		local senderId = child:GetAttribute("SenderId") or 0
		local timestamp = child:GetAttribute("Timestamp") or os.time()
		local question = child:GetAttribute("Question") or ""
		local okOpts, options = pcall(function()
			return HttpService:JSONDecode(child:GetAttribute("Options") or "[]")
		end)
		local okVotes, votes = pcall(function()
			return HttpService:JSONDecode(child:GetAttribute("Votes") or "[]")
		end)
		local pollData = {
			question = question,
			options = okOpts and options or {},
			votes = okVotes and votes or {},
		}
		callback(sender, timestamp, pollData, senderId)
	end)
end

--!
-- Registers a callback for vote updates on existing poll messages.
--!
function MessageEvents.onPollUpdate(callback: (number, table) -> ()): RBXScriptConnection?
	local folder = ChatState.getFolder()
	local function watchChild(child)
		local msgType = child:GetAttribute("MessageType") or ChatState.MESSAGE_TYPE_TEXT
		if msgType ~= ChatState.MESSAGE_TYPE_POLL then return end
		local timestamp = child:GetAttribute("Timestamp") or os.time()
		local question = child:GetAttribute("Question") or ""
		local okOpts, options = pcall(function()
			return HttpService:JSONDecode(child:GetAttribute("Options") or "[]")
		end)
		Lifetime.connect(child:GetAttributeChangedSignal("Votes"), function()
			local okV, newVotes = pcall(function()
				return HttpService:JSONDecode(child:GetAttribute("Votes") or "[]")
			end)
			local pollData = {
				question = question,
				options = okOpts and options or {},
				votes = okV and newVotes or {},
			}
			callback(timestamp, pollData)
		end)
	end
	for _, child in ipairs(folder:GetChildren()) do
		watchChild(child)
	end
	Lifetime.connect(folder.ChildAdded, watchChild)
	return nil
end

return MessageEvents