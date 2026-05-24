// StylizedLitHelpers.hlsl
// Drop this in the same folder as StylizedLit.shader.
// Can also be used as a Custom Function node source in Shader Graph.

#ifndef STYLIZED_LIT_HELPERS_INCLUDED
#define STYLIZED_LIT_HELPERS_INCLUDED

// ─────────────────────────────────────────────────────────────────────────────
//  CELL RAMP
//  Input : NdotL       – half-lambert (0..1)
//          threshold   – shadow/lit boundary
//          smoothness  – anti-alias width (0 = hard, 0.02 = slightly soft)
//  Output: 0 = in shadow, 1 = fully lit
// ─────────────────────────────────────────────────────────────────────────────
float CellRamp(float NdotL, float threshold, float smoothness)
{
    return smoothstep(threshold - smoothness, threshold + smoothness, NdotL);
}

// ─────────────────────────────────────────────────────────────────────────────
//  THREE-BAND CELL LIGHTING
//  Returns the cell-shaded colour for one light.
// ─────────────────────────────────────────────────────────────────────────────
half3 CellLight(
    half3  albedo,
    half3  shadowColor,
    half3  midtoneColor,
    float  NdotL,           // half-lambert (0..1) * shadow attenuation
    float  shadowThreshold,
    float  shadowSmooth,
    float  midtoneThreshold,
    float  midtoneSmooth
)
{
    float litMask = CellRamp(NdotL, shadowThreshold,  shadowSmooth);
    float midMask = CellRamp(NdotL, midtoneThreshold, midtoneSmooth);

    half3 col = shadowColor;
    col = lerp(col, midtoneColor, litMask);
    col = lerp(col, albedo,       midMask);
    return col;
}

// ─────────────────────────────────────────────────────────────────────────────
//  WORLD-POSITION GRADIENT
//  Maps worldY linearly between minY and maxY → lerp between two colours.
// ─────────────────────────────────────────────────────────────────────────────
half3 WorldGradient(
    float  worldY,
    half3  colorLow,
    half3  colorHigh,
    float  minY,
    float  maxY
)
{
    float t = saturate((worldY - minY) / max(maxY - minY, 1e-5));
    return lerp(colorLow, colorHigh, t);
}

// ─────────────────────────────────────────────────────────────────────────────
//  CELL RIM LIGHT
// ─────────────────────────────────────────────────────────────────────────────
half3 CellRim(
    float3 N,
    float3 V,
    half3  rimColor,
    float  litMask,         // pass CellRamp result so rim only appears on lit side
    float  rimThreshold,
    float  rimSmooth,
    float  rimStrength
)
{
    float NdotV  = saturate(dot(N, V));
    float rim    = CellRamp(1.0 - NdotV, rimThreshold, rimSmooth);
    rim         *= litMask;
    return rimColor * rim * rimStrength;
}

#endif // STYLIZED_LIT_HELPERS_INCLUDED
