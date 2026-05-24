// services/notification_badge_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationBadgeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  DateTime? _parseDataNascimento(dynamic valor) {
    try {
      if (valor == null) return null;

      if (valor is Timestamp) {
        return valor.toDate();
      }

      if (valor is String) {
        final partes = valor.trim().split('/');

        if (partes.length >= 2) {
          final dia = int.tryParse(partes[0]);
          final mes = int.tryParse(partes[1]);
          final ano = partes.length >= 3 ? int.tryParse(partes[2]) ?? 2000 : 2000;

          if (dia != null && mes != null) {
            return DateTime(ano, mes, dia);
          }
        }
      }
    } catch (e) {
      print('❌ Erro ao converter data_nascimento: $e');
    }

    return null;
  }

  // 🔔 Stream do número de aniversariantes HOJE
  Stream<int> getTodayBirthdayCount() {
    final hoje = DateTime.now();

    return _firestore
        .collection('alunos')
        .where('status_atividade', isEqualTo: 'ATIVO(A)')
        .snapshots()
        .map((snapshot) {
      int count = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();

        final birthDate = _parseDataNascimento(data['data_nascimento']);

        if (birthDate == null) continue;

        if (birthDate.day == hoje.day && birthDate.month == hoje.month) {
          count++;
        }
      }

      return count;
    });
  }

  // 🔔 Stream de notificações não lidas (para o sininho)
  Stream<int> getUnreadNotificationsCount() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(0);

    return _firestore
        .collection('notificacoes')
        .where('user_id', isEqualTo: user.uid)
        .where('lida', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // 🔔 Marcar notificação como lida
  Future<void> markAsRead(String notificationId) async {
    try {
      await _firestore.collection('notificacoes').doc(notificationId).update({
        'lida': true,
        'data_leitura': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Erro ao marcar notificação como lida: $e');
    }
  }

  // 🔔 Marcar TODAS como lidas
  Future<void> markAllAsRead() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final snapshot = await _firestore
          .collection('notificacoes')
          .where('user_id', isEqualTo: user.uid)
          .where('lida', isEqualTo: false)
          .get();

      final batch = _firestore.batch();

      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {
          'lida': true,
          'data_leitura': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    } catch (e) {
      print('❌ Erro ao marcar todas como lidas: $e');
    }
  }
}