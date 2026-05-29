import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class RegimentoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🔥 Busca as seções do regimento no Firestore
  Future<List<Map<String, dynamic>>> carregarRegimento() async {
    try {
      final doc = await _firestore.collection('site_conteudo').doc('regimento').get();

      if (doc.exists && doc.data()!.containsKey('secoes')) {
        return List<Map<String, dynamic>>.from(doc.data()!['secoes']);
      }
    } catch (e) {
      debugPrint('Erro ao carregar regimento: $e');
    }
    return []; // Retorna vazio se não encontrar
  }

  // 🔥 Mapeia nome do ícone para IconData
  IconData getIconFromName(String iconName) {
    switch (iconName) {
      case 'gavel': return Icons.gavel;
      case 'person_add': return Icons.person_add;
      case 'school': return Icons.school;
      case 'workspace_premium': return Icons.workspace_premium;
      case 'security': return Icons.security;
      case 'group': return Icons.group;
      case 'star': return Icons.star;
      case 'emoji_events': return Icons.emoji_events;
      case 'menu_book': return Icons.menu_book;
      case 'rule': return Icons.rule;
      default: return Icons.description;
    }
  }
}