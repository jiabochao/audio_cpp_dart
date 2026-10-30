import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings/audiocpp.g.dart';
import 'errors.dart';
import 'native.dart';
import 'reader.dart';
import 'types.dart';

/// Library-wide information.
abstract final class AudioCpp {
  /// The ABI major version these bindings were generated against.
  static const bindingsAbiMajor = AUDIOCPP_ABI_VERSION_MAJOR;

  /// The ABI minor version these bindings were generated against.
  static const bindingsAbiMinor = AUDIOCPP_ABI_VERSION_MINOR;

  /// The loaded library's ABI version, `(major << 16) | (minor << 8) | patch`.
  static int get abiVersion {
    ensureInitialized();
    return audiocpp_abi_version();
  }

  /// audio.cpp's own version string, e.g. `v0.9.3`.
  static String get buildVersion {
    ensureInitialized();
    return audiocpp_build_version().toDartString();
  }

  /// Throws [StateError] if the loaded library is not ABI-compatible with
  /// these bindings: a different major, or an older minor.
  static void checkAbi() {
    final version = abiVersion;
    final major = version >> 16;
    final minor = (version >> 8) & 0xff;
    if (major != bindingsAbiMajor || minor < bindingsAbiMinor) {
      throw StateError(
        'audiocpp ABI $major.$minor is incompatible with bindings built for '
        '$bindingsAbiMajor.$bindingsAbiMinor.',
      );
    }
  }

  /// The task tokens this build accepts: `vad`, `asr`, `tts`, `diar`, ...
  static List<String> get tasks {
    ensureInitialized();
    return [
      for (var i = 0; i < audiocpp_task_count(); i++)
        audiocpp_task_name(i).toDartString(),
    ];
  }

  /// Maps a model-spec task name (`music`) to its task token (`gen`), or
  /// `null` when this build cannot serve it.
  static String? taskFromSpecName(String specTask) {
    ensureInitialized();
    return using(
      (arena) => audiocpp_task_from_spec_name(
        specTask.toNative(arena),
      ).toDartStringOrNull(),
    );
  }
}

final _registryFinalizer = NativeFinalizer(
  addresses.audiocpp_registry_free.cast(),
);
final _modelFinalizer = NativeFinalizer(addresses.audiocpp_model_free.cast());
final _sessionFinalizer = NativeFinalizer(
  addresses.audiocpp_session_free.cast(),
);
final _requestFinalizer = NativeFinalizer(
  addresses.audiocpp_request_free.cast(),
);

/// Native memory is released by [close], or by a finalizer once the object
/// is unreachable. The C ABI keeps parents alive (a session keeps its model,
/// a model its registry), so handles may be closed in any order.
abstract interface class Closeable implements Finalizable {
  bool get isClosed;
  void close();
}

/// The set of model loaders compiled into the library.
final class Registry implements Closeable {
  Pointer<audiocpp_registry> _ptr;

  Registry._(this._ptr) {
    _registryFinalizer.attach(this, _ptr.cast(), detach: this);
  }

  /// [configPath] selects a loader configuration; `null` for the default set.
  factory Registry({String? configPath}) {
    ensureInitialized();
    return using((arena) {
      final out = arena<Pointer<audiocpp_registry>>();
      check(
        audiocpp_registry_create(configPath.toNativeOrNull(arena), out),
        'audiocpp_registry_create',
      );
      return Registry._(out.value);
    });
  }

  Pointer<audiocpp_registry> get _handle {
    if (_ptr == nullptr) throw StateError('Registry is closed.');
    return _ptr;
  }

  @override
  bool get isClosed => _ptr == nullptr;

  /// Model families this build can load, e.g. `kokoro_tts`, `silero_vad`.
  List<String> get families => using((arena) {
    final handle = _handle;
    final out = arena<Pointer<Char>>();
    return [
      for (var i = 0; i < audiocpp_registry_family_count(handle); i++)
        () {
          check(audiocpp_registry_family(handle, i, out));
          return out.value.toDartString();
        }(),
    ];
  });

  /// Loads the model at [path] (a GGUF file or a model directory).
  ///
  /// [family] skips identification from the path (`--family`). [configId],
  /// [weightId] and [modelSpecOverride] mirror `--config`, `--weight` and
  /// `--model-spec-override`; [options] mirrors `--load-option`.
  ///
  /// Loading reads the weights and blocks; prefer [loadModelAsync] on a UI
  /// isolate.
  Model loadModel(
    String path, {
    String? family,
    String? configId,
    String? weightId,
    String? modelSpecOverride,
    Map<String, String> options = const {},
  }) => Model._(
    Pointer.fromAddress(
      _loadModel(
        _handle.address,
        path,
        family,
        configId,
        weightId,
        modelSpecOverride,
        options,
      ),
    ),
  );

  /// [loadModel] on a background isolate.
  Future<Model> loadModelAsync(
    String path, {
    String? family,
    String? configId,
    String? weightId,
    String? modelSpecOverride,
    Map<String, String> options = const {},
  }) async {
    final registry = _handle.address;
    final model = await Isolate.run(
      () => _loadModel(
        registry,
        path,
        family,
        configId,
        weightId,
        modelSpecOverride,
        options,
      ),
      debugName: 'audiocpp_model_load',
    );
    _keepAlive(this);
    return Model._(Pointer.fromAddress(model));
  }

  @override
  void close() {
    if (_ptr == nullptr) return;
    _registryFinalizer.detach(this);
    audiocpp_registry_free(_ptr);
    _ptr = nullptr;
  }
}

int _loadModel(
  int registry,
  String path,
  String? family,
  String? configId,
  String? weightId,
  String? modelSpecOverride,
  Map<String, String> options,
) {
  ensureInitialized();
  return using((arena) {
    final config = audiocpp_model_config.$allocate(
      arena,
      family_hint: family.toNativeOrNull(arena),
      config_id: configId.toNativeOrNull(arena),
      weight_id: weightId.toNativeOrNull(arena),
      model_spec_override: modelSpecOverride.toNativeOrNull(arena),
    );
    final out = arena<Pointer<audiocpp_model>>();
    final nativeOptions = _createOptions(options);
    try {
      check(
        audiocpp_model_load(
          Pointer.fromAddress(registry),
          path.toNative(arena),
          config,
          nativeOptions,
          out,
        ),
        'audiocpp_model_load',
      );
    } finally {
      audiocpp_options_free(nativeOptions);
    }
    return out.value.address;
  });
}

/// `nullptr` for an empty map; the caller frees the result.
Pointer<audiocpp_options> _createOptions(Map<String, String> options) {
  if (options.isEmpty) return nullptr;
  final handle = audiocpp_options_create();
  if (handle == nullptr) {
    throw const AudioCppException(
      AudioCppStatus.outOfMemory,
      'audiocpp_options_create returned NULL',
    );
  }
  try {
    using((arena) {
      for (final MapEntry(:key, :value) in options.entries) {
        check(
          audiocpp_options_set(
            handle,
            key.toNative(arena),
            value.toNative(arena),
          ),
          'audiocpp_options_set',
        );
      }
    });
  } catch (_) {
    audiocpp_options_free(handle);
    rethrow;
  }
  return handle;
}

/// A loaded model.
final class Model implements Closeable {
  Pointer<audiocpp_model> _ptr;

  Model._(this._ptr) {
    _modelFinalizer.attach(this, _ptr.cast(), detach: this);
  }

  Pointer<audiocpp_model> get _handle {
    if (_ptr == nullptr) throw StateError('Model is closed.');
    return _ptr;
  }

  @override
  bool get isClosed => _ptr == nullptr;

  String get family => audiocpp_model_family(_handle).toDartString();

  String get description => audiocpp_model_description(_handle).toDartString();

  /// Whether the model serves [task] (one of [AudioCpp.tasks]) in [mode].
  /// Unknown tasks also answer `false`.
  bool supports(String task, {SessionMode mode = SessionMode.offline}) => using(
    (arena) =>
        audiocpp_model_supports(
          _handle,
          task.toNative(arena),
          mode.nativeName.toNative(arena),
        ) !=
        0,
  );

  bool get supportsTimestamps =>
      audiocpp_model_supports_timestamps(_handle) != 0;

  bool get supportsSpeakerReference =>
      audiocpp_model_supports_speaker_reference(_handle) != 0;

  bool get supportsStyleCondition =>
      audiocpp_model_supports_style_condition(_handle) != 0;

  List<String> get languages => using((arena) {
    final handle = _handle;
    final out = arena<Pointer<Char>>();
    return [
      for (var i = 0; i < audiocpp_model_language_count(handle); i++)
        () {
          check(audiocpp_model_language(handle, i, out));
          return out.value.toDartString();
        }(),
    ];
  });

  /// The options the family declares for [scope].
  List<ModelOption> options(OptionScope scope) => using((arena) {
    final handle = _handle;
    final nativeScope = audiocpp_option_scope.fromValue(scope.index);
    final name = arena<Pointer<Char>>();
    final valueName = arena<Pointer<Char>>();
    final description = arena<Pointer<Char>>();
    final defaultValue = arena<Pointer<Char>>();
    final minValue = arena<Pointer<Char>>();
    final maxValue = arena<Pointer<Char>>();
    final required = arena<Int>();
    return [
      for (var i = 0; i < audiocpp_model_option_count(handle, nativeScope); i++)
        () {
          check(
            audiocpp_model_option(
              handle,
              nativeScope,
              i,
              name,
              valueName,
              description,
              defaultValue,
              minValue,
              maxValue,
              required,
            ),
            'audiocpp_model_option',
          );
          return ModelOption(
            scope: scope,
            name: name.value.toDartString(),
            valueName: valueName.value.toDartString(),
            description: description.value.toDartString(),
            defaultValue: defaultValue.value.toDartString(),
            minValue: minValue.value.toDartString(),
            maxValue: maxValue.value.toDartString(),
            required: required.value != 0,
          );
        }(),
    ];
  });

  /// Creates a session for [task] (`tts`, `asr`, `vad`, ...).
  ///
  /// [threads] defaults to the number of processors. [options] mirrors
  /// `--session-option`.
  Session createSession(
    String task, {
    SessionMode mode = SessionMode.offline,
    Backend backend = Backend.cpu,
    int device = 0,
    int? threads,
    Map<String, String> options = const {},
  }) => Session._(
    Pointer.fromAddress(
      _createSession(
        _handle.address,
        task,
        mode.nativeName,
        backend.nativeName,
        device,
        threads ?? Platform.numberOfProcessors,
        options,
      ),
    ),
    mode,
  );

  /// [createSession] on a background isolate; creating a GPU session can
  /// take a while.
  Future<Session> createSessionAsync(
    String task, {
    SessionMode mode = SessionMode.offline,
    Backend backend = Backend.cpu,
    int device = 0,
    int? threads,
    Map<String, String> options = const {},
  }) async {
    final model = _handle.address;
    final modeName = mode.nativeName;
    final backendName = backend.nativeName;
    final threadCount = threads ?? Platform.numberOfProcessors;
    final session = await Isolate.run(
      () => _createSession(
        model,
        task,
        modeName,
        backendName,
        device,
        threadCount,
        options,
      ),
      debugName: 'audiocpp_session_create',
    );
    _keepAlive(this);
    return Session._(Pointer.fromAddress(session), mode);
  }

  @override
  void close() {
    if (_ptr == nullptr) return;
    _modelFinalizer.detach(this);
    audiocpp_model_free(_ptr);
    _ptr = nullptr;
  }
}

int _createSession(
  int model,
  String task,
  String mode,
  String backend,
  int device,
  int threads,
  Map<String, String> options,
) {
  ensureInitialized();
  return using((arena) {
    final config = audiocpp_backend_config.$allocate(
      arena,
      backend: backend.toNative(arena),
      device: device,
      threads: threads,
    );
    final out = arena<Pointer<audiocpp_session>>();
    final nativeOptions = _createOptions(options);
    try {
      check(
        audiocpp_session_create(
          Pointer.fromAddress(model),
          task.toNative(arena),
          mode.toNative(arena),
          config,
          nativeOptions,
          out,
        ),
        'audiocpp_session_create',
      );
    } finally {
      audiocpp_options_free(nativeOptions);
    }
    return out.value.address;
  });
}

/// A warm inference session. Not thread-safe: one call at a time, which the
/// async methods enforce by throwing [StateError] on overlap.
final class Session implements Closeable {
  Pointer<audiocpp_session> _ptr;

  /// The mode the session was created in.
  final SessionMode mode;

  bool _busy = false;
  int _streamPosition = 0;

  Session._(this._ptr, this.mode) {
    _sessionFinalizer.attach(this, _ptr.cast(), detach: this);
  }

  Pointer<audiocpp_session> get _handle {
    if (_ptr == nullptr) throw StateError('Session is closed.');
    if (_busy) {
      throw StateError('Session is busy with an asynchronous call.');
    }
    return _ptr;
  }

  @override
  bool get isClosed => _ptr == nullptr;

  String get family => audiocpp_session_family(_handle).toDartString();

  /// Optionally allocates up front for requests shaped like [request]; the
  /// next run still prepares for its own request.
  void prepare(Request request) => check(
    audiocpp_session_prepare(_handle, request._handle),
    'audiocpp_session_prepare',
  );

  /// Runs an offline task. Blocks; prefer [runAsync] on a UI isolate.
  TaskResult run(Request request) =>
      _runSession(_handle.address, request._handle.address);

  /// [run] on a background isolate.
  Future<TaskResult> runAsync(Request request) {
    final session = _handle.address;
    final req = request._handle.address;
    return _guard(
      () => Isolate.run(
        () => _runSession(session, req),
        debugName: 'audiocpp_session_run',
      ),
      keepAlive: request,
    );
  }

  /// How a streaming session wants to be fed.
  StreamPolicy get streamPolicy => using((arena) {
    final input = arena<UnsignedInt>();
    final output = arena<UnsignedInt>();
    final samples = arena<Int64>();
    final seconds = arena<Double>();
    check(
      audiocpp_stream_policy(_handle, input, output, samples, seconds),
      'audiocpp_stream_policy',
    );
    return StreamPolicy(
      input: StreamInputKind.values[input.value],
      output: StreamOutputKind.values[output.value],
      preferredChunkSamples: samples.value,
      preferredChunkSeconds: seconds.value,
    );
  });

  /// Starts (or restarts) a stream; [request] carries per-stream options.
  void startStream([Request? request]) {
    check(
      audiocpp_stream_start(_handle, request?._handle ?? nullptr),
      'audiocpp_stream_start',
    );
    _streamPosition = 0;
  }

  /// Feeds one chunk and returns the event it produced, if any.
  ///
  /// [startSample] defaults to the running position of the stream.
  StreamEvent? push(AudioBuffer chunk, {int? startSample}) {
    final start = startSample ?? _streamPosition;
    final event = _pushChunk(_handle.address, chunk, start);
    _streamPosition = start + chunk.frames;
    return event;
  }

  /// [push] on a background isolate.
  Future<StreamEvent?> pushAsync(AudioBuffer chunk, {int? startSample}) async {
    final session = _handle.address;
    final start = startSample ?? _streamPosition;
    final event = await _guard(
      () => Isolate.run(
        () => _pushChunk(session, chunk, start),
        debugName: 'audiocpp_stream_push',
      ),
    );
    _streamPosition = start + chunk.frames;
    return event;
  }

  /// Next event the family queued by itself, or `null` when none is pending.
  StreamEvent? nextEvent() => using((arena) {
    final out = arena<Pointer<audiocpp_event>>();
    check(
      audiocpp_stream_next_event(_handle, out),
      'audiocpp_stream_next_event',
    );
    return consumeEvent(out.value);
  });

  /// All currently queued events.
  List<StreamEvent> drainEvents() => [
    for (var event = nextEvent(); event != null; event = nextEvent()) event,
  ];

  /// Ends the stream and returns the final result.
  TaskResult finishStream() => _finishStream(_handle.address);

  /// [finishStream] on a background isolate.
  Future<TaskResult> finishStreamAsync() {
    final session = _handle.address;
    return _guard(
      () => Isolate.run(
        () => _finishStream(session),
        debugName: 'audiocpp_stream_finish',
      ),
    );
  }

  /// Drops any stream in flight.
  void resetStream() {
    check(audiocpp_stream_reset(_handle), 'audiocpp_stream_reset');
    _streamPosition = 0;
  }

  Future<T> _guard<T>(Future<T> Function() body, {Object? keepAlive}) async {
    _handle; // Throws when closed or busy.
    _busy = true;
    try {
      return await body();
    } finally {
      _busy = false;
      // Keeps [keepAlive] (a Request) reachable, and so unfinalized, until
      // the background call is done with its native handle.
      _keepAlive(keepAlive);
    }
  }

  @override
  void close() {
    if (_ptr == nullptr) return;
    if (_busy) {
      throw StateError('Cannot close a session during an asynchronous call.');
    }
    _sessionFinalizer.detach(this);
    audiocpp_session_free(_ptr);
    _ptr = nullptr;
  }
}

@pragma('vm:never-inline')
void _keepAlive(Object? object) {}

TaskResult _runSession(int session, int request) {
  ensureInitialized();
  return using((arena) {
    final out = arena<Pointer<audiocpp_result>>();
    check(
      audiocpp_session_run(
        Pointer.fromAddress(session),
        Pointer.fromAddress(request),
        out,
      ),
      'audiocpp_session_run',
    );
    return consumeResult(out.value);
  });
}

StreamEvent? _pushChunk(int session, AudioBuffer chunk, int startSample) {
  ensureInitialized();
  return using((arena) {
    final samples = _copySamples(chunk.samples, arena);
    final out = arena<Pointer<audiocpp_event>>();
    check(
      audiocpp_stream_push(
        Pointer.fromAddress(session),
        samples,
        chunk.frames,
        chunk.sampleRate,
        chunk.channels,
        startSample,
        out,
      ),
      'audiocpp_stream_push',
    );
    return consumeEvent(out.value);
  });
}

TaskResult _finishStream(int session) {
  ensureInitialized();
  return using((arena) {
    final out = arena<Pointer<audiocpp_result>>();
    check(
      audiocpp_stream_finish(Pointer.fromAddress(session), out),
      'audiocpp_stream_finish',
    );
    return consumeResult(out.value);
  });
}

Pointer<Float> _copySamples(Float32List samples, Allocator allocator) {
  if (samples.isEmpty) return nullptr;
  final pointer = allocator<Float>(samples.length);
  pointer.asTypedList(samples.length).setAll(0, samples);
  return pointer;
}

/// The input to a task: text, audio, a voice reference, style controls,
/// artifacts and options. Everything is copied into native memory as it is
/// set, so a request can be reused across runs.
final class Request implements Closeable {
  Pointer<audiocpp_request> _ptr;

  Request._(this._ptr) {
    _requestFinalizer.attach(this, _ptr.cast(), detach: this);
  }

  /// Convenience constructor covering the common fields.
  factory Request({
    String? text,
    String? language,
    AudioBuffer? audio,
    AudioBuffer? voiceAudio,
    String? voiceId,
    Map<String, String> options = const {},
  }) {
    ensureInitialized();
    final handle = audiocpp_request_create();
    if (handle == nullptr) {
      throw const AudioCppException(
        AudioCppStatus.outOfMemory,
        'audiocpp_request_create returned NULL',
      );
    }
    final request = Request._(handle);
    if (text != null) request.setText(text, language: language);
    if (audio != null) request.setAudio(audio);
    if (voiceAudio != null) request.setVoiceAudio(voiceAudio);
    if (voiceId != null) request.voiceId = voiceId;
    options.forEach(request.setOption);
    return request;
  }

  Pointer<audiocpp_request> get _handle {
    if (_ptr == nullptr) throw StateError('Request is closed.');
    return _ptr;
  }

  @override
  bool get isClosed => _ptr == nullptr;

  void _set(String operation, audiocpp_status Function(Arena arena) call) =>
      using((arena) => check(call(arena), operation));

  /// Sets the text. A non-empty [language] is also written to the
  /// `language` option, as `audiocpp_cli --language` does; use
  /// [textLanguage] to set only the transcript language.
  void setText(String text, {String? language}) => _set(
    'audiocpp_request_set_text',
    (a) => audiocpp_request_set_text(
      _handle,
      text.toNative(a),
      language.toNativeOrNull(a),
    ),
  );

  /// The transcript language, without touching the `language` option.
  set textLanguage(String language) => _set(
    'audiocpp_request_set_text_language',
    (a) => audiocpp_request_set_text_language(_handle, language.toNative(a)),
  );

  /// The input audio (ASR, VAD, separation, conversion, ...).
  void setAudio(AudioBuffer audio) => _set(
    'audiocpp_request_set_audio',
    (a) => audiocpp_request_set_audio(
      _handle,
      _copySamples(audio.samples, a),
      audio.frames,
      audio.sampleRate,
      audio.channels,
    ),
  );

  /// Speaker reference for cloning and conversion families.
  void setVoiceAudio(AudioBuffer audio) => _set(
    'audiocpp_request_set_voice_audio',
    (a) => audiocpp_request_set_voice_audio(
      _handle,
      _copySamples(audio.samples, a),
      audio.frames,
      audio.sampleRate,
      audio.channels,
    ),
  );

  /// A cached voice id.
  set voiceId(String id) => _set(
    'audiocpp_request_set_voice_id',
    (a) => audiocpp_request_set_voice_id(_handle, id.toNative(a)),
  );

  set styleLanguage(String language) => _set(
    'audiocpp_request_set_style_language',
    (a) => audiocpp_request_set_style_language(_handle, language.toNative(a)),
  );

  set emotion(String emotion) => _set(
    'audiocpp_request_set_emotion',
    (a) => audiocpp_request_set_emotion(_handle, emotion.toNative(a)),
  );

  set speakingRate(double rate) => _set(
    'audiocpp_request_set_speaking_rate',
    (_) => audiocpp_request_set_speaking_rate(_handle, rate),
  );

  set pitchShift(double shift) => _set(
    'audiocpp_request_set_pitch_shift',
    (_) => audiocpp_request_set_pitch_shift(_handle, shift),
  );

  set energyScale(double scale) => _set(
    'audiocpp_request_set_energy_scale',
    (_) => audiocpp_request_set_energy_scale(_handle, scale),
  );

  void setStyleTag(String key, String value) => _set(
    'audiocpp_request_set_style_tag',
    (a) => audiocpp_request_set_style_tag(
      _handle,
      key.toNative(a),
      value.toNative(a),
    ),
  );

  /// Mirrors `--request-option key=value`.
  void setOption(String key, String value) => _set(
    'audiocpp_request_set_option',
    (a) => audiocpp_request_set_option(
      _handle,
      key.toNative(a),
      value.toNative(a),
    ),
  );

  /// Sets a list-valued option, replacing any earlier list for [key].
  void setOptionList(String key, List<String> values) =>
      _set('audiocpp_request_set_option_array', (a) {
        final array = a<Pointer<Char>>(values.isEmpty ? 1 : values.length);
        for (var i = 0; i < values.length; i++) {
          array[i] = values[i].toNative(a);
        }
        return audiocpp_request_set_option_array(
          _handle,
          key.toNative(a),
          array,
          values.length,
        );
      });

  /// Adds an input artifact (with its [Artifact.meta]); returns its index.
  int addArtifact(Artifact artifact) => using((arena) {
    final handle = _handle;
    final payload = arena<Uint8>(
      artifact.payload.isEmpty ? 1 : artifact.payload.length,
    );
    payload.asTypedList(artifact.payload.length).setAll(0, artifact.payload);
    final index = arena<Size>();
    check(
      audiocpp_request_add_artifact(
        handle,
        audiocpp_artifact_kind.fromValue(artifact.kind.index),
        artifact.id.toNative(arena),
        payload.cast(),
        artifact.payload.length,
        index,
      ),
      'audiocpp_request_add_artifact',
    );
    for (final MapEntry(:key, :value) in artifact.meta.entries) {
      check(
        audiocpp_request_set_artifact_meta(
          handle,
          index.value,
          key.toNative(arena),
          value.toNative(arena),
        ),
        'audiocpp_request_set_artifact_meta',
      );
    }
    return index.value;
  });

  @override
  void close() {
    if (_ptr == nullptr) return;
    _requestFinalizer.detach(this);
    audiocpp_request_free(_ptr);
    _ptr = nullptr;
  }
}
