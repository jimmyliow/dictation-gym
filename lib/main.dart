import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_kit_stub.dart' if (dart.library.io) 'media_kit_impl.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:dictation_gym/common.dart';
import 'package:rxdart/rxdart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.jimmyliow.dictation_gym.channel.audio',
    androidNotificationChannelName: 'Dictation Gym',
    androidNotificationOngoing: true,
  );
  initMediaKit(); // Initialise just_audio_media_kit for Linux/Windows.
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late AudioPlayer _player;
  String _playMode = 'Empty';
  final FocusNode _buttonFocusNode = FocusNode(debugLabel: 'Menu Button');
  Duration clipStartDuration = Duration.zero;
  Duration clipEndDuration = Duration.zero;
  List<Lyric> lyrics = [];
  List<AudioFile> audioFiles = [];
  late final List<AudioSource> _playlist = [];
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    ambiguate(WidgetsBinding.instance)!.addObserver(this);
    _player = AudioPlayer(maxSkipsOnError: 3);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.black),
    );
    _init();
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    // Listen to errors during playback.
    _player.errorStream.listen((e) {
      print('A stream error occurred: $e');
    });

    try {
      _player.setLoopMode(LoopMode.off);
      await _player.setAudioSources(_playlist);
    } on PlayerException catch (e) {
      // Catch load errors: 404, invalid url...
      print("Error loading playlist: $e");
    }
    // Show a snackbar whenever reaching the end of an item in the playlist.
    _player.positionDiscontinuityStream.listen((discontinuity) {
      if (discontinuity.reason == PositionDiscontinuityReason.autoAdvance) {
        _showItemFinished(discontinuity.previousEvent.currentIndex);
      }
    });
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _showItemFinished(_player.currentIndex);
      }
    });
    loadAudioFiles();
  }

  Future<void> loadAudioFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('audio_files') ?? [];
    List<AudioFile> selectedFiles = jsonList
        .map((jsonStr) => AudioFile.fromJson(jsonDecode(jsonStr)))
        .toList();

    setState(() {
      audioFiles = selectedFiles;
    });
  }

  void _showItemFinished(int? index) async {
    final sequence = _player.sequence;

    if (index == null) return;

    if (index >= sequence.length) return;

    if (_playMode == 'fines') {
      // aₙ = 9n + 2
      // x >= 2 && (x - 2) % 9 === 0;
      if (index >= 0 && (index) % 3 == 0) {
        await Future.delayed(Duration.zero);
        await _player.setSpeed(0.8);
      } else if (index >= 1 && (index - 1) % 3 == 0) {
        await Future.delayed(Duration.zero);
        await _player.setSpeed(1.0);
      }
    }
  }

  @override
  void dispose() {
    _buttonFocusNode.dispose();
    ambiguate(WidgetsBinding.instance)!.removeObserver(this);
    _player.dispose();
    super.dispose();
  }

  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
        _player.positionStream,
        _player.bufferedPositionStream,
        _player.durationStream,
        (position, bufferedPosition, duration) =>
            PositionData(position, bufferedPosition, duration ?? Duration.zero),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Dictation Gym'),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.dehaze),
              tooltip: 'Setup',
              onPressed: () {},
            ),
            //
            MenuAnchor(
              childFocusNode: _buttonFocusNode,
              menuChildren: <Widget>[
                MenuItemButton(onPressed: () {
                  _pickDirectoryAndReadFiles();
                }, child: const Text('Pick dir')),
                MenuItemButton(
                  onPressed: () {
                    mockfromLrc();
                  },
                  child: const Text('Mock playlist'),
                ),
              ],
              builder: (_, MenuController controller, Widget? child) {
                return IconButton(
                  focusNode: _buttonFocusNode,
                  onPressed: () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
                  icon: const Icon(Icons.more_vert),
                );
              },
            ),
            //
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "Audio files",
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.playlist_play),
                    tooltip: 'Play All',
                    onPressed: () {
                      playAllAudios();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.playlist_remove),
                    tooltip: 'Clear All',
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Add files',
                    onPressed: () {
                      pickAudioFiles();
                    },
                  ),
                ],
              ),
              Expanded(
                child: audioFiles.isEmpty
                    ? Text(
                        'Less is more',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 16, bottom: 80),
                        itemCount: audioFiles.length,
                        itemBuilder: (context, index) {
                          final currentFile = audioFiles[index];
                          return ListTile(
                            leading: Text('${index + 1}'),
                            title: Text(
                              currentFile.name,
                              style: const TextStyle(fontSize: 16),
                            ),
                            subtitle: Text(currentFile.path),
                            trailing: IconButton(
                              icon: const Icon(Icons.playlist_add),
                              tooltip: 'Add to playlist',
                              onPressed: () {
                                _scaffoldMessengerKey.currentState
                                    ?.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          "Play file : ${currentFile.name}",
                                        ),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                              },
                            ),
                            onTap: () {
                              _scaffoldMessengerKey.currentState?.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    "Tap file : ${currentFile.name}",
                                  ),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                              playAudio(currentFile);
                            },
                          );
                        },
                      ),
              ),
              StreamBuilder<SequenceState?>(
                stream: _player.sequenceStateStream,
                builder: (context, snapshot) {
                  final state = snapshot.data;
                  if (state?.sequence.isEmpty ?? true) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [Text('Empty')],
                    );
                  }
                  final metadata = state!.currentSource!.tag as MediaItem;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [Text(metadata.title)],
                  );
                },
              ),
              ControlButtons(_player),
              StreamBuilder<PositionData>(
                stream: _positionDataStream,
                builder: (context, snapshot) {
                  final positionData = snapshot.data;
                  return SeekBar(
                    duration: positionData?.duration ?? Duration.zero,
                    position: positionData?.position ?? Duration.zero,
                    bufferedPosition:
                        positionData?.bufferedPosition ?? Duration.zero,
                    onChangeEnd: (newPosition) {
                      _player.seek(newPosition);
                    },
                  );
                },
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_formatDuration(clipStartDuration)),
                  Text(" |------| "),
                  Text(_formatDuration(clipEndDuration)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_left),
                    onPressed: () {
                      Duration newPosition =
                          clipStartDuration - Duration(microseconds: 800);
                      setState(() {
                        clipStartDuration = newPosition;
                      });
                      // _player.seek(newPosition);
                    },
                  ),
                  TextButton(
                    child: const Text('A'),
                    onPressed: () {
                      setState(() {
                        clipStartDuration = _player.position;
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_right),
                    onPressed: () {
                      Duration newPosition =
                          clipStartDuration + Duration(microseconds: 800);
                      setState(() {
                        clipStartDuration = newPosition;
                      });
                      // _player.seek(newPosition);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.start),
                    onPressed: () {
                      final currentIndex = _player.currentIndex;

                      if (currentIndex != null) {
                        final currentSource =
                            _player.audioSources[currentIndex]
                                as UriAudioSource;

                        List<AudioSource> a = [
                          ClippingAudioSource(
                            start: clipStartDuration,
                            end: clipEndDuration,
                            child: currentSource,
                            tag: currentSource.tag,
                          ),
                        ];
                        _player.setAudioSources(a);
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_left),
                    onPressed: () {
                      Duration newPosition =
                          clipEndDuration - Duration(microseconds: 800);
                      setState(() {
                        clipEndDuration = newPosition;
                      });
                      // _player.seek(newPosition);
                    },
                  ),
                  TextButton(
                    child: const Text('B'),
                    onPressed: () {
                      setState(() {
                        clipEndDuration = _player.position;
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_right),
                    onPressed: () {
                      Duration newPosition =
                          clipEndDuration + Duration(microseconds: 800);
                      setState(() {
                        clipEndDuration = newPosition;
                      });
                      // _player.seek(newPosition);
                    },
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.snooze),
                    onPressed: () {
                      delayedStop();
                    },
                  ),
                  IconButton(icon: const Icon(Icons.hearing), onPressed: () {
                    // _pickDirectoryAndReadFiles();
                  }),
                  IconButton(
                    icon: const Icon(Icons.fitness_center),
                    onPressed: () {
                      //
                      fitnessMode();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.autofps_select),
                    onPressed: () {
                      pickLrc();
                    },
                  ),
                  LyricsButton(lyrics),
                  PlaylistButton(_player),
                  SpeedMenu(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Lyric> _parseLrcContent(String content) {
    List<Lyric> result = [];
    final lines = content.split('\n');
    // 增强正则：匹配双时间标签（开始+结束）和歌词文本
    final timeRegExp = RegExp(
      r'\[(\d{0,2}):(\d{2}):(\d{2})\.(\d{1,3})\]\s*\[(\d{0,2}):(\d{2}):(\d{2})\.(\d{1,3})\](.*)',
    );

    for (String line in lines) {
      final match = timeRegExp.firstMatch(line);
      if (match == null) continue;

      // 解析开始时间
      final startHours = int.parse(match.group(1) ?? "0");
      final startMins = int.parse(match.group(2)!);
      final startSecs = int.parse(match.group(3)!);
      final startMs = int.parse(match.group(4)!);
      final startTime = Duration(
        hours: startHours,
        minutes: startMins,
        seconds: startSecs,
        milliseconds: startMs,
      );

      // 解析结束时间
      final endHours = int.parse(match.group(5) ?? "0");
      final endMins = int.parse(match.group(6)!);
      final endSecs = int.parse(match.group(7)!);
      final endMs = int.parse(match.group(8)!);
      final endTime = Duration(
        hours: endHours,
        minutes: endMins,
        seconds: endSecs,
        milliseconds: endMs,
      );

      // 提取歌词文本
      final text = match.group(9)?.trim() ?? "";
      if (text.isEmpty) continue;

      result.add(Lyric(startTime, endTime, text));
    }

    // 按开始时间排序
    result.sort((a, b) => a.startTime.compareTo(b.startTime));
    return result;
  }

  String _formatDuration(Duration d) {
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}.${(d.inMilliseconds % 1000).toString().padLeft(3, '0')}';
  }

  mockfromLrc() {
    final UriAudioSource gettingAVisa = AudioSource.uri(
      Uri.parse(
        "https://dailydictation.com/upload/english-conversations/21-getting-a-visa-2022-03-07-21-11-20/0-21-getting-a-visa.mp3",
      ),
    );
    List<AudioSource> lrcList = [
      ...List.generate(9, (index) {
        return ClippingAudioSource(
          // 00:00:01.710 - 00:00:03.680
          start: const Duration(seconds: 1, milliseconds: 710),
          end: const Duration(seconds: 3, milliseconds: 680),
          child: gettingAVisa,
          tag: MediaItem(
            id: '1($index)',
            title: "Does it take long to get a visa?($index)",
          ),
        );
      }),
      ...List.generate(9, (index) {
        return ClippingAudioSource(
          // [00:00:03.710][00:00:04.960]
          start: const Duration(seconds: 3, milliseconds: 710),
          end: const Duration(seconds: 4, milliseconds: 960),
          child: gettingAVisa,
          tag: MediaItem(
            id: '2($index)',
            title: "It depends on the season.($index)",
          ),
        );
      }),
      ...List.generate(9, (index) {
        return ClippingAudioSource(
          // 00:00:04.960][00:00:06.960
          start: const Duration(seconds: 4, milliseconds: 960),
          end: const Duration(seconds: 6, milliseconds: 960),
          child: gettingAVisa,
          tag: MediaItem(
            id: '3($index)',
            title: "Anywhere from one month to two months.($index)",
          ),
        );
      }),
    ];

    _player.setAudioSources(lrcList);
  }

  Future<void> fitnessMode() async {
    _player.stop();
    List<AudioSource> newSources = [];

    for (AudioFile file in audioFiles) {
      String fileName = file.name;
      List<AudioSource> repeatSource = List.generate(3, (index) {
        return AudioSource.uri(
          Uri.file(file.path),
          tag: MediaItem(id: fileName, title: fileName),
        );
      });

      newSources.addAll(repeatSource);
    }
    _playMode = 'fines';
    _player.setLoopMode(LoopMode.all);
    _player.setAudioSources(newSources);
    _player.play();
  }

  Future<void> delayedStop() async {
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('Stop playing after 30min.'),
        duration: const Duration(seconds: 1),
      ),
    );

    Future.delayed(Duration(minutes: 30), () async {
      if (_player.playing) {
        await _player.stop();
      }
    });
  }

  Future<bool> _requestMediaPermission() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) { // Android 13+
        final visualStatus = await Permission.videos.request(); // 实际使用 Permission.mediaLibrary
        final audioRequest = await Permission.audio.request();
        return audioRequest.isGranted || visualStatus.isGranted;
      } else { // Android <13
        return await Permission.storage.request().isGranted;
      }
    }
    return true; // iOS 或其他平台无需此权限
  }

  Future<void> _pickDirectoryAndReadFiles() async {
    _requestMediaPermission();
    try {
      // 1. 选择目录（仅桌面/移动端支持）
      String? selectedDir = await FilePicker.platform.getDirectoryPath();
      if (selectedDir == null) return;

      // 2. 读取目录下所有文件
      final dir = Directory(selectedDir);
      List<File> files = [];

      List<AudioFile> selectedFiles = [];
      await for (var entity in dir.list(recursive: false)) {
        if (entity is File) {
          String filePath = entity.path;
          String fileName = path.basename(filePath); // 文件名（推荐）
          String dirName = path.dirname(filePath);    // 所在目录路径
          selectedFiles.add(
              AudioFile(path: filePath, name: fileName));
        }
      }
      setState(() {
        audioFiles = selectedFiles;
      });
    } catch (e) {
      print("Error: $e");
    }
  }

  Future<String?> pickLrc() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.storage.request();
      if (!status.isGranted) return null;
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );

    if (result == null || result.files.isEmpty) return null;

    final lrcFile = File(result.files.single.path!);
    final lrcContent = await lrcFile.readAsString();

    final parsedLyrics = _parseLrcContent(lrcContent);

    setState(() {
      lyrics = parsedLyrics;
    });

    if (_player.audioSource == null) return null;

    final currentSource = _player.audioSource as UriAudioSource;

    List<AudioSource> newSources = [];
    for (Lyric lrc in parsedLyrics) {
      AudioSource lrcSource = ClippingAudioSource(
        start: lrc.startTime,
        end: lrc.endTime,
        child: currentSource,
        tag: MediaItem(id: lrc.text, title: lrc.text),
      );

      newSources.add(lrcSource);
    }
    _player.setAudioSources(newSources);

    return null;
  }

  Future<void> pickAudioFiles() async {
    bool mediaPermission = await _requestMediaPermission();

    if (!mediaPermission) return;

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.audio,
    );
    if (result == null || result.files.isEmpty) return;

    List<AudioFile> selectedFiles = [];

    List<AudioSource> newSources = [];
    for (PlatformFile file in result.files) {
      if (file.path == null) continue;

      String fileName = file.name;
      selectedFiles.add(AudioFile(path: file.path ?? 'Empty', name: file.name));

      AudioSource source = AudioSource.uri(
        Uri.file(file.path!),
        tag: MediaItem(id: fileName, title: fileName),
      );

      newSources.add(source);
    }

    setState(() {
      audioFiles = selectedFiles;
    });
    _player.setAudioSources(newSources);

    final prefs = await SharedPreferences.getInstance();
    final jsonList = selectedFiles
        .map((file) => jsonEncode(file.toJson()))
        .toList();
    await prefs.setStringList('audio_files', jsonList);
  }

  playAllAudios() async {
    List<AudioSource> newSources = [];

    for (AudioFile file in audioFiles) {
      String fileName = file.name;
      AudioSource source = AudioSource.uri(
        Uri.file(file.path),
        tag: MediaItem(id: fileName, title: fileName),
      );

      newSources.add(source);
    }

    _playMode = 'Empty';
    _player.setAudioSources(newSources);
    _player.play();
  }

  playAudio(AudioFile audio) async {
    List<AudioSource> playlist = [
      AudioSource.uri(
        Uri.file(audio.path),
        tag: MediaItem(id: audio.name, title: audio.name),
      ),
    ];

    _player.setAudioSources(playlist);
    _player.play();
  }
}
//
class LyricsButton extends StatelessWidget {
  final List _lyrics;
  const LyricsButton(this._lyrics, {super.key});

  String _formatDuration(Duration d) {
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}.${(d.inMilliseconds % 1000).toString().padLeft(3, '0')}';
  }

  String _formatTimeRange(Duration start, Duration end) {
    return '${_formatDuration(start)} - ${_formatDuration(end)}';
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.lyrics),
      onPressed: () {
        showModalBottomSheet<void>(
          context: context,
          builder: (BuildContext context) {
            return SizedBox(
              height: 600,
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 16, bottom: 80),
                itemCount: _lyrics.length,
                itemBuilder: (context, index) {
                  final lyric = _lyrics[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                        ),
                      ),
                      title: Text(
                        lyric.text,
                        style: const TextStyle(fontSize: 16),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _formatTimeRange(lyric.startTime, lyric.endTime),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${lyric.endTime.inMilliseconds - lyric.startTime.inMilliseconds}ms',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

//
class PlaylistButton extends StatelessWidget {
  final AudioPlayer _player;
  const PlaylistButton(this._player, {super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.queue_music),
      onPressed: () {
        showModalBottomSheet<void>(
          context: context,
          builder: (BuildContext context) {
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Playlist",
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    StreamBuilder<LoopMode>(
                      stream: _player.loopModeStream,
                      builder: (context, snapshot) {
                        final loopMode = snapshot.data ?? LoopMode.off;
                        const icons = [
                          Icon(Icons.repeat, color: Colors.grey),
                          Icon(Icons.repeat, color: Colors.orange),
                          Icon(Icons.repeat_one, color: Colors.orange),
                        ];
                        const cycleModes = [
                          LoopMode.off,
                          LoopMode.all,
                          LoopMode.one,
                        ];
                        final index = cycleModes.indexOf(loopMode);
                        return IconButton(
                          icon: icons[index],
                          onPressed: () {
                            _player.setLoopMode(
                              cycleModes[(cycleModes.indexOf(loopMode) + 1) %
                                  cycleModes.length],
                            );
                          },
                        );
                      },
                    ),
                    StreamBuilder<bool>(
                      stream: _player.shuffleModeEnabledStream,
                      builder: (context, snapshot) {
                        final shuffleModeEnabled = snapshot.data ?? false;
                        return IconButton(
                          icon: shuffleModeEnabled
                              ? const Icon(Icons.shuffle, color: Colors.orange)
                              : const Icon(Icons.shuffle, color: Colors.grey),
                          onPressed: () async {
                            final enable = !shuffleModeEnabled;
                            if (enable) {
                              await _player.shuffle();
                            }
                            await _player.setShuffleModeEnabled(enable);
                          },
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.playlist_remove),
                      tooltip: 'Clear All',
                      onPressed: () {
                        _player.stop();
                        _player.clearAudioSources();
                      },
                    ),
                  ],
                ),
                SizedBox(
                  // playlist
                  height: 400,
                  child: StreamBuilder<SequenceState?>(
                    stream: _player.sequenceStateStream,
                    builder: (context, snapshot) {
                      final state = snapshot.data;
                      final sequence = state?.sequence ?? [];
                      return ReorderableListView(
                        onReorder: (int oldIndex, int newIndex) {
                          if (oldIndex < newIndex) newIndex--;
                          _player.moveAudioSource(oldIndex, newIndex);
                        },
                        children: [
                          for (var i = 0; i < sequence.length; i++)
                            Dismissible(
                              key: ValueKey(sequence[i]),
                              background: Container(
                                color: Colors.redAccent,
                                alignment: Alignment.centerRight,
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 8.0),
                                  child: Icon(
                                    Icons.delete,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              onDismissed: (dismissDirection) =>
                                  _player.removeAudioSourceAt(i),
                              child: Material(
                                color: i == state!.currentIndex
                                    ? Colors.grey.shade300
                                    : null,
                                child: ListTile(
                                  title: Text(sequence[i].tag.title as String),
                                  onTap: () => _player
                                      .seek(Duration.zero, index: i)
                                      .catchError((e, st) {}),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                //
              ],
            );
          },
        );
      },
    );
  }
}

//
class SpeedMenu extends StatefulWidget {
  const SpeedMenu({super.key});

  @override
  State<SpeedMenu> createState() => SpeedMenuMenuState();
}

class SpeedMenuMenuState extends State<SpeedMenu> {
  final FocusNode _buttonFocusNode = FocusNode(debugLabel: 'Menu Button');

  @override
  void dispose() {
    _buttonFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      childFocusNode: _buttonFocusNode,
      menuChildren: <Widget>[
        MenuItemButton(
          onPressed: () {
            // player
          },
          child: const Text('0.2x'),
        ),
        MenuItemButton(onPressed: () {}, child: const Text('0.4x')),
        MenuItemButton(onPressed: () {}, child: const Text('0.6x')),
        MenuItemButton(onPressed: () {}, child: const Text('0.8x')),
        MenuItemButton(onPressed: () {}, child: const Text('1.0x')),
        MenuItemButton(onPressed: () {}, child: const Text('1.2x')),
        MenuItemButton(onPressed: () {}, child: const Text('1.5x')),
        MenuItemButton(onPressed: () {}, child: const Text('2.0x')),
      ],
      builder: (_, MenuController controller, Widget? child) {
        return IconButton(
          focusNode: _buttonFocusNode,
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          icon: const Icon(Icons.speed),
        );
      },
    );
  }
}
//

//
class ControlButtons extends StatelessWidget {
  final AudioPlayer player;

  const ControlButtons(this.player, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreamBuilder<SequenceState?>(
          stream: player.sequenceStateStream,
          builder: (context, snapshot) => IconButton(
            icon: const Icon(Icons.skip_previous),
            onPressed: player.hasPrevious ? player.seekToPrevious : null,
          ),
        ),
        StreamBuilder<(bool, ProcessingState, int)>(
          stream: Rx.combineLatest2(
            player.playerEventStream,
            player.sequenceStream,
            (event, sequence) => (
              event.playing,
              event.playbackEvent.processingState,
              sequence.length,
            ),
          ),
          builder: (context, snapshot) {
            final (playing, processingState, sequenceLength) =
                snapshot.data ?? (false, null, 0);
            if (processingState == ProcessingState.loading ||
                processingState == ProcessingState.buffering) {
              return Container(
                margin: const EdgeInsets.all(8.0),
                width: 64.0,
                height: 64.0,
                child: const CircularProgressIndicator(),
              );
            } else if (!playing) {
              return IconButton(
                icon: const Icon(Icons.play_arrow),
                iconSize: 64.0,
                onPressed: sequenceLength > 0 ? player.play : null,
              );
            } else if (processingState != ProcessingState.completed) {
              return IconButton(
                icon: const Icon(Icons.pause),
                iconSize: 64.0,
                onPressed: player.pause,
              );
            } else {
              return IconButton(
                icon: const Icon(Icons.replay),
                iconSize: 64.0,
                onPressed: sequenceLength > 0
                    ? () => player.seek(
                        Duration.zero,
                        index: player.effectiveIndices.first,
                      )
                    : null,
              );
            }
          },
        ),
        StreamBuilder<SequenceState?>(
          stream: player.sequenceStateStream,
          builder: (context, snapshot) => IconButton(
            icon: const Icon(Icons.skip_next),
            onPressed: player.hasNext ? player.seekToNext : null,
          ),
        ),
        StreamBuilder<double>(
          stream: player.speedStream,
          builder: (context, snapshot) => IconButton(
            icon: Text(
              "${snapshot.data?.toStringAsFixed(1)}x",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              showSliderDialog(
                context: context,
                title: "Adjust speed",
                divisions: 20,
                min: 0.2,
                max: 2.0,
                value: player.speed,
                stream: player.speedStream,
                onChanged: player.setSpeed,
              );
            },
          ),
        ),
      ],
    );
  }
}

class Lyric {
  final Duration startTime;
  final Duration endTime;
  final String text;

  Lyric(this.startTime, this.endTime, this.text);
}

class AudioFile {
  final String path;
  final String name;

  AudioFile({required this.path, required this.name});

  // 序列化为JSON
  Map<String, dynamic> toJson() => {'path': path, 'name': name};

  // 从JSON反序列化
  factory AudioFile.fromJson(Map<String, dynamic> json) =>
      AudioFile(path: json['path'], name: json['name']);
}
