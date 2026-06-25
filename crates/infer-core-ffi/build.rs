fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android")
        && std::env::var("CARGO_FEATURE_BACKEND_MNN").is_ok()
        && std::env::var("MNN_LINK").as_deref() != Ok("dylib")
    {
        // Fallback when MNN is linked statically (default MNN_LINK=static).
        println!("cargo:rustc-link-lib=c++_shared");
    }
}
