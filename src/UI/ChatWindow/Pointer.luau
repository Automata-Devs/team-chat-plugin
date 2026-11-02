--!strict
--[[
	Pointer

	Mouse helpers for the chat window. Full-panel "click catchers" sit behind
	modals and menus and also receive clicks made on top of them (frames don't
	block GUI buttons), so they check the real mouse position before closing.

	Usage:
		local pointer = Pointer.new(widget)
		if not pointer.isInside(card, pointer.mousePosition()) then close() end
]]

export type Pointer = {
	isInside: (gui: GuiObject, point: Vector2 | Vector3) -> boolean,
	mousePosition: () -> Vector2,
}

local Pointer = {}

--[=[
	True when `point` (same space as AbsolutePosition) is over `gui`.
]=]
function Pointer.isInside(gui: GuiObject, point: Vector2 | Vector3): boolean
	local topLeft, size = gui.AbsolutePosition, gui.AbsoluteSize
	return point.X >= topLeft.X
		and point.X <= topLeft.X + size.X
		and point.Y >= topLeft.Y
		and point.Y <= topLeft.Y + size.Y
end

--[=[
	Helpers bound to a widget (a DockWidgetPluginGui in the plugin).
]=]
function Pointer.new(widget: any): Pointer
	return {
		isInside = Pointer.isInside,
		-- Current mouse position in the same space as GuiObject.AbsolutePosition.
		mousePosition = function(): Vector2
			return widget:GetRelativeMousePosition() + widget.AbsolutePosition
		end,
	}
end

return Pointer
