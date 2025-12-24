// lib/widgets/profile_avatar.dart
import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  final String fullName;
  final double size;
  final Color? textColor;
  final bool showShadow;
  final Color? backgroundColor;
  final Gradient? gradient;

  const ProfileAvatar({
    super.key,
    required this.fullName,
    this.size = 40,
    this.textColor,
    this.showShadow = true,
    this.backgroundColor,
    this.gradient,
  });

  String _getInitials() {
    final names = fullName.trim().split(' ');
    if (names.isEmpty) return '';
    if (names.length == 1) return names[0][0].toUpperCase();
    return (names[0][0] + names[names.length - 1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final txtColor = textColor ?? Colors.white;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        gradient:
            gradient ??
            (backgroundColor == null
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.amber[400]!, Colors.orange[600]!],
                  )
                : null),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.orange.withAlpha(77),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          _getInitials(),
          style: TextStyle(
            color: txtColor,
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
