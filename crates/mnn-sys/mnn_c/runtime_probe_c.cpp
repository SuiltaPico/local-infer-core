#include "runtime_probe_c.h"

// Declared in MNN source/core/Backend.hpp (internal); exported by libMNN.
struct RuntimeCreator;
const RuntimeCreator *MNNGetExtraRuntimeCreator(MNNForwardType type);

extern "C" int mnn_backend_available(MNNForwardType type) {
  return MNNGetExtraRuntimeCreator(type) != nullptr ? 1 : 0;
}
