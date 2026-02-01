import 'dart:convert';
import 'dart:math';

/// Supported activity types.
enum FitnessActivity {
  hike('Hike', '🥾'),
  run('Run', '🏃'),
  walk('Walk', '🚶'),
  bike('Bike', '🚴'),
  ski('Ski', '⛷️'),
  swim('Swim', '🏊'),
  kayak('Kayak', '🛶'),
  other('Other', '📍');

  final String label;
  final String emoji;
  const FitnessActivity(this.label, this.emoji);
}

/// A single GPS waypoint during an activity.
class HikeWaypoint {
  final double latitude;
  final double longitude;
  final double altitude; // meters
  final double speed; // m/s
  final double heading; // degrees
  final double accuracy; // meters
  final DateTime timestamp;

  const HikeWaypoint({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.speed,
    required this.heading,
    required this.accuracy,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'lat': latitude,
    'lon': longitude,
    'alt': altitude,
    'spd': speed,
    'hdg': heading,
    'acc': accuracy,
    'ts': timestamp.toIso8601String(),
  };

  factory HikeWaypoint.fromJson(Map<String, dynamic> json) => HikeWaypoint(
    latitude: (json['lat'] as num).toDouble(),
    longitude: (json['lon'] as num).toDouble(),
    altitude: (json['alt'] as num?)?.toDouble() ?? 0,
    speed: (json['spd'] as num?)?.toDouble() ?? 0,
    heading: (json['hdg'] as num?)?.toDouble() ?? 0,
    accuracy: (json['acc'] as num?)?.toDouble() ?? 0,
    timestamp: DateTime.parse(json['ts'] as String),
  );
}

/// A complete activity track with waypoints and metadata.
class HikeTrack {
  final String id;
  final String name;
  final FitnessActivity activityType;
  final DateTime startTime;
  DateTime? endTime;
  final List<HikeWaypoint> waypoints;
  String? gpxPath; // Path to exported GPX file

  HikeTrack({
    required this.id,
    required this.name,
    this.activityType = FitnessActivity.hike,
    required this.startTime,
    this.endTime,
    this.gpxPath,
    List<HikeWaypoint>? waypoints,
  }) : waypoints = waypoints ?? [];

  /// Duration of the hike.
  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  /// Total distance in meters using Haversine formula.
  double get totalDistanceMeters {
    if (waypoints.length < 2) return 0;
    double total = 0;
    for (int i = 1; i < waypoints.length; i++) {
      total += _haversine(
        waypoints[i - 1].latitude, waypoints[i - 1].longitude,
        waypoints[i].latitude, waypoints[i].longitude,
      );
    }
    return total;
  }

  /// Total distance in km.
  double get totalDistanceKm => totalDistanceMeters / 1000;

  /// Average speed in km/h.
  double get avgSpeedKmh {
    final hrs = duration.inSeconds / 3600;
    if (hrs <= 0) return 0;
    return totalDistanceKm / hrs;
  }

  /// Elevation gain (only counting uphill segments).
  double get elevationGain {
    if (waypoints.length < 2) return 0;
    double gain = 0;
    for (int i = 1; i < waypoints.length; i++) {
      final diff = waypoints[i].altitude - waypoints[i - 1].altitude;
      if (diff > 0) gain += diff;
    }
    return gain;
  }

  /// Elevation loss (only counting downhill segments).
  double get elevationLoss {
    if (waypoints.length < 2) return 0;
    double loss = 0;
    for (int i = 1; i < waypoints.length; i++) {
      final diff = waypoints[i - 1].altitude - waypoints[i].altitude;
      if (diff > 0) loss += diff;
    }
    return loss;
  }

  /// Current altitude (last waypoint).
  double get currentAltitude =>
      waypoints.isNotEmpty ? waypoints.last.altitude : 0;

  /// Min altitude.
  double get minAltitude => waypoints.isEmpty
      ? 0
      : waypoints.map((w) => w.altitude).reduce(min);

  /// Max altitude.
  double get maxAltitude => waypoints.isEmpty
      ? 0
      : waypoints.map((w) => w.altitude).reduce(max);

  /// Haversine distance between two lat/lon points in meters.
  static double haversineDistance(double lat1, double lon1, double lat2, double lon2) =>
      _haversine(lat1, lon1, lat2, lon2);

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // Earth radius in meters
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _toRad(double deg) => deg * pi / 180;

  /// Export as GPX XML string.
  String toGpx() {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<gpx version="1.1" creator="ClawReach"');
    buf.writeln('  xmlns="http://www.topografix.com/GPX/1/1">');
    buf.writeln('  <metadata>');
    buf.writeln('    <name>${_xmlEscape(name)}</name>');
    buf.writeln('    <time>${startTime.toUtc().toIso8601String()}</time>');
    buf.writeln('  </metadata>');
    buf.writeln('  <trk>');
    buf.writeln('    <name>${_xmlEscape(name)}</name>');
    buf.writeln('    <trkseg>');
    for (final wp in waypoints) {
      buf.writeln('      <trkpt lat="${wp.latitude}" lon="${wp.longitude}">');
      buf.writeln('        <ele>${wp.altitude.toStringAsFixed(1)}</ele>');
      buf.writeln('        <time>${wp.timestamp.toUtc().toIso8601String()}</time>');
      if (wp.speed > 0) {
        buf.writeln('        <extensions><speed>${wp.speed.toStringAsFixed(2)}</speed></extensions>');
      }
      buf.writeln('      </trkpt>');
    }
    buf.writeln('    </trkseg>');
    buf.writeln('  </trk>');
    buf.writeln('</gpx>');
    return buf.toString();
  }

  static String _xmlEscape(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  /// Serialize to JSON for local storage.
  String toJsonString() => jsonEncode({
    'id': id,
    'name': name,
    'activityType': activityType.name,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'gpxPath': gpxPath,
    'waypoints': waypoints.map((w) => w.toJson()).toList(),
  });

  /// Deserialize from JSON.
  factory HikeTrack.fromJsonString(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    return HikeTrack(
      id: data['id'] as String,
      name: data['name'] as String,
      activityType: FitnessActivity.values.firstWhere(
        (t) => t.name == (data['activityType'] as String? ?? 'hike'),
        orElse: () => FitnessActivity.hike,
      ),
      startTime: DateTime.parse(data['startTime'] as String),
      endTime: data['endTime'] != null
          ? DateTime.parse(data['endTime'] as String)
          : null,
      gpxPath: data['gpxPath'] as String?,
      waypoints: (data['waypoints'] as List)
          .map((w) => HikeWaypoint.fromJson(w as Map<String, dynamic>))
          .toList(),
    );
  }
}
