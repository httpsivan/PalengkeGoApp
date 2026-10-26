class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String senderRole; // 'customer' | 'vendor'
  final String text;
  final DateTime timestamp;
  final bool isRead;
  final DateTime? readAt;
  final String? attachmentUrl;
  final String? attachmentType; // 'image', etc.

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.text,
    required this.timestamp,
    this.isRead = false,
    this.readAt,
    this.attachmentUrl,
    this.attachmentType,
  });

  bool get isFromVendor => senderRole == 'vendor';
  bool get isFromCustomer => senderRole == 'customer';
  bool get hasAttachment => attachmentUrl != null && attachmentUrl!.isNotEmpty;
  bool get isImageAttachment =>
      hasAttachment &&
      (attachmentType == 'image' ||
          attachmentUrl!.startsWith('data:image') ||
          attachmentUrl!.toLowerCase().endsWith('.jpg') ||
          attachmentUrl!.toLowerCase().endsWith('.jpeg') ||
          attachmentUrl!.toLowerCase().endsWith('.png'));

  ChatMessage copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? senderName,
    String? senderRole,
    String? text,
    DateTime? timestamp,
    bool? isRead,
    DateTime? readAt,
    String? attachmentUrl,
    String? attachmentType,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderRole: senderRole ?? this.senderRole,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      attachmentType: attachmentType ?? this.attachmentType,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversationId': conversationId,
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'text': text,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'isRead': isRead,
      'readAt': readAt?.toUtc().toIso8601String(),
      if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
      if (attachmentType != null) 'attachmentType': attachmentType,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    DateTime parseLocal(dynamic val) {
      if (val == null) return DateTime.now();
      final parsed = DateTime.tryParse(val.toString());
      return parsed != null ? parsed.toLocal() : DateTime.now();
    }

    DateTime? parseNullableLocal(dynamic val) {
      if (val == null) return null;
      final parsed = DateTime.tryParse(val.toString());
      return parsed?.toLocal();
    }

    return ChatMessage(
      id: json['id'] as String? ?? '',
      conversationId: json['conversationId'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? '',
      senderRole: json['senderRole'] as String? ?? 'customer',
      text: json['text'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? parseLocal(json['timestamp'])
          : DateTime.now(),
      isRead: json['isRead'] as bool? ?? false,
      readAt: parseNullableLocal(json['readAt']),
      attachmentUrl: json['attachmentUrl'] as String?,
      attachmentType: json['attachmentType'] as String?,
    );
  }
}
