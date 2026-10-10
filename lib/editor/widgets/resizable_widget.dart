import 'package:flutter/material.dart';

class ResizableWidget extends StatefulWidget {
  final Widget child;
  const ResizableWidget({required this.child, super.key});

  @override
  State<ResizableWidget> createState() =>
      _ResizableWidgetState();
}

class _ResizableWidgetState
    extends State<ResizableWidget> {

  double scale = 1;
  double rotation = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleUpdate: (details) {
        setState(() {
          scale = details.scale;
          rotation = details.rotation;
        });
      },
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..scale(scale)
          ..rotateZ(rotation),
        child: widget.child,
      ),
    );
  }
}