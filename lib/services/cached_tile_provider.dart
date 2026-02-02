import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/// Tile provider that caches tiles to local storage.
/// Previously viewed map areas work offline.
class CachedTileProvider extends TileProvider {
  static String? _cacheDirPath;

  /// Initialize the cache directory (call once at startup).
  static Future<void> init() async {
    final dir = await getApplicationCacheDirectory();
    _cacheDirPath = '${dir.path}/map_tiles';
    await Directory(_cacheDirPath!).create(recursive: true);
    debugPrint('🗺️ Tile cache: $_cacheDirPath');
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return CachedTileImage(url: url, cacheDir: _cacheDirPath);
  }
}

/// ImageProvider that checks local cache before network.
/// On failure, throws instead of returning transparent pixel so Flutter
/// retries on next paint rather than caching a blank tile forever.
class CachedTileImage extends ImageProvider<CachedTileImage> {
  final String url;
  final String? cacheDir;

  CachedTileImage({required this.url, this.cacheDir});

  @override
  Future<CachedTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(CachedTileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadTile(key, decode),
      scale: 1.0,
      informationCollector: () => [
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<CachedTileImage>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _loadTile(CachedTileImage key, ImageDecoderCallback decode) async {
    final cacheFile = _getCacheFile(key.url);

    // Try cache first
    if (cacheFile != null && await cacheFile.exists()) {
      try {
        final bytes = await cacheFile.readAsBytes();
        if (bytes.isNotEmpty) {
          final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
          return decode(buffer);
        }
      } catch (e) {
        debugPrint('🗺️ Cache read error for ${key.url}: $e');
        // Cache corrupt, fall through to network
      }
    }

    // Fetch from network with retry
    Exception? lastError;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http.get(
          Uri.parse(key.url),
          headers: {'User-Agent': 'ClawReach/1.0 (org.clawreach.app)'},
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          // Save to cache (fire-and-forget)
          if (cacheFile != null) {
            cacheFile.parent.create(recursive: true).then((_) {
              cacheFile.writeAsBytes(response.bodyBytes);
            }).catchError((_) {});
          }

          final buffer = await ui.ImmutableBuffer.fromUint8List(response.bodyBytes);
          return decode(buffer);
        }
        lastError = Exception('HTTP ${response.statusCode}');
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }

    // DON'T return transparent pixel — evict from Flutter's image cache
    // so the tile will be retried on next paint cycle.
    PaintingBinding.instance.imageCache.evict(this);
    debugPrint('🗺️ Tile load failed (will retry): ${key.url} — $lastError');
    throw lastError ?? Exception('Tile load failed');
  }

  File? _getCacheFile(String url) {
    if (cacheDir == null) return null;
    // URL -> cache path: /z/x/y.png
    final uri = Uri.parse(url);
    final segments = uri.pathSegments; // e.g. [z, x, y.png]
    if (segments.length < 3) return null;
    return File('$cacheDir/${segments.join('/')}');
  }

  @override
  bool operator ==(Object other) =>
      other is CachedTileImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
