import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart'; // Keep this import
import 'package:provider/provider.dart';
import 'services/database_helper.dart';
import 'services/notification_service.dart'; // Import NotificationService
import 'screens/timer_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/statistics_screen.dart';
import 'screens/settings_screen.dart' as my_screens;
import 'package:flutter_settings_screens/flutter_settings_screens.dart' hide SettingsScreen;

// Define keys for settings consistently
const String kDailyReminderEnabled = 'daily_reminder_enabled';
const String kDailyReminderTime = 'daily_reminder_time';

void main() async { // Make main async
  // Ensure Flutter bindings are initialized before using plugins
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize flutter_settings_screens
  await Settings.init();

  // Initialize DatabaseHelper
  final databaseHelper = DatabaseHelper();
  // Optional: Initialize the database if needed (e.g., open connection)
  // await databaseHelper.database; // Uncomment if initialization is required here

  // Initialize NotificationService
  final notificationService = NotificationService();
  await notificationService.init();

  // Reschedule reminder on startup if enabled
  // Use ?? false to handle potential null return from getValue
  final bool isReminderEnabled = Settings.getValue<bool>(kDailyReminderEnabled, defaultValue: false) ?? false;
  if (isReminderEnabled) {
    // Retrieve the stored TimeOfDay. Need to handle potential null or incorrect type.
    // flutter_settings_screens might store TimeOfDay in a specific format (e.g., Map or String).
    // Let's assume it stores it correctly retrieveable as TimeOfDay for now.
    // We need a default time if none is stored yet.
    final TimeOfDay defaultTime = const TimeOfDay(hour: 8, minute: 0); // Default 8:00 AM
    final TimeOfDay? reminderTime = Settings.getValue<TimeOfDay>(kDailyReminderTime, defaultValue: defaultTime);

    if (reminderTime != null) {
        print("Rescheduling reminder on startup for $reminderTime");
        // No need to request permissions here, assume they were granted when enabled.
        // If permissions were revoked, scheduling might fail silently or throw.
        // A more robust solution might re-check permissions.
        await notificationService.scheduleDailyReminder(reminderTime);
    } else {
        print("Reminder enabled but no valid time found in settings. Cannot reschedule.");
        // Optionally, disable the reminder setting if the time is invalid/missing
        // Settings.setValue(kDailyReminderEnabled, false);
    }
  }


  runApp(
    // Provide multiple services using MultiProvider
    MultiProvider(
      providers: [
        Provider<DatabaseHelper>(create: (_) => databaseHelper),
        Provider<NotificationService>(create: (_) => notificationService),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meditation Journal', // Updated title
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), // Example theme color
        useMaterial3: true,
      ), // <-- Added missing comma here
      // Set HomeScreen as the home screen
      home: const HomeScreen(),
    );
  }
}

// Removed the default MyHomePage StatefulWidget and its State

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // List of widgets to display based on the selected index
  // List of widgets to display based on the selected index
  // Remove 'const' because SettingsScreen() might not be const
  static final List<Widget> _widgetOptions = <Widget>[
    const TimerScreen(), // Assuming these have const constructors
    const CalendarScreen(), // Assuming these have const constructors
    const StatisticsScreen(), // Assuming these have const constructors
    my_screens.SettingsScreen(), // Use prefix, remove const
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // AppBar can be removed if each screen provides its own,
      // or kept for a consistent top bar. Let's remove it for now.
      // appBar: AppBar(
      //   title: const Text('Meditation Journal'),
      // ),
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.timer),
            label: 'Timer',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Calendar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart), // Or Icons.analytics, Icons.show_chart
            label: 'Stats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
        type: BottomNavigationBarType.fixed, // Explicitly set type for 4+ items
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey, // Set unselected color for clarity
        onTap: _onItemTapped,
      ),
    );
  }
}
