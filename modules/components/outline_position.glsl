const float HALF_PI=1.57079632679;
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

