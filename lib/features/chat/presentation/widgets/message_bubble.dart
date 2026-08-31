import 'package:flutter/material.dart';

import '../../data/chat_models.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final VoidCallback? onRetry;
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg =
        isMine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
        decoration: BoxDecoration(
          color: isMine
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.text, style: TextStyle(color: fg)),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_hm(message.createdAt),
                    style: TextStyle(
                        fontSize: 10, color: fg.withValues(alpha: 0.7))),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  if (message.failed)
                    GestureDetector(
                      onTap: onRetry,
                      child: Icon(Icons.error_outline,
                          size: 14, color: theme.colorScheme.error),
                    )
                  else
                    Icon(
                      message.pending
                          ? Icons.schedule
                          : message.seen
                              ? Icons.done_all
                              : Icons.done,
                      size: 13,
                      color: fg.withValues(alpha: 0.8),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
