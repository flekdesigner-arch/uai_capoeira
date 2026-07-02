import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class AlunoHistoricoEdicaoService {
  AlunoHistoricoEdicaoService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const Set<String> camposFicha = {
    'nome',
    'apelido',
    'cpf',
    'data_nascimento',
    'sexo',
    'contato_aluno',
    'nome_responsavel',
    'contato_responsavel',
    'endereco',
    'cidade',
    'academia_id',
    'academia',
    'turma_id',
    'turma',
    'graduacao_id',
    'graduacao_nome',
    'graduacao_cor1',
    'graduacao_cor2',
    'graduacao_ponta1',
    'graduacao_ponta2',
    'data_graduacao_atual',
    'tempo_capoeira',
    'status_atividade',
    'data_desativacao',
    'data_ativacao',
    'desativado_em',
    'reativado_em',
    'foto_perfil_aluno',
  };

  static const Set<String> camposIgnorados = {
    'atualizado_em',
    'editavel',
    'criado_em',
    'ultima_atualizacao',
    'ultimo_acesso',
    'ultimo_login',
    'areaAlunoGoogleUid',
    'areaAlunoGoogleEmail',
    'areaAlunoGoogleNome',
    'areaAlunoGoogleVinculadoEm',
    'cache',
    'graduacao_ref',
    'data_atualizacao',
    'atualizado_por',
    'atualizado_por_uid',
    'ultima_edicao_em',
    'ultima_edicao_por_uid',
    'ultima_edicao_por_nome',
    'ultima_edicao_por_email',
    'ultima_edicao_tipo',
    'ultima_edicao_origem',
    'ultima_edicao_resumo',
    'ultima_edicao_subtipo',
  };

  static const Map<String, String> labelsCampos = {
    'nome': 'Nome',
    'apelido': 'Apelido',
    'cpf': 'CPF',
    'data_nascimento': 'Data de nascimento',
    'sexo': 'Sexo',
    'contato_aluno': 'Contato do aluno',
    'nome_responsavel': 'Nome do responsável',
    'contato_responsavel': 'Contato do responsável',
    'endereco': 'Endereço',
    'cidade': 'Cidade',
    'academia_id': 'ID do núcleo',
    'academia': 'Núcleo/Academia',
    'turma_id': 'ID da turma',
    'turma': 'Turma',
    'graduacao_id': 'ID da graduação',
    'graduacao_nome': 'Graduação',
    'graduacao_cor1': 'Cor 1 da graduação',
    'graduacao_cor2': 'Cor 2 da graduação',
    'graduacao_ponta1': 'Ponta 1 da graduação',
    'graduacao_ponta2': 'Ponta 2 da graduação',
    'data_graduacao_atual': 'Data da graduação atual',
    'tempo_capoeira': 'Tempo de capoeira',
    'status_atividade': 'Status',
    'data_desativacao': 'Data de desativação',
    'data_ativacao': 'Data de ativação',
    'desativado_em': 'Desativado em',
    'reativado_em': 'Reativado em',
    'foto_perfil_aluno': 'Foto do aluno',
  };

  Future<void> registrarEdicaoManual({
    required String alunoId,
    required Map<String, dynamic> dadosAntes,
    required Map<String, dynamic> dadosDepois,
    required String origem,
    String? subtipoEdicao,
    String? resumoPersonalizado,
  }) async {
    await _registrarEdicaoAplicada(
      alunoId: alunoId,
      dadosAntes: dadosAntes,
      dadosDepois: dadosDepois,
      tipoEdicao: 'manual',
      origem: origem,
      prefixoResumo: 'Edição manual',
      subtipoEdicao: subtipoEdicao,
      resumoPersonalizado: resumoPersonalizado,
      extras: const {},
    );
  }

  Future<void> registrarEdicaoPorSolicitacao({
    required String alunoId,
    required Map<String, dynamic> dadosAntes,
    required Map<String, dynamic> dadosDepois,
    required String solicitacaoId,
    String? observacaoAluno,
    String? observacaoAprovacao,
  }) async {
    await _registrarEdicaoAplicada(
      alunoId: alunoId,
      dadosAntes: dadosAntes,
      dadosDepois: dadosDepois,
      tipoEdicao: 'solicitacao_area_aluno',
      origem: 'solicitacao_area_aluno_aprovada',
      prefixoResumo: 'Solicitação aprovada',
      subtipoEdicao: null,
      resumoPersonalizado: null,
      extras: {
        'solicitacao_id': solicitacaoId,
        if (observacaoAluno != null && observacaoAluno.trim().isNotEmpty)
          'observacao_aluno': observacaoAluno.trim(),
        if (observacaoAprovacao != null &&
            observacaoAprovacao.trim().isNotEmpty)
          'observacao_aprovacao': observacaoAprovacao.trim(),
      },
    );
  }

  Future<void> registrarDesativacaoAluno({
    required String alunoId,
    required Map<String, dynamic> dadosAntes,
    required Map<String, dynamic> dadosDepois,
    required String motivoId,
    required String motivoTitulo,
    String? observacao,
    String origem = 'aluno_detalhe_screen',
  }) async {
    await _registrarEdicaoAplicada(
      alunoId: alunoId,
      dadosAntes: dadosAntes,
      dadosDepois: dadosDepois,
      tipoEdicao: 'desativacao',
      origem: origem,
      prefixoResumo: 'Aluno desativado',
      subtipoEdicao: 'desativacao_aluno',
      resumoPersonalizado: 'Aluno desativado: $motivoTitulo',
      podeReverter: false,
      extras: {
        'motivo_id': motivoId,
        'motivo_titulo': motivoTitulo,
        if (observacao != null && observacao.trim().isNotEmpty)
          'observacao': observacao.trim(),
      },
    );
  }

  Future<void> registrarReativacaoAluno({
    required String alunoId,
    required Map<String, dynamic> dadosAntes,
    required Map<String, dynamic> dadosDepois,
    required String motivoId,
    required String motivoTitulo,
    String? observacao,
    String origem = 'vincular_aluno_inativo_turma_screen',
  }) async {
    await _registrarEdicaoAplicada(
      alunoId: alunoId,
      dadosAntes: dadosAntes,
      dadosDepois: dadosDepois,
      tipoEdicao: 'reativacao',
      origem: origem,
      prefixoResumo: 'Aluno reativado',
      subtipoEdicao: 'reativacao_aluno',
      resumoPersonalizado: 'Aluno reativado: $motivoTitulo',
      podeReverter: false,
      extras: {
        'motivo_id': motivoId,
        'motivo_titulo': motivoTitulo,
        if (observacao != null && observacao.trim().isNotEmpty)
          'observacao': observacao.trim(),
      },
    );
  }

  Future<void> reverterEdicao({
    required String alunoId,
    required String historicoId,
  }) async {
    final usuario = await _dadosUsuarioAtual();
    final alunoRef = _firestore.collection('alunos').doc(alunoId);
    final historicoRef = alunoRef
        .collection('historico_edicoes')
        .doc(historicoId);

    await _firestore.runTransaction((transaction) async {
      final historicoSnap = await transaction.get(historicoRef);
      if (!historicoSnap.exists) {
        throw Exception('Histórico não encontrado.');
      }

      final historico = historicoSnap.data() ?? <String, dynamic>{};
      if (historico['revertido'] == true) {
        throw Exception('Esta edição já foi revertida.');
      }
      if (historico['tipo_edicao'] == 'reversao' ||
          historico['pode_reverter'] == false) {
        throw Exception('Registros de reversão não podem ser revertidos.');
      }

      final dadosOriginais = _mapFrom(historico['dados_antes']);
      final campos = _camposParaReversao(
        dadosOriginais,
        historico['campos_alterados'],
      );
      if (campos.isEmpty) {
        throw Exception('Não há campos registrados para reverter.');
      }

      final alunoSnap = await transaction.get(alunoRef);
      if (!alunoSnap.exists) {
        throw Exception('Aluno não encontrado.');
      }

      final dadosAtuais = alunoSnap.data() ?? <String, dynamic>{};
      final updateAluno = <String, dynamic>{};
      final dadosDepois = Map<String, dynamic>.from(dadosAtuais);

      for (final campo in campos) {
        updateAluno[campo] = dadosOriginais[campo];
        dadosDepois[campo] = dadosOriginais[campo];
      }

      final camposAlterados = compararDados(
        dadosAtuais,
        dadosDepois,
        camposPermitidos: campos,
      );
      if (camposAlterados.isEmpty) {
        throw Exception(
          'Os dados atuais já correspondem aos valores anteriores.',
        );
      }

      final dadosAntesReversao = <String, dynamic>{};
      final dadosDepoisReversao = <String, dynamic>{};
      for (final item in camposAlterados) {
        final campo = item['campo']?.toString() ?? '';
        dadosAntesReversao[campo] = dadosAtuais[campo];
        dadosDepoisReversao[campo] = dadosDepois[campo];
      }
      final historicoSubtipo = historico['subtipo_edicao']?.toString();
      final reversaoSubtipo = historicoSubtipo == 'mudanca_turma'
          ? 'reversao_mudanca_turma'
          : null;
      final resumo = historicoSubtipo == 'mudanca_turma'
          ? 'Reversão de mudança de turma'
          : 'Reversão de edição anterior';
      updateAluno.addAll({
        'ultima_edicao_em': FieldValue.serverTimestamp(),
        'ultima_edicao_por_uid': usuario.uid,
        'ultima_edicao_por_nome': usuario.nome,
        'ultima_edicao_por_email': usuario.email,
        'ultima_edicao_tipo': 'reversao',
        'ultima_edicao_subtipo': reversaoSubtipo,
        'ultima_edicao_origem': 'historico_edicoes_aluno',
        'ultima_edicao_resumo': resumo,
        'atualizado_em': FieldValue.serverTimestamp(),
      });

      transaction.update(alunoRef, updateAluno);
      transaction.update(historicoRef, {
        'status': 'revertida',
        'revertido': true,
        'revertido_em': FieldValue.serverTimestamp(),
        'revertido_por_uid': usuario.uid,
        'revertido_por_nome': usuario.nome,
        'revertido_por_email': usuario.email,
      });

      final reversaoRef = alunoRef.collection('historico_edicoes').doc();
      transaction.set(reversaoRef, {
        'aluno_id': alunoId,
        'aluno_nome': _nomeAluno(dadosDepois),
        'tipo_edicao': 'reversao',
        'subtipo_edicao': reversaoSubtipo,
        'origem': 'historico_edicoes_aluno',
        'status': 'aplicada',
        'criado_em': FieldValue.serverTimestamp(),
        'criado_por_uid': usuario.uid,
        'criado_por_nome': usuario.nome,
        'criado_por_email': usuario.email,
        'aplicado_em': FieldValue.serverTimestamp(),
        'aplicado_por_uid': usuario.uid,
        'aplicado_por_nome': usuario.nome,
        'aplicado_por_email': usuario.email,
        'campos_alterados': camposAlterados,
        'dados_antes': dadosAntesReversao,
        'dados_depois': dadosDepoisReversao,
        'resumo': resumo,
        'pode_reverter': false,
        'revertido': false,
        'revertido_em': null,
        'revertido_por_uid': null,
        'revertido_por_nome': null,
        'revertido_por_email': null,
        'historico_revertido_id': historicoId,
      });
    });
  }

  Future<void> _registrarEdicaoAplicada({
    required String alunoId,
    required Map<String, dynamic> dadosAntes,
    required Map<String, dynamic> dadosDepois,
    required String tipoEdicao,
    required String origem,
    required String prefixoResumo,
    String? subtipoEdicao,
    String? resumoPersonalizado,
    bool podeReverter = true,
    required Map<String, dynamic> extras,
  }) async {
    final camposAlterados = compararDados(dadosAntes, dadosDepois);
    if (camposAlterados.isEmpty) return;

    final usuario = await _dadosUsuarioAtual();
    final dadosAntesAlterados = <String, dynamic>{};
    final dadosDepoisAlterados = <String, dynamic>{};

    for (final item in camposAlterados) {
      final campo = item['campo']?.toString() ?? '';
      dadosAntesAlterados[campo] = dadosAntes[campo];
      dadosDepoisAlterados[campo] = dadosDepois[campo];
    }

    final resumo = resumoPersonalizado?.trim().isNotEmpty == true
        ? resumoPersonalizado!.trim()
        : _resumo(prefixoResumo, camposAlterados);
    final alunoRef = _firestore.collection('alunos').doc(alunoId);
    final historicoRef = alunoRef.collection('historico_edicoes').doc();
    final batch = _firestore.batch();

    batch.set(historicoRef, {
      'aluno_id': alunoId,
      'aluno_nome': _nomeAluno(dadosDepois),
      'tipo_edicao': tipoEdicao,
      if (subtipoEdicao != null && subtipoEdicao.isNotEmpty)
        'subtipo_edicao': subtipoEdicao,
      'origem': origem,
      'status': 'aplicada',
      'criado_em': FieldValue.serverTimestamp(),
      'criado_por_uid': usuario.uid,
      'criado_por_nome': usuario.nome,
      'criado_por_email': usuario.email,
      'aplicado_em': FieldValue.serverTimestamp(),
      'aplicado_por_uid': usuario.uid,
      'aplicado_por_nome': usuario.nome,
      'aplicado_por_email': usuario.email,
      'campos_alterados': camposAlterados,
      'dados_antes': dadosAntesAlterados,
      'dados_depois': dadosDepoisAlterados,
      'resumo': resumo,
      'pode_reverter': podeReverter,
      'revertido': false,
      'revertido_em': null,
      'revertido_por_uid': null,
      'revertido_por_nome': null,
      'revertido_por_email': null,
      'historico_revertido_id': null,
      ...extras,
    });

    batch.set(alunoRef, {
      'ultima_edicao_em': FieldValue.serverTimestamp(),
      'ultima_edicao_por_uid': usuario.uid,
      'ultima_edicao_por_nome': usuario.nome,
      'ultima_edicao_por_email': usuario.email,
      'ultima_edicao_tipo': tipoEdicao,
      'ultima_edicao_subtipo': subtipoEdicao,
      'ultima_edicao_origem': origem,
      'ultima_edicao_resumo': resumo,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  static List<Map<String, dynamic>> compararDados(
    Map<String, dynamic> dadosAntes,
    Map<String, dynamic> dadosDepois, {
    Iterable<String>? camposPermitidos,
  }) {
    final campos = camposPermitidos?.toSet() ?? camposFicha;
    final alterados = <Map<String, dynamic>>[];

    for (final campo in campos) {
      if (camposIgnorados.contains(campo)) continue;
      if (!camposFicha.contains(campo)) continue;

      final antes = dadosAntes[campo];
      final depois = dadosDepois[campo];
      if (_normalizarComparacao(antes) == _normalizarComparacao(depois)) {
        continue;
      }

      alterados.add({
        'campo': campo,
        'label': labelCampo(campo),
        'antes': antes,
        'depois': depois,
      });
    }

    return alterados;
  }

  static String labelCampo(String campo) {
    final label = labelsCampos[campo];
    if (label != null) return label;

    return campo
        .replaceAll('_', ' ')
        .split(' ')
        .where((parte) => parte.isNotEmpty)
        .map((parte) => parte[0].toUpperCase() + parte.substring(1))
        .join(' ');
  }

  static String formatarValor(dynamic value, {bool somenteData = false}) {
    if (value == null) return 'Não informado';
    if (value is Timestamp) {
      return DateFormat(
        somenteData ? 'dd/MM/yyyy' : 'dd/MM/yyyy HH:mm',
      ).format(value.toDate());
    }
    if (value is DateTime) {
      return DateFormat(
        somenteData ? 'dd/MM/yyyy' : 'dd/MM/yyyy HH:mm',
      ).format(value);
    }
    if (value is bool) return value ? 'Sim' : 'Não';
    final texto = value.toString().trim();
    return texto.isEmpty ? 'Não informado' : texto;
  }

  static String tipoLegivel(String? tipo, {String? subtipo}) {
    if (subtipo == 'mudanca_turma') return 'Mudança de turma';
    if (subtipo == 'reversao_mudanca_turma') {
      return 'Reversão de mudança de turma';
    }

    switch (tipo) {
      case 'manual':
        return 'Manual';
      case 'solicitacao_area_aluno':
        return 'Solicitação do aluno/responsável';
      case 'desativacao':
        return 'Desativação';
      case 'reativacao':
        return 'Reativação';
      case 'reversao':
        return 'Reversão';
      default:
        return 'Não informado';
    }
  }

  static String _normalizarComparacao(dynamic value) {
    if (value == null) return '';
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is DocumentReference) return value.path;
    if (value is String) return value.trim();
    return value.toString();
  }

  List<String> _camposParaReversao(
    Map<String, dynamic> dadosAntes,
    dynamic camposAlterados,
  ) {
    final campos = <String>{};
    if (camposAlterados is List) {
      for (final item in camposAlterados) {
        if (item is Map && item['campo'] != null) {
          campos.add(item['campo'].toString());
        } else if (item != null) {
          campos.add(item.toString());
        }
      }
    }

    if (campos.isEmpty) campos.addAll(dadosAntes.keys);
    return campos.where((campo) => camposFicha.contains(campo)).toList();
  }

  Future<_UsuarioHistorico> _dadosUsuarioAtual() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuário não autenticado.');

    var nome = user.displayName ?? user.email ?? 'Usuário';
    var email = user.email ?? '';

    try {
      final doc = await _firestore.collection('usuarios').doc(user.uid).get();
      final data = doc.data();
      if (data != null) {
        nome =
            data['nome_completo']?.toString() ??
            data['nome']?.toString() ??
            nome;
        email = data['email']?.toString() ?? email;
      }
    } catch (e) {
      debugPrint('Erro ao buscar usuário do histórico de edição: $e');
    }

    return _UsuarioHistorico(uid: user.uid, nome: nome, email: email);
  }

  Map<String, dynamic> _mapFrom(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  String _nomeAluno(Map<String, dynamic> dados) {
    return dados['nome']?.toString().trim().isNotEmpty == true
        ? dados['nome'].toString()
        : 'Aluno';
  }

  String _resumo(String prefixo, List<Map<String, dynamic>> campos) {
    final labels = campos
        .map((item) => item['label']?.toString() ?? '')
        .where((label) => label.isNotEmpty)
        .toList();
    if (labels.isEmpty) return prefixo;
    return '$prefixo: ${labels.join(', ')}';
  }
}

class _UsuarioHistorico {
  const _UsuarioHistorico({
    required this.uid,
    required this.nome,
    required this.email,
  });

  final String uid;
  final String nome;
  final String email;
}
