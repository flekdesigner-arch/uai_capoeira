import 'package:flutter/material.dart';

class ProgressDialog extends StatelessWidget {
  final String message;
  final double? progress; // null = indeterminado

  const ProgressDialog({
    super.key,
    required this.message,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.sync,
              size: 50,
              color: Colors.purple,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (progress != null) ...[
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.purple.shade100,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.purple.shade900),
              ),
              const SizedBox(height: 8),
              Text(
                '${(progress! * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.purple.shade900,
                ),
              ),
            ] else ...[
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.purple),
              ),
            ],
          ],
        ),
      ),
    );
  }
}