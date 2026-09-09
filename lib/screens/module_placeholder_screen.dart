import 'package:flutter/material.dart';
import '../app_theme.dart';

class ModulePlaceholderScreen extends StatelessWidget {
  final String moduleId;
  final String title;

  const ModulePlaceholderScreen({
    super.key,
    required this.moduleId,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: AppTheme.header(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                'Этот модуль в процессе переноса из десктопной версии.',
                style: AppTheme.body(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'module: $moduleId',
                style: AppTheme.small(),
              ),
              const SizedBox(height: 40),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Назад'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
