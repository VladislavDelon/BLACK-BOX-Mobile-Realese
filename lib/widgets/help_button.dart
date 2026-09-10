import 'package:flutter/material.dart';
import '../app_theme.dart';

class HelpButton extends StatelessWidget {
  final String title;
  final String text;
  const HelpButton({super.key, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _show(context),
        icon: const Icon(Icons.help_outline, color: AppTheme.accent, size: 18),
        label: const Text('Как пользоваться?', style: TextStyle(color: AppTheme.accent, fontSize: 13)),
      ),
    );
  }

  void _show(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(title, style: AppTheme.title(color: AppTheme.accent)),
        content: SingleChildScrollView(
          child: Text(text, style: AppTheme.body()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }
}
