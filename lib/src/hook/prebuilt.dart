import 'package:code_assets/code_assets.dart';

/// The audio.cpp release this package binds to. The vendored header in
/// third_party/audiocpp/ is taken from the same release.
const audioCppTag = 'v0.9.3';

/// Commit of [audioCppTag], used for source builds.
const audioCppCommit = '41c1f8ffa0d13a1b7e366e30ea5fe5ab8d169d48';

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
          'c21204a8839d596500b2338acd1c69e73a5e1737720e54b77f039c3239588fa8',
        ),
      ),
      'cpu-portable': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-ubuntu-x64-cpu-portable.tar.gz',
          '38c7b7875ebd748b4ece5c865812c7ad9c83ded37ef21172abc1c2b506d3fbb0',
        ),
      ),
      'vulkan': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-ubuntu-x64-vulkan.tar.gz',
          'b551153844eefba21dc9f72c81ab92df261a5d0aa4dd4c5138443631398f947c',
        ),
      ),
      'vulkan-portable': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-ubuntu-x64-vulkan-portable.tar.gz',
          'e3aa9043cec0065da4f89997f68f9867e23c88f8c38be06dff1e4dd75170a7be',
        ),
      ),
      'cuda12.8': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-ubuntu-x64-cuda12.8.tar.gz',
          '204d813c39318f592ba5fd33d7cd83b0b2c6fa6e32c5659d02e863b6449f7851',
        ),
        ReleaseArchive(
          'audio-$audioCppTag-cudart-ubuntu-x64-cuda12.8.tar.gz',
          '2fcbaff8078b9eaed47a4a8e879c10dcf1f12fd31f2d52b29214fc9d45cfa198',
        ),
      ),
      'cuda13.3': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-ubuntu-x64-cuda13.3.tar.gz',
          '3fcb8e25c95af27c888434c3e76f2a8d637efac2e0c898a87c7808fba59eb016',
        ),
        ReleaseArchive(
          'audio-$audioCppTag-cudart-ubuntu-x64-cuda13.3.tar.gz',
          'fb4f995d760e60e159ea479379a1bf46f4844495f95913790d1b5d59427dbe44',
        ),
      ),
    },
  },
  OS.windows: {
    Architecture.x64: {
      'cpu': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-windows-x64-cpu.zip',
          'c7092b7cc4a82cf4625cadfdb31eff9d16d1d456bf6cc0b61588cfc14d505a6b',
        ),
      ),
      'cpu-portable': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-windows-x64-cpu-portable.zip',
          'dcf2fe0090b9eae862bfe1fba5233b6c0049cbfc0ff26f296c4991d0faed2bf9',
        ),
      ),
      'vulkan': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-windows-x64-vulkan.zip',
          '350e2f372a3911d7b21a617dd375b3479ecf13417e824d0004eb00565dd8e95c',
        ),
      ),
      'vulkan-portable': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-windows-x64-vulkan-portable.zip',
          'b4e5a66e0bda38daabfd00c0b0273a23f9789766a777b5247203f1d1ba2c1572',
        ),
      ),
      'cuda12.4': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-windows-x64-cuda12.4.zip',
          'cedfdd9e28a6720a16514118d6674a562a830066b483f89d60051e6cf1eb5bd2',
        ),
        ReleaseArchive(
          'audio-$audioCppTag-cudart-windows-x64-cuda12.4.zip',
          '866a2bc12c4d887eb3b1b62f82f7a8fdd93391cb77ea02b63b0f360cfb3bb4d8',
        ),
      ),
      'cuda13.3': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-windows-x64-cuda13.3.zip',
          '84c4c0d8c044b08a3d8bee2c35fe275e6ec95a3e9cc1a3cd81e0c77c43b39b80',
        ),
        ReleaseArchive(
          'audio-$audioCppTag-cudart-windows-x64-cuda13.3.zip',
          '839eb20f684a8aab64895b1e466b32ce9b29dfc19dc1ce15b2ef35218512ac0a',
        ),
      ),
    },
  },
  OS.macOS: {
    Architecture.arm64: {
      'metal': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-macos-arm64-metal.tar.gz',
          '871d5e981be33abfc45aebd3cfe4858997ee298fd022a606fdb250ae1854495d',
        ),
      ),
    },
    Architecture.x64: {
      // Built with Metal disabled upstream (CI runners have no GPU), so it is
      // the CPU library in practice.
      'cpu': const PrebuiltLibrary(
        ReleaseArchive(
          'audio-$audioCppTag-lib-macos-x64-metal.tar.gz',
          '7328284cd69b4e1953eca811b906850320e6001beb4eea28e69b54cfd5c07106',
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
