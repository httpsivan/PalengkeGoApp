import 'package:flutter/material.dart';
import 'package:palengkego/core/navigation/app_routes.dart';
import 'package:palengkego/core/theme/app_theme.dart';

/// Bottom action section with the pill-shaped Register Account button
/// and the "Already have an account? Log In" link, matching LoginScreen.
class RegistrationBottomActionBar extends StatefulWidget {
  final bool isLoading;
  final VoidCallback onRegister;

  const RegistrationBottomActionBar({
    super.key,
    required this.isLoading,
    required this.onRegister,
  });

  @override
  State<RegistrationBottomActionBar> createState() =>
      _RegistrationBottomActionBarState();
}

class _RegistrationBottomActionBarState
    extends State<RegistrationBottomActionBar> {
  bool _btnPressed = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Listener(
          onPointerDown: (_) {
            if (!widget.isLoading) setState(() => _btnPressed = true);
          },
          onPointerUp: (_) {
            if (_btnPressed) setState(() => _btnPressed = false);
          },
          onPointerCancel: (_) {
            if (_btnPressed) setState(() => _btnPressed = false);
          },
          child: AnimatedScale(
            scale: _btnPressed ? 0.98 : 1.0,
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
                onPressed: widget.isLoading ? null : widget.onRegister,
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
                child: widget.isLoading
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
                            'Register Account',
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
        ),
        const SizedBox(height: 22),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushNamedAndRemoveUntil(
                AppRoutes.login,
                (route) => false,
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Center(
              child: RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                  children: [
                    TextSpan(
                      text: 'Already have an account? ',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextSpan(
                      text: 'Log In',
                      style: TextStyle(
                        color: AppTheme.primaryGreen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
