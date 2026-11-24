// Adapted from osfans/MCPDict AudioAnalysis.java and AudioMeasures.java.
// Fixed-rate YIN pitch, windowed FFT, Kaiser-weighted intensity, LPC formants and pulses.
#include "Acoustics.h"
#include <algorithm>
#include <cmath>
#include <array>
template<class A,class B> auto minimum(A a,B b) -> decltype(a+b) { return a<b?a:b; }
template<class A,class B> auto maximum(A a,B b) -> decltype(a+b) { return a>b?a:b; }
namespace {
constexpr int RATE=16000, FFT=512, SPECTRUM_WINDOW=160, BINS=161;
constexpr int PITCH_WINDOW=1024, PITCH_RATE=8000, PITCH_MIN=55, PITCH_MAX=550;
constexpr int MIN_LAG=PITCH_RATE/PITCH_MAX, MAX_LAG=PITCH_RATE/PITCH_MIN, COMPARE=512-MAX_LAG-1;
constexpr float PITCH_THRESHOLD=0.16f;
constexpr int WINDOW=512, ORDER=16, STEP=25, LPC_BINS=201, FORMANT_COUNT=5;
constexpr double INTENSITY_RADIUS=3.2*RATE/75;
constexpr int INTENSITY_DELAY=int(INTENSITY_RADIUS)+1, INTENSITY_WINDOW=2*INTENSITY_DELAY-1;
constexpr double REFERENCE_PRESSURE=20e-6, FORMANT_MIN_POWER=3.162277660168379e-6;
const double PREEMPHASIS=std::exp(-2*M_PI*50/RATE);
    static double besselI0(double x) {
        double sum = 1;
        double term = 1;
        for (int k = 1; term > sum * 1e-15; k++) {
            double ratio = x / (2 * k);
            term *= ratio * ratio;
            sum += term;
        }
        return sum;
    }

struct Tables {
 double INTENSITY_WEIGHTS[INTENSITY_WINDOW], COSINE[LPC_BINS][ORDER], SINE[LPC_BINS][ORDER];
 double window[WINDOW], spectralWindow[SPECTRUM_WINDOW], spectralTilt[BINS], spectrumScale;
 double cosine[FFT/2], sine[FFT/2];
 int reverse[FFT];
 Tables() {
        // Praat's Kaiser-20 window spans 6.4 pitch periods at the intensity pitch floor.
        double beta = 2 * M_PI * M_PI + 0.5;
        double total = 0;
        for (int i = 0; i < INTENSITY_WINDOW; i++) {
            double position = (i - (INTENSITY_DELAY - 1)) / INTENSITY_RADIUS;
            INTENSITY_WEIGHTS[i] = besselI0(beta * std::sqrt(1 - position * position));
            total += INTENSITY_WEIGHTS[i];
        }
        for (int i = 0; i < INTENSITY_WINDOW; i++) INTENSITY_WEIGHTS[i] /= total;
        for (int bin = 0; bin < LPC_BINS; bin++) {
            for (int order = 1; order <= ORDER; order++) {
                double angle = 2 * M_PI * bin * STEP * order / RATE;
                COSINE[bin][order - 1] = std::cos(angle);
                SINE[bin][order - 1] = std::sin(angle);
            }
        }

 for(int i=0;i<WINDOW;i++) window[i]=0.54-0.46*std::cos(2*M_PI*i/(WINDOW-1));
 double sumWindow=0;
 for(int i=0;i<SPECTRUM_WINDOW;i++) sumWindow+=(spectralWindow[i]=0.5-0.5*std::cos(2*M_PI*i/(SPECTRUM_WINDOW-1)));
 spectrumScale=2/sumWindow;
 for(int i=0;i<BINS;i++) spectralTilt[i]=20*std::log10(maximum(1,i*RATE/(FFT*1000.0)));
 for(int i=0;i<FFT/2;i++){cosine[i]=std::cos(-2*M_PI*i/FFT);sine[i]=std::sin(-2*M_PI*i/FFT);}
 for(int i=0;i<FFT;i++){int x=i,j=0;for(int bit=0;bit<9;bit++){j=j*2+(x&1);x>>=1;}reverse[i]=j;}
 }
};
const Tables tables;
struct Analyzer {
 const float *pcm;
 int samples;
 float sampleAt(int i) const {return i < 0 ? 0 : pcm[i];}
    float pitch() {
        float downsampled[512], difference[MAX_LAG+2];
        if (samples < PITCH_WINDOW) return NAN;
        float energy = 0;
        float mean = 0;
        for (int i = 0; i < 512; i++) {
            int offset = samples - PITCH_WINDOW + 2 * i;
            float value = (sampleAt(offset) + sampleAt(offset + 1)) * 0.5f;
            downsampled[i] = value;
            energy += value * value;
            mean += value;
        }
        mean /= 512;
        if (energy / 512 - mean * mean < 0.000036f) return NAN;

        // YIN's cumulative mean-normalized difference rejects non-periodic frames.
        float cumulative = 0;
        difference[0] = 1;
        for (int lag = 1; lag <= MAX_LAG + 1; lag++) {
            float distance = 0;
            for (int i = 0; i < COMPARE; i++) {
                float delta = downsampled[i] - downsampled[i + lag];
                distance += delta * delta;
            }
            cumulative += distance;
            difference[lag] = cumulative > 0 ? distance * lag / cumulative : 1;
        }
        for (int lag = MIN_LAG; lag <= MAX_LAG; lag++) {
            float center = difference[lag];
            float right = difference[lag + 1];
            if (center >= PITCH_THRESHOLD || center > right) continue;
            float left = difference[lag - 1];
            float curvature = left - 2 * center + right;
            float offset = curvature > 0 ? 0.5f * (left - right) / curvature : 0;
            float hz = PITCH_RATE / (lag + maximum(-0.5f, minimum(0.5f, offset)));
            return hz >= PITCH_MIN && hz <= PITCH_MAX ? hz : NAN;
        }
        return NAN;
    }
    void spectrum(int endSample, uint8_t *bins) {
        float real[FFT], imaginary[FFT];
        for (int i = 0; i < FFT; i++) {
            int j = tables.reverse[i];
            real[j] = i < SPECTRUM_WINDOW ? sampleAt(endSample - SPECTRUM_WINDOW + i) * tables.spectralWindow[i] : 0;
            imaginary[j] = 0;
        }
        for (int size = 2; size <= FFT; size *= 2) {
            int half = size / 2;
            int step = FFT / size;
            for (int start = 0; start < FFT; start += size) {
                for (int i = 0; i < half; i++) {
                    int a = start + i;
                    int b = a + half;
                    float c = tables.cosine[i * step];
                    float s = tables.sine[i * step];
                    float r = real[b] * c - imaginary[b] * s;
                    float q = real[b] * s + imaginary[b] * c;
                    real[b] = real[a] - r;
                    imaginary[b] = imaginary[a] - q;
                    real[a] += r;
                    imaginary[a] += q;
                }
            }
        }
        for (int i = 0; i < BINS; i++) {
            double amplitude = std::hypot(real[i], imaginary[i]) * tables.spectrumScale;
            double db = 20 * std::log10(maximum(1e-6, amplitude)) + tables.spectralTilt[i];
            int shade = (int) (255 * maximum(0, minimum(1, (db + 80) / 62)));
            bins[i] = (uint8_t) (255 - shade);
        }

    }

    float intensity(int end) {
        if (end < INTENSITY_WINDOW) return NAN;
        int start = end - INTENSITY_WINDOW;
        double mean = 0;
        for (int i = start; i < end; i++) mean += sampleAt(i);
        mean /= INTENSITY_WINDOW;
        double power = 0;
        for (int i = 0; i < INTENSITY_WINDOW; i++) {
            double pressure = sampleAt(start + i) - mean;
            power += pressure * pressure * tables.INTENSITY_WEIGHTS[i];
        }
        double relativePower = power / (REFERENCE_PRESSURE * REFERENCE_PRESSURE);
        return (float) (10 * std::log10(maximum(1e-30, relativePower)));
    }

    bool hasFormantSignal(int end) {
        int start = end - WINDOW;
        double energy = 0;
        double sum = 0;
        for (int i = start; i < end; i++) {
            double sample = sampleAt(i);
            energy += sample * sample;
            sum += sample;
        }
        double mean = sum / WINDOW;
        double power = energy / WINDOW - mean * mean;
        return power >= FORMANT_MIN_POWER;
    }

    void formants(int end,float *frequencies) {
        double signal[WINDOW], correlation[ORDER+1], lpc[ORDER+1], updated[ORDER+1], envelope[LPC_BINS];
        if (end < WINDOW || !hasFormantSignal(end)) return;
        double previous = sampleAt(end - WINDOW - 1);
        for (int i = 0; i < WINDOW; i++) {
            double value = sampleAt(end - WINDOW + i);
            signal[i] = (value - PREEMPHASIS * previous) * tables.window[i];
            previous = value;
        }
        for (int lag = 0; lag <= ORDER; lag++) {
            double sum = 0;
            for (int i = lag; i < WINDOW; i++) sum += signal[i] * signal[i - lag];
            correlation[lag] = sum;
        }
        correlation[0] *= 1.0001;
        double error = correlation[0];
        if (error < 1e-8) return;
        lpc[0] = 1;
        for (int order = 1; order <= ORDER; order++) {
            double prediction = correlation[order];
            for (int i = 1; i < order; i++) prediction += lpc[i] * correlation[order - i];
            double reflection = -prediction / error;
            if (std::abs(reflection) >= 0.999 || !std::isfinite(reflection)) return;
            for (int i = 1; i < order; i++) updated[i] = lpc[i] + reflection * lpc[order - i];
            std::copy(updated+1,updated+order,lpc+1);
            lpc[order] = reflection;
            error *= 1 - reflection * reflection;
        }
        for (int bin = 0; bin < LPC_BINS; bin++) {
            double real = 1;
            double imaginary = 0;
            for (int order = 1; order <= ORDER; order++) {
                real += lpc[order] * tables.COSINE[bin][order - 1];
                imaginary += lpc[order] * tables.SINE[bin][order - 1];
            }
            envelope[bin] = 1 / maximum(1e-10, real * real + imaginary * imaginary);
        }


        int count = 0;
        for (int bin = 4; bin < LPC_BINS - 4 && count < FORMANT_COUNT; bin++) {
            double top = envelope[bin];
            if (top <= envelope[bin - 1] || top <= envelope[bin + 1]) continue;
            int left = bin - 1;
            int right = bin + 1;
            while (left > 0 && bin - left < 18 && envelope[left] > top * 0.55) left--;
            while (right < LPC_BINS - 1 && right - bin < 18 && envelope[right] > top * 0.55) right++;
            if (envelope[left] > top * 0.55 || envelope[right] > top * 0.55 || (right - left) * STEP > 550) continue;
            double before = std::log(envelope[bin - 1]);
            double after = std::log(envelope[bin + 1]);
            double bend = before - 2 * std::log(top) + after;
            double offset = bend < 0 ? 0.5 * (before - after) / bend : 0;
            frequencies[count++] = (float) ((bin + offset) * STEP);
        }

    }

    int pulses(int end,int blockSize,float pitch,int *pulses,int &lastPulse,double &polarity) {
        if (!std::isfinite(pitch)) {
            lastPulse = -1;
            return 0;
        }
        int period = std::lround(RATE / pitch);
        int radius = maximum(1, period / 5);
        int first = end - blockSize;
        int count = 0;
        if (lastPulse < first - 2 * period) lastPulse = -1;
        if (lastPulse == -1) {
            int seed = first;
            for (int i = first + 1; i < minimum(end, first + period); i++) {
                if (std::abs(sampleAt(i)) > std::abs(sampleAt(seed))) seed = i;
            }
            double sample = sampleAt(seed);
            if (std::abs(sample) < 0.005) return 0;
            polarity = std::copysign(1, sample);
            lastPulse = seed;
            pulses[count++] = seed;
        }
        while (lastPulse + period + radius < end && count < 16) {
            int target = lastPulse + period;
            int best = target - radius;
            for (int i = best + 1; i <= target + radius; i++) {
                if (sampleAt(i) * polarity > sampleAt(best) * polarity) best = i;
            }
            if (sampleAt(best) * polarity < 0.005) {
                lastPulse = -1;
                break;
            }
            lastPulse = best;
            pulses[count++] = best;
        }
        return count;
    }
};
}
void mcp_measure(const float *pcm,int start,int end,float *pitch,float *intensity,float *formants,int *positions,int *count,int *last,double *polarity,uint8_t *spectra) {
 Analyzer a{pcm,end};
 *pitch=a.pitch(); *intensity=a.intensity(end);
 std::fill(formants,formants+5,NAN); a.formants(end,formants);
 *count=a.pulses(end,end-start,*pitch,positions,*last,*polarity);
 for(int i=0;i<4;i++) a.spectrum(minimum(end,start+64*(i+1)),spectra+161*i);
}
