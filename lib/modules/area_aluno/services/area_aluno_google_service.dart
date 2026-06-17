import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:uai_capoeira/modules/area_aluno/screens/area_aluno_dashboard_screen.dart';
import 'package:uai_capoeira/modules/area_aluno/services/area_aluno_session_service.dart';
import 'package:uai_capoeira/modules/auth/screens/auth_check.dart';

class AlunoVinculadoGoogle {
  final String alunoId;
  final String nome;
  final String foto;
  final String turma;
  final String academia;
  final String statusAtividade;
  final String graduacao;
  final String emailGoogle;
  final String nomeGoogle;

  const AlunoVinculadoGoogle({
    required this.alunoId,
    required this.nome,
    required this.foto,
    required this.turma,
    required this.academia,
    required this.statusAtividade,
    required this.graduacao,
    required this.emailGoogle,
    required this.nomeGoogle,
  });

  factory AlunoVinculadoGoogle.fromMap(Map<String, dynamic> data) {
    return AlunoVinculadoGoogle(
      alunoId: _text(data['alunoId'] ?? data['aluno_id'] ?? data['id']),
      nome: _text(data['nome'], fallback: 'Aluno'),
      foto: _text(data['foto']),
      turma: _text(data['turma']),
      academia: _text(data['academia']),
      statusAtividade: _text(data['status_atividade']),
      graduacao: _text(data['graduacao']),
      emailGoogle: _text(data['areaAlunoGoogleEmail']),
      nomeGoogle: _text(data['areaAlunoGoogleNome']),
    );
  }

  static String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') return fallback;
    return text;
  }
}

class AreaAlunoGoogleService {
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final AreaAlunoSessionService _sessionService;

  AreaAlunoGoogleService({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    AreaAlunoSessionService? sessionService,
  }) : _functions = functions ?? FirebaseFunctions.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _sessionService = sessionService ?? AreaAlunoSessionService();

  Future<List<AlunoVinculadoGoogle>> buscarAlunosVinculados() async {
    final result = await _functions
        .httpsCallable('buscarAlunosVinculadosAoGoogle')
        .call();
    final data = Map<String, dynamic>.from(result.data as Map);
    final raw = data['alunos'];
    if (data['success'] != true || raw is! List) return const [];

    return raw
        .whereType<Map>()
        .map(
          (item) =>
              AlunoVinculadoGoogle.fromMap(Map<String, dynamic>.from(item)),
        )
        .where((aluno) => aluno.alunoId.isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>?> prepararAcessoAreaAluno(
    AlunoVinculadoGoogle aluno,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final result = await _functions
        .httpsCallable('validarAcessoGoogleAreaAluno')
        .call({'alunoId': aluno.alunoId});
    final data = Map<String, dynamic>.from(result.data as Map);

    if (data['success'] != true) return null;

    final alunoData = Map<String, dynamic>.from(data['aluno'] as Map? ?? {});
    final config = Map<String, dynamic>.from(data['config'] as Map? ?? {});
    final alunoId =
        alunoData['aluno_id']?.toString() ??
        alunoData['id']?.toString() ??
        alunoData['docId']?.toString() ??
        aluno.alunoId;
    final alunoNome = alunoData['nome']?.toString() ?? aluno.nome;

    final authPayload = {
      'modo_acesso': 'google',
      'aluno_id_login': alunoId,
      'aluno_id': alunoId,
      'aluno_nome_login': alunoNome,
      'google_uid': user.uid,
      'google_email': user.email ?? '',
      'login_google_em': DateTime.now().toIso8601String(),
    };

    await _sessionService.salvarSessao(
      aluno: alunoData,
      config: config,
      authPayload: authPayload,
      alunoSelecionadoId: alunoId,
      ultimoAlunoSelecionadoId: alunoId,
      googleUid: user.uid,
      googleEmail: user.email ?? '',
      alunosVinculadosResumo: [
        {
          'alunoId': aluno.alunoId,
          'nome': aluno.nome,
          'foto': aluno.foto,
          'turma': aluno.turma,
          'academia': aluno.academia,
          'status_atividade': aluno.statusAtividade,
          'graduacao': aluno.graduacao,
        },
      ],
    );

    await _registrarLog('alternou_para_area_aluno', {
      'aluno_id': alunoId,
      'aluno_nome': alunoNome,
    });

    return {'aluno': alunoData, 'config': config, 'authPayload': authPayload};
  }

  Future<void> abrirAreaAlunoVinculado(
    BuildContext context,
    AlunoVinculadoGoogle aluno, {
    bool limparPilha = true,
  }) async {
    final acesso = await prepararAcessoAreaAluno(aluno);
    if (acesso == null || !context.mounted) return;

    final route = MaterialPageRoute(
      builder: (_) => AreaAlunoDashboardScreen(
        aluno: Map<String, dynamic>.from(acesso['aluno'] as Map),
        config: Map<String, dynamic>.from(acesso['config'] as Map),
        authPayload: Map<String, dynamic>.from(acesso['authPayload'] as Map),
      ),
    );

    if (limparPilha) {
      Navigator.pushAndRemoveUntil(context, route, (route) => false);
    } else {
      Navigator.pushReplacement(context, route);
    }
  }

  Future<void> abrirGestao(BuildContext context) async {
    await _registrarLog('alternou_para_gestao', {});
    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthCheck()),
      (route) => false,
    );
  }

  Future<void> _registrarLog(String evento, Map<String, dynamic> dados) async {
    try {
      await _functions.httpsCallable('registrarEventoGoogleAreaAluno').call({
        'evento': evento,
        'dados': dados,
      });
    } catch (_) {
      // Log interno não deve bloquear a navegação do aluno.
    }
  }
}
