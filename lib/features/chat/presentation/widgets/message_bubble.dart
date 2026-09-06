import 'package:flutter/material.dart';

import '../../data/chat_models.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final VoidCallback? onRetry;
  final VoidCallback? onLongPress;
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.onRetry,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg =
        isMine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: message.isDeleted ? null : onLongPress,
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
              if (message.replyTo != null) _quote(fg),
              if (message.isDeleted)
                _deleted(fg)
              else
                Text(message.text, style: TextStyle(color: fg)),
              const SizedBox(height: 2),
              _meta(theme, fg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quote(Color fg) {
    final empty = message.replyTo!.text.isEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        border: Border(
            left: BorderSide(color: fg.withValues(alpha: 0.5), width: 3)),
        color: fg.withValues(alpha: 0.06),
      ),
      child: Text(
        empty ? 'usunięta wiadomość' : message.replyTo!.text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: fg.withValues(alpha: 0.8),
          fontStyle: empty ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );
  }

  Widget _deleted(Color fg) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block, size: 14, color: fg.withValues(alpha: 0.6)),
          const SizedBox(width: 4),
          Text('Wiadomość usunięta',
              style: TextStyle(
                  color: fg.withValues(alpha: 0.6),
                  fontStyle: FontStyle.italic)),
        ],
      );

  Widget _meta(ThemeData theme, Color fg) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_hm(message.createdAt),
              style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.7))),
          if (message.isEdited && !message.isDeleted) ...[
            const SizedBox(width: 4),
            Text('edytowano',
                style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: fg.withValues(alpha: 0.7))),
          ],
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
      );

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
