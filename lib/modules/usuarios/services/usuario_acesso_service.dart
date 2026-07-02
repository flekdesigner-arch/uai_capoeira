import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class UsuarioAcessoService {
  UsuarioAcessoService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<bool> registrarUltimoLoginGestao({
    required String uid,
    String? provider,
  }) async {
    if (uid.trim().isEmpty) {
      debugPrint('⚠️ Não foi possível registrar último login: UID vazio.');
      return false;
    }

    try {
      final agoraLocal = Timestamp.now();

      await _firestore.collection('usuarios').doc(uid).set({
        // Campo principal usado na tela de detalhe do usuário.
        // Usar Timestamp.now() evita a tela ler null enquanto o serverTimestamp
        // ainda está pendente no cache local.
        'ultimo_login': agoraLocal,

        // Campo de auditoria com horário do servidor.
        'ultimo_login_servidor': FieldValue.serverTimestamp(),
        'ultimo_login_atualizado_em': FieldValue.serverTimestamp(),

        'ultimo_login_origem': 'login_gestao',
        'ultimo_login_app': 'gestao',
        'ultimo_login_provider': provider?.isNotEmpty == true
            ? provider
            : 'desconhecido',
      }, SetOptions(merge: true));

      debugPrint('✅ Último login da gestão registrado em usuarios/$uid');
      return true;
    } catch (e, stack) {
      debugPrint(
        '⚠️ Erro ao registrar último login da gestão em usuarios/$uid: $e',
      );
      debugPrintStack(stackTrace: stack);
      return false;
    }
  }

  Future<bool> registrarUltimoAcessoGestao({required String uid}) async {
    if (uid.trim().isEmpty) {
      debugPrint('⚠️ Não foi possível registrar último acesso: UID vazio.');
      return false;
    }

    try {
      final agoraLocal = Timestamp.now();

      await _firestore.collection('usuarios').doc(uid).set({
        // Campo principal usado na tela de detalhe do usuário.
        'ultimo_acesso': agoraLocal,

        // Campo de auditoria com horário do servidor.
        'ultimo_acesso_servidor': FieldValue.serverTimestamp(),
        'ultimo_acesso_atualizado_em': FieldValue.serverTimestamp(),

        'ultimo_acesso_origem': 'home',
        'ultimo_acesso_app': 'gestao',
      }, SetOptions(merge: true));

      debugPrint('✅ Último acesso da gestão registrado em usuarios/$uid');
      return true;
    } catch (e, stack) {
      debugPrint(
        '⚠️ Erro ao registrar último acesso da gestão em usuarios/$uid: $e',
      );
      debugPrintStack(stackTrace: stack);
      return false;
    }
  }
}
