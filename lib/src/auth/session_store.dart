import 'dart:async';
import 'dart:convert';
import 'dart:math';
import '../core/logger.dart';
import '../orm/database_connection.dart';

/// Abstract base class for session storage
///
/// Defines the interface for storing and retrieving user sessions.
/// Implementations can use memory, database, Redis, etc.
abstract class SessionStore {
  /// Create a new session and return session ID
  Future<String> create();

  /// Get session by ID
  Future<Session?> get(String sessionId);

  /// Save session data
  Future<void> save(String sessionId, Session session);

  /// Delete session
  Future<void> delete(String sessionId);

  /// Clean up expired sessions
  Future<void> cleanup();

  /// Check if session exists
  Future<bool> exists(String sessionId);
}

/// In-memory session store implementation
///
/// Stores sessions in memory. Sessions are lost when the application restarts.
/// Suitable for development and single-instance deployments.
class MemorySessionStore implements SessionStore {
  static final ScopedLogger _logger = DLogger.scoped('MEMORY_SESSION_STORE');

  final Map<String, Session> _sessions = {};
  final Duration _defaultExpiry;
  Timer? _cleanupTimer;

  MemorySessionStore({
    Duration defaultExpiry = const Duration(hours: 24),
    Duration cleanupInterval = const Duration(minutes: 15),
  }) : _defaultExpiry = defaultExpiry {
    // Start periodic cleanup
    _cleanupTimer = Timer.periodic(cleanupInterval, (_) => cleanup());
    _logger.info(
        'Memory session store initialized with ${_defaultExpiry.inHours}h expiry');
  }

  @override
  Future<String> create() async {
    final sessionId = _generateSessionId();
    final session = Session(
      id: sessionId,
      data: {},
      createdAt: DateTime.now(),
      lastAccessedAt: DateTime.now(),
      expiresAt: DateTime.now().add(_defaultExpiry),
    );

    _sessions[sessionId] = session;
    _logger.debug('Created session: $sessionId');
    return sessionId;
  }

  @override
  Future<Session?> get(String sessionId) async {
    final session = _sessions[sessionId];

    if (session == null) {
      _logger.debug('Session not found: $sessionId');
      return null;
    }

    if (session.isExpired) {
      _logger.debug('Session expired: $sessionId');
      await delete(sessionId);
      return null;
    }

    _logger.debug('Retrieved session: $sessionId');
    return session;
  }

  @override
  Future<void> save(String sessionId, Session session) async {
    _sessions[sessionId] = session;
    _logger.debug('Saved session: $sessionId');
  }

  @override
  Future<void> delete(String sessionId) async {
    _sessions.remove(sessionId);
    _logger.debug('Deleted session: $sessionId');
  }

  @override
  Future<void> cleanup() async {
    final expiredSessions = <String>[];

    for (final entry in _sessions.entries) {
      if (entry.value.isExpired) {
        expiredSessions.add(entry.key);
      }
    }

    for (final sessionId in expiredSessions) {
      await delete(sessionId);
    }

    if (expiredSessions.isNotEmpty) {
      _logger.info('Cleaned up ${expiredSessions.length} expired sessions');
    }
  }

  @override
  Future<bool> exists(String sessionId) async {
    return _sessions.containsKey(sessionId) && !_sessions[sessionId]!.isExpired;
  }

  /// Generate secure session ID
  String _generateSessionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Dispose resources
  void dispose() {
    _cleanupTimer?.cancel();
    _sessions.clear();
    _logger.info('Memory session store disposed');
  }
}

/// Database-backed session store implementation
///
/// Stores sessions in PostgreSQL database for persistence across application restarts
/// and multi-instance deployments.
class DatabaseSessionStore implements SessionStore {
  static final ScopedLogger _logger = DLogger.scoped('DATABASE_SESSION_STORE');

  final DatabaseConnection _db;
  final Duration _defaultExpiry;
  final String _tableName;
  Timer? _cleanupTimer;

  DatabaseSessionStore({
    DatabaseConnection? db,
    Duration defaultExpiry = const Duration(hours: 24),
    Duration cleanupInterval = const Duration(minutes: 30),
    String tableName = 'sessions',
  })  : _db = db ?? DatabaseConnection.defaultConnection,
        _defaultExpiry = defaultExpiry,
        _tableName = tableName {
    // Initialize sessions table
    _initializeTable();

    // Start periodic cleanup
    _cleanupTimer = Timer.periodic(cleanupInterval, (_) => cleanup());
    _logger.info(
        'Database session store initialized with ${_defaultExpiry.inHours}h expiry');
  }

  @override
  Future<String> create() async {
    final sessionId = _generateSessionId();
    final now = DateTime.now();
    final expiresAt = now.add(_defaultExpiry);

    await _db.execute('''
      INSERT INTO $_tableName (id, data, created_at, last_accessed_at, expires_at)
      VALUES (@id, @data, @created_at, @last_accessed_at, @expires_at)
    ''', {
      'id': sessionId,
      'data': '{}',
      'created_at': now.toIso8601String(),
      'last_accessed_at': now.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
    });

    _logger.debug('Created session: $sessionId');
    return sessionId;
  }

  @override
  Future<Session?> get(String sessionId) async {
    final result = await _db.queryOne('''
      SELECT * FROM $_tableName WHERE id = @id AND expires_at > @now
    ''', {
      'id': sessionId,
      'now': DateTime.now().toIso8601String(),
    });

    if (result == null) {
      _logger.debug('Session not found or expired: $sessionId');
      return null;
    }

    final session = Session(
      id: result['id'],
      data: jsonDecode(result['data'] ?? '{}'),
      createdAt: DateTime.parse(result['created_at']),
      lastAccessedAt: DateTime.parse(result['last_accessed_at']),
      expiresAt: DateTime.parse(result['expires_at']),
    );

    _logger.debug('Retrieved session: $sessionId');
    return session;
  }

  @override
  Future<void> save(String sessionId, Session session) async {
    await _db.execute('''
      UPDATE $_tableName
      SET data = @data, last_accessed_at = @last_accessed_at, expires_at = @expires_at
      WHERE id = @id
    ''', {
      'id': sessionId,
      'data': jsonEncode(session.data),
      'last_accessed_at': session.lastAccessedAt.toIso8601String(),
      'expires_at': session.expiresAt.toIso8601String(),
    });

    _logger.debug('Saved session: $sessionId');
  }

  @override
  Future<void> delete(String sessionId) async {
    await _db
        .execute('DELETE FROM $_tableName WHERE id = @id', {'id': sessionId});
    _logger.debug('Deleted session: $sessionId');
  }

  @override
  Future<void> cleanup() async {
    final result = await _db.execute('''
      DELETE FROM $_tableName WHERE expires_at < @now
    ''', {'now': DateTime.now().toIso8601String()});

    if (result > 0) {
      _logger.info('Cleaned up $result expired sessions');
    }
  }

  @override
  Future<bool> exists(String sessionId) async {
    final result = await _db.queryOne('''
      SELECT 1 FROM $_tableName WHERE id = @id AND expires_at > @now
    ''', {
      'id': sessionId,
      'now': DateTime.now().toIso8601String(),
    });

    return result != null;
  }

  /// Initialize sessions table if it doesn't exist
  Future<void> _initializeTable() async {
    try {
      final tableExists = await _db.tableExists(_tableName);

      if (!tableExists) {
        await _db.execute('''
          CREATE TABLE $_tableName (
            id VARCHAR(255) PRIMARY KEY,
            data TEXT NOT NULL DEFAULT '{}',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            last_accessed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            expires_at TIMESTAMP NOT NULL
          )
        ''');

        // Add indexes for performance
        await _db.execute(
            'CREATE INDEX idx_${_tableName}_expires_at ON $_tableName (expires_at)');
        await _db.execute(
            'CREATE INDEX idx_${_tableName}_last_accessed ON $_tableName (last_accessed_at)');

        _logger.info('Created sessions table: $_tableName');
      }
    } catch (e) {
      _logger.error('Failed to initialize sessions table: $e');
      rethrow;
    }
  }

  /// Generate secure session ID
  String _generateSessionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Dispose resources
  void dispose() {
    _cleanupTimer?.cancel();
    _logger.info('Database session store disposed');
  }
}

/// Session data container
class Session {
  final String id;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  DateTime lastAccessedAt;
  DateTime expiresAt;

  Session({
    required this.id,
    required this.data,
    required this.createdAt,
    required this.lastAccessedAt,
    required this.expiresAt,
  });

  /// Check if session is expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Touch session (update last accessed time)
  void touch() {
    lastAccessedAt = DateTime.now();
  }

  /// Extend session expiry
  void extend(Duration duration) {
    expiresAt = DateTime.now().add(duration);
    touch();
  }

  /// Get session age
  Duration get age => DateTime.now().difference(createdAt);

  /// Get time since last access
  Duration get timeSinceLastAccess => DateTime.now().difference(lastAccessedAt);

  /// Get time until expiry
  Duration get timeUntilExpiry => expiresAt.difference(DateTime.now());

  @override
  String toString() {
    return 'Session(id: $id, created: $createdAt, expires: $expiresAt, data: ${data.keys.toList()})';
  }

  /// Create session from JSON
  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'],
      data: Map<String, dynamic>.from(json['data'] ?? {}),
      createdAt: DateTime.parse(json['created_at']),
      lastAccessedAt: DateTime.parse(json['last_accessed_at']),
      expiresAt: DateTime.parse(json['expires_at']),
    );
  }

  /// Convert session to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'data': data,
      'created_at': createdAt.toIso8601String(),
      'last_accessed_at': lastAccessedAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
    };
  }
}

/// Flash message storage for sessions
class FlashMessages {
  final Map<String, dynamic> _data;

  FlashMessages(this._data);

  /// Set flash message
  void set(String key, dynamic value) {
    _data['flash_$key'] = value;
  }

  /// Get flash message (removes it after reading)
  T? get<T>(String key) {
    final value = _data.remove('flash_$key');
    return value as T?;
  }

  /// Peek at flash message (doesn't remove it)
  T? peek<T>(String key) {
    return _data['flash_$key'] as T?;
  }

  /// Check if flash message exists
  bool has(String key) {
    return _data.containsKey('flash_$key');
  }

  /// Get all flash messages
  Map<String, dynamic> getAll() {
    final flash = <String, dynamic>{};
    final keysToRemove = <String>[];

    for (final entry in _data.entries) {
      if (entry.key.startsWith('flash_')) {
        final key = entry.key.substring(6); // Remove 'flash_' prefix
        flash[key] = entry.value;
        keysToRemove.add(entry.key);
      }
    }

    // Remove flash messages after reading
    for (final key in keysToRemove) {
      _data.remove(key);
    }

    return flash;
  }

  /// Clear all flash messages
  void clear() {
    _data.removeWhere((key, value) => key.startsWith('flash_'));
  }

  /// Keep flash message for next request
  void keep(String key) {
    final value = _data['flash_$key'];
    if (value != null) {
      _data['flash_keep_$key'] = value;
    }
  }

  /// Process kept flash messages
  void processKept() {
    final keptMessages = <String, dynamic>{};

    for (final entry in _data.entries) {
      if (entry.key.startsWith('flash_keep_')) {
        final key = entry.key.substring(11); // Remove 'flash_keep_' prefix
        keptMessages['flash_$key'] = entry.value;
      }
    }

    // Remove kept messages and add them back as regular flash messages
    _data.removeWhere((key, value) => key.startsWith('flash_keep_'));
    _data.addAll(keptMessages);
  }
}
