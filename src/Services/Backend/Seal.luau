--!strict
--[[
	Seal

	End-to-end encryption for everything stored on the backend: messages are
	sealed here, before they leave Studio, with a key only people who can open
	the place have. The server and its database only ever hold sealed text.

	The key comes from the place's secret (Connection), which lives in the
	place. The server never gets the secret either: joining sends a proof of it
	(sha256), which can't be turned back into the secret or the key.

	  master   = HMAC-SHA256(key = secret, "Team Chat end-to-end key v1")
	  enc, mac, nonce keys = HMAC-SHA256(master, "enc" | "mac" | "nonce")
	  sealed   = "e2e1:" .. Base64(nonce[12] .. ChaCha20(enc, nonce, 1, text) .. tag[16])
	  tag      = first 16 bytes of HMAC-SHA256(mac, "e2e1" .. nonce .. ciphertext)

	The nonce mixes fresh random bytes with the text (so it never repeats
	under one key), and the tag makes any change to sealed text detectable.
	docs/backend/MESSAGES.md has the format; backend/test/sealing.ts is the
	same thing in TypeScript.
]]

local Crypto = require(script.Parent.Parent.Parent.Core.Crypto)

local Seal = {}

local PREFIX = "e2e1:"
local KEY_LABEL = "Team Chat end-to-end key v1"

type Keys = { enc: string, mac: string, nonce: string }

local keys: Keys? = nil
local keysFor: string? = nil

local function derive(secret: string): Keys
	local master = Crypto.hmac(secret, KEY_LABEL)
	return {
		enc = Crypto.hmac(master, "enc"),
		mac = Crypto.hmac(master, "mac"),
		nonce = Crypto.hmac(master, "nonce"),
	}
end

--[=[
	What's sent to the backend to join the place, instead of its secret.
]=]
function Seal.proof(secret: string): string
	return Crypto.hex(Crypto.sha256(secret))
end

--[=[
	Seals with the key of this place's secret from now on (the one that got me
	into its workspace).
]=]
function Seal.use(secret: string)
	if keysFor ~= secret then
		keys = derive(secret)
		keysFor = secret
	end
end

function Seal.forget()
	keys = nil
	keysFor = nil
end

function Seal.ready(): boolean
	return keys ~= nil
end

function Seal.isSealed(value: any): boolean
	return type(value) == "string" and string.sub(value, 1, #PREFIX) == PREFIX
end

--[=[
	`text`, sealed. Errors without a key (Seal.use first).
]=]
function Seal.seal(text: string): string
	local current = assert(keys, "No key: join the place's workspace first")
	local nonce = string.sub(Crypto.hmac(current.nonce, Crypto.randomBytes(16) .. text), 1, 12)
	local body = Crypto.chacha20(current.enc, nonce, 1, text)
	local tag = string.sub(Crypto.hmac(current.mac, "e2e1" .. nonce .. body), 1, 16)
	return PREFIX .. Crypto.base64(nonce .. body .. tag)
end

--[=[
	The text in a sealed value, or nil when it isn't sealed with this place's
	key, or was changed.
]=]
function Seal.open(value: any): string?
	local current = keys
	if not current or not Seal.isSealed(value) then
		return nil
	end
	local bytes = Crypto.fromBase64(string.sub(value, #PREFIX + 1))
	if not bytes or #bytes < 28 then
		return nil
	end
	local nonce = string.sub(bytes, 1, 12)
	local body = string.sub(bytes, 13, -17)
	local tag = string.sub(bytes, -16)
	if not Crypto.equal(tag, string.sub(Crypto.hmac(current.mac, "e2e1" .. nonce .. body), 1, 16)) then
		return nil
	end
	return Crypto.chacha20(current.enc, nonce, 1, body)
end

return Seal
