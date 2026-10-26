import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:palengkego/features/messages/data/websocket_messaging_service.dart';
import 'package:palengkego/features/messages/domain/chat_conversation.dart';
import 'package:palengkego/features/messages/domain/chat_message.dart';
import 'package:palengkego/features/messages/domain/messaging_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase implementation of [MessagingRepository] with real-time WebSocket support.
///
/// Features:
/// - Real-time stream listening via Supabase Postgres CDC over WebSockets
/// - Ephemeral typing indicators via [WebSocketMessagingService]
/// - Zero custom server maintenance with row-level security
class SupabaseMessagingRepository implements MessagingRepository {
  SupabaseMessagingRepository({
    required SupabaseClient client,
    WebSocketMessagingService? wsService,
  }) : _client = client,
       _wsService = wsService;

  final SupabaseClient _client;
  final WebSocketMessagingService? _wsService;

  WebSocketMessagingService? get wsService => _wsService;

  @override
  Stream<List<ChatConversation>> watchConversationsForVendor(String stallId) {
    return _client
        .from('conversations')
        .stream(primaryKey: ['id'])
        .eq('stall_id', stallId)
        .order('last_message_timestamp', ascending: false)
        .map((rows) => rows.map(_mapConversation).toList());
  }

  @override
  Stream<List<ChatConversation>> watchConversationsForCustomer(
    String customerUid,
  ) {
    return _client
        .from('conversations')
        .stream(primaryKey: ['id'])
        .eq('customer_uid', customerUid)
        .order('last_message_timestamp', ascending: false)
        .map((rows) => rows.map(_mapConversation).toList());
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    // Ensure WebSocket channel is active for this conversation room
    _wsService?.subscribeToConversation(conversationId: conversationId);

    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('timestamp', ascending: true)
        .asyncMap((rows) => Future.wait(rows.map(_readMessage)));
  }

  @override
  Future<List<ChatConversation>> getConversationsForVendor(
    String stallId,
  ) async {
    try {
      final response = await _client
          .from('conversations')
          .select()
          .eq('stall_id', stallId)
          .order('last_message_timestamp', ascending: false);

      final list = (response as List<dynamic>? ?? []);
      return list
          .map((r) => _mapConversation(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[SupabaseMessaging] Error fetching vendor conversations: $e',
        );
      }
      return [];
    }
  }

  @override
  Future<List<ChatConversation>> getConversationsForCustomer(
    String customerUid,
  ) async {
    try {
      final response = await _client
          .from('conversations')
          .select()
          .eq('customer_uid', customerUid)
          .order('last_message_timestamp', ascending: false);

      final list = (response as List<dynamic>? ?? []);
      return list
          .map((r) => _mapConversation(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[SupabaseMessaging] Error fetching customer conversations: $e',
        );
      }
      return [];
    }
  }

  @override
  Future<List<ChatMessage>> getMessages(String conversationId) async {
    try {
      final response = await _client
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('timestamp', ascending: true);

      final list = (response as List<dynamic>? ?? []);
      return await Future.wait(
        list.map((r) => _readMessage(Map<String, dynamic>.from(r as Map))),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SupabaseMessaging] Error fetching messages: $e');
      }
      rethrow;
    }
  }

  @override
  Future<ChatConversation> getOrCreateConversation({
    required String customerUid,
    required String customerName,
    required String stallId,
    required String stallName,
    String? stallAvatar,
    String? customerAvatar,
    String inquiryType = 'general',
    String? relatedOrderId,
  }) async {
    try {
      final row = await _client
          .rpc(
            'chat_get_or_create',
            params: {
              'p_stall_id': stallId,
              'p_customer_uid': customerUid,
              'p_inquiry_type': inquiryType,
              'p_related_order_id': relatedOrderId,
            },
          )
          .single();
      return _mapConversation(Map<String, dynamic>.from(row));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SupabaseMessaging] chat_get_or_create rpc fallback to direct query: ');
      }
      final existing = await _client
          .from('conversations')
          .select()
          .eq('stall_id', stallId)
          .eq('customer_uid', customerUid)
          .maybeSingle();

      if (existing != null) {
        return _mapConversation(Map<String, dynamic>.from(existing));
      }

      final convId = 'conv_' + stallId + '_' + customerUid;
      final now = DateTime.now().toIso8601String();
      final inserted = await _client.from('conversations').insert({
        'id': convId,
        'stall_id': stallId,
        'stall_name': stallName,
        'stall_avatar': stallAvatar,
        'customer_uid': customerUid,
        'customer_name': customerName,
        'customer_avatar': customerAvatar,
        'inquiry_type': inquiryType,
        'related_order_id': relatedOrderId,
        'last_message_text': '',
        'last_message_timestamp': now,
        'last_message_sender_id': '',
        'created_at': now,
        'updated_at': now,
      }).select().single();

      return _mapConversation(Map<String, dynamic>.from(inserted));
    }
  }

  @override
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String senderId,
    required String senderName,
    required String senderRole,
    required String text,
    String? attachmentUrl,
    String? attachmentType,
  }) async {
    try {
      final row = await _client
          .rpc(
            'chat_send_message',
            params: {
              'p_conversation_id': conversationId,
              'p_text': text,
              'p_attachment_url': attachmentUrl,
              'p_attachment_type': attachmentType,
            },
          )
          .single();
      return _mapMessage(Map<String, dynamic>.from(row));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SupabaseMessaging] chat_send_message rpc fallback to direct insert: ');
      }
      final now = DateTime.now();
      final nowIso = now.toIso8601String();
      final msgId = 'msg_' + DateTime.now().millisecondsSinceEpoch.toString();

      final inserted = await _client.from('messages').insert({
        'id': msgId,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'sender_name': senderName,
        'sender_role': senderRole,
        'text': text.trim(),
        'timestamp': nowIso,
        'is_read': false,
        if (attachmentUrl != null) 'attachment_url': attachmentUrl,
        if (attachmentType != null) 'attachment_type': attachmentType,
      }).select().single();

      await _client.from('conversations').update({
        'last_message_text': text.trim(),
        'last_message_timestamp': nowIso,
        'last_message_sender_id': senderId,
        'admin_unread_count': 1,
        'updated_at': nowIso,
      }).eq('id', conversationId);

      return _mapMessage(Map<String, dynamic>.from(inserted));
    }
  }

  @override
  Future<void> markAsRead({
    required String conversationId,
    required String readerRole,
  }) async {
    try {
      await _client.rpc(
        'chat_mark_read',
        params: {'p_conversation_id': conversationId},
      );
    } catch (e) {
      final nowIso = DateTime.now().toIso8601String();
      await _client
          .from('messages')
          .update({'is_read': true, 'read_at': nowIso})
          .eq('conversation_id', conversationId)
          .eq('is_read', false);

      await _client.from('conversations').update({
        'customer_unread_count': 0,
        'vendor_unread_count': 0,
      }).eq('id', conversationId);
    }
  }

  @override
  Stream<int> watchVendorUnreadCount(String stallId) {
    return watchConversationsForVendor(stallId).map((conversations) {
      return conversations.where((c) => c.vendorUnreadCount > 0).length;
    });
  }

  @override
  Stream<int> watchCustomerUnreadCount(String customerUid) {
    return watchConversationsForCustomer(customerUid).map((conversations) {
      return conversations.where((c) => c.customerUnreadCount > 0).length;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Row Mapping Helpers
  // ─────────────────────────────────────────────────────────────────────────────

  ChatConversation _mapConversation(Map<String, dynamic> row) {
    final now = DateTime.now();
    return ChatConversation(
      id: row['id']?.toString() ?? '',
      stallId: row['stall_id']?.toString() ?? '',
      stallName: row['stall_name']?.toString() ?? '',
      stallAvatar: row['stall_avatar']?.toString(),
      customerUid: row['customer_uid']?.toString() ?? '',
      customerName: row['customer_name']?.toString() ?? '',
      customerAvatar: row['customer_avatar']?.toString(),
      lastMessageText: row['last_message_text']?.toString() ?? '',
      lastMessageTimestamp: row['last_message_timestamp'] != null
          ? DateTime.tryParse(row['last_message_timestamp'].toString()) ?? now
          : now,
      lastMessageSenderId: row['last_message_sender_id']?.toString() ?? '',
      customerUnreadCount: (row['customer_unread_count'] as int?) ?? 0,
      vendorUnreadCount: (row['vendor_unread_count'] as int?) ?? 0,
      inquiryType: row['inquiry_type']?.toString() ?? 'general',
      relatedOrderId: row['related_order_id']?.toString(),
      createdAt: row['created_at'] != null
          ? DateTime.tryParse(row['created_at'].toString()) ?? now
          : now,
      updatedAt: row['updated_at'] != null
          ? DateTime.tryParse(row['updated_at'].toString()) ?? now
          : now,
    );
  }

  Future<ChatMessage> _readMessage(Map<String, dynamic> row) async {
    final attachment = row['attachment_url']?.toString();
    if (attachment != null && attachment.startsWith('chat-attachments/')) {
      row = {
        ...row,
        'attachment_url': await _client.storage
            .from('chat-attachments')
            .createSignedUrl(
              attachment.substring('chat-attachments/'.length),
              3600,
            ),
      };
    }
    return _mapMessage(row);
  }

  ChatMessage _mapMessage(Map<String, dynamic> row) {
    final now = DateTime.now();
    return ChatMessage(
      id: row['id']?.toString() ?? '',
      conversationId: row['conversation_id']?.toString() ?? '',
      senderId: row['sender_id']?.toString() ?? '',
      senderName: row['sender_name']?.toString() ?? '',
      senderRole: row['sender_role']?.toString() ?? 'customer',
      text: row['text']?.toString() ?? '',
      timestamp: row['timestamp'] != null
          ? DateTime.tryParse(row['timestamp'].toString()) ?? now
          : now,
      isRead: row['is_read'] == true,
      readAt: row['read_at'] != null
          ? DateTime.tryParse(row['read_at'].toString())
          : null,
      attachmentUrl: row['attachment_url']?.toString(),
      attachmentType: row['attachment_type']?.toString(),
    );
  }
}
