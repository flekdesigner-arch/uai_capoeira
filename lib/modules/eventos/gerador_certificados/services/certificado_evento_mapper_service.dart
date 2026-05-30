import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_evento_data.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_participante_data.dart';

class CertificadoEventoMapperService {
  final FirebaseFirestore _firestore;

  CertificadoEventoMapperService({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String participacoesCollection =
      'participacoes_eventos_em_andamento';
  static const String alunosCollection = 'alunos';
  static const String graduacoesCollection = 'graduacoes';

  Future<List<CertificadoParticipanteData>> carregarParticipantesDoEvento({
    required CertificadoEventoData evento,
    bool somenteQuitados = false,
    bool somentePresentes = false,
    bool somenteSemCertificado = false,
  }) async {
    if (evento.eventoId.trim().isEmpty) return [];

    try {
      final snapshot = await _firestore
          .collection(participacoesCollection)
          .where('evento_id', isEqualTo: evento.eventoId)
          .get();

      final participantes = <CertificadoParticipanteData>[];

      for (final doc in snapshot.docs) {
        final participante = await mapearParticipacao(
          participacaoId: doc.id,
          participacao: doc.data(),
        );

        if (participante == null) continue;

        if (somenteQuitados && !participante.estaQuitado) continue;
        if (somentePresentes && !participante.presente) continue;
        if (somenteSemCertificado && participante.temCertificadoGerado) {
          continue;
        }

        participantes.add(participante);
      }

      participantes.sort(
            (a, b) => a.alunoNome.toUpperCase().compareTo(
          b.alunoNome.toUpperCase(),
        ),
      );

      return participantes;
    } catch (e) {
      debugPrint('❌ Erro ao carregar participantes para certificado: $e');
      rethrow;
    }
  }

  Future<CertificadoParticipanteData?> carregarParticipantePorId({
    required String participacaoId,
  }) async {
    if (participacaoId.trim().isEmpty) return null;

    try {
      final doc = await _firestore
          .collection(participacoesCollection)
          .doc(participacaoId)
          .get();

      if (!doc.exists || doc.data() == null) return null;

      return mapearParticipacao(
        participacaoId: doc.id,
        participacao: doc.data()!,
      );
    } catch (e) {
      debugPrint('❌ Erro ao carregar participante por ID: $e');
      rethrow;
    }
  }

  Future<CertificadoParticipanteData?> mapearParticipacao({
    required String participacaoId,
    required Map<String, dynamic> participacao,
  }) async {
    try {
      final alunoId = _asString(participacao['aluno_id']);
      final graduacaoNovaId = _firstNotEmpty([
        participacao['graduacao_nova_id'],
        participacao['nova_graduacao_id'],
      ]);

      final results = await Future.wait<Map<String, dynamic>?>([
        _buscarAluno(alunoId),
        _buscarGraduacao(graduacaoNovaId),
      ]);

      return CertificadoParticipanteData.fromMaps(
        participacaoId: participacaoId,
        participacao: participacao,
        aluno: results[0],
        graduacao: results[1],
      );
    } catch (e) {
      debugPrint(
        '❌ Erro ao mapear participação $participacaoId para certificado: $e',
      );
      return null;
    }
  }

  Future<Map<String, dynamic>?> _buscarAluno(String alunoId) async {
    if (alunoId.trim().isEmpty) return null;

    try {
      final doc = await _firestore.collection(alunosCollection).doc(alunoId).get();

      if (!doc.exists || doc.data() == null) return null;

      return {
        'id': doc.id,
        ...doc.data()!,
      };
    } catch (e) {
      debugPrint('⚠️ Erro ao buscar aluno $alunoId: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _buscarGraduacao(String graduacaoId) async {
    if (graduacaoId.trim().isEmpty || graduacaoId == '0') return null;

    try {
      final doc = await _firestore
          .collection(graduacoesCollection)
          .doc(graduacaoId)
          .get();

      if (!doc.exists || doc.data() == null) return null;

      return {
        'id': doc.id,
        ...doc.data()!,
      };
    } catch (e) {
      debugPrint('⚠️ Erro ao buscar graduação $graduacaoId: $e');
      return null;
    }
  }

  Future<void> marcarCertificadoGerado({
    required String participacaoId,
    required String linkCertificado,
    String? storagePath,
    String? tipoArquivo,
  }) async {
    if (participacaoId.trim().isEmpty) {
      throw Exception('ID da participação não informado.');
    }

    if (linkCertificado.trim().isEmpty) {
      throw Exception('Link do certificado não informado.');
    }

    final data = <String, dynamic>{
      'link_certificado': linkCertificado.trim(),
      'certificado_atualizado_em': FieldValue.serverTimestamp(),
      'certificado_gerado': true,
      'certificado_status': 'gerado',
    };

    if (storagePath != null && storagePath.trim().isNotEmpty) {
      data['certificado_storage_path'] = storagePath.trim();
    }

    if (tipoArquivo != null && tipoArquivo.trim().isNotEmpty) {
      data['certificado_tipo_arquivo'] = tipoArquivo.trim();
    }

    await _firestore
        .collection(participacoesCollection)
        .doc(participacaoId)
        .update(data);
  }

  Future<void> limparCertificadoGerado({
    required String participacaoId,
  }) async {
    if (participacaoId.trim().isEmpty) {
      throw Exception('ID da participação não informado.');
    }

    await _firestore
        .collection(participacoesCollection)
        .doc(participacaoId)
        .update({
      'link_certificado': FieldValue.delete(),
      'certificado_atualizado_em': FieldValue.serverTimestamp(),
      'certificado_gerado': false,
      'certificado_status': 'pendente',
      'certificado_storage_path': FieldValue.delete(),
      'certificado_tipo_arquivo': FieldValue.delete(),
    });
  }


  Future<void> marcarParticipanteImpresso({
    required String participacaoId,
    bool impresso = true,
  }) async {
    if (participacaoId.trim().isEmpty) {
      throw Exception('ID da participação não informado.');
    }

    await _firestore
        .collection(participacoesCollection)
        .doc(participacaoId)
        .update({
      'certificado_impresso': impresso,
      'certificado_impresso_em':
      impresso ? FieldValue.serverTimestamp() : null,
      'certificado_status': impresso ? 'impresso' : 'gerado',
      'certificado_atualizado_em': FieldValue.serverTimestamp(),
    });
  }

  Map<String, int> contarStatus(List<CertificadoParticipanteData> participantes) {
    var total = 0;
    var quitados = 0;
    var presentes = 0;
    var comCertificado = 0;
    var semCertificado = 0;
    var comGraduacao = 0;
    var comCpf = 0;

    for (final item in participantes) {
      total++;

      if (item.estaQuitado) quitados++;
      if (item.presente) presentes++;
      if (item.temCertificadoGerado) {
        comCertificado++;
      } else {
        semCertificado++;
      }
      if (item.temGraduacaoNova) comGraduacao++;
      if (item.temCpf) comCpf++;
    }

    return {
      'total': total,
      'quitados': quitados,
      'presentes': presentes,
      'com_certificado': comCertificado,
      'sem_certificado': semCertificado,
      'com_graduacao': comGraduacao,
      'com_cpf': comCpf,
    };
  }

  String _asString(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  String _firstNotEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = _asString(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }
}
