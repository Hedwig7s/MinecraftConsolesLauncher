import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:minecraft_consoles_updater/backend.dart';

class AppColors {
  static const green = Color(0xFF4CAF50);
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1A1A1E);
  static const progressBackground = Color(0xFF2C2C2E);
  static const textPrimary = Colors.white;
}

ThemeData lceTheme = ThemeData(
  brightness: Brightness.dark,
  primaryColor: AppColors.green,
  scaffoldBackgroundColor: AppColors.background,
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.green,
      foregroundColor: AppColors.textPrimary,
      textStyle: const TextStyle(fontSize: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
);

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: lceTheme,
      home: const LauncherScreen(),
    );
  }
}

class LauncherScreen extends StatefulWidget {
  const LauncherScreen({super.key});

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> {
  bool _isInstalling = false;
  final _progressNotifier = ValueNotifier<ProgressUpdate?>(null);

  @override
  void dispose() {
    _progressNotifier.dispose();
    super.dispose();
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _startInstallation() async {
    setState(() => _isInstalling = true);

    final receivePort = ReceivePort();

    try {
      await Isolate.spawn(downloadUpdate, receivePort.sendPort);
    } catch (e, st) {
      setState(() => _isInstalling = false);
      _showError(e.toString());
      return;
    }

    receivePort.listen((message) async {
      if (message is ProgressUpdate) {
        _progressNotifier.value = message;

        if (message.state == InstallState.completed) {
          await Future.delayed(const Duration(seconds: 1));
          setState(() => _isInstalling = false);
          try {
            await startGame();
          } catch (e) {
            _showError(e.toString());
          }
        }
      } else if (message is Exception) {
        setState(() => _isInstalling = false);
        _showError(message.toString());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _Header(),
          Expanded(
            child: Ink.image(
              image: const AssetImage("assets/background.jpg"),
              fit: BoxFit.cover,
            ),
          ),
          _Footer(
            isInstalling: _isInstalling,
            onPlay: _startInstallation,
            progressNotifier: _progressNotifier,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      color: Theme.of(context).primaryColor,
      alignment: Alignment.center,
      child: const Text('LCE Launcher', style: TextStyle(fontSize: 28)),
    );
  }
}

class _Footer extends StatelessWidget {
  final bool isInstalling;
  final VoidCallback onPlay;
  final ValueNotifier<ProgressUpdate?> progressNotifier;
  const _Footer({
    required this.isInstalling,
    required this.onPlay,
    required this.progressNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        children: [
          Center(
            child: SizedBox(
              width: 200,
              height: 56,
              child: FilledButton(
                onPressed: isInstalling ? null : onPlay,
                child: const Text("Play", style: TextStyle(fontSize: 32)),
              ),
            ),
          ),
          InstallProgress(
            progressNotifier: progressNotifier,
            visible: isInstalling,
          ),
        ],
      ),
    );
  }
}

class InstallProgress extends StatefulWidget {
  final ValueNotifier<ProgressUpdate?> progressNotifier;
  final bool visible;
  const InstallProgress({
    super.key,
    required this.progressNotifier,
    required this.visible,
  });

  @override
  State<InstallProgress> createState() => _InstallProgressState();
}

class _InstallProgressState extends State<InstallProgress>
    with TickerProviderStateMixin {
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;
  double _targetProgress = 0.0;

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      duration: const Duration(milliseconds: 80),
      vsync: this,
    );
    _progressAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeOut),
    );

    widget.progressNotifier.addListener(_onProgressChanged);
  }

  void _onProgressChanged() {
    final update = widget.progressNotifier.value;
    if (update == null) return;

    final newTarget = switch (update.state) {
      InstallState.completed => 1.0,
      InstallState.downloading => update.progress / 100.0,
      _ => null,
    };

    if (newTarget == null || newTarget == _targetProgress) return;

    _progressAnimation =
        Tween<double>(begin: _progressAnimation.value, end: newTarget).animate(
          CurvedAnimation(parent: _progressController, curve: Curves.easeOut),
        );

    _targetProgress = newTarget;
    _progressController.forward(from: 0);
  }

  @override
  void dispose() {
    widget.progressNotifier.removeListener(_onProgressChanged);
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,

      child: widget.visible
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 8.0),
              child: SizedBox(
                height: 24,
                child: ValueListenableBuilder<ProgressUpdate?>(
                  valueListenable: widget.progressNotifier,
                  builder: (context, progressUpdate, _) {
                    final update =
                        progressUpdate ??
                        const ProgressUpdate(InstallState.notStarted, 0);
                    final state = update.state;
                    final progress = update.progress;

                    final bool isIndeterminate = switch (state) {
                      InstallState.downloading => false,
                      InstallState.completed => false,
                      _ => true,
                    };

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (isIndeterminate)
                          LinearProgressIndicator(
                            value: null,
                            backgroundColor: AppColors.progressBackground,
                            color: AppColors.green,
                            borderRadius: BorderRadius.circular(4),
                          )
                        else
                          AnimatedBuilder(
                            animation: _progressAnimation,
                            builder: (context, _) => LinearProgressIndicator(
                              value: _progressAnimation.value,
                              backgroundColor: AppColors.progressBackground,
                              color: AppColors.green,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        Center(
                          child: Text(
                            update.message ?? _getDefaultLabel(state, progress),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              shadows: [
                                Shadow(color: Colors.black45, blurRadius: 2),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  String _getDefaultLabel(InstallState state, int progress) {
    return switch (state) {
      InstallState.notStarted => "Waiting...",
      InstallState.downloading => "Downloading... $progress%",
      InstallState.extracting => "Extracting...",
      InstallState.completed => "Ready",
    };
  }
}
