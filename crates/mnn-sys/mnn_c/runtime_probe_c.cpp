#include "runtime_probe_c.h"

#include <MNN/Backend.hpp>

extern "C" int mnn_backend_available(MNNForwardType type) {
  return MNNGetExtraRuntimeCreator(type) != nullptr ? 1 : 0;
}
