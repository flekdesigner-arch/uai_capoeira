import 'package:flutter/widgets.dart';

class PermissionDefinition {
  final String key;
  final String title;
  final String description;
  final List<String> aliases;
  final IconData icon;
  final String category;
  final bool critical;
  final bool adminOnlySuggested;
  final bool delegable;

  const PermissionDefinition({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.category,
    this.aliases = const [],
    this.critical = false,
    this.adminOnlySuggested = false,
    this.delegable = true,
  });

  List<String> get linkedKeys =>
      {key, ...aliases.where((alias) => alias.isNotEmpty)}.toList();

  Map<String, dynamic> toMap() {
    return {
      'chave': key,
      'titulo': title,
      'descricao': description,
      'aliases': aliases,
      'icone': icon,
      'categoria': category,
      'critical': critical,
      'adminOnlySuggested': adminOnlySuggested,
      'delegable': delegable,
    };
  }
}
