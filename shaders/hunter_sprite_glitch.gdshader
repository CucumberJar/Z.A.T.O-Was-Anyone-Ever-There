shader_type canvas_item;

// Актуальная область кадра передаётся из indoor_hunter.gd.
// Не зависит от старого region_rect в сцене.
uniform vec4 frame_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float glitch_strength : hint_range(0.0, 1.0) = 0.65;
uniform float glitch_rate : hint_range(1.0, 30.0) = 9.0;
uniform float slice_offset_pixels : hint_range(0.0, 8.0) = 3.0;
uniform float color_offset_pixels : hint_range(0.0, 4.0) = 1.0;

varying vec4 visual_tint;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
    visual_tint = COLOR;
}

void fragment() {
    vec2 texel = TEXTURE_PIXEL_SIZE;
    vec2 low = frame_uv_rect.xy + 0.5 * texel;
    vec2 high = frame_uv_rect.xy + frame_uv_rect.zw - 0.5 * texel;
    vec2 uv = clamp(UV, low, high);

    float y = clamp((UV.y - frame_uv_rect.y) / max(frame_uv_rect.w, 0.0001), 0.0, 0.9999);
    float stripe = floor(y * 16.0);
    float tick = floor(TIME * glitch_rate);
    float gate = step(0.78, hash21(vec2(stripe, tick))) * glitch_strength;
    float direction = hash21(vec2(stripe + 19.0, tick * 0.71)) * 2.0 - 1.0;
    vec2 shift = vec2(round(direction * slice_offset_pixels) * gate, 0.0) * texel;

    vec4 original = texture(TEXTURE, uv);
    vec4 shifted = texture(TEXTURE, clamp(uv + shift, low, high));
    vec2 rgb_shift = vec2(color_offset_pixels * gate, 0.0) * texel;
    vec3 split = vec3(
        texture(TEXTURE, clamp(uv + shift + rgb_shift, low, high)).r,
        shifted.g,
        texture(TEXTURE, clamp(uv + shift - rgb_shift, low, high)).b
    );

    // Даже во время глича не делаем весь спрайт прозрачным.
    vec3 rgb = mix(original.rgb, split, gate);
    float alpha = max(original.a, shifted.a * gate * 0.5);
    COLOR = vec4(rgb, alpha) * visual_tint;
}
