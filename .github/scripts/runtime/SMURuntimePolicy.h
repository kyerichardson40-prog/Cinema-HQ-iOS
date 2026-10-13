#ifndef SMU_RUNTIME_POLICY_H
#define SMU_RUNTIME_POLICY_H
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
static inline float SMUClampDegrees(float value) {
    return isfinite(value) ? fminf(100.0f,fmaxf(45.0f,roundf(value))) : 60.0f;
}
static inline float SMUResolveFrameFOV(float nativeRadians,float degrees,bool gameplayCaller,bool eligibleCamera) {
    if (!gameplayCaller || !eligibleCamera || !isfinite(nativeRadians) || nativeRadians<=0.1f || nativeRadians>=3.0f || SMUClampDegrees(degrees)==60.0f) return nativeRadians;
    return SMUClampDegrees(degrees)*0.017453292519943295f;
}
typedef struct { uint8_t tag,flags,padding[6];uint64_t payload,object; } SMUValue;
static inline uint32_t SMURol32(uint32_t v,unsigned bits) {return (v<<bits)|(v>>(32-bits));}
static inline SMUValue SMUNumber(double number) {
    SMUValue value;memset(&value,0,sizeof(value));uint64_t bits;memcpy(&bits,&number,8);value.tag=2;
    value.payload=(uint64_t)(SMURol32((uint32_t)bits,5)^0x380838ba)|((uint64_t)(SMURol32((uint32_t)(bits>>32),5)^0x380838ba)<<32);return value;
}
static inline double SMUDecodeNumber(SMUValue value) {
    uint32_t a=(uint32_t)value.payload^0x380838ba,b=(uint32_t)(value.payload>>32)^0x380838ba;
    uint64_t bits=(uint64_t)SMURol32(a,27)|((uint64_t)SMURol32(b,27)<<32);double number;memcpy(&number,&bits,8);return number;
}
#endif
