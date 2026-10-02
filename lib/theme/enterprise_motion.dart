import 'package:flutter/material.dart';

/// Short, restrained transitions with an accessible reduced-motion fallback.
class EnterprisePageTransitions extends PageTransitionsBuilder {
  const EnterprisePageTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondaryAnimation,
      Widget child) {
    final media = MediaQuery.maybeOf(context);
    if (media?.disableAnimations == true || media?.accessibleNavigation == true) {
      return child;
    }
    final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: curved.drive(Tween<Offset>(
          begin: const Offset(0, 0.025), end: Offset.zero)),
        child: child,
      ),
    );
  }
}
