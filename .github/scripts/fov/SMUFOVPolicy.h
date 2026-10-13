#include <math.h>
#include <stdbool.h>
typedef struct {
    float nativeRadians;
    float appliedRadians;
    bool applied;
} SMUFOVState;
static float SMUClampDegrees(float value) {
    if (!isfinite(value)) return 60.0f;
    return fminf(100.0f,fmaxf(45.0f,roundf(value)));
}
static float SMURadians(float value) { return SMUClampDegrees(value)*0.017453292519943295f; }
static bool SMUFOVNext(SMUFOVState *state,float current,float degrees,bool gameplay,float *next) {
    *next=current;
    if (!isfinite(current)||current<=0.1f||current>=3.0f) return false;
    // Capture authored camera changes; never mistake our own applied value for stock.
    if (!state->applied || fabsf(current-state->appliedRadians)>0.00001f)
        state->nativeRadians=current;
    const bool stock=!gameplay || SMUClampDegrees(degrees)==60.0f;
    const float target=stock ? state->nativeRadians : SMURadians(degrees);
    state->applied=!stock;
    state->appliedRadians=target;
    *next=target;
    return fabsf(current-target)>0.00001f;
}
