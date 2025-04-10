import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date/time formatting
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/meditation_session.dart';
import '../services/database_helper.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final DatabaseHelper _dbHelper;
  Map<DateTime, List<MeditationSession>> _sessionsByDate = {};
  List<MeditationSession> _selectedDaySessions = [];
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    _dbHelper = Provider.of<DatabaseHelper>(context, listen: false);
    _selectedDay = _focusedDay; // Select today initially
    _loadAllSessions();
    _loadSessionsForSelectedDay(_selectedDay!);
  }

  // Load all sessions to populate the event markers
  Future<void> _loadAllSessions() async {
    final allSessions = await _dbHelper.getAllSessions();
    final Map<DateTime, List<MeditationSession>> sessionsMap = {};
    for (var session in allSessions) {
      // Normalize the date to midnight UTC to use as map key
      final dateKey = DateTime.utc(session.sessionDateTime.year,
          session.sessionDateTime.month, session.sessionDateTime.day);
      if (sessionsMap[dateKey] == null) {
        sessionsMap[dateKey] = [];
      }
      sessionsMap[dateKey]!.add(session);
    }
    if (mounted) {
      setState(() {
        _sessionsByDate = sessionsMap;
      });
    }
  }

  // Load sessions specifically for the selected day
  Future<void> _loadSessionsForSelectedDay(DateTime day) async {
    // Normalize the day to handle potential time zone differences if needed
    final normalizedDay = DateTime.utc(day.year, day.month, day.day);
    final sessions = await _dbHelper.getSessionsForDate(normalizedDay);
    if (mounted) {
      setState(() {
        _selectedDaySessions = sessions;
      });
    }
  }

  // Get events for a specific day for the calendar marker
  List<MeditationSession> _getEventsForDay(DateTime day) {
    // Normalize the day to match the map keys
    final normalizedDay = DateTime.utc(day.year, day.month, day.day);
    return _sessionsByDate[normalizedDay] ?? [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay; // update focused day as well
        _selectedDaySessions = []; // Clear previous sessions immediately
      });
      _loadSessionsForSelectedDay(selectedDay);
    }
  }

  // Helper to format duration
  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    final minutes = duration.inMinutes;
    final seconds = totalSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meditation Calendar'),
      ),
      body: Column(
        children: [
          TableCalendar<MeditationSession>(
            firstDay: DateTime.utc(2020, 1, 1), // Example first day
            lastDay: DateTime.utc(2030, 12, 31), // Example last day
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            calendarFormat: _calendarFormat,
            eventLoader: _getEventsForDay,
            startingDayOfWeek: StartingDayOfWeek.monday,
            calendarStyle: CalendarStyle(
              // Customize appearance if desired
              todayDecoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              markerDecoration: BoxDecoration(
                color: Colors.teal[400], // Color for the event marker dot
                shape: BoxShape.circle,
              ),
            ),
            headerStyle: const HeaderStyle(
              formatButtonVisible: false, // Hide format button for simplicity
              titleCentered: true,
            ),
            onDaySelected: _onDaySelected,
            onFormatChanged: (format) {
              if (_calendarFormat != format) {
                setState(() {
                  _calendarFormat = format;
                });
              }
            },
            onPageChanged: (focusedDay) {
              // No need to call `setState()` here
              _focusedDay = focusedDay;
              // Optional: Load sessions for the new visible month range if needed
            },
          ),
          const SizedBox(height: 8.0),
          // Display sessions for the selected day
          Expanded(
            child: _buildSessionList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionList() {
    if (_selectedDaySessions.isEmpty) {
      return Center(
        child: Text(
          'No sessions recorded for ${DateFormat.yMMMd().format(_selectedDay!)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }

    return ListView.builder(
      itemCount: _selectedDaySessions.length,
      itemBuilder: (context, index) {
        final session = _selectedDaySessions[index];
        return ListTile(
          leading: const Icon(Icons.self_improvement), // Example icon
          title: Text(
              'Time: ${DateFormat.jm().format(session.sessionDateTime.toLocal())}'), // Show time
          subtitle: Text(
              'Duration: ${_formatDuration(session.durationSeconds)}'), // Show duration
          // Optional: Add trailing info or onTap for details
        );
      },
    );
  }
}