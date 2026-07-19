import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/file_utils.dart';
import '../services/playback_store.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({required this.title, this.filePath, super.key});

  final String title;
  final String? filePath;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? controller;
  Timer? overlayTimer;
  Timer? controlsTimer;
  double speed = 1;
  double speedBeforeHold = 1;
  double volume = 1;
  double brightness = 1;
  double horizontalDrag = 0;
  double verticalStartX = 0;
  bool coverFit = false;
  bool controlsVisible = true;
  bool locked = false;
  String? error;
  String? overlayText;
  Offset? doubleTapPosition;
  String? currentPath;
  final playbackStore = PlaybackStore();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    final filePath = widget.filePath;
    if (filePath != null && filePath.isNotEmpty) {
      _openFile(filePath);
    }
  }

  @override
  void dispose() {
    overlayTimer?.cancel();
    controlsTimer?.cancel();
    _savePlaybackPosition();
    controller?.setPlaybackSpeed(1);
    controller?.removeListener(_onPlayerChanged);
    controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: isLandscape
          ? null
          : AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  onPressed: _toggleFit,
                  icon: Icon(
                    coverFit
                        ? Icons.fit_screen_rounded
                        : Icons.aspect_ratio_rounded,
                  ),
                ),
              ],
            ),
      body: SafeArea(
        top: !isLandscape,
        bottom: !isLandscape,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: locked
              ? null
              : () {
                  setState(() => controlsVisible = !controlsVisible);
                  if (controlsVisible) _scheduleControlsHide();
                },
          onDoubleTapDown: (details) =>
              doubleTapPosition = details.localPosition,
          onDoubleTap: locked ? null : _handleDoubleTap,
          onLongPressStart: locked ? null : _handleLongPressStart,
          onLongPressEnd: locked ? null : (_) => _handleLongPressEnd(),
          onHorizontalDragStart: locked ? null : (_) => horizontalDrag = 0,
          onHorizontalDragUpdate: locked ? null : _handleHorizontalDrag,
          onHorizontalDragEnd: locked ? null : (_) => _commitHorizontalDrag(),
          onVerticalDragStart: locked
              ? null
              : (details) => verticalStartX = details.localPosition.dx,
          onVerticalDragUpdate: locked ? null : _handleVerticalDrag,
          child: Stack(
            children: [
              Positioned.fill(child: Center(child: _videoView())),
              Positioned.fill(
                child: IgnorePointer(child: _brightnessOverlay()),
              ),
              if (overlayText != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      overlayText!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 14,
                top: isLandscape ? 14 : 8,
                child: IconButton.filledTonal(
                  onPressed: () => setState(() => locked = !locked),
                  icon: Icon(
                    locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  ),
                ),
              ),
              if (controlsVisible && !locked)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _controls(isLandscape),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _videoView() {
    final player = controller;
    if (error != null) {
      return _placeholder(error!);
    }
    if (player == null) {
      return _placeholder('没有可播放的本地文件');
    }
    if (!player.value.isInitialized) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    final size = player.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return AspectRatio(
        aspectRatio: player.value.aspectRatio,
        child: VideoPlayer(player),
      );
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: coverFit ? BoxFit.cover : BoxFit.contain,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(player),
        ),
      ),
    );
  }

  Widget _placeholder(String text) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xff111111),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }

  Widget _brightnessOverlay() {
    if (brightness == 1) {
      return const SizedBox.shrink();
    }
    final color = brightness < 1 ? Colors.black : Colors.white;
    final opacity = brightness < 1
        ? (1 - brightness).clamp(0, 0.65).toDouble()
        : ((brightness - 1) * 0.28).clamp(0, 0.22).toDouble();
    return ColoredBox(color: color.withValues(alpha: opacity));
  }

  Widget _controls(bool isLandscape) {
    final player = controller;
    final value = player?.value;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.82)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isLandscape ? 28 : 18,
          46,
          isLandscape ? 28 : 18,
          isLandscape ? 18 : 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: _positionFraction(),
                onChanged: value == null || !value.isInitialized
                    ? null
                    : (position) {
                        final duration = value.duration;
                        player?.seekTo(
                          Duration(
                            milliseconds:
                                (duration.inMilliseconds * position).round(),
                          ),
                        );
                      },
              ),
            ),
            Row(
              children: [
                Text(
                  _formatPosition(value?.position ?? Duration.zero),
                  style: const TextStyle(color: Colors.white70),
                ),
                const Spacer(),
                Text(
                  _formatPosition(value?.duration ?? Duration.zero),
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton.filled(
                  onPressed: _togglePlay,
                  icon: Icon(
                    controller?.value.isPlaying ?? false
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                IconButton(
                  onPressed: () => _seekBy(-10),
                  icon: const Icon(
                    Icons.replay_10_rounded,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  onPressed: () => _seekBy(10),
                  icon: const Icon(
                    Icons.forward_10_rounded,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  onPressed: _toggleFit,
                  icon: Icon(
                    coverFit
                        ? Icons.fit_screen_rounded
                        : Icons.aspect_ratio_rounded,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                DropdownButton<double>(
                  value: speed,
                  dropdownColor: const Color(0xff222222),
                  style: const TextStyle(color: Colors.white),
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 0.75, child: Text('0.75x')),
                    DropdownMenuItem(value: 1, child: Text('1.0x')),
                    DropdownMenuItem(value: 1.25, child: Text('1.25x')),
                    DropdownMenuItem(value: 1.5, child: Text('1.5x')),
                    DropdownMenuItem(value: 2, child: Text('2.0x')),
                  ],
                  onChanged: (selected) {
                    setState(() => speed = selected ?? 1);
                    controller?.setPlaybackSpeed(speed);
                    _scheduleControlsHide();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _positionFraction() {
    final value = controller?.value;
    if (value == null ||
        !value.isInitialized ||
        value.duration.inMilliseconds <= 0) {
      return 0;
    }
    return (value.position.inMilliseconds / value.duration.inMilliseconds)
        .clamp(0, 1)
        .toDouble();
  }

  void _togglePlay() {
    final player = controller;
    if (player == null) return;
    player.value.isPlaying ? player.pause() : player.play();
    setState(() {});
    _scheduleControlsHide();
  }

  void _toggleFit() {
    setState(() => coverFit = !coverFit);
    _showOverlay(coverFit ? '画面填充' : '完整显示');
    _scheduleControlsHide();
  }

  void _handleDoubleTap() {
    final width = context.size?.width ?? 0;
    final dx = doubleTapPosition?.dx ?? width / 2;
    _seekBy(dx < width / 2 ? -10 : 10);
  }

  void _handleHorizontalDrag(DragUpdateDetails details) {
    horizontalDrag += details.delta.dx;
    final seconds = (horizontalDrag / 8).round();
    if (seconds == 0) return;
    _showOverlay(seconds > 0 ? '+${seconds}s' : '${seconds}s');
  }

  void _commitHorizontalDrag() {
    final seconds = (horizontalDrag / 8).round();
    horizontalDrag = 0;
    if (seconds != 0) {
      _seekBy(seconds);
    }
  }

  void _handleVerticalDrag(DragUpdateDetails details) {
    final width = context.size?.width ?? 0;
    final delta = -details.delta.dy / 320;
    if (verticalStartX < width / 2) {
      brightness = (brightness + delta).clamp(0.25, 1.45).toDouble();
      _showOverlay('亮度 ${(brightness * 100).round()}%');
    } else {
      volume = (volume + delta).clamp(0, 1).toDouble();
      controller?.setVolume(volume);
      _showOverlay('音量 ${(volume * 100).round()}%');
    }
    setState(() {});
  }

  void _seekBy(int seconds) {
    final player = controller;
    if (player == null || !player.value.isInitialized) return;
    final duration = player.value.duration;
    final current = player.value.position;
    final targetMs = (current.inMilliseconds + seconds * 1000)
        .clamp(0, duration.inMilliseconds)
        .toInt();
    player.seekTo(Duration(milliseconds: targetMs));
    _showOverlay(seconds > 0 ? '+${seconds}s' : '${seconds}s');
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    final player = controller;
    if (player == null || !player.value.isInitialized) return;
    speedBeforeHold = speed;
    speed = 2;
    player.setPlaybackSpeed(2);
    _showOverlay('2.0x 快进中');
    setState(() {});
  }

  void _handleLongPressEnd() {
    final player = controller;
    speed = speedBeforeHold <= 0 ? 1 : speedBeforeHold;
    player?.setPlaybackSpeed(speed);
    _showOverlay('已恢复 ${speed.toStringAsFixed(2)}x');
    setState(() {});
  }

  void _scheduleControlsHide() {
    controlsTimer?.cancel();
    if (!controlsVisible) return;
    controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !locked) {
        setState(() => controlsVisible = false);
      }
    });
  }

  void _showOverlay(String text) {
    overlayTimer?.cancel();
    setState(() => overlayText = text);
    overlayTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) {
        setState(() => overlayText = null);
      }
    });
  }

  String _formatPosition(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  void _onPlayerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openFile(String path) async {
    try {
      final file = File(path);
      final lower = path.toLowerCase();
      if (!await file.exists()) {
        throw StateError('文件不存在');
      }
      if (await file.length() <= 0) {
        throw StateError('文件大小为 0');
      }
      if (!lower.endsWith('.mp4') &&
          !lower.endsWith('.mov') &&
          !lower.endsWith('.m4v')) {
        throw StateError('不是支持的视频文件后缀');
      }
      if (await FileUtils.looksLikeHtml(file)) {
        throw StateError('文件内容是 HTML，不是视频');
      }
      currentPath = path;
      controller = VideoPlayerController.file(file)
        ..initialize().then((_) {
          if (!mounted) return;
          _afterInitialized(path);
        })
        ..addListener(_onPlayerChanged);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _afterInitialized(String path) async {
    final player = controller;
    if (player == null || !player.value.isInitialized) return;
    player.setVolume(volume);
    final resume = await playbackStore.positionFor(path);
    if (!mounted) return;
    if (resume.inSeconds > 10 &&
        resume < player.value.duration - const Duration(seconds: 10)) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('继续播放？'),
          content: Text('上次播放到 ${_formatPosition(resume)}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('从头播放'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续播放'),
            ),
          ],
        ),
      );
      if (shouldContinue == true) {
        await player.seekTo(resume);
      } else {
        await player.seekTo(Duration.zero);
      }
    }
    if (!mounted) return;
    setState(() {});
    _scheduleControlsHide();
    player.play();
  }

  void _savePlaybackPosition() {
    final path = currentPath;
    final value = controller?.value;
    if (path == null || value == null || !value.isInitialized) return;
    unawaited(
      playbackStore.save(
        path: path,
        position: value.position,
        duration: value.duration,
      ),
    );
  }
}
