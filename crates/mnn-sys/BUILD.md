# mnn-sys 构建说明

`mnn-sys` 是 MNN 的 Rust FFI 层：用 **cc** 编译 C++ 胶水（`mnn_c/`），再链接 **libMNN**（预编译或 CMake 本地编译）。

**Windows** 与 **Android** 均默认走官方预编译包，避免本地 CMake 编译 MNN。Windows 需额外处理 MSVC CRT / 静态库问题；Android 走共享库 `libMNN.so`，链路相对简单。

---

## 快速开始

### Windows x64（推荐）

```powershell
# 仓库根目录
powershell -ExecutionPolicy Bypass -File .\scripts\download_mnn_windows.ps1

cargo test -p infer-core-ffi --features backend-mnn --no-default-features
```

脚本会安装：

| 路径 | 内容 |
|------|------|
| `third_party/mnn/source/` | MNN 源码（头文件 + bindgen；`mnn_c` 编译需要） |
| `third_party/mnn/windows/x64-md/` | `MNN.dll` + import `MNN.lib`（Dynamic /MD） |

检测到上述预编译库后，`build.rs` 自动设置 `MNN_COMPILE=0`、`MNN_LINK=dylib`，并把 `MNN.dll` 复制到 `target/<profile>/` 与 `deps/`。

**发布或拷贝 `infer_core.dll` 时，需同目录附带 `MNN.dll`。**

已有本地解压目录时：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\download_mnn_windows.ps1 `
  -ImportFrom "C:\path\to\mnn_3.6.0_windows_x64_cpu_opencl_vulkan_avx512"
```

官方包：[mnn_3.6.0_windows_x64_cpu_opencl_vulkan_avx512.zip](https://github.com/alibaba/MNN/releases/download/3.6.0/mnn_3.6.0_windows_x64_cpu_opencl_vulkan_avx512.zip)

### Android（推荐）

Android 路径比 Windows 更早定型：**官方预编译 `libMNN.so` + NDK 交叉编译 Rust**，由 `build_android.ps1` 一键串联。

#### 1. 准备 MNN 产物

```powershell
# 仓库根目录：拉 source + arm64-v8a / armeabi-v7a 官方 .so
powershell -ExecutionPolicy Bypass -File .\scripts\download_mnn_android.ps1
```

| 路径 | 内容 |
|------|------|
| `third_party/mnn/source/` | MNN 源码（`mnn_c` 头文件、vendor patch） |
| `third_party/mnn/android/arm64-v8a/` | 官方预编译 `libMNN.so`（及 `libMNN_CL.so`、`libMNN_Vulkan.so` 等） |
| `third_party/mnn/android/armeabi-v7a/` | 同上（32 位 ARM，按需） |

官方包：[mnn_3.6.0_android_armv7_armv8_cpu_opencl_vulkan.zip](https://github.com/alibaba/MNN/releases/download/3.6.0/mnn_3.6.0_android_armv7_armv8_cpu_opencl_vulkan.zip)

#### 2. 构建 `libinfer_core.so`

前置：**Android NDK**（`ANDROID_NDK_HOME` 或 Android Studio 默认安装路径）、**cargo-ndk**（`cargo install cargo-ndk`）。

```powershell
# 默认：arm64-v8a + x86_64（模拟器）
powershell -ExecutionPolicy Bypass -File .\scripts\build_android.ps1

# 仅真机 arm64
powershell -ExecutionPolicy Bypass -File .\scripts\build_android.ps1 -Abi arm64-v8a

# 顺带重新下载 MNN
powershell -ExecutionPolicy Bypass -File .\scripts\build_android.ps1 -DownloadMnn
```

脚本对每个 ABI 会设置：

```text
MNN_COMPILE=0
MNN_LINK=dylib
MNN_LIB_DIR=third_party/mnn/android/<abi>
MNN_SRC=third_party/mnn/source
ANDROID_NDK_HOME=<自动探测>
```

然后执行：

```text
cargo ndk -t <abi> -o android/jniLibs build --release -p infer-core-ffi \
  --no-default-features --features backend-mnn --lib
```

产出在 `android/jniLibs/<abi>/libinfer_core.so`，并自动复制运行时依赖：

| `.so` | 来源 |
|-------|------|
| `libMNN.so` | 预编译（或 x86_64 本地 CMake 产物） |
| `libMNN_CL.so` / `libMNN_Vulkan.so` | 官方 arm 包（存在则复制） |
| `libc++_shared.so` | 预编译目录或 NDK sysroot |

Flutter / APK 打包时以 `android/jniLibs/` 为准（见仓库 `.gitignore`，该目录为构建产物）。

#### 3. ABI 与预编译覆盖

| ABI | 预编译 | 说明 |
|-----|--------|------|
| **arm64-v8a** | 官方 zip | 真机主力，download 脚本默认安装 |
| **armeabi-v7a** | 官方 zip | 32 位 ARM，`download_mnn_android.ps1 -Abi armeabi-v7a` |
| **x86_64** | **无官方包** | 模拟器：`build_android.ps1` 会自动调用 `build_mnn_android_x86_64.ps1`，用 NDK + CMake **本地编** `libMNN.so`（CPU only，无 OpenCL/Vulkan） |

`build.rs` 在 `target_os=android` 时会自动探测 `third_party/mnn/android/<abi>/libMNN.so`，与 `build_android.ps1` 设置的 `MNN_LIB_DIR` 一致。

#### 4. Android 与 Windows 的差异

| | Android | Windows |
|---|---------|---------|
| 链接方式 | `dylib` → `libMNN.so` | `dylib` → `MNN.dll` |
| 预编译 | 官方提供 arm ABI | 官方 x64 Dynamic/MD |
| C++ 工具链 | NDK clang（`build.rs` 自动选 `$triple-clang++`） | MSVC（host） |
| `runtime_probe` | 链共享库，可调 `MNNGetExtraRuntimeCreator` | DLL 不导出内部符号 → **stub** |
| 交叉编译 bindgen | 写 `mnn_cpp` stub，不跑 libclang 绑 MNN C++ | 本机 bindgen |
| 额外 link | `infer-core-ffi` 在 static 回退时链 `c++_shared` | 复制 `MNN.dll` 到 target |

#### 5. 模拟器 x86_64 单独构建 MNN

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_mnn_android_x86_64.ps1
```

在 `third_party/mnn/android/x86_64/` 生成 `libMNN.so`（Release 共享库）。需要本机 **CMake + Ninja**（或 Android SDK 自带 CMake）。

### 从源码编译 MNN（高级 / 无预编译时）

未找到预编译库时，`build.rs` 默认 `MNN_COMPILE=1`，通过 CMake 编译 vendor 源码。

```powershell
# 需完整 MNN 源码（download 脚本会拉 source/）
$env:MNN_COMPILE = "1"
$env:MNN_SRC = "D:\repo\local-infer-core\third_party\mnn\source"  # 可选，默认自动探测
cargo build -p mnn-sys
```

Windows 上 CMake 路径会强制 **Release + `/MD`**，与 Rust/cc 的 CRT 对齐（见下文「Windows 链接要点」）。

---

## 环境变量

| 变量 | 含义 | 默认 |
|------|------|------|
| `MNN_COMPILE` | `1` 用 CMake 编 MNN；`0` 用预编译 | 有预编译 → `0`，否则 `1` |
| `MNN_LINK` | `static` 或 `dylib` | 有预编译 → `dylib`，否则 `static` |
| `MNN_LIB_DIR` | 预编译库目录（含 `MNN.lib` 或 `libMNN.so`） | 按平台自动探测 `third_party/mnn/...` |
| `MNN_SRC` | MNN 源码根目录 | `third_party/mnn/source` 或 `vendor/` |
| `ANDROID_NDK_HOME` / `NDK_HOME` | Android 交叉编译 | Android 构建必填 |
| `CARGO_NDK_ANDROID_API_LEVEL` | NDK API level（可选） | 默认 21 |

Android 交叉编译时，`build.rs` 会通过 `$TARGET-clang++` 调用 NDK 编译 `mnn_c`；bindgen 使用 NDK clang 的 sysroot（本机 `LIBCLANG_PATH` 可指向独立 LLVM，见 `configure_bindgen_libclang`）。

---

## Cargo features

| Feature | 作用 |
|---------|------|
| `opencl` / `vulkan` | 启用对应 MNN backend（需预编译包或 CMake 选项一致） |
| `mnn-threadpool` | MNN 线程池（默认开启） |
| `crt_static` | Windows `/MT` 静态 CRT（与官方 Dynamic/MD 预编译**不**匹配，慎用） |
| `metal` / `coreml` | macOS / iOS |

`infer-core` 的 `backend-mnn` 会传递 `opencl`、`vulkan` 等 feature 到本 crate。

---

## Windows 链接要点（为何预编译 Dynamic/MD）

Rust（MSVC）与 **cc** 编译的 `mnn_c` 在 debug 构建下仍使用 **`/MD`（Release CRT）**，而 CMake debug 配置默认 **`/MDd`**，混链会报 `LNK2038`（`_ITERATOR_DEBUG_LEVEL` / `RuntimeLibrary` 不匹配）。

官方 Windows 包提供两种 `MNN.lib`：

| 类型 | 路径 | 说明 |
|------|------|------|
| **Dynamic /MD** | `lib/x64/Release/Dynamic/MD/` | import lib + `MNN.dll`；**推荐** |
| **Static /MD** | `lib/x64/Release/Static/MD/` | 约 500MB 单体静态库 |

不推荐在 Rust 工程里链 **Static/MD**：

1. **STL 符号**：静态库引用 `__std_min_element_4i` 等 MSVC 内部符号，与本地 VS 版本不一致时会 `LNK2019`。
2. **内部 API**：如 `MNNGetExtraRuntimeCreator` 在静态库中有完整符号，但 Dynamic import lib 不导出。

当前策略：

- 预编译 + **`MNN_LINK=dylib`** → 链 `MNN.dll`，C++ 实现在 DLL 内。
- `runtime_probe_c.cpp` 在 dylib 模式下使用 **`MNN_SYS_RUNTIME_PROBE_STUB`**：按已启用的 feature 声明 cpu/opencl/vulkan，不调用未导出的内部 API。
- 若有人强制 `MNN_LINK=static` + Static 预编译，会编译 `stl_link_shim.cpp` 尝试补齐 STL 符号（仍可能因工具链差异失败）。

链接时出现的 **`LNK4099: PDB 'vc140.pdb' not found`** 来自预编译库缺少调试符号，可忽略。

---

## Android 链接要点

Android 上 **共享库 `libMNN.so`** 把 MNN 的 C++ 实现和依赖都包在 `.so` 里，Rust 只链动态库，不会把数百 MB 的 `.obj` 拉进最终链接，因此**没有** Windows 上 Static `MNN.lib` 的 MSVC STL 符号问题。

注意：

1. **运行时**：APK / `jniLibs` 里除 `libinfer_core.so` 外，还需带上 `libMNN.so`（及 OpenCL/Vulkan 时的 `libMNN_CL.so`、`libMNN_Vulkan.so`）和 **`libc++_shared.so`**（`build_android.ps1` 会复制）。
2. **x86_64 模拟器**：无官方预编译，首次构建会 CMake 编 MNN，耗时较长，且当前脚本关闭 OpenCL/Vulkan。
3. **静态链 MNN**（`MNN_LINK=static`）：非默认路径；`infer-core-ffi/build.rs` 会额外 `rustc-link-lib=c++_shared`。预编译场景请保持 `MNN_LINK=dylib`。

---

## `build.rs` 做了什么

1. 复制 `MNN_SRC` → `OUT_DIR/vendor`，并 patch `HalideRuntime.h`、`MNNDefine.h`（tracing 转发）。
2. **预编译路径**：`cargo:rustc-link-search` + `rustc-link-lib=dylib=MNN`（或 static）。
3. **CMake 路径**：`cmake::Config` 编 MNN static，Windows 上 `profile("Release")` + `CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL`。
4. **cc**：编译 `mnn_c/*.cpp`（Windows dylib 模式定义 `MNN_SYS_RUNTIME_PROBE_STUB`；Android 用 NDK clang）。
5. **bindgen**：生成本机 `mnn_cpp.rs`（**Android 等交叉编译**时写 stub，避免 host libclang 无法解析 NDK 头文件）。

---

## 故障排查

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| `MNN source directory missing` | 未跑 download 脚本 | `download_mnn_windows.ps1` 或 `download_mnn_android.ps1` |
| `MNN prebuilt library not found` | `third_party/mnn/...` 不完整 | 重新跑 download；或设 `MNN_LIB_DIR` |
| `LNK2038` MD / MDd | 本地 CMake 编 MNN 且未对齐 CRT | 改用预编译，或确认 `build.rs` Windows Release/MD 逻辑 |
| `MNNGetExtraRuntimeCreator` 未解析 | 用了 Dynamic import lib 且未开 stub | 确保 `MNN_LINK=dylib` 且预编译为 Dynamic/MD |
| `__std_min_element_4i` 未解析 | 链了 Static 预编译 MNN.lib | 改 Dynamic/MD，或 `MNN_COMPILE=1` 本地编 |
| 运行缺 DLL | 未带 `MNN.dll` | 与 `infer_core.dll` 同目录，或加入 PATH |
| Android `libMNN.so not found` | 未 download 或 ABI 目录错 | `download_mnn_android.ps1`；x86_64 跑 `build_mnn_android_x86_64.ps1` |
| Android NDK 未找到 | 环境变量 / Studio 未装 NDK | 设 `ANDROID_NDK_HOME` 或安装 NDK |
| Android 运行 `UnsatisfiedLinkError` | jniLibs 缺依赖 `.so` | 确认 `libMNN.so`、`libc++_shared.so` 等与 `libinfer_core.so` 同 ABI 目录 |
| Android x86_64 无 OpenCL/Vulkan | 本地 CMake 脚本关闭了 GPU backend | 预期行为；真机 arm64 用官方包即可 |

强制清理 MNN 构建缓存：

```powershell
Remove-Item -Recurse -Force target\debug\build\mnn-sys-*
cargo clean -p mnn-sys
```

---

## 相关脚本

| 脚本 | 平台 |
|------|------|
| `scripts/download_mnn_windows.ps1` | Windows x64 预编译 + source |
| `scripts/download_mnn_android.ps1` | Android arm 预编译 + source |
| `scripts/build_android.ps1` | Android `infer-core-ffi` 构建（cargo-ndk + 复制 jniLibs） |
| `scripts/build_mnn_android_x86_64.ps1` | 模拟器 x86_64 本地编 `libMNN.so` |
| `scripts/build_release_android.ps1` | Android release 打包（上层脚本） |
