import '../models/annotation.dart';

class EditorController {

  List<Annotation> annotations = [];

  final List<List<Annotation>> _history = [];
  int _index = -1;

  void add(Annotation a) {
    _saveState();
    annotations.add(a);
  }

  void undo() {
    if (_index <= 0) return;
    _index--;
    annotations =
        _history[_index].map((e) => e.copy()).toList();
  }

  void redo() {
    if (_index >= _history.length - 1) return;
    _index++;
    annotations =
        _history[_index].map((e) => e.copy()).toList();
  }

  void _saveState() {
    _history.add(
        annotations.map((e) => e.copy()).toList());
    _index++;
  }
}