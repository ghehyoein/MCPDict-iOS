#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// For one 256-sample frame of mono PCM at 16 kHz. Four successive spectra of 161 bins.
void mcp_measure(const float *pcm, int start, int end, float *pitch, float *intensity,
                 float *formants, int *pulsePositions, int *pulseCount,
                 int *lastPulse, double *polarity, uint8_t *spectra);
#ifdef __cplusplus
}
#endif
