import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
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
              _AudioBubble(attachment: att, textColor: textColor),

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
      if (hasImages || hasAudio)
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

/// Compact voice note display in a bubble.
class _AudioBubble extends StatelessWidget {
  final ChatAttachment attachment;
  final Color textColor;

  const _AudioBubble({required this.attachment, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final durationStr = attachment.duration != null
        ? '${attachment.duration!.inMinutes}:${(attachment.duration!.inSeconds % 60).toString().padLeft(2, '0')}'
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic, size: 20, color: textColor.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          // Waveform placeholder
          Flexible(
            child: Container(
              height: 28,
              constraints: const BoxConstraints(maxWidth: 160),
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  for (int i = 0; i < 12; i++)
                    Container(
                      width: 3,
                      height: 6.0 + (i % 3) * 5 + (i % 5) * 2,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: textColor.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  const Spacer(),
                ],
              ),
            ),
          ),
          if (durationStr.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              durationStr,
              style: TextStyle(
                fontSize: 12,
                color: textColor.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
