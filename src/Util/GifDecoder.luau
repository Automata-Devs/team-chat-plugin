--!
-- GifDecoder
-- Decodes GIF files (GIF87a/GIF89a) in Luau. Roblox images can't be
-- animated, so the frames are decoded here and packed into a sprite sheet
-- (see GifPlayer).
--
-- GifDecoder.decode(data, maxFrames, onFrame)
--   data: the file's bytes
--   maxFrames: frames to keep; longer GIFs keep evenly spaced frames and
--     add the skipped frames' delays to the kept ones
--   onFrame(canvas, delayMs): called for each kept frame with the full
--     composited RGBA canvas (a buffer, reused between calls)
-- Returns width, height and the number of kept frames.
--!

local GifDecoder = {}

local band, rshift, lshift = bit32.band, bit32.rshift, bit32.lshift

local DEFAULT_DELAY_MS = 100 -- browsers use this for 0/1 centisecond delays

local function readSubBlocks(data: string, pos: number): (string, number)
	local parts = {}
	while true do
		local size = string.byte(data, pos)
		if not size then
			error("GIF ended unexpectedly")
		end
		pos += 1
		if size == 0 then
			break
		end
		table.insert(parts, string.sub(data, pos, pos + size - 1))
		pos += size
	end
	return table.concat(parts), pos
end

local function skipSubBlocks(data: string, pos: number): number
	while true do
		local size = string.byte(data, pos)
		if not size then
			error("GIF ended unexpectedly")
		end
		pos += 1 + size
		if size == 0 then
			return pos
		end
	end
end

local function readColorTable(data: string, pos: number, count: number): (buffer, number)
	local colors = buffer.create(256 * 3)
	for i = 0, count * 3 - 1 do
		buffer.writeu8(colors, i, string.byte(data, pos + i) or 0)
	end
	return colors, pos + count * 3
end

-- Decodes LZW image data into one palette index per pixel.
local function decodeLzw(stream: string, minCodeSize: number, pixelCount: number): buffer
	local out = buffer.create(pixelCount)
	local prefix = buffer.create(4096 * 2)
	local suffix = buffer.create(4096)
	local first = buffer.create(4096)
	local lengths = buffer.create(4096 * 2)

	local clearCode = lshift(1, minCodeSize)
	local endCode = clearCode + 1
	for code = 0, clearCode - 1 do
		buffer.writeu8(suffix, code, code)
		buffer.writeu8(first, code, code)
		buffer.writeu16(lengths, code * 2, 1)
	end

	local codeSize = minCodeSize + 1
	local codeMask = lshift(1, codeSize) - 1
	local nextCode = endCode + 1
	local previous = -1
	local bits, bitCount = 0, 0
	local streamPos, streamLength = 1, #stream
	local outPos = 0

	while outPos < pixelCount do
		while bitCount < codeSize do
			if streamPos > streamLength then
				return out
			end
			bits += lshift(string.byte(stream, streamPos), bitCount)
			streamPos += 1
			bitCount += 8
		end
		local code = band(bits, codeMask)
		bits = rshift(bits, codeSize)
		bitCount -= codeSize

		if code == clearCode then
			codeSize = minCodeSize + 1
			codeMask = lshift(1, codeSize) - 1
			nextCode = endCode + 1
			previous = -1
		elseif code == endCode then
			break
		else
			if previous ~= -1 then
				if code > nextCode then
					break
				end -- corrupt data
				if nextCode < 4096 then
					local firstByte = if code < nextCode
						then buffer.readu8(first, code)
						else buffer.readu8(first, previous)
					buffer.writeu16(prefix, nextCode * 2, previous)
					buffer.writeu8(suffix, nextCode, firstByte)
					buffer.writeu8(first, nextCode, buffer.readu8(first, previous))
					buffer.writeu16(lengths, nextCode * 2, buffer.readu16(lengths, previous * 2) + 1)
					nextCode += 1
					if nextCode > codeMask and codeSize < 12 then
						codeSize += 1
						codeMask = lshift(1, codeSize) - 1
					end
				elseif code >= nextCode then
					break
				end
			elseif code >= clearCode then
				break
			end

			-- Write the code's string back to front.
			local length = buffer.readu16(lengths, code * 2)
			local writePos = outPos + length - 1
			local current = code
			for _ = 1, length do
				if writePos < pixelCount then
					buffer.writeu8(out, writePos, buffer.readu8(suffix, current))
				end
				writePos -= 1
				current = buffer.readu16(prefix, current * 2)
			end
			outPos += length
			previous = code
		end
	end
	return out
end

-- Lists every frame's delay without decoding pixels.
local function scanDelays(data: string, pos: number): { number }
	local delays = {}
	local pendingDelay = nil
	while pos <= #data do
		local marker = string.byte(data, pos)
		if marker == 0x3B then
			break
		elseif marker == 0x21 then
			local label = string.byte(data, pos + 1)
			if label == 0xF9 then
				local centiseconds = (string.byte(data, pos + 4) or 0) + (string.byte(data, pos + 5) or 0) * 256
				pendingDelay = if centiseconds <= 1 then DEFAULT_DELAY_MS else centiseconds * 10
			end
			pos = skipSubBlocks(data, pos + 2)
		elseif marker == 0x2C then
			local packed = string.byte(data, pos + 9)
			pos += 10
			if band(packed, 0x80) ~= 0 then
				pos += 3 * lshift(1, band(packed, 7) + 1)
			end
			pos = skipSubBlocks(data, pos + 1)
			table.insert(delays, pendingDelay or DEFAULT_DELAY_MS)
			pendingDelay = nil
		else
			break
		end
	end
	return delays
end

function GifDecoder.decode(data: string, maxFrames: number, onFrame: (buffer, number) -> ()): (number, number, number)
	local signature = string.sub(data, 1, 6)
	if signature ~= "GIF87a" and signature ~= "GIF89a" then
		error("Not a GIF file")
	end

	local width = string.byte(data, 7) + string.byte(data, 8) * 256
	local height = string.byte(data, 9) + string.byte(data, 10) * 256
	if width == 0 or height == 0 or width * height > 4096 * 4096 then
		error("Unsupported GIF size")
	end
	local packed = string.byte(data, 11)
	local pos = 14
	local globalColors = nil
	if band(packed, 0x80) ~= 0 then
		globalColors, pos = readColorTable(data, pos, lshift(1, band(packed, 7) + 1))
	end

	-- Pick which frames to keep and how long each one shows.
	local delays = scanDelays(data, pos)
	local frameCount = #delays
	if frameCount == 0 then
		error("GIF has no frames")
	end
	local keep = {} -- frame index -> delay in ms for kept frames
	local kept = math.min(frameCount, maxFrames)
	local starts = {}
	for k = 0, kept - 1 do
		starts[k + 1] = math.floor(k * frameCount / kept) + 1
	end
	for k = 1, kept do
		local total = 0
		for index = starts[k], (starts[k + 1] or frameCount + 1) - 1 do
			total += delays[index]
		end
		keep[starts[k]] = total
	end

	local canvas = buffer.create(width * height * 4)
	local saved = buffer.create(width * height * 4)
	local frameIndex = 0
	local disposal, transparentIndex = 0, -1

	while pos <= #data do
		local marker = string.byte(data, pos)
		if marker == 0x3B then
			break
		elseif marker == 0x21 then
			local label = string.byte(data, pos + 1)
			if label == 0xF9 then
				local flags = string.byte(data, pos + 3)
				disposal = band(rshift(flags, 2), 7)
				transparentIndex = if band(flags, 1) ~= 0 then string.byte(data, pos + 6) else -1
			end
			pos = skipSubBlocks(data, pos + 2)
		elseif marker == 0x2C then
			frameIndex += 1
			local left = string.byte(data, pos + 1) + string.byte(data, pos + 2) * 256
			local top = string.byte(data, pos + 3) + string.byte(data, pos + 4) * 256
			local frameWidth = string.byte(data, pos + 5) + string.byte(data, pos + 6) * 256
			local frameHeight = string.byte(data, pos + 7) + string.byte(data, pos + 8) * 256
			local flags = string.byte(data, pos + 9)
			pos += 10
			local colors = globalColors
			if band(flags, 0x80) ~= 0 then
				colors, pos = readColorTable(data, pos, lshift(1, band(flags, 7) + 1))
			end
			local interlaced = band(flags, 0x40) ~= 0
			local minCodeSize = string.byte(data, pos)
			local stream
			stream, pos = readSubBlocks(data, pos + 1)

			if disposal == 3 then
				buffer.copy(saved, 0, canvas, 0)
			end

			if colors and frameWidth > 0 and frameHeight > 0 then
				local indices = decodeLzw(stream, minCodeSize, frameWidth * frameHeight)
				local rowOrder = {}
				if interlaced then
					for _, pass in ipairs({ { 0, 8 }, { 4, 8 }, { 2, 4 }, { 1, 2 } }) do
						for row = pass[1], frameHeight - 1, pass[2] do
							table.insert(rowOrder, row)
						end
					end
				end
				for sourceRow = 0, frameHeight - 1 do
					local y = top + (if interlaced then rowOrder[sourceRow + 1] else sourceRow)
					if y < height then
						local rowStart = sourceRow * frameWidth
						for x = 0, frameWidth - 1 do
							local canvasX = left + x
							if canvasX < width then
								local index = buffer.readu8(indices, rowStart + x)
								if index ~= transparentIndex then
									local offset = (y * width + canvasX) * 4
									buffer.writeu8(canvas, offset, buffer.readu8(colors, index * 3))
									buffer.writeu8(canvas, offset + 1, buffer.readu8(colors, index * 3 + 1))
									buffer.writeu8(canvas, offset + 2, buffer.readu8(colors, index * 3 + 2))
									buffer.writeu8(canvas, offset + 3, 255)
								end
							end
						end
					end
				end
			end

			if keep[frameIndex] then
				onFrame(canvas, keep[frameIndex])
			end

			if disposal == 2 then
				for y = top, math.min(top + frameHeight, height) - 1 do
					local rowOffset = (y * width + left) * 4
					local count = math.max(0, math.min(frameWidth, width - left)) * 4
					buffer.fill(canvas, rowOffset, 0, count)
				end
			elseif disposal == 3 then
				buffer.copy(canvas, 0, saved, 0)
			end
			disposal, transparentIndex = 0, -1
		else
			break
		end
	end

	return width, height, kept
end

return GifDecoder
