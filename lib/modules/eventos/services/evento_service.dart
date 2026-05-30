import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/evento_model.dart';

class EventoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final String _collection = 'eventos';

  Future<String?> salvarEvento(EventoModel evento) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Usuário não logado');

      if (evento.id == null) {
        final docRef =
        await _firestore.collection(_collection).add(evento.toMap());
        return docRef.id;
      } else {
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

  Future<void> atualizarBanner(String eventoId, String bannerUrl) async {
    try {
      await _firestore.collection(_collection).doc(eventoId).update({
        'linkBanner': bannerUrl,
        'link_banner': bannerUrl,
        'atualizado_em': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Erro ao atualizar banner: $e');
      rethrow;
    }
  }

  Future<void> atualizarConfiguracoesCertificado({
    required String eventoId,
    required ConfiguracoesCertificadoEvento configuracoes,
  }) async {
    try {
      await _firestore.collection(_collection).doc(eventoId).update({
        'tem_certificado': true,
        'geraCertificado': true,
        'modelo_certificado_id': configuracoes.modeloPadrao,
        'configuracoes_certificado': configuracoes.toMap(),
        'atualizado_em': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Erro ao atualizar configurações do certificado: $e');
      rethrow;
    }
  }

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

  Stream<List<EventoModel>> listarEventos() {
    return _firestore
        .collection(_collection)
        .orderBy('data', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => EventoModel.fromFirestore(doc)).toList();
    });
  }

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

  Future<void> deletarEvento(String eventoId) async {
    try {
      await _firestore.collection(_collection).doc(eventoId).delete();
    } catch (e) {
      print('❌ Erro ao deletar evento: $e');
      rethrow;
    }
  }

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

  Future<bool> podeCriarEvento() async {
    return true;
  }

  Future<bool> podeEditarEvento(String eventoId) async {
    return true;
  }
}
