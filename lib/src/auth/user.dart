import 'dart:math';
import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../orm/model.dart';
import '../orm/database_connection.dart';
import '../core/logger.dart';

/// User model with comprehensive authentication features
///
/// Provides authentication functionality including:
/// - Secure password hashing with bcrypt
/// - Email confirmation workflow
/// - Password reset functionality
/// - Remember me tokens
/// - Account lockout protection
/// - Failed login attempt tracking
///
/// ## Usage
///
/// ```dart
/// // Create a new user
/// final user = User();
/// user['email'] = 'user@example.com';
/// user['password'] = 'secure_password';
/// await user.save();
///
/// // Authenticate user
/// final authenticatedUser = await User.authenticate('user@example.com', 'secure_password');
///
/// // Send confirmation email
/// await user.sendConfirmationEmail();
///
/// // Reset password
/// await user.sendPasswordResetEmail();
/// ```
class User extends DModel {
  static final ScopedLogger _logger = DLogger.scoped('USER');

  static String get tableName => 'users';

  // Authentication configuration
  static const int maxFailedAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 30);
  static const Duration confirmationTokenExpiry = Duration(hours: 24);
  static const Duration resetTokenExpiry = Duration(hours: 2);
  static const Duration rememberTokenExpiry = Duration(days: 30);

  // Password validation configuration
  static const int minPasswordLength = 8;
  static const bool requireUppercase = true;
  static const bool requireLowercase = true;
  static const bool requireNumbers = true;
  static const bool requireSpecialChars = true;

  /// Set password with automatic hashing
  set password(String password) {
    final validationErrors = validatePassword(password);
    if (validationErrors.isNotEmpty) {
      throw ArgumentError(
          'Password validation failed: ${validationErrors.join(', ')}');
    }
    setAttribute('password_digest', _hashPassword(password));
  }

  /// Get user's email
  String? get email => getAttribute<String>('email');

  /// Get user's full name
  String get fullName {
    final firstName = getAttribute<String>('first_name') ?? '';
    final lastName = getAttribute<String>('last_name') ?? '';
    return '$firstName $lastName'.trim();
  }

  /// Check if user's email is confirmed
  bool get isEmailConfirmed =>
      getAttribute<String>('email_confirmed_at') != null;

  /// Check if user account is active
  bool get isActive => getAttribute<bool>('active') == true;

  /// Check if account is locked due to failed login attempts
  bool get isAccountLocked {
    final lockedAtStr = getAttribute<String>('locked_at');
    if (lockedAtStr == null) return false;

    final lockedAt = DateTime.parse(lockedAtStr);
    return DateTime.now().difference(lockedAt) < lockoutDuration;
  }

  /// Get number of failed login attempts
  int get failedAttempts => getAttribute<int>('failed_attempts') ?? 0;

  /// Authenticate user with email and password
  static Future<User?> authenticate(String email, String password) async {
    final user = await DModel.findBy<User>(
        'email = @email', {'email': email.toLowerCase()});

    if (user == null) {
      _logger
          .warning('Authentication failed: user not found for email: $email');
      return null;
    }

    // Check if account is locked
    if (user.isAccountLocked) {
      _logger.warning('Authentication failed: account locked for user: $email');
      return null;
    }

    // Check if account is active
    if (!user.isActive) {
      _logger
          .warning('Authentication failed: account inactive for user: $email');
      return null;
    }

    // Verify password
    if (!user.verifyPassword(password)) {
      await user._incrementFailedAttempts();
      _logger
          .warning('Authentication failed: invalid password for user: $email');
      return null;
    }

    // Reset failed attempts on successful login
    await user._resetFailedAttempts();

    _logger.info('User authenticated successfully: $email');
    return user;
  }

  /// Verify password against stored hash
  bool verifyPassword(String password) {
    final hash = getAttribute<String>('password_digest');
    if (hash == null) return false;
    return BCrypt.checkpw(password, hash);
  }

  /// Hash password using bcrypt
  String _hashPassword(String password) {
    return BCrypt.hashpw(password, BCrypt.gensalt());
  }

  /// Validate password according to security requirements
  List<String> validatePassword(String password) {
    final errors = <String>[];

    if (password.length < minPasswordLength) {
      errors
          .add('Password must be at least $minPasswordLength characters long');
    }

    if (requireUppercase && !password.contains(RegExp(r'[A-Z]'))) {
      errors.add('Password must contain at least one uppercase letter');
    }

    if (requireLowercase && !password.contains(RegExp(r'[a-z]'))) {
      errors.add('Password must contain at least one lowercase letter');
    }

    if (requireNumbers && !password.contains(RegExp(r'[0-9]'))) {
      errors.add('Password must contain at least one number');
    }

    if (requireSpecialChars &&
        !password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      errors.add('Password must contain at least one special character');
    }

    return errors;
  }

  /// Send email confirmation
  Future<void> sendConfirmationEmail() async {
    if (isEmailConfirmed) {
      _logger.warning('Email already confirmed for user: ${email}');
      return;
    }

    setAttribute('confirmation_token', _generateSecureToken());
    setAttribute('confirmation_sent_at', DateTime.now().toIso8601String());
    await save();

    // TODO: Integrate with email service
    _logger.info('Confirmation email would be sent to: $email');
    _logger.info('Confirmation token: ${getAttribute('confirmation_token')}');
  }

  /// Confirm email with token
  Future<bool> confirmEmail(String token) async {
    if (getAttribute<String>('confirmation_token') != token) {
      _logger.warning('Invalid confirmation token for user: $email');
      return false;
    }

    // Check token expiry
    final sentAt = getAttribute<String>('confirmation_sent_at');
    if (sentAt != null) {
      final sentDateTime = DateTime.parse(sentAt);
      if (DateTime.now().difference(sentDateTime) > confirmationTokenExpiry) {
        _logger.warning('Confirmation token expired for user: $email');
        return false;
      }
    }

    setAttribute('email_confirmed_at', DateTime.now().toIso8601String());
    setAttribute('confirmation_token', null);
    setAttribute('confirmation_sent_at', null);

    final success = await save();
    if (success) {
      _logger.info('Email confirmed for user: $email');
    }

    return success;
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail() async {
    setAttribute('reset_password_token', _generateSecureToken());
    setAttribute('reset_password_sent_at', DateTime.now().toIso8601String());
    await save();

    // TODO: Integrate with email service
    _logger.info('Password reset email would be sent to: $email');
    _logger.info('Reset token: ${getAttribute('reset_password_token')}');
  }

  /// Reset password with token
  Future<bool> resetPassword(String token, String newPassword) async {
    if (getAttribute<String>('reset_password_token') != token) {
      _logger.warning('Invalid reset token for user: $email');
      return false;
    }

    // Check token expiry
    final sentAt = getAttribute<String>('reset_password_sent_at');
    if (sentAt != null) {
      final sentDateTime = DateTime.parse(sentAt);
      if (DateTime.now().difference(sentDateTime) > resetTokenExpiry) {
        _logger.warning('Reset token expired for user: $email');
        return false;
      }
    }

    // Validate new password
    final validationErrors = validatePassword(newPassword);
    if (validationErrors.isNotEmpty) {
      _logger.warning(
          'Password reset failed - validation errors: ${validationErrors.join(', ')}');
      return false;
    }

    // Update password and clear reset tokens
    setAttribute('password_digest', _hashPassword(newPassword));
    setAttribute('reset_password_token', null);
    setAttribute('reset_password_sent_at', null);

    // Reset failed attempts and unlock account
    await _resetFailedAttempts();

    final success = await save();
    if (success) {
      _logger.info('Password reset successfully for user: $email');
    }

    return success;
  }

  /// Generate remember me token
  Future<String?> generateRememberToken(
      {String? userAgent, String? ipAddress}) async {
    final token = _generateSecureToken();
    final expiresAt = DateTime.now().add(rememberTokenExpiry);

    try {
      await DatabaseConnection.defaultConnection.execute('''
        INSERT INTO remember_tokens (user_id, token, expires_at, user_agent, ip_address, created_at, updated_at)
        VALUES (@user_id, @token, @expires_at, @user_agent, @ip_address, @created_at, @updated_at)
      ''', {
        'user_id': getAttribute('id'),
        'token': token,
        'expires_at': expiresAt.toIso8601String(),
        'user_agent': userAgent,
        'ip_address': ipAddress,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      _logger.info('Remember token generated for user: $email');
      return token;
    } catch (e) {
      _logger.error('Failed to generate remember token: $e');
      return null;
    }
  }

  /// Authenticate user with remember token
  static Future<User?> authenticateWithRememberToken(String token) async {
    try {
      final result = await DatabaseConnection.defaultConnection.queryOne('''
        SELECT u.*, rt.last_used_at
        FROM users u
        JOIN remember_tokens rt ON u.id = rt.user_id
        WHERE rt.token = @token AND rt.expires_at > @now
      ''', {
        'token': token,
        'now': DateTime.now().toIso8601String(),
      });

      if (result == null) {
        _logger.warning('Invalid or expired remember token');
        return null;
      }

      final user = User();
      user.loadAttributes(result);

      // Update last used timestamp
      await DatabaseConnection.defaultConnection.execute('''
        UPDATE remember_tokens
        SET last_used_at = @now, updated_at = @now
        WHERE token = @token
      ''', {
        'token': token,
        'now': DateTime.now().toIso8601String(),
      });

      _logger.info('User authenticated with remember token: ${user.email}');
      return user;
    } catch (e) {
      _logger.error('Failed to authenticate with remember token: $e');
      return null;
    }
  }

  /// Revoke remember token
  Future<void> revokeRememberToken(String token) async {
    try {
      await DatabaseConnection.defaultConnection.execute('''
        DELETE FROM remember_tokens
        WHERE user_id = @user_id AND token = @token
      ''', {
        'user_id': getAttribute('id'),
        'token': token,
      });

      _logger.info('Remember token revoked for user: $email');
    } catch (e) {
      _logger.error('Failed to revoke remember token: $e');
    }
  }

  /// Revoke all remember tokens for this user
  Future<void> revokeAllRememberTokens() async {
    try {
      await DatabaseConnection.defaultConnection.execute('''
        DELETE FROM remember_tokens WHERE user_id = @user_id
      ''', {'user_id': getAttribute('id')});

      _logger.info('All remember tokens revoked for user: $email');
    } catch (e) {
      _logger.error('Failed to revoke all remember tokens: $e');
    }
  }

  /// Increment failed login attempts
  Future<void> _incrementFailedAttempts() async {
    final attempts = failedAttempts + 1;
    setAttribute('failed_attempts', attempts);

    if (attempts >= maxFailedAttempts) {
      setAttribute('locked_at', DateTime.now().toIso8601String());
      setAttribute('unlock_token', _generateSecureToken());
      _logger.warning(
          'Account locked for user: $email after $attempts failed attempts');
    }

    await save();
  }

  /// Reset failed login attempts
  Future<void> _resetFailedAttempts() async {
    setAttribute('failed_attempts', 0);
    setAttribute('locked_at', null);
    setAttribute('unlock_token', null);
    await save();
  }

  /// Unlock account with token
  Future<bool> unlockAccount(String token) async {
    if (getAttribute<String>('unlock_token') != token) {
      _logger.warning('Invalid unlock token for user: $email');
      return false;
    }

    await _resetFailedAttempts();
    _logger.info('Account unlocked for user: $email');
    return true;
  }

  /// Generate secure random token
  String _generateSecureToken({int length = 32}) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Override save to handle email normalization
  @override
  Future<bool> save() async {
    // Normalize email to lowercase
    final currentEmail = getAttribute<String>('email');
    if (currentEmail != null) {
      setAttribute('email', currentEmail.toLowerCase());
    }

    // Set created_at and updated_at
    final now = DateTime.now().toIso8601String();
    if (!hasAttribute('id') || getAttribute('id') == null) {
      setAttribute('created_at', now);
    }
    setAttribute('updated_at', now);

    return await super.save();
  }

  /// Create a new user with validation
  static Future<User?> create(Map<String, dynamic> attributes) async {
    final user = User();

    // Set attributes
    attributes.forEach((key, value) {
      if (key == 'password') {
        user.password = value;
      } else {
        user.setAttribute(key, value);
      }
    });

    // Validate required fields
    if (user.getAttribute<String>('email') == null ||
        user.getAttribute<String>('email')!.isEmpty) {
      throw ArgumentError('Email is required');
    }

    if (user.getAttribute<String>('password_digest') == null) {
      throw ArgumentError('Password is required');
    }

    // Check if email already exists
    final existingUser = await DModel.findBy<User>(
        'email = @email', {'email': user.getAttribute('email')});
    if (existingUser != null) {
      throw ArgumentError('Email already exists');
    }

    final success = await user.save();
    if (success) {
      _logger.info('User created successfully: ${user.email}');
      return user;
    }

    return null;
  }

  /// Find user by email
  static Future<User?> findByEmail(String email) async {
    return await DModel.findBy<User>(
        'email = @email', {'email': email.toLowerCase()});
  }

  /// Find user by attribute map (helper method)
  static Future<User?> findBy(Map<String, dynamic> attributes) async {
    final conditions = <String>[];
    final params = <String, dynamic>{};

    attributes.forEach((key, value) {
      conditions.add('$key = @$key');
      params[key] = value;
    });

    return await DModel.findBy<User>(conditions.join(' AND '), params);
  }

  /// Clean up expired tokens (should be run periodically)
  static Future<void> cleanupExpiredTokens() async {
    try {
      final now = DateTime.now().toIso8601String();

      final result = await DatabaseConnection.defaultConnection.execute('''
        DELETE FROM remember_tokens WHERE expires_at < @now
      ''', {'now': now});

      _logger.info('Cleaned up ${result} expired remember tokens');
    } catch (e) {
      _logger.error('Failed to cleanup expired tokens: $e');
    }
  }
}
