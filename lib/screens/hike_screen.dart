import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/hike_track.dart';
import '../services/hike_service.dart';

/// Fitness activity tracking screen with GPS logging and live stats.
class HikeScreen extends StatelessWidget {
  const HikeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hike = context.watch<HikeService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(hike.isTracking
            ? '${hike.activeTrack?.activityType.emoji ?? "📍"} Tracking'
            : '🏋️ Fitness Tracker'),
        actions: [
          if (!hike.isTracking)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Past activities',
              onPressed: () => _showHistory(context),
            ),
        ],
      ),
      body: hike.isTracking ? const _TrackingView() : const _IdleView(),
    );
  }

  void _showHistory(BuildContext context) async {
    final hike = context.read<HikeService>();
    final tracks = await hike.listTracks();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => _HistorySheet(tracks: tracks),
    );
  }
}

/// Activity grid — tap to start tracking immediately.
class _IdleView extends StatelessWidget {
  const _IdleView();

  @override
  Widget build(BuildContext context) {
    final hike = context.watch<HikeService>();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (hike.error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(hike.error!,
                        style: TextStyle(color: Colors.red[300], fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],

          // Activity grid
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: FitnessActivity.values.map((type) {
                return _ActivityCard(
                  type: type,
                  onTap: () => hike.startTracking(type: type),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 8),
          Text(
            'GPS tracks every 10 seconds • Works offline',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Tappable activity card that starts tracking.
class _ActivityCard extends StatelessWidget {
  final FitnessActivity type;
  final VoidCallback onTap;

  const _ActivityCard({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(type.emoji, style: const TextStyle(fontSize: 36)),
              const SizedBox(height: 8),
              Text(type.label, style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600,
              )),
            ],
          ),
        ),
      ),
    );
  }
}

/// Live tracking view with stats.
class _TrackingView extends StatelessWidget {
  const _TrackingView();

  @override
  Widget build(BuildContext context) {
    final hike = context.watch<HikeService>();
    final track = hike.activeTrack;
    if (track == null) return const SizedBox();

    final duration = track.duration;
    final durationStr =
        '${duration.inHours}:${(duration.inMinutes % 60).toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

    return Column(
      children: [
        // Duration header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24),
          color: Colors.green.withValues(alpha: 0.1),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(
                        color: Colors.green.withValues(alpha: 0.5),
                        blurRadius: 8,
                      )],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${track.activityType.emoji} ${track.activityType.label.toUpperCase()}',
                    style: TextStyle(
                      color: Colors.green[400], fontSize: 12,
                      fontWeight: FontWeight.bold, letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                durationStr,
                style: const TextStyle(
                  fontSize: 48, fontWeight: FontWeight.w300,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),

        // Stats grid
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(children: [
                  _StatCard(
                    icon: Icons.straighten, label: 'Distance',
                    value: track.totalDistanceKm < 1
                        ? '${track.totalDistanceMeters.toStringAsFixed(0)} m'
                        : '${track.totalDistanceKm.toStringAsFixed(2)} km',
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    icon: Icons.speed, label: 'Avg Speed',
                    value: '${track.avgSpeedKmh.toStringAsFixed(1)} km/h',
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  _StatCard(
                    icon: Icons.terrain, label: 'Altitude',
                    value: '${track.currentAltitude.toStringAsFixed(0)} m',
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    icon: Icons.trending_up, label: 'Elev. Gain',
                    value: '${track.elevationGain.toStringAsFixed(0)} m',
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  _StatCard(
                    icon: Icons.location_on, label: 'Waypoints',
                    value: '${track.waypoints.length}',
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    icon: Icons.gps_fixed, label: 'GPS Accuracy',
                    value: hike.lastPosition != null
                        ? '${hike.lastPosition!.accuracy.toStringAsFixed(0)} m'
                        : '—',
                  ),
                ]),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _confirmStop(context),
                    icon: const Icon(Icons.stop, size: 28),
                    label: Text('Stop ${track.activityType.label}',
                        style: const TextStyle(fontSize: 18)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.red[700],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _confirmStop(BuildContext context) {
    final track = context.read<HikeService>().activeTrack;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stop ${track?.activityType.label ?? "Activity"}?'),
        content: const Text('GPS tracking will stop and your GPX file will be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Going'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _stopAndShowSummary(context);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }

  void _stopAndShowSummary(BuildContext context) async {
    final hike = context.read<HikeService>();
    final track = await hike.stopTracking();
    if (track == null || !context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SummarySheet(track: track),
    );
  }
}

/// Post-activity summary with auto-exported GPX.
class _SummarySheet extends StatelessWidget {
  final HikeTrack track;
  const _SummarySheet({required this.track});

  @override
  Widget build(BuildContext context) {
    final duration = track.duration;
    final durationStr = '${duration.inHours}h ${duration.inMinutes % 60}m';

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(24),
        children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          )),
          const SizedBox(height: 20),
          Text(
            '${track.activityType.emoji} ${track.activityType.label} Complete!',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(track.name,
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          _summaryRow('Duration', durationStr),
          _summaryRow('Distance', '${track.totalDistanceKm.toStringAsFixed(2)} km'),
          _summaryRow('Avg Speed', '${track.avgSpeedKmh.toStringAsFixed(1)} km/h'),
          _summaryRow('Elevation Gain', '↑ ${track.elevationGain.toStringAsFixed(0)} m'),
          _summaryRow('Elevation Loss', '↓ ${track.elevationLoss.toStringAsFixed(0)} m'),
          _summaryRow('Max Altitude', '${track.maxAltitude.toStringAsFixed(0)} m'),
          _summaryRow('Waypoints', '${track.waypoints.length}'),

          const SizedBox(height: 24),

          // GPX file status
          if (track.gpxPath != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('GPX file saved',
                      style: TextStyle(color: Colors.green))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _shareGpx(context),
              icon: const Icon(Icons.share),
              label: const Text('Share GPX File'),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text('No GPX — no waypoints recorded',
                      style: TextStyle(color: Colors.orange))),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            label: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[400])),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      ],
    ),
  );

  void _shareGpx(BuildContext context) async {
    if (track.gpxPath == null) return;
    try {
      await Share.shareXFiles([XFile(track.gpxPath!)]);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      }
    }
  }
}

/// Past activities list.
class _HistorySheet extends StatelessWidget {
  final List<HikeTrack> tracks;
  const _HistorySheet({required this.tracks});

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: Text('No activities yet',
            style: TextStyle(color: Colors.grey))),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tracks.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Past Activities',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          );
        }
        final track = tracks[i - 1];
        final duration = track.duration;
        return Card(
          child: ListTile(
            leading: Text(track.activityType.emoji,
                style: const TextStyle(fontSize: 28)),
            title: Text(track.name),
            subtitle: Text(
              '${track.totalDistanceKm.toStringAsFixed(2)} km • '
              '${duration.inHours}h ${duration.inMinutes % 60}m • '
              '${track.waypoints.length} pts',
            ),
            trailing: track.gpxPath != null
                ? IconButton(
                    icon: const Icon(Icons.share, size: 20),
                    onPressed: () async {
                      try {
                        await Share.shareXFiles([XFile(track.gpxPath!)]);
                      } catch (_) {}
                    },
                  )
                : null,
          ),
        );
      },
    );
  }
}

/// Single stat card widget.
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ]),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
