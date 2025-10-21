import 'dart:io';
import 'package:shelf/shelf.dart';
import '../core/logger.dart';
import '../orm/model.dart';
import 'user.dart';
import 'session_store.dart';

/// Authentication middleware for D_Server framework
///
/// Provides session-based authentication:
/// - Loads current user from session
/// - Handles remember me functionality
/// - Manages authentication state
/// - Provides user context to controllers
///
/// ## Usage
///
/// ```dart
/// final app = DApplication();
/// app.use(AuthenticationMiddleware());
/// ```
class AuthenticationMiddleware {
  static final ScopedLogger _logger = DLogger.scoped('AUTH_MIDDLEWARE');

  final SessionStore _sessionStore;
  final String _sessionCookieName;
  final String _rememberCookieName;
  final Duration _sessionTimeout;
  final bool _secureRequests;

  AuthenticationMiddleware({
    SessionStore? sessionStore,
    String sessionCookieName = 'd_server_session',
    String rememberCookieName = 'd_server_remember',
    Duration sessionTimeout = const Duration(hours: 24),
    bool secureRequests = false,
  })  : _sessionStore = sessionStore ?? MemorySessionStore(),
        _sessionCookieName = sessionCookieName,
        _rememberCookieName = rememberCookieName,
        _sessionTimeout = sessionTimeout,
        _secureRequests = secureRequests;

  /// Create middleware handler
  Middleware get handler => (Handler innerHandler) {
        return (Request request) async {
          // Load session and user
          final updatedRequest = await _loadUserFromSession(request);

          // Process request
          final response = await innerHandler(updatedRequest);

          // Save session changes
          return await _saveSession(updatedRequest, response);
        };
      };

  /// Load user from session or remember token
  Future<Request> _loadUserFromSession(Request request) async {
    try {
      User? user;
      String? sessionId;
      Session? session;

      // Try to get session from cookie
      final sessionCookie = _getCookie(request, _sessionCookieName);
      if (sessionCookie != null) {
        sessionId = sessionCookie;
        session = await _sessionStore.get(sessionId);

        if (session != null && !session.isExpired) {
          // Load user from session
          final userId = session.data['user_id'];
          if (userId != null) {
            user = await DModel.find<User>(userId);
            if (user != null) {
              session.touch(); // Update last accessed time
              _logger.debug('User loaded from session: ${user.email}');
            }
          }
        }
      }

      // If no user from session, try remember token
      if (user == null) {
        final rememberCookie = _getCookie(request, _rememberCookieName);
        if (rememberCookie != null) {
          user = await User.authenticateWithRememberToken(rememberCookie);
          if (user != null) {
            // Create new session for remembered user
            sessionId = await _createUserSession(user);
            _logger
                .info('User authenticated via remember token: ${user.email}');
          }
        }
      }

      // Create new session if needed
      if (sessionId == null) {
        sessionId = await _sessionStore.create();
        session = await _sessionStore.get(sessionId);
      }

      // Add authentication context to request
      final context = <String, dynamic>{
        'session_id': sessionId,
        'session': session,
        'current_user': user,
        'authenticated': user != null,
      };

      // Merge with existing context
      final updatedContext = Map<String, dynamic>.from(request.context)
        ..addAll(context);

      return request.change(context: updatedContext);
    } catch (e) {
      _logger.error('Error loading user from session: $e');

      // Return request with empty auth context on error
      final context = Map<String, dynamic>.from(request.context)
        ..addAll({
          'session_id': null,
          'session': null,
          'current_user': null,
          'authenticated': false,
        });

      return request.change(context: context);
    }
  }

  /// Save session changes to response
  Future<Response> _saveSession(Request request, Response response) async {
    try {
      final sessionId = request.context['session_id'] as String?;
      final session = request.context['session'] as Session?;

      if (sessionId == null || session == null) {
        return response;
      }

      // Save session data
      await _sessionStore.save(sessionId, session);

      // Set session cookie
      final sessionCookie = Cookie(_sessionCookieName, sessionId)
        ..httpOnly = true
        ..secure = _secureRequests
        ..maxAge = _sessionTimeout.inSeconds
        ..path = '/';

      final cookies = <String>[];

      // Preserve existing cookies
      final existingCookies = response.headers['set-cookie'];
      if (existingCookies != null) {
        // Handle both String and List<String> cases
        cookies.add(existingCookies.toString());
      }

      // Add session cookie
      cookies.add(sessionCookie.toString());

      // Add remember cookie if user is authenticated and remember_me is set
      final user = request.context['current_user'] as User?;
      final rememberMe = session.data['remember_me'] as bool? ?? false;

      if (user != null && rememberMe) {
        final rememberToken = await user.generateRememberToken(
          userAgent: request.headers['user-agent'],
          ipAddress: _getClientIP(request),
        );

        if (rememberToken != null) {
          final rememberCookie = Cookie(_rememberCookieName, rememberToken)
            ..httpOnly = true
            ..secure = _secureRequests
            ..maxAge = User.rememberTokenExpiry.inSeconds
            ..path = '/';

          cookies.add(rememberCookie.toString());
        }
      }

      // Return response with updated cookies
      final headers = Map<String, dynamic>.from(response.headers);
      headers['set-cookie'] = cookies;

      return response.change(headers: headers);
    } catch (e) {
      _logger.error('Error saving session: $e');
      return response;
    }
  }

  /// Create session for authenticated user
  Future<String> _createUserSession(User user) async {
    final sessionId = await _sessionStore.create();
    final session = await _sessionStore.get(sessionId);

    if (session != null) {
      session.data['user_id'] = user.getAttribute('id');
      session.data['user_email'] = user.email;
      session.data['authenticated_at'] = DateTime.now().toIso8601String();
      await _sessionStore.save(sessionId, session);
    }

    return sessionId;
  }

  /// Get cookie value from request
  String? _getCookie(Request request, String name) {
    final cookieHeader = request.headers['cookie'];
    if (cookieHeader == null) return null;

    final cookies = cookieHeader
        .split(';')
        .map((cookie) {
          final parts = cookie.trim().split('=');
          return parts.length == 2 ? MapEntry(parts[0], parts[1]) : null;
        })
        .where((entry) => entry != null)
        .cast<MapEntry<String, String>>();

    for (final cookie in cookies) {
      if (cookie.key == name) {
        return cookie.value;
      }
    }

    return null;
  }

  /// Get client IP address from request
  String? _getClientIP(Request request) {
    // Check for forwarded headers first (proxy/load balancer)
    var ip = request.headers['x-forwarded-for'];
    if (ip != null) {
      // X-Forwarded-For can contain multiple IPs, get the first one
      return ip.split(',').first.trim();
    }

    ip = request.headers['x-real-ip'];
    if (ip != null) return ip;

    // Fallback to connection remote address
    final context = request.context['shelf.io.connection_info'];
    if (context is HttpConnectionInfo) {
      return context.remoteAddress.address;
    }

    return null;
  }
}

/// Authentication helper methods for controllers
class AuthenticationHelpers {
  /// Sign in user
  static Future<void> signIn(Request request, User user,
      {bool rememberMe = false}) async {
    final session = request.context['session'] as Session?;
    if (session == null) {
      throw StateError('No session available');
    }

    session.data['user_id'] = user.getAttribute('id');
    session.data['user_email'] = user.email;
    session.data['authenticated_at'] = DateTime.now().toIso8601String();
    session.data['remember_me'] = rememberMe;

    // Update request context
    final context = Map<String, dynamic>.from(request.context);
    context['current_user'] = user;
    context['authenticated'] = true;
  }

  /// Sign out user
  static Future<void> signOut(Request request) async {
    final session = request.context['session'] as Session?;
    final user = request.context['current_user'] as User?;

    if (session != null) {
      // Clear user data from session
      session.data.remove('user_id');
      session.data.remove('user_email');
      session.data.remove('authenticated_at');
      session.data.remove('remember_me');
    }

    // Update request context
    final context = Map<String, dynamic>.from(request.context);
    context['current_user'] = null;
    context['authenticated'] = false;

    // Revoke remember tokens
    if (user != null) {
      await user.revokeAllRememberTokens();
    }
  }

  /// Get current authenticated user
  static User? currentUser(Request request) {
    return request.context['current_user'] as User?;
  }

  /// Check if user is authenticated
  static bool isAuthenticated(Request request) {
    return request.context['authenticated'] as bool? ?? false;
  }

  /// Require authentication (throws if not authenticated)
  static User requireAuthentication(Request request) {
    final user = currentUser(request);
    if (user == null) {
      throw UnauthorizedException('Authentication required');
    }
    return user;
  }
}

/// Exception thrown when authentication is required
class UnauthorizedException implements Exception {
  final String message;

  UnauthorizedException(this.message);

  @override
  String toString() => 'UnauthorizedException: $message';
}
