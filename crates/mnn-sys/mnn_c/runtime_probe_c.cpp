#include "runtime_probe_c.h"

// Declared in MNN source/core/Backend.hpp (internal); exported by libMNN in
// namespace MNN (Itanium: _ZN3MNN25MNNGetExtraRuntimeCreatorE14MNNForwardType).
namespace MNN {
struct RuntimeCreator;
const RuntimeCreator *MNNGetExtraRuntimeCreator(MNNForwardType type);
} // namespace MNN

extern "C" int mnn_backend_available(MNNForwardType type) {
  return MNN::MNNGetExtraRuntimeCreator(type) != nullptr ? 1 : 0;
}
