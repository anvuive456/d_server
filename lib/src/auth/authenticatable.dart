import 'dart:convert';
import 'dart:math';
import 'package:shelf/shelf.dart';
import '../controllers/base_controller.dart';
import '../core/logger.dart';
import 'user.dart';
import 'authentication_middleware.dart' as auth_middleware;
import 'session_store.dart';

/// Authenticatable mixin for controllers
///
/// Provides authentication helpers for controllers:
/// - current_user
/// - authenticate_user!
/// - sign_in, sign_out
/// - flash messages
/// - redirect helpers
///
/// ## Usage
///
/// ```dart
/// class UsersController extends DController with Authenticatable {
///   Future<Response> show() async {
///     authenticateUser(); // Require authentication
///     final user = currentUser; // Get current user
///     return render('users/show', locals: {'user': user});
///   }
///
///   Future<Response> login() async {
///     if (request.method == 'POST') {
///       final email = body['email'];
///       final password = body['password'];
///       final user = await User.authenticate(email, password);
///
///       if (user != null) {
///         await signIn(user, rememberMe: body['remember_me'] == 'true');
///         setFlash('success', 'Welcome back!');
///         return redirectTo('/dashboard');
///       } else {
///         setFlash('error', 'Invalid email or password');
///         return redirectBack();
///       }
///     }
///
///     return render('auth/login');
///   }
/// }
/// ```
mixin Authenticatable on DController {
  static final ScopedLogger _logger = DLogger.scoped('AUTHENTICATABLE');

  /// Get current authenticated user
  User? get currentUser {
    return auth_middleware.AuthenticationHelpers.currentUser(request);
  }

  /// Check if user is authenticated
  bool get isAuthenticated {
    return auth_middleware.AuthenticationHelpers.isAuthenticated(request);
  }

  /// Get current session
  Session? get currentSession {
    return request.context['session'] as Session?;
  }

  /// Get flash messages
  FlashMessages get flashMessages {
    final session = this.currentSession;
    if (session == null) {
      return FlashMessages({});
    }
    return FlashMessages(session.data);
  }

  /// Require authentication (redirect to login if not authenticated)
  void authenticateUser() {
    if (!isAuthenticated) {
      _logger.info('Authentication required, redirecting to login');

      // Store the current URL for redirect after login
      final currentUrl = request.requestedUri.toString();
      flashMessages.set('redirect_after_login', currentUrl);

      throw DRedirectException('/login');
    }
  }

  /// Require authentication and return user (throw exception if not authenticated)
  User requireUser() {
    try {
      return auth_middleware.AuthenticationHelpers.requireAuthentication(
          request);
    } on auth_middleware.UnauthorizedException {
      authenticateUser(); // This will throw RedirectException
      throw StateError('This should never be reached');
    }
  }

  /// Sign in user
  Future<void> signIn(User user, {bool rememberMe = false}) async {
    try {
      await auth_middleware.AuthenticationHelpers.signIn(request, user,
          rememberMe: rememberMe);
      _logger.info('User signed in: ${user.email}');

      // Clear any existing failed login attempts flash messages
      flashMessages.clear();
    } catch (e) {
      _logger.error('Failed to sign in user: $e');
      flashMessages.set('error', 'An error occurred during sign in');
      rethrow;
    }
  }

  /// Sign out current user
  Future<void> signOut() async {
    final user = currentUser;
    if (user != null) {
      try {
        await auth_middleware.AuthenticationHelpers.signOut(request);
        _logger.info('User signed out: ${user.email}');
        flashMessages.set('notice', 'You have been signed out');
      } catch (e) {
        _logger.error('Failed to sign out user: $e');
        flashMessages.set('error', 'An error occurred during sign out');
      }
    }
  }

  /// Check if user has specific role or permission
  bool hasRole(String role) {
    final user = currentUser;
    if (user == null) return false;

    // Basic role checking - extend as needed
    final userRole = user.getAttribute<String>('role');
    return userRole == role;
  }

  /// Require specific role
  void requireRole(String role) {
    authenticateUser(); // Ensure user is authenticated first

    if (!hasRole(role)) {
      _logger.warning(
          'Access denied: user ${currentUser!.email} lacks role: $role');
      flashMessages.set('error', 'Access denied');
      throw DRedirectException('/dashboard'); // or appropriate page
    }
  }

  /// Check if current user can access resource (basic authorization)
  bool canAccess(dynamic resource) {
    final user = currentUser;
    if (user == null) return false;

    // Basic ownership checking - extend as needed
    if (resource is Map<String, dynamic> && resource.containsKey('user_id')) {
      return resource['user_id'] == user.getAttribute('id');
    }

    return true; // Default allow if no specific rules
  }

  /// Require access to resource
  void requireAccess(dynamic resource) {
    authenticateUser(); // Ensure user is authenticated first

    if (!canAccess(resource)) {
      _logger.warning(
          'Access denied: user ${currentUser!.email} cannot access resource');
      flashMessages.set('error', 'Access denied');
      throw DRedirectException('/');
    }
  }

  /// Redirect to login page
  Response redirectToLogin({String? message}) {
    if (message != null) {
      flashMessages.set('error', message);
    }
    return redirect('/login');
  }

  /// Redirect after successful login
  Response redirectAfterLogin() {
    final redirectUrl =
        flashMessages.get<String>('redirect_after_login') ?? '/';
    return redirect(redirectUrl);
  }

  /// Redirect back to previous page or fallback
  Response redirectBack({String fallback = '/'}) {
    final referer = request.headers['referer'];
    final redirectUrl = referer ?? fallback;
    return redirect(redirectUrl);
  }

  /// Store current URL for redirect after authentication
  void storeLocation() {
    final currentUrl = request.requestedUri.toString();
    flashMessages.set('redirect_after_login', currentUrl);
  }

  /// Handle authentication required scenarios
  Response handleAuthenticationRequired([String? message]) {
    storeLocation();
    return redirectToLogin(message: message ?? 'Please sign in to continue');
  }

  /// Handle authorization failure scenarios
  Response handleAuthorizationFailure([String? message]) {
    flashMessages.set('error', message ?? 'Access denied');
    return redirectBack(fallback: '/dashboard');
  }

  /// Before action: require authentication
  void beforeAuthenticate() {
    authenticateUser();
  }

  /// Before action: require specific role
  void beforeRequireRole(String role) {
    requireRole(role);
  }

  /// Before action: store current location
  void beforeStoreLocation() {
    storeLocation();
  }

  /// Helper to check if user is the owner of a resource
  bool isOwner(Map<String, dynamic> resource) {
    final user = currentUser;
    if (user == null) return false;

    return resource['user_id'] == user.getAttribute('id');
  }

  /// Helper to check if user is admin
  bool get isAdmin {
    return hasRole('admin') || hasRole('administrator');
  }

  /// Helper to check if user is moderator
  bool get isModerator {
    return hasRole('moderator') || isAdmin;
  }

  /// Get user's display name
  String get currentUserDisplayName {
    final user = currentUser;
    if (user == null) return 'Guest';

    final fullName = user.fullName;
    if (fullName.isNotEmpty) return fullName;

    return user.getAttribute('email') ?? 'User';
  }

  /// Check if password confirmation is required for sensitive actions
  bool requiresPasswordConfirmation() {
    final user = currentUser;
    if (user == null) return true;

    // Check if user has confirmed password recently (within last 15 minutes)
    final session = this.currentSession;
    if (session == null) return true;

    final confirmedAt = session.data['password_confirmed_at'] as String?;
    if (confirmedAt == null) return true;

    final confirmed = DateTime.parse(confirmedAt);
    final now = DateTime.now();

    return now.difference(confirmed) > Duration(minutes: 15);
  }

  /// Mark password as confirmed for sensitive actions
  void confirmPassword() {
    final session = this.currentSession;
    if (session != null) {
      session.data['password_confirmed_at'] = DateTime.now().toIso8601String();
    }
  }

  /// Clear password confirmation
  void clearPasswordConfirmation() {
    final session = this.currentSession;
    if (session != null) {
      session.data.remove('password_confirmed_at');
    }
  }

  /// Generate CSRF token for forms
  String get csrfToken {
    final session = this.currentSession;
    if (session == null) {
      throw StateError('No session available for CSRF token');
    }

    String? token = session.data['csrf_token'] as String?;
    if (token == null) {
      // Generate new CSRF token
      token = _generateCsrfToken();
      session.data['csrf_token'] = token;
    }

    return token;
  }

  /// Verify CSRF token
  bool verifyCsrfToken(String? token) {
    if (token == null) return false;

    final session = this.currentSession;
    if (session == null) return false;

    final sessionToken = session.data['csrf_token'] as String?;
    return sessionToken != null && sessionToken == token;
  }

  /// Require valid CSRF token
  Future<void> requireCsrfToken() async {
    final body = await parseBody();
    final token =
        body['csrf_token'] as String? ?? request.headers['x-csrf-token'];

    if (!verifyCsrfToken(token)) {
      _logger.warning('CSRF token verification failed');
      flashMessages.set('error', 'Security token verification failed');
      throw DRedirectException(request.requestedUri.path);
    }
  }

  /// Generate secure CSRF token
  String _generateCsrfToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

/// Exception for handling redirects in authentication flows
class DRedirectException implements Exception {
  final String location;
  final int statusCode;

  DRedirectException(this.location, {this.statusCode = 302});

  @override
  String toString() => 'RedirectException: $location';
}

/// Helper extension for cleaner syntax
extension AuthenticatableExtension on DController {
  /// Quick access to authentication mixin if present
  Authenticatable? get auth {
    return this is Authenticatable ? this as Authenticatable : null;
  }
}
