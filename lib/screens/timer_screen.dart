import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:audioplayers/audioplayers.dart'; // Added for audio
import 'package:shared_preferences/shared_preferences.dart'; // Added for saving duration
import '../models/meditation_session.dart';
import '../services/database_helper.dart';

// Enum to manage timer states
enum TimerState { initial, running, paused }

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  Timer? _timer;
  TimerState _timerState = TimerState.initial;
  final int _minSessionDuration = 10; // Minimum duration in seconds to save

  // Duration and progress state
  Duration _selectedDuration = const Duration(minutes: 10); // Default duration
  Duration _timeLeft = const Duration(minutes: 10); // Initialize with default
  static const String _prefSelectedDurationKey = 'selectedDurationMinutes';

  // Audio state
  late AudioPlayer _audioPlayer;
  final String _startSoundPath = 'audio/start_sound.mp3'; // Placeholder path
  final String _endSoundPath = 'audio/end_sound.mp3'; // Placeholder path

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    // Optional: Configure audio player if needed (e.g., release mode)
    // _audioPlayer.setReleaseMode(ReleaseMode.stop);
    _loadSelectedDuration(); // Load saved duration on init
    _resetTimerVisuals(); // Initialize timeLeft based on loaded duration
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer.dispose(); // Dispose audio player
    WakelockPlus.disable(); // Ensure wakelock is disabled
    super.dispose();
  }

  // --- Preference Methods ---

  Future<void> _loadSelectedDuration() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMinutes = prefs.getInt(_prefSelectedDurationKey);
    if (savedMinutes != null) {
      setState(() {
        _selectedDuration = Duration(minutes: savedMinutes);
        _resetTimerVisuals(); // Update timeLeft when duration loads
      });
    }
  }

  Future<void> _saveSelectedDuration(Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefSelectedDurationKey, duration.inMinutes);
  }

  // --- UI Methods ---

  void _showDurationPicker() {
    final durations = [1, 5, 10, 15, 20, 30]; // Pre-set durations in minutes

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: const Text('Select Meditation Duration'),
          children: durations.map((minutes) {
            final duration = Duration(minutes: minutes);
            return SimpleDialogOption(
              onPressed: () {
                setState(() {
                  _selectedDuration = duration;
                  _resetTimerVisuals(); // Reset timer display to new duration
                });
                _saveSelectedDuration(duration); // Save the selected duration
                Navigator.pop(context);
              },
              child: Text('$minutes minutes'),
            );
          }).toList(),
        );
      },
    );
  }

  // --- Timer Control Methods ---

  void _startTimer({bool resuming = false}) {
    // Reset timeLeft only if starting fresh, not resuming
    if (!resuming) {
      setState(() {
         _timeLeft = _selectedDuration; // Start countdown from selected duration
      });
       _playStartSound(); // Play start sound only on fresh start
    }

    _timerState = TimerState.running;
    WakelockPlus.enable(); // Keep screen awake

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft.inSeconds > 0) {
        setState(() {
          _timeLeft -= const Duration(seconds: 1);
        });
      } else {
        _timerCompleted(); // Timer finished
      }
    });
  }

  void _pauseTimer() {
    if (_timerState == TimerState.running) {
      _timer?.cancel();
      setState(() {
        _timerState = TimerState.paused;
      });
      WakelockPlus.disable(); // Allow screen to sleep
    }
  }

  void _resumeTimer() {
    if (_timerState == TimerState.paused) {
      _startTimer(resuming: true); // Restart timer logic without resetting seconds
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    WakelockPlus.disable(); // Allow screen to sleep
    _playEndSound(); // Play end sound on stop

    // Calculate elapsed duration for saving
    final elapsedDuration = _selectedDuration - _timeLeft;

    // Save session only if timer was running/paused and duration is sufficient
    if (_timerState == TimerState.running || _timerState == TimerState.paused) {
       _saveSession(elapsedDuration);
    }

    // Reset state after stopping
    setState(() {
      _timerState = TimerState.initial;
      _resetTimerVisuals(); // Reset timer display
    });
  }

  void _timerCompleted() {
    _timer?.cancel();
    WakelockPlus.disable();
    _playEndSound(); // Play end sound on completion

    _saveSession(_selectedDuration); // Save session with the full selected duration

    // Reset state after completion
    setState(() {
      _timerState = TimerState.initial;
      _resetTimerVisuals(); // Reset timer display
    });
  }

  // --- Session Saving Logic ---

  Future<void> _saveSession(Duration duration) async {
     if (duration.inSeconds >= _minSessionDuration) {
      final session = MeditationSession(
        sessionDateTime: DateTime.now(),
        durationSeconds: duration.inSeconds, // Use the passed duration
      );

      try {
        final dbHelper = Provider.of<DatabaseHelper>(context, listen: false);
        await dbHelper.insertSession(session);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Meditation session saved!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving session: $e')),
          );
        }
      }
    } else if (_timerState != TimerState.initial) { // Only show "too short" if timer was actually running/paused
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
               content: Text(
                   'Session too short (minimum $_minSessionDuration seconds). Not saved.')),
         );
       }
     }
  }

  // --- Audio Methods ---

  Future<void> _playStartSound() async {
    try {
      // Note: Place your actual start_sound.mp3 in assets/audio/
      await _audioPlayer.play(AssetSource(_startSoundPath));
    } catch (e) {
      print("Error playing start sound: $e");
      // Optionally show a snackbar or log error
    }
  }

  Future<void> _playEndSound() async {
    try {
      // Note: Place your actual end_sound.mp3 in assets/audio/
      await _audioPlayer.play(AssetSource(_endSoundPath));
    } catch (e) {
      print("Error playing end sound: $e");
      // Optionally show a snackbar or log error
    }
  }

  // --- Helper Methods ---

  // Resets the timeLeft display to the currently selected duration
  void _resetTimerVisuals() {
    setState(() {
      _timeLeft = _selectedDuration;
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // --- Build Method ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meditation Timer'),
      ),
      body: Padding( // Add padding around the content
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // --- Duration Selection Button ---
              TextButton(
                onPressed: _timerState == TimerState.initial ? _showDurationPicker : null, // Only allow changing when stopped
                child: Text(
                  'Duration: ${_formatDuration(_selectedDuration)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _timerState == TimerState.initial ? Theme.of(context).colorScheme.primary : Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // --- Timer Display with Progress ---
              SizedBox(
                width: 250, // Adjust size as needed
                height: 250,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Circular Progress Indicator
                    CircularProgressIndicator(
                      value: _calculateProgress(),
                      strokeWidth: 10,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                    ),
                    // Time Left Text
                    Center(
                      child: Text(
                        _formatDuration(_timeLeft), // Display time left
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 60), // Adjust font size
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // --- Control Buttons ---
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _buildControlButtons(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Button Building Logic ---

  List<Widget> _buildControlButtons() {
    switch (_timerState) {
      case TimerState.initial:
        return [
          ElevatedButton(
            onPressed: () => _startTimer(),
            child: const Text('Start'),
          ),
        ];
      case TimerState.running:
        return [
          ElevatedButton(
            onPressed: _pauseTimer,
            child: const Text('Pause'),
          ),
          const SizedBox(width: 20),
          ElevatedButton(
            onPressed: _stopTimer,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Stop'),
          ),
        ];
      case TimerState.paused:
        return [
          ElevatedButton(
            onPressed: _resumeTimer,
            child: const Text('Resume'),
          ),
          const SizedBox(width: 20),
          ElevatedButton(
            onPressed: _stopTimer,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Stop'),
          ),
        ];
    }
  }

  // --- Helper Methods ---

  double _calculateProgress() {
    if (_selectedDuration.inSeconds == 0) {
      return 0.0; // Avoid division by zero
    }
    // Calculate progress: (total duration - time left) / total duration
    double elapsedSeconds = (_selectedDuration - _timeLeft).inSeconds.toDouble();
    return elapsedSeconds / _selectedDuration.inSeconds;
  }
}