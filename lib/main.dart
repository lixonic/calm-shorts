import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'src/reels_screen.dart';
import 'src/calm_prompts.dart';
import 'src/video_library.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xff101410),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const CalmReelsApp());
}

class CalmReelsApp extends StatelessWidget {
  const CalmReelsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calm Reels',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
        },
      ),
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xffccdec2),
          brightness: Brightness.dark,
          surface: const Color(0xff101410),
        ),
        scaffoldBackgroundColor: const Color(0xff101410),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const _LibraryLoader(),
    );
  }
}

class _LibraryLoader extends StatefulWidget {
  const _LibraryLoader();

  @override
  State<_LibraryLoader> createState() => _LibraryLoaderState();
}

class _LibraryLoaderState extends State<_LibraryLoader> {
  Future<({List<VideoClip> clips, PromptLibrary prompts})>
  _loadLibrary() async {
    final clips = await loadVideoLibrary();
    final prompts = await loadPromptLibrary();
    return (clips: clips, prompts: prompts);
  }

  late var _library = _loadLibrary();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({List<VideoClip> clips, PromptLibrary prompts})>(
      future: _library,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.clips.isNotEmpty) {
          return ReelsScreen(
            clips: snapshot.data!.clips,
            prompts: snapshot.data!.prompts,
          );
        }
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.spa_rounded, size: 38),
                  const SizedBox(height: 16),
                  Text(
                    snapshot.connectionState == ConnectionState.waiting
                        ? 'A little room to wander'
                        : snapshot.hasData
                        ? 'No portrait videos added yet'
                        : 'Your videos could not open',
                    style: const TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    FilledButton(
                      onPressed: () => setState(() {
                        _library = _loadLibrary();
                      }),
                      child: const Text('Try again'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
