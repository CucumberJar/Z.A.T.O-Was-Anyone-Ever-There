shader_type canvas_item;

// Full-view distortion, driven by distance to the player from GDScript.
// Screen-reading requires Godot 4's hint_screen_texture.
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float glitch_rate : hint_range(1.0, 30.0) = 8.0;
uniform float slice_height_pixels : hint_range(3.0, 32.0) = 12.0;
uniform float slice_offset_pixels : hint_range(0.0, 18.0) = 7.0;
uniform float color_offset_pixels : hint_range(0.0, 8.0) = 2.0;
uniform float noise_amount : hint_range(0.0, 0.3) = 0.05;

float noise2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    vec4 normal = textureLod(screen_tex, uv, 0.0);

    float tick = floor(TIME * glitch_rate);
    float band = floor(FRAGCOORD.y / max(slice_height_pixels, 1.0));
    float gate = step(0.78, noise2(vec2(band, tick * 1.37)));
    float direction = noise2(vec2(tick + 17.0, band * 2.33)) * 2.0 - 1.0;
    float displacement = direction * slice_offset_pixels * strength * gate;

    vec2 shift = vec2(displacement * SCREEN_PIXEL_SIZE.x, 0.0);
    vec2 torn_uv = clamp(uv + shift, vec2(0.0), vec2(1.0));
    vec3 torn = textureLod(screen_tex, torn_uv, 0.0).rgb;

    // A brief chromatic split in selected horizontal bands.
    float split = step(0.66, noise2(vec2(band + 5.0, tick + 19.0))) * gate;
    float chroma = color_offset_pixels * strength * split * SCREEN_PIXEL_SIZE.x;
    vec2 red_uv = clamp(torn_uv + vec2(chroma, 0.0), vec2(0.0), vec2(1.0));
    vec2 blue_uv = clamp(torn_uv - vec2(chroma, 0.0), vec2(0.0), vec2(1.0));
    vec3 distorted = vec3(
        textureLod(screen_tex, red_uv, 0.0).r,
        torn.g,
        textureLod(screen_tex, blue_uv, 0.0).b
    );

    float grain = noise2(vec2(floor(FRAGCOORD.x * 0.5), floor(FRAGCOORD.y * 0.5) + tick * 11.0));
    float grain_shift = (grain - 0.5) * noise_amount * strength;
    distorted += vec3(grain_shift);

    // No large white flashes; the effect stays readable during gameplay.
    float blend = strength * (0.38 + 0.62 * gate);
    COLOR = vec4(mix(normal.rgb, clamp(distorted, vec3(0.0), vec3(1.0)), blend), 1.0);
}
