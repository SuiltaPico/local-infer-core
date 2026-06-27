#ifndef RUNTIME_PROBE_C_H
#define RUNTIME_PROBE_C_H

#include <MNN/MNNForwardType.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Returns 1 when MNN registered a runtime creator for [type], else 0.
int mnn_backend_available(MNNForwardType type);

#ifdef __cplusplus
}
#endif

#endif
