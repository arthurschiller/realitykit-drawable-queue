//
//  CustomMaterialShaders.metal
//  CustomMaterialShaders
//
//  Created by Arthur Schiller on 12.08.21.
//

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

constexpr sampler samplerBilinear(coord::normalized,
                                  address::repeat,
                                  filter::linear,
                                  mip_filter::nearest);

[[visible]]
void customMaterialSurfaceModifier(realitykit::surface_parameters params) {
    auto surface = params.surface();
    
    float2 uv = params.geometry().uv0();

    // Flip uvs vertically.
    uv.y = 1.0 - uv.y;

    half4 color = params.textures().custom().sample(samplerBilinear, uv);
    
    // support for partially transparent textures
    if (color.a == 0) {
        discard_fragment();
    }
    
    surface.set_emissive_color(color.rgb);
}
