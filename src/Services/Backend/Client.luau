--!strict
--[[
	Client

	One request to the backend: JSON in and out, my session token, and every
	failure turned into a problem the caller can show. Remembers whether the
	server answered last time (`online`).

	Problems: "notConnected", "signedOut" (no or an expired sign-in),
	"unreachable" (no answer: offline, blocked, or HTTP not allowed), or
	"<status> <message>" from the server. `retry` is true when the same request
	may work later.
]]

local HttpService = game:GetService("HttpService")

local BackendConfig = require(script.Parent.Parent.Parent.Config.Backend)
local Connection = require(script.Parent.Connection)
local Session = require(script.Parent.Session)

export type Request = { Url: string, Method: string, Headers: { [string]: string }, Body: string? }
export type Response = { Success: boolean, StatusCode: number, StatusMessage: string, Body: string }
export type Result = { data: any, problem: string?, retry: boolean, status: number? }

local Client = {}

Client.online = nil :: boolean? -- nil until the first request

local function defaultTransport(request: Request): Response
	return HttpService:RequestAsync(request :: any) :: any
end

local transport: (Request) -> Response = defaultTransport

--[=[
	Replaces HttpService:RequestAsync (the specs use a fake server). nil puts it back.
]=]
function Client.setTransport(fn: ((Request) -> Response)?)
	transport = fn or defaultTransport
end

local function decode(body: string?): any
	if type(body) ~= "string" or body == "" then
		return nil
	end
	local ok, value = pcall(HttpService.JSONDecode, HttpService, body)
	return if ok then value else nil
end

--[=[
	Sends `method path` (after /api/v1) with an optional JSON body. `public`
	requests (signing in) go without a token. Yields.
]=]
function Client.request(method: string, path: string, body: any?, public: boolean?): Result
	local info = Connection.get()
	if not info then
		return { data = nil, problem = "notConnected", retry = false }
	end
	local headers = { ["Content-Type"] = "application/json" }
	local session = Session.get(info.url)
	if session then
		headers.Authorization = "Bearer " .. session.token
	elseif not public then
		return { data = nil, problem = "signedOut", retry = false }
	end
	local encoded: string? = nil
	if body ~= nil then
		local ok, json = pcall(HttpService.JSONEncode, HttpService, body)
		if not ok then
			return { data = nil, problem = "badValue", retry = false }
		end
		encoded = json
	end
	local ok, response = pcall(transport, {
		Url = info.url .. BackendConfig.API_PREFIX .. path,
		Method = method,
		Headers = headers,
		Body = encoded,
	})
	if not ok or type(response) ~= "table" then
		Client.online = false
		return { data = nil, problem = "unreachable", retry = true }
	end
	Client.online = true
	local status = response.StatusCode
	local data = decode(response.Body)
	if not response.Success then
		if status == 401 and not public then
			Session.clear(info.url) -- expired or signed out elsewhere: sign in again
			return { data = nil, problem = "signedOut", retry = false, status = status }
		end
		local message = if type(data) == "table"
				and type(data.error) == "table"
				and type(data.error.message) == "string"
			then data.error.message
			else response.StatusMessage
		return {
			data = data,
			problem = string.format("%d %s", status, tostring(message)),
			retry = status == 429 or status >= 500,
			status = status,
		}
	end
	return { data = data, problem = nil, retry = false, status = status }
end

--[=[
	Encodes one part of a path (an emoji, an invite code).
]=]
function Client.escape(part: string): string
	return HttpService:UrlEncode(part)
end

return Client
