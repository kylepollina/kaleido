// The kaleidoscope shader, compiled at launch (a SwiftPM executable has no .metallib to load).
enum Shaders {
    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float width, height;
        float rotation;      // radians, mirror pattern angle
        float sourceRotation;// radians, turns the photo inside the mirrors
        float panX, panY;    // photo-space drift (units of photo height)
        float zoom;
        float twist;
        float hue;           // radians
        float saturation;
        float vignette;
        float blurLod;       // extra mip levels
        float time;
        float aspectA, aspectB;
        float mixAmount;     // 0...1 transition progress (raw)
        float spinBoost;     // extra rotation during the "spin" transition
        int segments;
        int mode;            // 0 radial, 1 hex, 2 fractal
        int transition;      // 0 dissolve 1 iris 2 swirl 3 zoom 4 segments 5 spin
        int hasB;
    };

    struct VOut { float4 position [[position]]; };

    vertex VOut kaleido_vertex(uint vid [[vertex_id]]) {
        // One oversized triangle covers the screen.
        float2 p = float2((vid << 1) & 2, vid & 2);
        VOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    constant float PI = 3.14159265359;

    float2 rot2(float2 p, float a) {
        float c = cos(a), s = sin(a);
        return float2(c * p.x - s * p.y, s * p.x + c * p.y);
    }

    // Folds the plane into one wedge of 2*PI/n and mirrors it, so neighbouring wedges are reflections
    // of each other and there is no seam. Works for any integer n.
    float2 foldRadial(float2 p, int n) {
        float seg = 2.0 * PI / float(n);
        float r = length(p);
        float a = atan2(p.y, p.x);
        a = a - seg * floor(a / seg);
        a = abs(a - 0.5 * seg);
        return r * float2(cos(a), sin(a));
    }

    // Nearest centre of a regular triangular lattice (spacing 1) and the offset from it.
    float2 hexLocal(float2 p) {
        const float2 s = float2(1.0, 1.7320508);
        float2 c1 = (floor(p / s) + 0.5) * s;
        float2 c2 = (floor((p - 0.5 * s) / s) + 0.5) * s + 0.5 * s;
        float2 d1 = p - c1, d2 = p - c2;
        return dot(d1, d1) < dot(d2, d2) ? d1 : d2;
    }

    float hash11(float n) { return fract(sin(n * 127.1) * 43758.5453); }
    float hash21(float2 p) { return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453); }

    // Maps a screen point (centred, units of screen height) to a point in photo space.
    // `scale` is how many photo-space units one screen unit covers at this point (for the mip level).
    float2 kaleidoPoint(float2 p, constant Uniforms &u, float zoomMul, float extraRot, thread float &scale) {
        float zoom = u.zoom * zoomMul;
        p = rot2(p, u.rotation + extraRot);
        p = rot2(p, u.twist * length(p));
        scale = 1.0;
        float2 f;
        if (u.mode == 1) {
            // Tiled: the lattice is rotated as a whole so the cell fold keeps lining up with cell edges.
            float density = 0.9 + 0.3 * float(u.segments);
            f = foldRadial(hexLocal(p * density), 6);
            scale = density;   // photo units covered by one screen unit
        } else if (u.mode == 2) {
            f = foldRadial(p, u.segments);
            float k = 1.0;
            for (int i = 0; i < 3; i++) {
                float fi = float(i);
                f = abs(f) - float2(0.20 + 0.06 * sin(u.time * 0.21 + fi * 1.7), 0.10 + 0.05 * cos(u.time * 0.17 + fi));
                f = rot2(f, 0.55 + 0.25 * sin(u.time * 0.13 + fi * 2.1));
                f *= 1.28;
                k *= 1.28;
            }
            scale = k;
        } else {
            f = foldRadial(p, u.segments);
        }
        float2 q = rot2(f, u.sourceRotation) / zoom + float2(u.panX, u.panY);
        scale /= zoom;
        return q;
    }

    float3 samplePhoto(texture2d<float> tex, sampler smp, float2 q, float aspect, float scale, constant Uniforms &u) {
        // Photo space: height = 1, width = aspect. Mirrored repeat extends it without edges.
        float2 uv = float2(q.x / aspect, q.y) + 0.5;
        float texels = (scale / u.height) * float(tex.get_height());
        float lod = max(log2(max(texels, 1.0)), 0.0) + u.blurLod;
        return tex.sample(smp, uv, level(lod)).rgb;
    }

    float3 hueRotate(float3 c, float a) {
        const float3 k = float3(0.57735027);
        float cs = cos(a), sn = sin(a);
        return c * cs + cross(k, c) * sn + k * dot(k, c) * (1.0 - cs);
    }

    fragment float4 kaleido_fragment(VOut in [[stage_in]],
                                     constant Uniforms &u [[buffer(0)]],
                                     texture2d<float> texA [[texture(0)]],
                                     texture2d<float> texB [[texture(1)]]) {
        constexpr sampler smp(coord::normalized, address::mirrored_repeat, filter::linear, mip_filter::linear);
        float2 res = float2(u.width, u.height);
        float2 p = (in.position.xy - 0.5 * res) / u.height;   // centred, y down; screen height = 1
        p.y = -p.y;

        float t = u.mixAmount;
        float sA, sB;
        float3 col;
        if (u.hasB == 0) {
            float2 q = kaleidoPoint(p, u, 1.0, 0.0, sA);
            col = samplePhoto(texA, smp, q, u.aspectA, sA, u);
        } else {
            float zoomA = 1.0, zoomB = 1.0, extra = 0.0;
            if (u.transition == 3) { zoomA = 1.0 + 1.6 * t; zoomB = 1.0 / (1.0 + 1.6 * (1.0 - t)); }
            if (u.transition == 5) { extra = u.spinBoost; }
            float2 qa = kaleidoPoint(p, u, zoomA, extra, sA);
            float2 qb = kaleidoPoint(p, u, zoomB, extra, sB);
            float3 a = samplePhoto(texA, smp, qa, u.aspectA, sA, u);
            float3 b = samplePhoto(texB, smp, qb, u.aspectB, sB, u);

            float m;
            float w = 0.18;
            float halfDiag = 0.5 * length(float2(res.x / res.y, 1.0));
            float r = length(p) / halfDiag;
            if (u.transition == 1) {
                m = 1.0 - smoothstep(t * (1.0 + w) - w, t * (1.0 + w), r);
            } else if (u.transition == 2) {
                float ang = (atan2(p.y, p.x) / (2.0 * PI) + 0.5);
                float x = 0.75 * ang + 0.25 * r;
                m = 1.0 - smoothstep(t * (1.0 + w) - w, t * (1.0 + w), x);
            } else if (u.transition == 4) {
                int n = max(u.segments, 3);
                float seg = 2.0 * PI / float(n);
                float idx = floor((atan2(p.y, p.x) + PI) / seg);
                float h = hash11(idx + 1.0 + u.time * 0.0);
                float local = clamp((t * 1.6 - h * 0.6) / 1.0, 0.0, 1.0);
                m = smoothstep(0.0, 1.0, local);
            } else if (u.transition == 3) {
                m = smoothstep(0.15, 0.85, t);
            } else {
                m = smoothstep(0.0, 1.0, t);
            }
            col = mix(a, b, m);
        }

        // Grade: hue rotation, saturation, vignette, a hair of dither against banding in soft areas.
        col = hueRotate(col, u.hue);
        float luma = dot(col, float3(0.2126, 0.7152, 0.0722));
        col = mix(float3(luma), col, u.saturation);
        float vr = length(p) / (0.5 * length(float2(res.x / res.y, 1.0)));
        col *= 1.0 - u.vignette * smoothstep(0.35, 1.05, vr);
        col += (hash21(in.position.xy + fract(u.time)) - 0.5) / 255.0;
        return float4(saturate(col), 1.0);
    }
    """#
}
