// The kaleidoscope shader, compiled at launch (a SwiftPM executable has no .metallib to load).
enum Shaders {
    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float width, height;
        float rotation;      // radians, mirror pattern angle
        float sourceRotation;// radians, turns the photo inside the mirrors
        float panX, panY;    // photo-space drift plus the user's drag (units of photo height)
        float zoom;
        float twist;
        float hue;           // radians
        float saturation;
        float vignette;
        float time;
        float aspectA, aspectB;
        float mixAmount;     // 0...1 transition progress (raw)
        float morph;         // 0...1 cross-fade from `segments` to `segmentsMorph` (dynamic mirrors)
        float outline;       // 0...1 thickness of black lines along the pattern's mirrors and tile edges
        int segments;       // mirrors of the outgoing photo (A)
        int mode;            // 0 radial, 1 hex, 2 fractal (A)
        int transition;      // 0 dissolve 1 iris 3 zoom 4 segments
        int hasB;
        int segmentsB;       // the incoming photo (B) can arrive with a different look
        int modeB;
        int original;        // 1 = show the photo itself, uncut (the preview's "Original" tab)
        int segmentsMorph;   // the mirror count being faded towards
        int outlines;        // 1 = draw the pattern's mirror and tile lines in red (editor previews)
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

    // Folds the plane into mirrored wedges. The folded angle is the distance to the nearest wedge edge, so
    // every edge is a mirror whatever the wedge widths. That lets the count be fractional: for nf = n + t
    // there are n wedges of 2*PI/nf plus one extra wedge that grows from nothing (t = 0) to full width
    // (t = 1). Dynamic mirrors use this to "open up" a new mirror instead of cross-fading.
    float2 foldRadial(float2 p, float nf) {
        float n = floor(nf + 1e-4);
        float w = 2.0 * PI / max(nf, 1.0);
        float r = length(p);
        float a = atan2(p.y, p.x);
        a = a - 2.0 * PI * floor(a / (2.0 * PI));          // 0 ... 2*PI
        float k = floor(a / w);
        float width = k < n ? w : max(2.0 * PI - n * w, 1e-6);
        float local = k < n ? a - k * w : a - n * w;
        a = min(local, width - local);
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

    // Triangle wave in [0, 1] with period 2: tiles that mirror at every whole number, with no seams.
    float2 triWave(float2 x) { return abs(fract(x * 0.5) * 2.0 - 1.0); }

    float hash11(float n) { return fract(sin(n * 127.1) * 43758.5453); }
    float hash21(float2 p) { return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453); }

    // Maps a screen point (centred, units of screen height) to a point in photo space.
    // `scale` is how many photo-space units one screen unit covers at this point (for the mip level).
    // `segments` may be fractional while dynamic mirrors open up a new mirror (or tiles grow denser).
    // `shade` darkens the result: cube faces and tile outlines (1 = untouched).
    float2 kaleidoPoint(float2 p, constant Uniforms &u, float zoomMul, int mode, float segments, thread float &scale,
                        thread float &shade) {
        float zoom = u.zoom * zoomMul;
        p = rot2(p, u.rotation);
        p = rot2(p, u.twist * length(p));
        scale = 1.0;
        shade = 1.0;
        float2 f;
        if (mode == 1) {
            // Tiled: the lattice is rotated as a whole so the cell fold keeps lining up with cell edges.
            float density = 0.9 + 0.3 * segments;
            f = foldRadial(hexLocal(p * density), 6.0);
            scale = density;   // photo units covered by one screen unit
        } else if (mode == 2) {
            f = foldRadial(p, segments);
            float k = 1.0;
            for (int i = 0; i < 3; i++) {
                float fi = float(i);
                f = abs(f) - float2(0.20 + 0.06 * sin(u.time * 0.21 + fi * 1.7), 0.10 + 0.05 * cos(u.time * 0.17 + fi));
                f = rot2(f, 0.55 + 0.25 * sin(u.time * 0.13 + fi * 2.1));
                f *= 1.28;
                k *= 1.28;
            }
            scale = k;
        } else if (mode == 3) {
            // Square tiles (p4m): mirror both axes, then the diagonal, so every edge and diagonal is a mirror.
            float density = 0.6 + 0.25 * segments;
            float2 m = triWave(p * density);
            if (m.y > m.x) m = m.yx;
            f = m - 0.5;
            scale = density;
        } else if (mode == 4) {
            // Mirror grid (pmm): a plain hall of mirrors with 3:2 cells, no diagonal fold.
            float density = 0.6 + 0.25 * segments;
            float2 m = triWave(p * density * float2(1.0, 1.5));
            f = (m - 0.5) * float2(1.0, 0.6667);
            scale = density;
        } else if (mode == 5) {
            // Spiral: mirror tiles laid out in log-polar space, so they shrink towards the centre like a tunnel.
            // Around the circle each arm is mirrored about its own centre line (like the classic wedges), so the
            // arms meet edge to edge with no seam where the angle wraps, whatever the count, odd or even.
            float n = max(2.0, floor(segments + 0.001));
            float k = n / (2.0 * PI);
            float r = max(length(p), 1e-4);
            // Flows inward as the pattern turns; 2/pi keeps the wrap of `rotation` a whole number of tiles.
            float2 lp = float2(log(r) * k + u.rotation * (2.0 / PI), atan2(p.y, p.x) * k);
            f = (float2(triWave(lp).x, abs(fract(lp.y) - 0.5) * 2.0) - 0.5) * 0.8;
            scale = 0.8 * k / r;
        } else if (mode == 6) {
            // Triangle: the classic toy, three mirrors forming an equilateral triangle (p3m1). Move into one
            // 3 x sqrt(3) period of the pattern, then reflect across whichever triangle edge the point is
            // outside of until it lands in the triangle.
            float density = 0.6 + 0.25 * segments;
            const float s3 = 1.7320508;
            float2 t = p * density * 1.6;
            t -= float2(3.0, s3) * floor(t / float2(3.0, s3));
            for (int i = 0; i < 16; i++) {
                if (t.y < 0.0) { t.y = -t.y; continue; }
                float2 n1 = float2(0.8660254, -0.5);                      // edge through (0,0) at 60 degrees
                float d1 = dot(t, n1);
                if (d1 < 0.0) { t -= 2.0 * d1 * n1; continue; }
                float2 n2 = float2(-0.8660254, -0.5);                     // edge through (1,0) at 120 degrees
                float d2 = dot(t - float2(1.0, 0.0), n2);
                if (d2 < 0.0) { t -= 2.0 * d2 * n2; continue; }
                break;
            }
            f = (t - float2(0.5, 0.2886751)) * 0.9;
            scale = density * 1.6 * 0.9;
        } else if (mode == 7) {
            // Diamonds (the rhombille tiling Escher used for his cubes, kept flat): each hexagon splits into three
            // diamonds. Each diamond carries its own little mandala (an 8-mirror fold in the diamond's own skewed
            // coordinates) that slowly turns, alternating direction, and each of the three orientations looks at
            // a different part of the photo.
            float density = 0.5 + 0.2 * segments;
            float2 d = hexLocal(p * density);
            const float R = 0.5773503;                                    // hexagon corner radius
            float a = atan2(d.y, d.x);
            a = a - 2.0 * PI * floor(a / (2.0 * PI));                     // 0 ... 2*PI
            // Corners at 90, 210 and 330 degrees bound the three faces.
            int face = (a >= PI / 2.0 && a < 7.0 * PI / 6.0) ? 1 : ((a >= 7.0 * PI / 6.0 && a < 11.0 * PI / 6.0) ? 2 : 0);
            float a0 = face == 0 ? -PI / 6.0 : (face == 1 ? PI / 2.0 : 7.0 * PI / 6.0);
            float2 e1 = R * float2(cos(a0), sin(a0));
            float2 e2 = R * float2(cos(a0 + 2.0 * PI / 3.0), sin(a0 + 2.0 * PI / 3.0));
            // Face coordinates: d = s*e1 + t*e2 with s, t in 0...1.
            float det = e1.x * e2.y - e1.y * e2.x;
            float2 st = float2(d.x * e2.y - d.y * e2.x, e1.x * d.y - e1.y * d.x) / det;
            float2 c = st - 0.5;
            // A whole-number multiple of `rotation` keeps its wrap at 2*pi invisible.
            c = rot2(c, u.rotation * 3.0);
            f = foldRadial(c, 8.0) * 0.9;
            scale = density * 0.9 / R;
        } else {
            f = foldRadial(p, segments);
        }
        float2 q = rot2(f, u.sourceRotation) / zoom + float2(u.panX, u.panY);
        scale /= zoom;
        return q;
    }

    // Distance (in screen heights) from a screen point to the nearest mirror or tile line of the pattern, for the
    // "Pattern lines" overlay. Mirrors the geometry of kaleidoPoint, one mode at a time.
    float lineDistance(float2 p, constant Uniforms &u, int mode, float segments) {
        p = rot2(p, u.rotation);
        p = rot2(p, u.twist * length(p));
        if (mode == 1 || mode == 7) {
            float density = mode == 1 ? 0.9 + 0.3 * segments : 0.5 + 0.2 * segments;
            float2 d = hexLocal(p * density);
            float cell = 0.5 - max(abs(d.x), max(abs(dot(d, float2(0.5, 0.8660254))), abs(dot(d, float2(-0.5, 0.8660254)))));
            float inner;
            if (mode == 1) {
                // Six mirrors through the cell centre, one every 30 degrees.
                float w = PI / 6.0;
                float a = atan2(d.y, d.x);
                a = a - w * floor(a / w);
                inner = length(d) * sin(min(a, w - a));
            } else {
                // The three cube edges from the centre to alternate corners (90, 210 and 330 degrees).
                inner = 1e3;
                for (int i = 0; i < 3; i++) {
                    float ang = PI / 2.0 + float(i) * 2.0 * PI / 3.0;
                    float2 v = float2(cos(ang), sin(ang));
                    if (dot(d, v) > 0.0) inner = min(inner, abs(d.x * v.y - d.y * v.x));
                }
            }
            return min(cell, inner) / density;
        }
        if (mode == 3) {
            float density = 0.6 + 0.25 * segments;
            float2 g = p * density;
            float2 fr = abs(g - round(g));
            float2 m = triWave(g);
            return min(min(fr.x, fr.y), abs(m.x - m.y) * 0.7071068) / density;
        }
        if (mode == 4) {
            float density = 0.6 + 0.25 * segments;
            float2 g = p * density * float2(1.0, 1.5);
            float2 fr = abs(g - round(g));
            return min(fr.x / density, fr.y / (1.5 * density));
        }
        if (mode == 5) {
            float n = max(2.0, floor(segments + 0.001));
            float k = n / (2.0 * PI);
            float r = max(length(p), 1e-4);
            float2 lp = float2(log(r) * k + u.rotation * (2.0 / PI), atan2(p.y, p.x) * k);
            // Rings at every whole step out; around the circle, arm edges and each arm's centre mirror.
            float fx = abs(lp.x - round(lp.x));
            float fy = abs(lp.y * 2.0 - round(lp.y * 2.0)) * 0.5;
            return min(fx, fy) * r / k;
        }
        if (mode == 6) {
            float density = 0.6 + 0.25 * segments;
            const float s3 = 1.7320508;
            float2 t = p * density * 1.6;
            t -= float2(3.0, s3) * floor(t / float2(3.0, s3));
            float2 n1 = float2(0.8660254, -0.5), n2 = float2(-0.8660254, -0.5);
            for (int i = 0; i < 16; i++) {
                if (t.y < 0.0) { t.y = -t.y; continue; }
                float d1 = dot(t, n1);
                if (d1 < 0.0) { t -= 2.0 * d1 * n1; continue; }
                float d2 = dot(t - float2(1.0, 0.0), n2);
                if (d2 < 0.0) { t -= 2.0 * d2 * n2; continue; }
                break;
            }
            return min(t.y, min(dot(t, n1), dot(t - float2(1.0, 0.0), n2))) / (density * 1.6);
        }
        // Classic and fractal: the wedge edges and the mirror down the middle of each wedge.
        float n = floor(segments + 1e-4);
        float w = 2.0 * PI / max(segments, 1.0);
        float r = length(p);
        float a = atan2(p.y, p.x);
        a = a - 2.0 * PI * floor(a / (2.0 * PI));
        float k = floor(a / w);
        float width = k < n ? w : max(2.0 * PI - n * w, 1e-6);
        float local = k < n ? a - k * w : a - n * w;
        float ang = min(min(local, width - local), abs(local - 0.5 * width));
        float dist = r * sin(min(ang, PI / 2.0));
        if (mode == 2) {
            // The fractal's extra folds: every abs() is a mirror along an axis of the current frame.
            float2 f = foldRadial(p, segments);
            float s = 1.0;
            for (int i = 0; i < 3; i++) {
                float fi = float(i);
                dist = min(dist, min(abs(f.x), abs(f.y)) / s);
                f = abs(f) - float2(0.20 + 0.06 * sin(u.time * 0.21 + fi * 1.7), 0.10 + 0.05 * cos(u.time * 0.17 + fi));
                f = rot2(f, 0.55 + 0.25 * sin(u.time * 0.13 + fi * 2.1));
                f *= 1.28;
                s *= 1.28;
            }
        }
        return dist;
    }

    // Multiplier that paints black lines along the pattern (1 = no line here).
    float outlineFactor(float2 p, constant Uniforms &u, int mode, float segments) {
        if (u.outline < 0.05) return 1.0;
        float px = 1.0 / u.height;
        float w = px * 0.75 + u.outline * 0.006;           // half the line width, in screen heights
        return mix(0.06, 1.0, smoothstep(w, w + px * 1.5, lineDistance(p, u, mode, segments)));
    }

    float3 samplePhoto(texture2d<float> tex, sampler smp, float2 q, float aspect, float scale, constant Uniforms &u) {
        // Photo space: height = 1, width = aspect. Mirrored repeat extends it without edges.
        float2 uv = float2(q.x / aspect, q.y) + 0.5;
        float texels = (scale / u.height) * float(tex.get_height());
        float lod = max(log2(max(texels, 1.0)), 0.0);
        return tex.sample(smp, uv, level(lod)).rgb;
    }

    // The photo as it is: fitted inside the view, upright, black around it.
    float3 samplePlain(texture2d<float> tex, sampler smp, float2 p, float aspect, float viewAspect) {
        float s = min(viewAspect / aspect, 1.0);          // photo height on screen, in screen heights
        float2 q = p / s;                                  // photo space: height 1, width aspect
        if (abs(q.x) > 0.5 * aspect || abs(q.y) > 0.5) return float3(0.0);
        float2 uv = float2(q.x / aspect + 0.5, 0.5 - q.y);
        return tex.sample(smp, uv, level(0.0)).rgb;
    }

    float3 hueRotate(float3 c, float a) {
        const float3 k = float3(0.57735027);
        float cs = cos(a), sn = sin(a);
        return c * cs + cross(k, c) * sn + k * dot(k, c) * (1.0 - cs);
    }

    // The kaleidoscope (with any photo transition) at a given extra magnification.
    float3 kaleidoColor(float2 p, constant Uniforms &u, texture2d<float> texA, texture2d<float> texB, sampler smp,
                        float zoomMul) {
        float2 res = float2(u.width, u.height);
        float t = u.mixAmount;
        float sA, sB;
        float3 col;
        float hA, hB;
        if (u.hasB == 0) {
            float e = smoothstep(0.0, 1.0, u.morph);
            if (u.mode == 5 && u.morph > 0.0) {
                // The spiral needs a whole number of arms, so it cross-fades between counts.
                float2 q = kaleidoPoint(p, u, zoomMul, u.mode, float(u.segments), sA, hA);
                float2 q2 = kaleidoPoint(p, u, zoomMul, u.mode, float(u.segmentsMorph), sB, hB);
                col = mix(samplePhoto(texA, smp, q, u.aspectA, sA, u) * hA, samplePhoto(texA, smp, q2, u.aspectA, sB, u) * hB, e);
            } else {
                // Everything else opens up: the count slides continuously from one whole number to the next.
                float segs = mix(float(u.segments), float(u.segmentsMorph), e);
                float2 q = kaleidoPoint(p, u, zoomMul, u.mode, segs, sA, hA);
                col = samplePhoto(texA, smp, q, u.aspectA, sA, u) * hA;
            }
            float segsNow = u.mode == 5 ? float(u.segments) : mix(float(u.segments), float(u.segmentsMorph), e);
            col *= outlineFactor(p, u, u.mode, segsNow);
        } else {
            float zoomA = zoomMul, zoomB = zoomMul;
            if (u.transition == 3) {
                // Zoom through: ease in and out (zero speed at both ends) and zoom geometrically, so the
                // incoming photo settles instead of stopping dead.
                float e = t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
                const float span = 0.9;   // ln of the total zoom travelled by each photo
                zoomA *= exp(span * e);
                zoomB *= exp(-span * (1.0 - e));
            }
            float2 qa = kaleidoPoint(p, u, zoomA, u.mode, float(u.segments), sA, hA);
            float2 qb = kaleidoPoint(p, u, zoomB, u.modeB, float(u.segmentsB), sB, hB);
            float3 a = samplePhoto(texA, smp, qa, u.aspectA, sA, u) * hA * outlineFactor(p, u, u.mode, float(u.segments));
            float3 b = samplePhoto(texB, smp, qb, u.aspectB, sB, u) * hB * outlineFactor(p, u, u.modeB, float(u.segmentsB));

            float m;
            float w = 0.18;
            float halfDiag = 0.5 * length(float2(res.x / res.y, 1.0));
            float r = length(p) / halfDiag;
            if (u.transition == 1) {
                m = 1.0 - smoothstep(t * (1.0 + w) - w, t * (1.0 + w), r);
            } else if (u.transition == 4) {
                int n = max(u.segmentsB, 3);
                float seg = 2.0 * PI / float(n);
                float idx = floor((atan2(p.y, p.x) + PI) / seg);
                float h = hash11(idx + 1.0);
                float local = clamp(t * 1.6 - h * 0.6, 0.0, 1.0);
                m = smoothstep(0.0, 1.0, local);
            } else if (u.transition == 3) {
                m = smoothstep(0.15, 0.85, t);
            } else {
                m = smoothstep(0.0, 1.0, t);
            }
            col = mix(a, b, m);
        }
        return col;
    }

    fragment float4 kaleido_fragment(VOut in [[stage_in]],
                                     constant Uniforms &u [[buffer(0)]],
                                     texture2d<float> texA [[texture(0)]],
                                     texture2d<float> texB [[texture(1)]]) {
        constexpr sampler smp(coord::normalized, address::mirrored_repeat, filter::linear, mip_filter::linear);
        float2 res = float2(u.width, u.height);
        float2 p = (in.position.xy - 0.5 * res) / u.height;   // centred, y down; screen height = 1
        p.y = -p.y;

        if (u.original == 1) {
            float3 a = samplePlain(texA, smp, p, u.aspectA, res.x / res.y);
            if (u.hasB == 1) {
                float3 b = samplePlain(texB, smp, p, u.aspectB, res.x / res.y);
                a = mix(a, b, smoothstep(0.0, 1.0, u.mixAmount));
            }
            return float4(a, 1.0);
        }

        float3 col = kaleidoColor(p, u, texA, texB, smp, 1.0);

        // Grade: hue rotation, saturation, vignette, a hair of dither against banding in soft areas.
        col = hueRotate(col, u.hue);
        float luma = dot(col, float3(0.2126, 0.7152, 0.0722));
        if (u.saturation > 1.0) {
            // Vibrance-style boost: dull colours gain the most, already-vivid ones barely move, so bright
            // channels don't clip flat and smear away detail.
            float chroma = max(col.r, max(col.g, col.b)) - min(col.r, min(col.g, col.b));
            col = mix(float3(luma), col, 1.0 + (u.saturation - 1.0) * 1.6 * (1.0 - chroma));
        } else {
            col = mix(float3(luma), col, u.saturation);
        }
        float vr = length(p) / (0.5 * length(float2(res.x / res.y, 1.0)));
        col *= 1.0 - u.vignette * smoothstep(0.35, 1.05, vr);
        col += (hash21(in.position.xy + fract(u.time)) - 0.5) / 255.0;

        if (u.outlines == 1) {
            // Pattern lines: dim the photo and trace every mirror and tile edge in red, about 1.5 px wide.
            float segsNow = u.mode == 5 ? float(u.segments)
                                        : mix(float(u.segments), float(u.segmentsMorph), smoothstep(0.0, 1.0, u.morph));
            float d = lineDistance(p, u, u.mode, segsNow);
            float px = 1.0 / u.height;
            float line = 1.0 - smoothstep(px * 0.6, px * 1.8, d);
            col = mix(col * 0.45, float3(1.0, 0.18, 0.12), line);
        }
        return float4(saturate(col), 1.0);
    }
    """#
}
