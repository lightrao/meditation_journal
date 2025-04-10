import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../models/meditation_session.dart'; // Import the model

/// A singleton class to manage the application's SQLite database.
class DatabaseHelper {
  // Singleton instance
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  static const String _dbName = 'meditation_journal.db';
  static const String _tableName = 'meditation_sessions';
  static const int _dbVersion = 1;

  /// Returns the database instance, initializing it if necessary.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initializes the database connection and creates the table if it doesn't exist.
  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      // onUpgrade: _onUpgrade, // Optional: Add for future schema migrations
    );
  }

  /// Called when the database is created for the first time.
  /// Creates the meditation_sessions table.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sessionDateTime TEXT NOT NULL,
        durationSeconds INTEGER NOT NULL,
        notes TEXT NULL
      )
    ''');
    // Create an index on sessionDateTime for faster date-based queries
    await db.execute('''
      CREATE INDEX idx_session_datetime ON $_tableName (sessionDateTime)
    ''');
  }

  // --- CRUD Method Stubs ---

  /// Inserts a new meditation session into the database.
  Future<int> insertSession(MeditationSession session) async {
    final db = await database;
    // Use toMap() which handles DateTime to String conversion
    return await db.insert(_tableName, session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Retrieves all meditation sessions from the database, ordered by date descending.
  Future<List<MeditationSession>> getAllSessions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      orderBy: 'sessionDateTime DESC',
    );

    // Convert the List<Map<String, dynamic>> into a List<MeditationSession>.
    return List.generate(maps.length, (i) {
      return MeditationSession.fromMap(maps[i]);
    });
  }

  /// Retrieves sessions for a specific date.
  Future<List<MeditationSession>> getSessionsForDate(DateTime date) async {
    final db = await database;
    // Query for sessions within the start and end of the given day
    final startOfDay = DateTime(date.year, date.month, date.day).toIso8601String();
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999).toIso8601String();

    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'sessionDateTime >= ? AND sessionDateTime <= ?',
      whereArgs: [startOfDay, endOfDay],
      orderBy: 'sessionDateTime DESC',
    );

    return List.generate(maps.length, (i) {
      return MeditationSession.fromMap(maps[i]);
    });
  }

  /// Retrieves sessions within a specific date range.
  Future<List<MeditationSession>> getSessionsDateRange(DateTime start, DateTime end) async {
     final db = await database;
     // Ensure the end time includes the entire end day
     final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
     final List<Map<String, dynamic>> maps = await db.query(
       _tableName,
       where: 'sessionDateTime >= ? AND sessionDateTime <= ?',
       whereArgs: [start.toIso8601String(), endOfDay.toIso8601String()],
       orderBy: 'sessionDateTime DESC',
     );

     return List.generate(maps.length, (i) {
       return MeditationSession.fromMap(maps[i]);
     });
  }

  /// Updates an existing meditation session.
  Future<int> updateSession(MeditationSession session) async {
    final db = await database;
    return await db.update(
      _tableName,
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  /// Deletes a meditation session by its ID.
  Future<int> deleteSession(int id) async {
    final db = await database;
    return await db.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Checks if a session with the exact DateTime already exists.
  Future<bool> sessionExists(DateTime dateTime) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      _tableName,
      where: 'sessionDateTime = ?',
      whereArgs: [dateTime.toIso8601String()],
      limit: 1, // We only need to know if at least one exists
    );
    return result.isNotEmpty;
  }


  // Optional: Close the database when it's no longer needed
  Future<void> close() async {
    final db = await database;
    _database = null;
    await db.close();
  }
}