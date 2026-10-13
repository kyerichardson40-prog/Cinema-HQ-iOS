#include <assert.h>
#include "SMURuntimePolicy.h"
int main(void) {
    // Every native camera update is overridden, including changing speed/zoom FOV.
    for (int frame=0;frame<14400;frame++) {
        float native=0.87f+(frame%50)*0.005f;
        float result=SMUResolveFrameFOV(native,90,true,true);
        assert(fabsf(result-1.57079632679f)<0.00001f);
        assert(SMUResolveFrameFOV(native,60,true,true)==native);
        assert(SMUResolveFrameFOV(native,90,false,true)==native);
        assert(SMUResolveFrameFOV(native,90,true,false)==native);
    }
    assert(isnan(SMUResolveFrameFOV(NAN,90,true,true)));
    double numbers[]={0,1,45,59,60,75,90,100,640,1337.5,-48,0.0000001};
    for (unsigned i=0;i<sizeof(numbers)/sizeof(numbers[0]);i++) {SMUValue v=SMUNumber(numbers[i]);assert(v.tag==2);assert(SMUDecodeNumber(v)==numbers[i]);}
    assert(sizeof(SMUValue)==24);
    return 0;
}
