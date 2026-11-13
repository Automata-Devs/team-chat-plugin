--[[
	End-to-end encryption: Core.Crypto against the standard test vectors
	(SHA-256, HMAC-SHA256 from RFC 4231, ChaCha20 from RFC 8439), and
	Services/Backend/Seal sealing, opening, refusing changed or foreign text,
	and opening what backend/test/sealing.ts (the TypeScript twin) sealed.
]]

local SECRET = string.rep("0123456789abcdef", 4)
-- Sealed by backend/test/sealing.ts with SECRET
local FROM_TYPESCRIPT = "e2e1:WpkD3TUuQZNqN2dy6Ejao6/pNSUe7wgBmIhBTOWc605xW4eJU0dNalmb6DG5UZIbEgZfC1D/QGeg"

return function(t)
	-- Pure functions: a fresh copy of the plugin's modules is enough, no app
	local copy = game:GetService("ReplicatedStorage").TeamChatPlugin:Clone()
	local ok, err = pcall(function()
		local Crypto = require(copy.Core.Crypto) :: any
		local Seal = require(copy.Services.Backend.Seal) :: any
		local hex = Crypto.hex

		t.equal(
			"sha256 of nothing",
			hex(Crypto.sha256("")),
			"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
		)
		t.equal(
			"sha256 of abc",
			hex(Crypto.sha256("abc")),
			"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
		)
		t.equal(
			"sha256 across two blocks",
			hex(Crypto.sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")),
			"248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
		)
		t.equal(
			"sha256 of a million a's",
			hex(Crypto.sha256(string.rep("a", 1000000))),
			"cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
		)
		t.equal(
			"HMAC-SHA256 (RFC 4231 case 2)",
			hex(Crypto.hmac("Jefe", "what do ya want for nothing?")),
			"5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
		)
		t.equal(
			"HMAC-SHA256 with a key longer than a block (RFC 4231 case 6)",
			hex(Crypto.hmac(string.rep("\170", 131), "Test Using Larger Than Block-Size Key - Hash Key First")),
			"60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"
		)

		local key = ""
		for i = 0, 31 do
			key ..= string.char(i)
		end
		local nonce = "\0\0\0\0\0\0\0\74\0\0\0\0"
		local sunscreen =
			"Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
		local encrypted = Crypto.chacha20(key, nonce, 1, sunscreen)
		t.equal(
			"ChaCha20 (RFC 8439 2.4.2)",
			hex(encrypted),
			"6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0bf91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d807ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab77937365af90bbf74a35be6b40b8eedf2785e42874d"
		)
		t.equal("...and back", Crypto.chacha20(key, nonce, 1, encrypted), sunscreen)

		for _, sample in ipairs({ "", "f", "fo", "foo", "foob", "fooba", "foobar", "\0\255\128é🐉" }) do
			-- t.check, not t.equal: raw bytes in a result line break the Studio MCP's reply
			t.check("Base64 round trip of " .. #sample .. " bytes", Crypto.fromBase64(Crypto.base64(sample)) == sample)
		end
		t.equal("Base64 of foobar", Crypto.base64("foobar"), "Zm9vYmFy")
		t.equal("Base64 of fo", Crypto.base64("fo"), "Zm8=")
		t.check("not Base64", Crypto.fromBase64("Zm9v!mFy") == nil and Crypto.fromBase64("Zm=v") == nil)
		t.check(
			"random bytes differ",
			Crypto.randomBytes(16) ~= Crypto.randomBytes(16) and #Crypto.randomBytes(40) == 40
		)

		-- Sealing
		Seal.forget()
		t.check("no key before joining", not Seal.ready() and Seal.open(FROM_TYPESCRIPT) == nil)
		Seal.use(SECRET)
		t.equal(
			"the proof is sha256 of the secret, like the backend expects",
			Seal.proof(SECRET),
			"a8ae6e6ee929abea3afcfc5258c8ccd6f85273e0d4626d26c7279f3250f77c8e"
		)
		t.equal("opens what TypeScript sealed", Seal.open(FROM_TYPESCRIPT), 'Hello from Node 🐉 "quoted"')
		local text = "Meet at the spawn — bring the 🗝️ " .. string.rep("long ", 300)
		local sealed = Seal.seal(text)
		t.check("sealed text starts with e2e1:", string.sub(sealed, 1, 5) == "e2e1:" and Seal.isSealed(sealed))
		t.check("...hides the text", string.find(sealed, "spawn", 1, true) == nil)
		t.equal("...opens again", Seal.open(sealed), text)
		t.check("sealing twice gives different results", Seal.seal("same") ~= Seal.seal("same"))
		local flipped = string.sub(sealed, 1, 20)
			.. (if string.sub(sealed, 21, 21) == "A" then "B" else "A")
			.. string.sub(sealed, 22)
		t.check("a changed character is noticed", Seal.open(flipped) == nil)
		t.check("readable text isn't opened", Seal.open("hello") == nil)
		Seal.use(string.rep("another place ", 5))
		t.check("another place's key can't open it", Seal.open(sealed) == nil)
		Seal.forget()
	end)
	copy:Destroy()
	if not ok then
		error(err, 0)
	end
end
