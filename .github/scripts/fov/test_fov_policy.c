#include <assert.h>
#include "SMUFOVPolicy.h"
int main(void) {
    SMUFOVState state={0};float next;
    const float stock=SMURadians(60);
    assert(!SMUFOVNext(&state,stock,60,true,&next));assert(next==stock);
    assert(SMUFOVNext(&state,stock,90,true,&next));assert(fabsf(next-1.5707963f)<0.00001f);
    for (int i=0;i<100;i++) { assert(!SMUFOVNext(&state,next,90,true,&next)); assert(fabsf(next-1.5707963f)<0.00001f); }
    assert(SMUFOVNext(&state,next,60,true,&next));assert(next==stock);
    // A new native zoom while overridden is captured and restored on leaving gameplay.
    assert(SMUFOVNext(&state,stock,80,true,&next));
    float authored=SMURadians(50);
    assert(SMUFOVNext(&state,authored,80,true,&next));
    assert(SMUFOVNext(&state,next,80,false,&next));assert(next==authored);
    assert(SMUClampDegrees(-10)==45 && SMUClampDegrees(200)==100 && SMUClampDegrees(NAN)==60);
    assert(!SMUFOVNext(&state,NAN,90,true,&next));
    return 0;
}
