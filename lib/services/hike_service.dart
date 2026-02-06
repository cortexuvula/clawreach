import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/hike_track.dart';
import 'node_connection_service.dart';

/// Manages GPS fitness tracking with local storage and gateway sync.
class HikeService extends ChangeNotifier {
  static const _uuid = Uuid();
  NodeConnectionService? _nodeConnection;

  /// Wire up the node connection for syncing completed activities to gateway.
  void setNodeConnection(NodeConnectionService nodeConn) {
    _nodeConnection = nodeConn;
    // Listen for connection changes to flush pending syncs
    _nodeConnection!.addListener(_onConnectionChanged);
  }

  void _onConnectionChanged() {
    if (_nodeConnection?.isConnected == true) {
      _flushPendingSync();
    }
  }

  HikeTrack? _activeTrack;
  StreamSubscription<Position>? _positionSub;
  Timer? _durationTimer;
  Timer? _fallbackTimer;
  bool _tracking = false;
  String? _error;
  Position? _lastPosition;

  HikeTrack? get activeTrack => _activeTrack;
  bool get isTracking => _tracking;
  String? get error => _error;
  Position? get lastPosition => _lastPosition;

  /// Start tracking an activity.
  Future<bool> startTracking({String? name, FitnessActivity type = FitnessActivity.hike}) async {
    _error = null;

    // Check permissions
    final permission = await _ensurePermission();
    if (!permission) return false;

    // Initialize track
    _activeTrack = HikeTrack(
      id: _uuid.v4(),
      name: name ?? 'Activity ${DateTime.now().toString().substring(0, 16)}',
      activityType: type,
      startTime: DateTime.now(),
      waypoints: [],
    );
    _tracking = true;
    notifyListeners();

    // Start position stream
    _startPositionStream();

    // Start duration timer (updates UI every second)
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners(); // Duration is computed, no need to update track
    });

    // Fallback timer: auto-stop if no GPS fix for 5 minutes
    _fallbackTimer = Timer(const Duration(minutes: 5), () {
      if (_activeTrack!.waypoints.isEmpty) {
        debugPrint('⏱️ Auto-stopping track (no GPS fix after 5 min)');
        stopTracking();
      }
    });

    debugPrint('🎯 Tracking started: ${_activeTrack!.name}');
    return true;
  }

  void _startPositionStream() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 5, // Update every 5 meters
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        _lastPosition = position;
        if (_tracking && _activeTrack != null) {
          // Cancel fallback timer once we get GPS
          _fallbackTimer?.cancel();
          _fallbackTimer = null;

          // Convert Position to HikeWaypoint
          final waypoint = HikeWaypoint(
            latitude: position.latitude,
            longitude: position.longitude,
            altitude: position.altitude,
            speed: position.speed,
            heading: position.heading,
            accuracy: position.accuracy,
            timestamp: DateTime.now(),
          );

          _activeTrack = _activeTrack!.copyWith(
            waypoints: [..._activeTrack!.waypoints, waypoint],
          );
          _saveTrack(); // Auto-save
          notifyListeners();
        }
      },
      onError: (e) {
        debugPrint('❌ GPS error: $e');
        _error = 'GPS unavailable';
        notifyListeners();
      },
    );
  }

  /// Pause tracking (keeps current track, stops GPS updates).
  void pauseTracking() {
    if (!_tracking) return;
    _tracking = false;
    _positionSub?.cancel();
    _positionSub = null;
    _durationTimer?.cancel();
    _durationTimer = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    notifyListeners();
    debugPrint('⏸️ Tracking paused');
  }

  /// Resume tracking after pause.
  Future<void> resumeTracking() async {
    if (_tracking || _activeTrack == null) return;
    _tracking = true;
    _startPositionStream();

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
    notifyListeners();
    debugPrint('▶️ Tracking resumed');
  }

  /// Stop tracking and finalize the current track.
  Future<HikeTrack?> stopTracking() async {
    if (_activeTrack == null) return null;

    _tracking = false;
    _positionSub?.cancel();
    _positionSub = null;
    _durationTimer?.cancel();
    _durationTimer = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;

    // Finalize with endTime
    _activeTrack = _activeTrack!.copyWith(
      endTime: DateTime.now(),
    );
    await _saveTrack();

    // Push summary to gateway
    _syncToGateway(_activeTrack!);

    final completedTrack = _activeTrack!;
    debugPrint('🏁 Track saved: ${completedTrack.name} (${completedTrack.waypoints.length} points)');
    _activeTrack = null;
    notifyListeners();
    
    return completedTrack;
  }

  /// Discard the current track without saving.
  void discardTrack() {
    _tracking = false;
    _positionSub?.cancel();
    _positionSub = null;
    _durationTimer?.cancel();
    _durationTimer = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _activeTrack = null;
    notifyListeners();
    debugPrint('🗑️ Track discarded');
  }

  Future<void> _saveTrack() async {
    if (_activeTrack == null) return;
    
    if (kIsWeb) {
      // On web: save to SharedPreferences (in-memory only, lost on page reload)
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('active_track', _activeTrack!.toJsonString());
      } catch (e) {
        debugPrint('❌ Failed to save track (web): $e');
      }
    } else {
      // On mobile/desktop: save to file
      try {
        final dir = await _hikesDir();
        final file = File('${dir.path}/${_activeTrack!.id}.json');
        await file.writeAsString(_activeTrack!.toJsonString());
      } catch (e) {
        debugPrint('❌ Failed to save track: $e');
      }
    }
  }

  /// Export track as GPX file and return the file path.
  Future<String?> exportGpx(HikeTrack track) async {
    if (kIsWeb) {
      debugPrint('⚠️ GPX export not supported on web');
      return null;
    }

    try {
      final dir = await _hikesDir();
      final safeName = track.name.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
      final file = File('${dir.path}/$safeName.gpx');
      await file.writeAsString(track.toGpx());
      debugPrint('📁 GPX exported: ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('❌ GPX export failed: $e');
      return null;
    }
  }

  /// List saved hike tracks.
  Future<List<HikeTrack>> listTracks() async {
    if (kIsWeb) {
      // On web: tracks aren't persisted between sessions
      return [];
    }

    try {
      final dir = await _hikesDir();
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
      final tracks = <HikeTrack>[];
      for (final file in files) {
        try {
          tracks.add(HikeTrack.fromJsonString(await file.readAsString()));
        } catch (_) {}
      }
      tracks.sort((a, b) => b.startTime.compareTo(a.startTime));
      return tracks;
    } catch (_) {
      return [];
    }
  }

  /// Load a specific track by ID.
  Future<HikeTrack?> loadTrack(String id) async {
    if (kIsWeb) return null;

    try {
      final dir = await _hikesDir();
      final file = File('${dir.path}/$id.json');
      if (await file.exists()) {
        return HikeTrack.fromJsonString(await file.readAsString());
      }
    } catch (_) {}
    return null;
  }

  Future<Directory> _hikesDir() async {
    if (kIsWeb) {
      throw UnsupportedError('File storage not available on web');
    }
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/hikes');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Permission handling.
  Future<bool> _ensurePermission() async {
    if (kIsWeb) {
      // Web uses browser geolocation API (handled by geolocator)
      try {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          final requested = await Geolocator.requestPermission();
          if (requested == LocationPermission.denied ||
              requested == LocationPermission.deniedForever) {
            _error = 'Location permission denied';
            notifyListeners();
            return false;
          }
        }
        return true;
      } catch (e) {
        _error = 'Permission check failed: $e';
        notifyListeners();
        return false;
      }
    }

    // Mobile/Desktop: use permission_handler
    final status = await ph.Permission.locationWhenInUse.status;
    if (!status.isGranted) {
      final result = await ph.Permission.locationWhenInUse.request();
      if (!result.isGranted) {
        _error = 'Location permission denied';
        notifyListeners();
        return false;
      }
    }

    // Check if location services are enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _error = 'Location services disabled';
      notifyListeners();
      return false;
    }

    return true;
  }

  /// Push activity summary to gateway (if connected).
  Future<void> _syncToGateway(HikeTrack track) async {
    final summary = _buildSummary(track);

    if (_nodeConnection != null && _nodeConnection!.isConnected) {
      try {
        _nodeConnection!.sendNodeEvent('fitness-activity', summary);
        debugPrint('✅ Activity synced to gateway');
      } catch (e) {
        debugPrint('❌ Sync failed: $e');
        await _queuePendingSync(summary);
      }
    } else {
      await _queuePendingSync(summary);
    }
  }

  Map<String, dynamic> _buildSummary(HikeTrack track) {
    // Calculate max speed from waypoints
    final maxSpeed = track.waypoints.isEmpty
        ? 0.0
        : track.waypoints.map((w) => w.speed).reduce((a, b) => a > b ? a : b);

    // Calculate avg pace (min/km) from avg speed
    final avgPace = track.avgSpeedKmh > 0
        ? 60 / track.avgSpeedKmh
        : 0.0;

    return {
      'id': track.id,
      'name': track.name,
      'activity': track.activityType.name,
      'startTime': track.startTime.toIso8601String(),
      'endTime': track.endTime?.toIso8601String(),
      'duration': track.duration.inSeconds,
      'distance': track.totalDistanceMeters,
      'ascent': track.elevationGain,
      'descent': track.elevationLoss,
      'maxAltitude': track.maxAltitude,
      'maxSpeed': maxSpeed,
      'avgPace': avgPace,
      'points': track.waypoints.length,
    };
  }

  /// Save unsent summary to local queue file.
  Future<void> _queuePendingSync(Map<String, dynamic> summary) async {
    if (kIsWeb) {
      // On web: skip pending sync queue (no persistent storage)
      debugPrint('⚠️ Sync queue not available on web');
      return;
    }

    try {
      final dir = await _hikesDir();
      final file = File('${dir.path}/_pending_sync.jsonl');
      await file.writeAsString(
        '${jsonEncode(summary)}\n',
        mode: FileMode.append,
      );
    } catch (e) {
      debugPrint('❌ Failed to queue sync: $e');
    }
  }

  /// Flush pending syncs when connection is re-established.
  Future<void> _flushPendingSync() async {
    if (kIsWeb) return;
    if (_nodeConnection == null || !_nodeConnection!.isConnected) return;

    try {
      final dir = await _hikesDir();
      final file = File('${dir.path}/_pending_sync.jsonl');
      if (!await file.exists()) return;

      final lines = await file.readAsLines();
      if (lines.isEmpty) return;

      int sent = 0;
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final summary = jsonDecode(line) as Map<String, dynamic>;
          _nodeConnection!.sendNodeEvent('fitness-activity', summary);
          sent++;
        } catch (e) {
          debugPrint('❌ Failed to sync pending activity: $e');
        }
      }

      if (sent > 0) {
        await file.delete();
        debugPrint('✅ Flushed $sent pending activities');
      }
    } catch (e) {
      debugPrint('❌ Pending sync flush failed: $e');
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationTimer?.cancel();
    _fallbackTimer?.cancel();
    _nodeConnection?.removeListener(_onConnectionChanged);
    super.dispose();
  }
}
