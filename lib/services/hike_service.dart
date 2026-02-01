import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/hike_track.dart';

/// Manages GPS hike tracking with local storage.
class HikeService extends ChangeNotifier {
  static const _uuid = Uuid();

  HikeTrack? _activeTrack;
  StreamSubscription<Position>? _positionSub;
  Timer? _durationTimer;
  bool _tracking = false;
  String? _error;
  Position? _lastPosition;

  HikeTrack? get activeTrack => _activeTrack;
  bool get isTracking => _tracking;
  String? get error => _error;
  Position? get lastPosition => _lastPosition;

  /// Start tracking a new hike.
  Future<bool> startTracking({String? name}) async {
    _error = null;

    // Check permissions
    final permission = await _ensurePermission();
    if (!permission) return false;

    // Create track
    final now = DateTime.now();
    final trackName = name ?? 'Hike ${now.month}/${now.day} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    _activeTrack = HikeTrack(
      id: _uuid.v4(),
      name: trackName,
      startTime: now,
    );

    // Start GPS stream
    _tracking = true;
    notifyListeners();

    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // meters — only log if moved 5m+
      intervalDuration: const Duration(seconds: 10),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'ClawReach — Tracking Hike',
        notificationText: 'GPS logging active',
        notificationChannelName: 'Hike Tracking',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      _onPosition,
      onError: (e) {
        debugPrint('❌ GPS error: $e');
        _error = 'GPS error: $e';
        notifyListeners();
      },
    );

    // Update UI timer (for duration display)
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });

    // Save initial state
    await _saveTrack();
    debugPrint('🥾 Hike tracking started: ${_activeTrack!.name}');
    return true;
  }

  /// Stop tracking and save final track.
  Future<HikeTrack?> stopTracking() async {
    if (_activeTrack == null) return null;

    _tracking = false;
    _activeTrack!.endTime = DateTime.now();

    await _positionSub?.cancel();
    _positionSub = null;
    _durationTimer?.cancel();
    _durationTimer = null;

    await _saveTrack();
    final track = _activeTrack!;
    debugPrint('🥾 Hike stopped: ${track.waypoints.length} waypoints, '
        '${track.totalDistanceKm.toStringAsFixed(2)} km');

    notifyListeners();
    return track;
  }

  /// Discard active tracking without saving.
  void discardTracking() {
    _tracking = false;
    _positionSub?.cancel();
    _positionSub = null;
    _durationTimer?.cancel();
    _durationTimer = null;
    _activeTrack = null;
    notifyListeners();
  }

  void _onPosition(Position pos) {
    if (_activeTrack == null) return;

    // Skip very inaccurate readings
    if (pos.accuracy > 50) {
      debugPrint('📍 Skipped inaccurate reading (${pos.accuracy.toStringAsFixed(0)}m)');
      return;
    }

    _lastPosition = pos;

    final waypoint = HikeWaypoint(
      latitude: pos.latitude,
      longitude: pos.longitude,
      altitude: pos.altitude,
      speed: pos.speed,
      heading: pos.heading,
      accuracy: pos.accuracy,
      timestamp: DateTime.now(),
    );

    _activeTrack!.waypoints.add(waypoint);

    // Auto-save every 30 waypoints
    if (_activeTrack!.waypoints.length % 30 == 0) {
      _saveTrack();
      debugPrint('📍 Auto-saved: ${_activeTrack!.waypoints.length} waypoints');
    }

    notifyListeners();
  }

  Future<bool> _ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _error = 'Location services are disabled. Please enable GPS.';
      notifyListeners();
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _error = 'Location permission denied';
        notifyListeners();
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _error = 'Location permission permanently denied. Enable in Settings.';
      notifyListeners();
      return false;
    }

    return true;
  }

  /// Save track to local storage.
  Future<void> _saveTrack() async {
    if (_activeTrack == null) return;
    try {
      final dir = await _hikesDir();
      final file = File('${dir.path}/${_activeTrack!.id}.json');
      await file.writeAsString(_activeTrack!.toJsonString());
    } catch (e) {
      debugPrint('❌ Failed to save track: $e');
    }
  }

  /// Export track as GPX file and return the file path.
  Future<String?> exportGpx(HikeTrack track) async {
    try {
      final dir = await _hikesDir();
      final safeName = track.name.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
      final file = File('${dir.path}/${safeName}.gpx');
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
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/hikes');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }
}
