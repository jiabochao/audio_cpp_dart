import 'package:code_assets/code_assets.dart';

/// The audio.cpp release this package binds to. The vendored header in
/// third_party/audiocpp/ is taken from the same release.
const audioCppTag = 'v0.9.5';

/// Commit of [audioCppTag], used for source builds.
const audioCppCommit = '61c7838baf1f7f34769b5b7bd369c0d78edf9535';

const _releaseBase =
    'https://github.com/0xShug0/audio.cpp/releases/download/$audioCppTag';

/// A downloadable release archive.
final class ReleaseArchive {
  final String fileName;
  final String sha256;

  const ReleaseArchive(this.fileName, this.sha256);

  Uri get url => Uri.parse('$_releaseBase/$fileName');
}

/// A prebuilt `lib` package, optionally with the CUDA runtime archive that
/// must accompany it.
final class PrebuiltLibrary {
  final ReleaseArchive library;
  final ReleaseArchive? cudaRuntime;

  const PrebuiltLibrary(this.library, [this.cudaRuntime]);
}

/// Upstream publishes `lib` archives for desktop targets only. Android and iOS
/// (and desktop targets missing here) are built from source.
///
/// Keyed by OS, architecture, then backend. Digests are the ones GitHub
/// reports for the release assets.
final Map<OS, Map<Architecture, Map<String, PrebuiltLibrary>>> prebuilts = {
  OS.linux: {
    Architecture.x64: {
      'cpu': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-ubuntu-x64-cpu.tar.gz',
          'd08ca1d0929d5e19ac4940f3eaf810ff3e99755c7b077f9e52373943afaef4cd',
        ),
      ),
      'cpu-portable': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-ubuntu-x64-cpu-portable.tar.gz',
          'b60fab096d58eb07955409ce3b931de0b5830f5e89ad023dc9f8f1dfa74f1db2',
        ),
      ),
      'vulkan': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-ubuntu-x64-vulkan.tar.gz',
          '928fe3a2e90a72de864f582f5c7c2c58db24466e6dc274fa4169a7c0375d86a2',
        ),
      ),
      'vulkan-portable': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-ubuntu-x64-vulkan-portable.tar.gz',
          'ff732d8daaf5770daa88acd4e2237c516fb9eaab81da69321245bb2669dff1dd',
        ),
      ),
      'cuda12.8': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-ubuntu-x64-cuda12.8.tar.gz',
          'ba1708122290ce1a32ec6040063d2adc9a06ad2d22b9a25d37a8e34f57fc6d45',
        ),
        ReleaseArchive(
          'audio-$audioCppTag-cudart-ubuntu-x64-cuda12.8.tar.gz',
          '732bf2f4b81760529996c076e9a255fa406a296a01c140ab290c62523e145bd0',
        ),
      ),
      'cuda13.3': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-ubuntu-x64-cuda13.3.tar.gz',
          '61091545078e7c0b1ee24f7b48ac3a7f32b7a32d30e419ea65abe35c788d7c4b',
        ),
        ReleaseArchive(
          'audio-$audioCppTag-cudart-ubuntu-x64-cuda13.3.tar.gz',
          'd8c6bf84655310ae34702486ba8641bbe909b22a66605b2cb08fc24b6af84bf9',
        ),
      ),
    },
  },
  OS.windows: {
    Architecture.x64: {
      'cpu': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-windows-x64-cpu.zip',
          'fef51c31705f524f51d47c858f93c7b184bd789eecfa916d5e689f139426171b',
        ),
      ),
      'cpu-portable': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-windows-x64-cpu-portable.zip',
          '0cca326b8a58a81d4646531d7086c34c8e2e829246ef6015602156588d13857d',
        ),
      ),
      'vulkan': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-windows-x64-vulkan.zip',
          '33b16d1afa800c9f73bbcc3d230873296a51fee1dc79512afe0ad14c29fe2d62',
        ),
      ),
      'vulkan-portable': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-windows-x64-vulkan-portable.zip',
          '44b9cb3c07449045da6607a074fd6d4c87f23073cfde285459383e9f1f062405',
        ),
      ),
      'cuda12.4': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-windows-x64-cuda12.4.zip',
          '99ec5fed230f5babcd3d5b59fb8c0c47ca631fda034d16ba96bdb1cc8e4b34cf',
        ),
        ReleaseArchive(
          'audio-$audioCppTag-cudart-windows-x64-cuda12.4.zip',
          'fa55dfaff1d4b5c6e8fac460d64f380b9df76cd46435f187c39b05700f623a7e',
        ),
      ),
      'cuda13.3': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-windows-x64-cuda13.3.zip',
          '7b7735581858082523ae216de12954f7aa4dd55061a3e5006769c87bc4a65ceb',
        ),
        ReleaseArchive(
          'audio-$audioCppTag-cudart-windows-x64-cuda13.3.zip',
          '8614040110cc5852b1dd2192e80344295500f4fa7f3199a51c737c2c7549c3dc',
        ),
      ),
    },
  },
  OS.macOS: {
    Architecture.arm64: {
      'metal': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-macos-arm64-metal.tar.gz',
          '6c66ce9515c3e0bcf298186f6497881a124e97fd9c986afd25e244f43103bd48',
        ),
      ),
    },
    Architecture.x64: {
      // Built with Metal disabled upstream (CI runners have no GPU), so it is
      // the CPU library in practice.
      'cpu': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-macos-x64-metal.tar.gz',
          'd92e6ecdae81c0f914efbea6d2a0a768963ed13610a82fd0dedd4c4f3a6a5277',
        ),
      ),
    },
  },
};

/// The backend used when the user does not pick one.
String defaultBackend(OS os, Architecture architecture) => switch (os) {
  OS.macOS when architecture == Architecture.x64 => 'cpu',
  OS.macOS || OS.iOS => 'metal',
  _ => 'cpu',
};
