import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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
  int _elapsedSeconds = 0;
  TimerState _timerState = TimerState.initial;
  final int _minSessionDuration = 10; // Minimum duration in seconds to save

  @override
  void dispose() {
    _timer?.cancel();
    WakelockPlus.disable(); // Ensure wakelock is disabled when screen is disposed
    super.dispose();
  }

  // --- Timer Control Methods ---

  void _startTimer({bool resuming = false}) {
    if (!resuming) {
      _elapsedSeconds = 0; // Reset if starting fresh
    }
    _timerState = TimerState.running;
    WakelockPlus.enable(); // Keep screen awake
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedSeconds++;
      });
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

  void _stopTimer() async {
    _timer?.cancel();
    WakelockPlus.disable(); // Allow screen to sleep

    if (_elapsedSeconds >= _minSessionDuration) {
      final session = MeditationSession(
        sessionDateTime: DateTime.now(),
        durationSeconds: _elapsedSeconds,
      );

      try {
        // Access DatabaseHelper via Provider
        final dbHelper = Provider.of<DatabaseHelper>(context, listen: false);
        await dbHelper.insertSession(session);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Meditation session saved!')),
          );
        }
      } catch (e) {
        // Handle potential database errors
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving session: $e')),
          );
        }
      }
    } else {
      // Optional: Feedback if session was too short
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Session too short (minimum $_minSessionDuration seconds). Not saved.')),
        );
      }
    }

    // Reset state regardless of saving
    setState(() {
      _timerState = TimerState.initial;
      _elapsedSeconds = 0;
    });
  }

  // --- Helper Methods ---

  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              _formatDuration(_elapsedSeconds),
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _buildControlButtons(),
            ),
          ],
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
}