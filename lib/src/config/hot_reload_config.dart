/// Configuration for hot reload functionality in D_Server framework
class HotReloadConfig {
  /// Whether hot reload is enabled
  final bool enabled;

  /// Debounce delay in milliseconds to prevent rapid restarts
  final int debounceDelay;

  /// List of directories to watch for changes
  final List<String> watchDirectories;

  /// List of patterns to ignore when watching files
  final List<String> ignorePatterns;

  /// Create a new hot reload configuration
  HotReloadConfig({
    this.enabled = true,
    this.debounceDelay = 500,
    this.watchDirectories = const ['lib', 'views'],
    this.ignorePatterns = const ['**/*.tmp', '**/.*', '**/.git/**'],
  });

  /// Create configuration from YAML data
  factory HotReloadConfig.fromYaml(Map<String, dynamic>? yaml) {
    if (yaml == null) return HotReloadConfig();

    return HotReloadConfig(
      enabled: yaml['enabled'] ?? true,
      debounceDelay: yaml['debounce_delay'] ?? 500,
      watchDirectories:
          _parseStringList(yaml['watch_directories']) ?? const ['lib', 'views'],
      ignorePatterns: _parseStringList(yaml['ignore_patterns']) ??
          const ['**/*.tmp', '**/.*', '**/.git/**'],
    );
  }

  /// Parse a YAML value as a list of strings
  static List<String>? _parseStringList(dynamic value) {
    if (value == null) return null;

    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }

    if (value is String) {
      return [value];
    }

    return null;
  }

  /// Convert to a map for serialization
  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'debounce_delay': debounceDelay,
      'watch_directories': watchDirectories,
      'ignore_patterns': ignorePatterns,
    };
  }

  @override
  String toString() {
    return 'HotReloadConfig(enabled: $enabled, debounceDelay: $debounceDelay, '
        'watchDirectories: $watchDirectories, ignorePatterns: $ignorePatterns)';
  }

  /// Create a copy with updated values
  HotReloadConfig copyWith({
    bool? enabled,
    int? debounceDelay,
    List<String>? watchDirectories,
    List<String>? ignorePatterns,
  }) {
    return HotReloadConfig(
      enabled: enabled ?? this.enabled,
      debounceDelay: debounceDelay ?? this.debounceDelay,
      watchDirectories: watchDirectories ?? this.watchDirectories,
      ignorePatterns: ignorePatterns ?? this.ignorePatterns,
    );
  }
}
