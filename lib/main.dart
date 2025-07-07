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
  Duration clipStartDuration = Duration.zero;
  Duration clipEndDuration = Duration.zero;
  List<Lyric> lyrics = [];
  List<PlatformFile> audioFiles = [];

  final UriAudioSource gettingAVisa = AudioSource.uri(
    Uri.parse(
      "https://dailydictation.com/upload/english-conversations/21-getting-a-visa-2022-03-07-21-11-20/0-21-getting-a-visa.mp3",
    ),
  );
  late final List<AudioSource> _playlist = [
    // AudioSource.uri(Uri.parse("https://dailydictation.com/upload/english-conversations/21-getting-a-visa-2022-03-07-21-11-20/0-21-getting-a-visa.mp3"),
    //   tag: MediaItem(
    //     id: "21-getting-a-visa",
    //     title: "21-getting-a-visa",
    //   ),
    // )
  ];
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
  }

  void _showItemFinished(int? index) async {
    final sequence = _player.sequence;

    if (index == null) return;

    if (index >= sequence.length) return;

    // aₙ = 9n + 2
    // x >= 2 && (x - 2) % 9 === 0;
    // if (index >= 2 && (index - 2) % 9 == 0) {
    //   await Future.delayed(Duration.zero);
    //   await _player.setSpeed(0.6);
    // } else if (index >= 5 && (index - 5) % 9 == 0) {
    //   await Future.delayed(Duration.zero);
    //   await _player.setSpeed(1.0);
    // }

    final source = sequence[index];
    final metadata = source.tag as MediaItem;
    // _scaffoldMessengerKey.currentState?.showSnackBar(
    //   SnackBar(
    //     content: Text('Finished playing ${metadata.title} - $index'),
    //     duration: const Duration(seconds: 1),
    //   ),
    // );
  }

  @override
  void dispose() {
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
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('This is a snackbar')),
                );
              },
            ),
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
                        'Audio files is empty',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 16, bottom: 80),
                        itemCount: audioFiles.length,
                        itemBuilder: (context, index) {
                          final currentFile = audioFiles[index];
                          return ListTile(
                            title: Text(
                              currentFile.name,
                              style: const TextStyle(fontSize: 16),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.playlist_add),
                              tooltip: 'Add to playlist',
                              onPressed: () {
                                _scaffoldMessengerKey.currentState?.showSnackBar(
                                  SnackBar(
                                    content: Text("Play file : ${currentFile.name}"),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                            ),
                            onTap: () {
                              _scaffoldMessengerKey.currentState?.showSnackBar(
                                SnackBar(
                                  content: Text("Tap file : ${currentFile.name}"),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                              playAudio(currentFile);
                            }
                          );
                        },
                      ),
              ),
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
              // SizedBox( // playlist
              //   height: 240.0,
              //   child: StreamBuilder<SequenceState?>(
              //     stream: _player.sequenceStateStream,
              //     builder: (context, snapshot) {
              //       final state = snapshot.data;
              //       final sequence = state?.sequence ?? [];
              //       return ReorderableListView(
              //         onReorder: (int oldIndex, int newIndex) {
              //           if (oldIndex < newIndex) newIndex--;
              //           _player.moveAudioSource(oldIndex, newIndex);
              //         },
              //         children: [
              //           for (var i = 0; i < sequence.length; i++)
              //             Dismissible(
              //               key: ValueKey(sequence[i]),
              //               background: Container(
              //                 color: Colors.redAccent,
              //                 alignment: Alignment.centerRight,
              //                 child: const Padding(
              //                   padding: EdgeInsets.only(right: 8.0),
              //                   child: Icon(Icons.delete, color: Colors.white),
              //                 ),
              //               ),
              //               onDismissed: (dismissDirection) =>
              //                   _player.removeAudioSourceAt(i),
              //               child: Material(
              //                 color: i == state!.currentIndex
              //                     ? Colors.grey.shade300
              //                     : null,
              //                 child: ListTile(
              //                   title: Text(sequence[i].tag.title as String),
              //                   onTap: () => _player
              //                       .seek(Duration.zero, index: i)
              //                       .catchError((e, st) {}),
              //                 ),
              //               ),
              //             ),
              //         ],
              //       );
              //     },
              //   ),
              // ),
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
                    icon: const Icon(Icons.loop),
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
                            tag: MediaItem(
                              id: 'Clipping Audio',
                              title: "Clipping Audio",
                            ),
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
                  IconButton(icon: const Icon(Icons.fitbit), onPressed: () {}),
                  IconButton(
                    icon: const Icon(Icons.fitness_center),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.autofps_select),
                    onPressed: () {
                      pickLrc();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.lyrics),
                    onPressed: () {
                      fromLrc();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.push_pin),
                    onPressed: () {},
                  ),

                  IconButton(
                    icon: const Icon(Icons.queue_music),
                    onPressed: () {
                      showSliderDialog(
                        context: context,
                        title: "Adjust speed",
                        divisions: 20,
                        min: 0.2,
                        max: 2.0,
                        value: _player.speed,
                        stream: _player.speedStream,
                        onChanged: _player.setSpeed,
                      );
                    },
                  ),
                  ShowPlaylistButton(_player),
                ],
              ),

              Expanded(
                child: lyrics.isEmpty
                    ? Text(
                        'Lyrics is empty',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 16, bottom: 80),
                        itemCount: lyrics.length,
                        itemBuilder: (context, index) {
                          final lyric = lyrics[index];
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
                                  _formatTimeRange(
                                    lyric.startTime,
                                    lyric.endTime,
                                  ),
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

  String _formatTimeRange(Duration start, Duration end) {
    return '${_formatDuration(start)} - ${_formatDuration(end)}';
  }

  fromLrc() {
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
    print("lrc: $parsedLyrics");
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

  Future<String?> pickAudioFiles() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.storage.request();
      if (!status.isGranted) return null;
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.audio,
    );
    if (result == null || result.files.isEmpty) return null;

    List<PlatformFile> selectedFiles = [];

    List<AudioSource> newSources = [];
    for (PlatformFile file in result.files) {
      if (file.path == null) continue;

      String fileName = file.name;
      selectedFiles.add(file);

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

    return null;
  }

  playAllAudios() async {

    List<AudioSource> newSources = [];

    for (PlatformFile file in audioFiles) {
      if (file.path == null) continue;

      String fileName = file.name;

      AudioSource source = AudioSource.uri(
        Uri.file(file.path!),
        tag: MediaItem(id: fileName, title: fileName),
      );

      newSources.add(source);
    }

    _player.setAudioSources(newSources);
  }

  playAudio(PlatformFile audio) async {

    List<AudioSource> playlist = [
      AudioSource.uri(Uri.file(audio.path!),
        tag: MediaItem(
          id: audio.name,
          title: audio.name,
        ),
      )
    ];

    _player.setAudioSources(playlist);
  }
}

//
enum SingingCharacter { lafayette, jefferson }

class ShowPlaylistButton extends StatelessWidget {
  final AudioPlayer player;
  const ShowPlaylistButton(this.player, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreamBuilder<double>(
          stream: player.speedStream,
          builder: (context, snapshot) => IconButton(
            icon: Text(
              "${snapshot.data?.toStringAsFixed(1)}x",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text("Adjust Speed", textAlign: TextAlign.center),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      ListTile(
                        title: const Text('0.2'),
                        leading: Radio(
                          value: 0.2,
                          groupValue: [0.2, 0.4],
                          onChanged: (v) {},
                        ),
                      ),
                      ListTile(
                        title: const Text('0.4'),
                        leading: Radio(
                          value: 0.4,
                          groupValue: [0.2, 0.4],
                          onChanged: (v) {},
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

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
