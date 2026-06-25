// Minimal SessionInfoCode bindings (from Interpreter.hpp).
// Used when cross-compiling: parsing full C++ headers via bindgen is fragile on Android NDK.
#[doc = " memory session used in MB, float*"]
pub const MNN_Interpreter_SessionInfoCode_MEMORY: MNN_Interpreter_SessionInfoCode = 0;
#[doc = " float operation needed in session in M, float*"]
pub const MNN_Interpreter_SessionInfoCode_FLOPS: MNN_Interpreter_SessionInfoCode = 1;
#[doc = " Backends in session in M, int*, length >= 1 + number of configs when create session"]
pub const MNN_Interpreter_SessionInfoCode_BACKENDS: MNN_Interpreter_SessionInfoCode = 2;
#[doc = " Resize Info, int* , the mean different from API\nInterpreter::getSessionInfo: 0: ready to execute, 1: need malloc, 2: need resize\nRuntimeManager::getInfo: 0: no resize, 1: re-malloc, 2: resize"]
pub const MNN_Interpreter_SessionInfoCode_RESIZE_STATUS: MNN_Interpreter_SessionInfoCode = 3;
#[doc = " Mode / NumberThread, int*"]
pub const MNN_Interpreter_SessionInfoCode_THREAD_NUMBER: MNN_Interpreter_SessionInfoCode = 4;
#[doc = " Mode / NumberThread, int*"]
pub const MNN_Interpreter_SessionInfoCode_ALL: MNN_Interpreter_SessionInfoCode = 5;
pub type MNN_Interpreter_SessionInfoCode = core::ffi::c_int;
