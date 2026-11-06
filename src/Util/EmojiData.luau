--!
-- EmojiData
-- Emoji shortcode database (Discord/Slack style, e.g. :sob: -> 😭).
-- The list order is the default popularity order, used when nothing has been
-- used yet. Provides lookup, search (for the autocomplete menu) and
-- replaceShortcodes (for converting :name: inside a string).
--!

local EmojiData = {}

export type Entry = {
	name: string,
	emoji: string,
	aliases: { string },
}

-- { name, emoji, aliases? } -- ordered roughly by how commonly they're used.
local RAW: { { any } } = {
	-- Popular faces
	{ "joy", "😂" },
	{ "sob", "😭" },
	{ "smile", "😄" },
	{ "grin", "😁" },
	{ "laughing", "😆", { "satisfied" } },
	{ "rofl", "🤣" },
	{ "sweat_smile", "😅" },
	{ "slight_smile", "🙂", { "slightly_smiling_face" } },
	{ "wink", "😉" },
	{ "blush", "😊" },
	{ "heart_eyes", "😍" },
	{ "kissing_heart", "😘" },
	{ "star_struck", "🤩" },
	{ "thinking", "🤔", { "think" } },
	{ "sunglasses", "😎", { "cool" } },
	{ "pleading", "🥺", { "pleading_face" } },
	{ "cry", "😢" },
	{ "scream", "😱" },
	{ "rage", "😡", { "pout" } },
	{ "angry", "😠" },
	{ "skull", "💀" },
	{ "exploding_head", "🤯", { "mind_blown" } },
	{ "partying", "🥳", { "partying_face" } },
	-- No Emoji 14+ (🫠 melting, 🫡 saluting, ...): Roblox draws them as empty boxes
	{ "roll_eyes", "🙄", { "eye_roll" } },
	{ "smirk", "😏" },
	{ "unamused", "😒" },
	{ "neutral_face", "😐", { "neutral" } },
	{ "expressionless", "😑" },
	{ "relieved", "😌" },
	{ "pensive", "😔" },
	{ "disappointed", "😞" },
	{ "worried", "😟" },
	{ "fearful", "😨" },
	{ "cold_sweat", "😰" },
	{ "flushed", "😳" },
	{ "weary", "😩" },
	{ "tired_face", "😫" },
	{ "triumph", "😤" },
	{ "sleepy", "😪" },
	{ "sleeping", "😴" },
	{ "yawning", "🥱", { "yawn" } },
	{ "yum", "😋" },
	{ "stuck_out_tongue", "😛" },
	{ "stuck_out_tongue_winking_eye", "😜" },
	{ "zany_face", "🤪", { "crazy" } },
	{ "nerd", "🤓", { "nerd_face" } },
	{ "monocle", "🧐", { "monocle_face" } },
	{ "hugging", "🤗", { "hug" } },
	{ "upside_down", "🙃", { "upside_down_face" } },
	{ "innocent", "😇", { "angel" } },
	{ "smiling_imp", "😈", { "devil" } },
	{ "shushing", "🤫", { "shushing_face", "shh" } },
	{ "zipper_mouth", "🤐" },
	{ "money_mouth", "🤑" },
	{ "hot_face", "🥵", { "hot" } },
	{ "cold_face", "🥶", { "cold" } },
	{ "mask", "😷" },
	{ "sneezing", "🤧", { "sneeze" } },
	{ "nauseated", "🤢", { "sick" } },
	{ "vomiting", "🤮", { "puke" } },
	{ "clown", "🤡" },
	{ "ghost", "👻" },
	{ "poop", "💩", { "hankey", "shit" } },
	{ "alien", "👽" },
	{ "robot", "🤖" },
	{ "face_palm", "🤦", { "facepalm" } },
	{ "shrug", "🤷" },

	-- Gestures & people
	{ "thumbsup", "👍", { "+1", "thumbs_up", "like" } },
	{ "thumbsdown", "👎", { "-1", "thumbs_down", "dislike" } },
	{ "clap", "👏" },
	{ "raised_hands", "🙌" },
	{ "pray", "🙏", { "please", "thanks" } },
	{ "wave", "👋", { "hello", "hi" } },
	{ "ok_hand", "👌", { "ok" } },
	{ "muscle", "💪", { "flex", "strong" } },
	{ "fist", "👊", { "punch" } },
	{ "v", "✌️", { "peace", "victory" } },
	{ "crossed_fingers", "🤞", { "fingers_crossed" } },
	{ "metal", "🤘" },
	{ "call_me", "🤙" },
	{ "point_up", "☝️" },
	{ "point_down", "👇" },
	{ "point_left", "👈" },
	{ "point_right", "👉" },
	{ "open_hands", "👐" },
	{ "handshake", "🤝", { "deal" } },
	{ "writing_hand", "✍️" },
	{ "eyes", "👀", { "look" } },
	{ "brain", "🧠" },
	{ "see_no_evil", "🙈" },
	{ "hear_no_evil", "🙉" },
	{ "speak_no_evil", "🙊" },

	-- Hearts, sparkles & celebration
	{ "heart", "❤️", { "love", "red_heart" } },
	{ "orange_heart", "🧡" },
	{ "yellow_heart", "💛" },
	{ "green_heart", "💚" },
	{ "blue_heart", "💙" },
	{ "purple_heart", "💜" },
	{ "black_heart", "🖤" },
	{ "white_heart", "🤍" },
	{ "broken_heart", "💔" },
	{ "sparkling_heart", "💖" },
	{ "two_hearts", "💕" },
	{ "fire", "🔥", { "lit", "flame" } },
	{ "100", "💯", { "hundred" } },
	{ "sparkles", "✨" },
	{ "star", "⭐" },
	{ "star2", "🌟", { "glowing_star" } },
	{ "boom", "💥", { "explosion" } },
	{ "zap", "⚡", { "lightning" } },
	{ "tada", "🎉", { "party", "celebrate" } },
	{ "confetti_ball", "🎊" },
	{ "balloon", "🎈" },
	{ "gift", "🎁", { "present" } },
	{ "trophy", "🏆" },
	{ "medal", "🏅" },
	{ "crown", "👑" },
	{ "gem", "💎", { "diamond" } },
	{ "rocket", "🚀", { "launch" } },

	-- Symbols & status
	{ "white_check_mark", "✅", { "check", "done" } },
	{ "heavy_check_mark", "✔️" },
	{ "x", "❌", { "cross", "no" } },
	{ "warning", "⚠️", { "caution" } },
	{ "no_entry", "⛔" },
	{ "no_entry_sign", "🚫", { "prohibited" } },
	{ "question", "❓" },
	{ "exclamation", "❗", { "bangbang" } },
	{ "info", "ℹ️", { "information" } },
	{ "rotating_light", "🚨", { "alert", "siren" } },
	{ "construction", "🚧", { "wip" } },
	{ "recycle", "♻️" },
	{ "lock", "🔒", { "locked" } },
	{ "unlock", "🔓", { "unlocked" } },
	{ "key", "🔑" },
	{ "shield", "🛡️" },
	{ "bell", "🔔", { "notification" } },
	{ "arrow_up", "⬆️", { "up" } },
	{ "arrow_down", "⬇️", { "down" } },
	{ "arrow_left", "⬅️", { "left" } },
	{ "arrow_right", "➡️", { "right" } },
	{ "repeat", "🔁", { "loop" } },
	{ "refresh", "🔄", { "arrows_counterclockwise" } },

	-- Dev, tools & work
	{ "computer", "💻", { "laptop", "pc" } },
	{ "keyboard", "⌨️" },
	{ "bug", "🐛" },
	{ "gear", "⚙️", { "settings", "cog" } },
	{ "wrench", "🔧" },
	{ "hammer", "🔨" },
	{ "tools", "🛠️", { "hammer_and_wrench" } },
	{ "package", "📦" },
	{ "link", "🔗" },
	{ "pushpin", "📌", { "pin" } },
	{ "memo", "📝", { "note", "pencil" } },
	{ "clipboard", "📋" },
	{ "calendar", "📅" },
	{ "bulb", "💡", { "idea", "light_bulb" } },
	{ "mag", "🔍", { "search" } },
	{ "books", "📚" },
	{ "chart_with_upwards_trend", "📈", { "chart_up", "growth" } },
	{ "chart_with_downwards_trend", "📉", { "chart_down" } },
	{ "hourglass", "⏳" },
	{ "alarm_clock", "⏰", { "alarm" } },
	{ "stopwatch", "⏱️", { "timer" } },
	{ "folder", "📁" },
	{ "page_facing_up", "📄", { "file", "page" } },
	{ "floppy_disk", "💾", { "save" } },
	{ "wastebasket", "🗑️", { "trash", "delete" } },
	{ "email", "📧", { "mail" } },
	{ "inbox_tray", "📥", { "inbox" } },
	{ "outbox_tray", "📤", { "outbox" } },
	{ "megaphone", "📣", { "announce" } },
	{ "battery", "🔋" },
	{ "electric_plug", "🔌", { "plug" } },
	{ "globe", "🌐", { "web", "internet" } },
	{ "cloud", "☁️" },

	-- Games, media & creativity
	{ "video_game", "🎮", { "game", "controller" } },
	{ "joystick", "🕹️" },
	{ "dart", "🎯", { "target", "bullseye" } },
	{ "game_die", "🎲", { "dice" } },
	{ "jigsaw", "🧩", { "puzzle" } },
	{ "bricks", "🧱", { "brick" } },
	{ "art", "🎨", { "palette" } },
	{ "camera", "📷" },
	{ "microphone", "🎤", { "mic" } },
	{ "headphones", "🎧" },
	{ "loud_sound", "🔊", { "speaker", "volume" } },
	{ "mute", "🔇" },
	{ "musical_note", "🎵", { "music" } },
	{ "checkered_flag", "🏁", { "finish" } },
	{ "soccer", "⚽" },
	{ "basketball", "🏀" },
	{ "football", "🏈" },

	-- Nature & animals
	{ "sun", "☀️", { "sunny" } },
	{ "moon", "🌙" },
	{ "rainbow", "🌈" },
	{ "snowflake", "❄️" },
	{ "umbrella", "☔" },
	{ "earth_africa", "🌍", { "earth", "world" } },
	{ "tree", "🌳", { "deciduous_tree" } },
	{ "cactus", "🌵" },
	{ "rose", "🌹" },
	{ "sunflower", "🌻" },
	{ "dog", "🐶" },
	{ "cat", "🐱" },
	{ "fox", "🦊", { "fox_face" } },
	{ "panda", "🐼", { "panda_face" } },
	{ "unicorn", "🦄" },
	{ "penguin", "🐧" },
	{ "chicken", "🐔" },
	{ "monkey", "🐵", { "monkey_face" } },
	{ "snake", "🐍" },
	{ "turtle", "🐢" },
	{ "whale", "🐳" },
	{ "octopus", "🐙" },
	{ "butterfly", "🦋" },
	{ "bee", "🐝", { "honeybee" } },

	-- Food & drink
	{ "pizza", "🍕" },
	{ "hamburger", "🍔", { "burger" } },
	{ "fries", "🍟" },
	{ "taco", "🌮" },
	{ "sushi", "🍣" },
	{ "popcorn", "🍿" },
	{ "cake", "🍰", { "shortcake" } },
	{ "cookie", "🍪" },
	{ "doughnut", "🍩", { "donut" } },
	{ "ice_cream", "🍦", { "icecream" } },
	{ "apple", "🍎", { "red_apple" } },
	{ "banana", "🍌" },
	{ "watermelon", "🍉" },
	{ "strawberry", "🍓" },
	{ "avocado", "🥑" },
	{ "coffee", "☕" },
	{ "tea", "🍵" },
	{ "beer", "🍺" },
	{ "beers", "🍻", { "cheers" } },
	{ "wine_glass", "🍷", { "wine" } },
	{ "champagne", "🍾" },

	-- Misc
	{ "zzz", "💤" },
	{ "sweat_drops", "💦", { "water" } },
	{ "dash", "💨", { "wind", "fast" } },
	{ "moneybag", "💰", { "money" } },
	{ "dollar", "💵", { "cash" } },
	{ "house", "🏠", { "home" } },
	{ "car", "🚗" },
	{ "airplane", "✈️", { "plane" } },
	{ "footprints", "👣" },
}

-- Built once at require-time.
local entries: { Entry } = {}
local byName: { [string]: Entry } = {} -- name AND aliases -> entry
local orderIndex: { [Entry]: number } = {}

for index, raw in ipairs(RAW) do
	local entry: Entry = {
		name = raw[1],
		emoji = raw[2],
		aliases = raw[3] or {},
	}
	entries[index] = entry
	orderIndex[entry] = index

	byName[entry.name] = entry
	for _, alias in ipairs(entry.aliases) do
		-- Never let an alias shadow a real emoji name.
		if byName[alias] == nil then
			byName[alias] = entry
		end
	end
end

--!
-- Returns true if a shortcode starting at the end of `prefix` is allowed there.
-- A shortcode must not directly follow a letter or digit, so things like
-- "12:30:45" or "Note:sob:" are left alone.
--!
function EmojiData.isValidBoundary(prefix: string): boolean
	return prefix == "" or not prefix:find("%w$")
end

--!
-- Looks up an emoji by shortcode name or alias (case-insensitive).
-- @return Entry? - nil if the name is unknown
--!
function EmojiData.get(name: string): Entry?
	return byName[name:lower()]
end

--!
-- Finds emojis for the autocomplete menu.
-- Matches on names and aliases: prefix matches rank before substring matches.
-- Within each group, entries are ordered by the supplied score (e.g. usage
-- count, higher first) and then by the default popularity order.
-- @param query string - text typed after the colon (may be empty)
-- @param getScore ((Entry) -> number)? - optional ranking score
-- @param limit number? - maximum results (default: all matches)
--!
function EmojiData.search(query: string, getScore: ((Entry) -> number)?, limit: number?): { Entry }
	local q = query:lower()
	local prefixMatches: { Entry } = {}
	local containsMatches: { Entry } = {}

	for _, entry in ipairs(entries) do
		if q == "" then
			table.insert(prefixMatches, entry)
		else
			local isPrefix = entry.name:sub(1, #q) == q
			local isContains = not isPrefix and entry.name:find(q, 1, true) ~= nil

			if not isPrefix and not isContains then
				for _, alias in ipairs(entry.aliases) do
					if alias:sub(1, #q) == q then
						isPrefix = true
						break
					elseif alias:find(q, 1, true) then
						isContains = true
					end
				end
			end

			if isPrefix then
				table.insert(prefixMatches, entry)
			elseif isContains then
				table.insert(containsMatches, entry)
			end
		end
	end

	local function sortGroup(group: { Entry })
		table.sort(group, function(a, b)
			local scoreA = getScore and getScore(a) or 0
			local scoreB = getScore and getScore(b) or 0
			if scoreA ~= scoreB then
				return scoreA > scoreB
			end
			return orderIndex[a] < orderIndex[b]
		end)
	end
	sortGroup(prefixMatches)
	sortGroup(containsMatches)

	local results: { Entry } = {}
	local max = limit or math.huge
	for _, group in ipairs({ prefixMatches, containsMatches }) do
		for _, entry in ipairs(group) do
			if #results >= max then
				return results
			end
			table.insert(results, entry)
		end
	end
	return results
end

--!
-- Replaces every known :shortcode: in `text` with its emoji.
-- Unknown shortcodes and ones directly after a letter/digit are left untouched.
-- @param onReplace ((Entry) -> ())? - called once per replacement (usage tracking)
--!
function EmojiData.replaceShortcodes(text: string, onReplace: ((Entry) -> ())?): string
	if not text:find(":", 1, true) then
		return text
	end

	local result = text:gsub("()(:[%w_%+%-]+:)", function(position: number, token: string)
		if not EmojiData.isValidBoundary(text:sub(1, position - 1)) then
			return nil -- keep original text
		end
		local entry = byName[token:sub(2, -2):lower()]
		if not entry then
			return nil
		end
		if onReplace then
			onReplace(entry)
		end
		return entry.emoji
	end)
	return result
end

return EmojiData
