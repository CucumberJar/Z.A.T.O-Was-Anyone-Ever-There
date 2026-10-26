shader_type canvas_item;
render_mode unshaded, blend_mix;

// Z.A.T.O. Fog v0.9.4. Shadow is blocked ONLY by tiles from
// WallTiles / WeryWellTiles (see fog_of_war.gd).
// Use the nearest angular ray, not min(two rays): avoids false black wedges.
uniform sampler2D vision_rays : filter_nearest, repeat_disable;
uniform float ray_count = 768.0;
uniform vec2 viewport_size = vec2(640.0, 360.0);
uniform vec2 camera_translation = vec2(0.0);
uniform float camera_zoom = 1.0;
uniform vec2 eye_world = vec2(0.0);
uniform float vision_radius = 250.0;
uniform float pixel_size = 4.0;

uniform float near_dim = 0.03;
uniform float middle_dim = 0.17;
uniform float far_dim = 0.40;
uniform float edge_dim = 0.70;
uniform float darkness = 0.985;
uniform float near_boundary = 0.36;
uniform float middle_boundary = 0.67;
uniform float far_boundary = 0.88;
uniform float wall_dim = 0.16;
uniform vec4 shadow_color : source_color = vec4(0.016, 0.022, 0.033, 1.0);

const float PI_VALUE = 3.141592653589793;
const float TWO_PI_VALUE = 6.283185307179586;

void fragment() {
    vec2 screen_pos = UV * viewport_size;
    vec2 world_pos = (screen_pos - camera_translation) / max(camera_zoom, 0.001);
    float block = max(pixel_size, 1.0);
    world_pos = (floor(world_pos / block) + 0.5) * block;

    vec2 delta = world_pos - eye_world;
    float distance_to_eye = length(delta);
    float angle = atan(delta.y, delta.x);
    float index = floor(fract((angle + PI_VALUE) / TWO_PI_VALUE) * ray_count);
    vec4 ray = texture(vision_rays, vec2((index + 0.5) / ray_count, 0.5));

    float visible_reach = ray.a * vision_radius;
    float first_wall = ray.r * vision_radius;
    bool wall_ray = ray.g > 0.5;
    float opacity = darkness;

    if (distance_to_eye <= visible_reach) {
        float ratio = distance_to_eye / max(vision_radius, 0.001);
        float middle_limit = max(middle_boundary, near_boundary);
        float far_limit = max(far_boundary, middle_limit);
        if (ratio < near_boundary) {
            opacity = near_dim;
        } else if (ratio < middle_limit) {
            opacity = middle_dim;
        } else if (ratio < far_limit) {
            opacity = far_dim;
        } else {
            opacity = edge_dim;
        }
        // Only dim the visible surface of the wall, not the room in front.
        if (wall_ray && distance_to_eye >= first_wall - block * 0.5) {
            opacity = max(opacity, wall_dim);
        }
    }
    COLOR = vec4(shadow_color.rgb, clamp(opacity, 0.0, 1.0));
}
