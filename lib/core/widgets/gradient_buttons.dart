import 'package:flutter/material.dart';

/// A full-width, pill-shaped button with a gradient fill — Flutter's
/// ButtonStyle can't express a gradient background, so primary actions
/// (Start/Stop) use this instead of FilledButton.
class GradientPillButton extends StatelessWidget {
  const GradientPillButton({
    super.key,
    required this.label,
    required this.icon,
    required this.gradient,
    required this.foregroundColor,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final List<Color> gradient;
  final Color foregroundColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(gradient: LinearGradient(colors: gradient)),
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: foregroundColor),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: foregroundColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
