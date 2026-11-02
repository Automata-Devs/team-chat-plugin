--!nonstrict
--!
-- EmbedStyle
-- Layout constants for embed cards. Change sizes, spacing, and limits here.
--!

return {
	-- Behavior
	MAX_EMBEDS_PER_MESSAGE = 1,
	-- LayoutOrder inside a message container: text is 1, embeds start here,
	-- and any image attachment is moved after the last embed.
	FIRST_EMBED_LAYOUT_ORDER = 2,

	-- Space around the card inside the message. The message container uses
	-- a negative list padding (-4), so the top value is a net gap of 4px.
	HOLDER_PADDING_TOP = 8,
	HOLDER_PADDING_BOTTOM = 2,
	HOLDER_PADDING_RIGHT = 4,

	-- Card
	CARD_MAX_WIDTH = 400, -- cards don't stretch across wide chat panels
	CARD_CORNER_RADIUS = 8,
	CARD_STROKE_TRANSPARENCY = 0.35,

	-- Accent bar (inset pill on the left edge)
	ACCENT_WIDTH = 3,
	ACCENT_LEFT = 6,
	ACCENT_VERTICAL_INSET = 8,
	ACCENT_CORNER_RADIUS = 2,

	-- Content area inside the card
	BODY_PADDING_TOP = 9,
	BODY_PADDING_BOTTOM = 9,
	BODY_PADDING_LEFT = 18,
	BODY_PADDING_RIGHT = 12,
	ROW_SPACING = 2,

	-- Link preview row: icon tile, two text lines, open arrow
	ICON_TILE_SIZE = 34,
	ICON_SIZE = 18,
	ICON_GAP = 10,
	OPEN_ICON_SIZE = 16,

	-- Text
	TITLE_TEXT_SIZE = 14,
	BODY_TEXT_SIZE = 12,
	FOOTER_TEXT_SIZE = 11,
}
