import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/evento_model.dart';

class EventoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 📌 Coleção no Firestore
  final String _collection = 'eventos';

  // 🔥 SALVAR evento (criar ou atualizar)
  Future<String?> salvarEvento(EventoModel evento) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Usuário não logado');

      if (evento.id == null) {
        // Criar novo evento
        final docRef = await _firestore.collection(_collection).add(evento.toMap());
        return docRef.id;
      } else {
        // Atualizar evento existente
        await _firestore
            .collection(_collection)
            .doc(evento.id)
            .update(evento.toMap());
        return evento.id;
      }
    } catch (e) {
      print('❌ Erro ao salvar evento: $e');
      rethrow;
    }
  }

  // 🔥 ATUALIZAR BANNER DO EVENTO
  Future<void> atualizarBanner(String eventoId, String bannerUrl) async {
    try {
      await _firestore
          .collection(_collection)
          .doc(eventoId)
          .update({
        'link_banner': bannerUrl,
        'atualizado_em': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Erro ao atualizar banner: $e');
      rethrow;
    }
  }

  // 🔥 BUSCAR evento por ID
  Future<EventoModel?> buscarEventoPorId(String eventoId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(eventoId).get();

      if (!doc.exists) return null;

      return EventoModel.fromFirestore(doc);
    } catch (e) {
      print('❌ Erro ao buscar evento: $e');
      return null;
    }
  }

  // 🔥 LISTAR todos os eventos (ordenados por data)
  Stream<List<EventoModel>> listarEventos() {
    return _firestore
        .collection(_collection)
        .orderBy('data', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => EventoModel.fromFirestore(doc)).toList();
    });
  }

  // 🔥 LISTAR eventos por status (andamento/finalizado)
  Stream<List<EventoModel>> listarEventosPorStatus(String status) {
    return _firestore
        .collection(_collection)
        .where('status', isEqualTo: status)
        .orderBy('data', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => EventoModel.fromFirestore(doc)).toList();
    });
  }

  // 🔥 LISTAR eventos por tipo
  Stream<List<EventoModel>> listarEventosPorTipo(String tipo) {
    return _firestore
        .collection(_collection)
        .where('tipo', isEqualTo: tipo)
        .orderBy('data', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => EventoModel.fromFirestore(doc)).toList();
    });
  }

  // 🔥 DELETAR evento
  Future<void> deletarEvento(String eventoId) async {
    try {
      await _firestore.collection(_collection).doc(eventoId).delete();
    } catch (e) {
      print('❌ Erro ao deletar evento: $e');
      rethrow;
    }
  }

  // 🔥 FINALIZAR evento (muda status para 'finalizado')
  Future<void> finalizarEvento(String eventoId) async {
    try {
      await _firestore.collection(_collection).doc(eventoId).update({
        'status': 'finalizado',
        'atualizado_em': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Erro ao finalizar evento: $e');
      rethrow;
    }
  }

  // 🔥 BUSCAR eventos em andamento (útil pra verificar se tem)
  Future<bool> existeEventoEmAndamento() async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('status', isEqualTo: 'andamento')
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('❌ Erro ao verificar eventos em andamento: $e');
      return false;
    }
  }

  // 🔥 LISTAR eventos que acontecem em uma data específica
  Stream<List<EventoModel>> listarEventosPorData(DateTime data) {
    final inicioDoDia = DateTime(data.year, data.month, data.day);
    final fimDoDia = inicioDoDia.add(const Duration(days: 1));

    return _firestore
        .collection(_collection)
        .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioDoDia))
        .where('data', isLessThan: Timestamp.fromDate(fimDoDia))
        .orderBy('data', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => EventoModel.fromFirestore(doc)).toList();
    });
  }

  // 🔥 LISTAR eventos por cidade
  Stream<List<EventoModel>> listarEventosPorCidade(String cidade) {
    return _firestore
        .collection(_collection)
        .where('cidade', isEqualTo: cidade)
        .orderBy('data', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => EventoModel.fromFirestore(doc)).toList();
    });
  }

  // 🔥 LISTAR eventos que têm camisa
  Stream<List<EventoModel>> listarEventosComCamisa() {
    return _firestore
        .collection(_collection)
        .where('temCamisa', isEqualTo: true)
        .orderBy('data', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => EventoModel.fromFirestore(doc)).toList();
    });
  }

  // 🔥 ESTATÍSTICAS RÁPIDAS (quantidade de eventos por status)
  Future<Map<String, int>> getEstatisticas() async {
    try {
      final andamento = await _firestore
          .collection(_collection)
          .where('status', isEqualTo: 'andamento')
          .count()
          .get();

      final finalizados = await _firestore
          .collection(_collection)
          .where('status', isEqualTo: 'finalizado')
          .count()
          .get();

      return {
        'andamento': andamento.count ?? 0,
        'finalizados': finalizados.count ?? 0,
      };
    } catch (e) {
      print('❌ Erro ao buscar estatísticas: $e');
      return {'andamento': 0, 'finalizados': 0};
    }
  }

  // 🔥 VALIDAR se usuário pode criar evento (pela permissão)
  Future<bool> podeCriarEvento() async {
    // Aqui você vai usar o PermissaoService que já temos
    // Por enquanto retorna true, depois ajustamos
    return true;
  }

  // 🔥 VALIDAR se usuário pode editar evento
  Future<bool> podeEditarEvento(String eventoId) async {
    // TODO: Implementar verificação de permissão
    return true;
  }
}