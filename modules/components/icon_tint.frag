#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D source;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tintColor;
} ubuf;

void main() {
    vec4 tex = texture(source, qt_TexCoord0);
    // Qt textures are premultiplied. Recover the artwork color before
    // checking for white, including along translucent antialiased edges.
    vec3 rgb = tex.a > 0.0001 ? tex.rgb / tex.a : vec3(0.0);
    float darkest = min(min(rgb.r, rgb.g), rgb.b);
    float brightest = max(max(rgb.r, rgb.g), rgb.b);
    float white = smoothstep(0.82, 0.94, darkest)
        * (1.0 - smoothstep(0.06, 0.18, brightest - darkest));
    float luminance = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 themed = ubuf.tintColor.rgb * mix(0.35, 1.0, luminance);
    vec3 heavilyTinted = mix(rgb, themed, 0.95);
    vec3 finalColor = mix(heavilyTinted, rgb, white);
    fragColor = vec4(finalColor * tex.a, tex.a) * ubuf.qt_Opacity;
}
