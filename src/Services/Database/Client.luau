--!strict
--[[
	Client

	Sends one request to the database server: JSON in and out, the place's
	token in a header, and every failure turned into a problem the caller can
	show. Remembers whether the server answered last time (`online`).

	Problems: "notConnected", "unreachable" (no answer: offline, blocked, or
	HTTP not allowed), or "<status> <message>" from the server.
	`retry` is true when the same request may work later.
]]

local HttpService = game:GetService("HttpService")

local DatabaseConfig = require(script.Parent.Parent.Parent.Config.Database)
local Signal = require(script.Parent.Parent.Parent.Util.Signal)
local Connection = require(script.Parent.Connection)

export type Request = { Url: string, Method: string, Headers: { [string]: string }, Body: string? }
export type Response = { Success: boolean, StatusCode: number, StatusMessage: string, Body: string }
export type Result = { data: any, problem: string?, retry: boolean }

local Client = {}

Client.online = nil :: boolean? -- nil until the first request
Client.statusChanged = Signal.new()

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

local function setOnline(online: boolean)
	if Client.online ~= online then
		Client.online = online
		Client.statusChanged:Fire(online)
	end
end

local function decode(body: string?): any
	if type(body) ~= "string" or body == "" then
		return nil
	end
	local ok, value = pcall(HttpService.JSONDecode, HttpService, body)
	return if ok then value else nil
end

--[=[
	Sends `method path` (path after /v1, e.g. "/kv/notes/a") with an optional
	JSON body. Yields.
]=]
function Client.request(method: string, path: string, body: any?): Result
	local info = Connection.get()
	if not info then
		return { data = nil, problem = "notConnected", retry = false }
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
		Url = info.url .. DatabaseConfig.API_PREFIX .. path,
		Method = method,
		Headers = {
			["Content-Type"] = "application/json",
			[DatabaseConfig.TOKEN_HEADER] = info.token,
		},
		Body = encoded,
	})
	if not ok or type(response) ~= "table" then
		setOnline(false)
		return { data = nil, problem = "unreachable", retry = true }
	end
	setOnline(true)
	if not response.Success then
		local status = response.StatusCode
		local answer = decode(response.Body)
		local message = if type(answer) == "table" and type(answer.error) == "string"
			then answer.error
			else response.StatusMessage
		return {
			data = nil,
			problem = string.format("%d %s", status, tostring(message)),
			retry = status == 429 or status >= 500,
		}
	end
	return { data = decode(response.Body), problem = nil, retry = false }
end

--[=[
	Encodes one part of a path (a key or a collection name).
]=]
function Client.escape(part: string): string
	return HttpService:UrlEncode(part)
end

return Client
