shader_type canvas_item;
// Erodes the enemy's purple body to peach, left to right, as HP drops.
// Purple stays right-anchored (like the old HP bar): hp_ratio 1.0 = all
// purple, 0.0 = all peach. Outline/transparent pixels pass through.
// Colors are Palette.PURPLE / Palette.PEACH (shaders can't read GDScript).

uniform float hp_ratio : hint_range(0.0, 1.0) = 1.0;

const vec3 PURPLE = vec3(0.439216, 0.341176, 0.611765);
const vec3 PEACH = vec3(0.878431, 0.588235, 0.658824);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a > 0.0 && distance(tex.rgb, PURPLE) < 0.02 && UV.x < 1.0 - hp_ratio) {
		COLOR = vec4(PEACH, tex.a);
	} else {
		COLOR = tex;
	}
}
