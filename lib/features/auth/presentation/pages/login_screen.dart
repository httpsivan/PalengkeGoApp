import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:palengkego/core/infrastructure/supabase_service.dart';
import 'package:palengkego/core/navigation/app_routes.dart';
import 'package:palengkego/core/services/app_services.dart';
import 'package:palengkego/core/theme/app_theme.dart';
import 'package:palengkego/features/auth/application/auth_provider.dart';
import 'package:palengkego/features/auth/domain/app_user.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _loginBtnPressed = false;

  late final AnimationController _entranceCtrl;
  late final Animation<double> _heroFade;
  late final Animation<double> _heroScale;
  late final Animation<double> _contentFade;
  late final Animation<Offset> _contentSlide;

  @override
  void initState() {
    super.initState();
    _emailFocusNode.addListener(_onFocusChange);
    _passwordFocusNode.addListener(_onFocusChange);

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _heroFade = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
    );
    _heroScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.0, 0.70, curve: Curves.easeOutBack),
      ),
    );
    _contentFade = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.20, 1.0, curve: Curves.easeOut),
    );
    _contentSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.20, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    final isTest =
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (isTest) {
      _entranceCtrl.value = 1.0;
    } else {
      _entranceCtrl.forward();
    }
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _emailFocusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    _passwordFocusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text;
      await ref.read(authProvider.notifier).login(email, password);
      if (!mounted) return;
      _navigateByRole();
    } catch (e) {
      if (mounted) {
        AppServices.showAuthError(e);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      AppServices.showError('Enter your email first.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(email);
      if (mounted) {
        AppServices.showSnackBar(
          'Password reset link sent to your email. Check your inbox.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppServices.showAuthError(e);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _devLoginAs(UserRole role) async {
    setState(() => _isLoading = true);
    await ref.read(authProvider.notifier).loginAs(role);
    if (!mounted) return;
    setState(() => _isLoading = false);
    // Dev login: always go to the role's home, don't just pop to Guest
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = ref.read(authProvider);
      if (user?.isVendor == true) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.vendorDashboard,
          (route) => false,
        );
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.main,
          (route) => false,
        );
      }
    });
  }

  void _navigateByRole() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = ref.read(authProvider);
      if (user?.isVendor == true) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.vendorDashboard,
          (route) => false,
        );
        return;
      }

      if (Navigator.canPop(context)) {
        Navigator.pop(context, true);
        return;
      }

      // Default to Customer UI (Marketplace) upon logging in
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.main, (route) => false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSupabaseActive = ref.watch(supabaseClientProvider) != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FCFA),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Reuse existing onboarding botanical background asset
          const Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.75,
                child: Image(
                  image: AssetImage('assets/images/onboarding-background.png'),
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),

          // Subtle top-right & bottom-left leaf/wave accents matching reference
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _LoginCornerAccentsPainter(),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Dev bypass banner — only visible in offline/mock debug mode when Supabase/Firebase is not enabled
                if (kDebugMode && !isSupabaseActive)
                  Container(
                    width: double.infinity,
                    color: const Color(0xFF1E293B),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.code_rounded,
                            color: Color(0xFFF59E0B),
                            size: 14,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'DEV MODE —',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _devChip(
                            'Customer',
                            () => _devLoginAs(UserRole.customer),
                          ),
                          const SizedBox(width: 6),
                          _devChip(
                            'Stall Holder',
                            () => _devLoginAs(UserRole.vendor),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Scrollable responsive content
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompactHeight = constraints.maxHeight < 700;
                      final isNarrowWidth = constraints.maxWidth < 360;
                      final horizontalPadding = isNarrowWidth ? 20.0 : 24.0;
                      final basketHeight = isCompactHeight ? 124.0 : 148.0;

                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          isCompactHeight ? 12 : 18,
                          horizontalPadding,
                          24,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Back button
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: GestureDetector(
                                      key: const Key('login_back_button'),
                                      onTap: () {
                                        final user = ref.read(authProvider);
                                        if (user == null ||
                                            !Navigator.of(context).canPop()) {
                                          Navigator.of(context)
                                              .pushNamedAndRemoveUntil(
                                            AppRoutes.main,
                                            (route) => false,
                                          );
                                        } else {
                                          Navigator.of(context).pop();
                                        }
                                      },
                                      child: Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: const Color(0xFFE8F0EC),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppTheme.primaryGreen
                                                  .withValues(alpha: 0.08),
                                              blurRadius: 14,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        alignment: Alignment.center,
                                        child: SvgPicture.asset(
                                          'assets/icons/back button icon.svg',
                                          width: 17,
                                          height: 17,
                                          colorFilter: const ColorFilter.mode(
                                            AppTheme.primaryGreen,
                                            BlendMode.srcIn,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  SizedBox(height: isCompactHeight ? 4 : 8),

                                  // Welcome Section with existing splash/app basket logo & animation
                                  FadeTransition(
                                    opacity: _heroFade,
                                    child: ScaleTransition(
                                      scale: _heroScale,
                                      child: _WelcomeBasketHero(
                                        height: basketHeight,
                                      ),
                                    ),
                                  ),

                                  SizedBox(height: isCompactHeight ? 12 : 18),

                                  FadeTransition(
                                    opacity: _contentFade,
                                    child: SlideTransition(
                                      position: _contentSlide,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              'Welcome to PalengkeGo!',
                                              maxLines: 1,
                                              style: TextStyle(
                                                fontSize:
                                                    isNarrowWidth ? 24 : 28,
                                                fontWeight: FontWeight.w800,
                                                color: AppTheme.primaryGreen,
                                                height: 1.2,
                                                letterSpacing: -0.6,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Skip the roam, order from home.',
                                            style: TextStyle(
                                              fontSize:
                                                  isNarrowWidth ? 14 : 15.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppTheme.textSecondary,
                                              height: 1.4,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          SizedBox(
                                            height: isCompactHeight ? 24 : 32,
                                          ),

                                          // Email field
                                          _buildField(
                                            label: 'Email',
                                            hintText: 'Enter your email',
                                            prefixIcon: Icons.email_outlined,
                                            focusNode: _emailFocusNode,
                                            keyboardType:
                                                TextInputType.emailAddress,
                                            textInputAction:
                                                TextInputAction.next,
                                            controller: _emailController,
                                            // Strip spaces and force lowercase as the user types
                                            inputFormatters: [
                                              FilteringTextInputFormatter.deny(
                                                RegExp(r'\s'),
                                              ),
                                              _LowercaseFormatter(),
                                            ],
                                            validator: (v) {
                                              final val = (v ?? '').trim();
                                              if (val.isEmpty) {
                                                return 'Email is required';
                                              }
                                              final ok = RegExp(
                                                r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
                                              ).hasMatch(val);
                                              return ok
                                                  ? null
                                                  : 'Enter a valid email address';
                                            },
                                          ),
                                          SizedBox(
                                            height: isCompactHeight ? 14 : 18,
                                          ),

                                          // Password field
                                          _buildPasswordField(),
                                          const SizedBox(height: 10),

                                          // Forgot password
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton(
                                              onPressed: _handleForgotPassword,
                                              style: TextButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                  vertical: 2,
                                                ),
                                                minimumSize: Size.zero,
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                foregroundColor:
                                                    AppTheme.primaryGreen,
                                              ),
                                              child: const Text(
                                                'Forgot Password?',
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.primaryGreen,
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            height: isCompactHeight ? 18 : 22,
                                          ),

                                          // Login button
                                          _loginButton(),
                                          SizedBox(
                                            height: isCompactHeight ? 20 : 24,
                                          ),

                                          // Divider
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Container(
                                                  height: 1,
                                                  color:
                                                      const Color(0xFFE2E8F0),
                                                ),
                                              ),
                                              const Padding(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                ),
                                                child: Text(
                                                  'or continue with',
                                                  style: TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w500,
                                                    color: Color(0xFF64748B),
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Container(
                                                  height: 1,
                                                  color:
                                                      const Color(0xFFE2E8F0),
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(
                                            height: isCompactHeight ? 18 : 22,
                                          ),

                                          // Social Login Buttons
                                          _googleSignInButton(),
                                          SizedBox(
                                            height: isCompactHeight ? 20 : 26,
                                          ),

                                          // Register link
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              Navigator.of(context).pushNamed(
                                                AppRoutes.registration,
                                              );
                                            },
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 4,
                                              ),
                                              child: Center(
                                                child: RichText(
                                                  text: const TextSpan(
                                                    style: TextStyle(
                                                      fontSize: 14.5,
                                                      height: 1.4,
                                                    ),
                                                    children: [
                                                      TextSpan(
                                                        text:
                                                            "Don't have an account? ",
                                                        style: TextStyle(
                                                          color: Color(
                                                            0xFF64748B,
                                                          ),
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                      TextSpan(
                                                        text: 'Register',
                                                        style: TextStyle(
                                                          color: AppTheme
                                                              .primaryGreen,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _devChip(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF334155),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF475569)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildPrefixWithDivider(IconData icon, {required bool isFocused}) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 20,
            color: isFocused ? AppTheme.primaryGreen : const Color(0xFF64748B),
          ),
          const SizedBox(width: 12),
          Container(
            width: 1,
            height: 22,
            color: const Color(0xFFE2E8F0),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required String hintText,
    required IconData prefixIcon,
    FocusNode? focusNode,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    TextEditingController? controller,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    final isFocused = focusNode?.hasFocus ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryGreen.withValues(
                  alpha: isFocused ? 0.08 : 0.04,
                ),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextFormField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            inputFormatters: inputFormatters,
            validator: validator,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1E293B),
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: hintText,
              hintStyle: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w400,
                color: Color(0xFF64748B),
              ),
              prefixIcon: _buildPrefixWithDivider(
                prefixIcon,
                isFocused: isFocused,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 52,
                minHeight: 0,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: AppTheme.primaryGreen,
                  width: 1.5,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFFEF4444),
                  width: 1.2,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFFEF4444),
                  width: 1.5,
                ),
              ),
              errorStyle: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFFEF4444),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleGoogleSignIn({bool useAnotherAccount = false}) async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(authProvider.notifier)
          .signInWithGoogle(useAnotherAccount: useAnotherAccount);
      if (!mounted) return;
      _navigateByRole();
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      final msg = e.toString().toLowerCase();
      final isDismissed = msg.contains('cancelled') ||
          msg.contains('canceled') ||
          msg.contains('closed') ||
          msg.contains('popup_closed_by_user') ||
          msg.contains('web-context-cancelled');
      if (!isDismissed && mounted) {
        String displayMsg =
            'Google Sign-In was not completed. Please try again or use email sign-in.';
        if (msg.contains('missing-id-token') || msg.contains('id token')) {
          displayMsg =
              'Google Sign-In: Missing ID token. Please check your network and Google Play Services.';
        } else if (msg.contains('network') || msg.contains('connection')) {
          displayMsg =
              'Network error during Google Sign-In. Please check your internet connection.';
        } else if (e is GoogleSignInException &&
            e.description != null &&
            e.description!.isNotEmpty) {
          displayMsg = 'Google Sign-In: ${e.description}';
        }
        AppServices.showError(displayMsg);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showGoogleSignInSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Continue with Google',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select how you want to sign in:',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                ListTile(
                  leading: Container(
                    width: 42,
                    height: 42,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: SvgPicture.asset(
                      'assets/icons/google_icon.svg',
                    ),
                  ),
                  title: const Text(
                    kIsWeb
                        ? 'Continue with Saved Account'
                        : 'Saved Accounts on Device',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  subtitle: const Text(
                    kIsWeb
                        ? 'Quick sign-in using your active browser account'
                        : 'Use Google accounts saved on this phone',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Color(0xFF94A3B8),
                  ),
                  contentPadding: EdgeInsets.zero,
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleGoogleSignIn(useAnotherAccount: false);
                  },
                ),
                const Divider(height: 16, color: Color(0xFFF1F5F9)),
                ListTile(
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: AppTheme.primaryGreen,
                      size: 22,
                    ),
                  ),
                  title: const Text(
                    'Add / Use Another Account',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  subtitle: const Text(
                    kIsWeb
                        ? 'Pick or sign into another Google account'
                        : 'Sign in with a different Gmail address',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Color(0xFF94A3B8),
                  ),
                  contentPadding: EdgeInsets.zero,
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleGoogleSignIn(useAnotherAccount: true);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _googleSignInButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B372B).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _isLoading ? null : _showGoogleSignInSheet,
          borderRadius: BorderRadius.circular(16),
          splashColor: AppTheme.surfaceContainerLow,
          highlightColor: AppTheme.surface,
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  'assets/icons/google_icon.svg',
                  width: 22,
                  height: 22,
                ),
                const SizedBox(width: 12),
                const Flexible(
                  child: Text(
                    'Continue with Google',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    final isFocused = _passwordFocusNode.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Password',
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryGreen.withValues(
                  alpha: isFocused ? 0.08 : 0.04,
                ),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextFormField(
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) {
              if (!_isLoading) _handleLogin();
            },
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1E293B),
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: 'Enter your password',
              hintStyle: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w400,
                color: Color(0xFF64748B),
              ),
              prefixIcon: _buildPrefixWithDivider(
                Icons.lock_outline_rounded,
                isFocused: isFocused,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 52,
                minHeight: 0,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: const Color(0xFF64748B),
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: AppTheme.primaryGreen,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _loginButton() {
    return Listener(
      onPointerDown: (_) {
        if (!_isLoading) setState(() => _loginBtnPressed = true);
      },
      onPointerUp: (_) {
        if (_loginBtnPressed) setState(() => _loginBtnPressed = false);
      },
      onPointerCancel: (_) {
        if (_loginBtnPressed) setState(() => _loginBtnPressed = false);
      },
      child: AnimatedScale(
        scale: _loginBtnPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryGreen.withValues(alpha: 0.28),
                offset: const Offset(0, 8),
                blurRadius: 18,
                spreadRadius: -4,
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              disabledBackgroundColor:
                  AppTheme.primaryGreen.withValues(alpha: 0.5),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.0,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Log In',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(width: 10),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Reuses the existing splash basket logo (`assets/images/palengkego-logo.png`)
/// with the soft grocery-themed organic backdrop and floating leaf accents.
class _WelcomeBasketHero extends StatelessWidget {
  const _WelcomeBasketHero({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final width = height * 1.55;
    return Center(
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Soft organic mint backdrop + floating leaves
            Positioned.fill(
              child: CustomPaint(
                painter: _BasketBackdropPainter(),
              ),
            ),
            // Existing splash screen logo asset (toned down so it's not overly bright)
            Hero(
              tag: 'palengkego_splash_logo',
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix(
                  <double>[
                    0.85, 0, 0, 0, 0,
                    0, 0.85, 0, 0, 0,
                    0, 0, 0.85, 0, 0,
                    0, 0, 0, 1, 0,
                  ],
                ),
                child: Image.asset(
                  'assets/images/palengkego-logo.png',
                  height: height * 0.92,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Soft pastel green organic blob and floating leaves behind the grocery basket.
class _BasketBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Soft pastel mint organic shape behind the basket
    final blobPaint = Paint()
      ..color = const Color(0xFFE6F4EC)
      ..style = PaintingStyle.fill;

    final blobPath = Path()
      ..moveTo(w * 0.16, h * 0.65)
      ..cubicTo(w * 0.06, h * 0.42, w * 0.20, h * 0.10, w * 0.46, h * 0.12)
      ..cubicTo(w * 0.68, h * 0.13, w * 0.88, h * 0.26, w * 0.86, h * 0.56)
      ..cubicTo(w * 0.85, h * 0.82, w * 0.94, h * 0.90, w * 0.72, h * 0.92)
      ..cubicTo(w * 0.48, h * 0.94, w * 0.10, h * 0.95, w * 0.12, h * 0.76)
      ..cubicTo(w * 0.13, h * 0.70, w * 0.18, h * 0.68, w * 0.16, h * 0.65)
      ..close();
    canvas.drawPath(blobPath, blobPaint);

    // Subtle ground shadow beneath basket
    final shadowPaint = Paint()
      ..color = AppTheme.primaryGreen.withValues(alpha: 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.88),
        width: w * 0.52,
        height: h * 0.10,
      ),
      shadowPaint,
    );

    // Floating decorative leaf (left-upper)
    final leafPaint = Paint()
      ..color = const Color(0xFF68B64C).withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;

    final leftLeaf = Path()
      ..moveTo(w * 0.15, h * 0.52)
      ..quadraticBezierTo(w * 0.06, h * 0.44, w * 0.07, h * 0.34)
      ..quadraticBezierTo(w * 0.16, h * 0.38, w * 0.15, h * 0.52)
      ..close();
    canvas.drawPath(leftLeaf, leafPaint);

    // Floating decorative leaf (right-middle)
    final rightLeaf = Path()
      ..moveTo(w * 0.83, h * 0.66)
      ..quadraticBezierTo(w * 0.92, h * 0.62, w * 0.95, h * 0.50)
      ..quadraticBezierTo(w * 0.85, h * 0.52, w * 0.83, h * 0.66)
      ..close();
    canvas.drawPath(rightLeaf, leafPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Subtle corner botanical waves and leaves matching the reference design.
class _LoginCornerAccentsPainter extends CustomPainter {
  const _LoginCornerAccentsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final wavePaint = Paint()
      ..color = const Color(0xFFE6F3EB).withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;

    // Top-right soft organic wave
    final topRightWave = Path()
      ..moveTo(w * 0.67, 0)
      ..quadraticBezierTo(w * 0.72, h * 0.06, w * 0.84, h * 0.08)
      ..quadraticBezierTo(w * 0.94, h * 0.10, w, h * 0.17)
      ..lineTo(w, 0)
      ..close();
    canvas.drawPath(topRightWave, wavePaint);

    // Bottom-left soft organic wave
    final bottomLeftWave = Path()
      ..moveTo(0, h * 0.88)
      ..quadraticBezierTo(w * 0.10, h * 0.92, w * 0.26, h * 0.95)
      ..quadraticBezierTo(w * 0.38, h * 0.97, w * 0.44, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(bottomLeftWave, wavePaint);

    // Top-right decorative soft leaves
    final leafPaint = Paint()
      ..color = const Color(0xFF9AC58E).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    final topLeaf1 = Path()
      ..moveTo(w, 0)
      ..quadraticBezierTo(w * 0.88, h * 0.01, w * 0.87, h * 0.065)
      ..quadraticBezierTo(w * 0.95, h * 0.055, w, h * 0.02)
      ..close();
    canvas.drawPath(topLeaf1, leafPaint);

    final topLeaf2 = Path()
      ..moveTo(w, h * 0.015)
      ..quadraticBezierTo(w * 0.93, h * 0.045, w * 0.94, h * 0.095)
      ..quadraticBezierTo(w * 0.99, h * 0.075, w, h * 0.045)
      ..close();
    canvas.drawPath(topLeaf2, leafPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Forces all typed characters to lowercase — used on email fields.
class _LowercaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toLowerCase());
}
