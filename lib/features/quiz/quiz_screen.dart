import 'package:flutter/material.dart';

class QuizScreen extends StatelessWidget {
  final Map<String, dynamic>? args;
  const QuizScreen({super.key, this.args});

  @override
  Widget build(BuildContext context) {
    final title = args?['subchapterTitle'] ?? args?['title'] ?? 'Test';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(child: Text('Quiz not implemented yet')),
    );
  }
}
