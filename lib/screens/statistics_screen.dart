import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math'; // For max function

import '../services/database_helper.dart';
import '../models/meditation_session.dart';

// Enum to represent the time period for the chart
enum ChartPeriod { daily, weekly, monthly }

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late Future<List<MeditationSession>> _sessionsFuture;
  ChartPeriod _selectedPeriod = ChartPeriod.weekly; // Default period

  // Calculated values
  Duration _totalTime = Duration.zero;
  Duration _avgDuration = Duration.zero;
  int _currentStreak = 0;
  int _longestStreak = 0;
  Map<String, double> _chartData = {}; // Key: Period label, Value: Total seconds

  @override
  void initState() {
    super.initState();
    // Initial load is triggered by FutureBuilder, but we might need to reload
    // if data changes elsewhere. For now, FutureBuilder handles initial load.
    _loadSessions();
  }

  void _loadSessions() {
    final dbHelper = Provider.of<DatabaseHelper>(context, listen: false);
    _sessionsFuture = dbHelper.getAllSessions();
    // When sessions are loaded, calculate stats
    _sessionsFuture.then((sessions) {
      if (mounted) { // Check if the widget is still in the tree
        _calculateAllStats(sessions);
      }
    });
  }

  // --- Calculation Logic ---

  void _calculateAllStats(List<MeditationSession> sessions) {
    if (sessions.isEmpty) {
      setState(() {
        _totalTime = Duration.zero;
        _avgDuration = Duration.zero;
        _currentStreak = 0;
        _longestStreak = 0;
        _chartData = {};
      });
      return;
    }

    // Sort sessions by date for streak calculation
    sessions.sort((a, b) => a.sessionDateTime.compareTo(b.sessionDateTime));

    // Calculate KPIs
    _totalTime = _calculateTotalTime(sessions);
    _avgDuration = _calculateAverageDuration(sessions, _totalTime);
    _currentStreak = _calculateCurrentStreak(sessions);
    _longestStreak = _calculateLongestStreak(sessions);

    // Aggregate data for the currently selected chart period
    _chartData = _aggregateChartData(sessions, _selectedPeriod);

    // Update the state to reflect calculations
    setState(() {});
  }


  Duration _calculateTotalTime(List<MeditationSession> sessions) {
    int totalSeconds = sessions.fold(0, (sum, session) => sum + session.durationSeconds);
    return Duration(seconds: totalSeconds);
  }

  Duration _calculateAverageDuration(List<MeditationSession> sessions, Duration totalTime) {
    if (sessions.isEmpty) return Duration.zero;
    return Duration(seconds: (totalTime.inSeconds / sessions.length).round());
  }

  // Helper to check if two dates are consecutive days
  bool _isConsecutive(DateTime date1, DateTime date2) {
      DateTime day1 = DateTime(date1.year, date1.month, date1.day);
      DateTime day2 = DateTime(date2.year, date2.month, date2.day);
      return day2.difference(day1).inDays == 1;
  }

  // Helper to check if a date is today or yesterday
  bool _isTodayOrYesterday(DateTime date) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final checkDay = DateTime(date.year, date.month, date.day);
      return checkDay == today || checkDay == yesterday;
  }

  int _calculateCurrentStreak(List<MeditationSession> sessions) {
    if (sessions.isEmpty) return 0;

    // Get unique days with sessions, sorted descending
    final uniqueDays = sessions.map((s) => DateTime(s.sessionDateTime.year, s.sessionDateTime.month, s.sessionDateTime.day))
                               .toSet()
                               .toList()
                               ..sort((a, b) => b.compareTo(a)); // Descending

    if (uniqueDays.isEmpty) return 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    // Check if the most recent session day is today or yesterday
    if (uniqueDays.first != today && uniqueDays.first != yesterday) {
      return 0; // Streak broken if no session today or yesterday
    }

    int currentStreak = 0;
    DateTime expectedDate = uniqueDays.first;

    for (final day in uniqueDays) {
        if (day == expectedDate) {
            currentStreak++;
            expectedDate = expectedDate.subtract(const Duration(days: 1));
        } else {
            // Found a gap, stop counting the current streak
            break;
        }
    }

    return currentStreak;
  }


  int _calculateLongestStreak(List<MeditationSession> sessions) {
    if (sessions.isEmpty) return 0;

    // Get unique days with sessions, sorted ascending
    final uniqueDays = sessions.map((s) => DateTime(s.sessionDateTime.year, s.sessionDateTime.month, s.sessionDateTime.day))
                               .toSet()
                               .toList()
                               ..sort((a, b) => a.compareTo(b)); // Ascending

    if (uniqueDays.isEmpty) return 0;

    int longestStreak = 0;
    int currentStreak = 0;

    for (int i = 0; i < uniqueDays.length; i++) {
      if (i == 0) {
        // Start of the list
        currentStreak = 1;
      } else {
        // Check if consecutive to the previous day
        if (_isConsecutive(uniqueDays[i-1], uniqueDays[i])) {
          currentStreak++;
        } else {
          // Gap found, reset current streak
          longestStreak = max(longestStreak, currentStreak);
          currentStreak = 1; // Start new streak
        }
      }
    }
    // Check the last streak after the loop finishes
    longestStreak = max(longestStreak, currentStreak);

    return longestStreak;
  }

  Map<String, double> _aggregateChartData(List<MeditationSession> sessions, ChartPeriod period) {
    Map<String, double> aggregatedData = {};
    DateFormat formatter;

    switch (period) {
      case ChartPeriod.daily:
        // Group by YYYY-MM-DD
        formatter = DateFormat('yyyy-MM-dd');
        for (var session in sessions) {
          String dayKey = formatter.format(session.sessionDateTime);
          aggregatedData[dayKey] = (aggregatedData[dayKey] ?? 0) + session.durationSeconds;
        }
        break;
      case ChartPeriod.weekly:
         // Group by Year and Week Number (ISO 8601 week date)
        formatter = DateFormat('yyyy-ww'); // 'ww' gives week number
        for (var session in sessions) {
            // Calculate ISO week number
            int dayOfYear = int.parse(DateFormat("D").format(session.sessionDateTime));
            int weekOfYear = ((dayOfYear - session.sessionDateTime.weekday + 10) / 7).floor();
            // Handle edge case for start/end of year if needed, basic approach:
            String weekKey = "${session.sessionDateTime.year}-W${weekOfYear.toString().padLeft(2, '0')}";
            aggregatedData[weekKey] = (aggregatedData[weekKey] ?? 0) + session.durationSeconds;
        }
        break;
      case ChartPeriod.monthly:
        // Group by YYYY-MM
        formatter = DateFormat('yyyy-MM');
        for (var session in sessions) {
          String monthKey = formatter.format(session.sessionDateTime);
          aggregatedData[monthKey] = (aggregatedData[monthKey] ?? 0) + session.durationSeconds;
        }
        break;
    }

    // Sort keys for chronological order on the chart
    var sortedKeys = aggregatedData.keys.toList()..sort();
    Map<String, double> sortedData = { for (var k in sortedKeys) k : aggregatedData[k]! };

    return sortedData;
  }

  // Helper to format duration
  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return "${duration.inHours}h ${duration.inMinutes.remainder(60)}m";
    } else {
      return "${duration.inMinutes}m";
    }
  }

  // --- UI Building ---
  Widget _buildKPIs() {
    return Column(
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.access_time_filled),
            title: const Text('Total Time'),
            trailing: Text(_formatDuration(_totalTime)),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.timelapse),
            title: const Text('Average Session'),
            trailing: Text(_formatDuration(_avgDuration)),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.local_fire_department), // Streak icon
            title: const Text('Current Streak'),
            trailing: Text('$_currentStreak Day${_currentStreak == 1 ? '' : 's'}'),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.star), // Longest streak icon
            title: const Text('Longest Streak'),
            trailing: Text('$_longestStreak Day${_longestStreak == 1 ? '' : 's'}'),
          ),
        ),
      ],
    );
  }

  Widget _buildChart() {
    if (_chartData.isEmpty) {
      return const AspectRatio(
        aspectRatio: 1.7,
        child: Card(child: Center(child: Text("Not enough data for chart"))),
      );
    }

    final List<BarChartGroupData> barGroups = [];
    int index = 0;
    double maxY = 0; // Find max Y value for axis scaling

    _chartData.forEach((key, value) {
       final durationMinutes = value / 60.0; // Convert seconds to minutes for Y axis
       maxY = max(maxY, durationMinutes);
       barGroups.add(
         BarChartGroupData(
           x: index,
           barRods: [
             BarChartRodData(
               toY: durationMinutes,
               color: Theme.of(context).colorScheme.primary,
               width: 16, // Adjust width as needed
               borderRadius: BorderRadius.circular(4)
             ),
           ],
         ),
       );
       index++;
    });

    // Add some padding to the max Y value
    maxY = maxY * 1.2;
    // Ensure maxY is at least a small value if all durations are tiny
    maxY = max(maxY, 10.0); // e.g., ensure axis goes up to at least 10 minutes

    return AspectRatio(
      aspectRatio: 1.7,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        color: Theme.of(context).colorScheme.surfaceVariant, // Use theme color
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => Colors.blueGrey, // Use getTooltipColor callback
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    String periodLabel = _chartData.keys.elementAt(group.x);
                    String durationLabel = _formatDuration(Duration(seconds: (_chartData[periodLabel] ?? 0).toInt()));
                    return BarTooltipItem(
                      '$periodLabel\n',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      children: <TextSpan>[
                        TextSpan(
                          text: durationLabel,
                          style: const TextStyle(
                            color: Colors.yellow,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (double value, TitleMeta meta) {
                      final index = value.toInt();
                      String text = '';
                      if (index >= 0 && index < _chartData.length) {
                        text = _chartData.keys.elementAt(index);
                        // Optionally shorten labels if they become too long/crowded
                        if (_selectedPeriod == ChartPeriod.daily && text.length > 5) {
                           text = text.substring(5); // Show MM-DD
                        } else if (_selectedPeriod == ChartPeriod.weekly && text.length > 8) {
                           text = text.substring(5); // Show Www
                        } else if (_selectedPeriod == ChartPeriod.monthly && text.length > 7) {
                           text = text.substring(5); // Show MM
                        }
                      }
                      return SideTitleWidget(
                        axisSide: meta.axisSide,
                        space: 4.0,
                        child: Text(text, style: const TextStyle(fontSize: 10)),
                      );
                    },
                    reservedSize: 30, // Adjust space for labels
                    interval: 1, // Show label for each bar
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40, // Adjust space for labels
                    getTitlesWidget: (value, meta) {
                      // Show labels in minutes
                      if (value == 0 || value == meta.max) return Container(); // Avoid clutter at edges
                      return Text('${value.toInt()}m', style: const TextStyle(fontSize: 10));
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false, // Hide vertical grid lines
                  getDrawingHorizontalLine: (value) {
                    return const FlLine(
                      color: Colors.grey, // Customize grid line color
                      strokeWidth: 0.5,
                    );
                  },
              ),
              barGroups: barGroups,
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildPeriodSelector() {
    return SegmentedButton<ChartPeriod>(
      segments: const <ButtonSegment<ChartPeriod>>[
        ButtonSegment<ChartPeriod>(
            value: ChartPeriod.daily,
            label: Text('Daily'),
            icon: Icon(Icons.calendar_view_day)),
        ButtonSegment<ChartPeriod>(
            value: ChartPeriod.weekly,
            label: Text('Weekly'),
            icon: Icon(Icons.calendar_view_week)),
        ButtonSegment<ChartPeriod>(
            value: ChartPeriod.monthly,
            label: Text('Monthly'),
            icon: Icon(Icons.calendar_month)),
      ],
      selected: <ChartPeriod>{_selectedPeriod},
      onSelectionChanged: (Set<ChartPeriod> newSelection) {
        setState(() {
          _selectedPeriod = newSelection.first;
          // Recalculate chart data based on the new period
          // We need the sessions data here. Access it from the snapshot in build or re-fetch/re-process.
          // Easiest is to re-process from the already fetched future's result.
          _sessionsFuture.then((sessions) {
             if (mounted) {
               setState(() {
                 _chartData = _aggregateChartData(sessions, _selectedPeriod);
               });
             }
          });
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
      ),
      body: FutureBuilder<List<MeditationSession>>(
        future: _sessionsFuture,
        // We trigger calculations in initState/didChangeDependencies and when period changes.
        // The FutureBuilder just handles the initial loading state.
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && _totalTime == Duration.zero) {
             // Show loading only on initial load before first calculation
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error loading data: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
             // Handle case where future completes but has no data
             // Calculations should have set KPIs to zero/empty
            return ListView( // Show KPIs even if zero, but indicate no data for chart
               padding: const EdgeInsets.all(16.0),
               children: [
                 _buildKPIs(),
                 const SizedBox(height: 20),
                 _buildPeriodSelector(),
                 const SizedBox(height: 10),
                 const AspectRatio(
                   aspectRatio: 1.7,
                   child: Card(child: Center(child: Text("No meditation data yet."))),
                 ),
               ],
             );
          } else {
            // Data is loaded and calculations are done (triggered by .then in _loadSessions or period change)
            return RefreshIndicator( // Optional: Add pull-to-refresh
              onRefresh: () async {
                 _loadSessions(); // Re-fetch and re-calculate
                 await _sessionsFuture; // Wait for the future to complete
              },
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildKPIs(),
                  const SizedBox(height: 20),
                  _buildPeriodSelector(),
                  const SizedBox(height: 10),
                  _buildChart(),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}