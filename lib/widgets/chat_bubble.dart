import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_message.dart';

/// A chat message bubble with optional media attachments.
class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final color = isUser
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = isUser
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : Theme.of(context).colorScheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPressStart: (details) => _showContextMenu(context, details.globalPosition),
        child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: EdgeInsets.only(
          left: isUser ? 48 : 8,
          right: isUser ? 8 : 48,
          top: 4,
          bottom: 4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '🦊 Fred',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textColor.withValues(alpha: 0.6),
                  ),
                ),
              ),

            // Image attachments
            for (final att in message.attachments.where((a) => a.isImage))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: att.filePath != null
                      ? Image.file(
                          File(att.filePath!),
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _brokenImage(),
                        )
                      : att.bytes != null
                          ? Image.memory(
                              att.bytes!,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _brokenImage(),
                            )
                          : _brokenImage(),
                ),
              ),

            // Audio attachments
            for (final att in message.attachments.where((a) => a.isAudio))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AudioPlayerWidget(
                  attachment: att,
                  textColor: textColor,
                ),
              ),

            // File attachments (non-audio, non-image)
            for (final att in message.attachments.where((a) => !a.isAudio && !a.isImage))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FileAttachmentWidget(
                  attachment: att,
                  textColor: textColor,
                ),
              ),

            // Text content
            if (message.text.isNotEmpty &&
                message.text != '🎤 Voice note' &&
                message.text != '📷 Photo')
              Text(
                message.text,
                style: TextStyle(color: textColor, fontSize: 15),
              ),

            // Show placeholder for media-only messages without custom text
            if (message.text == '🎤 Voice note' &&
                message.attachments.isEmpty)
              Text(
                message.text,
                style: TextStyle(color: textColor, fontSize: 15),
              ),
            if (message.text == '📷 Photo' &&
                message.attachments.isEmpty)
              Text(
                message.text,
                style: TextStyle(color: textColor, fontSize: 15),
              ),

            if (message.isStreaming)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: textColor.withValues(alpha: 0.4),
                  ),
                ),
              ),
            // Timestamp
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 10,
                  color: textColor.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final hasText = message.text.isNotEmpty &&
        message.text != '🎤 Voice note' &&
        message.text != '📷 Photo';
    final hasImages = message.attachments.any((a) => a.isImage);
    final hasAudio = message.attachments.any((a) => a.isAudio);
    final hasFiles = message.attachments.any((a) => !a.isAudio && !a.isImage);

    final items = <PopupMenuEntry<String>>[
      if (hasText)
        const PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy, size: 20),
              SizedBox(width: 12),
              Text('Copy text'),
            ],
          ),
        ),
      if (hasText)
        const PopupMenuItem(
          value: 'select',
          child: Row(
            children: [
              Icon(Icons.select_all, size: 20),
              SizedBox(width: 12),
              Text('Select text'),
            ],
          ),
        ),
      if (hasImages || hasAudio || hasFiles)
        const PopupMenuItem(
          value: 'share_media',
          child: Row(
            children: [
              Icon(Icons.share, size: 20),
              SizedBox(width: 12),
              Text('Share media'),
            ],
          ),
        ),
      if (hasImages)
        const PopupMenuItem(
          value: 'save_image',
          child: Row(
            children: [
              Icon(Icons.save_alt, size: 20),
              SizedBox(width: 12),
              Text('Save image'),
            ],
          ),
        ),
      if (hasText)
        const PopupMenuItem(
          value: 'share_text',
          child: Row(
            children: [
              Icon(Icons.share, size: 20),
              SizedBox(width: 12),
              Text('Share text'),
            ],
          ),
        ),
    ];

    if (items.isEmpty) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx + 1, position.dy + 1,
      ),
      items: items,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'copy':
          Clipboard.setData(ClipboardData(text: message.text));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied to clipboard'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          break;
        case 'select':
          _showSelectableText(context);
          break;
        case 'share_text':
          Share.share(message.text);
          break;
        case 'share_media':
          final files = <XFile>[];
          for (final att in message.attachments) {
            if (att.filePath != null) {
              files.add(XFile(att.filePath!));
            }
          }
          if (files.isNotEmpty) {
            Share.shareXFiles(files);
          }
          break;
        case 'save_image':
          // Images from filePath are already on device
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Image is saved in app storage'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          break;
      }
    });
  }

  void _showSelectableText(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select text'),
        content: SelectableText(
          message.text,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _brokenImage() => Container(
        height: 100,
        color: Colors.grey[800],
        child: const Center(
          child: Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
}

/// Interactive audio player with play/pause, seek bar, and duration.
class AudioPlayerWidget extends StatefulWidget {
  final ChatAttachment attachment;
  final Color textColor;

  const AudioPlayerWidget({
    super.key,
    required this.attachment,
    required this.textColor,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _duration = widget.attachment.duration;

    // Listen to player state
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    // Listen to position updates
    _player.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });

    // Listen to duration updates
    _player.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration;
        });
      }
    });

    // Auto-stop when completed
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        setState(() => _isLoading = true);
        
        // If at the end, restart from beginning
        if (_position.inSeconds > 0 && _duration != null && 
            _position.inSeconds >= _duration!.inSeconds - 1) {
          await _player.seek(Duration.zero);
        }

        if (widget.attachment.filePath != null && !kIsWeb) {
          await _player.play(DeviceFileSource(widget.attachment.filePath!));
        } else if (widget.attachment.bytes != null) {
          await _player.play(BytesSource(widget.attachment.bytes!));
        }
        
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to play audio: $e'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _seek(double value) async {
    final position = Duration(seconds: value.toInt());
    await _player.seek(position);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.textColor;
    final maxDuration = _duration ?? widget.attachment.duration ?? const Duration(minutes: 1);
    final progress = maxDuration.inSeconds > 0
        ? _position.inSeconds / maxDuration.inSeconds
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Play/Pause button
              IconButton(
                icon: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    : Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: color,
                      ),
                onPressed: _isLoading ? null : _togglePlayPause,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
              const SizedBox(width: 4),

              // Waveform visualization (static)
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: List.generate(20, (i) {
                      final isActive = progress > (i / 20);
                      return Container(
                        width: 2.5,
                        height: 8.0 + (i % 3) * 4 + (i % 5) * 2,
                        decoration: BoxDecoration(
                          color: color.withValues(
                            alpha: isActive ? 0.7 : 0.3,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Duration
              Text(
                '${_formatDuration(_position)} / ${_formatDuration(maxDuration)}',
                style: TextStyle(
                  fontSize: 11,
                  color: color.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),

          // Seek bar
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: color.withValues(alpha: 0.8),
              inactiveTrackColor: color.withValues(alpha: 0.2),
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: _position.inSeconds.toDouble().clamp(0, maxDuration.inSeconds.toDouble()),
              max: maxDuration.inSeconds.toDouble(),
              onChanged: _seek,
            ),
          ),
        ],
      ),
    );
  }
}

/// File attachment display with download/open options.
class FileAttachmentWidget extends StatelessWidget {
  final ChatAttachment attachment;
  final Color textColor;

  const FileAttachmentWidget({
    super.key,
    required this.attachment,
    required this.textColor,
  });

  IconData _getFileIcon() {
    final mime = attachment.mimeType.toLowerCase();
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    if (mime.contains('zip') || mime.contains('archive')) return Icons.folder_zip;
    if (mime.contains('text')) return Icons.description;
    if (mime.contains('video')) return Icons.video_file;
    return Icons.insert_drive_file;
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _openFile(BuildContext context) async {
    if (attachment.filePath != null && !kIsWeb) {
      final file = File(attachment.filePath!);
      if (await file.exists()) {
        final uri = Uri.file(file.path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot open this file type'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = attachment.fileName ?? 'file';
    final fileSize = attachment.fileSize ?? attachment.bytes?.length;

    return InkWell(
      onTap: () => _openFile(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: textColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: textColor.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _getFileIcon(),
              size: 32,
              color: textColor.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (fileSize != null)
                    Text(
                      _formatFileSize(fileSize),
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.file_download,
              size: 20,
              color: textColor.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
