import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

import 'package:audio_cpp_dart/src/hook/build_audiocpp.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final logger = Logger.detached('audio_cpp_dart')
      ..level = Level.ALL
      ..onRecord.listen((record) => print(record.message));
    await buildAudioCpp(input, output, logger: logger);
  });
}
