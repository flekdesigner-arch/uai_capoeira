// services/lock_chamada_service.dart
import 'dart:async'; // 👈 IMPORT OBRIGATÓRIO para Timer
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class LockChamadaService {
  static final Map<String, Timer> _timers = {}; // Para controle de heartbeat
  static final Map<String, bool> _lockStatus = {}; // Cache do status

  // 🔥 VERIFICAR DISPONIBILIDADE
  static Future<bool> verificarDisponibilidade(String turmaId, {String? usuarioId}) async {
    debugPrint('🔒 Verificando disponibilidade para turma $turmaId');

    try {
      final hoje = DateTime.now();
      final dataHoje = DateTime(hoje.year, hoje.month, hoje.day);

      final lockDoc = await FirebaseFirestore.instance
          .collection('locks_chamada')
          .doc(turmaId)
          .get();

      if (!lockDoc.exists) {
        debugPrint('🔒 Documento não existe - DISPONÍVEL');
        return true;
      }

      final data = lockDoc.data();
      if (data == null) {
        debugPrint('🔒 Data null - DISPONÍVEL');
        return true;
      }

      final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
      if (timestamp == null) {
        debugPrint('🔒 Timestamp null - DISPONÍVEL');
        return true;
      }

      final dataLock = DateTime(timestamp.year, timestamp.month, timestamp.day);

      if (dataLock.isAtSameMomentAs(dataHoje)) {
        final diferenca = DateTime.now().difference(timestamp);
        debugPrint('🔒 Diferença: ${diferenca.inMinutes} minutos');

        // 👇 VERIFICA SE É O MESMO USUÁRIO
        final ocupanteId = data['usuario_id'] as String?;

        if (ocupanteId == usuarioId) {
          debugPrint('🔒 É O MESMO USUÁRIO - considerando disponível');
          return true; // É o mesmo usuário, pode acessar
        }

        if (diferenca.inMinutes < 30) {
          debugPrint('🔒 OCUPADO por ${data['usuario_nome']}');
          return false; // Outro usuário ocupando
        }
      }

      debugPrint('🔒 DISPONÍVEL (expirado ou outro dia)');
      return true;

    } catch (e) {
      debugPrint('🔒 Erro na verificação: $e');
      return true;
    }
  }
  // 🔒 OCUPAR CHAMADA
  static Future<bool> ocuparChamada({
    required String turmaId,
    required String usuarioId,
    required String usuarioNome,
  }) async {
    debugPrint('🔒 Tentando OCUPAR: $turmaId por $usuarioNome');

    try {
      final hoje = DateTime.now();
      final dataHoje = DateTime(hoje.year, hoje.month, hoje.day);

      final lockRef = FirebaseFirestore.instance
          .collection('locks_chamada')
          .doc(turmaId);

      // Primeiro, verificar se já existe um lock válido
      final doc = await lockRef.get();

      if (doc.exists) {
        final data = doc.data();
        final timestamp = data?['timestamp']?.toDate();

        if (timestamp != null) {
          final dataLock = DateTime(timestamp.year, timestamp.month, timestamp.day);

          if (dataLock.isAtSameMomentAs(dataHoje)) {
            final diferenca = DateTime.now().difference(timestamp);
            if (diferenca.inMinutes < 30) {
              final ocupanteId = data?['usuario_id'];
              if (ocupanteId != usuarioId) {
                debugPrint('🔒 JÁ OCUPADO por ${data?['usuario_nome']}');
                return false;
              }
            }
          }
        }
      }

      // Criar/atualizar o lock
      await lockRef.set({
        'turma_id': turmaId,
        'usuario_id': usuarioId,
        'usuario_nome': usuarioNome,
        'timestamp': FieldValue.serverTimestamp(),
        'data': dataHoje.toIso8601String(),
        'status': 'ocupado',
        'ultimo_heartbeat': FieldValue.serverTimestamp(),
      });

      debugPrint('🔒 LOCK CRIADO/ATUALIZADO com sucesso!');

      // Iniciar heartbeat para manter o lock ativo
      _iniciarHeartbeat(turmaId, usuarioId);

      return true;

    } catch (e) {
      debugPrint('🔒 ERRO ao ocupar: $e');
      return false;
    }
  }

  // 💓 HEARTBEAT - Mantém o lock ativo
  static void _iniciarHeartbeat(String turmaId, String usuarioId) {
    // Cancela timer anterior se existir
    _timers[turmaId]?.cancel();

    // Cria novo timer que atualiza o lock a cada 2 minutos
    _timers[turmaId] = Timer.periodic(const Duration(minutes: 2), (timer) async {
      try {
        final lockRef = FirebaseFirestore.instance
            .collection('locks_chamada')
            .doc(turmaId);

        // Verifica se ainda é o mesmo usuário antes de atualizar
        final doc = await lockRef.get();
        if (doc.exists && doc.data()?['usuario_id'] == usuarioId) {
          await lockRef.update({
            'ultimo_heartbeat': FieldValue.serverTimestamp(),
            'timestamp': FieldValue.serverTimestamp(),
          });
          debugPrint('💓 Heartbeat enviado para $turmaId');
        } else {
          // Se não for mais o mesmo usuário, para o heartbeat
          timer.cancel();
          _timers.remove(turmaId);
        }
      } catch (e) {
        debugPrint('💓 Erro no heartbeat: $e');
      }
    });
  }

  // 🔓 LIBERAR CHAMADA
  static Future<void> liberarChamada(String turmaId) async {
    debugPrint('🔓 Liberando lock: $turmaId');

    // Cancela heartbeat
    _timers[turmaId]?.cancel();
    _timers.remove(turmaId);

    try {
      await FirebaseFirestore.instance
          .collection('locks_chamada')
          .doc(turmaId)
          .delete();
      debugPrint('🔓 Lock removido com sucesso');
    } catch (e) {
      debugPrint('🔓 Erro ao remover lock: $e');
    }
  }

  // 👤 MONITORAR OCUPAÇÃO (versão estabilizada)
  static Stream<Map<String, dynamic>?> monitorarOcupacao(String turmaId) {
    debugPrint('👤 Iniciando monitoramento de $turmaId');

    return FirebaseFirestore.instance
        .collection('locks_chamada')
        .doc(turmaId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) {
        debugPrint('👤 Lock não existe (monitor)');
        return null;
      }

      final data = snapshot.data();
      debugPrint('👤 Lock atual: ${data?['usuario_nome']}');
      return data;
    })
        .distinct(); // IMPORTANTE: Evita notificações duplicadas
  }
}