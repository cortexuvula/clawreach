import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/hike_track.dart';
import '../services/cached_tile_provider.dart';

/// Map widget showing a GPS activity track.
class ActivityMap extends StatefulWidget {
  final List<HikeWaypoint> waypoints;
  final bool isLive; // If true, auto-follows latest position
  final bool interactive; // If false, map ignores gestures (for previews)

  const ActivityMap({
    super.key,
    required this.waypoints,
    this.isLive = false,
    this.interactive = true,
  });

  @override
  State<ActivityMap> createState() => _ActivityMapState();
}

class _ActivityMapState extends State<ActivityMap> {
  final MapController _mapController = MapController();
  int _lastWaypointCount = 0;
  bool _hasFittedBounds = false;

  @override
  void didUpdateWidget(ActivityMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-pan to latest point when live tracking
    if (widget.isLive && widget.waypoints.length > _lastWaypointCount) {
      _lastWaypointCount = widget.waypoints.length;
      final last = widget.waypoints.last;
      try {
        _mapController.move(
          LatLng(last.latitude, last.longitude),
          _mapController.camera.zoom,
        );
      } catch (_) {}
    }
  }

  void _fitBounds(LatLngBounds bounds) {
    if (_hasFittedBounds) return;
    _hasFittedBounds = true;
    // Use post-frame callback to ensure the widget has its final layout size
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(30),
          ),
        );
      } catch (e) {
        debugPrint('🗺️ fitCamera error: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.waypoints.isEmpty) {
      return Container(
        color: Colors.grey[900],
        child: const Center(
          child: Text('Waiting for GPS...', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final points = widget.waypoints
        .map((w) => LatLng(w.latitude, w.longitude))
        .toList();

    // Calculate bounds for the track
    LatLngBounds? bounds;
    if (!widget.isLive && points.length > 1) {
      bounds = LatLngBounds.fromPoints(points);
    }

    // For non-live maps, start centered on the track
    final center = widget.isLive
        ? points.last
        : LatLng(
            points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length,
            points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 15.0,
          interactionOptions: InteractionOptions(
            flags: widget.interactive
                ? InteractiveFlag.all
                : InteractiveFlag.none,
          ),
          onMapReady: () {
            // Fit bounds after map is fully ready + laid out
            if (bounds != null) {
              _fitBounds(bounds!);
            }
          },
        ),
        children: [
          // OpenStreetMap tiles with offline caching
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'org.clawreach.app',
            tileProvider: CachedTileProvider(),
          ),

          // Track polyline
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                strokeWidth: 4.0,
                color: Colors.deepOrange,
              ),
            ],
          ),

          // Start marker
          MarkerLayer(
            markers: [
              // Start point (green)
              Marker(
                point: points.first,
                width: 24, height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                    )],
                  ),
                ),
              ),
              // Current/end point (orange or red)
              if (points.length > 1)
                Marker(
                  point: points.last,
                  width: 24, height: 24,
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.isLive ? Colors.deepOrange : Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 4,
                      )],
                    ),
                    child: widget.isLive
                        ? const Icon(Icons.navigation, size: 12, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
