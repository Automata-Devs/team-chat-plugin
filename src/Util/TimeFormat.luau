--!
-- TimeFormatter
-- Utility for formatting timestamps in [HH:MM] format.
-- Times are rendered in the plugin user's local timezone (the machine
-- running Studio), so every collaborator sees message times in their own
-- timezone instead of a fixed UTC clock.
-- Supports a configurable clock format (24-hour or 12-hour with AM/PM)
-- and an option to hide timestamps entirely.
--!

local TimeFormatter = {}

-- Configurable state (set via setClockFormat / setShowTimestamps)
local clockFormat: string = "24h" -- "24h" or "12h"
local showTimestamps: boolean = true

--!
-- Sets the clock format used by format().
-- @param fmt "24h" for [HH:MM], "12h" for [H:MM AM/PM]. Invalid values are ignored.
--!
function TimeFormatter.setClockFormat(fmt: string)
	if fmt == "24h" or fmt == "12h" then
		clockFormat = fmt
	end
end

--!
-- Returns the current clock format ("24h" or "12h").
--!
function TimeFormatter.getClockFormat(): string
	return clockFormat
end

--!
-- Sets whether timestamps are shown at all. When disabled, format()
-- returns an empty string so callers can omit the time prefix.
-- @param show Whether timestamps should be rendered.
--!
function TimeFormatter.setShowTimestamps(show: boolean)
	showTimestamps = show and true or false
end

--!
-- Returns whether timestamps are currently shown.
--!
function TimeFormatter.isShowingTimestamps(): boolean
	return showTimestamps
end

--!
-- Returns a formatted time string, rendered in the plugin user's local
-- timezone. os.date("*t") resolves the timestamp against the local timezone
-- of the machine running Studio, so each collaborator sees message times
-- in their own timezone.
-- 24-hour format: "[12:34]". 12-hour format: "[12:34 PM]" / "[1:05 AM]".
-- Returns "" when timestamps are hidden.
-- @param timeValue Optional os.time() value; defaults to current time.
-- @return string e.g. "[12:34]"
--!
function TimeFormatter.format(timeValue: number?): string
	if not showTimestamps then
		return ""
	end
	timeValue = timeValue or os.time()
	local date = os.date("*t", timeValue)
	if clockFormat == "12h" then
		local hour = date.hour % 12
		if hour == 0 then
			hour = 12
		end
		local suffix = date.hour >= 12 and "PM" or "AM"
		return string.format("[%d:%02d %s]", hour, date.min, suffix)
	end
	return string.format("[%02d:%02d]", date.hour, date.min)
end

--!
-- Like format(), without the brackets: "12:34" or "1:05 PM" (message headers).
-- Returns "" when timestamps are hidden.
--!
function TimeFormatter.formatPlain(timeValue: number?): string
	local text = TimeFormatter.format(timeValue)
	return (string.gsub(text, "^%[(.*)%]$", "%1"))
end

--!
-- Returns a unique message ID based on current time and a random suffix.
-- @return string
--!
function TimeFormatter.generateId(): string
	return string.format("%d_%d", os.time(), math.random(100000, 999999))
end

return TimeFormatter
