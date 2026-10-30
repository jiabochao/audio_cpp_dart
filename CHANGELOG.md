## 0.1.0

- Initial release, binding audio.cpp v0.9.3 (C ABI 0.2).
- `@Native` FFI bindings generated with ffigen; idiomatic API with
  `Registry`, `Model`, `Session`, `Request`, `TaskResult`, streaming and
  background-isolate `*Async` calls.
- Build hook providing the native library: sha256-verified upstream
  prebuilts for Linux, Windows and macOS; CMake source builds for Android, iOS
  and other targets; or a local library.
