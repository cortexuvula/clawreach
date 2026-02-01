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
      } catch (_) {
        // Cache corrupt, fall through to network
      }
    }

    // Fetch from network
    try {
      final response = await http.get(
        Uri.parse(key.url),
        headers: {'User-Agent': 'ClawReach/1.0 (com.clawreach.clawreach)'},
      ).timeout(const Duration(seconds: 10));

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
    } catch (_) {
      // Network failed — if cache exists but was corrupt, try once more
    }

    // Return a 1x1 transparent pixel as fallback
    final fallback = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG header
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x62, 0x00, 0x00, 0x00, 0x02,
      0x00, 0x01, 0xE5, 0x27, 0xDE, 0xFC, 0x00, 0x00,
      0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
      0x60, 0x82,
    ]);
    final buffer = await ui.ImmutableBuffer.fromUint8List(fallback);
    return decode(buffer);
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
