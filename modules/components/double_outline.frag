#version 440
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
} ubuf;
void main() {
    vec2 p = qt_TexCoord0*ubuf.size-ubuf.size*0.5;
    float radius = p.y < 0.0 ? (p.x < 0.0 ? ubuf.corners.x : ubuf.corners.y)
                                : (p.x < 0.0 ? ubuf.corners.z : ubuf.corners.w);
    radius = clamp(radius,0.0,min(ubuf.size.x,ubuf.size.y)*0.5);
    vec2 q = abs(p)-(ubuf.size*0.5-radius);
    float d = length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-radius;
    float aa = max(fwidth(d)*0.5,0.001);
    float line = clamp(ubuf.strokeWidth,0.75,1.25);
    float gap = ubuf.cellSize;
    float band = 2.0*line+gap;
    float outer = (1.0-smoothstep(-aa,aa,d))*smoothstep(-line-aa,-line+aa,d);
    float inner = (1.0-smoothstep(-line-gap-aa,-line-gap+aa,d))
        *smoothstep(-band-aa,-band+aa,d);
    float coverage = (1.0-smoothstep(-aa,aa,d))*smoothstep(-band-aa,-band+aa,d);
    vec3 edge = mix(ubuf.baseColor.rgb,ubuf.edgeColor.rgb,ubuf.edgeColor.a);
    vec3 color = mix(ubuf.baseColor.rgb,edge,max(outer,inner*0.65));
    float alpha = coverage*ubuf.qt_Opacity;
    fragColor = vec4(color*alpha,alpha);
}
