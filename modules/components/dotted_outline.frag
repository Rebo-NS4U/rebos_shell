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
const float HALF_PI = 1.57079632679;

// Clockwise perimeter starting at the top-left straight/arc junction.
// The same coordinate spans straight edges and arcs, eliminating the broken
// corner fragments produced by clipping a checkerboard against the border.
vec2 pointOnOutline(float t, vec2 box, vec4 r) {
    float n = box.x - r.x - r.y;
    if (t < n) return vec2(r.x + t, 0.0);
    t -= n; n = HALF_PI * r.y;
    if (t < n) {
        float a = t / r.y - HALF_PI;
        return vec2(box.x-r.y, r.y) + r.y*vec2(cos(a),sin(a));
    }
    t -= n; n = box.y-r.y-r.w;
    if (t < n) return vec2(box.x, r.y+t);
    t -= n; n = HALF_PI*r.w;
    if (t < n) {
        float a = t/r.w;
        return vec2(box.x-r.w, box.y-r.w) + r.w*vec2(cos(a),sin(a));
    }
    t -= n; n = box.x-r.w-r.z;
    if (t < n) return vec2(box.x-r.w-t,box.y);
    t -= n; n = HALF_PI*r.z;
    if (t < n) {
        float a = t/r.z + HALF_PI;
        return vec2(r.z,box.y-r.z) + r.z*vec2(cos(a),sin(a));
    }
    t -= n; n = box.y-r.z-r.x;
    if (t < n) return vec2(0.0,box.y-r.z-t);
    t -= n;
    float a = t/max(r.x,0.001) + 2.0*HALF_PI;
    return vec2(r.x) + r.x*vec2(cos(a),sin(a));
}

float outlinePosition(vec2 p, vec2 box, vec4 r) {
    float top = box.x-r.x-r.y;
    float rightStart = top+HALF_PI*r.y;
    float bottomArc = rightStart+box.y-r.y-r.w;
    float bottomStart = bottomArc+HALF_PI*r.w;
    float leftArc = bottomStart+box.x-r.w-r.z;
    float leftStart = leftArc+HALF_PI*r.z;
    float topArc = leftStart+box.y-r.z-r.x;
    if (p.x < r.x && p.y < r.x)
        return topArc+(atan(p.y-r.x,p.x-r.x)+2.0*HALF_PI)*r.x;
    if (p.x > box.x-r.y && p.y < r.y)
        return top+(atan(p.y-r.y,p.x-box.x+r.y)+HALF_PI)*r.y;
    if (p.x > box.x-r.w && p.y > box.y-r.w)
        return bottomArc+atan(p.y-box.y+r.w,p.x-box.x+r.w)*r.w;
    if (p.x < r.z && p.y > box.y-r.z)
        return leftArc+(atan(p.y-box.y+r.z,p.x-r.z)-HALF_PI)*r.z;
    vec4 d = abs(vec4(p.y,box.x-p.x,box.y-p.y,p.x));
    float nearest = min(min(d.x,d.y),min(d.z,d.w));
    if (d.x == nearest) return clamp(p.x-r.x,0.0,top);
    if (d.y == nearest) return rightStart+clamp(p.y-r.y,0.0,box.y-r.y-r.w);
    if (d.z == nearest) return bottomStart+clamp(box.x-r.w-p.x,0.0,box.x-r.w-r.z);
    return leftStart+clamp(box.y-r.z-p.y,0.0,box.y-r.z-r.x);
}

void main() {
    vec2 pixel = qt_TexCoord0*ubuf.size;
    vec2 p = pixel-ubuf.size*0.5;
    vec4 outerRadii = clamp(ubuf.corners,vec4(0.0),vec4(min(ubuf.size.x,ubuf.size.y)*0.5));
    float radius = p.y < 0.0 ? (p.x < 0.0 ? outerRadii.x : outerRadii.y)
                                : (p.x < 0.0 ? outerRadii.z : outerRadii.w);
    vec2 q = abs(p)-(ubuf.size*0.5-radius);
    float distance = length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-radius;
    float aa = max(fwidth(distance)*0.5,0.001);
    float stroke = min(ubuf.strokeWidth,min(ubuf.size.x,ubuf.size.y));
    float ring = (1.0-smoothstep(-aa,aa,distance))
        *smoothstep(-stroke-aa,-stroke+aa,distance);
    if (ring <= 0.001) { fragColor=vec4(0.0); return; }

    float inset = stroke*0.5;
    vec2 box = max(ubuf.size-vec2(stroke),vec2(0.001));
    vec4 r = max(outerRadii-vec4(inset),vec4(0.0));
    float perimeter = max(0.001,2.0*(box.x+box.y)+(HALF_PI-2.0)*(r.x+r.y+r.z+r.w));
    // Fit whole dots to the closed contour so the seam has the same gap as
    // every other pair. Dot diameter still comes from the shared cell size.
    float count = max(1.0,floor(perimeter/(2.0*ubuf.cellSize)+0.5));
    float pitch = perimeter/count;
    float s = outlinePosition(pixel-vec2(inset),box,r);
    float t = mod(floor(s/pitch+0.5)*pitch,perimeter);
    vec2 center = pointOnOutline(t,box,r)+vec2(inset);
    float dotDistance = length(pixel-center);
    float dotRadius = min(ubuf.cellSize,stroke)*0.5;
    float dotAA = aa;
    float dot = 1.0-smoothstep(dotRadius-dotAA,dotRadius+dotAA,dotDistance);
    vec3 edge = mix(ubuf.baseColor.rgb,ubuf.edgeColor.rgb,ubuf.edgeColor.a);
    vec3 color = mix(ubuf.baseColor.rgb,edge,dot);
    float alpha = ring*ubuf.qt_Opacity;
    fragColor = vec4(color*alpha,alpha);
}
