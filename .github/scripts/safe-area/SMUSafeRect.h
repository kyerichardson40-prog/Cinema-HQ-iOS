#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdbool.h>

static bool SMUNearRect(CGRect a, CGRect b) {
    return fabs(a.origin.x-b.origin.x)<0.5 && fabs(a.origin.y-b.origin.y)<0.5 &&
           fabs(a.size.width-b.size.width)<0.5 && fabs(a.size.height-b.size.height)<0.5;
}
static bool SMUAdjustFrame(CGRect proposed, CGRect full, CGFloat top, CGFloat left,
                          CGFloat bottom, CGFloat right, CGRect *out) {
    *out=proposed;
    if (!isfinite(top)||!isfinite(left)||!isfinite(bottom)||!isfinite(right)||
        top<0||left<0||bottom<0||right<0||top+bottom>=full.size.height||left+right>=full.size.width)
        return false;
    CGRect fitted=CGRectMake(full.origin.x+left,full.origin.y+top,
                            full.size.width-left-right,full.size.height-top-bottom);
    // Never compound the inset or replace a deliberately smaller modal/keyboard frame.
    if (!SMUNearRect(proposed,full) && !SMUNearRect(proposed,fitted)) return false;
    *out=fitted;
    return true;
}
