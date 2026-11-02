--!
-- MediaFocus
-- Only one audio clip or video plays at a time: whatever starts playing
-- claims focus, which stops the previous one.
--!

local MediaFocus = {}

local currentOwner: any = nil
local currentStop: (() -> ())? = nil

--!
-- Call right before something starts playing. stop() pauses it if another
-- player claims focus later.
--!
function MediaFocus.claim(owner: any, stop: () -> ())
	if currentOwner ~= owner and currentStop then
		pcall(currentStop)
	end
	currentOwner = owner
	currentStop = stop
end

--!
-- Call when the owner goes away so it isn't stopped (or kept alive) later.
--!
function MediaFocus.release(owner: any)
	if currentOwner == owner then
		currentOwner = nil
		currentStop = nil
	end
end

return MediaFocus
