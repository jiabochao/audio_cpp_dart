import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'bindings/audiocpp.g.dart';
import 'errors.dart';

/// Throws [AudioCppException] unless [status] is OK. Must run on the thread
/// that made the failing call: `audiocpp_last_error` is thread-local.
void check(audiocpp_status status, [String? operation]) {
  if (status == audiocpp_status.AUDIOCPP_OK) return;
  throw AudioCppException(
    AudioCppStatus.fromNative(status),
    audiocpp_last_error().toDartString(),
    operation: operation,
  );
}

extension CharPointerToString on Pointer<Char> {
  /// Borrowed C string to Dart; `null` for a null pointer.
  String? toDartStringOrNull() =>
      this == nullptr ? null : cast<Utf8>().toDartString();

  String toDartString() => toDartStringOrNull() ?? '';
}

extension StringToNative on String {
  Pointer<Char> toNative(Allocator allocator) =>
      toNativeUtf8(allocator: allocator).cast();
}

extension NullableStringToNative on String? {
  Pointer<Char> toNativeOrNull(Allocator allocator) =>
      this?.toNative(allocator) ?? nullptr;
}

/// Runs once per isolate before the first native call.
///
/// On Windows, libraries the bundled `audiocpp.dll` imports (MSVC runtime,
/// ggml backend DLLs) live next to it, but the loader resolves imports from
/// the executable's directory rather than the DLL's. `dart build cli` puts
/// assets in `lib/` beside `bin/`, so the directory is located through one of
/// the bundled runtime assets and added to the DLL search path.
void ensureInitialized() => _initialized;

final bool _initialized = () {
  if (Platform.isWindows) _addBundledDllDirectory();
  return true;
}();

@Native<Int32 Function()>(
  symbol: 'omp_get_max_threads',
  assetId: 'package:audio_cpp_dart/runtime/vcomp140.dll',
)
external int _vcompProbe();

@Native<Pointer<Void> Function(Size)>(
  symbol: 'ggml_init',
  assetId: 'package:audio_cpp_dart/runtime/ggml-base.dll',
)
external Pointer<Void> _ggmlBaseProbe(int size);

void _addBundledDllDirectory() {
  final probes = <Pointer<Void> Function()>[
    () =>
        Native.addressOf<NativeFunction<Int32 Function()>>(_vcompProbe).cast(),
    () => Native.addressOf<NativeFunction<Pointer<Void> Function(Size)>>(
      _ggmlBaseProbe,
    ).cast(),
  ];
  for (final probe in probes) {
    final Pointer<Void> address;
    try {
      address = probe();
    } on Object {
      continue; // This asset is not part of the build.
    }
    final directory = _moduleDirectory(address);
    if (directory != null) {
      using(
        (arena) => _setDllDirectory(directory.toNativeUtf16(allocator: arena)),
      );
      return;
    }
  }
}

String? _moduleDirectory(Pointer<Void> address) {
  const fromAddress = 0x4; // GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
  const unchangedRefCount = 0x2; // GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT
  return using((arena) {
    final module = arena<Pointer<Void>>();
    if (_getModuleHandleEx(fromAddress | unchangedRefCount, address, module) ==
        0) {
      return null;
    }
    const capacity = 32768;
    final buffer = arena<Uint16>(capacity).cast<Utf16>();
    final length = _getModuleFileName(module.value, buffer, capacity);
    if (length == 0 || length >= capacity) return null;
    final path = buffer.toDartString(length: length);
    final separator = path.lastIndexOf(r'\');
    return separator < 0 ? null : path.substring(0, separator);
  });
}

final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _getModuleHandleEx = _kernel32
    .lookupFunction<
      Int32 Function(Uint32, Pointer<Void>, Pointer<Pointer<Void>>),
      int Function(int, Pointer<Void>, Pointer<Pointer<Void>>)
    >('GetModuleHandleExW');

final _getModuleFileName = _kernel32
    .lookupFunction<
      Uint32 Function(Pointer<Void>, Pointer<Utf16>, Uint32),
      int Function(Pointer<Void>, Pointer<Utf16>, int)
    >('GetModuleFileNameW');

final _setDllDirectory = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Utf16>),
      int Function(Pointer<Utf16>)
    >('SetDllDirectoryW');
