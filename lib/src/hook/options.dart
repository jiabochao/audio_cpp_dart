import 'package:hooks/hooks.dart';

/// Where the native library comes from.
enum LibrarySource {
  /// Prebuilt release archive when one exists for the target, otherwise a
  /// source build.
  auto,

  /// Upstream release archive; fails for targets without one.
  prebuilt,

  /// CMake build of the upstream sources.
  build,

  /// A library the user already has on disk.
  local,
}

/// The `hooks: user_defines: audio_cpp_dart:` section of the root pubspec.
///
/// ```yaml
/// hooks:
///   user_defines:
///     audio_cpp_dart:
///       source: auto            # auto | prebuilt | build | local
///       backend: vulkan         # cpu, cpu-portable, vulkan, cuda13.3, metal, ...
///       local_library: path/to/libaudiocpp.so   # source: local
///       source_dir: ../audio.cpp                # source: build (optional)
///       cmake_args: [-DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod]
///       model_set: full         # full | core | custom
///       models: [kokoro_tts, silero_vad]        # model_set: custom
///       build_type: Release
///       jobs: 8
///       bundle_msvc_runtime: true
/// ```
final class HookOptions {
  final LibrarySource source;
  final String? backend;
  final Uri? localLibrary;
  final Uri? sourceDir;
  final List<String> cmakeArgs;
  final String modelSet;
  final List<String> models;
  final String buildType;
  final int? jobs;
  final bool bundleMsvcRuntime;

  HookOptions({
    this.source = LibrarySource.auto,
    this.backend,
    this.localLibrary,
    this.sourceDir,
    this.cmakeArgs = const [],
    this.modelSet = 'full',
    this.models = const [],
    this.buildType = 'Release',
    this.jobs,
    this.bundleMsvcRuntime = true,
  });

  factory HookOptions.fromInput(HookInput input) {
    final defines = input.userDefines;
    final sourceName = _string(defines['source']) ?? 'auto';
    final source = LibrarySource.values.firstWhere(
      (s) => s.name == sourceName,
      orElse: () => throw FormatException(
        'audio_cpp_dart: unknown source "$sourceName"; expected one of '
        '${LibrarySource.values.map((s) => s.name).join(', ')}.',
      ),
    );
    final localLibrary = defines.path('local_library');
    if (source == LibrarySource.local && localLibrary == null) {
      throw const FormatException(
        'audio_cpp_dart: source "local" requires local_library.',
      );
    }
    return HookOptions(
      source: source,
      backend: _string(defines['backend']),
      localLibrary: localLibrary,
      sourceDir: defines.path('source_dir'),
      cmakeArgs: _stringList(defines['cmake_args']),
      modelSet: _string(defines['model_set']) ?? 'full',
      models: _stringList(defines['models']),
      buildType: _string(defines['build_type']) ?? 'Release',
      jobs: switch (defines['jobs']) {
        final int jobs => jobs,
        final String jobs => int.parse(jobs),
        _ => null,
      },
      bundleMsvcRuntime: defines['bundle_msvc_runtime'] != false,
    );
  }

  static String? _string(Object? value) => switch (value) {
    null => null,
    final String s when s.isEmpty => null,
    final String s => s,
    final other => '$other',
  };

  static List<String> _stringList(Object? value) => switch (value) {
    null => const [],
    final List<Object?> list => [for (final e in list) '$e'],
    final String s =>
      s.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList(),
    final other => ['$other'],
  };
}
