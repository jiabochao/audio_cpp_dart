import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

import 'options.dart';
import 'prebuilt.dart';

/// Asset name of the main library; matches the `@DefaultAsset` of the
/// generated bindings (`package:audio_cpp_dart/audiocpp`).
const mainAssetName = 'audiocpp';

/// Emits libaudiocpp, plus anything it needs beside it, as code assets.
Future<void> buildAudioCpp(
  BuildInput input,
  BuildOutputBuilder output, {
  required Logger logger,
}) async {
  final code = input.config.code;
  final os = code.targetOS;
  final arch = code.targetArchitecture;
  final options = HookOptions.fromInput(input);
  final backend = options.backend ?? defaultBackend(os, arch);

  // audio.cpp is not 32-bit clean (and its models would not fit a 32-bit
  // address space). Emitting nothing keeps multi-ABI Flutter builds working;
  // the library is simply absent on armeabi-v7a / x86 devices.
  if (os == OS.android &&
      (arch == Architecture.arm || arch == Architecture.ia32) &&
      options.source != LibrarySource.local) {
    logger.warning(
      'audio_cpp_dart: audio.cpp does not support 32-bit Android ($arch); '
      'no native library is bundled for it.',
    );
    return;
  }

  final List<File> libraries;
  switch (options.source) {
    case LibrarySource.local:
      libraries = _localLibraries(options.localLibrary!, os);
    case LibrarySource.prebuilt || LibrarySource.auto:
      final prebuilt = prebuilts[os]?[arch]?[backend];
      if (prebuilt != null) {
        libraries = await _prebuiltLibraries(input, prebuilt, os, logger);
        break;
      }
      if (options.source == LibrarySource.prebuilt) {
        final available = prebuilts[os]?[arch]?.keys.join(', ');
        throw UnsupportedError(
          'audio_cpp_dart: no prebuilt audio.cpp $audioCppTag for '
          '$os/$arch backend "$backend"'
          '${available == null ? '' : ' (available: $available)'}. '
          'Use `source: build` or `source: auto`.',
        );
      }
      libraries = await _sourceBuild(input, options, backend, logger);
    case LibrarySource.build:
      libraries = await _sourceBuild(input, options, backend, logger);
  }

  final mainFileName = os.dylibFileName(mainAssetName);
  final outDir = Directory.fromUri(input.outputDirectory.resolve('lib/'));
  if (outDir.existsSync()) outDir.deleteSync(recursive: true);
  outDir.createSync(recursive: true);

  final main = libraries.first;
  final mainOut = main.copySync('${outDir.path}/$mainFileName');
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: mainAssetName,
      linkMode: DynamicLoadingBundled(),
      file: mainOut.uri,
    ),
  );

  for (final library in libraries.skip(1)) {
    final name = _baseName(library.path);
    if (os == OS.windows &&
        !options.bundleMsvcRuntime &&
        _msvcRuntime.hasMatch(name)) {
      continue;
    }
    final copy = library.copySync('${outDir.path}/$name');
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'runtime/$name',
        linkMode: DynamicLoadingBundled(),
        file: copy.uri,
      ),
    );
  }
}

final _msvcRuntime = RegExp(
  r'^(msvcp|vcruntime|vcomp|concrt)\d+.*\.dll$',
  caseSensitive: false,
);

String _baseName(String path) => path.split(RegExp(r'[/\\]')).last;

/// Shared-library files in [dir], main library first.
///
/// Symlinks are skipped: release archives ship `libaudiocpp.so ->
/// libaudiocpp.so.0 -> libaudiocpp.so.0.1.0`, and only the real file is
/// bundled (under the canonical asset file name).
List<File> _librariesIn(Directory dir, OS os) {
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                FileSystemEntity.typeSync(f.path, followLinks: false) ==
                FileSystemEntityType.file,
          )
          .where((f) => _isSharedLibrary(_baseName(f.path), os))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final mainIndex = files.indexWhere(
    (f) => _isMainLibrary(_baseName(f.path), os),
  );
  if (mainIndex < 0) {
    throw StateError('audio_cpp_dart: no audiocpp library in ${dir.path}.');
  }
  return [files.removeAt(mainIndex), ...files];
}

bool _isSharedLibrary(String name, OS os) => switch (os) {
  OS.windows => name.toLowerCase().endsWith('.dll'),
  OS.macOS || OS.iOS => name.endsWith('.dylib'),
  _ => RegExp(r'\.so(\.\d+)*$').hasMatch(name),
};

bool _isMainLibrary(String name, OS os) => switch (os) {
  OS.windows => name.toLowerCase() == 'audiocpp.dll',
  OS.macOS || OS.iOS => RegExp(r'^libaudiocpp(\.\d+)*\.dylib$').hasMatch(name),
  _ => RegExp(r'^libaudiocpp\.so(\.\d+)*$').hasMatch(name),
};

List<File> _localLibraries(Uri location, OS os) {
  final type = FileSystemEntity.typeSync(location.toFilePath());
  return switch (type) {
    FileSystemEntityType.directory => _librariesIn(
      Directory.fromUri(location),
      os,
    ),
    FileSystemEntityType.notFound => throw ArgumentError(
      'audio_cpp_dart: local_library ${location.toFilePath()} does not exist.',
    ),
    _ => [File(File.fromUri(location).resolveSymbolicLinksSync())],
  };
}

// ---------------------------------------------------------------------------
// Prebuilt release archives
// ---------------------------------------------------------------------------

Future<List<File>> _prebuiltLibraries(
  BuildInput input,
  PrebuiltLibrary prebuilt,
  OS os,
  Logger logger,
) async {
  final libDir = await _fetchArchive(input, prebuilt.library, logger);
  final libraries = _librariesIn(Directory('${libDir.path}/libs'), os);
  if (prebuilt.cudaRuntime case final runtime?) {
    final runtimeDir = await _fetchArchive(input, runtime, logger);
    libraries.addAll(
      runtimeDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => _isSharedLibrary(_baseName(f.path), os)),
    );
  }
  return libraries;
}

/// Downloads, verifies and extracts [archive] once into the shared output
/// directory, which is preserved across builds and configurations.
Future<Directory> _fetchArchive(
  BuildInput input,
  ReleaseArchive archive,
  Logger logger,
) async {
  final root = Directory.fromUri(
    input.outputDirectoryShared.resolve('prebuilt/${archive.sha256}/'),
  );
  final done = File('${root.path}/.extracted');
  final extracted = Directory('${root.path}/contents');
  if (done.existsSync()) return extracted;

  root.createSync(recursive: true);
  final download = File('${root.path}/${archive.fileName}');
  if (!download.existsSync() || await _sha256(download) != archive.sha256) {
    logger.info('Downloading ${archive.url}');
    await _download(archive.url, download);
    final actual = await _sha256(download);
    if (actual != archive.sha256) {
      download.deleteSync();
      throw StateError(
        'audio_cpp_dart: checksum mismatch for ${archive.fileName}: '
        'expected ${archive.sha256}, got $actual.',
      );
    }
  }
  if (extracted.existsSync()) extracted.deleteSync(recursive: true);
  logger.info('Extracting ${archive.fileName}');
  await extractFileToDisk(download.path, extracted.path);
  download.deleteSync();
  done.writeAsStringSync(archive.fileName);
  return extracted;
}

Future<String> _sha256(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> _download(Uri url, File destination) async {
  final client = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
  final partial = File('${destination.path}.part');
  try {
    for (var attempt = 1; ; attempt++) {
      try {
        final request = await client.getUrl(url);
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          throw HttpException('HTTP ${response.statusCode}', uri: url);
        }
        await response.pipe(partial.openWrite());
        partial.renameSync(destination.path);
        return;
      } on IOException {
        if (attempt >= 3) rethrow;
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
    }
  } finally {
    client.close();
  }
}

// ---------------------------------------------------------------------------
// Source builds
// ---------------------------------------------------------------------------

Future<List<File>> _sourceBuild(
  BuildInput input,
  HookOptions options,
  String backend,
  Logger logger,
) async {
  final code = input.config.code;
  final os = code.targetOS;
  final arch = code.targetArchitecture;

  final sourceDir = options.sourceDir != null
      ? Directory.fromUri(options.sourceDir!)
      : await _fetchSources(input, logger);
  if (!File('${sourceDir.path}/CMakeLists.txt').existsSync()) {
    throw StateError(
      'audio_cpp_dart: ${sourceDir.path} is not an audio.cpp checkout.',
    );
  }

  final tools = _CMakeTools.find(input);
  final buildDir = Directory.fromUri(input.outputDirectory.resolve('cmake/'));
  // A CMake build tree is tied to its source directory.
  final sourceMarker = File('${buildDir.path}/.audiocpp_source');
  if (buildDir.existsSync() &&
      (!sourceMarker.existsSync() ||
          sourceMarker.readAsStringSync() != sourceDir.path)) {
    buildDir.deleteSync(recursive: true);
  }
  buildDir.createSync(recursive: true);
  sourceMarker.writeAsStringSync(sourceDir.path);
  final args = <String>[
    '-S',
    sourceDir.path,
    '-B',
    buildDir.path,
    ...tools.generatorArgs(os, arch),
    '-DCMAKE_BUILD_TYPE=${options.buildType}',
    '-DAUDIOCPP_BUILD_C_API=ON',
    '-DAUDIOCPP_DEPLOYMENT_BUILD=ON',
    '-DAUDIOCPP_VERSION=$audioCppTag',
    '-DAUDIOCPP_MODEL_SET=${options.modelSet}',
    '-DAUDIOCPP_MODELS=${options.models.join(';')}',
    '-DENGINE_ENABLE_NATIVE_CPU=OFF',
    '-DENGINE_BUILD_TESTS=OFF',
    '-DENGINE_BUILD_EXAMPLES=OFF',
    ..._backendArgs(os, backend),
    ..._targetArgs(input, tools),
    ...options.cmakeArgs,
  ];

  logger.info('Configuring audio.cpp for $os/$arch ($backend)');
  await _run(tools.cmake, args, logger);
  logger.info('Building audio.cpp; this takes a while on first build');
  await _run(tools.cmake, [
    '--build',
    buildDir.path,
    '--target',
    'audiocpp',
    '--config',
    options.buildType,
    '--parallel',
    '${options.jobs ?? Platform.numberOfProcessors}',
  ], logger);

  final binDir = Directory('${buildDir.path}/bin');
  final configDir = Directory('${binDir.path}/${options.buildType}');
  return _librariesIn(
    os == OS.windows && configDir.existsSync() ? configDir : binDir,
    os,
  );
}

List<String> _backendArgs(OS os, String backend) {
  final metal = backend == 'metal';
  final vulkan = backend.startsWith('vulkan');
  final cuda = backend.startsWith('cuda');
  final hip = backend == 'hip' || backend == 'rocm';
  if (!metal && !vulkan && !cuda && !hip && !backend.startsWith('cpu')) {
    throw ArgumentError('audio_cpp_dart: unknown backend "$backend".');
  }
  return [
    '-DENGINE_ENABLE_METAL=${metal ? 'ON' : 'OFF'}',
    '-DENGINE_ENABLE_VULKAN=${vulkan ? 'ON' : 'OFF'}',
    '-DENGINE_ENABLE_CUDA=${cuda ? 'ON' : 'OFF'}',
    '-DENGINE_ENABLE_HIP=${hip ? 'ON' : 'OFF'}',
    if (metal) '-DGGML_METAL_EMBED_LIBRARY=ON',
  ];
}

List<String> _targetArgs(BuildInput input, _CMakeTools tools) {
  final code = input.config.code;
  final arch = code.targetArchitecture;
  switch (code.targetOS) {
    case OS.android:
      final ndk = _androidNdk(code);
      final abi = switch (arch) {
        Architecture.arm64 => 'arm64-v8a',
        Architecture.x64 => 'x86_64',
        Architecture.riscv64 => 'riscv64',
        _ => throw UnsupportedError('Android $arch is not supported.'),
      };
      return [
        '-DCMAKE_TOOLCHAIN_FILE=${ndk.path}/build/cmake/android.toolchain.cmake',
        '-DANDROID_ABI=$abi',
        '-DANDROID_PLATFORM=android-${code.android.targetNdkApi}',
        '-DANDROID_STL=c++_static',
        '-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON',
        // Keeps the library self-contained: the NDK's OpenMP runtime would
        // otherwise have to be bundled as well. ggml uses its own threadpool.
        '-DENGINE_ENABLE_OPENMP=OFF',
        '-DGGML_OPENMP=OFF',
      ];
    case OS.iOS:
      final simulator = code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
      return [
        '-DCMAKE_SYSTEM_NAME=iOS',
        // sentencepiece calls set_xcode_property(), which only its own iOS
        // toolchain file defines.
        '-DCMAKE_PROJECT_INCLUDE=${_iosShim(input).path}',
        '-DCMAKE_OSX_SYSROOT=${simulator ? 'iphonesimulator' : 'iphoneos'}',
        '-DCMAKE_OSX_ARCHITECTURES=${_appleArch(arch)}',
        '-DCMAKE_OSX_DEPLOYMENT_TARGET=${_appleTarget(code.iOS.targetVersion, 16)}',
        '-DCMAKE_INSTALL_NAME_DIR=@rpath',
        '-DCMAKE_BUILD_WITH_INSTALL_NAME_DIR=ON',
        '-DENGINE_ENABLE_OPENMP=OFF',
        '-DGGML_OPENMP=OFF',
      ];
    case OS.macOS:
      return [
        '-DCMAKE_OSX_ARCHITECTURES=${_appleArch(arch)}',
        '-DCMAKE_OSX_DEPLOYMENT_TARGET=${_appleTarget(code.macOS.targetVersion, 13)}',
        '-DCMAKE_INSTALL_NAME_DIR=@rpath',
        '-DCMAKE_BUILD_WITH_INSTALL_NAME_DIR=ON',
        '-DENGINE_ENABLE_OPENMP=OFF',
        '-DGGML_OPENMP=OFF',
      ];
    case OS.linux:
      if (arch != Architecture.current) {
        throw UnsupportedError(
          'audio_cpp_dart: cross-compiling for Linux $arch is not supported; '
          'build on a $arch host or use `source: local`.',
        );
      }
      return [
        // As in the upstream release builds: no libstdc++/libgcc_s dependency.
        '-DCMAKE_SHARED_LINKER_FLAGS=-static-libstdc++ -static-libgcc',
      ];
    case OS.windows:
      return const [];
    default:
      throw UnsupportedError(
        'audio_cpp_dart: ${code.targetOS} is not supported.',
      );
  }
}

/// audio.cpp uses floating-point `std::to_chars`, which Apple's libc++ ships
/// from macOS 13.3 / iOS 16.3 (`major` 13 / 16). Older app targets are raised
/// to that, so the library requires it at runtime.
File _iosShim(BuildInput input) {
  final file = File.fromUri(input.outputDirectory.resolve('ios_shim.cmake'));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('''
if(NOT COMMAND set_xcode_property)
  # Only matters for the Xcode generator, which this build does not use.
  macro(set_xcode_property)
  endmacro()
endif()
''');
  return file;
}

String _appleTarget(int configured, int major) =>
    configured > major ? '$configured.0' : '$major.3';

String _appleArch(Architecture arch) => switch (arch) {
  Architecture.arm64 => 'arm64',
  Architecture.x64 => 'x86_64',
  _ => throw UnsupportedError('Apple $arch is not supported.'),
};

/// The NDK that Flutter hands the hook through its C compiler, falling back
/// to the usual environment variables.
Directory _androidNdk(CodeConfig code) {
  // <ndk>/toolchains/llvm/prebuilt/<host>/bin/clang
  if (code.cCompiler?.compiler case final compiler?) {
    final ndk = File.fromUri(
      compiler,
    ).parent.parent.parent.parent.parent.parent;
    if (File('${ndk.path}/build/cmake/android.toolchain.cmake').existsSync()) {
      return ndk;
    }
  }
  final env = Platform.environment;
  for (final key in [
    'ANDROID_NDK_HOME',
    'ANDROID_NDK_ROOT',
    'ANDROID_NDK',
    'ANDROID_NDK_LATEST_HOME',
  ]) {
    final value = env[key];
    if (value != null &&
        File('$value/build/cmake/android.toolchain.cmake').existsSync()) {
      return Directory(value);
    }
  }
  if (env['ANDROID_HOME'] case final home?) {
    final ndks = Directory('$home/ndk');
    if (ndks.existsSync()) {
      final versions = ndks.listSync().whereType<Directory>().toList()
        ..sort(
          (a, b) => _compareVersions(_baseName(b.path), _baseName(a.path)),
        );
      if (versions.isNotEmpty) return versions.first;
    }
  }
  throw StateError(
    'audio_cpp_dart: Android NDK not found. Build through Flutter, or set '
    'ANDROID_NDK_HOME / ANDROID_HOME.',
  );
}

int _compareVersions(String a, String b) {
  final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
  }
  return pa.length.compareTo(pb.length);
}

/// Downloads the upstream source tree for [audioCppCommit] once.
///
/// Paths are kept short on purpose: the deepest files in the tree
/// (sentencepiece's bundled protobuf) exceed Windows' 260-character MAX_PATH
/// below a long prefix.
Future<Directory> _fetchSources(BuildInput input, Logger logger) async {
  final root = Directory.fromUri(
    input.outputDirectoryShared.resolve(
      'src-${audioCppCommit.substring(0, 12)}/',
    ),
  );
  final tree = Directory('${root.path}/tree');
  final done = File('${root.path}/.extracted');
  if (done.existsSync()) return tree;

  root.createSync(recursive: true);
  final tarball = File('${root.path}/src.tar.gz');
  final url = Uri.parse(
    'https://codeload.github.com/0xShug0/audio.cpp/tar.gz/$audioCppCommit',
  );
  logger.info('Downloading audio.cpp sources from $url');
  await _download(url, tarball);
  final unpacked = Directory('${root.path}/x');
  for (final dir in [unpacked, tree]) {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
  await extractFileToDisk(tarball.path, unpacked.path);
  // codeload archives contain a single `audio.cpp-<commit>/` directory.
  unpacked.listSync().whereType<Directory>().single.renameSync(tree.path);
  unpacked.deleteSync(recursive: true);
  tarball.deleteSync();
  done.writeAsStringSync(audioCppCommit);
  return tree;
}

final class _CMakeTools {
  final String cmake;
  final String? ninja;

  _CMakeTools(this.cmake, this.ninja);

  factory _CMakeTools.find(BuildInput input) {
    final sdkCmake = <String>[];
    if (Platform.environment['ANDROID_HOME'] case final home?) {
      final dir = Directory('$home/cmake');
      if (dir.existsSync()) {
        final versions = dir.listSync().whereType<Directory>().toList()
          ..sort(
            (a, b) => _compareVersions(_baseName(b.path), _baseName(a.path)),
          );
        sdkCmake.addAll(versions.map((d) => '${d.path}/bin'));
      }
    }
    final exe = Platform.isWindows ? '.exe' : '';
    final cmake = _which('cmake$exe', sdkCmake);
    if (cmake == null) {
      throw StateError(
        'audio_cpp_dart: cmake not found on PATH; it is required to build '
        'audio.cpp from source.',
      );
    }
    final ninja = _which('ninja$exe', [File(cmake).parent.path, ...sdkCmake]);
    return _CMakeTools(cmake, ninja);
  }

  List<String> generatorArgs(OS os, Architecture arch) {
    if (os == OS.windows) {
      // Visual Studio generator: finds MSVC without a developer prompt.
      final platform = switch (arch) {
        Architecture.x64 => 'x64',
        Architecture.arm64 => 'ARM64',
        Architecture.ia32 => 'Win32',
        _ => throw UnsupportedError('Windows $arch is not supported.'),
      };
      return ['-A', platform];
    }
    if (ninja != null) return ['-G', 'Ninja', '-DCMAKE_MAKE_PROGRAM=$ninja'];
    return ['-G', 'Unix Makefiles'];
  }

  static String? _which(String name, List<String> extraDirs) {
    final path = Platform.environment['PATH'] ?? '';
    final dirs = [
      ...path.split(Platform.isWindows ? ';' : ':'),
      ...extraDirs,
      if (Platform.isMacOS) ...['/opt/homebrew/bin', '/usr/local/bin'],
    ];
    for (final dir in dirs.where((d) => d.isNotEmpty)) {
      final candidate = File('$dir${Platform.pathSeparator}$name');
      if (candidate.existsSync()) return candidate.path;
    }
    return null;
  }
}

Future<void> _run(String executable, List<String> args, Logger logger) async {
  logger.info('$executable ${args.join(' ')}');
  final process = await Process.start(executable, args);
  final lines = <String>[];
  void collect(String line) {
    logger.fine(line);
    lines.add(line);
    if (lines.length > 200) lines.removeAt(0);
  }

  final stdoutDone = process.stdout
      .transform(systemEncoding.decoder)
      .transform(const LineSplitter())
      .forEach(collect);
  final stderrDone = process.stderr
      .transform(systemEncoding.decoder)
      .transform(const LineSplitter())
      .forEach(collect);
  final exitCode = await process.exitCode;
  await Future.wait([stdoutDone, stderrDone]);
  if (exitCode != 0) {
    throw ProcessException(
      executable,
      args,
      'exited with $exitCode. Last output:\n${lines.join('\n')}',
      exitCode,
    );
  }
}
