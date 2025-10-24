import 'dart:io';
import 'package:path/path.dart' as path;
import '../exceptions/template_exception.dart';

/// Loads partial templates from the filesystem with .html.dt extension.
///
/// The PartialLoader searches for partial files starting from the current
/// template's directory and recursively searching subdirectories.
///
/// ## Search Strategy:
/// 1. Start from the current template's directory
/// 2. Search for `partialName.html.dt` in current directory
/// 3. Recursively search subdirectories
/// 4. Throw TemplateException if partial not found
///
/// ## Example:
/// ```dart
/// final loader = PartialLoader('/app/templates');
///
/// // Template: /app/templates/users/show.html.dt
/// // Partial: {{> _todo}}
/// // Searches: /app/templates/users/_todo.html.dt
/// //          /app/templates/users/components/_todo.html.dt
/// //          etc.
///
/// final content = loader.loadPartial('_todo', '/app/templates/users');
/// ```
class PartialLoader {
  final String baseDirectory;
  final Map<String, String> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const String _extension = '.html.dt';

  /// Create a new PartialLoader with the specified base directory.
  ///
  /// [baseDirectory] is the root directory where templates are stored.
  PartialLoader(this.baseDirectory) {
    if (!Directory(baseDirectory).existsSync()) {
      throw ArgumentError('Base directory does not exist: $baseDirectory');
    }
  }

  /// Load a partial template content by name.
  ///
  /// [partialName] is the name of the partial (without extension).
  /// [currentDir] is the directory of the current template being rendered.
  ///
  /// Returns the content of the partial template.
  /// Throws [TemplateException] if the partial is not found.
  String loadPartial(String partialName, String currentDir) {
    final cacheKey = '$currentDir/$partialName';

    // Find the partial file first to check timestamp
    final partialPath = _findPartialFile(partialName, currentDir);

    if (partialPath == null) {
      throw TemplateException.parsing(
        'Partial not found: $partialName$_extension in $currentDir or subdirectories',
      );
    }

    try {
      final file = File(partialPath);
      final lastModified = file.lastModifiedSync();

      // Check if cached content is still valid
      if (_cache.containsKey(cacheKey) &&
          _cacheTimestamps.containsKey(cacheKey) &&
          !lastModified.isAfter(_cacheTimestamps[cacheKey]!)) {
        return _cache[cacheKey]!;
      }

      final content = file.readAsStringSync();

      // Cache the content with timestamp
      _cache[cacheKey] = content;
      _cacheTimestamps[cacheKey] = lastModified;

      return content;
    } catch (e) {
      throw TemplateException.parsing(
        'Failed to read partial $partialName: $e',
        cause: e,
      );
    }
  }

  /// Find a partial file by searching current directory and subdirectories.
  ///
  /// [partialName] is the name of the partial to find.
  /// [searchDir] is the directory to start searching from.
  ///
  /// Returns the full path to the partial file, or null if not found.
  String? _findPartialFile(String partialName, String searchDir) {
    final fileName = '$partialName$_extension';

    // Ensure search directory is within base directory
    final normalizedSearchDir = path.normalize(searchDir);
    final normalizedBaseDir = path.normalize(baseDirectory);

    if (!normalizedSearchDir.startsWith(normalizedBaseDir)) {
      return null;
    }

    // If partial name contains path separators, handle it as a relative path
    if (partialName.contains('/') || partialName.contains(path.separator)) {
      // Try relative to base directory first
      final basePartialPath =
          path.join(baseDirectory, '$partialName$_extension');
      if (File(basePartialPath).existsSync()) {
        return basePartialPath;
      }

      // Try relative to current search directory
      final currentPartialPath =
          path.join(searchDir, '$partialName$_extension');
      if (File(currentPartialPath).existsSync()) {
        return currentPartialPath;
      }

      return null;
    }

    // Search current directory first
    final currentDirPath = path.join(searchDir, fileName);
    if (File(currentDirPath).existsSync()) {
      return currentDirPath;
    }

    // Recursively search subdirectories
    try {
      final directory = Directory(searchDir);
      if (!directory.existsSync()) {
        return null;
      }

      final subdirectories = directory
          .listSync()
          .whereType<Directory>()
          .where((dir) =>
              !path.basename(dir.path).startsWith('.')) // Skip hidden dirs
          .toList();

      for (final subdir in subdirectories) {
        final result = _findPartialFile(partialName, subdir.path);
        if (result != null) {
          return result;
        }
      }
    } catch (e) {
      // Continue searching if directory access fails
    }

    return null;
  }

  /// Check if a partial exists.
  ///
  /// [partialName] is the name of the partial to check.
  /// [currentDir] is the directory of the current template.
  ///
  /// Returns true if the partial exists, false otherwise.
  bool partialExists(String partialName, String currentDir) {
    return _findPartialFile(partialName, currentDir) != null;
  }

  /// Get the full path to a partial if it exists.
  ///
  /// [partialName] is the name of the partial.
  /// [currentDir] is the directory of the current template.
  ///
  /// Returns the full path to the partial, or null if not found.
  String? getPartialPath(String partialName, String currentDir) {
    return _findPartialFile(partialName, currentDir);
  }

  /// Clear the partial cache.
  ///
  /// This is useful during development when partial files are modified.
  void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }

  /// Get cache statistics.
  ///
  /// Returns a map with cache information for debugging purposes.
  Map<String, dynamic> getCacheStats() {
    return {
      'cached_partials': _cache.length,
      'cached_items': _cache.keys.toList(),
    };
  }

  /// List all partial files in a directory and its subdirectories.
  ///
  /// [searchDir] is the directory to search in.
  ///
  /// Returns a list of partial file paths relative to the search directory.
  List<String> listPartials(String searchDir) {
    final partials = <String>[];

    try {
      final directory = Directory(searchDir);
      if (!directory.existsSync()) {
        return partials;
      }

      _collectPartials(directory, searchDir, partials);
    } catch (e) {
      // Return empty list if directory access fails
    }

    return partials;
  }

  /// Recursively collect partial files from a directory.
  void _collectPartials(Directory dir, String baseDir, List<String> partials) {
    try {
      for (final entity in dir.listSync()) {
        if (entity is File && entity.path.endsWith(_extension)) {
          final relativePath = path.relative(entity.path, from: baseDir);
          final partialName = path.basenameWithoutExtension(relativePath);
          partials.add(partialName);
        } else if (entity is Directory &&
            !path.basename(entity.path).startsWith('.')) {
          _collectPartials(entity, baseDir, partials);
        }
      }
    } catch (e) {
      // Continue if directory access fails
    }
  }
}
