import 'dart:ui';

enum AnnotationType { text, signature }

class Annotation {
  AnnotationType type;
  Offset position;
  double scale;
  double rotation;
  String? text;

  Annotation({
    required this.type,
    required this.position,
    this.scale = 1,
    this.rotation = 0,
    this.text,
  });

  Annotation copy() => Annotation(
        type: type,
        position: position,
        scale: scale,
        rotation: rotation,
        text: text,
      );
}