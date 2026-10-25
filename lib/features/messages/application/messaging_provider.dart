import 'dart:async';
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

      // Force refresh token if expired or about to expire within 3 minutes
      var token = await user.getIdTokenResult();
      final exp = token.expirationTime;
      final isExpiredOrExpiringSoon = exp == null ||
          exp.toUtc().isBefore(DateTime.now().toUtc().add(const Duration(minutes: 3)));

      if (isExpiredOrExpiringSoon) {
        await user.getIdToken(true);
        token = await user.getIdTokenResult();
      }

      if (token.claims?['role'] == 'authenticated') return token.token;
      try {
        await (authSetup ??= backend.functions.invoke(
          'chat-auth',
          headers: {'Authorization': 'Bearer ${token.token}'},
        ));
      } catch (_) {
        authSetup = null;
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
/// Merges remote Supabase realtime updates with the local store so vendor conversations
/// are always immediately visible and resilient across online/offline modes.
final vendorConversationsProvider =
    StreamProvider.autoDispose<List<ChatConversation>>((ref) {
      final repo = ref.watch(messagingRepositoryProvider);
      final store = ref.watch(sharedMessagingStoreProvider);
      final stall = ref.watch(vendorStallProvider);
      final currentVendorId = ref.watch(currentVendorIdProvider);
      final stallId = currentVendorId ?? stall.stallId;

      final controller = StreamController<List<ChatConversation>>();
      List<ChatConversation> repoList = [];

      List<ChatConversation> buildMerged() {
        final normalizedStallId =
            (stallId == 'stall holder-001' || stallId == 'vendor-001')
                ? 'v1'
                : stallId;
        // Never include admin support conversations in the vendor inbox history.
        // Direct admin support is accessed separately via the dedicated header action.
        final localConvs = store.conversations.where(
          (c) {
            final isAdmin = c.inquiryType == 'admin_support' ||
                c.customerUid == 'admin_support' ||
                c.stallId == 'admin_support' ||
                c.id.contains('admin_support');
            if (isAdmin) return false;
            return c.stallId == stallId ||
                c.stallId == normalizedStallId ||
                (normalizedStallId.isEmpty &&
                    (c.stallId == 'v1' || c.stallId == 'vendor-001'));
          },
        );
        final result = repoList.where((c) {
          final isAdmin = c.inquiryType == 'admin_support' ||
              c.customerUid == 'admin_support' ||
              c.stallId == 'admin_support' ||
              c.id.contains('admin_support');
          return !isAdmin;
        }).toList();
        for (final localConv in localConvs) {
          final existingIdx = result.indexWhere((c) => c.id == localConv.id);
          if (existingIdx == -1) {
            result.add(localConv);
          } else {
            if (localConv.lastMessageTimestamp.isAfter(result[existingIdx].lastMessageTimestamp)) {
              result[existingIdx] = localConv;
            }
          }
        }
        result.sort((a, b) => b.lastMessageTimestamp.compareTo(a.lastMessageTimestamp));
        return result;
      }

      void emit() {
        if (!controller.isClosed) {
          controller.add(buildMerged());
        }
      }

      store.load().then((_) {
        emit();
      });

      repo.getConversationsForVendor(stallId).then((list) {
        repoList = list;
        emit();
      }).catchError((_) {});

      final repoSub = repo.watchConversationsForVendor(stallId).listen(
        (list) {
          repoList = list;
          emit();
        },
        onError: (_) {},
      );

      final storeSub = store.watchConversations().listen(
        (_) => emit(),
        onError: (_) {},
      );

      ref.onDispose(() {
        repoSub.cancel();
        storeSub.cancel();
        controller.close();
      });

      return controller.stream;
    });

/// Stream of conversations for the customer.
/// Merges remote Supabase realtime updates with local store conversations so chat
/// history remains continuously accessible.
final customerConversationsProvider =
    StreamProvider.autoDispose<List<ChatConversation>>((ref) {
      final repo = ref.watch(messagingRepositoryProvider);
      final store = ref.watch(sharedMessagingStoreProvider);
      final user = ref.watch(authProvider);
      final customerUid = user?.uid ?? 'customer-001';

      final controller = StreamController<List<ChatConversation>>();
      List<ChatConversation> repoList = [];

      List<ChatConversation> buildMerged() {
        // Never include admin support conversations in customer inbox history.
        // Direct admin support is accessed separately via the dedicated header action.
        final localConvs = store.conversations.where(
          (c) {
            final isAdmin = c.inquiryType == 'admin_support' ||
                c.customerUid == 'admin_support' ||
                c.stallId == 'admin_support' ||
                c.id.contains('admin_support');
            if (isAdmin) return false;
            return c.customerUid == customerUid ||
                c.customerUid == 'customer-001';
          },
        );
        final result = repoList.where((c) {
          final isAdmin = c.inquiryType == 'admin_support' ||
              c.customerUid == 'admin_support' ||
              c.stallId == 'admin_support' ||
              c.id.contains('admin_support');
          return !isAdmin;
        }).toList();
        for (final localConv in localConvs) {
          final existingIdx = result.indexWhere((c) => c.id == localConv.id);
          if (existingIdx == -1) {
            result.add(localConv);
          } else {
            if (localConv.lastMessageTimestamp.isAfter(result[existingIdx].lastMessageTimestamp)) {
              result[existingIdx] = localConv;
            }
          }
        }
        result.sort((a, b) => b.lastMessageTimestamp.compareTo(a.lastMessageTimestamp));
        return result;
      }

      void emit() {
        if (!controller.isClosed) {
          controller.add(buildMerged());
        }
      }

      store.load().then((_) {
        emit();
      });

      repo.getConversationsForCustomer(customerUid).then((list) {
        repoList = list;
        emit();
      }).catchError((_) {});

      final repoSub = repo.watchConversationsForCustomer(customerUid).listen(
        (list) {
          repoList = list;
          emit();
        },
        onError: (_) {},
      );

      final storeSub = store.watchConversations().listen(
        (_) => emit(),
        onError: (_) {},
      );

      ref.onDispose(() {
        repoSub.cancel();
        storeSub.cancel();
        controller.close();
      });

      return controller.stream;
    });

/// Stream indicating whether there is an unread message in the admin support conversation
/// for the current vendor or customer, powering the unread badge on the "Message Admin Directly" button.
final adminHasUnreadProvider =
    StreamProvider.autoDispose.family<bool, bool>((ref, isVendor) {
      final store = ref.watch(sharedMessagingStoreProvider);
      final controller = StreamController<bool>();

      bool checkUnread() {
        return store.conversations.any((c) {
          final isAdmin = c.inquiryType == 'admin_support' ||
              c.customerUid == 'admin_support' ||
              c.stallId == 'admin_support' ||
              c.id.contains('admin_support');
          if (!isAdmin) return false;
          return isVendor ? c.vendorUnreadCount > 0 : c.customerUnreadCount > 0;
        });
      }

      controller.add(checkUnread());

      final sub = store.watchConversations().listen((_) {
        if (!controller.isClosed) {
          controller.add(checkUnread());
        }
      });

      ref.onDispose(() {
        sub.cancel();
        controller.close();
      });

      return controller.stream;
    });


/// Stream of messages for a single conversation with instant live sync and deduplication.
final conversationMessagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, String>((ref, conversationId) {
      final repo = ref.watch(messagingRepositoryProvider);
      final store = ref.watch(sharedMessagingStoreProvider);
      final wsService = ref.watch(webSocketMessagingServiceProvider);

      final controller = StreamController<List<ChatMessage>>();
      final messageMap = <String, ChatMessage>{};

      void emitMerged() {
        if (controller.isClosed) return;
        final list = messageMap.values.toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        controller.add(list);
      }

      void addMessages(Iterable<ChatMessage> msgs) {
        bool changed = false;
        for (final m in msgs) {
          final existing = messageMap[m.id];
          if (existing == null || existing.isRead != m.isRead || existing.text != m.text) {
            messageMap[m.id] = m;
            changed = true;
          }
        }
        if (changed) {
          emitMerged();
        }
      }

      // 1. Initial load from local store (instant display with 0ms delay)
      store.load().then((_) {
        addMessages(store.getMessages(conversationId));
      });

      // 2. Fetch remote DB messages and update local store cache
      Future<void> fetchRemote() async {
        try {
          final remote = await repo.getMessages(conversationId);
          if (remote.isNotEmpty) {
            addMessages(remote);
            for (final m in remote) {
              store.addMessageSilently(m);
            }
          }
        } catch (_) {}
      }

      fetchRemote();

      // 3. Listen to local store (fires instantly when local user sends message or marks read)
      final storeSub = store.watchMessages(conversationId).listen((msgs) {
        addMessages(msgs);
      });

      // 4. Listen to WebSocket live broadcasts (fires instantly when counterpart sends message)
      final wsSub = wsService.watchBroadcastMessages(conversationId).listen((msg) {
        addMessages([msg]);
        store.addMessageSilently(msg);
      });

      // 5. Listen to Supabase Postgres CDC stream (if enabled)
      final repoSub = repo.watchMessages(conversationId).listen(
        (msgs) => addMessages(msgs),
        onError: (_) {},
      );

      // 6. Polling timer every 2 seconds while chat is active to guarantee 100% synchronization
      final pollTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
        fetchRemote();
      });

      ref.onDispose(() {
        pollTimer.cancel();
        storeSub.cancel();
        wsSub.cancel();
        repoSub.cancel();
        controller.close();
      });

      return controller.stream;
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
      final conv = await _repo.getOrCreateConversation(
        customerUid: customerUid,
        customerName: customerName,
        stallId: stallId,
        stallName: stallName,
        stallAvatar: stallAvatar,
        customerAvatar: customerAvatar,
        inquiryType: inquiryType,
        relatedOrderId: relatedOrderId,
      );
      await _store.registerConversation(conv);
      return conv;
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
      final msg = await _store.sendMessage(
        conversationId: conversationId,
        senderId: senderId,
        senderName: senderName,
        senderRole: senderRole,
        text: text,
        attachmentUrl: attachmentUrl,
        attachmentType: attachmentType,
      );
      _wsService.broadcastMessage(conversationId: conversationId, message: msg);
      return msg;
    }

    ChatMessage result;
    try {
      result = await _repo.sendMessage(
        conversationId: conversationId,
        senderId: senderId,
        senderName: senderName,
        senderRole: senderRole,
        text: text,
        attachmentUrl: attachmentUrl,
        attachmentType: attachmentType,
      );
    } catch (_) {
      result = await _store.sendMessage(
        conversationId: conversationId,
        senderId: senderId,
        senderName: senderName,
        senderRole: senderRole,
        text: text,
        attachmentUrl: attachmentUrl,
        attachmentType: attachmentType,
      );
    }

    // Immediately record in local store so sender sees it without delay
    _store.addMessage(result);

    // Broadcast over WebSocket so counterpart receives it in real time
    _wsService.broadcastMessage(
      conversationId: conversationId,
      message: result,
    );

    return result;
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
