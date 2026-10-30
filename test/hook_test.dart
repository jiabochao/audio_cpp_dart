import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as hook;

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('audio_cpp_hook'));
  tearDown(() => temp.deleteSync(recursive: true));

  PackageUserDefines defines(Map<String, Object?> values) => PackageUserDefines(
    workspacePubspec: PackageUserDefinesSource(
      defines: values,
      basePath: temp.uri,
    ),
  );

  final layouts = {
    OS.linux: ['libaudiocpp.so.0.1.0', 'libcudart.so.13'],
    OS.windows: ['audiocpp.dll', 'vcomp140.dll', 'ggml-base.dll'],
    OS.macOS: ['libaudiocpp.0.1.0.dylib'],
  };

  for (final MapEntry(key: os, value: files) in layouts.entries) {
    test('bundles a local $os library directory', () async {
      final libs = Directory('${temp.path}/libs')..createSync();
      for (final name in [...files, 'audiocpp.lib', 'README.txt']) {
        File('${libs.path}/$name').writeAsStringSync('not a real library');
      }
      await testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: os,
        targetArchitecture: Architecture.x64,
        userDefines: defines({'source': 'local', 'local_library': 'libs'}),
        check: (input, output) {
          final assets = output.assets.code;
          expect(assets.first.id, 'package:audio_cpp_dart/audiocpp');
          expect(
            assets.first.file!.pathSegments.last,
            os.dylibFileName('audiocpp'),
          );
          expect(
            assets.skip(1).map((a) => a.id),
            unorderedEquals([
              for (final name in files.skip(1))
                'package:audio_cpp_dart/runtime/$name',
            ]),
          );
          for (final asset in assets) {
            expect(asset.linkMode, isA<DynamicLoadingBundled>());
            expect(File.fromUri(asset.file!).existsSync(), isTrue);
          }
        },
      );
    });
  }

  test('can leave the MSVC runtime out', () async {
    final libs = Directory('${temp.path}/libs')..createSync();
    for (final name in ['audiocpp.dll', 'msvcp140.dll', 'vcruntime140.dll']) {
      File('${libs.path}/$name').writeAsStringSync('');
    }
    await testCodeBuildHook(
      mainMethod: hook.main,
      targetOS: OS.windows,
      targetArchitecture: Architecture.x64,
      userDefines: defines({
        'source': 'local',
        'local_library': 'libs',
        'bundle_msvc_runtime': false,
      }),
      check: (input, output) => expect(output.assets.code, hasLength(1)),
    );
  });

  test('bundles nothing for 32-bit Android', () async {
    await testCodeBuildHook(
      mainMethod: hook.main,
      targetOS: OS.android,
      targetArchitecture: Architecture.arm,
      userDefines: defines({}),
      check: (input, output) => expect(output.assets.code, isEmpty),
    );
  });

  test('refuses prebuilt for targets without a release archive', () async {
    await expectLater(
      testCodeBuildHook(
        mainMethod: hook.main,
        targetOS: OS.android,
        targetArchitecture: Architecture.arm64,
        userDefines: defines({'source': 'prebuilt'}),
        check: (_, _) {},
      ),
      throwsA(anything),
    );
  });
}
