import 'package:flutter/material.dart';

import 'vad_demo.dart';

void main() => runApp(const VadApp());

class VadApp extends StatelessWidget {
  const VadApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'audio.cpp',
    home: Scaffold(
      appBar: AppBar(title: const Text('audio.cpp · Silero VAD')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder(
          future: runVadDemo(),
          builder: (context, snapshot) => switch (snapshot) {
            AsyncSnapshot(:final error?) => Text(
              'Error: $error',
              key: const Key('error'),
            ),
            AsyncSnapshot(:final data?) => Text(
              '$data',
              key: const Key('report'),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    ),
  );
}
