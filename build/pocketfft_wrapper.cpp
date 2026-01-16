#include "pocketfft_hdronly.h"
#include <complex>
#include <cstdlib>

#if defined(_WIN32)
#define POCKETFFT_EXPORT __declspec(dllexport)
#else
#define POCKETFFT_EXPORT __attribute__((visibility("default")))
#endif

extern "C" {

typedef float pocketfft_complex[2];

struct pocketfft_plan_s {
    size_t n;
    std::complex<float> *in;
    std::complex<float> *out;
    bool forward;
};

typedef struct pocketfft_plan_s *pocketfft_plan;

POCKETFFT_EXPORT void *pocketfft_malloc(size_t n) {
    return malloc(n);
}

POCKETFFT_EXPORT void pocketfft_free(void *p) {
    free(p);
}

POCKETFFT_EXPORT pocketfft_plan pocketfft_plan_dft_1d(int n, pocketfft_complex *in, pocketfft_complex *out, int sign, unsigned flags) {
    pocketfft_plan plan = (pocketfft_plan)malloc(sizeof(struct pocketfft_plan_s));
    if (!plan) return nullptr;
    plan->n = (size_t)n;
    plan->in = reinterpret_cast<std::complex<float> *>(in);
    plan->out = reinterpret_cast<std::complex<float> *>(out);
    // FFTW style sign: -1 is Forward, 1 is Backward.
    // PocketFFT: forward=true is Forward.
    plan->forward = (sign == -1);
    return plan;
}

POCKETFFT_EXPORT void pocketfft_execute(const pocketfft_plan plan) {
    if (!plan) return;

    pocketfft::shape_t shape = {plan->n};
    pocketfft::stride_t stride_in = {sizeof(std::complex<float>)};
    pocketfft::stride_t stride_out = {sizeof(std::complex<float>)};
    pocketfft::shape_t axes = {0};

    pocketfft::c2c(
        shape,
        stride_in,
        stride_out,
        axes,
        plan->forward,
        plan->in,
        plan->out,
        1.0f);
}

POCKETFFT_EXPORT void pocketfft_destroy_plan(pocketfft_plan plan) {
    if (plan) {
        free(plan);
    }
}

} // extern "C"
