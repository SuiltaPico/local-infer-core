// Prebuilt MSVC Static/MD MNN.lib may reference __std_min_element_4i /
// __std_max_element_4i from the STL version used at MNN build time. Compiling
// min/max_element here with the host toolset provides those symbols at link.
#include <algorithm>

namespace mnn_sys {
namespace {

const int *min_element_shim(const int *first, const int *last) {
  return std::min_element(first, last);
}

const int *max_element_shim(const int *first, const int *last) {
  return std::max_element(first, last);
}

} // namespace

void stl_link_shim_anchor() {
  static const int data[] = {3, 1, 4, 2};
  (void)min_element_shim(data, data + 4);
  (void)max_element_shim(data, data + 4);
}

} // namespace mnn_sys
