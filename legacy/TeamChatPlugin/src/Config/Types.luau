--!
-- Types
-- Shared type definitions for the TeamChat plugin.
-- Provides centralized type annotations for messages, commands,
-- poll data, and user context to ensure type safety across modules.
--!

--!
-- Admin rank constants.
--!
export type Rank = number

--!
-- A single poll option and its voters.
--!
export type PollData = {
	question: string,
	options: {string},
	votes: {{string}},
}

--!
-- Message types supported by the chat system.
--!
export type MessageType = "Text" | "Poll" | "File"

--!
-- A chat message entry as stored in the DataModel.
--!
export type MessageEntry = {
	sender: string,
	senderId: number,
	timestamp: number,
	content: string,
	imageUrl: string?,
	messageType: MessageType,
	-- Poll-specific fields
	question: string?,
	options: {string}?,
	votes: {{string}}?,
	pollData: PollData?,
	-- File-specific fields
	fileName: string?,
	fileUrl: string?,
	fileType: string?,
}

--!
-- The command module schema that all commands follow.
--!
export type Command = {
	Name: string,
	Aliases: {string}?,
	Prefixes: {string}?,
	Rank: number?,
	RankLock: boolean?,
	Loopable: boolean?,
	Tags: {string}?,
	Description: string?,
	Contributors: {string}?,
	Args: {string}?,
	Function: (speaker: Speaker, args: {string}, ctx: CommandContext) -> (),
}

--!
-- The speaker info passed to command functions.
--!
export type Speaker = {
	userId: number,
	username: string,
	rank: number,
}

--!
-- The context table passed to command functions, providing
-- access to UI callbacks and network helpers.
--!
export type CommandContext = {
	addSystemMessage: (text: string) -> (),
	clearChat: () -> (),
	sendMessage: (msg: string) -> (),
	getUsername: () -> string,
	getUserId: () -> number,
	getPendingImage: () -> string?,
	getPendingFile: () -> {fileName: string, fileUrl: string, fileType: string}?,
	clearPendingImage: () -> (),
	clearPendingFile: () -> (),
	setTextBox: (text: string) -> (),
	textBoxText: () -> string,
}

--!
-- A pending file attachment.
--!
export type PendingFile = {
	fileName: string,
	fileUrl: string,
	fileType: string,
}

return {}