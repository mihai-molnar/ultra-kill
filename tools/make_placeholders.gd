extends SceneTree
## Regenerates the placeholder sprites in res://sprites/ from ASCII pixel
## maps ('.' transparent, 'B' black, 'P' purple, 'H' peach — palette only).
## Run: "$GODOT" --headless --path . --script res://tools/make_placeholders.gd

const COLORS := {
	"B": Palette.BLACK,
	"P": Palette.PURPLE,
	"H": Palette.PEACH,
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

func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://sprites")
	_write("res://sprites/enemy.png", ENEMY)
	_write("res://sprites/drop.png", DROP)
	quit()


func _write(path: String, rows: Array) -> void:
	var img := Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		assert(rows[y].length() == rows[0].length(), "ragged row in " + path)
		for x in rows[y].length():
			if COLORS.has(rows[y][x]):
				img.set_pixel(x, y, COLORS[rows[y][x]])
	img.save_png(path)
	print("wrote ", path)
