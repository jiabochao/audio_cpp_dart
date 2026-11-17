## 0.2.0

- Upgrade to audio.cpp v0.9.5 (C ABI 0.3), refreshing the vendored header,
  generated bindings, source commit and all prebuilt SHA-256 digests.
- SenseVoice now returns words when `return_timestamps: true` is requested.
- Expose the WebGPU and SYCL backend names.
- Normalize the Apache-2.0 license text so pub.dev recognizes the license.

## 0.1.0

- Initial release, binding audio.cpp v0.9.3 (C ABI 0.2).
- `@Native` FFI bindings generated with ffigen; idiomatic API with
  `Registry`, `Model`, `Session`, `Request`, `TaskResult`, streaming and
  background-isolate `*Async` calls.
- Build hook providing the native library: sha256-verified upstream
  prebuilts for Linux, Windows and macOS; CMake source builds for Android, iOS
  and other targets; or a local library.
