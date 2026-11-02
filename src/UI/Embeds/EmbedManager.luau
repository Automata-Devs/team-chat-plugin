--!nonstrict
--!
-- EmbedManager
-- Single entry point for all chat embeds. ChatUI only talks to this module.
--
--   EmbedManager.attach(messageContainer, urls, theme, ctx)  -- on new message
--   EmbedManager.recolor(messageContainer, theme)            -- on theme change
--   EmbedManager.register(provider)                          -- optional manual add
--
-- Providers are ModuleScripts in UI/Embeds/Providers and are discovered
-- automatically (see EmbedTypes for the provider shape). The highest
-- priority provider whose matches() returns true renders the URL.
-- A provider that errors is skipped, so one broken embed can never stop a
-- chat message from rendering.
--!

local Types = require(script.Parent.EmbedTypes)
local Style = require(script.Parent.EmbedStyle)
local CardFrame = require(script.Parent.CardFrame)
local Logger = require(script.Parent.Parent.Parent.Core.Logger)

local log = Logger.scope("Embeds")

type EmbedProvider = Types.EmbedProvider
type ThemeColors = Types.ThemeColors
type EmbedContext = Types.EmbedContext

local EmbedManager = {}

local providers: { EmbedProvider } = {}
local providersByName: { [string]: EmbedProvider } = {}

local function sortProviders()
	table.sort(providers, function(a, b)
		local pa, pb = a.Priority or 0, b.Priority or 0
		if pa ~= pb then
			return pa > pb
		end
		return a.Name < b.Name
	end)
end

--!
-- Registers a provider. Registering a name that already exists replaces it.
--!
function EmbedManager.register(provider: EmbedProvider)
	assert(type(provider) == "table", "EmbedManager.register: provider must be a table")
	assert(type(provider.Name) == "string", "EmbedManager.register: provider.Name must be a string")
	assert(type(provider.matches) == "function", provider.Name .. ": missing matches()")
	assert(type(provider.build) == "function", provider.Name .. ": missing build()")
	assert(type(provider.recolor) == "function", provider.Name .. ": missing recolor()")

	local existing = providersByName[provider.Name]
	if existing then
		table.remove(providers, table.find(providers, existing))
	end
	providersByName[provider.Name] = provider
	table.insert(providers, provider)
	sortProviders()
end

local function loadProviders()
	local folder = script.Parent:FindFirstChild("Providers")
	if not folder then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			local ok, result = pcall(require, child)
			if ok then
				local registered, err = pcall(EmbedManager.register, result)
				if not registered then
					log.warn("Embed provider '" .. child.Name .. "' is invalid: " .. tostring(err))
				end
			else
				log.warn("Embed provider '" .. child.Name .. "' failed to load: " .. tostring(result))
			end
		end
	end
end

--!
-- Builds an embed for a single URL using the best matching provider.
-- @return the embed root GuiObject, or nil if no provider could build it
--!
function EmbedManager.createEmbed(url: string, theme: ThemeColors, ctx: EmbedContext?): GuiObject?
	for _, provider in ipairs(providers) do
		local okMatch, matched = pcall(provider.matches, url)
		if okMatch and matched then
			local okBuild, embed = pcall(provider.build, url, theme, ctx or {})
			if okBuild and embed then
				embed.Name = "Embed"
				embed:SetAttribute("EmbedProvider", provider.Name)
				embed:SetAttribute("EmbedUrl", url)
				return embed
			end
			log.warn("Embed provider '" .. provider.Name .. "' failed for " .. url .. ": " .. tostring(embed))
		end
	end
	return nil
end

--!
-- Adds embeds for the URLs found in a message (up to MAX_EMBEDS_PER_MESSAGE,
-- duplicates ignored) and keeps any image attachment below them.
-- @return number of embeds added
--!
function EmbedManager.attach(messageContainer: Frame, urls: { string }, theme: ThemeColors, ctx: EmbedContext?): number
	local seen = {}
	local count = 0

	for _, url in ipairs(urls) do
		if count >= Style.MAX_EMBEDS_PER_MESSAGE then
			break
		end
		if not seen[url] then
			seen[url] = true
			local embed = EmbedManager.createEmbed(url, theme, ctx)
			if embed then
				embed.LayoutOrder = Style.FIRST_EMBED_LAYOUT_ORDER + count
				embed.Parent = messageContainer
				count += 1
			end
		end
	end

	if count > 0 then
		local imageAttachment = messageContainer:FindFirstChild("ImageAttachment")
		if imageAttachment then
			imageAttachment.LayoutOrder = Style.FIRST_EMBED_LAYOUT_ORDER + count
		end
	end

	return count
end

--!
-- Re-applies theme colors to every embed in a message container.
--!
function EmbedManager.recolor(messageContainer: Instance, theme: ThemeColors)
	for _, child in ipairs(messageContainer:GetChildren()) do
		local providerName = child:GetAttribute("EmbedProvider")
		if providerName then
			CardFrame.recolor(child, theme)
			local provider = providersByName[providerName]
			if provider then
				local ok, err = pcall(provider.recolor, child, theme)
				if not ok then
					log.warn("Embed recolor failed (" .. providerName .. "): " .. tostring(err))
				end
			end
		end
	end
end

loadProviders()

return EmbedManager
