import 'package:audio_cpp_flutter_example/vad_demo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Silero VAD runs on device', (tester) async {
    final report = await tester.runAsync(runVadDemo);
    // ignore: avoid_print
    print(report);
    expect(report, isNotNull);
    expect(report!.family, 'silero_vad');
    expect(report.segments, isNotEmpty);
    for (final segment in report.segments) {
      expect(segment.startSample, lessThan(segment.endSample));
    }
  });
}
