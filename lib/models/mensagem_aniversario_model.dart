import 'package:cloud_firestore/cloud_firestore.dart';

class MensagemAniversario {
  final String id;
  final String texto;
  final bool ativa;
  final String categoria;

  MensagemAniversario({
    required this.id,
    required this.texto,
    required this.ativa,
    required this.categoria,
  });

  // Construtor para criar a partir do Firestore
  factory MensagemAniversario.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data()!;
    return MensagemAniversario(
      id: doc.id,
      texto: data['texto'] ?? '',
      ativa: data['ativa'] ?? true,
      categoria: data['categoria'] ?? 'neutra',
    );
  }

  // Converter para Map (para salvar no Firestore)
  Map<String, dynamic> toMap() {
    return {
      'texto': texto,
      'ativa': ativa,
      'categoria': categoria,
      'criada_em': FieldValue.serverTimestamp(),
    };
  }

  // Substituir {nome} pelo nome real do aluno
  String getTextoComNome(String nomeAluno) {
    return texto.replaceAll('{nome}', nomeAluno);
  }
}