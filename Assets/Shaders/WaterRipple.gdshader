shader_type canvas_item;

// ============================================================================
//  PIXEL-ART WATER RIPPLE TINT  (pixel-snapped)
// ----------------------------------------------------------------------------
//  Colours a white-on-transparent ripple mask by the water underneath: cyan in
//  shallow, dark purple in deep, bright foam along the grass shoreline, plus
//  scattered sparkle glints. The ripple's alpha mask is only tinted, never cut.
//
//  EVERYTHING is quantised to the art-pixel grid:
//    - all pattern maths runs on floor(world_pos / pixel_size)
//    - all neighbour sampling steps by WHOLE art pixels, derived from the
//      actual on-screen scale, so radii stay correct at any camera zoom
//    - all animation steps at anim_fps instead of drifting continuously
//
//  SETUP
//    1. Ripple sheet import: Filter = Nearest, Repeat = Disabled, Mipmaps off.
//    2. Scene order MUST be:
//         water base layer
//         rock / cliff layer
//         BackBufferCopy   (Copy Mode = Viewport)
//         ripple layer     <- this material
//       If the rock layer draws AFTER the BackBufferCopy the shader cannot see
//       it, and you get no shoreline at all.
//    3. Set pixel_size to your art's pixel scale in world units (normally 1.0).
//
//  FIRST THINGS TO TUNE
//    grass_radius - in ART PIXELS. Must exceed your cliff band thickness or
//                   foam never appears anywhere.
//    shore_radius - in ART PIXELS. No zoom multiplication needed any more.
// ============================================================================

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, repeat_disable, filter_nearest;


// ------------------------------------------------------------ pixel grid ---
// World units per art pixel. 1.0 if your sprites draw at 1:1 in world space.
uniform float pixel_size : hint_range(1.0, 16.0) = 1.0;
// Animation is stepped at this rate so nothing moves in sub-pixel increments.
// 8-12 suits most pixel art. Higher gets smoother but less "drawn".
uniform float anim_fps : hint_range(1.0, 60.0) = 10.0;


// ---------------------------------------------------------------- palette ---
uniform vec4 ripple_foam    : source_color = vec4(0.431, 0.722, 0.843, 1.0); // 110,184,215
uniform vec4 ripple_shallow : source_color = vec4(0.384, 0.624, 0.765, 1.0); //  98,159,195
uniform vec4 ripple_mid     : source_color = vec4(0.353, 0.557, 0.714, 1.0); //  90,142,182
uniform vec4 ripple_deep    : source_color = vec4(0.196, 0.220, 0.333, 1.0); //  50, 56, 85
                                                                             // deliberately DARKER than the deep base

// ----------------------------------------------------------- depth mapping --
uniform float deep_lum    : hint_range(0.0, 1.0) = 0.283;  //  72/255  fully deep
uniform float shallow_lum : hint_range(0.0, 1.0) = 0.443;  // 113/255  fully shallow
uniform float deep_fade   : hint_range(0.0, 1.0) = 0.25;   // deep ripples are fainter
uniform float shallow_cut : hint_range(0.0, 1.0) = 0.66;   // below this = deep


// ------------------------------------------------- depth transition noise ---
// Only acts near a colour threshold, so open water on either side stays flat.
uniform float noise_strength : hint_range(0.0, 1.0)  = 0.30;
uniform float noise_cell     : hint_range(1.0, 32.0) = 6.0;  // art px per blob
uniform float noise_speed    : hint_range(0.0, 1.0)  = 0.05; // 0 = static edge
uniform float noise_band     : hint_range(0.0, 0.5)  = 0.22; // reach around a threshold
uniform float noise_chunk    : hint_range(1.0, 8.0)  = 1.0;  // edge blockiness, art px


// ------------------------------------------------------------- shoreline ----
uniform bool  shore_enabled = true;
uniform float shore_radius : hint_range(0.0, 32.0)  = 5.0;   // ART PIXELS
uniform float grass_radius : hint_range(0.0, 128.0) = 14.0;  // ART PIXELS
// (blue - red) below this means solid rock, not water.
// Measured from the scene: rock 26..43, water 66..115 (out of 255).
uniform float rock_cut : hint_range(0.0, 0.5) = 0.212;  // 54/255


// --------------------------------------------------------------- sparkle ----
uniform vec4  highlight_color       : source_color = vec4(0.847, 0.925, 0.973, 1.0); // 216,236,248
uniform float highlight_amount      : hint_range(0.0, 0.25) = 0.05;  // coverage fraction, shallow
uniform bool  highlight_deep        = true;
uniform vec4  highlight_color_deep  : source_color = vec4(0.600, 0.702, 0.878, 1.0); // 153,179,224
uniform float highlight_amount_deep : hint_range(0.0, 0.25) = 0.03;  // coverage fraction, deep
uniform bool  highlight_shore_only  = false;

// Block size in ART PIXELS. 1 can never be clipped by the mask.
uniform float highlight_px : hint_range(1.0, 8.0) = 1.0;
// Skip ripple edge pixels so sparkles sit inside a blob. 4 extra fetches.
uniform bool  highlight_interior_only = true;

// Each cell runs its OWN clock, phase-offset by a hash. A single shared clock
// makes the entire field snap to new positions on the same frame.
uniform float highlight_rate  : hint_range(0.0, 8.0)  = 1.2;   // rolls/sec per cell
uniform float highlight_hold  : hint_range(0.05, 1.0) = 0.55;  // visible fraction of a cycle
uniform vec2  highlight_drift = vec2(1.5, -0.8);               // art px/sec, stepped


varying vec2 world_pos;


float hash21(vec2 p) {
    return fract(sin(p.x * 127.1 + p.y * 311.7) * 43758.5453);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = p - i;
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float e = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, e, f.x), f.y);
}

// Grass is the only thing in the palette where green beats blue.
bool is_grass(vec2 uv) {
    vec3 c = texture(SCREEN_TEXTURE, uv).rgb;
    return c.g > c.b + 0.04;
}

// Rock is dark AND washed out. Luminance alone cannot separate it from deep
// water (rock L50 vs water L70); the blue-red spread can (rock <43, water >66).
bool is_rock(vec2 uv) {
    vec3 c = texture(SCREEN_TEXTURE, uv).rgb;
    if (c.g > c.b + 0.04) return true;      // grass counts as solid too
    return (c.b - c.r) < rock_cut;
}


void vertex() {
    // World space: tiles stay a fixed size, patterns do not swim with the
    // camera, and neighbouring water nodes line up.
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}


void fragment() {
    // ---- pixel grid ------------------------------------------------------
    // P is this fragment's art pixel, as an integer cell index. Every pattern
    // below is evaluated from P, never from the raw continuous position, so no
    // feature can ever land on a half pixel.
    vec2 P = floor(world_pos / pixel_size);

    // World units covered by one screen pixel, straight from the rasteriser.
    // Dividing pixel_size by it gives screen pixels per art pixel = zoom.
    // art_step = UV delta that moves exactly one art pixel on screen. Derived
    // from the real on-screen scale, so it tracks camera zoom by itself.
    vec2 wpp = vec2(abs(dFdx(world_pos.x)), abs(dFdy(world_pos.y)));
    vec2 art_step = SCREEN_PIXEL_SIZE * (pixel_size / max(wpp, vec2(0.0001)));

    // Stepped clock. Every animated term uses this, not TIME.
    float T = floor(TIME * anim_fps) / anim_fps;

    float mask = texture(TEXTURE, UV).a;   // white-on-transparent: alpha is the shape

    vec3  below = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
    float lum   = dot(below, vec3(0.299, 0.587, 0.114));

    // d_raw: depth straight from the tile underneath, BEFORE noise.
    // Every "is this shallow" decision uses this, so a noise nudge can never
    // promote a deep pixel into receiving foam or shallow sparkle.
    float d_raw = clamp((lum - deep_lum) / max(shallow_lum - deep_lum, 0.001), 0.0, 1.0);
    bool  shallow_water = d_raw > shallow_cut;

    // d: noise-perturbed copy, used ONLY to choose the band colour.
    float edge_dist = min(abs(d_raw - 0.33), abs(d_raw - 0.66));
    float gate      = 1.0 - smoothstep(0.0, noise_band, edge_dist);
    vec2  np        = floor(P / noise_chunk) * noise_chunk / noise_cell;
    float n         = vnoise(np + vec2(T * noise_speed, T * noise_speed * 0.6));
    float d         = clamp(d_raw + (n - 0.5) * noise_strength * gate, 0.0, 1.0);

    // ---- band colour by depth ----
    vec3 tint = ripple_deep.rgb;
    if (d > 0.33) tint = ripple_mid.rgb;
    if (d > 0.66) tint = ripple_shallow.rgb;

    // ---- shoreline, shallow water only ----
    float shore = 0.0;
    if (shore_enabled && shallow_water && shore_radius > 0.0) {

        // Stage 1: grass anywhere in the wider neighbourhood? This is what
        // disqualifies the underwater ledge, which has rock beside it but no
        // grass for a long way.
        bool near_grass = false;
        for (int i = 0; i < 8; i++) {
            float a = float(i) * 0.7853982;             // TAU / 8
            vec2 dir = vec2(cos(a), sin(a));
            // round() keeps every probe on a whole art pixel.
            vec2 o1 = round(dir * grass_radius) * art_step;
            vec2 o2 = round(dir * grass_radius * 0.65) * art_step;
            if (is_grass(SCREEN_UV + o1)) { near_grass = true; }
            if (is_grass(SCREEN_UV + o2)) { near_grass = true; }
        }

        // Stage 2: only then, how close is the rock edge?
        if (near_grass) {
            for (int i = 0; i < 8; i++) {
                float a = float(i) * 0.7853982;
                vec2 dir = vec2(cos(a), sin(a));
                vec2 inner = round(dir * shore_radius * 0.5) * art_step;
                vec2 outer = round(dir * shore_radius) * art_step;
                if (is_rock(SCREEN_UV + inner))     { shore = 1.0; }
                else if (is_rock(SCREEN_UV + outer)) { shore = max(shore, 0.5); }
            }
        }
    }

    if (shore >= 1.0)     tint = ripple_foam.rgb;
    else if (shore > 0.0) tint = ripple_shallow.rgb;

    // ---- sparkle, applied last so it sits on top of every other tone ----
    vec3  spark_col = shallow_water ? highlight_color.rgb : highlight_color_deep.rgb;
    float spark_amt = shallow_water ? highlight_amount    : highlight_amount_deep;

    bool lit = shallow_water || highlight_deep;
    if (highlight_shore_only) { lit = shallow_water && shore > 0.0; }

    // Ripple edge pixels are where grid-vs-mask clipping shows, so drop them.
    if (lit && highlight_interior_only) {
        vec2 tp = TEXTURE_PIXEL_SIZE;
        float inner = min(
            min(texture(TEXTURE, UV + vec2(0.0, -tp.y)).a,
                texture(TEXTURE, UV + vec2(0.0,  tp.y)).a),
            min(texture(TEXTURE, UV + vec2(-tp.x, 0.0)).a,
                texture(TEXTURE, UV + vec2( tp.x, 0.0)).a));
        if (inner < 0.5) { lit = false; }
    }

    if (lit && spark_amt > 0.0) {
        // Drift is rounded to whole art pixels, so the sparkle field jumps a
        // pixel at a time instead of sliding through fractional positions.
        vec2 drift = round(highlight_drift * T);
        vec2 hp = floor((P + drift) / highlight_px);

        // Per-cell phase offset, so cells never re-roll in unison.
        float seed  = hash21(hp * 1.37 + vec2(3.11, 7.53));
        float cycle = T * highlight_rate + seed * 43.0;

        float k = floor(cycle);   // which roll this cell is on
        float f = fract(cycle);   // position inside its own roll

        // hash21 is uniform 0..1, so spark_amt IS the coverage fraction.
        if (f < highlight_hold && hash21(hp + vec2(k * 17.31, k * 5.77)) < spark_amt) {
            tint = spark_col;
        }
    }

    float fade = mix(1.0 - deep_fade, 1.0, max(d, shore));

    COLOR = vec4(tint, mask * fade);
}
