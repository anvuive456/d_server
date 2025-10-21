import 'dart:async';
import 'dart:io';
import 'package:watcher/watcher.dart';
import '../core/logger.dart';

/// A file watcher that debounces changes to prevent rapid fire events
///
/// This class monitors specified directories for file changes and triggers
/// a callback after a configurable delay. If multiple changes occur within
/// the delay period, only one callback is triggered.
class DebouncedFileWatcher {
  Timer? _debounceTimer;
  final Duration _debounceDelay;
  final Function(String changedFile) _onReload;
  final List<String> _watchDirectories;
  final List<String> _ignorePatterns;
  final List<StreamSubscription> _subscriptions = [];
  static final ScopedLogger _logger = DLogger.scoped('HOT_RELOAD');

  /// Create a new debounced file watcher
  ///
  /// [debounceDelay] - Time to wait before triggering callback
  /// [onReload] - Callback function when files change
  /// [watchDirectories] - List of directories to monitor
  /// [ignorePatterns] - List of patterns to ignore
  DebouncedFileWatcher({
    required Duration debounceDelay,
    required Function(String changedFile) onReload,
    required List<String> watchDirectories,
    required List<String> ignorePatterns,
  })  : _debounceDelay = debounceDelay,
        _onReload = onReload,
        _watchDirectories = watchDirectories,
        _ignorePatterns = ignorePatterns;

  /// Start watching the configured directories
  Future<void> start() async {
    _logger.info('👀 Watching: ${_watchDirectories.join(', ')}');

    for (final dir in _watchDirectories) {
      final directory = Directory(dir);
      if (directory.existsSync()) {
        try {
          final watcher = DirectoryWatcher(dir);
          final subscription = watcher.events.listen(
            _onFileChanged,
            onError: (error) {
              _logger.warning('File watcher error for $dir: $error');
            },
          );
          _subscriptions.add(subscription);
          _logger.debug('Started watching directory: $dir');
        } catch (e) {
          _logger.warning('Failed to watch directory $dir: $e');
        }
      } else {
        _logger.debug('Directory does not exist, skipping: $dir');
      }
    }

    if (_subscriptions.isEmpty) {
      _logger.warning('No directories are being watched');
    }
  }

  /// Handle file change events with debouncing
  void _onFileChanged(WatchEvent event) {
    final path = event.path;

    // Skip ignored patterns
    if (_shouldIgnore(path)) {
      _logger.debug('Ignoring file change: $path');
      return;
    }

    // Only trigger on actual file changes, not directory changes
    if (event.type == ChangeType.MODIFY || event.type == ChangeType.ADD) {
      _logger.debug('File change detected: $path (${event.type})');

      // Cancel existing timer and start a new one
      _debounceTimer?.cancel();
      _debounceTimer = Timer(_debounceDelay, () {
        _logger.info('📁 File changed: $path');
        _onReload(path);
      });
    }
  }

  /// Check if a file path should be ignored based on ignore patterns
  bool _shouldIgnore(String path) {
    final normalizedPath = path.replaceAll('\\', '/');

    for (final pattern in _ignorePatterns) {
      if (_matchesPattern(normalizedPath, pattern)) {
        return true;
      }
    }

    return false;
  }

  /// Simple pattern matching for ignore patterns
  bool _matchesPattern(String path, String pattern) {
    // Handle exact matches
    if (path == pattern) return true;

    // Handle wildcard patterns
    if (pattern.contains('*')) {
      // Convert glob pattern to regex
      String regexPattern = pattern
          .replaceAll('**/', '.*/')
          .replaceAll('**', '.*')
          .replaceAll('*', '[^/]*')
          .replaceAll('.', r'\.');

      try {
        final regex = RegExp(regexPattern);
        return regex.hasMatch(path);
      } catch (e) {
        _logger.debug('Invalid ignore pattern: $pattern');
        return false;
      }
    }

    // Handle directory patterns
    if (pattern.endsWith('/')) {
      return path.startsWith(pattern) || path.contains('/$pattern');
    }

    // Handle file extension patterns
    if (pattern.startsWith('*.')) {
      return path.endsWith(pattern.substring(1));
    }

    // Handle substring matches
    return path.contains(pattern);
  }

  /// Stop watching all directories and clean up resources
  void stop() {
    _logger.debug('Stopping file watcher');

    _debounceTimer?.cancel();
    _debounceTimer = null;

    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    _logger.debug('File watcher stopped');
  }

  /// Get the number of active directory watchers
  int get activeWatcherCount => _subscriptions.length;

  /// Check if the watcher is currently active
  bool get isActive => _subscriptions.isNotEmpty;
}
