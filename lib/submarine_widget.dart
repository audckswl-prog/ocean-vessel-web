import 'dart:math';

import 'package:flutter/material.dart';

class Submarine extends StatelessWidget {
  final Animation<double> animation;
  final bool isDashing;
  final double rotationY;

  const Submarine({
    super.key,
    required this.animation,
    this.isDashing = false,
    this.rotationY = 0,
  });

  @override
  Widget build(BuildContext context) {
    // The bobble animation is preserved from the original animation controller.
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        // The bobble effect (up and down movement)
        final bobble = sin(animation.value * 2 * pi) * 5;
        
        // The rotation effect is preserved
        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001) // perspective
            ..rotateY(rotationY)
            ..translate(0.0, bobble, 0.0), // Apply bobble effect
          alignment: FractionalOffset.center,
          child: Image.asset(
            'assets/images/new_submarine.png',
            width: 192,
            height: 192,
            fit: BoxFit.contain,
            gaplessPlayback: true, // Prevents image from disappearing on hot reload
          ),
        );
      },
    );
  }
}
