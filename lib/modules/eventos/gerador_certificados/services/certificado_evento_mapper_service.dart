import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_evento_data.dart';
import 'package:uai_capoeira/modules/eventos/gerador_certificados/models/certificado_participante_data.dart';

class CertificadoEventoMapperService {
  final FirebaseFirestore _firestore;

  CertificadoEventoMapperService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String participacoesCollection =
      'participacoes_eventos_em_andamento';
  static const String alunosCollection = 'alunos';
  static const String graduacoesCollection = 'graduacoes';
  static const String academiasCollection = 'academias';
  static const String turmasCollection = 'turmas';

  final Map<String, String> _academiaNomeCache = <String, String>{};
  final Map<String, String> _turmaNomeCache = <String, String>{};

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
        (a, b) =>
            a.alunoNome.toUpperCase().compareTo(b.alunoNome.toUpperCase()),
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
      final alunoOriginal = await _buscarAluno(alunoId);
      final aluno = alunoOriginal == null
          ? null
          : Map<String, dynamic>.from(alunoOriginal);

      // O certificado deve refletir o vínculo REAL do aluno, e nunca o local/cidade
      // do evento como se fosse academia. Resolve nomes por ID somente quando
      // necessário e mantém cache por tela para não multiplicar leituras.
      if (aluno != null) {
        final academiaId = _firstNotEmpty([
          participacao['academia_id'],
          aluno['academia_id'],
        ]);
        var academiaNome = _firstNotEmpty([
          participacao['academia_nome'],
          participacao['academia'],
          aluno['academia_nome'],
          aluno['academia'],
        ]);
        if (academiaNome.isEmpty && academiaId.isNotEmpty) {
          academiaNome = await _buscarNomeAcademia(academiaId);
        }
        if (academiaId.isNotEmpty) aluno['academia_id'] = academiaId;
        if (academiaNome.isNotEmpty) aluno['academia_nome'] = academiaNome;

        final turmaId = _firstNotEmpty([
          participacao['turma_id'],
          aluno['turma_id'],
        ]);
        var turmaNome = _firstNotEmpty([
          participacao['turma_nome'],
          participacao['turma'],
          aluno['turma_nome'],
          aluno['turma'],
        ]);
        if (turmaNome.isEmpty && turmaId.isNotEmpty) {
          turmaNome = await _buscarNomeTurma(turmaId);
        }
        if (turmaId.isNotEmpty) aluno['turma_id'] = turmaId;
        if (turmaNome.isNotEmpty) aluno['turma_nome'] = turmaNome;
      }

      // Busca a graduação nova preferindo a participação.
      // Se por algum motivo a participação antiga não tiver o ID novo,
      // usa fallbacks do aluno para não perder frase, título, corda, cores e modelo.
      final graduacaoNovaId = _firstNotEmpty([
        participacao['graduacao_nova_id'],
        participacao['nova_graduacao_id'],
        participacao['graduacao_nova_ref_id'],
        aluno?['graduacao_atual_id'],
        aluno?['graduacao_id'],
      ]);

      final graduacao = await _buscarGraduacao(graduacaoNovaId);

      final participante = CertificadoParticipanteData.fromMaps(
        participacaoId: participacaoId,
        participacao: participacao,
        aluno: aluno,
        graduacao: graduacao,
      );

      if (participante.sexoNormalizado.isEmpty) {
        debugPrint(
          '⚠️ Participante sem sexo informado para frase dinâmica: ${participante.alunoNome}',
        );
      }

      return participante;
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
      final doc = await _firestore
          .collection(alunosCollection)
          .doc(alunoId)
          .get();

      if (!doc.exists || doc.data() == null) return null;

      return {'id': doc.id, ...doc.data()!};
    } catch (e) {
      debugPrint('⚠️ Erro ao buscar aluno $alunoId: $e');
      return null;
    }
  }

  Future<String> _buscarNomeAcademia(String academiaId) async {
    final id = academiaId.trim();
    if (id.isEmpty) return '';
    final cached = _academiaNomeCache[id];
    if (cached != null) return cached;
    try {
      final doc = await _firestore.collection(academiasCollection).doc(id).get();
      final nome = _firstNotEmpty([
        doc.data()?['nome'],
        doc.data()?['academia_nome'],
        doc.data()?['titulo'],
      ]);
      _academiaNomeCache[id] = nome;
      return nome;
    } catch (e) {
      debugPrint('⚠️ Erro ao resolver academia $id: $e');
      _academiaNomeCache[id] = '';
      return '';
    }
  }

  Future<String> _buscarNomeTurma(String turmaId) async {
    final id = turmaId.trim();
    if (id.isEmpty) return '';
    final cached = _turmaNomeCache[id];
    if (cached != null) return cached;
    try {
      final doc = await _firestore.collection(turmasCollection).doc(id).get();
      final nome = _firstNotEmpty([
        doc.data()?['nome'],
        doc.data()?['turma_nome'],
        doc.data()?['titulo'],
      ]);
      _turmaNomeCache[id] = nome;
      return nome;
    } catch (e) {
      debugPrint('⚠️ Erro ao resolver turma $id: $e');
      _turmaNomeCache[id] = '';
      return '';
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

      return {'id': doc.id, ...doc.data()!};
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
    String? emissaoV2Id,
    String? codigoPublico,
    String? codigoHumano,
    String? urlAutenticidade,
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
    if (emissaoV2Id != null && emissaoV2Id.trim().isNotEmpty) {
      data['certificado_emissao_v2_id'] = emissaoV2Id.trim();
      data['certificado_modo_emissao'] = 'profissional_v2';
    }
    if (codigoPublico != null && codigoPublico.trim().isNotEmpty) {
      data['certificado_codigo_publico'] = codigoPublico.trim();
    }
    if (codigoHumano != null && codigoHumano.trim().isNotEmpty) {
      data['certificado_codigo'] = codigoHumano.trim();
    }
    if (urlAutenticidade != null && urlAutenticidade.trim().isNotEmpty) {
      data['certificado_url_autenticidade'] = urlAutenticidade.trim();
    }

    await _firestore
        .collection(participacoesCollection)
        .doc(participacaoId)
        .update(data);
  }

  Future<void> limparCertificadoGerado({required String participacaoId}) async {
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
          'certificado_impresso_em': impresso
              ? FieldValue.serverTimestamp()
              : null,
          'certificado_status': impresso ? 'impresso' : 'gerado',
          'certificado_atualizado_em': FieldValue.serverTimestamp(),
        });
  }

  Map<String, int> contarStatus(
    List<CertificadoParticipanteData> participantes,
  ) {
    var total = 0;
    var quitados = 0;
    var presentes = 0;
    var comCertificado = 0;
    var semCertificado = 0;
    var comGraduacao = 0;
    var comCpf = 0;
    var femininos = 0;
    var masculinos = 0;
    var semSexo = 0;

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
      if (item.sexoFeminino) {
        femininos++;
      } else if (item.sexoMasculino) {
        masculinos++;
      } else {
        semSexo++;
      }
    }

    return {
      'total': total,
      'quitados': quitados,
      'presentes': presentes,
      'com_certificado': comCertificado,
      'sem_certificado': semCertificado,
      'com_graduacao': comGraduacao,
      'com_cpf': comCpf,
      'femininos': femininos,
      'masculinos': masculinos,
      'sem_sexo': semSexo,
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
