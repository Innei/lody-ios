import Foundation

// A Metal port of the login visual in LodyAI/Lody
// (packages/components/src/components/login-dither-visual.tsx, Apache-2.0):
// a ray-marched jellyfish thresholded against an 8×8 Bayer matrix, one
// fragment per 3 pt cell. `leave` lifts it out of frame after sign-in.
enum MacJellyfishShader {
  static let vertex = "lodyJellyfishVertex"
  static let fragment = "lodyJellyfishFragment"

  static let source = """
  #include <metal_stdlib>
  using namespace metal;

  struct LodyJellyfishUniforms {
    float2 r;
    float2 m;
    float4 paper;
    float4 ink;
    float t;
    float reveal;
    float leave;
    float pad;
  };

  struct LodyJellyfishOut {
    float4 position [[position]];
  };

  vertex LodyJellyfishOut lodyJellyfishVertex(uint id [[vertex_id]]) {
    float2 p = float2(float((id << 1) & 2), float(id & 2));
    LodyJellyfishOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return out;
  }

  static float2x2 rot(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, -s), float2(s, c));
  }

  static float b2(float2 a) { a = floor(a); return fract(a.x * 0.5 + a.y * a.y * 0.75); }
  static float b4(float2 a) { return b2(0.5 * a) * 0.25 + b2(a); }
  static float b8(float2 a) { return b4(0.5 * a) * 0.25 + b2(a); }

  static float bell(float3 p, float t) {
    float pu = 1.0 + 0.08 * sin(t * 2.2);
    float3 q = p;
    q.xz /= pu;
    q.y *= pu;
    float3 e = q * float3(1.0, 1.3, 1.0);
    float d = max((length(e) - 1.0) / 1.3, -(q.y + 0.05));
    d = max(d, -((length(e - float3(0.0, -0.16, 0.0)) - 0.84) / 1.3));
    d += 0.025 * sin(atan2(q.z, q.x) * 12.0 + t * 3.0) * smoothstep(0.25, -0.05, q.y);
    return d;
  }

  static float tent(float3 p, float t) {
    float d = 1e5;
    for (int i = 0; i < 8; i++) {
      float fi = float(i);
      float a = fi * 0.785 + 0.3;
      float y = clamp(-p.y, 0.0, 2.8);
      float2 o = float2(cos(a), sin(a)) * (0.62 - y * 0.08)
        + float2(sin(y * 2.3 - t * 2.0 + fi), cos(y * 2.0 - t * 1.6 + fi * 1.3)) * 0.13 * y;
      d = min(d, length(p - float3(o.x, -y, o.y)) - 0.05 * (1.0 - y / 3.1));
    }
    float y = clamp(-p.y, 0.0, 1.8);
    d = min(d, length(p - float3(sin(y * 3.0 - t * 1.5) * 0.12 * y, -y, cos(y * 2.5 - t * 1.3) * 0.1 * y)) - 0.15 * (1.0 - y / 2.0));
    return d;
  }

  static float map(float3 p, constant LodyJellyfishUniforms &u) {
    p.y -= 0.14 * sin(u.t * 0.7) + u.leave * u.leave * 5.5;
    p.xz = rot((u.m.x - 0.5) * 1.4 + u.t * 0.15) * p.xz;
    p.yz = rot(0.38 + (u.m.y - 0.5) * 0.6) * p.yz;
    return min(bell(p, u.t), tent(p, u.t));
  }

  fragment float4 lodyJellyfishFragment(LodyJellyfishOut in [[stage_in]], constant LodyJellyfishUniforms &u [[buffer(0)]]) {
    float2 frag = float2(in.position.x, u.r.y - in.position.y);
    float2 sp = frag / u.r;
    float2 uv = (frag - 0.5 * u.r) / u.r.y;
    float aspect = u.r.x / u.r.y;
    float3 ro = float3(-0.75 * clamp((aspect - 1.0) / 0.6, 0.0, 1.0), -0.95, 7.4);
    float3 rd = normalize(float3(uv, -1.7));
    float d = 0.0;
    bool hit = false;
    for (int i = 0; i < 80; i++) {
      float h = map(ro + rd * d, u);
      if (h < 0.002) { hit = true; break; }
      d += h * 0.8;
      if (d > 13.0) break;
    }
    float L = 0.02 + 0.1 * (1.0 - sp.y) + 0.04 * sin(sp.x * 9.0 + u.t * 0.4 + sin(sp.y * 7.0 - u.t * 0.3) * 2.0);
    if (hit) {
      float3 p = ro + rd * d;
      float2 e = float2(0.003, 0.0);
      float3 n = normalize(float3(
        map(p + e.xyy, u) - map(p - e.xyy, u),
        map(p + e.yxy, u) - map(p - e.yxy, u),
        map(p + e.yyx, u) - map(p - e.yyx, u)));
      float dif = max(dot(n, normalize(float3(-0.5, 0.8, 0.6))), 0.0);
      float rim = pow(1.0 - max(dot(n, -rd), 0.0), 2.0);
      L = 0.12 + 0.6 * dif + 0.55 * rim;
    }
    L *= smoothstep(0.0, 1.0, u.reveal * 1.8 - length(uv) * 0.8);
    float on = step(b8(frag) + 0.001, clamp(L, 0.0, 1.0));
    return float4(mix(u.paper.rgb, u.ink.rgb, on), 1.0);
  }
  """
}
