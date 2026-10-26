import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palengkego/core/presentation/widgets/adaptive_image.dart';
import 'package:palengkego/core/theme/app_theme.dart';
import 'package:palengkego/core/utils/page_transitions.dart';
import 'package:palengkego/features/auth/application/auth_provider.dart';
import 'package:palengkego/features/messages/application/messaging_provider.dart';
import 'package:palengkego/features/messages/data/shared_messaging_store.dart';
import 'package:palengkego/features/messages/domain/chat_conversation.dart';
import 'package:palengkego/features/messages/presentation/pages/chat_screen.dart';
import 'package:palengkego/features/messages/presentation/widgets/conversation_card.dart';
import 'package:palengkego/features/messages/presentation/widgets/messages_filter_chips.dart';
import 'package:palengkego/features/vendors/application/vendor_stall_provider.dart';

class MessagesInboxScreen extends ConsumerStatefulWidget {
  final bool isEmbeddedInTab;
  final bool? isVendorView;

  const MessagesInboxScreen({
    super.key,
    this.isEmbeddedInTab = true,
    this.isVendorView,
  });

  @override
  ConsumerState<MessagesInboxScreen> createState() => _MessagesInboxScreenState();
}

class _MessagesInboxScreenState extends ConsumerState<MessagesInboxScreen> {
  MessageFilter _selectedFilter = MessageFilter.all;
  String _searchQuery = '';
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openAdminChat(
    BuildContext context,
    bool isVendor,
  ) async {
    try {
      final user = ref.read(authProvider);
      final stall = ref.read(vendorStallProvider);
      final currentVendorId = ref.read(currentVendorIdProvider);
      final stallId = currentVendorId ??
          (stall.stallId.isNotEmpty ? stall.stallId : 'v1');
      final stallName =
          stall.name.isNotEmpty ? stall.name : 'PalengkeGo Stall Holder';

      const adminId = 'admin_support';
      const adminName = 'PalengkeGo Admin';

      final messagingActions = ref.read(messagingActionsProvider);

      ChatConversation conv;
      try {
        if (isVendor) {
          conv = await messagingActions.getOrCreateConversation(
            customerUid: adminId,
            customerName: adminName,
            stallId: stallId,
            stallName: stallName,
            stallAvatar: null,
            inquiryType: 'admin_support',
          );
        } else {
          conv = await messagingActions.getOrCreateConversation(
            customerUid: user?.uid ?? 'customer-001',
            customerName: user?.displayName ?? 'Customer',
            customerAvatar: user?.profilePhoto,
            stallId: adminId,
            stallName: adminName,
            inquiryType: 'admin_support',
          );
        }
      } catch (_) {
        // Fallback directly to shared messaging store if remote backend RLS restricts admin conversation creation
        final localStore = ref.read(sharedMessagingStoreProvider);
        conv = await localStore.getOrCreateConversation(
          customerUid: isVendor ? adminId : (user?.uid ?? 'customer-001'),
          customerName: isVendor ? adminName : (user?.displayName ?? 'Customer'),
          stallId: isVendor ? stallId : adminId,
          stallName: isVendor ? stallName : adminName,
          stallAvatar: null,
          customerAvatar: isVendor ? null : user?.profilePhoto,
          inquiryType: 'admin_support',
        );
      }

      if (!context.mounted) return;
      Navigator.of(context).push(
        PageTransitions.slideFromRight(
          ChatScreen(
            conversationId: conv.id,
            displayName: adminName,
            isVendorView: isVendor,
            stallId: isVendor ? stallId : adminId,
            avatarUrl: null, // Default admin profile avatar
            inquiryType: 'admin_support',
            relatedOrderId: conv.relatedOrderId,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Unable to connect to Admin: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final isVendor = widget.isVendorView ?? (user?.isVendor ?? true);
    final stall = ref.watch(vendorStallProvider);
    final headerAvatar = isVendor ? stall.avatarImage : null;

    final conversationsAsync = isVendor
        ? ref.watch(vendorConversationsProvider)
        : ref.watch(customerConversationsProvider);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header Bar matching reference image
            _buildHeader(context, ref, isVendor, headerAvatar),
            // Search Bar
            _buildSearchBar(isVendor),
            // Content
            Expanded(
              child: conversationsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.primaryGreen,
                  ),
                ),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 40,
                          color: Color(0xFFEF4444),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Unable to load messages. Please try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            ref.invalidate(vendorConversationsProvider);
                            ref.invalidate(customerConversationsProvider);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryGreen,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (allConversations) {
                  return _buildConversationContent(
                    context,
                    allConversations,
                    isVendor,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    bool isVendor,
    String? avatarUrl,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          if (!widget.isEmbeddedInTab) ...[
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(right: 12),
                decoration: const BoxDecoration(
                  color: AppTheme.scaffoldBackground,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 16,
                  color: AppTheme.primaryGreen,
                ),
              ),
            ),
          ],
          if (isVendor) ...[
            // Left: Stall icon/avatar (Stall Holder view only)
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                image: (avatarUrl != null &&
                        avatarUrl.isNotEmpty &&
                        adaptiveImageProvider(avatarUrl) != null)
                    ? DecorationImage(
                        image: adaptiveImageProvider(avatarUrl)!,
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: (avatarUrl == null || avatarUrl.isEmpty)
                  ? const Icon(
                      Icons.storefront_outlined,
                      color: Colors.white,
                      size: 20,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
          ],
          // Subtitle + Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isVendor) ...[
                  const Text(
                    'PalengkeGo Stall Holder',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                const Text(
                  'Messages',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ],
            ),
          ),
          // Direct Messaging to Admin Button (Replaces Notification Bell)
          Consumer(
            builder: (context, ref, _) {
              final hasAdminUnread = ref
                      .watch(adminHasUnreadProvider(isVendor))
                      .asData
                      ?.value ??
                  false;

              return Tooltip(
                message: 'Message Admin Directly',
                child: GestureDetector(
                  key: const Key('messages_admin_chat_button'),
                  onTap: () => _openAdminChat(context, isVendor),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primaryGreen.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        const Icon(
                          Icons.support_agent_rounded,
                          color: AppTheme.primaryGreen,
                          size: 24,
                        ),
                        Positioned(
                          top: 4,
                          right: 3,
                          child: Container(
                            padding: const EdgeInsets.all(1.5),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.chat_bubble_rounded,
                              color: Color(0xFF0284C7),
                              size: 10,
                            ),
                          ),
                        ),
                        if (hasAdminUnread)
                          Positioned(
                            top: 1,
                            right: 1,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isVendor) {
    final hintText = isVendor
        ? 'Search messages, customers, or orders...'
        : 'Search messages, stalls, or orders...';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              size: 20,
              color: AppTheme.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.muted,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppTheme.muted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationContent(
    BuildContext context,
    List<ChatConversation> rawConversations,
    bool isVendor,
  ) {
    // Include admin support in message history once chatting has started.
    final store = ref.watch(sharedMessagingStoreProvider);
    final allConversations = rawConversations.where((c) {
      if (c.isAdminSupport) {
        return store.hasStartedChatting(c.id);
      }
      return true;
    }).toList();

    // 1. Filter counts
    final allCount = allConversations.length;
    final unreadCount = allConversations
        .where((c) => isVendor ? c.hasUnreadForVendor() : c.hasUnreadForCustomer())
        .length;
    final ordersCount = allConversations
        .where((c) => c.relatedOrderId != null || c.inquiryType == 'order')
        .length;

    // 2. Active Tab Filtering
    List<ChatConversation> filteredList = allConversations.where((c) {
      if (_selectedFilter == MessageFilter.unread) {
        return isVendor ? c.hasUnreadForVendor() : c.hasUnreadForCustomer();
      }
      if (_selectedFilter == MessageFilter.orders) {
        return c.relatedOrderId != null || c.inquiryType == 'order';
      }
      return true;
    }).toList();

    // 3. Search Query Filtering
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filteredList = filteredList.where((c) {
        final name = (isVendor ? c.customerName : c.stallName).toLowerCase();
        final text = c.lastMessageText.toLowerCase();
        final orderId = c.relatedOrderId?.toLowerCase() ?? '';
        return name.contains(q) || text.contains(q) || orderId.contains(q);
      }).toList();
    }

    return Column(
      children: [
        // Filter Chips Row
        MessagesFilterChips(
          selectedFilter: _selectedFilter,
          allCount: allCount,
          unreadCount: unreadCount,
          ordersCount: ordersCount,
          onSelected: (filter) {
            setState(() => _selectedFilter = filter);
          },
        ),
        const SizedBox(height: 8),
        // Conversation List or Empty State
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.primaryGreen,
            onRefresh: () async {
              ref.invalidate(vendorConversationsProvider);
              ref.invalidate(customerConversationsProvider);
            },
            child: filteredList.isEmpty
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.45,
                      child: Center(
                        child: _buildEmptyState(isVendor),
                      ),
                    ),
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      final conv = filteredList[index];
                      return ConversationCard(
                        conversation: conv,
                        isVendorView: isVendor,
                        onTap: () {
                          Navigator.of(context).push(
                            PageTransitions.slideFromRight(
                              ChatScreen(
                                conversationId: conv.id,
                                displayName: isVendor
                                    ? conv.customerName
                                    : conv.stallName,
                                isVendorView: isVendor,
                                stallId: conv.stallId,
                                avatarUrl: isVendor
                                    ? conv.customerAvatar
                                    : conv.stallAvatar,
                                inquiryType: conv.inquiryType,
                                relatedOrderId: conv.relatedOrderId,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isVendor) {
    String title;
    String subtitle;
    IconData icon;

    if (_searchQuery.isNotEmpty) {
      title = 'No results found';
      subtitle = 'No conversations match "$_searchQuery"';
      icon = Icons.search_off_rounded;
    } else if (_selectedFilter == MessageFilter.unread) {
      title = 'No unread messages';
      subtitle = 'You are all caught up on your conversations.';
      icon = Icons.mark_chat_read_outlined;
    } else if (_selectedFilter == MessageFilter.orders) {
      title = 'No order messages';
      subtitle = isVendor
          ? 'No conversations linked to customer orders.'
          : 'No conversations linked to your orders.';
      icon = Icons.receipt_long_outlined;
    } else {
      title = 'No messages yet';
      subtitle = isVendor
          ? 'Customer questions and order updates will appear here.'
          : 'Your conversations with stall holders will appear here.';
      icon = Icons.chat_bubble_outline_rounded;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppTheme.primaryGreen, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
