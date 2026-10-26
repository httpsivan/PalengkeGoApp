import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:palengkego/core/presentation/widgets/adaptive_image.dart';
import 'package:palengkego/core/theme/app_theme.dart';
import 'package:palengkego/features/messages/domain/chat_message.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isOutgoing;
  final bool showTimestamp;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isOutgoing,
    this.showTimestamp = true,
  });

  Widget _errorPlaceholder() {
    return Container(
      width: 180,
      height: 120,
      color: Colors.black12,
      child: const Center(
        child: Icon(
          Icons.broken_image_rounded,
          color: AppTheme.muted,
          size: 32,
        ),
      ),
    );
  }

  void _openFullScreenImage(BuildContext context, String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              leading: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: AdaptiveImage(
                  url,
                  fit: BoxFit.contain,
                  placeholder: const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryGreen,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAttachment(BuildContext context) {
    final url = message.attachmentUrl!;

    return GestureDetector(
      onTap: () => _openFullScreenImage(context, url),
      child: Container(
        margin: EdgeInsets.only(bottom: message.text.isNotEmpty ? 6 : 4),
        constraints: const BoxConstraints(
          maxHeight: 220,
          minHeight: 120,
          minWidth: 160,
        ),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.black.withValues(alpha: 0.05),
        ),
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.passthrough,
          children: [
            AdaptiveImage(
              url,
              fit: BoxFit.cover,
              placeholder: _errorPlaceholder(),
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.zoom_in_rounded,
                  color: Colors.white,
                  size: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localTime = message.timestamp.toLocal();
    final timeStr = DateFormat('h:mm a').format(localTime);
    final isAdmin = message.senderRole == 'admin';
    final roleLabel = isAdmin
        ? 'PalengkeGo Admin'
        : (message.senderName.trim().isNotEmpty
            ? message.senderName.trim()
            : (message.senderRole == 'vendor' ? 'Stall Holder' : 'Customer'));

    final Color bg = isOutgoing
        ? AppTheme.primaryGreen
        : const Color(0xFFF0FDF4);
    final Color fg = isOutgoing ? Colors.white : const Color(0xFF0F172A);
    final Border? border = isOutgoing
        ? null
        : Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35));

    final isWelcome = isAdmin &&
        (message.id.startsWith('msg_admin_welcome') ||
            message.text.toLowerCase().contains('how can the palengkego admin team help you') ||
            message.text.contains('PalengkeGo Admin team help you today'));
    final shouldDisplayHeader = showTimestamp && !isWelcome;

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          border: border,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isOutgoing ? 14 : 2),
            bottomRight: Radius.circular(isOutgoing ? 2 : 14),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Row: Sender Info & Time
            if (shouldDisplayHeader)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isOutgoing) ...[
                    Flexible(
                      child: Text(
                        roleLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF065F46),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ] else ...[
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      message.isRead
                          ? Icons.done_all_rounded
                          : Icons.done_rounded,
                      size: 13,
                      color: message.isRead
                          ? const Color(0xFF6EE7B7)
                          : Colors.white.withValues(alpha: 0.75),
                    ),
                  ],
                ],
              ),
            if (shouldDisplayHeader) const SizedBox(height: 4),
            // Photo Attachment if present
            if (message.hasAttachment) ...[
              _buildAttachment(context),
            ],
            // Text Content if present
            if (message.text.isNotEmpty)
              Text(
                message.text,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: fg,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
