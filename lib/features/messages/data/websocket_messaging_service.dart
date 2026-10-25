import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:palengkego/features/messages/domain/chat_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Manages real-time WebSocket communication for in-app chat.
///
/// Uses Supabase Realtime Channels operating over persistent WebSockets (WSS).
/// Supports:
/// - Instant message pushes via Postgres CDC over WebSocket
/// - Ephemeral typing indicators (`typing`) via WebSocket Broadcast
/// - Connection lifecycle and channel cleanup
class WebSocketMessagingService {
  WebSocketMessagingService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  final Map<String, RealtimeChannel> _activeChannels = {};
  final Map<String, StreamController<bool>> _typingControllers = {};
  final Map<String, Timer> _typingTimers = {};
  final Map<String, Set<String>> _typingCurrentUsers = {};
  final Map<String, StreamController<ChatMessage>> _messageControllers = {};
  final Map<String, Timer> _reconnectTimers = {};

  bool get isAvailable => _client != null;

  /// Subscribes to a conversation's WebSocket channel.
  RealtimeChannel? subscribeToConversation({
    required String conversationId,
    void Function(Map<String, dynamic> record)? onNewMessage,
    void Function(Map<String, dynamic> record)? onMessageUpdated,
  }) {
    final client = _client;
    if (client == null) return null;

    // Return existing channel if already subscribed
    if (_activeChannels.containsKey(conversationId)) {
      return _activeChannels[conversationId];
    }

    final channelName = 'chat-room-$conversationId';
    final channel = client.channel(channelName);

    // 1. WebSocket Broadcast: Typing indicators
    channel.onBroadcast(
      event: 'typing',
      callback: (payload) {
        final senderId = payload['sender_id']?.toString() ?? '';
        final isTyping = payload['is_typing'] == true;
        _handleTypingReceived(conversationId, senderId, isTyping);
      },
    );

    // 2. WebSocket Broadcast: Live message sync
    channel.onBroadcast(
      event: 'message',
      callback: (payload) {
        try {
          final messageMap = Map<String, dynamic>.from(payload['message'] as Map);
          final message = ChatMessage.fromJson(messageMap);
          _handleMessageReceived(conversationId, message);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[WebSocket] Error parsing broadcast message: $e');
          }
        }
      },
    );

    // 3. WebSocket Postgres Changes: Insert (new message)
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'conversation_id',
        value: conversationId,
      ),
      callback: (payload) {
        if (onNewMessage != null && payload.newRecord.isNotEmpty) {
          onNewMessage(payload.newRecord);
        }
      },
    );

    // 3. WebSocket Postgres Changes: Update (read receipts)
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'conversation_id',
        value: conversationId,
      ),
      callback: (payload) {
        if (onMessageUpdated != null && payload.newRecord.isNotEmpty) {
          onMessageUpdated(payload.newRecord);
        }
      },
    );

    channel.subscribe((status, error) {
      if (kDebugMode) {
        debugPrint('[WebSocket] Channel $channelName status: $status (error: $error)');
      }
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.closed) {
        _activeChannels.remove(conversationId);

        if (status == RealtimeSubscribeStatus.channelError) {
          // Token expired or temporary network drop; auto-reconnect after backoff
          _reconnectTimers[conversationId]?.cancel();
          _reconnectTimers[conversationId] = Timer(const Duration(milliseconds: 1500), () {
            if (_typingControllers.containsKey(conversationId) ||
                _messageControllers.containsKey(conversationId)) {
              subscribeToConversation(conversationId: conversationId);
            }
          });
        }
      }
    });

    _activeChannels[conversationId] = channel;
    return channel;
  }

  /// Broadcasts a typing status over the WebSocket connection.
  Future<void> sendTyping({
    required String conversationId,
    required String senderId,
    required bool isTyping,
  }) async {
    final userSet = _typingCurrentUsers.putIfAbsent(conversationId, () => <String>{});
    if (senderId.isNotEmpty) userSet.add(senderId);

    var channel = _activeChannels[conversationId];
    if (channel == null && _client != null) {
      channel = subscribeToConversation(conversationId: conversationId);
    }
    if (channel == null) return;

    try {
      await channel.sendBroadcastMessage(
        event: 'typing',
        payload: {
          'sender_id': senderId,
          'is_typing': isTyping,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebSocket] Failed to send typing broadcast: $e');
      }
    }
  }

  /// Broadcasts a newly sent chat message to all participants in [conversationId].
  Future<void> broadcastMessage({
    required String conversationId,
    required ChatMessage message,
  }) async {
    var channel = _activeChannels[conversationId];
    if (channel == null && _client != null) {
      channel = subscribeToConversation(conversationId: conversationId);
    }
    if (channel == null) return;

    try {
      await channel.sendBroadcastMessage(
        event: 'message',
        payload: {
          'conversation_id': conversationId,
          'message': message.toJson(),
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebSocket] Failed to broadcast message: $e');
      }
    }
  }

  /// Returns a stream of real-time broadcasted messages for [conversationId].
  Stream<ChatMessage> watchBroadcastMessages(String conversationId) {
    _messageControllers[conversationId] ??= StreamController<ChatMessage>.broadcast();
    return _messageControllers[conversationId]!.stream;
  }

  void _handleMessageReceived(String conversationId, ChatMessage message) {
    final controller = _messageControllers[conversationId];
    if (controller != null && !controller.isClosed) {
      controller.add(message);
    }
  }

  /// Returns a stream of typing state for the counterpart in [conversationId].
  Stream<bool> watchTyping(
    String conversationId,
    String currentUserId, {
    String? stallId,
  }) {
    _typingControllers[conversationId] ??= StreamController<bool>.broadcast();
    final userSet = _typingCurrentUsers.putIfAbsent(conversationId, () => <String>{});
    if (currentUserId.isNotEmpty) userSet.add(currentUserId);
    if (stallId != null && stallId.isNotEmpty) userSet.add(stallId);
    return _typingControllers[conversationId]!.stream.distinct();
  }

  void _handleTypingReceived(
    String conversationId,
    String senderId,
    bool isTyping,
  ) {
    // If the sender is this local user/device, ignore self-typing echo
    final currentUsers = _typingCurrentUsers[conversationId];
    if (currentUsers != null && senderId.isNotEmpty && currentUsers.contains(senderId)) {
      return;
    }

    final controller = _typingControllers[conversationId];
    if (controller == null || controller.isClosed) return;

    if (isTyping) {
      controller.add(true);
      _typingTimers[conversationId]?.cancel();
      // Auto-clear typing indicator after 3 seconds of inactivity
      _typingTimers[conversationId] = Timer(const Duration(seconds: 3), () {
        if (!controller.isClosed) {
          controller.add(false);
        }
      });
    } else {
      _typingTimers[conversationId]?.cancel();
      controller.add(false);
    }
  }

  /// Unsubscribes and cleans up the WebSocket channel for [conversationId].
  void unsubscribe(String conversationId) {
    final channel = _activeChannels.remove(conversationId);
    if (channel != null && _client != null) {
      _client.removeChannel(channel);
    }
    _reconnectTimers[conversationId]?.cancel();
    _reconnectTimers.remove(conversationId);
    _typingTimers[conversationId]?.cancel();
    _typingTimers.remove(conversationId);
    _typingControllers[conversationId]?.close();
    _typingControllers.remove(conversationId);
    _typingCurrentUsers.remove(conversationId);
    _messageControllers[conversationId]?.close();
    _messageControllers.remove(conversationId);
  }

  /// Disposes all active WebSocket channels and controllers.
  void dispose() {
    for (final entry in _activeChannels.entries) {
      _client?.removeChannel(entry.value);
    }
    _activeChannels.clear();
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    for (final controller in _typingControllers.values) {
      controller.close();
    }
    _typingControllers.clear();
    for (final controller in _messageControllers.values) {
      controller.close();
    }
    _messageControllers.clear();
    _typingCurrentUsers.clear();
  }
}
