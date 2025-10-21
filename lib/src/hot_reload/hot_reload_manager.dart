import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../config/hot_reload_config.dart';
import '../core/logger.dart';
import 'debounced_file_watcher.dart';

/// Manages hot reload functionality for D_Server development
///
/// This class coordinates file watching, keyboard input handling,
/// and server process management to provide a smooth development experience.
class HotReloadManager {
  Process? _serverProcess;
  DebouncedFileWatcher? _fileWatcher;
  StreamSubscription? _stdinSubscription;
  final HotReloadConfig _config;
  bool _isErrorState = false;
  bool _isShuttingDown = false;
  static final ScopedLogger _logger = DLogger.scoped('HOT_RELOAD');

  /// Create a new hot reload manager
  HotReloadManager(this._config);

  /// Start the hot reload manager
  ///
  /// This will start the server, set up file watching, and keyboard listeners
  Future<void> start() async {
    _logger.info('🚀 Development server started with hot reload');
    _logger.info('📝 Press "r" to manually reload, "q" to quit');

    await _startServer();
    _setupFileWatcher();
    _setupKeyboardListener();

    // Handle process signals gracefully
    ProcessSignal.sigint.watch().listen((signal) async {
      if (!_isShuttingDown) {
        _logger.info('Received interrupt signal');
        await _cleanup();
        exit(0);
      }
    });

    // Keep the process alive
    await _keepAlive();
  }

  /// Start the server process
  Future<void> _startServer() async {
    if (_isShuttingDown) return;

    final stopwatch = Stopwatch()..start();

    try {
      // Kill existing process if running
      if (_serverProcess != null) {
        _serverProcess!.kill();
        await _serverProcess!.exitCode.timeout(
          Duration(seconds: 5),
          onTimeout: () {
            _logger.warning('Server process did not exit gracefully');
            return -1;
          },
        );
      }

      _logger.debug('Starting server process...');
      _serverProcess = await Process.start(
        'dart',
        ['run', 'lib/main.dart'],
        mode: ProcessStartMode.inheritStdio,
      );

      // Listen for server crashes
      _serverProcess!.exitCode.then((exitCode) {
        if (!_isShuttingDown && exitCode != 0) {
          _logger.error('❌ Server crashed with exit code: $exitCode');
          _logger.info('🔧 Fix the error and press "r" to restart');
          _isErrorState = true;
        }
      });

      _isErrorState = false; // Clear error state on successful start
      stopwatch.stop();
      _logger.info('✅ Server started in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      stopwatch.stop();
      _logger.error('❌ Failed to start server: $e');
      _logger.info('🔧 Fix the error and press "r" to restart');
      _isErrorState = true;
    }
  }

  /// Restart the server process
  Future<void> _restartServer([String? changedFile]) async {
    if (_isShuttingDown) return;

    final stopwatch = Stopwatch()..start();

    if (changedFile != null) {
      _logger.info('🔄 Reloading due to changes in: $changedFile');
    } else {
      _logger.info('🔄 Manual reload triggered');
    }

    await _startServer();

    if (!_isErrorState) {
      stopwatch.stop();
      _logger.info('✅ Server restarted in ${stopwatch.elapsedMilliseconds}ms');
    }
  }

  /// Set up file watching with debouncing
  void _setupFileWatcher() {
    if (!_config.enabled) {
      _logger.debug('Hot reload disabled in config');
      return;
    }

    try {
      _fileWatcher = DebouncedFileWatcher(
        debounceDelay: Duration(milliseconds: _config.debounceDelay),
        onReload: (changedFile) {
          // Only auto-restart if not in error state
          if (!_isErrorState && !_isShuttingDown) {
            _restartServer(changedFile);
          } else if (_isErrorState) {
            _logger
                .debug('Ignoring file change due to error state: $changedFile');
          }
        },
        watchDirectories: _config.watchDirectories,
        ignorePatterns: _config.ignorePatterns,
      );

      _fileWatcher!.start();
    } catch (e) {
      _logger.error('Failed to setup file watcher: $e');
    }
  }

  /// Set up keyboard input listeners
  void _setupKeyboardListener() {
    try {
      // Try to set raw mode for immediate key detection
      stdin.echoMode = false;
      stdin.lineMode = false;

      _stdinSubscription = stdin.listen(
        (List<int> data) {
          if (_isShuttingDown) return;

          final input = String.fromCharCodes(data).toLowerCase().trim();
          _handleKeyboardInput(input);
        },
        onError: (error) {
          _logger.debug('Keyboard input error: $error');
        },
      );

      _logger.debug('Keyboard listener setup successful');
    } catch (e) {
      _logger.warning('Could not setup raw keyboard input: $e');
      _logger
          .info('You can still use "r" + Enter to reload, "q" + Enter to quit');

      // Fallback to line mode
      try {
        stdin.echoMode = true;
        stdin.lineMode = true;
        _stdinSubscription = stdin
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (String line) {
            if (_isShuttingDown) return;
            _handleKeyboardInput(line.toLowerCase().trim());
          },
          onError: (error) {
            _logger.debug('Stdin error: $error');
          },
        );
      } catch (fallbackError) {
        _logger.error('Failed to setup keyboard input: $fallbackError');
      }
    }
  }

  /// Handle keyboard input commands
  void _handleKeyboardInput(String input) {
    switch (input) {
      case 'r':
        // Manual restart works even in error state
        _restartServer();
        break;
      case 'q':
      case 'quit':
      case 'exit':
        _logger.info('👋 Shutting down...');
        _cleanup().then((_) => exit(0));
        break;
      case 'h':
      case 'help':
        _showHelp();
        break;
      case 's':
      case 'status':
        _showStatus();
        break;
      default:
        if (input.isNotEmpty &&
            !input.contains('\n') &&
            !input.contains('\r')) {
          _logger.debug('Unknown command: $input (try "h" for help)');
        }
        break;
    }
  }

  /// Show help message
  void _showHelp() {
    _logger.info('Available commands:');
    _logger.info('  r - Restart server');
    _logger.info('  q - Quit');
    _logger.info('  s - Show status');
    _logger.info('  h - Show this help');
  }

  /// Show current status
  void _showStatus() {
    final serverStatus = _serverProcess != null ? 'running' : 'stopped';
    final errorStatus = _isErrorState ? ' (error state)' : '';
    final watcherStatus =
        _fileWatcher?.isActive == true ? 'active' : 'inactive';

    _logger.info('Status:');
    _logger.info('  Server: $serverStatus$errorStatus');
    _logger.info('  File watcher: $watcherStatus');
    _logger.info('  Watched dirs: ${_config.watchDirectories.join(', ')}');
    _logger.info('  Debounce delay: ${_config.debounceDelay}ms');
  }

  /// Keep the main process alive
  Future<void> _keepAlive() async {
    // Create a completer that never completes to keep the process alive
    final completer = Completer<void>();

    // Set up a periodic timer to prevent the process from being garbage collected
    Timer.periodic(Duration(seconds: 30), (timer) {
      if (_isShuttingDown) {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });

    return completer.future;
  }

  /// Clean up resources and shut down gracefully
  Future<void> _cleanup() async {
    if (_isShuttingDown) return;
    _isShuttingDown = true;

    _logger.debug('Starting cleanup...');

    // Stop file watcher
    try {
      _fileWatcher?.stop();
    } catch (e) {
      _logger.debug('Error stopping file watcher: $e');
    }

    // Cancel keyboard listener
    try {
      await _stdinSubscription?.cancel();
    } catch (e) {
      _logger.debug('Error canceling stdin subscription: $e');
    }

    // Kill server process
    try {
      if (_serverProcess != null) {
        _logger.debug('Killing server process...');
        _serverProcess!.kill();
        await _serverProcess!.exitCode.timeout(
          Duration(seconds: 3),
          onTimeout: () {
            _logger
                .debug('Server process did not exit gracefully, force killing');
            _serverProcess!.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      }
    } catch (e) {
      _logger.debug('Error killing server process: $e');
    }

    // Restore terminal settings
    try {
      stdin.echoMode = true;
      stdin.lineMode = true;
    } catch (e) {
      _logger.debug('Error restoring terminal settings: $e');
    }

    _logger.debug('Cleanup completed');
  }

  /// Get current manager status for debugging
  Map<String, dynamic> getStatus() {
    return {
      'server_running': _serverProcess != null,
      'error_state': _isErrorState,
      'shutting_down': _isShuttingDown,
      'file_watcher_active': _fileWatcher?.isActive ?? false,
      'config': _config.toMap(),
    };
  }
}
