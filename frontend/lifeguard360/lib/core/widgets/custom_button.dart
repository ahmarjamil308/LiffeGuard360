import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum ButtonVariant { emergency, safe, neutral, outline }

/// Reusable safety action button with loading and icon states.
class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final ButtonVariant variant;
  final IconData? icon;
  final double height;
  final double? width;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.variant = ButtonVariant.emergency,
    this.icon,
    this.height = 50,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    BorderSide? border;

    switch (variant) {
      case ButtonVariant.emergency:
        bg = AppTheme.emergencyRed;
        fg = Colors.white;
        break;
      case ButtonVariant.safe:
        bg = AppTheme.safeEmerald;
        fg = Colors.white;
        break;
      case ButtonVariant.neutral:
        bg = AppTheme.deepSlate;
        fg = AppTheme.textPrimary;
        border = const BorderSide(color: AppTheme.slateBorder);
        break;
      case ButtonVariant.outline:
        bg = Colors.transparent;
        fg = AppTheme.textPrimary;
        border = const BorderSide(color: AppTheme.slateBorder, width: 1.5);
        break;
    }

    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      elevation: variant == ButtonVariant.outline ? 0 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: border ?? BorderSide.none,
      ),
    );

    return SizedBox(
      height: height,
      width: width ?? double.infinity,
      child: ElevatedButton(
        style: buttonStyle,
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: fg),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: fg,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
