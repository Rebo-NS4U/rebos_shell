#version 440
#extension GL_GOOGLE_include_directive : require
#include "dither_pattern.glsl"
#include "outline_position.glsl"
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec4 corners;
    float strokeWidth;
    float cellSize;
    vec4 edgeColor;
    vec4 baseColor;
    vec4 surfaceDotColor;
    float nativeStrokeWidth;
} ubuf;
void main() {
    vec2 pixel=qt_TexCoord0*ubuf.size;
    vec2 p=pixel-ubuf.size*0.5;
    vec4 radii=clamp(ubuf.corners,vec4(0.0),vec4(min(ubuf.size.x,ubuf.size.y)*0.5));
    float radius=p.y<0.0 ? (p.x<0.0 ? radii.x : radii.y) : (p.x<0.0 ? radii.z : radii.w);
    vec2 q=abs(p)-(ubuf.size*0.5-radius);
    float d=length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-radius;
    float aa=max(fwidth(d)*0.5,0.001);
    float band=min(ubuf.strokeWidth,min(ubuf.size.x,ubuf.size.y));
    float outer=1.0-smoothstep(-aa,aa,d);
    float visibleBand=outer*smoothstep(-band-aa,-band+aa,d);
    // Wider native focus borders are erased with the matching fill, rather
    // than changing the visible width of this shared border treatment.
    float clearBand=max(band,ubuf.nativeStrokeWidth);
    float coverage=outer*smoothstep(-clearBand-aa,-clearBand+aa,d);
    float inset=band*0.5;
    vec2 box=max(ubuf.size-vec2(band),vec2(0.001));
    vec4 r=max(radii-vec4(inset),vec4(0.0));
    float perimeter=max(0.001,2.0*(box.x+box.y)+(HALF_PI-2.0)*(r.x+r.y+r.z+r.w));
    float pairs=max(1.0,floor(perimeter/(2.0*ubuf.cellSize)+0.5));
    float pitch=perimeter/(2.0*pairs);
    float s=outlinePosition(pixel-vec2(inset),box,r);
    float grain=mod(floor(s/pitch),2.0);
    float depth=clamp(-d/max(band,0.001),0.0,1.0);
    vec3 background=mix(ubuf.baseColor.rgb,ubuf.surfaceDotColor.rgb,ditherMask(pixel,ubuf.cellSize));
    vec3 edge=mix(background,ubuf.edgeColor.rgb,ubuf.edgeColor.a);
    // A quiet continuous base keeps the full width readable. Regular pixel
    // accents follow the contour, without scattered inward/outward specks.
    float texture=0.75*(0.65+0.35*grain)*(1.0-0.15*depth);
    vec3 color=mix(background,edge,visibleBand*texture);
    float alpha=coverage*ubuf.qt_Opacity;
    fragColor=vec4(color*alpha,alpha);
}
