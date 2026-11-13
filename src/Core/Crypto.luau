--!strict
--[[
	Crypto

	The few primitives end-to-end encryption needs, in plain Luau (Roblox has
	no encryption API): SHA-256, HMAC-SHA256, ChaCha20 (RFC 8439), Base64 and
	hex. Strings are byte strings throughout. Checked against the standard test
	vectors in tests/Specs/Crypto.spec.luau.

	Usage:
		local Crypto = require(Core.Crypto)
		local mac = Crypto.hmac(key, message)
]]

local HttpService = game:GetService("HttpService")

local band, bor, bxor, bnot = bit32.band, bit32.bor, bit32.bxor, bit32.bnot
local rrotate, lrotate, rshift = bit32.rrotate, bit32.lrotate, bit32.rshift

local Crypto = {}

-- SHA-256 ------------------------------------------------------------------

local K = {
	0x428a2f98,
	0x71374491,
	0xb5c0fbcf,
	0xe9b5dba5,
	0x3956c25b,
	0x59f111f1,
	0x923f82a4,
	0xab1c5ed5,
	0xd807aa98,
	0x12835b01,
	0x243185be,
	0x550c7dc3,
	0x72be5d74,
	0x80deb1fe,
	0x9bdc06a7,
	0xc19bf174,
	0xe49b69c1,
	0xefbe4786,
	0x0fc19dc6,
	0x240ca1cc,
	0x2de92c6f,
	0x4a7484aa,
	0x5cb0a9dc,
	0x76f988da,
	0x983e5152,
	0xa831c66d,
	0xb00327c8,
	0xbf597fc7,
	0xc6e00bf3,
	0xd5a79147,
	0x06ca6351,
	0x14292967,
	0x27b70a85,
	0x2e1b2138,
	0x4d2c6dfc,
	0x53380d13,
	0x650a7354,
	0x766a0abb,
	0x81c2c92e,
	0x92722c85,
	0xa2bfe8a1,
	0xa81a664b,
	0xc24b8b70,
	0xc76c51a3,
	0xd192e819,
	0xd6990624,
	0xf40e3585,
	0x106aa070,
	0x19a4c116,
	0x1e376c08,
	0x2748774c,
	0x34b0bcb5,
	0x391c0cb3,
	0x4ed8aa4a,
	0x5b9cca4f,
	0x682e6ff3,
	0x748f82ee,
	0x78a5636f,
	0x84c87814,
	0x8cc70208,
	0x90befffa,
	0xa4506ceb,
	0xbef9a3f7,
	0xc67178f2,
}

local MOD = 4294967296 -- 2^32

--[=[
	The SHA-256 digest of `message`: 32 bytes.
]=]
function Crypto.sha256(message: string): string
	local length = #message
	message ..= "\128" .. string.rep("\0", (55 - length) % 64) .. string.pack(
		">I4I4",
		length // 0x20000000,
		(length * 8) % MOD
	)

	local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
	local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
	local w = table.create(64, 0)
	for chunk = 1, #message, 64 do
		for i = 1, 16 do
			w[i] = string.unpack(">I4", message, chunk + (i - 1) * 4)
		end
		for i = 17, 64 do
			local a, b = w[i - 15], w[i - 2]
			local s0 = bxor(rrotate(a, 7), rrotate(a, 18), rshift(a, 3))
			local s1 = bxor(rrotate(b, 17), rrotate(b, 19), rshift(b, 10))
			w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % MOD
		end
		local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
		for i = 1, 64 do
			local s1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
			local ch = bxor(band(e, f), band(bnot(e), g))
			local t1 = h + s1 + ch + K[i] + w[i]
			local s0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
			local maj = bxor(band(a, b), band(a, c), band(b, c))
			h, g, f, e = g, f, e, (d + t1) % MOD
			d, c, b, a = c, b, a, (t1 + s0 + maj) % MOD
		end
		h0, h1, h2, h3 = (h0 + a) % MOD, (h1 + b) % MOD, (h2 + c) % MOD, (h3 + d) % MOD
		h4, h5, h6, h7 = (h4 + e) % MOD, (h5 + f) % MOD, (h6 + g) % MOD, (h7 + h) % MOD
	end
	return string.pack(">I4I4I4I4I4I4I4I4", h0, h1, h2, h3, h4, h5, h6, h7)
end

local function xorEach(text: string, byte: number): string
	return (string.gsub(text, ".", function(char)
		return string.char(bxor(string.byte(char), byte))
	end))
end

--[=[
	HMAC-SHA256 of `message` under `key`: 32 bytes.
]=]
function Crypto.hmac(key: string, message: string): string
	if #key > 64 then
		key = Crypto.sha256(key)
	end
	key ..= string.rep("\0", 64 - #key)
	return Crypto.sha256(xorEach(key, 0x5c) .. Crypto.sha256(xorEach(key, 0x36) .. message))
end

-- ChaCha20 -----------------------------------------------------------------

local function quarter(s: { number }, a: number, b: number, c: number, d: number)
	s[a] = (s[a] + s[b]) % MOD
	s[d] = lrotate(bxor(s[d], s[a]), 16)
	s[c] = (s[c] + s[d]) % MOD
	s[b] = lrotate(bxor(s[b], s[c]), 12)
	s[a] = (s[a] + s[b]) % MOD
	s[d] = lrotate(bxor(s[d], s[a]), 8)
	s[c] = (s[c] + s[d]) % MOD
	s[b] = lrotate(bxor(s[b], s[c]), 7)
end

--[=[
	Encrypts or decrypts (the same thing) `text` with ChaCha20: a 32-byte key,
	a 12-byte nonce, and the first block's counter.
]=]
function Crypto.chacha20(key: string, nonce: string, counter: number, text: string): string
	assert(#key == 32 and #nonce == 12, "ChaCha20 needs a 32-byte key and a 12-byte nonce")
	local input = { 0x61707865, 0x3320646e, 0x79622d32, 0x6b206574 }
	for i = 0, 7 do
		input[5 + i] = string.unpack("<I4", key, 1 + i * 4)
	end
	input[13] = counter
	for i = 0, 2 do
		input[14 + i] = string.unpack("<I4", nonce, 1 + i * 4)
	end

	local out = table.create(math.ceil(#text / 64))
	local state = table.create(16, 0)
	for offset = 1, #text, 64 do
		table.move(input, 1, 16, 1, state)
		for _ = 1, 10 do
			quarter(state, 1, 5, 9, 13)
			quarter(state, 2, 6, 10, 14)
			quarter(state, 3, 7, 11, 15)
			quarter(state, 4, 8, 12, 16)
			quarter(state, 1, 6, 11, 16)
			quarter(state, 2, 7, 12, 13)
			quarter(state, 3, 8, 9, 14)
			quarter(state, 4, 5, 10, 15)
		end
		local block = string.sub(text, offset, offset + 63)
		local words = math.ceil(#block / 4)
		local padded = block .. string.rep("\0", words * 4 - #block)
		local mixed = table.create(words)
		for i = 1, words do
			local keystream = (state[i] + input[i]) % MOD
			mixed[i] = string.pack("<I4", bxor(string.unpack("<I4", padded, i * 4 - 3), keystream))
		end
		table.insert(out, string.sub(table.concat(mixed), 1, #block))
		input[13] = (input[13] + 1) % MOD
	end
	return table.concat(out)
end

-- Encodings ----------------------------------------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CHARS: { [number]: string } = {}
local VALUES: { [number]: number } = {}
for i = 1, 64 do
	CHARS[i - 1] = string.sub(ALPHABET, i, i)
	VALUES[string.byte(ALPHABET, i)] = i - 1
end

function Crypto.base64(bytes: string): string
	local out = table.create(math.ceil(#bytes / 3))
	for i = 1, #bytes, 3 do
		local a, b, c = string.byte(bytes, i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		out[#out + 1] = CHARS[n // 262144]
			.. CHARS[(n // 4096) % 64]
			.. (if b then CHARS[(n // 64) % 64] else "=")
			.. (if c then CHARS[n % 64] else "=")
	end
	return table.concat(out)
end

--[=[
	The bytes of standard, padded Base64, or nil when it isn't.
]=]
function Crypto.fromBase64(text: string): string?
	if #text % 4 ~= 0 or string.find(text, "[^%w%+/=]") or string.find(text, "=[^=]") then
		return nil
	end
	local out = table.create(#text // 4)
	for i = 1, #text, 4 do
		local a, b, c, d = string.byte(text, i, i + 3)
		if a == 61 or b == 61 or (c == 61 and d ~= 61) or (i + 3 < #text and d == 61) then
			return nil
		end
		local n = VALUES[a] * 262144 + VALUES[b] * 4096 + (VALUES[c] or 0) * 64 + (VALUES[d] or 0)
		local bytes = string.char(n // 65536, (n // 256) % 256, n % 256)
		out[#out + 1] = string.sub(bytes, 1, if c == 61 then 1 elseif d == 61 then 2 else 3)
	end
	return table.concat(out)
end

function Crypto.hex(bytes: string): string
	return (string.gsub(bytes, ".", function(char)
		return string.format("%02x", string.byte(char))
	end))
end

--[=[
	True when two byte strings are equal, taking the same time wherever they differ.
]=]
function Crypto.equal(a: string, b: string): boolean
	if #a ~= #b then
		return false
	end
	local difference = 0
	for i = 1, #a do
		difference = bor(difference, bxor(string.byte(a, i), string.byte(b, i)))
	end
	return difference == 0
end

--[=[
	`count` unpredictable bytes. Built from GUIDs (Roblox has no other source
	of secure randomness), hashed so their fixed version bits don't show.
]=]
function Crypto.randomBytes(count: number): string
	local out = ""
	while #out < count do
		out ..= Crypto.sha256(
			HttpService:GenerateGUID(false) .. HttpService:GenerateGUID(false) .. tostring(os.clock())
		)
	end
	return string.sub(out, 1, count)
end

return Crypto
