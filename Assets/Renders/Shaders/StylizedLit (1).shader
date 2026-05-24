Shader "Custom/StylizedLit"
{
    Properties
    {
        // ── Base ──────────────────────────────────────────────────────────────
        _BaseColor          ("Base Color",          Color)  = (1, 1, 1, 1)
        _BaseMap            ("Base Map (Albedo)",   2D)     = "white" {}

        // ── Cell Shading ──────────────────────────────────────────────────────
        [Header(Cell Shading)]
        _ShadowColor        ("Shadow Color",        Color)  = (0.2, 0.2, 0.35, 1)
        _ShadowThreshold    ("Shadow Threshold",    Range(0, 1))    = 0.5
        _ShadowSmoothness   ("Shadow Smoothness",   Range(0, 0.2))  = 0.02
        // Optional mid-tone band
        _MidtoneColor       ("Midtone Color",       Color)  = (0.6, 0.6, 0.75, 1)
        _MidtoneThreshold   ("Midtone Threshold",   Range(0, 1))    = 0.75
        _MidtoneSmoothness  ("Midtone Smoothness",  Range(0, 0.2))  = 0.02

        // ── World-Position Gradient ───────────────────────────────────────────
        [Header(World Gradient)]
        _GradientColorLow   ("Gradient Color Low",  Color)  = (0.1, 0.15, 0.5,  1)
        _GradientColorHigh  ("Gradient Color High", Color)  = (1.0, 0.85, 0.4,  1)
        _GradientMinY       ("Gradient Min Y (world)",  Float) = 0.0
        _GradientMaxY       ("Gradient Max Y (world)",  Float) = 3.0
        _GradientStrength   ("Gradient Strength",   Range(0, 1)) = 0.4

        // ── Rim / Specular ────────────────────────────────────────────────────
        [Header(Rim Light)]
        _RimColor           ("Rim Color",           Color)  = (1, 1, 1, 1)
        _RimThreshold       ("Rim Threshold",       Range(0, 1))   = 0.5
        _RimSmoothness      ("Rim Smoothness",      Range(0, 0.2)) = 0.03
        _RimStrength        ("Rim Strength",        Range(0, 2))   = 0.6
    }

    SubShader
    {
        Tags
        {
            "RenderType"      = "Opaque"
            "RenderPipeline"  = "UniversalPipeline"
            "Queue"           = "Geometry"
        }
        LOD 300

        // ══════════════════════════════════════════════════════════════════════
        //  MAIN FORWARD PASS
        // ══════════════════════════════════════════════════════════════════════
        Pass
        {
            Name "StylizedForward"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag

            // URP feature keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // ── Uniforms ──────────────────────────────────────────────────────
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;

                float4 _ShadowColor;
                float  _ShadowThreshold;
                float  _ShadowSmoothness;

                float4 _MidtoneColor;
                float  _MidtoneThreshold;
                float  _MidtoneSmoothness;

                float4 _GradientColorLow;
                float4 _GradientColorHigh;
                float  _GradientMinY;
                float  _GradientMaxY;
                float  _GradientStrength;

                float4 _RimColor;
                float  _RimThreshold;
                float  _RimSmoothness;
                float  _RimStrength;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            // ── Structs ───────────────────────────────────────────────────────
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float2 uv           : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
                float3 positionWS   : TEXCOORD1;
                float3 normalWS     : TEXCOORD2;
                float3 viewDirWS    : TEXCOORD3;
                float4 shadowCoord  : TEXCOORD4;
                float  fogFactor    : TEXCOORD5;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            // ── Helper: stepped/smooth cell ramp ─────────────────────────────
            // Returns 0 in shadow region, 1 in lit region, smooth at the edge.
            float CellRamp(float NdotL, float threshold, float smoothness)
            {
                return smoothstep(threshold - smoothness, threshold + smoothness, NdotL);
            }

            // ── Vertex ────────────────────────────────────────────────────────
            Varyings vert(Attributes IN)
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                Varyings OUT = (Varyings)0;
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                VertexPositionInputs posInputs  = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs   normInputs = GetVertexNormalInputs(IN.normalOS);

                OUT.positionCS  = posInputs.positionCS;
                OUT.positionWS  = posInputs.positionWS;
                OUT.normalWS    = normInputs.normalWS;
                OUT.viewDirWS   = GetWorldSpaceViewDir(posInputs.positionWS);
                OUT.uv          = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.shadowCoord = GetShadowCoord(posInputs);
                OUT.fogFactor   = ComputeFogFactor(posInputs.positionCS.z);

                return OUT;
            }

            // ── Fragment ──────────────────────────────────────────────────────
            half4 frag(Varyings IN) : SV_Target
            {
                // ── Sample albedo ─────────────────────────────────────────────
                half4 albedoSample = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half3 albedo       = albedoSample.rgb * _BaseColor.rgb;

                // ── Normals & view ────────────────────────────────────────────
                float3 N = normalize(IN.normalWS);
                float3 V = normalize(IN.viewDirWS);

                // ── Main light ────────────────────────────────────────────────
                Light  mainLight   = GetMainLight(IN.shadowCoord);
                float3 L           = normalize(mainLight.direction);
                float  NdotL_raw   = dot(N, L);                        // -1..1
                float  NdotL       = NdotL_raw * 0.5 + 0.5;            // remap 0..1

                // Combine geometric NdotL with URP shadow attenuation
                float  lightAtten  = mainLight.shadowAttenuation * mainLight.distanceAttenuation;
                float  NdotL_lit   = NdotL * lightAtten;

                // ── Cell ramp: shadow → midtone → lit ─────────────────────────
                float litMask      = CellRamp(NdotL_lit, _ShadowThreshold,  _ShadowSmoothness);
                float midMask      = CellRamp(NdotL_lit, _MidtoneThreshold, _MidtoneSmoothness);

                // Build three-band colour
                half3 shadedColor  = _ShadowColor.rgb;
                half3 midColor     = lerp(shadedColor,  _MidtoneColor.rgb, litMask);
                half3 litColor     = lerp(midColor,     albedo,            midMask);
                half3 cellColor    = litColor * mainLight.color;

                // ── World-position gradient ───────────────────────────────────
                float gradT        = saturate((IN.positionWS.y - _GradientMinY)
                                             / max(_GradientMaxY - _GradientMinY, 0.0001));
                half3 gradColor    = lerp(_GradientColorLow.rgb, _GradientColorHigh.rgb, gradT);

                // Blend gradient on top of cell-shaded colour
                half3 finalColor   = lerp(cellColor, cellColor * gradColor, _GradientStrength);

                // ── Rim light ─────────────────────────────────────────────────
                float NdotV        = saturate(dot(N, V));
                float rimMask      = CellRamp(1.0 - NdotV, _RimThreshold, _RimSmoothness);
                //  Only show rim on lit side
                rimMask           *= litMask;
                finalColor        += _RimColor.rgb * rimMask * _RimStrength;

                // ── Fog ───────────────────────────────────────────────────────
                finalColor = MixFog(finalColor, IN.fogFactor);

                return half4(finalColor, albedoSample.a * _BaseColor.a);
            }
            ENDHLSL
        }

        // ══════════════════════════════════════════════════════════════════════
        //  SHADOW CASTER PASS
        //  Written inline so we own the CBUFFER and _BaseMap_ST is always present.
        // ══════════════════════════════════════════════════════════════════════
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex   ShadowVert
            #pragma fragment ShadowFrag

            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            // Minimal CBUFFER – must contain _BaseMap_ST so TRANSFORM_TEX compiles
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float4 _ShadowColor;
                float  _ShadowThreshold;
                float  _ShadowSmoothness;
                float4 _MidtoneColor;
                float  _MidtoneThreshold;
                float  _MidtoneSmoothness;
                float4 _GradientColorLow;
                float4 _GradientColorHigh;
                float  _GradientMinY;
                float  _GradientMaxY;
                float  _GradientStrength;
                float4 _RimColor;
                float  _RimThreshold;
                float  _RimSmoothness;
                float  _RimStrength;
            CBUFFER_END

            // Shadow bias helpers (replaces the macro from ShadowCasterPass.hlsl)
            float3 _LightDirection;
            float3 _LightPosition;

            struct ShadowAttributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct ShadowVaryings
            {
                float4 positionCS   : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            float4 GetShadowPositionHClip(ShadowAttributes input)
            {
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS   = TransformObjectToWorldNormal(input.normalOS);

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDir = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDir = _LightDirection;
                #endif

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDir));

                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif

                return positionCS;
            }

            ShadowVaryings ShadowVert(ShadowAttributes input)
            {
                ShadowVaryings output = (ShadowVaryings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.positionCS = GetShadowPositionHClip(input);
                return output;
            }

            half4 ShadowFrag(ShadowVaryings input) : SV_TARGET
            {
                return 0;
            }
            ENDHLSL
        }

        // ══════════════════════════════════════════════════════════════════════
        //  DEPTH-ONLY PASS
        //  Same approach: inline CBUFFER so _BaseMap_ST is always declared.
        // ══════════════════════════════════════════════════════════════════════
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask R
            Cull Back

            HLSLPROGRAM
            #pragma vertex   DepthVert
            #pragma fragment DepthFrag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float4 _ShadowColor;
                float  _ShadowThreshold;
                float  _ShadowSmoothness;
                float4 _MidtoneColor;
                float  _MidtoneThreshold;
                float  _MidtoneSmoothness;
                float4 _GradientColorLow;
                float4 _GradientColorHigh;
                float  _GradientMinY;
                float  _GradientMaxY;
                float  _GradientStrength;
                float4 _RimColor;
                float  _RimThreshold;
                float  _RimSmoothness;
                float  _RimStrength;
            CBUFFER_END

            struct DepthAttributes
            {
                float4 positionOS   : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct DepthVaryings
            {
                float4 positionCS   : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            DepthVaryings DepthVert(DepthAttributes input)
            {
                DepthVaryings output = (DepthVaryings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            half4 DepthFrag(DepthVaryings input) : SV_TARGET
            {
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}
