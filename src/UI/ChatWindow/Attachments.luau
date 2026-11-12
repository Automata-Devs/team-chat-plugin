--[[
	Attachments

	The composer's attachment: the preview bar above the message box, the
	file picker, image and GIF uploads, and dragging an image or file card
	from the chat back onto the panel. The composer holds one attachment at
	a time.

	Images are uploaded as Roblox assets so they sync over Team Create.
	Plugins can't upload other file types (AssetService:CreateAssetAsync only
	takes Roblox objects), so those keep their temporary id: they work on
	this computer only, and collaborators see the card but can't open it.

	Usage:
		local attachments = Attachments.create(ctx)
		attachments.pick()                       -- the file picker
		local url = attachments.getPendingImage()
]]

local AssetService = game:GetService("AssetService")
local StudioService = game:GetService("StudioService")

local GifPlayer = require(script.Parent.Parent.Components.GifPlayer)
local Icons = require(script.Parent.Parent.Parent.Config.Icons)
local Logger = require(script.Parent.Parent.Parent.Core.Logger)
local Theme = require(script.Parent.Parent.Parent.Config.Theme)

local log = Logger.scope("Chat")

local FONT = Theme.FONT
local FONTS = Theme.FONTS
local IMAGE_FILTER = Theme.IMAGE_FILTER
local FILE_EXTENSIONS = Theme.FILE_EXTENSIONS
local INPUT_HEIGHT = Theme.INPUT_HEIGHT
local PREVIEW_HEIGHT = Theme.PREVIEW_HEIGHT

local Attachments = {}

-- Drag data for images and file cards dragged out of the chat: "name|url|type"
Attachments.MIME_TYPE = "application/x-teamchat-attachment"

local ATTACH_FILE_FILTER = table.clone(IMAGE_FILTER)
for extension in pairs(FILE_EXTENSIONS) do
	if not table.find(ATTACH_FILE_FILTER, extension) then
		table.insert(ATTACH_FILE_FILTER, extension)
	end
end

local function extensionOf(fileName: string): string
	return string.lower(string.match(fileName, "%.([^.]+)$") or "")
end

function Attachments.create(ctx)
	local container: Frame = ctx.container
	local widget = ctx.widget

	local previewBar = Instance.new("Frame")
	previewBar.Name = "PreviewBar"
	previewBar.Size = UDim2.new(1, 0, 0, PREVIEW_HEIGHT)
	previewBar.Position = UDim2.new(0, 0, 1, -(INPUT_HEIGHT + PREVIEW_HEIGHT))
	previewBar.BackgroundColor3 = ctx.palette.inputFrame
	previewBar.BorderSizePixel = 0
	previewBar.Visible = false
	previewBar.ZIndex = 5
	previewBar.Parent = container

	local previewPadding = Instance.new("UIPadding")
	previewPadding.PaddingLeft = UDim.new(0, 8)
	previewPadding.PaddingRight = UDim.new(0, 8)
	previewPadding.PaddingTop = UDim.new(0, 4)
	previewPadding.PaddingBottom = UDim.new(0, 4)
	previewPadding.Parent = previewBar

	local previewThumbnail = Instance.new("ImageLabel")
	previewThumbnail.Name = "Thumbnail"
	previewThumbnail.Size = UDim2.new(0, 28, 0, 28)
	previewThumbnail.Position = UDim2.new(0, 0, 0.5, -14)
	previewThumbnail.BackgroundColor3 = ctx.palette.scrollBack
	previewThumbnail.BorderColor3 = ctx.palette.previewBorder
	previewThumbnail.BorderSizePixel = 1
	previewThumbnail.ScaleType = Enum.ScaleType.Fit
	previewThumbnail.ZIndex = 6
	previewThumbnail.Parent = previewBar

	local previewThumbCorner = Instance.new("UICorner")
	previewThumbCorner.CornerRadius = UDim.new(0, 4)
	previewThumbCorner.Parent = previewThumbnail

	local previewLabel = Instance.new("TextLabel")
	previewLabel.Name = "Label"
	previewLabel.Size = UDim2.new(1, -70, 1, 0)
	previewLabel.Position = UDim2.new(0, 36, 0, 0)
	previewLabel.BackgroundTransparency = 1
	previewLabel.RichText = true -- file previews embed an inline attachment icon
	previewLabel.Text = "Image attached"
	previewLabel.TextColor3 = ctx.palette.messageText
	previewLabel.Font = FONT
	previewLabel.TextSize = 12
	previewLabel.TextXAlignment = Enum.TextXAlignment.Left
	previewLabel.ZIndex = 6
	previewLabel.BorderSizePixel = 0
	previewLabel.Parent = previewBar

	local previewRemove = Instance.new("TextButton")
	previewRemove.Name = "Remove"
	previewRemove.Size = UDim2.new(0, 24, 0, 24)
	previewRemove.Position = UDim2.new(1, -24, 0.5, -12)
	previewRemove.BackgroundColor3 = ctx.palette.attachButton
	Icons.apply(previewRemove, "close")
	previewRemove.TextColor3 = ctx.palette.attachIcon
	previewRemove.TextSize = 14
	previewRemove.AutoButtonColor = true
	previewRemove.ZIndex = 6
	previewRemove.BorderSizePixel = 0
	previewRemove.Parent = previewBar

	local previewRemoveCorner = Instance.new("UICorner")
	previewRemoveCorner.CornerRadius = UDim.new(0, 4)
	previewRemoveCorner.Parent = previewRemove

	local dropOverlay = Instance.new("Frame")
	dropOverlay.Name = "DropOverlay"
	dropOverlay.Size = UDim2.new(1, 0, 1, 0)
	dropOverlay.BackgroundColor3 = ctx.palette.sendButton
	dropOverlay.BackgroundTransparency = 0.85
	dropOverlay.BorderSizePixel = 0
	dropOverlay.Visible = false
	dropOverlay.ZIndex = 30
	dropOverlay.Parent = container

	local dropOverlayCorner = Instance.new("UICorner")
	dropOverlayCorner.CornerRadius = UDim.new(0, 16)
	dropOverlayCorner.Parent = dropOverlay

	local dropOverlayStroke = Instance.new("UIStroke")
	dropOverlayStroke.Color = ctx.palette.sendButton
	dropOverlayStroke.Thickness = 3
	dropOverlayStroke.Transparency = 0.4
	dropOverlayStroke.Parent = dropOverlay

	local dropLabel = Instance.new("TextLabel")
	dropLabel.Name = "DropLabel"
	dropLabel.Size = UDim2.new(1, -20, 0, 40)
	dropLabel.Position = UDim2.new(0, 0, 0.5, -20)
	dropLabel.BackgroundTransparency = 1
	dropLabel.RichText = true
	dropLabel.Text = Icons.inline("dropFile", false, 20) .. "  Drop to attach"
	dropLabel.TextColor3 = ctx.palette.sendButtonText
	dropLabel.FontFace = FONTS.display
	dropLabel.TextSize = 16
	dropLabel.ZIndex = 31
	dropLabel.BorderSizePixel = 0
	dropLabel.Parent = dropOverlay

	local pendingImage: string? = nil
	local pendingFile: { fileName: string, fileUrl: string, fileType: string }? = nil
	local isUploading = false

	local function showPreview(imageUrl: string, labelText: string?)
		pendingImage = imageUrl
		pendingFile = nil
		GifPlayer.apply(previewThumbnail, imageUrl)
		previewThumbnail.Visible = true
		previewLabel.Text = Icons.escape(labelText or "Image attached")
		previewBar.Visible = true
	end

	-- A file card in the bar (no thumbnail)
	local function showFileLabel(text: string)
		previewThumbnail.Image = ""
		previewThumbnail.Visible = false
		previewLabel.Text = Icons.inline("attachFile", false, 14) .. text
		previewBar.Visible = true
	end

	local function hidePreview()
		pendingImage = nil
		pendingFile = nil
		isUploading = false
		previewThumbnail.Image = ""
		previewThumbnail.Visible = true
		previewBar.Visible = false
	end

	-- Uploads an image as an asset; falls back to its temporary id (local only)
	local function uploadImageFile(file)
		local tempId = file:GetTemporaryId()

		showPreview(tempId, "Uploading image...")
		isUploading = true

		task.spawn(function()
			local permanentUrl = nil

			local ok1, editableImage = pcall(function()
				return AssetService:CreateEditableImageAsync(Content.fromUri(tempId))
			end)

			if ok1 and editableImage then
				local ok2, result, assetId = pcall(function()
					return AssetService:CreateAssetAsync(editableImage, Enum.AssetType.Image, {
						Name = "TeamChat Image",
						Description = "Image shared via Team Chat plugin",
					})
				end)

				if ok2 and result == Enum.CreateAssetResult.Success and assetId then
					permanentUrl = "rbxassetid://" .. tostring(assetId)
				end
			end

			isUploading = false

			if permanentUrl then
				showPreview(permanentUrl, "Image attached")
			else
				showPreview(tempId, "Image attached (local only)")
				log.warn("Could not upload image as permanent asset. Using temporary ID (local only).")
			end
		end)
	end

	-- Any other file keeps its temporary id
	local function uploadFile(file)
		local fileName = file.Name
		local fileType = FILE_EXTENSIONS[extensionOf(fileName)] or "Other"

		pendingImage = nil
		pendingFile = nil
		showFileLabel(" Uploading " .. Icons.escape(fileName) .. "...")
		ctx.relayout()

		isUploading = true

		task.spawn(function()
			isUploading = false

			local tempId = file:GetTemporaryId()
			if tempId and tempId ~= "" then
				pendingFile = {
					fileName = fileName,
					fileUrl = tempId,
					fileType = fileType,
				}
				previewLabel.Text = Icons.inline("attachFile", false, 14)
					.. " "
					.. Icons.escape(fileName)
					.. " (local only)"
				log.warn(
					""
						.. fileName
						.. " is shared as a local-only file: plugins can't upload "
						.. fileType
						.. " files as Roblox assets, so collaborators won't be able to open it."
				)
			else
				hidePreview()
				log.warn("Could not attach file: " .. fileName)
			end
		end)
	end

	-- A GIF is decoded into an animated sprite sheet (GifPlayer)
	local function attachGif(file)
		pendingImage = nil
		pendingFile = nil
		previewThumbnail.Visible = false
		previewLabel.Text = Icons.inline("attachFile", false, 14) .. " Processing " .. Icons.escape(file.Name) .. "..."
		previewBar.Visible = true
		ctx.relayout()
		isUploading = true
		local gifOk, url, uploaded = pcall(GifPlayer.fromFile, file)
		isUploading = false
		if gifOk then
			showPreview(url, if uploaded then "GIF attached" else "GIF attached (local only)")
		else
			hidePreview()
			log.warn("Could not read " .. file.Name .. ": " .. tostring(url))
		end
		ctx.relayout()
	end

	previewRemove.MouseButton1Click:Connect(function()
		hidePreview()
		ctx.relayout()
	end)

	-- Dragging anything else over the panel (Explorer items, files) comes
	-- with no drag data at all
	local function isAttachmentDrag(dragData): boolean
		return type(dragData) == "table" and dragData.MimeType == Attachments.MIME_TYPE
	end

	widget.PluginDragEntered:Connect(function(dragData)
		if isAttachmentDrag(dragData) then
			dropOverlay.Visible = true
		end
	end)
	widget.PluginDragLeft:Connect(function()
		dropOverlay.Visible = false
	end)
	widget.PluginDragDropped:Connect(function(dragData)
		dropOverlay.Visible = false
		if not isAttachmentDrag(dragData) or type(dragData.Data) ~= "string" then
			return
		end

		local fileName, fileUrl, fileType = string.match(dragData.Data, "^(.-)|(.-)|(.-)$")
		if not fileUrl or fileUrl == "" then
			return
		end

		if fileType == "Image" then
			showPreview(fileUrl, "Image attached")
		else
			pendingImage = nil
			pendingFile = { fileName = fileName, fileUrl = fileUrl, fileType = fileType }
			showFileLabel(" " .. Icons.escape(fileName))
		end
		ctx.relayout()
	end)

	local self = {}

	--[=[
		Opens the file picker and attaches the first file chosen.
	]=]
	function self.pick()
		if isUploading then
			return
		end

		task.spawn(function()
			local ok, files = pcall(function()
				return StudioService:PromptImportFilesAsync(ATTACH_FILE_FILTER)
			end)
			if not ok then
				log.warn("Could not open the file picker: " .. tostring(files))
				return
			end
			local file = files and files[1]
			if not file then
				return
			end

			local extension = extensionOf(file.Name)
			if extension == "gif" then
				attachGif(file)
			elseif table.find(IMAGE_FILTER, extension) then
				uploadImageFile(file)
			else
				uploadFile(file)
			end
		end)
	end

	function self.getPendingImage(): string?
		return pendingImage
	end

	function self.clearPendingImage()
		pendingImage = nil
		hidePreview()
	end

	function self.getPendingFile()
		return pendingFile
	end

	function self.clearPendingFile()
		pendingFile = nil
		hidePreview()
	end

	function self.isUploading(): boolean
		return isUploading
	end

	--[=[
		Puts the preview bar on top of the composer; returns the space it takes.
	]=]
	function self.place(composerHeight: number): number
		previewBar.Position = UDim2.new(0, 0, 1, -(composerHeight + PREVIEW_HEIGHT))
		return if previewBar.Visible then PREVIEW_HEIGHT else 0
	end

	function self.recolor()
		local palette = ctx.palette
		previewBar.BackgroundColor3 = palette.inputFrame
		previewThumbnail.BackgroundColor3 = palette.scrollBack
		previewThumbnail.BorderColor3 = palette.previewBorder
		previewLabel.TextColor3 = palette.messageText
		previewRemove.BackgroundColor3 = palette.attachButton
		previewRemove.TextColor3 = palette.attachIcon

		dropOverlay.BackgroundTransparency = 0.85
		dropOverlayStroke.Color = palette.sendButton
		dropLabel.TextColor3 = palette.sendButtonText
	end

	return self
end

return Attachments
