import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:palengkego/core/config/app_config.dart';
import 'package:palengkego/core/infrastructure/firebase_service.dart';
import 'package:palengkego/core/infrastructure/supabase_service.dart';
import 'package:palengkego/features/auth/application/auth_provider.dart';
import 'package:palengkego/features/messages/data/mock_messaging_repository.dart';
import 'package:palengkego/features/messages/data/shared_messaging_store.dart';
import 'package:palengkego/features/messages/data/supabase_messaging_repository.dart';
import 'package:palengkego/features/messages/data/websocket_messaging_service.dart';
import 'package:palengkego/features/messages/domain/chat_conversation.dart';
import 'package:palengkego/features/messages/domain/chat_message.dart';
import 'package:palengkego/features/messages/domain/messaging_repository.dart';
import 'package:palengkego/features/vendors/application/vendor_stall_provider.dart';

/// Dedicated authenticated client: other app services keep their existing auth.
final messagingClientProvider = Provider<SupabaseClient?>((ref) {
  final backend = ref.watch(supabaseClientProvider);
  if (backend == null) return null;
  final config = ref.watch(appConfigProvider);
  final auth = ref.watch(firebaseAuthProvider);
  final uid = ref.watch(authProvider)?.uid;
  Future<FunctionResponse>? authSetup;
  final client = SupabaseClient(
    config.supabaseUrl,
    config.supabaseAnonKey,
    accessToken: () async {
      final user = auth?.currentUser;
      if (user == null || user.uid != uid) return null;
      final token = await user.getIdTokenResult();
      if (token.claims?['role'] == 'authenticated') return token.token;
      try {
        await (authSetup ??= backend.functions.invoke(
          'chat-auth',
          headers: {'Authorization': 'Bearer ${token.token}'},
        ));
      } catch (_) {
        authSetup = null;
        rethrow;
      }
      return user.getIdToken(true);
    },
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Provider for managing persistent WebSocket channels and broadcast events.
final webSocketMessagingServiceProvider = Provider<WebSocketMessagingService>((
  ref,
) {
  final client = ref.watch(messagingClientProvider);
  final service = WebSocketMessagingService(client: client);
  ref.onDispose(service.dispose);
  return service;
});

/// Returns [SupabaseMessagingRepository] when Supabase is live/configured,
/// and falls back smoothly to [MockMessagingRepository] for testing and offline mode.
final messagingRepositoryProvider = Provider<MessagingRepository>((ref) {
  final client = ref.watch(messagingClientProvider);
  final store = ref.watch(sharedMessagingStoreProvider);

  if (client != null) {
    final wsService = ref.watch(webSocketMessagingServiceProvider);
    return SupabaseMessagingRepository(client: client, wsService: wsService);
  }

  return MockMessagingRepository(store: store);
});

/// Stream of conversations for the currently logged in vendor stall.
final vendorConversationsProvider =
    StreamProvider.autoDispose<List<ChatConversation>>((ref) async* {
      final repo = ref.watch(messagingRepositoryProvider);
      final store = ref.watch(sharedMessagingStoreProvider);
      final stall = ref.watch(vendorStallProvider);
      final currentVendorId = ref.watch(currentVendorIdProvider);
      final stallId = currentVendorId ?? stall.stallId;

      List<ChatConversation> mergeLocalAdmin(List<ChatConversation> list) {
        final localAdmin = store.conversations.where(
          (c) =>
              c.inquiryType == 'admin_support' ||
              c.customerUid == 'admin_support' ||
              c.stallId == 'admin_support',
        );
        final result = List<ChatConversation>.from(list);
        for (final adminConv in localAdmin) {
          if (!result.any((c) => c.id == adminConv.id)) {
            result.insert(0, adminConv);
          }
        }
        return result;
      }

      await store.load();
      var initial = <ChatConversation>[];
      try {
        initial = await repo.getConversationsForVendor(stallId);
      } catch (_) {}

      if (initial.isEmpty) {
        final normalizedStallId =
            (stallId == 'stall holder-001' || stallId == 'vendor-001')
                ? 'v1'
                : stallId;
        final local = store.conversations
            .where((c) =>
                c.stallId == stallId ||
                c.stallId == normalizedStallId ||
                (normalizedStallId.isEmpty &&
                    (c.stallId == 'v1' || c.stallId == 'vendor-001')) ||
                c.customerUid == 'admin_support')
            .toList();
        if (local.isNotEmpty) {
          initial = local;
        }
      }
      yield mergeLocalAdmin(initial);

      try {
        await for (final convs in repo.watchConversationsForVendor(stallId)) {
          yield mergeLocalAdmin(convs);
        }
      } catch (_) {
        await for (final convs in store.watchConversations()) {
          final normalizedStallId =
              (stallId == 'stall holder-001' || stallId == 'vendor-001')
                  ? 'v1'
                  : stallId;
          final local = convs
              .where((c) =>
                  c.stallId == stallId ||
                  c.stallId == normalizedStallId ||
                  c.inquiryType == 'admin_support' ||
                  c.customerUid == 'admin_support')
              .toList();
          yield local;
        }
      }
    });

/// Stream of conversations for the customer.
final customerConversationsProvider =
    StreamProvider.autoDispose<List<ChatConversation>>((ref) async* {
      final repo = ref.watch(messagingRepositoryProvider);
      final store = ref.watch(sharedMessagingStoreProvider);
      final user = ref.watch(authProvider);
      final customerUid = user?.uid ?? 'customer-001';

      List<ChatConversation> mergeLocalAdmin(List<ChatConversation> list) {
        final localAdmin = store.conversations.where(
          (c) =>
              c.inquiryType == 'admin_support' ||
              c.customerUid == 'admin_support' ||
              c.stallId == 'admin_support',
        );
        final result = List<ChatConversation>.from(list);
        for (final adminConv in localAdmin) {
          if (!result.any((c) => c.id == adminConv.id)) {
            result.insert(0, adminConv);
          }
        }
        return result;
      }

      await store.load();
      var initial = <ChatConversation>[];
      try {
        initial = await repo.getConversationsForCustomer(customerUid);
      } catch (_) {}

      if (initial.isEmpty) {
        final local = store.conversations
            .where((c) =>
                c.customerUid == customerUid ||
                c.customerUid == 'customer-001' ||
                c.stallId == 'admin_support')
            .toList();
        if (local.isNotEmpty) {
          initial = local;
        }
      }
      yield mergeLocalAdmin(initial);

      try {
        await for (final convs in repo.watchConversationsForCustomer(customerUid)) {
          yield mergeLocalAdmin(convs);
        }
      } catch (_) {
        await for (final convs in store.watchConversations()) {
          final local = convs
              .where((c) =>
                  c.customerUid == customerUid ||
                  c.customerUid == 'customer-001' ||
                  c.inquiryType == 'admin_support' ||
                  c.stallId == 'admin_support')
              .toList();
          yield local;
        }
      }
    });

/// Stream of messages for a single conversation.
final conversationMessagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, String>((ref, conversationId) async* {
      final repo = ref.watch(messagingRepositoryProvider);
      final store = ref.watch(sharedMessagingStoreProvider);
      final isAdmin = conversationId.contains('admin_support');

      if (isAdmin) {
        await store.load();
        final local = store.getMessages(conversationId);
        yield local;
        yield* store.watchMessages(conversationId);
        return;
      }

      var initial = <ChatMessage>[];
      try {
        initial = await repo.getMessages(conversationId);
      } catch (_) {}

      if (initial.isEmpty) {
        await store.load();
        final local = store.getMessages(conversationId);
        if (local.isNotEmpty) {
          initial = local;
        }
      }
      yield initial;

      try {
        await for (final msgs in repo.watchMessages(conversationId)) {
          if (msgs.isEmpty && initial.isNotEmpty) {
            yield initial;
          } else {
            yield msgs;
          }
        }
      } catch (_) {
        yield* store.watchMessages(conversationId);
      }
    });

/// Stream of ephemeral typing indicators over WebSockets.
final conversationTypingProvider = StreamProvider.autoDispose
    .family<bool, String>((ref, conversationId) {
      final wsService = ref.watch(webSocketMessagingServiceProvider);
      final user = ref.watch(authProvider);
      final stall = ref.watch(vendorStallProvider);
      final currentUserId = user?.uid ?? '';
      final stallId = stall.stallId;
      return wsService.watchTyping(
        conversationId,
        currentUserId,
        stallId: stallId,
      );
    });

/// Total unread conversation count for vendor (used on badges).
final vendorUnreadMessagesCountProvider = Provider<int>((ref) {
  final conversationsAsync = ref.watch(vendorConversationsProvider);
  return conversationsAsync.maybeWhen(
    data: (conversations) {
      return conversations.where((c) => c.vendorUnreadCount > 0).length;
    },
    orElse: () => 0,
  );
});

/// Total unread conversation count for customer.
final customerUnreadMessagesCountProvider = Provider<int>((ref) {
  final conversationsAsync = ref.watch(customerConversationsProvider);
  return conversationsAsync.maybeWhen(
    data: (conversations) {
      return conversations.where((c) => c.customerUnreadCount > 0).length;
    },
    orElse: () => 0,
  );
});

/// Provider for messaging actions (send, mark read, getOrCreate, sendTyping).
final messagingActionsProvider = Provider<MessagingActions>((ref) {
  final repo = ref.watch(messagingRepositoryProvider);
  final wsService = ref.watch(webSocketMessagingServiceProvider);
  final store = ref.watch(sharedMessagingStoreProvider);
  return MessagingActions(repo, wsService, store);
});

class MessagingActions {
  final MessagingRepository _repo;
  final WebSocketMessagingService _wsService;
  final SharedMessagingStore _store;

  MessagingActions(this._repo, this._wsService, this._store);

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
    final isAdmin = inquiryType == 'admin_support' ||
        customerUid == 'admin_support' ||
        stallId == 'admin_support';

    if (isAdmin) {
      return _store.getOrCreateConversation(
        customerUid: customerUid,
        customerName: customerName,
        stallId: stallId,
        stallName: stallName,
        stallAvatar: stallAvatar,
        customerAvatar: customerAvatar,
        inquiryType: inquiryType,
        relatedOrderId: relatedOrderId,
      );
    }

    try {
      return await _repo.getOrCreateConversation(
        customerUid: customerUid,
        customerName: customerName,
        stallId: stallId,
        stallName: stallName,
        stallAvatar: stallAvatar,
        customerAvatar: customerAvatar,
        inquiryType: inquiryType,
        relatedOrderId: relatedOrderId,
      );
    } catch (_) {
      return _store.getOrCreateConversation(
        customerUid: customerUid,
        customerName: customerName,
        stallId: stallId,
        stallName: stallName,
        stallAvatar: stallAvatar,
        customerAvatar: customerAvatar,
        inquiryType: inquiryType,
        relatedOrderId: relatedOrderId,
      );
    }
  }

  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String senderId,
    required String senderName,
    required String senderRole,
    required String text,
    String? attachmentUrl,
    String? attachmentType,
  }) async {
    // Clear typing indicator when message is sent
    try {
      _wsService.sendTyping(
        conversationId: conversationId,
        senderId: senderId,
        isTyping: false,
      );
    } catch (_) {}

    final isAdmin = conversationId.contains('admin_support');
    if (isAdmin) {
      return _store.sendMessage(
        conversationId: conversationId,
        senderId: senderId,
        senderName: senderName,
        senderRole: senderRole,
        text: text,
        attachmentUrl: attachmentUrl,
        attachmentType: attachmentType,
      );
    }

    try {
      return await _repo.sendMessage(
        conversationId: conversationId,
        senderId: senderId,
        senderName: senderName,
        senderRole: senderRole,
        text: text,
        attachmentUrl: attachmentUrl,
        attachmentType: attachmentType,
      );
    } catch (_) {
      return _store.sendMessage(
        conversationId: conversationId,
        senderId: senderId,
        senderName: senderName,
        senderRole: senderRole,
        text: text,
        attachmentUrl: attachmentUrl,
        attachmentType: attachmentType,
      );
    }
  }

  Future<void> sendTyping({
    required String conversationId,
    required String senderId,
    required bool isTyping,
  }) {
    return _wsService.sendTyping(
      conversationId: conversationId,
      senderId: senderId,
      isTyping: isTyping,
    );
  }

  Future<void> markAsRead({
    required String conversationId,
    required String readerRole,
  }) async {
    if (conversationId.contains('admin_support')) {
      return _store.markAsRead(
        conversationId: conversationId,
        readerRole: readerRole,
      );
    }
    try {
      await _repo.markAsRead(
        conversationId: conversationId,
        readerRole: readerRole,
      );
    } catch (_) {
      await _store.markAsRead(
        conversationId: conversationId,
        readerRole: readerRole,
      );
    }
  }
}
