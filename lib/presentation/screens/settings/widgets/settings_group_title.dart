
import 'package:flutter/material.dart';

class SettingsGroupTitle extends StatelessWidget {
  const SettingsGroupTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 24, 6, 10),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              letterSpacing: 1.1,
            ),
      ),
    );
  }
}

// ------------------------------------------------------------- Seguridad
