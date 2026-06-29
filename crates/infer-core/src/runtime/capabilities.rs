/// Primary runtime family compiled into this build.
pub fn backend_kind() -> &'static str {
    if cfg!(feature = "types-only") {
        "none"
    } else if cfg!(feature = "backend-mnn") {
        "mnn"
    } else {
        "onnx"
    }
}

/// Execution providers (ORT) or MNN backends available on this device/build.
pub fn available_backends() -> Vec<String> {
    if cfg!(feature = "types-only") {
        return vec![];
    }
    #[cfg(feature = "backend-ort")]
    {
        return ort_available_backends();
    }
    #[cfg(all(feature = "backend-mnn", not(feature = "backend-ort")))]
    {
        return mnn_available_backends();
    }
    #[cfg(not(any(feature = "backend-ort", feature = "backend-mnn")))]
    {
        vec![]
    }
}

#[cfg(feature = "backend-ort")]
use super::ort;

#[cfg(feature = "backend-mnn")]
use mnn_sys::MNNForwardType;

#[cfg(feature = "backend-ort")]
fn ort_available_backends() -> Vec<String> {
    let mut backends = vec!["cpu".to_string()];
    for ep in ["directml", "cuda", "coreml"] {
        if ort::ep_available(ep) {
            backends.push(ep.to_string());
        }
    }
    backends
}

#[cfg(feature = "backend-mnn")]
fn mnn_available_backends() -> Vec<String> {
    let mut backends = Vec::new();
    for (name, ty) in [
        ("cpu", MNNForwardType::MNN_FORWARD_CPU),
        ("opencl", MNNForwardType::MNN_FORWARD_OPENCL),
        ("vulkan", MNNForwardType::MNN_FORWARD_VULKAN),
    ] {
        if mnn_backend_available(ty) {
            backends.push(name.to_string());
        }
    }
    if backends.is_empty() {
        backends.push("cpu".to_string());
    }
    backends
}

#[cfg(feature = "backend-mnn")]
fn mnn_backend_available(ty: MNNForwardType) -> bool {
    unsafe { mnn_sys::mnn_backend_available(ty) != 0 }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cpu_is_always_available() {
        if cfg!(feature = "types-only") {
            return;
        }
        assert!(available_backends().iter().any(|b| b == "cpu"));
    }
}
