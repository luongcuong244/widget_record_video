import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';
import 'package:flutter/rendering.dart';
import 'package:widget_record_video/src/recording_controller.dart';

class RecordingWidget extends StatefulWidget {
  const RecordingWidget({
    super.key,
    required this.child,
    required this.controller,
    this.limitTime = 120,
    required this.onComplete,
    required this.recordKey,
    this.onUpdateElapsedTime,
    this.onReachingLimitTime,
  });

  /// This is the widget you want to record the screen
  final Widget child;

  /// [RecordingController] Used to start, pause, or stop screen recording
  final RecordingController controller;

  /// [limitTime] is the video recording time limit, when the limit is reached, the process automatically stops.
  /// Its default value is 120 seconds. If you do not have a limit, please set the value less than or equal to 0
  final int limitTime;

  /// [onComplete] is the next action after creating a video, it returns the video path
  final Function(String) onComplete;

  final GlobalKey recordKey;

  final Function(int)? onUpdateElapsedTime;
  final Function()? onReachingLimitTime;

  @override
  State<RecordingWidget> createState() => _RecordingWidgetState();
}

class _RecordingWidgetState extends State<RecordingWidget> {
  static const int fps = 30;

  @override
  void initState() {
    super.initState();
    widget.controller.start = startRecording;
    widget.controller.stop = stopRecording;
    widget.controller.pauseRecord = pauseRecording;
    widget.controller.continueRecord = continueRecording;
  }

  Directory? tempDir;

  Future<void> getImageSize() async {
    RenderRepaintBoundary boundary =
    widget.recordKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    ui.Image image = await boundary.toImage();
    width = image.width;
    height = image.height;
  }

  bool isRecording = false;
  Timer? timer;
  int width = 0;
  int height = 0;

  bool isPauseRecord = false;

  BuildContext? _context;

  int elapsedTime = 0;

  int recordingStartTime = 0;
  int pauseDuration = 0;

  void startRecording(String outputPath) {
    recordingStartTime = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      isRecording = true;
      elapsedTime = 0;
    });
    startExportVideo(outputPath);
    timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (elapsedTime >= widget.limitTime && widget.limitTime > 0) {
        widget.onReachingLimitTime?.call();
        stopRecording();
      } else if (!isPauseRecord) {
        setState(() {
          elapsedTime++;
        });
        widget.onUpdateElapsedTime?.call(elapsedTime);
      }
    });
  }

  Future stopRecording() async {
    timer?.cancel();
    setState(() {
      isRecording = false;
    });
  }

  void pauseRecording() {
    isPauseRecord = true;
  }

  void continueRecording() {
    recordingStartTime = DateTime.now().millisecondsSinceEpoch;
    isPauseRecord = false;
  }

  Future<void> startExportVideo(String outputPath) async {
    // Directory? appDir = await getApplicationCacheDirectory();

    try {
      await getImageSize();

      await FlutterQuickVideoEncoder.setup(
        width: (width ~/ 2) * 2,
        height: (height ~/ 2) * 2,
        fps: fps,
        videoBitrate: 2500000,
        profileLevel: ProfileLevel.any,
        audioBitrate: 0,
        audioChannels: 0,
        sampleRate: 0,
        filepath: outputPath,
        //filepath: '${appDir.path}/exportVideoOnly.mp4',
      );

      Completer<void> readyForMore = Completer<void>();
      readyForMore.complete();

      bool wasPreviouslyPaused = false;
      while (isRecording) {
        Uint8List? videoFrame;
        Uint8List? audioFrame;
        if (!isPauseRecord) {
          wasPreviouslyPaused = true;
          videoFrame = await captureWidgetAsRGBA();

          await readyForMore.future;
          readyForMore = Completer<void>();

          try {
            _appendFrames(videoFrame, audioFrame)
                .then((value) => readyForMore.complete())
                .catchError((e) => readyForMore.completeError(e));
          } catch (e) {
            debugPrint(e.toString());
          }
        } else {
          if (wasPreviouslyPaused) {
            pauseDuration += DateTime.now().millisecondsSinceEpoch - recordingStartTime;
            wasPreviouslyPaused = false;
          }
          await Future.delayed(const Duration(milliseconds: 20));
        }
      }

      await readyForMore.future;

      await FlutterQuickVideoEncoder.finish();

      debugPrint("Finish recording: ${FlutterQuickVideoEncoder.filepath}");

      int endTime = DateTime.now().millisecondsSinceEpoch;
      int videoTime = ((endTime - recordingStartTime) / 1000).round() - 1;
      debugPrint("video time: $videoTime");

      widget.onComplete(outputPath);

      FlutterQuickVideoEncoder.dispose();
    } catch (e) {
      ('Error: $e');
    }
  }

  Future<Uint8List?> captureWidgetAsRGBA() async {
    try {
      RenderRepaintBoundary boundary =
      widget.recordKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage();
      width = image.width;
      height = image.height;
      ByteData? byteData =
      await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint(
        e.toString(),
      );
      return null;
    }
  }

  Future<void> _appendFrames(
      Uint8List? videoFrame, Uint8List? audioFrame) async {
    if (videoFrame != null) {
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      final presentationTime = pauseDuration + currentTime - recordingStartTime;
      print("presentationTime: $presentationTime");
      await FlutterQuickVideoEncoder.appendVideoFrame(videoFrame, presentationTime);
    } else {
      debugPrint("Error append $videoFrame");
    }
  }

  void showSnackBar(String message) {
    debugPrint(message);
    final snackBar = SnackBar(content: Text(message));
    if (_context != null && _context!.mounted) {
      ScaffoldMessenger.of(_context!).showSnackBar(snackBar);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _context = context;
    return widget.child;
  }
}
