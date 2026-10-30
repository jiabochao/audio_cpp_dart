import 'bindings/audiocpp.g.dart';

/// Status codes returned by the audio.cpp C ABI.
enum AudioCppStatus {
  ok,
  invalidArgument,
  unsupportedFamily,
  loadFailed,
  runtime,
  outOfMemory,
  outOfRange,
  notAvailable;

  static AudioCppStatus fromNative(audiocpp_status status) =>
      values[status.value];

  audiocpp_status get native => audiocpp_status.fromValue(index);
}

/// A non-OK status from audio.cpp, with the library's error detail.
final class AudioCppException implements Exception {
  final AudioCppStatus status;

  /// `audiocpp_last_error()` for the failing call.
  final String message;

  /// The binding operation that failed, e.g. `audiocpp_model_load`.
  final String? operation;

  const AudioCppException(this.status, this.message, {this.operation});

  @override
  String toString() {
    final where = operation == null ? '' : ' in $operation';
    final detail = message.isEmpty ? '' : ': $message';
    return 'AudioCppException(${status.name})$where$detail';
  }
}
