import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/hike_track.dart';
import '../services/hike_service.dart';
import 'package:share_plus/share_plus.dart';

/// Hike tracking screen with GPS logging and live stats.
class HikeScreen extends StatelessWidget {
  const HikeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hike = context.watch<HikeService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('🥾 Hike Tracker'),
        actions: [
          if (!hike.isTracking)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Past hikes',
              onPressed: () => _showHistory(context),
            ),
        ],
      ),
      body: hike.isTracking ? _TrackingView() : _IdleView(),
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

/// View shown when not tracking — start button.
class _IdleView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hike = context.watch<HikeService>();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🏔️', style: TextStyle(fontSize: 72)),
            const SizedBox(height: 16),
            const Text(
              'Ready to hit the trail?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'GPS tracks every 10 seconds.\nWorks offline — no data needed.',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (hike.error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hike.error!,
                        style: TextStyle(color: Colors.red[300], fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => hike.startTracking(),
              icon: const Icon(Icons.play_arrow, size: 28),
              label: const Text('Start Hike', style: TextStyle(fontSize: 18)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                backgroundColor: Colors.green[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// View shown during active tracking — live stats.
class _TrackingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hike = context.watch<HikeService>();
    final track = hike.activeTrack;
    if (track == null) return const SizedBox();

    final duration = track.duration;
    final durationStr = '${duration.inHours}:${(duration.inMinutes % 60).toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

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
                      boxShadow: [BoxShadow(color: Colors.green.withValues(alpha: 0.5), blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('TRACKING', style: TextStyle(
                    color: Colors.green[400], fontSize: 12,
                    fontWeight: FontWeight.bold, letterSpacing: 2,
                  )),
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
                // Distance + Speed row
                Row(
                  children: [
                    _StatCard(
                      icon: Icons.straighten,
                      label: 'Distance',
                      value: track.totalDistanceKm < 1
                          ? '${track.totalDistanceMeters.toStringAsFixed(0)} m'
                          : '${track.totalDistanceKm.toStringAsFixed(2)} km',
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      icon: Icons.speed,
                      label: 'Avg Speed',
                      value: '${track.avgSpeedKmh.toStringAsFixed(1)} km/h',
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Elevation row
                Row(
                  children: [
                    _StatCard(
                      icon: Icons.terrain,
                      label: 'Altitude',
                      value: '${track.currentAltitude.toStringAsFixed(0)} m',
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      icon: Icons.trending_up,
                      label: 'Elev. Gain',
                      value: '${track.elevationGain.toStringAsFixed(0)} m',
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Points + Accuracy row
                Row(
                  children: [
                    _StatCard(
                      icon: Icons.location_on,
                      label: 'Waypoints',
                      value: '${track.waypoints.length}',
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      icon: Icons.gps_fixed,
                      label: 'GPS Accuracy',
                      value: hike.lastPosition != null
                          ? '${hike.lastPosition!.accuracy.toStringAsFixed(0)} m'
                          : '—',
                    ),
                  ],
                ),

                const Spacer(),

                // Stop button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _confirmStop(context),
                    icon: const Icon(Icons.stop, size: 28),
                    label: const Text('Stop Hike', style: TextStyle(fontSize: 18)),
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop Hike?'),
        content: const Text('GPS tracking will stop. You can export the GPX file after.'),
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

/// Post-hike summary sheet.
class _SummarySheet extends StatelessWidget {
  final HikeTrack track;
  const _SummarySheet({required this.track});

  @override
  Widget build(BuildContext context) {
    final duration = track.duration;
    final durationStr = '${duration.inHours}h ${duration.inMinutes % 60}m';

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
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
          const Text('🏁 Hike Complete!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
          _summaryRow('Elevation Gain', '${track.elevationGain.toStringAsFixed(0)} m'),
          _summaryRow('Elevation Loss', '${track.elevationLoss.toStringAsFixed(0)} m'),
          _summaryRow('Max Altitude', '${track.maxAltitude.toStringAsFixed(0)} m'),
          _summaryRow('Waypoints', '${track.waypoints.length}'),

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _exportGpx(context),
            icon: const Icon(Icons.file_download),
            label: const Text('Export GPX'),
          ),
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

  void _exportGpx(BuildContext context) async {
    final hike = context.read<HikeService>();
    final path = await hike.exportGpx(track);
    if (path != null && context.mounted) {
      // Try sharing the file
      try {
        await Share.shareXFiles([XFile(path)]);
      } catch (_) {
        // Fallback: just show path
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPX saved: $path')),
        );
      }
    }
  }
}

/// Past hikes list.
class _HistorySheet extends StatelessWidget {
  final List<HikeTrack> tracks;
  const _HistorySheet({required this.tracks});

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: Text('No hikes yet', style: TextStyle(color: Colors.grey))),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tracks.length + 1, // +1 for header
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Past Hikes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          );
        }
        final track = tracks[i - 1];
        final duration = track.duration;
        return Card(
          child: ListTile(
            leading: const Text('🥾', style: TextStyle(fontSize: 28)),
            title: Text(track.name),
            subtitle: Text(
              '${track.totalDistanceKm.toStringAsFixed(2)} km • '
              '${duration.inHours}h ${duration.inMinutes % 60}m • '
              '${track.waypoints.length} pts',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.file_download, size: 20),
              onPressed: () async {
                final hike = context.read<HikeService>();
                final path = await hike.exportGpx(track);
                if (path != null && context.mounted) {
                  try {
                    await Share.shareXFiles([XFile(path)]);
                  } catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('GPX saved: $path')),
                    );
                  }
                }
              },
            ),
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
            Row(
              children: [
                Icon(icon, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
