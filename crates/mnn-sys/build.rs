use ::tap::*;
use anyhow::*;
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;
use std::{
    path::{Path, PathBuf},
    sync::LazyLock,
};
const VENDOR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/vendor");
const MANIFEST_DIR: &str = env!("CARGO_MANIFEST_DIR");
const THIRD_PARTY_MNN_SOURCE: &str =
    concat!(env!("CARGO_MANIFEST_DIR"), "/../../third_party/mnn/source");
const THIRD_PARTY_MNN_WINDOWS_MD: &str =
    concat!(env!("CARGO_MANIFEST_DIR"), "/../../third_party/mnn/windows/x64-md");
const THIRD_PARTY_MNN_ANDROID: &str =
    concat!(env!("CARGO_MANIFEST_DIR"), "/../../third_party/mnn/android");
static TARGET_OS: LazyLock<String> =
    LazyLock::new(|| std::env::var("CARGO_CFG_TARGET_OS").expect("CARGO_CFG_TARGET_OS not set"));
static TARGET_ARCH: LazyLock<String> = LazyLock::new(|| {
    std::env::var("CARGO_CFG_TARGET_ARCH").expect("CARGO_CFG_TARGET_ARCH not found")
});
static EMSCRIPTEN_CACHE: LazyLock<String> = LazyLock::new(|| {
    let emscripten_cache = std::process::Command::new("em-config")
        .arg("CACHE")
        .output()
        .expect("Failed to get emscripten cache")
        .stdout;
    let emscripten_cache = std::str::from_utf8(&emscripten_cache)
        .expect("Failed to parse emscripten cache")
        .trim()
        .to_string();
    emscripten_cache
});

static MNN_COMPILE: LazyLock<bool> = LazyLock::new(|| {
    std::env::var("MNN_COMPILE")
        .ok()
        .and_then(|v| match v.as_str() {
            "1" | "true" | "yes" => Some(true),
            "0" | "false" | "no" => Some(false),
            _ => None,
        })
        .unwrap_or_else(|| resolve_prebuilt_lib_dir().is_none())
});

static MNN_LINK: LazyLock<String> = LazyLock::new(|| {
    std::env::var("MNN_LINK").unwrap_or_else(|_| {
        if resolve_prebuilt_lib_dir().is_some() {
            "dylib".into()
        } else {
            "static".into()
        }
    })
});

const HALIDE_SEARCH: &str =
    r#"HALIDE_ATTRIBUTE_ALIGN(1) halide_type_code_t code; // halide_type_code_t"#;
const TRACING_SEARCH: &str = "#define MNN_PRINT(format, ...) printf(format, ##__VA_ARGS__)\n#define MNN_ERROR(format, ...) printf(format, ##__VA_ARGS__)";
const TRACING_REPLACE: &str = r#"
enum class Level {
  Info = 0,
  Error = 1,
};
extern "C" {
void mnn_ffi_emit(const char *file, size_t line, Level level,
                  const char *message);
}
#define MNN_PRINT(format, ...)                                                 \
  {                                                                            \
    char logtmp[4096];                                                         \
    snprintf(logtmp, 4096, format, ##__VA_ARGS__);                             \
    mnn_ffi_emit(__FILE__, __LINE__, Level::Info, logtmp);                     \
  }

#define MNN_ERROR(format, ...)                                                 \
  {                                                                            \
    char logtmp[4096];                                                         \
    snprintf(logtmp, 4096, format, ##__VA_ARGS__);                             \
    mnn_ffi_emit(__FILE__, __LINE__, Level::Error, logtmp);                    \
  }
"#;

fn android_api_level() -> u32 {
    std::env::var("CARGO_NDK_ANDROID_API_LEVEL")
        .ok()
        .or_else(|| {
            std::env::var("ANDROID_PLATFORM").ok().map(|p| {
                p.strip_prefix("android-")
                    .unwrap_or(p.as_str())
                    .to_string()
            })
        })
        .or_else(|| std::env::var("ANDROID_API_LEVEL").ok())
        .and_then(|v| v.parse().ok())
        .unwrap_or(21)
}

fn android_clang_triple(api: u32) -> String {
    let arch = match TARGET_ARCH.as_str() {
        "aarch64" => "aarch64-linux-android",
        "arm" => "armv7a-linux-androideabi",
        "x86_64" => "x86_64-linux-android",
        "x86" => "i686-linux-android",
        other => panic!("unsupported Android target arch: {other}"),
    };
    format!("{arch}{api}")
}

fn android_ndk_host_prebuilt() -> Result<PathBuf> {
    let ndk = std::env::var("ANDROID_NDK_HOME")
        .or_else(|_| std::env::var("NDK_HOME"))
        .context("ANDROID_NDK_HOME or NDK_HOME must be set for Android builds")?;
    let prebuilt = PathBuf::from(ndk).join("toolchains/llvm/prebuilt");
    prebuilt
        .read_dir()
        .with_context(|| format!("NDK llvm prebuilt missing: {}", prebuilt.display()))?
        .flatten()
        .find(|e| e.path().is_dir())
        .context("NDK llvm prebuilt toolchain not found")
        .map(|e| e.path())
}

fn android_clang_resource_dir(host_prebuilt: &Path, triple: &str) -> Result<String> {
    let clang = if cfg!(windows) {
        host_prebuilt.join("bin/clang.exe")
    } else {
        host_prebuilt.join("bin/clang")
    };
    let resource_dir = std::process::Command::new(&clang)
        .arg(format!("--target={triple}"))
        .arg("-print-resource-dir")
        .output()
        .with_context(|| format!("failed to query clang resource dir: {}", clang.display()))?;
    if !resource_dir.status.success() {
        anyhow::bail!(
            "clang -print-resource-dir failed: {}",
            String::from_utf8_lossy(&resource_dir.stderr)
        );
    }
    Ok(String::from_utf8(resource_dir.stdout)?.trim().to_string())
}

fn android_clang_common_args(host_prebuilt: &Path, triple: &str) -> Result<Vec<String>> {
    let resource_dir = android_clang_resource_dir(host_prebuilt, triple)?;
    Ok(vec![
        format!("--target={triple}"),
        format!("--sysroot={}", host_prebuilt.join("sysroot").display()),
        format!("-isystem{resource_dir}/include"),
        format!("-isystem{resource_dir}/include/c++/v1"),
    ])
}

fn android_cxx_compiler() -> Result<(PathBuf, Vec<String>)> {
    let host_prebuilt = android_ndk_host_prebuilt()?;
    let api = android_api_level();
    let triple = android_clang_triple(api);
    let bin_dir = host_prebuilt.join("bin");
    let base = format!("{triple}-clang++");
    let candidates = if cfg!(windows) {
        vec![
            bin_dir.join(format!("{base}.cmd")),
            bin_dir.join(format!("{base}.exe")),
            bin_dir.join(&base),
        ]
    } else {
        vec![bin_dir.join(&base)]
    };
    let compiler = candidates
        .into_iter()
        .find(|p| p.is_file())
        .with_context(|| format!("NDK C++ compiler not found for triple {triple}"))?;
    let args = android_clang_common_args(&host_prebuilt, &triple)?;
    Ok((compiler, args))
}

fn configure_android_cc() -> Result<()> {
    if *TARGET_OS != "android" {
        return Ok(());
    }
    let target = std::env::var("TARGET")?;
    let cxx_key = format!("CXX_{target}");
    if std::env::var(&cxx_key).is_ok() || std::env::var("CXX").is_ok() {
        return Ok(());
    }
    let (compiler, _) = android_cxx_compiler()?;
    std::env::set_var(&cxx_key, compiler.to_string_lossy().as_ref());
    Ok(())
}

fn android_bindgen_toolchain() -> Result<Option<(PathBuf, Vec<String>)>> {
    if *TARGET_OS != "android" {
        return Ok(None);
    }
    let host_prebuilt = android_ndk_host_prebuilt()?;
    let clang = if cfg!(windows) {
        host_prebuilt.join("bin/clang.exe")
    } else {
        host_prebuilt.join("bin/clang")
    };
    let triple = android_clang_triple(android_api_level());
    let args = android_clang_common_args(&host_prebuilt, &triple)?;
    Ok(Some((clang, args)))
}

fn configure_bindgen_libclang() {
    if std::env::var("LIBCLANG_PATH").is_ok() {
        return;
    }
    // NDK ships libclang.dll but it often fails to load on Windows hosts
    // (LoadLibraryExW / missing deps). Prefer a standalone LLVM install.
    for candidate in [
        std::env::var("LLVM_HOME")
            .ok()
            .map(|p| PathBuf::from(p).join("bin")),
        Some(PathBuf::from(r"D:\sdk\llvm\bin")),
    ]
    .into_iter()
    .flatten()
    {
        let libclang = if cfg!(windows) {
            candidate.join("libclang.dll")
        } else if cfg!(target_os = "macos") {
            candidate.join("libclang.dylib")
        } else {
            candidate.join("libclang.so")
        };
        if libclang.is_file() {
            std::env::set_var("LIBCLANG_PATH", candidate);
            return;
        }
    }
}

fn is_cross_compiling() -> bool {
    std::env::var("TARGET").ok().as_deref()
        != std::env::var("HOST").ok().as_deref()
}

fn write_mnn_cpp_stub(out: impl AsRef<Path>) -> Result<()> {
    std::fs::write(
        out.as_ref().join("mnn_cpp.rs"),
        include_str!("mnn_cpp/session_info.rs"),
    )?;
    Ok(())
}

fn apply_android_bindgen(builder: bindgen::Builder) -> Result<bindgen::Builder> {
    if let Some((_clang, args)) = android_bindgen_toolchain()? {
        Ok(builder.clang_args(args.iter().map(String::as_str)))
    } else {
        Ok(builder)
    }
}

fn ensure_vendor_exists(vendor: impl AsRef<Path>) -> Result<()> {
    let vendor = vendor.as_ref();
    if !vendor.is_dir() {
        anyhow::bail!(
            "MNN source directory missing: {}. Set MNN_SRC or run scripts/download_mnn_windows.ps1 (Windows) / scripts/download_mnn_android.ps1 (Android).",
            vendor.display(),
        );
    }
    if vendor.read_dir()?.flatten().next().is_none() {
        anyhow::bail!(
            "MNN source tree is empty at {}. Run scripts/download_mnn_windows.ps1 or scripts/download_mnn_android.ps1, or set MNN_SRC.",
            vendor.display()
        )
    }
    Ok(())
}

fn resolve_mnn_source() -> PathBuf {
    if let std::result::Result::Ok(source) = std::env::var("MNN_SRC") {
        return PathBuf::from(source);
    }
    let candidates = [
        PathBuf::from(VENDOR),
        PathBuf::from(THIRD_PARTY_MNN_SOURCE),
    ];
    for candidate in candidates {
        if candidate.is_dir()
            && candidate
                .read_dir()
                .map(|entries| entries.flatten().next().is_some())
                .unwrap_or(false)
        {
            return candidate;
        }
    }
    PathBuf::from(VENDOR)
}

fn android_prebuilt_abi() -> Option<&'static str> {
    match TARGET_ARCH.as_str() {
        "aarch64" => Some("arm64-v8a"),
        "arm" => Some("armeabi-v7a"),
        "x86_64" => Some("x86_64"),
        _ => None,
    }
}

fn resolve_prebuilt_lib_dir() -> Option<PathBuf> {
    if let core::result::Result::Ok(lib_dir) = std::env::var("MNN_LIB_DIR") {
        let dir = PathBuf::from(lib_dir);
        if dir.join("MNN.lib").is_file() || dir.join("libMNN.so").is_file() {
            return Some(dir);
        }
    }
    if *TARGET_OS == "windows" && *TARGET_ARCH == "x86_64" {
        let dir = PathBuf::from(THIRD_PARTY_MNN_WINDOWS_MD);
        if dir.join("MNN.lib").is_file() {
            return Some(dir);
        }
    }
    if *TARGET_OS == "android" {
        if let Some(abi) = android_prebuilt_abi() {
            let dir = PathBuf::from(THIRD_PARTY_MNN_ANDROID).join(abi);
            if dir.join("libMNN.so").is_file() {
                return Some(dir);
            }
        }
    }
    None
}

fn copy_windows_runtime_dll(lib_dir: &Path) -> Result<()> {
    let dll = lib_dir.join("MNN.dll");
    if !dll.is_file() {
        return Ok(());
    }
    let out_dir = PathBuf::from(std::env::var("OUT_DIR")?);
    let Some(profile_dir) = out_dir.ancestors().nth(3) else {
        return Ok(());
    };
    let deps_dir = profile_dir.join("deps");
    for dest_dir in [profile_dir, deps_dir.as_path()] {
        let dest = dest_dir.join("MNN.dll");
        if let Some(parent) = dest.parent() {
            std::fs::create_dir_all(parent).ok();
        }
        std::fs::copy(&dll, &dest).with_context(|| format!("Failed to copy {} to {}", dll.display(), dest.display()))?;
    }
    Ok(())
}

fn main() -> Result<()> {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=src/mnn_c.rs");
    println!("cargo:rerun-if-changed=mnn_cpp/session_info.rs");
    println!("cargo:rerun-if-env-changed=MNN_SRC");
    println!("cargo:rerun-if-env-changed=MNN_COMPILE");
    println!("cargo:rerun-if-env-changed=MNN_LIB_DIR");
    println!("cargo:rerun-if-env-changed=MNN_LINK");
    println!("cargo:rerun-if-env-changed=ANDROID_NDK_HOME");
    println!("cargo:rerun-if-env-changed=NDK_HOME");
    let out_dir = PathBuf::from(std::env::var("OUT_DIR")?);
    let source = resolve_mnn_source();
    println!("cargo:rerun-if-changed={}", source.display());

    ensure_vendor_exists(&source)?;
    if !is_cross_compiling() {
        configure_bindgen_libclang();
    }

    let vendor = out_dir.join("vendor");
    // std::fs::remove_dir_all(&vendor).ok();
    if !vendor.exists() {
        fs_extra::dir::copy(
            &source,
            &vendor,
            &fs_extra::dir::CopyOptions::new()
                .overwrite(true)
                .copy_inside(true),
        )
        .context("Failed to copy vendor")?;
        let intptr = vendor.join("include").join("MNN").join("HalideRuntime.h");
        #[cfg(unix)]
        std::fs::set_permissions(&intptr, std::fs::Permissions::from_mode(0o644))?;

        use itertools::Itertools;
        let intptr_contents = std::fs::read_to_string(&intptr)?;
        let patched = intptr_contents.lines().collect::<Vec<_>>();
        if let Some((idx, _)) = patched
            .iter()
            .find_position(|line| line.contains(HALIDE_SEARCH))
        {
            // remove the last line and the next 3 lines
            let patched = patched
                .into_iter()
                .enumerate()
                .filter(|(c_idx, _)| !(*c_idx == idx - 1 || (idx + 1..=idx + 3).contains(c_idx)))
                .map(|(_, c)| c)
                .collect::<Vec<_>>();

            std::fs::write(intptr, patched.join("\n"))?;
        }

        let mnn_define = vendor.join("include").join("MNN").join("MNNDefine.h");
        let patched =
            std::fs::read_to_string(&mnn_define)?.replace(TRACING_SEARCH, TRACING_REPLACE);
        #[cfg(unix)]
        std::fs::set_permissions(&mnn_define, std::fs::Permissions::from_mode(0o644))?;
        std::fs::write(mnn_define, patched)?;
    }

    if *MNN_COMPILE {
        let install_dir = out_dir.join("mnn-install");
        build_cmake(&vendor, &install_dir)?;
        println!(
            "cargo:rustc-link-search=native={}",
            install_dir.join("lib").display()
        );
    } else {
        let lib_dir = resolve_prebuilt_lib_dir().with_context(|| {
            "MNN prebuilt library not found. On Windows x64 run scripts/download_mnn_windows.ps1; \
             on Android run scripts/download_mnn_android.ps1. Or set MNN_LIB_DIR, or MNN_COMPILE=1 to build from source."
        })?;
        println!("cargo:rustc-link-search=native={}", lib_dir.display());
        println!("cargo:rerun-if-changed={}", lib_dir.join("MNN.lib").display());
        println!("cargo:rerun-if-changed={}", lib_dir.join("libMNN.so").display());
        if *TARGET_OS == "windows" && MNN_LINK.as_str() == "dylib" {
            copy_windows_runtime_dll(&lib_dir)?;
        }
    }

    mnn_c_build(PathBuf::from(MANIFEST_DIR).join("mnn_c"), &vendor)
        .with_context(|| "Failed to build mnn_c")?;
    if is_cross_compiling() {
        write_mnn_cpp_stub(&out_dir).with_context(|| "Failed to write mnn_cpp stub")?;
    } else {
        mnn_cpp_bindgen(&vendor, &out_dir).with_context(|| "Failed to generate mnn_cpp bindings")?;
    }
    println!("cargo:include={vendor}/include", vendor = vendor.display());
    if *TARGET_OS == "macos" {
        #[cfg(feature = "metal")]
        println!("cargo:rustc-link-lib=framework=Foundation");
        #[cfg(feature = "metal")]
        println!("cargo:rustc-link-lib=framework=CoreGraphics");
        #[cfg(feature = "metal")]
        println!("cargo:rustc-link-lib=framework=Metal");
        #[cfg(feature = "coreml")]
        println!("cargo:rustc-link-lib=framework=CoreML");
        #[cfg(feature = "coreml")]
        println!("cargo:rustc-link-lib=framework=CoreVideo");
        #[cfg(feature = "opencl")]
        println!("cargo:rustc-link-lib=framework=OpenCL");
        #[cfg(feature = "opengl")]
        println!("cargo:rustc-link-lib=framework=OpenGL");
    } else {
        // #[cfg(feature = "opencl")]
        // println!("cargo:rustc-link-lib=static=opencl");
    }
    if is_emscripten() {
        // println!("cargo:rustc-link-lib=static=stdc++");
        let emscripten_cache = std::process::Command::new("em-config")
            .arg("CACHE")
            .output()?
            .stdout;
        let emscripten_cache = std::str::from_utf8(&emscripten_cache)?.trim();
        let wasm32_emscripten_libs =
            PathBuf::from(emscripten_cache).join("sysroot/lib/wasm32-emscripten");
        println!(
            "cargo:rustc-link-search=native={}",
            wasm32_emscripten_libs.display()
        );
    }
    match MNN_LINK.as_str() {
        "dylib" => println!("cargo:rustc-link-lib=dylib=MNN"),
        "static" => {
            println!("cargo:rustc-link-lib=static=MNN");
            if *TARGET_OS == "windows" && !*MNN_COMPILE {
                // Official prebuilt Static/MD MNN.lib pulls in MSVC C++ STL objects.
                println!("cargo:rustc-link-lib=dylib=msvcprt");
            }
        }
        other => panic!("Invalid MNN_LINK={other}, expected dylib or static"),
    }
    Ok(())
}

pub fn mnn_cpp_bindgen(vendor: impl AsRef<Path>, out: impl AsRef<Path>) -> Result<()> {
    let vendor = vendor.as_ref();
    let mut bindings = bindgen::Builder::default()
        .clang_args(["-x", "c++"])
        .clang_args(["-std=c++14"])
        .clang_arg(CxxOption::VULKAN.cxx())
        .clang_arg(CxxOption::METAL.cxx())
        .clang_arg(CxxOption::COREML.cxx())
        .clang_arg(CxxOption::OPENCL.cxx())
        .clang_arg(format!("-I{}", vendor.join("include").to_string_lossy()));
    bindings = apply_android_bindgen(bindings)?;
    let bindings = bindings
        .generate_cstr(true)
        .generate_inline_functions(true)
        .size_t_is_usize(true)
        .emit_diagnostics()
        .ctypes_prefix("core::ffi")
        .header(
            vendor
                .join("include")
                .join("MNN")
                .join("Interpreter.hpp")
                .to_string_lossy(),
        )
        .allowlist_item(".*SessionInfoCode.*");
    // let cmd = bindings.command_line_flags().join(" ");
    // println!("cargo:warn=bindgen: {}", cmd);
    let bindings = bindings.generate()?;
    bindings.write_to_file(out.as_ref().join("mnn_cpp.rs"))?;
    Ok(())
}

pub fn mnn_c_build(path: impl AsRef<Path>, vendor: impl AsRef<Path>) -> Result<()> {
    configure_android_cc()?;
    let windows_prebuilt_dylib =
        *TARGET_OS == "windows" && !*MNN_COMPILE && MNN_LINK.as_str() == "dylib";
    let windows_prebuilt_static =
        *TARGET_OS == "windows" && !*MNN_COMPILE && MNN_LINK.as_str() == "static";
    let mnn_c = path.as_ref();
    mnn_c.read_dir()?.flatten().for_each(|e| {
        rerun_if_changed(e.path());
    });
    let files = mnn_c.read_dir()?.flatten().map(|e| e.path()).filter(|e| {
        let name = e.file_name().and_then(|s| s.to_str()).unwrap_or("");
        if name == "stl_link_shim.cpp" {
            return windows_prebuilt_static;
        }
        e.extension() == Some(std::ffi::OsStr::new("cpp"))
            || e.extension() == Some(std::ffi::OsStr::new("c"))
    });
    let vendor = vendor.as_ref();
    cc::Build::new()
        .include(vendor.join("include"))
        // .includes(vulkan_includes(vendor))
        .pipe(|config| {
            if windows_prebuilt_dylib {
                config.define("MNN_SYS_RUNTIME_PROBE_STUB", "1");
            }
            #[cfg(feature = "vulkan")]
            config.define("MNN_VULKAN", "1");
            #[cfg(feature = "opengl")]
            config.define("MNN_OPENGL", "1");
            #[cfg(feature = "metal")]
            config.define("MNN_METAL", "1");
            #[cfg(feature = "coreml")]
            config.define("MNN_COREML", "1");
            #[cfg(feature = "opencl")]
            config.define("MNN_OPENCL", "1");
            if is_emscripten() {
                config.compiler("emcc");
                // We can't compile wasm32-unknown-unknown with emscripten
                config.target("wasm32-unknown-emscripten");
                config.cpp_link_stdlib("c++-noexcept");
            }
            #[cfg(feature = "crt_static")]
            config.static_crt(true);
            config
        })
        .cpp(true)
        .files(files)
        .std("c++14")
        // .pipe(|build| {
        //     let c = build.get_compiler();
        //     use std::io::Write;
        //     writeln!(
        //         std::fs::File::create("./command.txt").unwrap(),
        //         "{:?}",
        //         c.to_command()
        //     )
        //     .unwrap();
        //     build
        // })
        .try_compile("mnn_c")
        .context("Failed to compile mnn_c library")?;
    Ok(())
}

pub fn build_cmake(path: impl AsRef<Path>, install: impl AsRef<Path>) -> Result<()> {
    cmake::Config::new(path)
        .define("CMAKE_CXX_STANDARD", "14")
        .define("MNN_BUILD_SHARED_LIBS", "OFF")
        .define("MNN_SEP_BUILD", "OFF")
        .define("MNN_PORTABLE_BUILD", "ON")
        .define("MNN_USE_SYSTEM_LIB", "OFF")
        .define("MNN_BUILD_CONVERTER", "OFF")
        .define("MNN_BUILD_TOOLS", "OFF")
        .define("CMAKE_INSTALL_PREFIX", install.as_ref())
        // https://github.com/rust-lang/rust/issues/39016
        // https://github.com/rust-lang/cc-rs/pull/717
        // Rust/cc always link with the release CRT (/MD) even in debug builds.
        .pipe(|config| {
            if *TARGET_OS == "windows" {
                config.profile("Release");
                if cfg!(feature = "crt_static") {
                    config.define("CMAKE_MSVC_RUNTIME_LIBRARY", "MultiThreaded");
                } else {
                    config.define("CMAKE_MSVC_RUNTIME_LIBRARY", "MultiThreadedDLL");
                }
            }
            config.define("MNN_WIN_RUNTIME_MT", CxxOption::CRT_STATIC.cmake_value());
            config.define("MNN_USE_THREAD_POOL", CxxOption::THREADPOOL.cmake_value());
            config.define("MNN_OPENMP", CxxOption::OPENMP.cmake_value());
            config.define("MNN_VULKAN", CxxOption::VULKAN.cmake_value());
            config.define("MNN_METAL", CxxOption::METAL.cmake_value());
            config.define("MNN_COREML", CxxOption::COREML.cmake_value());
            config.define("MNN_OPENCL", CxxOption::OPENCL.cmake_value());
            config.define("MNN_OPENGL", CxxOption::OPENGL.cmake_value());
            // config.define("CMAKE_CXX_FLAGS", "-O0");
            // #[cfg(windows)]
            if *TARGET_OS == "android" {
                config.define("MNN_BUILD_FOR_ANDROID_COMMAND", "ON");
            }
            if *TARGET_OS == "windows" {
                config.define("CMAKE_CXX_FLAGS", "-DWIN32=1");
            }

            if is_emscripten() {
                config
                    .define("CMAKE_C_COMPILER", "emcc")
                    .define("CMAKE_CXX_COMPILER", "em++")
                    .target("wasm32-unknown-emscripten");
            }
            config
        })
        .build();
    Ok(())
}

// pub fn try_patch_file(patch: impl AsRef<Path>, file: impl AsRef<Path>) -> Result<()> {
//     let patch = dunce::canonicalize(patch)?;
//     rerun_if_changed(&patch);
//     let patch = std::fs::read_to_string(&patch)?;
//     let patch = diffy::Patch::from_str(&patch)?;
//     let file_path = file.as_ref();
//     let file = std::fs::read_to_string(file_path).context("Failed to read input file")?;
//     let patched_file =
//         diffy::apply(&file, &patch).context("Failed to apply patches using diffy")?;
//     std::fs::write(file_path, patched_file)?;
//     Ok(())
// }

pub fn rerun_if_changed(path: impl AsRef<Path>) {
    println!("cargo:rerun-if-changed={}", path.as_ref().display());
}

// pub fn vulkan_includes(vendor: impl AsRef<Path>) -> Vec<PathBuf> {
//     let vendor = vendor.as_ref();
//     let vulkan_dir = vendor.join("source/backend/vulkan");
//     if cfg!(feature = "vulkan") {
//         vec![
//             vulkan_dir.clone(),
//             vulkan_dir.join("runtime"),
//             vulkan_dir.join("component"),
//             // IDK If the order is important but the cmake file does it like this
//             vulkan_dir.join("buffer/execution"),
//             vulkan_dir.join("buffer/backend"),
//             vulkan_dir.join("buffer"),
//             vulkan_dir.join("buffer/shaders"),
//             // vulkan_dir.join("image/execution"),
//             // vulkan_dir.join("image/backend"),
//             // vulkan_dir.join("image"),
//             // vulkan_dir.join("image/shaders"),
//             vendor.join("schema/current"),
//             vendor.join("3rd_party/flatbuffers/include"),
//             vendor.join("source"),
//         ]
//     } else {
//         vec![]
//     }
// }

pub fn is_emscripten() -> bool {
    *TARGET_OS == "emscripten" && *TARGET_ARCH == "wasm32"
}

pub fn emscripten_cache() -> &'static str {
    &EMSCRIPTEN_CACHE
}

#[derive(Debug, Clone, Copy)]
pub enum CxxOptionValue {
    On,
    Off,
    Value(&'static str),
}

impl From<bool> for CxxOptionValue {
    fn from(b: bool) -> Self {
        if b {
            Self::On
        } else {
            Self::Off
        }
    }
}

impl CxxOptionValue {
    pub const fn from_bool(value: bool) -> Self {
        match value {
            true => Self::On,
            false => Self::Off,
        }
    }
}

impl From<&'static str> for CxxOptionValue {
    fn from(s: &'static str) -> Self {
        match s {
            "ON" => Self::On,
            "OFF" => Self::Off,
            _ => Self::Value(s),
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct CxxOption {
    pub name: &'static str,
    pub value: CxxOptionValue,
}

macro_rules! cxx_option_from_feature {
    ($feature:literal, $cxx:literal) => {{
        CxxOption::from_bool($cxx, cfg!(feature = $feature))
    }};
}
impl CxxOption {
    const fn from_bool(name: &'static str, value: bool) -> Self {
        Self {
            name,
            value: CxxOptionValue::from_bool(value),
        }
    }
    pub const VULKAN: CxxOption = cxx_option_from_feature!("vulkan", "MNN_VULKAN");
    pub const METAL: CxxOption = cxx_option_from_feature!("metal", "MNN_METAL");
    pub const COREML: CxxOption = cxx_option_from_feature!("coreml", "MNN_COREML");
    pub const OPENCL: CxxOption = cxx_option_from_feature!("opencl", "MNN_OPENCL");
    pub const OPENMP: CxxOption = cxx_option_from_feature!("openmp", "MNN_OPENMP");
    pub const OPENGL: CxxOption = cxx_option_from_feature!("opengl", "MNN_OPENGL");
    pub const CRT_STATIC: CxxOption = cxx_option_from_feature!("crt_static", "MNN_WIN_RUNTIME_MT");
    pub const THREADPOOL: CxxOption =
        cxx_option_from_feature!("mnn-threadpool", "MNN_USE_THREAD_POOL");

    pub fn new(name: &'static str, value: impl Into<CxxOptionValue>) -> Self {
        Self {
            name,
            value: value.into(),
        }
    }

    pub fn on(mut self) -> Self {
        self.value = CxxOptionValue::On;
        self
    }

    pub fn off(mut self) -> Self {
        self.value = CxxOptionValue::Off;
        self
    }

    pub fn with_value(mut self, value: &'static str) -> Self {
        self.value = CxxOptionValue::Value(value);
        self
    }

    pub fn cmake(&self) -> String {
        match &self.value {
            CxxOptionValue::On => format!("-D{}=ON", self.name),
            CxxOptionValue::Off => format!("-D{}=OFF", self.name),
            CxxOptionValue::Value(v) => format!("-D{}={}", self.name, v),
        }
    }

    pub fn cmake_value(&self) -> &'static str {
        match &self.value {
            CxxOptionValue::On => "ON",
            CxxOptionValue::Off => "OFF",
            CxxOptionValue::Value(v) => v,
        }
    }

    pub fn cxx(&self) -> String {
        match &self.value {
            CxxOptionValue::On => format!("-D{}=1", self.name),
            CxxOptionValue::Off => format!("-D{}=0", self.name),
            CxxOptionValue::Value(v) => format!("-D{}={}", self.name, v),
        }
    }

    pub fn enabled(&self) -> bool {
        match self.value {
            CxxOptionValue::On => true,
            CxxOptionValue::Off => false,
            CxxOptionValue::Value(_) => true,
        }
    }
}
