#include "runtime_probe_c.h"

#if defined(MNN_SYS_RUNTIME_PROBE_STUB)

extern "C" int mnn_backend_available(MNNForwardType type) {
  switch (type) {
  case MNN_FORWARD_CPU:
    return 1;
#if defined(MNN_OPENCL)
  case MNN_FORWARD_OPENCL:
    return 1;
#endif
#if defined(MNN_VULKAN)
  case MNN_FORWARD_VULKAN:
    return 1;
#endif
  default:
    return 0;
  }
}

#else

// Must match MNN Backend.hpp: RuntimeCreator is a class, not a struct (MSVC name mangling).
namespace MNN {
class RuntimeCreator;
const RuntimeCreator *MNNGetExtraRuntimeCreator(MNNForwardType type);
} // namespace MNN

extern "C" int mnn_backend_available(MNNForwardType type) {
  return MNN::MNNGetExtraRuntimeCreator(type) != nullptr ? 1 : 0;
}

#endif
