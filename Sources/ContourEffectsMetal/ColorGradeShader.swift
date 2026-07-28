// SPDX-FileCopyrightText: 2026 Daito Manabe
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension ColorGradeEffect {
    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct RasterOut {
        float4 position [[position]];
        float2 uv;
    };

    struct ColorGradeUniforms {
        float4 controls0;
        float4 controls1;
        float4 controls2;
        float4 viewport;
        float4 lutControls;
        float4 lutDomainMinimum;
        float4 lutDomainMaximum;
    };

    constexpr sampler linearSampler(
        coord::normalized,
        address::clamp_to_edge,
        filter::linear
    );

    vertex RasterOut contourFullScreenVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[6] = {
            float2(-1.0f, -1.0f), float2( 1.0f, -1.0f), float2(-1.0f,  1.0f),
            float2( 1.0f, -1.0f), float2( 1.0f,  1.0f), float2(-1.0f,  1.0f)
        };
        const float2 uvs[6] = {
            float2(0.0f, 1.0f), float2(1.0f, 1.0f), float2(0.0f, 0.0f),
            float2(1.0f, 1.0f), float2(1.0f, 0.0f), float2(0.0f, 0.0f)
        };
        RasterOut out;
        out.position = float4(positions[vertexID], 0.0f, 1.0f);
        out.uv = uvs[vertexID];
        return out;
    }

    float contourGradeHash(float2 p) {
        float2 cell = floor(max(p, float2(0.0f)));
        float seed = cell.x * 0.17320508f + cell.y * 0.14142136f;
        float wave = sin(seed * 113.0f) + cos(seed * 71.0f);
        return fract(wave * 437.0f);
    }

    float3 contourFilmCurve(float3 color) {
        float3 positive = max(color, 0.0f);
        float3 compressed = positive / (1.0f + positive);
        float3 softLift = sqrt(compressed);
        return saturate(mix(compressed, softLift, 0.22f) * 1.45f);
    }

    float3 contourSRGBToLinear(float3 color) {
        float3 value = max(color, 0.0f);
        float3 low = value / 12.92f;
        float3 high = pow((value + 0.055f) / 1.055f, float3(2.4f));
        return select(low, high, value > 0.04045f);
    }

    float3 contourLinearToSRGB(float3 color) {
        float3 value = max(color, 0.0f);
        float3 low = value * 12.92f;
        float3 high = 1.055f * pow(value, float3(1.0f / 2.4f)) - 0.055f;
        return select(low, high, value > 0.0031308f);
    }

    fragment half4 contourColorGradeFragment(
        RasterOut in [[stage_in]],
        texture2d<float, access::sample> source [[texture(0)]],
        texture3d<float, access::sample> lut [[texture(1)]],
        constant ColorGradeUniforms& grade [[buffer(0)]]
    ) {
        float4 sampled = source.sample(linearSampler, in.uv);
        float3 color = sampled.rgb;
        if (grade.viewport.w < 0.5f) {
            return half4(half3(color), half(sampled.a));
        }

        float exposure = clamp(grade.controls0.x, -3.0f, 3.0f);
        float brightness = clamp(grade.controls0.y, -0.5f, 0.5f);
        float contrast = clamp(grade.controls0.z, 0.5f, 2.0f);
        float saturation = clamp(grade.controls0.w, 0.0f, 2.0f);
        float temperature = clamp(grade.controls1.x, -1.0f, 1.0f);
        float tint = clamp(grade.controls1.y, -1.0f, 1.0f);
        float gamma = clamp(grade.controls1.z, 0.5f, 2.0f);
        float blackLift = clamp(grade.controls1.w, 0.0f, 0.5f);
        float highlightRolloff = saturate(grade.controls2.x);
        float curveAmount = saturate(grade.controls2.y);
        float grainAmount = saturate(grade.controls2.z);
        float vignetteAmount = saturate(grade.controls2.w);

        color = max(color * exp2(exposure) + brightness, 0.0f);
        color *= float3(
            1.0f + temperature * 0.12f + tint * 0.025f,
            1.0f - abs(temperature) * 0.018f - tint * 0.055f,
            1.0f - temperature * 0.12f + tint * 0.025f
        );
        float luma = dot(color, float3(0.2126f, 0.7152f, 0.0722f));
        color = luma + (color - luma) * saturation;
        color = (color - 0.18f) * contrast + 0.18f;
        color = pow(max(color, 0.0f), float3(1.0f / gamma));
        color += (1.0f - saturate(color)) * blackLift * 0.20f;

        float lutMix = saturate(grade.lutControls.x);
        float lutSize = grade.lutControls.y;
        if (grade.lutControls.w > 0.5f && lutMix > 0.0001f && lutSize >= 2.0f) {
            bool linearInput = grade.lutControls.z > 0.5f;
            float3 lutInput = linearInput ? contourSRGBToLinear(color) : color;
            float3 domainMinimum = grade.lutDomainMinimum.xyz;
            float3 domainRange = max(
                grade.lutDomainMaximum.xyz - domainMinimum,
                float3(0.000001f)
            );
            float3 normalized = saturate((lutInput - domainMinimum) / domainRange);
            float3 coordinate = (normalized * (lutSize - 1.0f) + 0.5f) / lutSize;
            float3 transformed = lut.sample(linearSampler, coordinate).rgb;
            if (linearInput) {
                transformed = contourLinearToSRGB(transformed);
            }
            color = mix(color, transformed, lutMix);
        }

        float3 rolled = color / (1.0f + max(color, 0.0f) * 0.72f);
        color = mix(color, rolled, highlightRolloff);
        color = mix(color, contourFilmCurve(color), curveAmount);

        if (grainAmount > 0.0001f) {
            float frame = floor(grade.viewport.x * 24.0f);
            float grain = contourGradeHash(floor(in.position.xy) + frame * 17.0f) - 0.5f;
            float tone = 1.0f - smoothstep(0.55f, 1.0f, luma);
            color += grain * grainAmount * (0.08f + tone * 0.08f);
        }
        if (vignetteAmount > 0.0001f) {
            float2 q = in.uv - 0.5f;
            q.x *= max(grade.viewport.y / max(grade.viewport.z, 1.0f), 1.0f);
            float edge = smoothstep(0.30f, 1.05f, length(q));
            color *= 1.0f - edge * vignetteAmount * 0.42f;
        }
        return half4(half3(saturate(color)), half(sampled.a));
    }
    """
}
