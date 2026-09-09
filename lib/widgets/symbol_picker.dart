import 'package:flutter/material.dart';
import '../app_theme.dart';

/// Выпадающий список монет с поиском для одиночного выбора.
/// Открывает диалог с фильтром, как в мульти-поиске, но без галочек.
class SymbolDropdownField extends StatefulWidget {
  final String label;
  final String value;
  final List<String> symbols;
  final ValueChanged<String> onSelected;

  const SymbolDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.symbols,
    required this.onSelected,
  });

  @override
  State<SymbolDropdownField> createState() => _SymbolDropdownFieldState();
}

class _SymbolDropdownFieldState extends State<SymbolDropdownField> {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _openDialog,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: 'Нажмите, чтобы выбрать',
          suffixIcon: widget.symbols.isNotEmpty
              ? const Icon(Icons.arrow_drop_down, color: AppTheme.muted)
              : null,
        ),
        child: Text(
          widget.value.isEmpty ? 'Выберите монету' : widget.value,
          style: AppTheme.body(),
        ),
      ),
    );
  }

  Future<void> _openDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _SingleSelectDialog(
        all: widget.symbols,
        selected: widget.value,
      ),
    );
    if (result != null && result.isNotEmpty) {
      widget.onSelected(result.toUpperCase());
    }
  }
}

class _SingleSelectDialog extends StatefulWidget {
  final List<String> all;
  final String selected;

  const _SingleSelectDialog({required this.all, required this.selected});

  @override
  State<_SingleSelectDialog> createState() => __SingleSelectDialogState();
}

class __SingleSelectDialogState extends State<_SingleSelectDialog> {
  final _queryCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _query.isEmpty
        ? widget.all
        : widget.all.where((s) => s.toUpperCase().contains(_query.toUpperCase())).toList();

    return AlertDialog(
      backgroundColor: AppTheme.card,
      title: Text('Выбор монеты', style: AppTheme.title()),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _queryCtrl,
              onChanged: (s) => setState(() => _query = s),
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'Поиск...',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final s = items[i];
                  final isSelected = widget.selected.toUpperCase() == s.toUpperCase();
                  return ListTile(
                    dense: true,
                    title: Text(s, style: AppTheme.body()),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: AppTheme.accent, size: 20)
                        : null,
                    onTap: () => Navigator.of(context).pop(s),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
      ],
    );
  }
}

/// Поле ввода символа с автодополнением: можно выбрать из списка
/// или ввести вручную. Подходит для одиночного выбора.
class SymbolAutocompleteField extends StatefulWidget {
  final String label;
  final String value;
  final List<String> symbols;
  final ValueChanged<String> onSelected;

  const SymbolAutocompleteField({
    super.key,
    required this.label,
    required this.value,
    required this.symbols,
    required this.onSelected,
  });

  @override
  State<SymbolAutocompleteField> createState() => _SymbolAutocompleteFieldState();
}

class _SymbolAutocompleteFieldState extends State<SymbolAutocompleteField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.value;
  }

  @override
  void didUpdateWidget(covariant SymbolAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: _controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        final q = value.text.toUpperCase();
        if (q.isEmpty) return widget.symbols;
        return widget.symbols.where((s) => s.toUpperCase().contains(q));
      },
      onSelected: (s) {
        _controller.text = s;
        widget.onSelected(s);
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: AppTheme.card,
            elevation: 4,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (ctx, i) {
                  final s = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    title: Text(s, style: AppTheme.body()),
                    onTap: () => onSelected(s),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onSubmitted: (_) => onFieldSubmitted(),
          onEditingComplete: () {
            final text = controller.text.trim().toUpperCase();
            if (text.isNotEmpty) {
              widget.onSelected(text);
            }
          },
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: 'Начните вводить BTC, ETH, SOL...',
            suffixIcon: widget.symbols.isNotEmpty
                ? const Icon(Icons.search, color: AppTheme.muted, size: 20)
                : null,
          ),
        );
      },
    );
  }
}

/// Поле множественного выбора символов с поиском и галочками.
/// Показывает "выбрано N".
class MultiSymbolPicker extends StatefulWidget {
  final List<String> selected;
  final List<String> symbols;
  final ValueChanged<List<String>> onChanged;

  const MultiSymbolPicker({
    super.key,
    required this.selected,
    required this.symbols,
    required this.onChanged,
  });

  @override
  State<MultiSymbolPicker> createState() => _MultiSymbolPickerState();
}

class _MultiSymbolPickerState extends State<MultiSymbolPicker> {
  @override
  Widget build(BuildContext context) {
    final text = widget.selected.isEmpty
        ? 'Выберите монеты'
        : 'Выбрано ${widget.selected.length}: ${widget.selected.take(3).join(", ")}${widget.selected.length > 3 ? '...' : ''}';
    return InkWell(
      onTap: _openDialog,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Монеты',
          hintText: 'Нажмите, чтобы выбрать',
        ),
        child: Text(text, style: AppTheme.body()),
      ),
    );
  }

  Future<void> _openDialog() async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => _MultiSelectDialog(
        all: widget.symbols,
        selected: List.from(widget.selected),
      ),
    );
    if (result != null) {
      widget.onChanged(result.map((s) => s.toUpperCase()).toList());
    }
  }
}

class _MultiSelectDialog extends StatefulWidget {
  final List<String> all;
  final List<String> selected;

  const _MultiSelectDialog({required this.all, required this.selected});

  @override
  State<_MultiSelectDialog> createState() => __MultiSelectDialogState();
}

class __MultiSelectDialogState extends State<_MultiSelectDialog> {
  late List<String> _selected;
  final _queryCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = widget.selected;
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _query.isEmpty
        ? widget.all
        : widget.all.where((s) => s.toUpperCase().contains(_query.toUpperCase())).toList();

    return AlertDialog(
      backgroundColor: AppTheme.card,
      title: Text('Выбор монет', style: AppTheme.title()),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _queryCtrl,
              onChanged: (s) => setState(() => _query = s),
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'Поиск...',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _selected = List.from(widget.all)),
                  child: const Text('Выбрать все'),
                ),
                TextButton(
                  onPressed: () => setState(() => _selected = []),
                  child: const Text('Снять все'),
                ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final s = items[i];
                  final isSelected = _selected.contains(s);
                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(s);
                        } else {
                          _selected.remove(s);
                        }
                      });
                    },
                    title: Text(s, style: AppTheme.body()),
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Готово'),
        ),
      ],
    );
  }
}
