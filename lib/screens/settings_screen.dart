import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:provider/provider.dart';
import 'package:file_saver/file_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';

import '../services/database_helper.dart';
import '../services/notification_service.dart'; // Import NotificationService
import '../models/meditation_session.dart';
import '../main.dart'; // Import main to access keys

// Convert to StatefulWidget
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

// Create State class
class _SettingsScreenState extends State<SettingsScreen> {

  // Default time for the picker if none is set
  static const TimeOfDay _defaultTime = TimeOfDay(hour: 8, minute: 0);

  Future<void> _exportData(BuildContext context) async {
    final dbHelper = Provider.of<DatabaseHelper>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context); // Store for use after async gap

    try {
      final sessions = await dbHelper.getAllSessions();
      if (sessions.isEmpty) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('No data to export.')),
        );
        return;
      }

      // Convert sessions to list of maps using the existing toMap method
      final List<Map<String, dynamic>> sessionMaps =
          sessions.map((session) => session.toMap()).toList();

      // Construct the final export object
      final exportData = {
        'exportVersion': '1.0', // As per PRS (assuming version 1.0)
        'exportTimestamp': DateTime.now().toIso8601String(),
        'sessions': sessionMaps,
      };

      // Encode the data to a JSON string with indentation for readability
      const jsonEncoder = JsonEncoder.withIndent('  ');
      final jsonString = jsonEncoder.convert(exportData);

      // Save the file using file_saver
      // Note: file_saver typically saves to a common location (like Downloads)
      // and doesn't always allow picking a specific directory easily across platforms.
      final String fileName =
          'meditation_data_export_${DateTime.now().toIso8601String().split('T')[0]}.json';
      // Convert String to Uint8List
      // Use MimeType.text and specify extension as .json
      // file_saver doesn't have a specific MimeType.JSON
      final MimeType type = MimeType.text;
      final bytes = utf8.encode(jsonString);

      String? path = await FileSaver.instance.saveFile(
          name: fileName, // file name
          bytes: bytes, // data being saved
          ext: 'json', // file extension
          mimeType: type // mime type
          );

      if (path != null) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Data exported successfully to $path')),
        );
      } else {
         scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Export cancelled or failed (no path returned).')),
        );
      }
    } catch (e) {
      // Log the error for debugging
      print('Export failed: $e');
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Export failed: ${e.toString()}')),
      );
    }
  }

  // Removed duplicate _importData function definition here

  Future<void> _importData(BuildContext context) async {
    final dbHelper = Provider.of<DatabaseHelper>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      // 1. Pick the file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);

        // 2. Read file content
        final String jsonString = await file.readAsString();

        // 3. Decode JSON
        final Map<String, dynamic> jsonData = jsonDecode(jsonString);

        // 4. Validate structure (basic check)
        if (jsonData case {'sessions': List sessionsList}) {
          int addedCount = 0;
          int skippedCount = 0;
          int errorCount = 0;

          // 5. Iterate through sessions
          for (var sessionData in sessionsList) {
            if (sessionData is Map<String, dynamic>) {
              try {
                // 6a. Parse session
                // Important: Use fromMap as it aligns with the DB/JSON structure used
                final session = MeditationSession.fromMap(sessionData);

                // 6b. Check for duplicates
                final bool exists = await dbHelper.sessionExists(session.sessionDateTime);

                if (!exists) {
                  // 6c. Insert non-duplicate
                  await dbHelper.insertSession(session);
                  addedCount++;
                } else {
                  skippedCount++;
                }
              } catch (e) {
                // Handle parsing errors for individual sessions
                print('Error parsing session data: $sessionData. Error: $e');
                errorCount++;
                // Optionally skip this entry or handle differently
              }
            } else {
               print('Skipping invalid session data format: $sessionData');
               errorCount++;
            }
          }

          // 7. Provide feedback
          String message = 'Import complete. $addedCount sessions added, $skippedCount skipped (duplicates).';
          if (errorCount > 0) {
            message += ' $errorCount entries failed to parse.';
          }
          scaffoldMessenger.showSnackBar(SnackBar(content: Text(message)));

          // TODO: Consider triggering a state refresh for Calendar/Stats screens
          // This might involve calling a method on a shared state provider/notifier

        } else {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('Import failed: Invalid JSON format (missing "sessions" list).')),
          );
        }
      } else {
        // User canceled the picker
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Import cancelled.')),
        );
      }
    } catch (e) {
      // Handle general errors (file reading, JSON parsing, etc.)
      print('Import failed: $e');
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Import failed: ${e.toString()}')),
      );
    }
  }


  @override
  @override
  Widget build(BuildContext context) {
    // IMPORTANT: Settings.init() should ideally be called *once* in main.dart
    // before runApp() for better performance and to avoid potential issues.
    // Adding it here temporarily for demonstration if not done in main.
    // Consider moving this call to main.dart.
    // WidgetsFlutterBinding.ensureInitialized(); // Needed if called before runApp
    // await Settings.init(); // Use await if in async main

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView( // Use ListView as the main body container
        children: [
          SettingsGroup( // Place SettingsGroup directly inside ListView
            title: 'Data Management', // Title for the group
            children: <Widget>[ // Children are the individual setting tiles
              SimpleSettingsTile(
                title: 'Export Data',
                subtitle: 'Save your meditation data to a JSON file.',
                leading: const Icon(Icons.upload_file),
                onTap: () => _exportData(context),
              ),
              SimpleSettingsTile(
                title: 'Import Data',
                subtitle: 'Load meditation data from a JSON file.',
                leading: const Icon(Icons.file_download),
                onTap: () => _importData(context),
              ),
            ],
          ),
          // --- Notifications Settings Group ---
          SettingsGroup(
            title: 'Notifications',
            children: <Widget>[
              // --- Enable/Disable Switch ---
              SwitchSettingsTile(
                settingKey: kDailyReminderEnabled,
                title: 'Enable Daily Reminder',
                defaultValue: false,
                leading: const Icon(Icons.notifications_active),
                // Update onChange to call setState
                onChange: (bool value) async {
                  final notificationService = Provider.of<NotificationService>(context, listen: false);
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  bool settingChanged = false; // Flag to check if we need to call setState

                  if (value) {
                    print('Daily reminder switch turned ON');
                    bool permissionsGranted = await notificationService.requestPermissions();
                    if (permissionsGranted) {
                      final TimeOfDay reminderTime = Settings.getValue<TimeOfDay>(
                            kDailyReminderTime,
                            defaultValue: _defaultTime,
                          ) ?? _defaultTime;
                      await notificationService.scheduleDailyReminder(reminderTime);
                      scaffoldMessenger.showSnackBar(
                        SnackBar(content: Text('Daily reminder scheduled for ${reminderTime.format(context)}.')),
                      );
                      // No need to call Settings.setValue here, the tile does it.
                      settingChanged = true;
                    } else {
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(content: Text('Notification permissions denied. Cannot schedule reminder.')),
                      );
                       // Force the setting back to false if permissions denied
                       // Use notify: false as we will call setState manually
                       await Settings.setValue<bool>(kDailyReminderEnabled, false, notify: false);
                       settingChanged = true; // Need to update UI as we forced the value back
                    }
                  } else {
                    print('Daily reminder switch turned OFF');
                    await notificationService.cancelDailyReminder();
                     scaffoldMessenger.showSnackBar(
                      const SnackBar(content: Text('Daily reminder cancelled.')),
                    );
                    // No need to call Settings.setValue here, the tile does it.
                    settingChanged = true;
                  }
                  // Trigger rebuild if the logical state might have changed
                  if (settingChanged) {
                    setState(() {});
                  }
                },
              ),
              // --- Time Picker Tile (conditionally enabled) ---
              // Read values directly in build method
              () {
                final bool isEnabled = Settings.getValue<bool>(kDailyReminderEnabled, defaultValue: false) ?? false;
                final TimeOfDay currentTime = Settings.getValue<TimeOfDay>(kDailyReminderTime, defaultValue: _defaultTime) ?? _defaultTime;

                return SimpleSettingsTile(
                  title: 'Reminder Time',
                  subtitle: 'Set to: ${currentTime.format(context)}',
                  leading: const Icon(Icons.access_time),
                  enabled: isEnabled, // Enable/disable based on the switch state read above
                  onTap: isEnabled // Only allow tap if enabled
                      ? () async {
                          final TimeOfDay? pickedTime = await showTimePicker(
                            context: context,
                            initialTime: currentTime,
                          );

                          if (pickedTime != null && pickedTime != currentTime) {
                            print('New reminder time picked: ${pickedTime.format(context)}');
                            // Save the new time, use notify: false as we call setState
                            await Settings.setValue<TimeOfDay>(kDailyReminderTime, pickedTime, notify: false);

                            // Reschedule notification
                            final notificationService = Provider.of<NotificationService>(context, listen: false);
                            await notificationService.scheduleDailyReminder(pickedTime);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Reminder rescheduled for ${pickedTime.format(context)}.')),
                            );
                            // Trigger rebuild to update subtitle
                            setState(() {});
                          }
                        }
                      : null, // Disable onTap if switch is off
                );
              }(), // Immediately invoke the anonymous function to return the widget
            ],
          ),
          // --- End Notifications Settings Group ---
        ],
      ),
    );
  }
}