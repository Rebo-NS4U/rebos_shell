#version 440
#extension GL_GOOGLE_include_directive : require
#include "dither_pattern.glsl"
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float cellSize;
    vec4 dotColor;
    vec4 baseColor;
} ubuf;
void main() {
    float mask = ditherMask(qt_TexCoord0 * ubuf.size, ubuf.cellSize);
    vec4 color = mix(ubuf.baseColor, ubuf.dotColor, mask);
    float alpha = color.a * ubuf.qt_Opacity;
    fragColor = vec4(color.rgb * alpha, alpha);
}
