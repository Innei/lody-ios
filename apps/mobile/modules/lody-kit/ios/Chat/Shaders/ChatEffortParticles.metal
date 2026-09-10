#include <metal_stdlib>
using namespace metal;
struct Vertex { float4 position [[position]]; float2 uv; };
vertex Vertex particleVertex(uint id [[vertex_id]]) {
  float2 p = float2((id << 1) & 2, id & 2);
  return {float4(p * 2.0 - 1.0, 0, 1), p};
}
float random(float n) { return fract(sin(n * 127.1) * 43758.5453); }
fragment float4 particleFragment(Vertex in [[stage_in]], constant float4 &u [[buffer(0)]]) {
  float2 p = in.uv * u.yz;
  float thumb = 16.0 + u.w * (u.y - 32.0);
  if (distance(p, float2(thumb, u.z * 0.5)) < 16.0) return float4(0);
  float light = 0.0;
  for (int i = 0; i < 48; i++) {
    bool entry = i >= 32;
    if (entry && u.x > 0.65) continue;
    float seed = float(i) + 1.0;
    // Four loose clusters gather slowly on the left, then accelerate to the right.
    float phase = entry
      ? clamp((u.x - random(seed) * 0.1) / 0.5, 0.0, 1.0)
      : fract(u.x * 0.38 + float(i / 8) * 0.25 + random(seed + 19.0) * 0.13);
    float travel = pow(phase, entry ? 1.6 : 2.6);
    float x = -12.0 + travel * (u.y + 24.0);
    float y = u.z * (0.12 + random(seed + 3.0) * 0.76);
    float2 delta = p - float2(x, y);
    float radius = i % 7 == 0 ? 2.1 : 0.85 + random(seed + 7.0) * 0.65;
    float distanceSquared = dot(delta, delta) / (radius * radius);
    float dotLight = exp(-distanceSquared) + 0.12 * exp(-distanceSquared * 0.3);
    float fade = smoothstep(0.0, 0.1, phase) * (1.0 - smoothstep(0.96, 1.0, phase));
    if (entry) fade *= 1.0 - smoothstep(0.45, 0.65, u.x);
    light += dotLight * fade * (0.85 + 0.15 * sin(u.x * 2.0 + seed));
  }
  float alpha = min(light, 1.0);
  return float4(float3(0.96, 0.94, 1.0) * alpha, alpha);
}
