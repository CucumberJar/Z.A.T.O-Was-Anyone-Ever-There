shader_type canvas_item;
render_mode unshaded, blend_mix;

// Physics ray distances are encoded into this tiny 384x1 image.
uniform sampler2D vision_rays : filter_nearest, repeat_disable;
uniform float ray_count = 384.0;

uniform vec2 viewport_size = vec2(640.0, 360.0);
uniform vec2 camera_translation = vec2(0.0, 0.0);
uniform float camera_zoom = 1.0;
uniform vec2 eye_world = vec2(0.0, 0.0);
uniform float vision_radius = 250.0;
uniform float ray_cast_radius = 276.0;

uniform float oval_width = 1.0;
uniform float oval_height = 0.62;
uniform vec2 oval_center_offset = vec2(0.0, 26.0);
uniform float pixel_size = 2.0;
uniform float visibility_feather = 2.0;
// 0 = linear between control points; 1 = smooth cubic interpolation.
uniform float gradient_smoothing = 0.7;
// < 1 makes the center slightly darker, > 1 brightens the center.
uniform float gradient_exponent = 1.0;

uniform float near_dim = 0.04;
uniform float middle_dim = 0.20;
uniform float far_dim = 0.43;
uniform float edge_dim = 0.71;
uniform float darkness = 0.985;
uniform float near_boundary = 0.30;
uniform float middle_boundary = 0.59;
uniform float far_boundary = 0.84;
uniform float wall_dim = 0.16;
uniform vec4 shadow_color : source_color = vec4(0.016, 0.022, 0.033, 1.0);

const float PI_VALUE = 3.14159265359;
const float TWO_PI_VALUE = 6.28318530718;

vec4 sample_vision_ray(float index) {
    float wrapped = mod(index + ray_count, ray_count);
    return texture(vision_rays, vec2((wrapped + 0.5) / ray_count, 0.5));
}

// All four dim levels are control points of ONE continuous gradient.
// No conditional flat shading rings, so the light doesn't look like stacked ovals.
float ease_segment(float t) {
    t = clamp(t, 0.0, 1.0);
    float smooth_t = t * t * (3.0 - 2.0 * t);
    return mix(t, smooth_t, clamp(gradient_smoothing, 0.0, 1.0));
}

float dim_gradient(float normalized_distance) {
    float x = clamp(pow(max(normalized_distance, 0.0), max(gradient_exponent, 0.1)), 0.0, 1.0);
    float p1 = clamp(near_boundary, 0.05, 0.8);
    float p2 = clamp(middle_boundary, p1 + 0.02, 0.91);
    float p3 = clamp(far_boundary, p2 + 0.02, 0.99);

    if (x < p1) {
        return mix(near_dim, middle_dim, ease_segment(x / p1));
    }
    if (x < p2) {
        return mix(middle_dim, far_dim, ease_segment((x - p1) / (p2 - p1)));
    }
    if (x < p3) {
        return mix(far_dim, edge_dim, ease_segment((x - p2) / (p3 - p2)));
    }
    return mix(edge_dim, darkness, ease_segment((x - p3) / (1.0 - p3)));
}

void fragment() {
    // Screen-aligned, integer-sized pixels. The pattern does not swim across
    // the screen with camera subpixel movement during sprinting.
    float block = max(pixel_size, 1.0);
    vec2 screen_pixel = (floor((UV * viewport_size) / block) + vec2(0.5)) * block;
    vec2 world_pixel = (screen_pixel - camera_translation) / max(camera_zoom, 0.001);

    vec2 from_eye = world_pixel - eye_world;
    vec2 from_oval_center = from_eye - oval_center_offset;
    vec2 scaled = from_oval_center / max(vision_radius, 0.001);
    float oval_distance = length(vec2(scaled.x / max(oval_width, 0.01),
                                       scaled.y / max(oval_height, 0.01)));

    float angle = atan(from_eye.y, from_eye.x);
    float ray_pos = fract((angle + PI_VALUE) / TWO_PI_VALUE) * ray_count;
    float ray0 = floor(ray_pos);
    float mix_amount = fract(ray_pos);
    vec4 a = sample_vision_ray(ray0);
    vec4 b = sample_vision_ray(ray0 + 1.0);

    // Adjacent-ray interpolation removes hard angular stripes at high speed.
    // It changes only visibility sampling; obstacles still come from physics.
    vec4 ray = mix(a, b, mix_amount);
    float distance_from_eye = length(from_eye);
    float visibility_reach = ray.a * ray_cast_radius;
    float first_wall = ray.r * ray_cast_radius;
    float fade_px = max(visibility_feather / max(camera_zoom, 0.001), 0.3);

    // Unlike v0.9.7, dim is evaluated continuously across the entire oval.
    // The oval itself gently reaches full darkness before the radius limit.
    float gradual_dim = dim_gradient(oval_distance);

    // Wall visibility uses physics ray distances and stays sharp: fading the
    // RADIAL gradient is safe, but fading across walls can reveal other rooms.
    float wall_visibility = 1.0 - smoothstep(
        visibility_reach - fade_px,
        visibility_reach + fade_px,
        distance_from_eye
    );

    // Light the face of a wall but never reveal what is behind it.
    if (ray.g > 0.5) {
        float face_factor = smoothstep(
            first_wall - fade_px,
            first_wall + fade_px,
            distance_from_eye
        );
        gradual_dim = mix(
            gradual_dim,
            max(gradual_dim, wall_dim),
            face_factor
        );
    }

    float alpha = mix(darkness, gradual_dim, wall_visibility);
    COLOR = vec4(shadow_color.rgb, clamp(alpha, 0.0, 1.0));
}
