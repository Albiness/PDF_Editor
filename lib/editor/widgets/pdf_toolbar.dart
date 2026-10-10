import 'package:flutter/material.dart';

class PdfToolbar extends StatelessWidget {
  final VoidCallback onText;
  final VoidCallback onSign;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onSave;

  const PdfToolbar({
    super.key,
    required this.onText,
    required this.onSign,
    required this.onUndo,
    required this.onRedo,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      color: Colors.black87,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(icon: Icon(Icons.text_fields,color: Colors.white), onPressed: onText),
          IconButton(icon: Icon(Icons.draw,color: Colors.white), onPressed: onSign),
          IconButton(icon: Icon(Icons.undo,color: Colors.white), onPressed: onUndo),
          IconButton(icon: Icon(Icons.redo,color: Colors.white), onPressed: onRedo),
          IconButton(icon: Icon(Icons.save,color: Colors.white), onPressed: onSave),
        ],
      ),
    );
  }
}