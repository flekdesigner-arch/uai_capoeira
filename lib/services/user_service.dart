// lib/services/user_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  // Cria ou atualiza documento do usuário no Firestore
  static Future<void> createOrUpdateUserDocument({
    required User user,
    String? nomeCompleto,
    String? contato,
    bool isGoogleLogin = false,
  }) async {
    final docRef = FirebaseFirestore.instance.collection('usuarios').doc(user.uid);
    final docSnapshot = await docRef.get();

    final agora = FieldValue.serverTimestamp();

    // Dados básicos do usuário
    Map<String, dynamic> userData = {
      'email': user.email,
      'ultima_atualizacao': agora,
    };

    if (!docSnapshot.exists) {
      // Primeiro login - criar documento completo
      userData.addAll({
        'nome_completo': nomeCompleto ?? user.displayName ?? 'Usuário',
        'contato': contato ?? '',
        'foto_url': user.photoURL ?? '',
        'status_conta': 'pendente',
        'peso_permissao': 0,
        'tipo': 'pendente',
        'aprovado_por': '',
        'aprovado_por_nome': '',
        'aprovado_em': null,
        'data_cadastro': agora,
      });
    } else {
      // Atualizar apenas campos permitidos
      if (nomeCompleto != null) userData['nome_completo'] = nomeCompleto;
      if (contato != null) userData['contato'] = contato;
    }

    await docRef.set(userData, SetOptions(merge: true));
  }

  // Verifica se o usuário tem permissão para acessar
  static Future<bool> hasAccess(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(userId)
          .get();

      if (!doc.exists) return false;

      final status = doc.data()?['status_conta'] as String?;
      return status == 'ativa';
    } catch (e) {
      return false;
    }
  }
}