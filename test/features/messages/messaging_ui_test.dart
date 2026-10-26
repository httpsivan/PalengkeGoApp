import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:palengkego/core/services/preferences_provider.dart';
import 'package:palengkego/features/auth/application/auth_provider.dart';
import 'package:palengkego/features/auth/domain/app_user.dart';
import 'package:palengkego/features/messages/data/shared_messaging_store.dart';
import 'package:palengkego/features/messages/presentation/pages/chat_screen.dart';
import 'package:palengkego/features/messages/presentation/pages/messages_inbox_screen.dart';
import 'package:palengkego/features/messages/presentation/widgets/conversation_card.dart';
import 'package:palengkego/features/vendors/presentation/widgets/dashboard_bottom_nav.dart';
import 'package:palengkego/features/messages/domain/chat_message.dart';
import 'package:palengkego/features/messages/presentation/widgets/chat_bubble.dart';
import 'package:palengkego/features/home/presentation/widgets/home_header.dart';
import 'package:palengkego/features/vendors/presentation/pages/vendor_account_screen.dart';
import 'package:palengkego/features/vendors/presentation/pages/vendor_profile_screen.dart';
import 'package:palengkego/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNotificationsPlatform extends FlutterLocalNotificationsPlatform {}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(this.initialUser);
  final AppUser? initialUser;
  @override
  AppUser? build() => initialUser;
}

void main() {
  late SharedPreferences prefs;
  late SharedMessagingStore messagingStore;

  setUp(() async {
    FlutterLocalNotificationsPlatform.instance = _FakeNotificationsPlatform();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    messagingStore = SharedMessagingStore();
    await messagingStore.load();
  });

  Widget wrap(Widget child, {AppUser? user}) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authProvider.overrideWith(() => _TestAuthNotifier(user ?? MockUsers.vendor)),
        sharedMessagingStoreProvider.overrideWithValue(messagingStore),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  group('VendorDashboardBottomNav', () {
    testWidgets('renders all 5 tabs including Messages with badge', (tester) async {
      int selected = 0;
      await tester.pumpWidget(
        wrap(
          VendorDashboardBottomNav(
            selectedIndex: selected,
            onSelect: (index) => selected = index,
            unreadCount: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // badge count
    });
  });

  group('MessagesInboxScreen', () {
    testWidgets('displays header, search bar, filter chips and conversation cards', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const MessagesInboxScreen(isEmbeddedInTab: true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Search messages, customers, or orders...'), findsOneWidget);
      expect(find.text('All (12)'), findsOneWidget);
      expect(find.text('Unread (2)'), findsOneWidget);
      expect(find.text('Orders (5)'), findsOneWidget);
      expect(find.byType(ConversationCard), findsWidgets);
      expect(find.text('Ana Santos'), findsOneWidget);
      expect(find.text('Mark Dela Cruz'), findsOneWidget);
    });

    testWidgets('filtering by Unread displays only unread conversations', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const MessagesInboxScreen(isEmbeddedInTab: true)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Unread (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Ana Santos'), findsOneWidget);
      expect(find.text('Mark Dela Cruz'), findsOneWidget);
      expect(find.text('Liza Reyes'), findsNothing);
    });

    testWidgets('search filters conversations by name', (tester) async {
      await tester.pumpWidget(
        wrap(const MessagesInboxScreen(isEmbeddedInTab: true)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Ana');
      await tester.pumpAndSettle();

      expect(find.text('Ana Santos'), findsOneWidget);
      expect(find.text('Mark Dela Cruz'), findsNothing);
    });

    testWidgets('customer view displays stall holder conversation history', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const MessagesInboxScreen(
            isEmbeddedInTab: false,
            isVendorView: false,
          ),
          user: MockUsers.customer,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Search messages, stalls, or orders...'), findsOneWidget);
      expect(find.text("Aling Nena's Fresh Gulay"), findsOneWidget);
      expect(find.text("Pedro's Fresh Catch"), findsOneWidget);
      expect(find.text('All (2)'), findsOneWidget);
      expect(find.text('Unread (1)'), findsOneWidget);
    });

    testWidgets(
      'displays admin support icon in header without notification bell and opens chat on tap',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            const MessagesInboxScreen(
              isEmbeddedInTab: false,
              isVendorView: true,
            ),
            user: MockUsers.vendor,
          ),
        );
        await tester.pumpAndSettle();

        // Notification bell should NOT be present on MessagesInboxScreen
        expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
        expect(find.byIcon(Icons.notifications_outlined), findsNothing);
        expect(find.byIcon(Icons.notifications), findsNothing);

        // Admin messaging icon should be present in the header
        final adminButton = find.byIcon(Icons.support_agent_rounded);
        expect(adminButton, findsOneWidget);

        // Tapping admin messaging icon should open Admin ChatScreen
        await tester.tap(adminButton);
        await tester.pumpAndSettle();

        expect(find.text('PalengkeGo Admin'), findsOneWidget);
        expect(find.text('Official Admin Support'), findsOneWidget);
        expect(find.text('Direct Admin Support Channel'), findsOneWidget);
      },
    );

    testWidgets(
      'excludes PalengkeGo Admin conversation from inbox history list and accesses it via header button',
      (tester) async {
        // Create an admin conversation with welcome message history
        await messagingStore.getOrCreateConversation(
          customerUid: 'admin_support',
          customerName: 'PalengkeGo Admin',
          stallId: 'v1',
          stallName: "Mer's Mayao Fruit Stand",
          inquiryType: 'admin_support',
        );

        // Also add customer conversations
        await messagingStore.getOrCreateConversation(
          customerUid: 'cust_ivan',
          customerName: 'Ivan Navarro',
          stallId: 'v1',
          stallName: "Mer's Mayao Fruit Stand",
          inquiryType: 'product',
        );

        await tester.pumpWidget(
          wrap(
            const MessagesInboxScreen(
              isEmbeddedInTab: false,
              isVendorView: true,
            ),
            user: MockUsers.vendor,
          ),
        );
        await tester.pumpAndSettle();

        // The vendor message history list MUST contain the customer, but NOT PalengkeGo Admin card
        expect(find.text('Ivan Navarro'), findsOneWidget);
        expect(find.text('Hello! How can the PalengkeGo Admin team help you today? Please feel free to leave any inquiries, reports, or support questions here.'), findsNothing);

        // Tap the headset icon to access Admin chat directly
        final adminButton = find.byKey(const Key('messages_admin_chat_button'));
        expect(adminButton, findsOneWidget);
        await tester.tap(adminButton);
        await tester.pumpAndSettle();

        // Inside Admin ChatScreen, PalengkeGo Admin and its message history appear
        expect(find.text('PalengkeGo Admin'), findsOneWidget);
        expect(find.text('Hello! How can the PalengkeGo Admin team help you today? Please feel free to leave any inquiries, reports, or support questions here.'), findsOneWidget);

        // Admin profile must use default profile (Icons.support_agent_rounded), not a picture
        expect(find.byIcon(Icons.support_agent_rounded), findsWidgets);
      },
    );
  });

  group('Customer HomeHeader Messages Icon', () {
    testWidgets(
      'places Messages icon to the left of Notification Bell and navigates to customer inbox',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            const Scaffold(
              body: HomeHeader(),
            ),
            user: MockUsers.customer,
          ),
        );
        await tester.pumpAndSettle();

        final messagesButton = find.byKey(const Key('home_header_messages_button'));
        final notificationsButton = find.byKey(
          const Key('home_header_notifications_button'),
        );

        expect(messagesButton, findsOneWidget);
        expect(notificationsButton, findsOneWidget);

        // Verify Messages icon is positioned directly to the left of Notification Bell
        final messagesCenter = tester.getCenter(messagesButton);
        final notificationsCenter = tester.getCenter(notificationsButton);
        expect(messagesCenter.dx, lessThan(notificationsCenter.dx));

        // Tapping Messages icon opens the Customer Messages History inbox
        await tester.tap(messagesButton);
        await tester.pumpAndSettle();

        expect(find.text("Aling Nena's Fresh Gulay"), findsOneWidget);
        expect(find.text("Pedro's Fresh Catch"), findsOneWidget);
      },
    );
  });

  group('ChatScreen', () {
    testWidgets('renders chat messages, header and composer', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ChatScreen(
            conversationId: 'conv_ana_santos',
            displayName: 'Ana Santos',
            isVendorView: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ana Santos'), findsOneWidget);
      expect(find.text('Type a message...'), findsOneWidget);
      expect(find.textContaining('Available pa po ba'), findsOneWidget);
    });

    testWidgets('sending message adds it to conversation', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ChatScreen(
            conversationId: 'conv_ana_santos',
            displayName: 'Ana Santos',
            isVendorView: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Bagong bagsak po kanina!');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Bagong bagsak po kanina!'), findsOneWidget);
    });

    testWidgets('tapping attachment button opens source sheet with camera and gallery', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ChatScreen(
            conversationId: 'conv_ana_santos',
            displayName: 'Ana Santos',
            isVendorView: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final attachButton = find.byKey(const Key('chat_attachment_button'));
      expect(attachButton, findsOneWidget);

      await tester.tap(attachButton);
      await tester.pumpAndSettle();

      expect(find.text('Attach Photo'), findsOneWidget);
      expect(find.text('Take Photo (Camera)'), findsOneWidget);
      expect(find.text('Choose from Gallery (Photos)'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Close bottom sheet
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Attach Photo'), findsNothing);
    });

    testWidgets('ChatBubble renders message with photo attachment', (tester) async {
      const fakeDataUri = 'data:image/jpeg;base64,/9j/4AAQSkZJRg==';
      final photoMessage = ChatMessage(
        id: 'msg_photo_test',
        conversationId: 'conv_ana_santos',
        senderId: 'cust_ana_santos',
        senderName: 'Ana Santos',
        senderRole: 'customer',
        text: 'Eto po ba yung available?',
        timestamp: DateTime.now(),
        attachmentUrl: fakeDataUri,
        attachmentType: 'image',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              message: photoMessage,
              isOutgoing: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Eto po ba yung available?'), findsOneWidget);
      expect(find.byIcon(Icons.zoom_in_rounded), findsOneWidget);
    });

    testWidgets('ChatBubble displays time without date', (tester) async {
      final msg = ChatMessage(
        id: 'msg_time_test',
        conversationId: 'conv_ana_santos',
        senderId: 'cust_ana_santos',
        senderName: 'Ana Santos',
        senderRole: 'customer',
        text: 'Kumusta',
        timestamp: DateTime(2026, 10, 25, 15, 43),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              message: msg,
              isOutgoing: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('3:43 PM'), findsOneWidget);
      expect(find.textContaining('Oct 25'), findsNothing);
    });

    testWidgets(
        'ChatBubble omits date and time for PalengkeGo Admin welcome greeting',
        (tester) async {
      final welcomeMsg = ChatMessage(
        id: 'msg_admin_welcome_123',
        conversationId: 'conv_admin_support_channel',
        senderId: 'admin_support',
        senderName: 'PalengkeGo Admin',
        senderRole: 'admin',
        text:
            'Hello! How can the PalengkeGo Admin team help you today? Please feel free to leave any inquiries, reports, or support questions here.',
        timestamp: DateTime(2026, 10, 25, 22, 25),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              message: welcomeMsg,
              isOutgoing: false,
            ),
          ),
        ),
      );
      await tester.pump();

      // Welcome text is present
      expect(
        find.text(
            'Hello! How can the PalengkeGo Admin team help you today? Please feel free to leave any inquiries, reports, or support questions here.'),
        findsOneWidget,
      );
      // Date and time are omitted
      expect(find.text('10:25 PM'), findsNothing);
      expect(find.textContaining('Oct 25'), findsNothing);
    });

    testWidgets(
        'ChatScreen omits date header for welcome message, starts date and time when user chats, and saves conversation',
        (tester) async {
      final store = SharedMessagingStore();
      await store.load();

      final adminConv = await store.getOrCreateConversation(
        customerUid: 'customer-001',
        customerName: 'Maria Santos',
        stallId: 'admin_support',
        stallName: 'PalengkeGo Admin',
        inquiryType: 'admin_support',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedMessagingStoreProvider.overrideWithValue(store),
          ],
          child: MaterialApp(
            home: ChatScreen(
              conversationId: adminConv.id,
              displayName: 'PalengkeGo Admin',
              isVendorView: false,
              inquiryType: 'admin_support',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Welcome message is visible
      expect(
        find.text(
            'Hello! How can the PalengkeGo Admin team help you today? Please feel free to leave any inquiries, reports, or support questions here.'),
        findsOneWidget,
      );

      // Date badge header above welcome message is omitted
      expect(find.textContaining('TODAY'), findsNothing);
      expect(find.textContaining('AT'), findsNothing);

      // Now user starts chatting
      final inputField = find.byType(TextField);
      expect(inputField, findsOneWidget);
      await tester.enterText(inputField, 'Hello Admin, I need assistance');
      await tester.pump();

      final sendButton = find.byIcon(Icons.send_rounded);
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      // Allow automated admin reply 600ms timer to complete
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      // Now date header starts because user started chatting
      expect(find.textContaining('TODAY'), findsOneWidget);
      expect(find.text('Hello Admin, I need assistance'), findsOneWidget);

      // Verify conversation is saved and registered in store conversations list
      expect(store.hasStartedChatting(adminConv.id), isTrue);
      expect(store.conversations.any((c) => c.id == adminConv.id), isTrue);
    });
  });

  group('VendorAccountScreen (Profile)', () {
    testWidgets('displays Customer Messages card with unread badge', (tester) async {
      await tester.pumpWidget(wrap(const VendorAccountScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Customer Messages'), findsOneWidget);
      expect(
        find.text('Reply to customer inquiries and order concerns'),
        findsOneWidget,
      );
      expect(find.text('2'), findsWidgets); // unread badge count
    });
  });

  group('Customer Stall Detail Screen', () {
    testWidgets('displays Chat with Stall Holder button', (tester) async {
      await tester.pumpWidget(
        wrap(
          const VendorProfileScreen(vendorId: 'v1'),
          user: MockUsers.customer,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Chat with Stall Holder'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
