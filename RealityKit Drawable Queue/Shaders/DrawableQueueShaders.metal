//
//  DrawableQueueShaders.metal
//  DrawableQueueShaders
//
//  Created by Arthur Schiller on 12.08.21.
//

#include <metal_stdlib>
using namespace metal;

typedef struct {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
} DrawableVertex;

typedef struct {
    float4 position [[position]];
    float2 texCoord;
} DrawableColorInOut;

vertex DrawableColorInOut drawableQueueVertexShader(DrawableVertex in [[stage_in]]) {
    DrawableColorInOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

fragment half4 drawableQueueFragmentShader(DrawableColorInOut inputVertex [[ stage_in ]],
                              texture2d<float, access::sample> texture [[ texture(0) ]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    half4 color = half4(texture.sample(s, inputVertex.texCoord));
//    color.g *= 0.5;
    return color;
}
