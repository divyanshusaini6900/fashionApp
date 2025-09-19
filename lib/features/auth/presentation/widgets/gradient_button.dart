import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class GradientButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final Gradient gradient;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final List<BoxShadow>? boxShadow;

  const GradientButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.gradient = AppColors.buttonGradient,
    this.borderRadius,
    this.padding,
    this.width,
    this.height,
    this.boxShadow,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.8,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onPressed != null) {
      _animationController.forward();
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onPressed != null) {
      _animationController.reverse();
    }
  }

  void _onTapCancel() {
    _animationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.onPressed,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(
              opacity: widget.onPressed == null ? 0.6 : _opacityAnimation.value,
              child: Container(
                width: widget.width ?? double.infinity,
                height: widget.height ?? 56,
                padding: widget.padding ??
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                decoration: BoxDecoration(
                  gradient: widget.onPressed == null
                      ? LinearGradient(
                          colors: [
                            AppColors.grey.withOpacity(0.5),
                            AppColors.grey.withOpacity(0.7),
                          ],
                        )
                      : widget.gradient,
                  borderRadius: widget.borderRadius ?? BorderRadius.circular(16),
                  boxShadow: widget.onPressed == null
                      ? null
                      : widget.boxShadow ??
                          [
                            BoxShadow(
                              color: AppColors.primaryBlue.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                ),
                child: Center(child: widget.child),
              ),
            ),
          );
        },
      ),
    );
  }
}