extends SceneTree
## Regenerates the placeholder sprites in res://sprites/ from ASCII pixel
## maps ('.' transparent, 'B' black, 'P' purple, 'H' peach — palette only).
## Run: "$GODOT" --headless --path . --script res://tools/make_placeholders.gd

const COLORS := {
	"B": Palette.BLACK,
	"P": Palette.PURPLE,
	"H": Palette.PEACH,
	"W": Palette.WHITE,
}

const ENEMY := [
	"......BB........BB......",
	".....BPPB......BPPB.....",
	".....BHHB......BHHB.....",
	".....BHHB......BHHB.....",
	".....BHHB......BHHB.....",
	".....BHHB......BHHB.....",
	".....BPPB......BPPB.....",
	"....BBBBBBBBBBBBBBBB....",
	"...BPPPPPPPPPPPPPPPPB...",
	"..BPPPPPPPPPPPPPPPPPPB..",
	"..BPPPBBPPPPPPPPBBPPPB..",
	"..BPPPBBPPPPPPPPBBPPPB..",
	"..BPPPPPPPPHHPPPPPPPPB..",
	"..BPPPPPPPBPPBPPPPPPPB..",
	"..BPPPPPPPPPPPPPPPPPPB..",
	"..BPPPPPPPPPPPPPPPPPPB..",
	"..BPPPPPPPPPPPPPPPPPPB..",
	"..BPPPPPPPPPPPPPPPPPPB..",
	"...BPPPPPPPPPPPPPPPPB...",
	"....BBBBBBBBBBBBBBBB....",
	"......BPPB....BPPB......",
	"......BPPB....BPPB......",
	"......BBBB....BBBB......",
	"........................",
]

const DROP := [
	".BB.",
	"BHHB",
	"BHHB",
	".BB.",
]

const ICON_DMG := [
	"................",
	"............BB..",
	"...........BBB..",
	"..........BBB...",
	".........BBB....",
	"........BBB.....",
	".......BBB......",
	"......BBB.......",
	"..H..BBB........",
	"..HHBBB.........",
	"...HHB..........",
	"..HHHH..........",
	".HH..HH.........",
	"BB....HH........",
	"................",
	"................",
]

const ICON_SIZE := [
	"BBBB............",
	"BB..............",
	"B.B.............",
	"B..B............",
	"....BBBBBBBB....",
	"....BPPPPPPB....",
	"....BPPPPPPB....",
	"....BPPPPPPB....",
	"....BPPPPPPB....",
	"....BPPPPPPB....",
	"....BPPPPPPB....",
	"....BBBBBBBB....",
	"............B..B",
	".............B.B",
	"..............BB",
	"............BBBB",
]

const ICON_SPEED := [
	"........BB......",
	".......BHB......",
	"......BHHB......",
	".....BHHB.......",
	"....BHHB........",
	"...BHHHBBBB.....",
	"...BHHHHHHB.....",
	"...BBBBHHB......",
	"......BHHB......",
	".....BHHB.......",
	"....BHHB........",
	"...BHHB.........",
	"...BHB..........",
	"...BB...........",
	"................",
	"................",
]

const ICON_HUB := [
	"BBBB........BBBB",
	"B..............B",
	"B..............B",
	"B..............B",
	"................",
	"................",
	"......PPPP......",
	"......PPPP......",
	"......PPPP......",
	"......PPPP......",
	"................",
	"................",
	"B..............B",
	"B..............B",
	"B..............B",
	"BBBB........BBBB",
]

const CURSOR := [
	"B.......",
	"BB......",
	"BWB.....",
	"BWWB....",
	"BWWWB...",
	"BWWWWB..",
	"BWBBBB..",
	"BB......",
]

func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://sprites")
	_write("res://sprites/enemy.png", ENEMY)
	_write("res://sprites/drop.png", DROP)
	_write("res://sprites/icon_dmg.png", ICON_DMG)
	_write("res://sprites/icon_size.png", ICON_SIZE)
	_write("res://sprites/icon_speed.png", ICON_SPEED)
	_write("res://sprites/icon_hub.png", ICON_HUB)
	# Cursor is pre-upscaled x4: OS cursors render at window resolution,
	# outside the 480x270 integer-scaled canvas (documented spec exception).
	_write("res://sprites/cursor.png", CURSOR, 4)
	quit()


func _write(path: String, rows: Array, scale: int = 1) -> void:
	var img := Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		assert(rows[y].length() == rows[0].length(), "ragged row in " + path)
		for x in rows[y].length():
			if COLORS.has(rows[y][x]):
				img.set_pixel(x, y, COLORS[rows[y][x]])
	if scale > 1:
		img.resize(rows[0].length() * scale, rows.size() * scale, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
	print("wrote ", path)
