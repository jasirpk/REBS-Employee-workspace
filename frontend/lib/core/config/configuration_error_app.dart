import 'package:flutter/material.dart';

// Shown instead of the app when build-time configuration is missing or
// invalid, so the problem is visible rather than surfacing as network errors.
class ConfigurationErrorApp extends StatelessWidget {
  final String message;

  const ConfigurationErrorApp({required this.message, super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'REBS Employee Workspace',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.settings_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text('App configuration error', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
