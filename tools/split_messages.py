"""One-off refactor: moves the message builders at the top of UI/ChatWindow.luau
into UI/Messages/* modules, verbatim, and points ChatWindow at them.

Run once from the repo root: python tools/split_messages.py
"""
import os
import re

WINDOW = "src/UI/ChatWindow.luau"
OUT = "src/UI/Messages"

src = open(WINDOW, encoding="utf-8").read()
lines = src.split("\n")


def find_function(name):
    for i, line in enumerate(lines):
        if re.match(rf"^local function {name}\(", line):
            return i
    raise SystemExit("not found: " + name)


def with_doc(start):
    """Walks back over the comment block directly above a function."""
    while start > 0 and lines[start - 1].startswith("--"):
        start -= 1
    return start


def block(first_index, end_index):
    return "\n".join(lines[first_index:end_index]).rstrip() + "\n"


create_doc = with_doc(next(i for i, l in enumerate(lines) if l.startswith("function ChatUI.create(")))
order = [
    "buildAnnouncementHeader",
    "createReplyReference",
    "addMessageSurface",
    "createMessageContainer",
    "createAnnouncementContainer",
    "createPollContainer",
    "updatePollVotes",
    "addFileCardBounds",
    "createFileContainer",
    "recolorMessageContainer",
]
starts = {name: with_doc(find_function(name)) for name in order}
# Shared state that sits between buildAnnouncementHeader and createReplyReference
jump_decl = next(i for i, l in enumerate(lines) if l.startswith("local jumpToMessage"))
starts["sharedState"] = with_doc(jump_decl)
file_consts = next(i for i, l in enumerate(lines) if l.startswith("-- File and audio cards fill the chat width"))
starts["addFileCardBounds"] = file_consts

sequence = sorted(starts.items(), key=lambda kv: kv[1])
ends = {}
for (name, start), (_, next_start) in zip(sequence, sequence[1:] + [("end", create_doc)]):
    ends[name] = next_start

region_start = min(starts.values())
region_end = create_doc


def piece(name):
    return block(starts[name], ends[name])


def rewrite(code):
    code = code.replace("messageTextSize", "Shared.textSize")
    code = re.sub(r"\bjumpToMessage\b", "Shared.jumpToMessage", code)
    code = re.sub(r"(?<![\w.])createReplyReference\(", "Shared.createReplyReference(", code)
    code = re.sub(r"(?<![\w.])addMessageSurface\(", "Shared.addMessageSurface(", code)
    code = re.sub(r"(?<![\w.])buildRichText\(", "RichText.buildMessage(", code)
    code = re.sub(r"(?<![\w.])toHex\(", "RichText.toHex(", code)
    code = code.replace("RichTextHelper.", "RichText.")
    return code


REQUIRES = {
    "Theme": "local Theme = require(script.Parent.Parent.Parent.Config.Theme)",
    "Icons": "local Icons = require(script.Parent.Parent.Parent.Config.Icons)",
    "RichText": "local RichText = require(script.Parent.Parent.Parent.Util.RichText)",
    "TimeFormatter": "local TimeFormatter = require(script.Parent.Parent.Parent.Util.TimeFormat)",
    "UsernameColors": "local UsernameColors = require(script.Parent.Parent.Parent.Util.UsernameColors)",
    "GifPlayer": "local GifPlayer = require(script.Parent.Parent.Components.GifPlayer)",
    "AudioPlayback": "local AudioPlayback = require(script.Parent.Parent.Components.AudioPlayback)",
    "AttachmentCards": "local AttachmentCards = require(script.Parent.Parent.Components.AttachmentCards)",
    "EmbedManager": "local EmbedManager = require(script.Parent.Parent.Embeds.EmbedManager)",
    "Shared": "local Shared = require(script.Shared)",
    "Announcement": "local Announcement = require(script.Announcement)",
}
ALIASES = {
    "FONT": "local FONT = Theme.FONT",
    "FONTS": "local FONTS = Theme.FONTS",
    "MAX_IMAGE_HEIGHT": "local MAX_IMAGE_HEIGHT = Theme.MAX_IMAGE_HEIGHT",
}


def module(name, title, purpose, body, exports, sibling=True):
    uses = [key for key in REQUIRES if re.search(rf"\b{key}\.", body)]
    requires = []
    for key in uses:
        line = REQUIRES[key]
        if sibling:
            line = line.replace("script.Shared", "script.Parent.Shared").replace("script.Announcement", "script.Parent.Announcement")
        requires.append(line)
    if any(re.search(rf"\b{a}\b", body) for a in ALIASES) and "Theme" not in uses:
        requires.insert(0, REQUIRES["Theme"])
    aliases = [line for key, line in ALIASES.items() if re.search(rf"\b{key}\b", body)]
    head = f"--[[\n\t{title}\n\n{purpose}\n]]\n\n"
    out = head + "\n".join(sorted(requires)) + "\n"
    if aliases:
        out += "\n" + "\n".join(aliases) + "\n"
    out += f"\nlocal {name} = {{}}\n\n" + body + "\n" + exports + f"\nreturn {name}\n"
    return out


os.makedirs(OUT, exist_ok=True)

shared_body = rewrite(piece("sharedState") + "\n" + piece("createReplyReference") + "\n" + piece("addMessageSurface"))
shared_body = shared_body.replace("local Shared.jumpToMessage: ((number) -> ())? = nil", "Shared.jumpToMessage = nil :: ((number) -> ())?")
shared_body = shared_body.replace("local function Shared.createReplyReference(", "function Shared.createReplyReference(")
shared_body = shared_body.replace("local function Shared.addMessageSurface(", "function Shared.addMessageSurface(")
shared_body = (
    "-- Message text size options (pixel sizes), chosen in Settings.\n"
    "Shared.TEXT_SIZES = { Small = 12, Default = 14, Large = 16 }\n"
    "Shared.textSize = Shared.TEXT_SIZES.Default\n\n" + shared_body
)
files = {
    "Shared": module(
        "Shared", "Messages/Shared",
        "\tState and pieces shared by every message builder: the message text size,\n"
        "\tthe jump-to-message handler (set by ChatWindow), the reply line shown above\n"
        "\treplies and the rounded surface that the jump flash lights up.",
        shared_body, "", sibling=True),
}

def rename(code, old, new):
    code = code.replace(f"local function {old}(", f"function {new}(")
    return code

announcement = rewrite(piece("buildAnnouncementHeader") + "\n" + piece("createAnnouncementContainer"))
announcement = rename(rename(announcement, "buildAnnouncementHeader", "Announcement.buildHeader"), "createAnnouncementContainer", "Announcement.create")
announcement = re.sub(r"(?<![\w.])buildAnnouncementHeader\(", "Announcement.buildHeader(", announcement)
files["Announcement"] = module("Announcement", "Messages/Announcement",
    "\tThe highlighted announcement card (/broadcast): accent bar, header with\n"
    "\tthe megaphone, sender and time, and the message body.", announcement, "")

text = rename(rewrite(piece("createMessageContainer")), "createMessageContainer", "TextMessage.create")
files["TextMessage"] = module("TextMessage", "Messages/TextMessage",
    "\tA normal chat line: optional reply line, \"<time> [sender]: text\" and an\n"
    "\toptional inline image (GIFs animate through GifPlayer).", text, "")

poll = rewrite(piece("createPollContainer") + "\n" + piece("updatePollVotes"))
poll = rename(rename(poll, "createPollContainer", "PollMessage.create"), "updatePollVotes", "PollMessage.updateVotes")
poll = re.sub(r"(?<![\w.])updatePollVotes\(", "PollMessage.updateVotes(", poll)
files["PollMessage"] = module("PollMessage", "Messages/PollMessage",
    "\tA poll card: header, question, one bar per answer with its share of the\n"
    "\tvotes, and a summary. updateVotes() refreshes the bars when votes change.", poll, "")

file_msg = rewrite(piece("addFileCardBounds") + "\n" + piece("createFileContainer"))
file_msg = rename(rename(file_msg, "addFileCardBounds", "FileMessage.addCardBounds"), "createFileContainer", "FileMessage.create")
file_msg = re.sub(r"(?<![\w.])addFileCardBounds\b", "FileMessage.addCardBounds", file_msg)
files["FileMessage"] = module("FileMessage", "Messages/FileMessage",
    "\tA file message: the audio player card for audio, otherwise the generic file\n"
    "\tcard (AttachmentCards). Cards stay between FILE_CARD_MIN_WIDTH and\n"
    "\tFILE_CARD_MAX_WIDTH wide.", file_msg, "")

recolor = rewrite(piece("recolorMessageContainer"))
recolor = rename(recolor, "recolorMessageContainer", "Recolor.apply")
recolor = re.sub(r"(?<![\w.])buildAnnouncementHeader\(", "Announcement.buildHeader(", recolor)
files["Recolor"] = module("Recolor", "Messages/Recolor",
    "\tRe-themes an existing message (any kind) after the palette or the display\n"
    "\tsettings changed.", recolor, "")

for name, code in files.items():
    with open(os.path.join(OUT, name + ".luau"), "w", encoding="utf-8", newline="\n") as f:
        f.write(code)

facade = '''--!strict
--[[
	Messages

	Builds the rows of the message list, one module per kind of message.
	ChatWindow creates rows through this facade and sets the shared state.

	Usage:
		local row = Messages.text(sender, timestamp, content, imageUrl, palette, replyRef)
		Messages.setTextSize("Large")
		Messages.setJumpHandler(function(timestamp) ... end)
		Messages.recolor(row, palette)
]]

local Announcement = require(script.Announcement)
local FileMessage = require(script.FileMessage)
local PollMessage = require(script.PollMessage)
local Recolor = require(script.Recolor)
local Shared = require(script.Shared)
local TextMessage = require(script.TextMessage)

local Messages = {}

Messages.text = TextMessage.create
Messages.announcement = Announcement.create
Messages.poll = PollMessage.create
Messages.updatePollVotes = PollMessage.updateVotes
Messages.file = FileMessage.create
Messages.recolor = Recolor.apply

--[=[
	Sets the message text size ("Small" | "Default" | "Large").
]=]
function Messages.setTextSize(sizeName: string)
	Shared.textSize = Shared.TEXT_SIZES[sizeName] or Shared.TEXT_SIZES.Default
end

--[=[
	The current message text size in pixels.
]=]
function Messages.getTextSize(): number
	return Shared.textSize
end

--[=[
	Sets what clicking a reply line does (scroll to and flash the original).
]=]
function Messages.setJumpHandler(handler: (timestamp: number) -> ())
	Shared.jumpToMessage = handler
end

return Messages
'''
with open(os.path.join(OUT, "init.luau"), "w", encoding="utf-8", newline="\n") as f:
    f.write(facade)

# ChatWindow: drop the region, use the facade
kept = lines[:region_start] + lines[region_end:]
window = "\n".join(kept)
replacements = [
    (r"(?<![\w.])createMessageContainer\(", "Messages.text("),
    (r"(?<![\w.])createAnnouncementContainer\(", "Messages.announcement("),
    (r"(?<![\w.])createPollContainer\(", "Messages.poll("),
    (r"(?<![\w.])updatePollVotes\(", "Messages.updatePollVotes("),
    (r"(?<![\w.])createFileContainer\(", "Messages.file("),
    (r"(?<![\w.])recolorMessageContainer\(", "Messages.recolor("),
    (r"(?<![\w.])detectTheme\b", "Theme.detect"),
]
for pattern, new in replacements:
    window = re.sub(pattern, new, window)
window = window.replace("\tjumpToMessage = function(timestamp)", "\tMessages.setJumpHandler(function(timestamp)")
window = window.replace("label.TextSize = messageTextSize", "label.TextSize = Messages.getTextSize()")
window = window.replace("messageTextSize = TEXT_SIZES[sizeName] or TEXT_SIZES.Default", "Messages.setTextSize(sizeName)")
window = window.replace("local Links = require(script.Parent.Parent.Util.Links)\n",
                        "local Links = require(script.Parent.Parent.Util.Links)\nlocal Messages = require(script.Parent.Messages)\n")
open(WINDOW, "w", encoding="utf-8", newline="\n").write(window)
print("region", region_start + 1, "-", region_end, "moved;", {k: (v + 1, ends[k]) for k, v in starts.items()})
