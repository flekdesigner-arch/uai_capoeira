import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/alunos/services/aluno_historico_edicao_service.dart';

class VincularAlunoInativoTurmaScreen extends StatefulWidget {
  final String turmaId;
  final String turmaNome;
  final String academiaId;
  final String academiaNome;

  const VincularAlunoInativoTurmaScreen({
    super.key,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaId,
    required this.academiaNome,
  });

  @override
  State<VincularAlunoInativoTurmaScreen> createState() =>
      _VincularAlunoInativoTurmaScreenState();
}

class _MotivoReativacaoAluno {
  const _MotivoReativacaoAluno({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.icone,
    required this.cor,
  });

  final String id;
  final String titulo;
  final String descricao;
  final IconData icone;
  final Color cor;
}

class _ReativacaoPayload {
  const _ReativacaoPayload({
    required this.motivo,
    required this.observacao,
    required this.enviarWhatsApp,
    required this.destinoWhatsApp,
  });

  final _MotivoReativacaoAluno motivo;
  final String observacao;
  final bool enviarWhatsApp;
  final String destinoWhatsApp;
}

class _UsuarioReativacao {
  const _UsuarioReativacao({
    required this.uid,
    required this.nome,
    required this.email,
  });

  final String uid;
  final String nome;
  final String email;
}

class _VincularAlunoInativoTurmaScreenState
    extends State<VincularAlunoInativoTurmaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AlunoHistoricoEdicaoService _historicoService =
      AlunoHistoricoEdicaoService();

  bool _isLoading = false;
  bool _carregandoAlunos = false;
  List<Map<String, dynamic>> _alunosInativos = [];
  String? _alunoSelecionadoId;
  Map<String, dynamic>? _alunoSelecionado;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _carregarAlunosInativos();
  }

  Color _readableOn(Color background) => background.computeLuminance() > 0.48
      ? const Color(0xFF111827)
      : const Color(0xFFFFFFFF);

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();
    if (diff >= 0.26) return color;
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness(background.computeLuminance() < 0.45 ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;
  Color _appBarFg() =>
      Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());

  List<_MotivoReativacaoAluno> _motivosReativacao() {
    final t = context.uai;
    return [
      _MotivoReativacaoAluno(
        id: 'aluno_retornou_treinos',
        titulo: 'Aluno retornou aos treinos',
        descricao: 'Retorno espontâneo do aluno.',
        icone: Icons.sports_martial_arts_rounded,
        cor: t.success,
      ),
      _MotivoReativacaoAluno(
        id: 'responsavel_solicitou_retorno',
        titulo: 'Responsável solicitou retorno',
        descricao: 'Retorno solicitado pelo responsável.',
        icone: Icons.family_restroom_rounded,
        cor: t.info,
      ),
      _MotivoReativacaoAluno(
        id: 'contato_coordenacao',
        titulo: 'Reativação após contato da coordenação',
        descricao: 'Aluno voltou após acompanhamento da coordenação.',
        icone: Icons.support_agent_rounded,
        cor: t.associacao,
      ),
      _MotivoReativacaoAluno(
        id: 'retorno_pos_inatividade',
        titulo: 'Retorno após período de inatividade',
        descricao: 'Fim de um período sem frequência.',
        icone: Icons.history_toggle_off_rounded,
        cor: t.warning,
      ),
      _MotivoReativacaoAluno(
        id: 'retorno_nova_turma_horario',
        titulo: 'Retorno após mudança de horário/turma',
        descricao: 'Nova turma ou horário tornou o retorno possível.',
        icone: Icons.swap_horiz_rounded,
        cor: t.success,
      ),
      _MotivoReativacaoAluno(
        id: 'correcao_desativacao_indevida',
        titulo: 'Correção de desativação indevida',
        descricao: 'Ajuste administrativo de status.',
        icone: Icons.fact_check_rounded,
        cor: t.warning,
      ),
      _MotivoReativacaoAluno(
        id: 'transferencia_interna',
        titulo: 'Transferência interna para nova turma',
        descricao: 'Aluno retorna em outra turma interna.',
        icone: Icons.groups_rounded,
        cor: t.info,
      ),
      _MotivoReativacaoAluno(
        id: 'retorno_evento_projeto',
        titulo: 'Participação em evento/projeto',
        descricao: 'Retorno ligado a evento ou projeto.',
        icone: Icons.emoji_events_rounded,
        cor: t.associacao,
      ),
      _MotivoReativacaoAluno(
        id: 'regularizacao_cadastral',
        titulo: 'Regularização cadastral',
        descricao: 'Cadastro regularizado para retorno.',
        icone: Icons.assignment_turned_in_rounded,
        cor: t.success,
      ),
      _MotivoReativacaoAluno(
        id: 'outro',
        titulo: 'Outro motivo',
        descricao: 'Use a observação para detalhar internamente.',
        icone: Icons.more_horiz_rounded,
        cor: t.textMuted,
      ),
    ];
  }

  Future<void> _carregarAlunosInativos() async {
    setState(() => _carregandoAlunos = true);
    try {
      final alunosSnapshot = await _firestore
          .collection('alunos')
          .where('academia_id', isEqualTo: widget.academiaId)
          .where('status_atividade', isEqualTo: 'INATIVO(A)')
          .orderBy('nome')
          .get();
      if (!mounted) return;
      setState(() {
        _alunosInativos = alunosSnapshot.docs.map((doc) {
          final data = doc.data();
          return {
            ...data,
            'id': doc.id,
            'nome': data['nome'] ?? 'Sem nome',
            'apelido': data['apelido'] ?? '',
            'graduacao':
                data['graduacao_nome'] ??
                data['graduacao_atual'] ??
                'Sem graduação',
            'foto_url': data['foto_perfil_aluno'] ?? '',
            'idade': data['idade'] ?? '',
            'telefone': data['contato_aluno'] ?? data['telefone'] ?? '',
          };
        }).toList();
        _alunoSelecionadoId = null;
        _alunoSelecionado = null;
      });
    } catch (e) {
      debugPrint('Erro ao carregar alunos inativos: $e');
      if (mounted) {
        _mostrarSnack(
          'Erro ao carregar alunos inativos: $e',
          context.uai.error,
        );
      }
    } finally {
      if (mounted) setState(() => _carregandoAlunos = false);
    }
  }

  Future<bool> _podeReativarAluno() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final usuarioDoc = await _firestore
        .collection('usuarios')
        .doc(user.uid)
        .get();
    final usuarioData = usuarioDoc.data() ?? <String, dynamic>{};
    final peso = usuarioData['peso_permissao'] as int? ?? 0;
    if (peso >= 90) return true;
    final permissoesDoc = await _firestore
        .collection('usuarios')
        .doc(user.uid)
        .collection('permissoes_usuario')
        .doc('configuracoes')
        .get();
    final permissoes = permissoesDoc.data() ?? <String, dynamic>{};
    return permissoes['pode_ativar_alunos'] == true;
  }

  Future<_UsuarioReativacao> _dadosUsuarioAtual() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuário não autenticado.');
    var nome = user.displayName ?? user.email ?? 'Usuário';
    var email = user.email ?? '';
    final doc = await _firestore.collection('usuarios').doc(user.uid).get();
    final data = doc.data();
    if (data != null) {
      nome =
          data['nome_completo']?.toString() ?? data['nome']?.toString() ?? nome;
      email = data['email']?.toString() ?? email;
    }
    return _UsuarioReativacao(uid: user.uid, nome: nome, email: email);
  }

  Future<bool> _turmaTemVagaNoServidor() async {
    final turmaDoc = await _firestore
        .collection('turmas')
        .doc(widget.turmaId)
        .get(GetOptions(source: Source.server));
    final dados = turmaDoc.data();
    if (dados == null) throw Exception('Turma destino não encontrada.');
    final capacidadeMaxima = dados['capacidade_maxima'] as int? ?? 0;
    final alunosCount = dados['alunos_count'] as int? ?? 0;
    final alunosAtivos = dados['alunos_ativos'] as int? ?? 0;
    final totalAlunos = alunosAtivos > 0 ? alunosAtivos : alunosCount;
    return capacidadeMaxima <= 0 || totalAlunos < capacidadeMaxima;
  }

  Future<void> _invalidarCacheAluno(String alunoId) async {
    try {
      await _firestore
          .collection('cache_alunos')
          .doc('aluno_$alunoId')
          .delete();
      debugPrint('✅ Cache do aluno invalidado após reativação: aluno_$alunoId');
    } catch (e) {
      debugPrint('⚠️ Erro ao invalidar cache do aluno após reativação: $e');
    }
  }

  Future<void> _reativarAlunoSelecionado() async {
    if (_alunoSelecionadoId == null || _alunoSelecionado == null) {
      _mostrarSnack('Selecione um aluno para reativar.', context.uai.warning);
      return;
    }
    final podeReativar = await _podeReativarAluno();
    if (!mounted) return;
    if (!podeReativar) {
      _mostrarSnack(
        'Você não tem permissão para reativar alunos.',
        context.uai.error,
      );
      return;
    }
    final payload = await _mostrarDialogReativacao(_alunoSelecionado!);
    if (payload == null || !mounted) return;
    setState(() => _isLoading = true);
    try {
      final temVaga = await _turmaTemVagaNoServidor();
      if (!temVaga) {
        _mostrarSnack(
          'Esta turma está lotada. Escolha outra turma ou aumente a capacidade.',
          context.uai.warning,
        );
        return;
      }
      final usuario = await _dadosUsuarioAtual();
      final alunoRef = _firestore.collection('alunos').doc(_alunoSelecionadoId);
      final alunoDoc = await alunoRef.get(GetOptions(source: Source.server));
      if (!alunoDoc.exists) throw Exception('Aluno não encontrado.');
      final dadosAntes = Map<String, dynamic>.from(alunoDoc.data() ?? {});
      final updateAluno = <String, dynamic>{
        'turma_id': widget.turmaId,
        'turma': widget.turmaNome,
        'academia_id': widget.academiaId,
        'academia': widget.academiaNome,
        'status_atividade': 'ATIVO(A)',
        'data_ativacao': FieldValue.serverTimestamp(),
        'data_desativacao': null,
        'reativado_em': FieldValue.serverTimestamp(),
        'reativado_por_uid': usuario.uid,
        'reativado_por_nome': usuario.nome,
        'reativado_por_email': usuario.email,
        'reativacao_motivo_id': payload.motivo.id,
        'reativacao_motivo_titulo': payload.motivo.titulo,
        'reativacao_observacao': payload.observacao.isEmpty
            ? null
            : payload.observacao,
        'reativacao_origem': 'vincular_aluno_inativo_turma_screen',
        'reativacao_turma_id': widget.turmaId,
        'reativacao_turma_nome': widget.turmaNome,
        'reativacao_academia_id': widget.academiaId,
        'reativacao_academia_nome': widget.academiaNome,
        'ultima_edicao_em': FieldValue.serverTimestamp(),
        'ultima_edicao_por_uid': usuario.uid,
        'ultima_edicao_por_nome': usuario.nome,
        'ultima_edicao_por_email': usuario.email,
        'ultima_edicao_tipo': 'reativacao',
        'ultima_edicao_subtipo': 'reativacao_aluno',
        'ultima_edicao_origem': 'vincular_aluno_inativo_turma_screen',
        'ultima_edicao_resumo': 'Aluno reativado: ${payload.motivo.titulo}',
        'atualizado_em': FieldValue.serverTimestamp(),
      };
      final turmaRef = _firestore.collection('turmas').doc(widget.turmaId);
      final batch = _firestore.batch();
      batch.update(alunoRef, updateAluno);
      batch.set(turmaRef, {
        'alunos': FieldValue.arrayUnion([_alunoSelecionadoId]),
        'atualizado_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
      await _atualizarContadorTurma();
      await _invalidarCacheAluno(_alunoSelecionadoId!);
      final dadosDepois = Map<String, dynamic>.from(dadosAntes)
        ..addAll({
          'turma_id': widget.turmaId,
          'turma': widget.turmaNome,
          'academia_id': widget.academiaId,
          'academia': widget.academiaNome,
          'status_atividade': 'ATIVO(A)',
          'data_desativacao': null,
        });
      await _historicoService.registrarReativacaoAluno(
        alunoId: _alunoSelecionadoId!,
        dadosAntes: dadosAntes,
        dadosDepois: dadosDepois,
        motivoId: payload.motivo.id,
        motivoTitulo: payload.motivo.titulo,
        observacao: payload.observacao,
      );
      if (!mounted) return;
      _mostrarSnack(
        'Aluno reativado e vinculado com sucesso.',
        context.uai.success,
      );
      if (payload.enviarWhatsApp) {
        await _enviarWhatsAppReativacao(dadosDepois, payload);
        await _registrarWhatsAppReativacao(_alunoSelecionadoId!, payload);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Erro ao reativar aluno: $e');
      if (mounted)
        _mostrarSnack('Erro ao reativar aluno: $e', context.uai.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _atualizarContadorTurma() async {
    try {
      final snapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get(GetOptions(source: Source.server));
      final alunosCount = snapshot.docs.length;
      await _firestore.collection('turmas').doc(widget.turmaId).set({
        'alunos_count': alunosCount,
        'alunos_ativos': alunosCount,
        'atualizado_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Erro ao atualizar contador da turma: $e');
    }
  }

  Future<_ReativacaoPayload?> _mostrarDialogReativacao(
    Map<String, dynamic> aluno,
  ) async {
    final motivos = _motivosReativacao();
    final destinos = _destinosWhatsApp(aluno);
    final observacaoController = TextEditingController();
    _MotivoReativacaoAluno? motivoSelecionado;
    var enviarWhatsApp = destinos.isNotEmpty;
    var destinoWhatsApp = destinos.isNotEmpty
        ? destinos.first['id']!
        : 'nenhum';
    final result = await showModalBottomSheet<_ReativacaoPayload>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final t = context.uai;
            final nome = aluno['nome']?.toString() ?? 'Aluno';
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 720),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: t.border),
                    boxShadow: t.cardShadow,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.person_add_alt_1_rounded,
                              color: t.success,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Reativar aluno',
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: t.success.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: t.success.withOpacity(0.22),
                            ),
                          ),
                          child: Text(
                            'Aluno: $nome\nTurma destino: ${widget.turmaNome}\nNúcleo: ${widget.academiaNome}',
                            style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Motivo da reativação',
                          style: TextStyle(
                            color: t.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...motivos.map((motivo) {
                          final selected = motivoSelecionado?.id == motivo.id;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => setSheetState(
                                () => motivoSelecionado = motivo,
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? motivo.cor.withOpacity(0.12)
                                      : t.card,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected
                                        ? motivo.cor.withOpacity(0.55)
                                        : t.border,
                                    width: selected ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(motivo.icone, color: motivo.cor),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            motivo.titulo,
                                            style: TextStyle(
                                              color: t.textPrimary,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          Text(
                                            motivo.descricao,
                                            style: TextStyle(
                                              color: t.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Radio<String>(
                                      value: motivo.id,
                                      groupValue: motivoSelecionado?.id,
                                      onChanged: (_) => setSheetState(
                                        () => motivoSelecionado = motivo,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        TextField(
                          controller: observacaoController,
                          minLines: 2,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: 'Observação interna (opcional)',
                            filled: true,
                            fillColor: t.card,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Material(
                          color: Colors.transparent,
                          child: CheckboxListTile(
                            value: enviarWhatsApp,
                            onChanged: destinos.isEmpty
                                ? null
                                : (value) => setSheetState(
                                    () => enviarWhatsApp = value ?? false,
                                  ),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Enviar aviso por WhatsApp'),
                            subtitle: destinos.isEmpty
                                ? const Text(
                                    'Nenhum contato válido cadastrado.',
                                  )
                                : null,
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        ),
                        if (enviarWhatsApp && destinos.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: destinos.map((destino) {
                              return ChoiceChip(
                                selected: destinoWhatsApp == destino['id'],
                                label: Text(destino['label']!),
                                onSelected: (_) => setSheetState(
                                  () => destinoWhatsApp = destino['id']!,
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              if (motivoSelecionado == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Selecione um motivo para reativar.',
                                    ),
                                    backgroundColor: t.warning,
                                  ),
                                );
                                return;
                              }
                              Navigator.pop(
                                context,
                                _ReativacaoPayload(
                                  motivo: motivoSelecionado!,
                                  observacao: observacaoController.text.trim(),
                                  enviarWhatsApp:
                                      enviarWhatsApp && destinos.isNotEmpty,
                                  destinoWhatsApp: destinoWhatsApp,
                                ),
                              );
                            },
                            icon: const Icon(Icons.person_add_alt_1_rounded),
                            label: const Text('REATIVAR E VINCULAR'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: t.success,
                              foregroundColor: _readableOn(t.success),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    observacaoController.dispose();
    return result;
  }

  Future<void> _registrarWhatsAppReativacao(
    String alunoId,
    _ReativacaoPayload payload,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('alunos').doc(alunoId).set({
      'whatsapp_reativacao_ultimo_envio_em': FieldValue.serverTimestamp(),
      'whatsapp_reativacao_ultimo_envio_por_uid': user.uid,
      'whatsapp_reativacao_destino': payload.destinoWhatsApp,
      'whatsapp_reativacao_motivo_id': payload.motivo.id,
    }, SetOptions(merge: true));
  }

  Future<void> _enviarWhatsAppReativacao(
    Map<String, dynamic> aluno,
    _ReativacaoPayload payload,
  ) async {
    final destinos = _destinosWhatsApp(aluno).where((destino) {
      if (payload.destinoWhatsApp == 'ambos') {
        return destino['id'] == 'aluno' || destino['id'] == 'responsavel';
      }
      return destino['id'] == payload.destinoWhatsApp;
    }).toList();
    if (destinos.isEmpty) return;
    final nome = aluno['nome']?.toString() ?? 'Aluno';
    final mensagem = [
      'Olá, tudo bem?',
      '',
      'Informamos que o cadastro de $nome foi reativado na UAI Capoeira.',
      '',
      'Turma: ${widget.turmaNome}',
      'Núcleo: ${widget.academiaNome}',
      '',
      'Motivo: ${payload.motivo.titulo}',
      '',
      'Seja bem-vindo(a) de volta aos treinos!',
    ].join('\n');
    for (final destino in destinos) {
      await _abrirWhatsApp(destino['numero']!, mensagem: mensagem);
    }
  }

  List<Map<String, String>> _destinosWhatsApp(Map<String, dynamic> aluno) {
    final contatoAluno =
        aluno['contato_aluno']?.toString() ?? aluno['telefone']?.toString();
    final contatoResponsavel = aluno['contato_responsavel']?.toString();
    final destinos = <Map<String, String>>[];
    if (_temContatoValido(contatoAluno)) {
      destinos.add({'id': 'aluno', 'label': 'Aluno', 'numero': contatoAluno!});
    }
    if (_temContatoValido(contatoResponsavel) &&
        _limparNumeroContato(contatoResponsavel) !=
            _limparNumeroContato(contatoAluno)) {
      destinos.add({
        'id': 'responsavel',
        'label': 'Responsável',
        'numero': contatoResponsavel!,
      });
    }
    if (destinos.length > 1) {
      destinos.add({'id': 'ambos', 'label': 'Ambos', 'numero': ''});
    }
    return destinos;
  }

  String _limparNumeroContato(String? numero) =>
      numero?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
  bool _temContatoValido(String? numero) =>
      _limparNumeroContato(numero).length >= 10;

  String _formatarNumeroWhatsApp(String numero) {
    var cleanedPhone = numero.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanedPhone.startsWith('0')) cleanedPhone = cleanedPhone.substring(1);
    if (!cleanedPhone.startsWith('55')) cleanedPhone = '55$cleanedPhone';
    return cleanedPhone;
  }

  Future<void> _abrirWhatsApp(String numero, {String? mensagem}) async {
    final cleanedPhone = _formatarNumeroWhatsApp(numero);
    var url = 'https://wa.me/$cleanedPhone';
    if (mensagem != null && mensagem.isNotEmpty) {
      url += '?text=${Uri.encodeComponent(mensagem)}';
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _mostrarSnack(String mensagem, Color color) {
    final visible = _ensureVisible(color, context.uai.background);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: visible,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _selecionarAluno(Map<String, dynamic> aluno) {
    setState(() {
      if (_alunoSelecionadoId == aluno['id']) {
        _alunoSelecionadoId = null;
        _alunoSelecionado = null;
      } else {
        _alunoSelecionadoId = aluno['id']?.toString();
        _alunoSelecionado = aluno;
      }
    });
  }

  void _limparSelecao() {
    setState(() {
      _alunoSelecionadoId = null;
      _alunoSelecionado = null;
    });
  }

  List<Map<String, dynamic>> _filtrarAlunos() {
    final query = _normalizar(_searchQuery);
    if (query.isEmpty) return _alunosInativos;
    return _alunosInativos.where((aluno) {
      final nome = _normalizar(aluno['nome']);
      final apelido = _normalizar(aluno['apelido']);
      final graduacao = _normalizar(aluno['graduacao']);
      return nome.contains(query) ||
          apelido.contains(query) ||
          graduacao.contains(query);
    }).toList();
  }

  String _normalizar(dynamic value) {
    return value
            ?.toString()
            .toLowerCase()
            .trim()
            .replaceAll('á', 'a')
            .replaceAll('à', 'a')
            .replaceAll('â', 'a')
            .replaceAll('ã', 'a')
            .replaceAll('é', 'e')
            .replaceAll('ê', 'e')
            .replaceAll('í', 'i')
            .replaceAll('ó', 'o')
            .replaceAll('ô', 'o')
            .replaceAll('õ', 'o')
            .replaceAll('ú', 'u')
            .replaceAll('ç', 'c') ??
        '';
  }

  String _iniciais(String nome) {
    final partes = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first.characters.first.toUpperCase();
    return '${partes.first.characters.first}${partes.last.characters.first}'
        .toUpperCase();
  }

  Widget _buildAlunoCard(Map<String, dynamic> aluno) {
    final t = context.uai;
    final selecionado = aluno['id'] == _alunoSelecionadoId;
    final accent = selecionado
        ? _ensureVisible(t.success, t.card)
        : _ensureVisible(t.primary, t.card);
    final nome = aluno['nome']?.toString() ?? 'Sem nome';
    final fotoUrl = aluno['foto_url']?.toString() ?? '';
    final apelido = aluno['apelido']?.toString() ?? '';
    final graduacao = aluno['graduacao']?.toString() ?? 'Sem graduação';
    final idade = aluno['idade']?.toString() ?? '';
    final telefone = aluno['telefone']?.toString() ?? '';
    final motivoDesativacao =
        aluno['desativacao_motivo_titulo']?.toString() ?? '';
    final dataDesativacao = aluno['desativado_em'] ?? aluno['data_desativacao'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Material(
        color: selecionado
            ? Color.alphaBlend(accent.withOpacity(0.08), t.card)
            : t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _selecionarAluno(aluno),
          borderRadius: BorderRadius.circular(t.cardRadius),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius),
              border: Border.all(
                color: selecionado ? accent.withOpacity(0.55) : t.border,
                width: selecionado ? 1.6 : 1,
              ),
              boxShadow: t.softShadow,
            ),
            child: Row(
              children: [
                _buildAvatar(nome, fotoUrl, selecionado, accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          color: selecionado ? accent : t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (apelido.isNotEmpty)
                            _buildMiniChip(
                              Icons.alternate_email_rounded,
                              apelido,
                              t.info,
                            ),
                          _buildMiniChip(
                            Icons.workspace_premium_rounded,
                            graduacao,
                            t.primary,
                          ),
                          if (idade.isNotEmpty)
                            _buildMiniChip(
                              Icons.cake_rounded,
                              '$idade anos',
                              t.success,
                            ),
                          if (telefone.isNotEmpty)
                            _buildMiniChip(
                              Icons.phone_rounded,
                              telefone,
                              t.info,
                            ),
                          if (motivoDesativacao.isNotEmpty)
                            _buildMiniChip(
                              Icons.flag_rounded,
                              motivoDesativacao,
                              t.warning,
                            ),
                          if (dataDesativacao != null)
                            _buildMiniChip(
                              Icons.event_busy_rounded,
                              AlunoHistoricoEdicaoService.formatarValor(
                                dataDesativacao,
                              ),
                              t.textMuted,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Radio<String>(
                  value: aluno['id'].toString(),
                  groupValue: _alunoSelecionadoId,
                  onChanged: (_) => _selecionarAluno(aluno),
                  activeColor: accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(
    String nome,
    String fotoUrl,
    bool selecionado,
    Color accent,
  ) {
    final t = context.uai;
    final temFoto =
        fotoUrl.trim().isNotEmpty &&
        (fotoUrl.startsWith('http://') || fotoUrl.startsWith('https://'));
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selecionado ? accent : t.border,
          width: selecionado ? 2.4 : 1.4,
        ),
      ),
      child: ClipOval(
        child: temFoto
            ? Image.network(
                fotoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _avatarFallback(nome),
              )
            : _avatarFallback(nome),
      ),
    );
  }

  Widget _avatarFallback(String nome) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);
    return Container(
      color: Color.alphaBlend(primary.withOpacity(0.10), t.cardAlt),
      alignment: Alignment.center,
      child: Text(
        _iniciais(nome),
        style: TextStyle(
          color: primary,
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildMiniChip(IconData icon, String label, Color color) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.07), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 12),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);
    final selecionado =
        _alunoSelecionado?['nome']?.toString() ?? 'Nenhum selecionado';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 4),
        boxShadow: t.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.person_add_alt_1_rounded,
              color: onPrimary,
              size: 30,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reativar aluno inativo',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Escolha apenas um aluno por vez para voltar à turma.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onPrimary.withOpacity(0.78),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildWhiteChip(
                      Icons.person_off_rounded,
                      '${_alunosInativos.length} inativo(s)',
                    ),
                    _buildWhiteChip(Icons.check_circle_rounded, selecionado),
                    _buildWhiteChip(Icons.groups_rounded, widget.turmaNome),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhiteChip(IconData icon, String label) {
    final onPrimary = _readableOn(context.uai.primary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onPrimary, size: 13),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onPrimary,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);
    return TextField(
      onChanged: (value) => setState(() => _searchQuery = value),
      style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700),
      cursorColor: primary,
      decoration: InputDecoration(
        hintText: 'Buscar aluno inativo...',
        hintStyle: TextStyle(color: t.textMuted),
        prefixIcon: Icon(Icons.search_rounded, color: primary),
        suffixIcon: _searchQuery.trim().isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpar busca',
                onPressed: () => setState(() => _searchQuery = ''),
                icon: Icon(Icons.close_rounded, color: t.textSecondary),
              ),
        filled: true,
        fillColor: t.cardAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
      ),
    );
  }

  Widget _buildResumoBar(List<Map<String, dynamic>> filtrados) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.card);
    final success = _ensureVisible(t.success, t.card);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildResumoChip(
                  Icons.filter_alt_rounded,
                  '${filtrados.length} exibido(s)',
                  primary,
                ),
                _buildResumoChip(
                  Icons.check_circle_rounded,
                  _alunoSelecionadoId == null
                      ? 'Nenhum selecionado'
                      : '1 selecionado',
                  success,
                ),
              ],
            ),
          ),
          if (_alunoSelecionadoId != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: _limparSelecao,
              style: TextButton.styleFrom(
                foregroundColor: t.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Limpar seleção',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResumoChip(IconData icon, String label, Color color) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(0.13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onReload,
  }) {
    final t = context.uai;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 430),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 74, color: t.textMuted),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textSecondary,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (onReload != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onReload,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('RECARREGAR'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ensureVisible(t.primary, t.card),
                    side: BorderSide(color: t.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(t.buttonRadius),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    final t = context.uai;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(22),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: t.border),
          boxShadow: t.softShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: t.primary),
            const SizedBox(height: 14),
            Text(
              'Carregando alunos inativos...',
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final alunosFiltrados = _filtrarAlunos();
    final nomeSelecionado = _alunoSelecionado?['nome']?.toString();
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: _appBarBg(),
        foregroundColor: _appBarFg(),
        iconTheme: IconThemeData(color: _appBarFg()),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reativar aluno inativo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            Text(
              widget.turmaNome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _appBarFg().withOpacity(0.78),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregandoAlunos || _isLoading
                ? null
                : _carregarAlunosInativos,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _carregandoAlunos
          ? _buildLoadingState()
          : LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth > 860
                    ? 860.0
                    : constraints.maxWidth;
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: RefreshIndicator(
                      color: t.primary,
                      backgroundColor: t.surface,
                      onRefresh: _carregarAlunosInativos,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
                        children: [
                          _buildHero(),
                          const SizedBox(height: 12),
                          _buildSearchField(),
                          const SizedBox(height: 12),
                          _buildResumoBar(alunosFiltrados),
                          const SizedBox(height: 12),
                          if (_alunosInativos.isEmpty)
                            _buildEmptyState(
                              icon: Icons.person_off_rounded,
                              title: 'Nenhum aluno inativo',
                              subtitle:
                                  'Não existem alunos inativos nesta academia para vincular à turma.',
                              onReload: _carregarAlunosInativos,
                            )
                          else if (alunosFiltrados.isEmpty)
                            _buildEmptyState(
                              icon: Icons.search_off_rounded,
                              title: 'Nenhum aluno encontrado',
                              subtitle:
                                  'Tente buscar por outro nome, apelido ou graduação.',
                            )
                          else
                            ...alunosFiltrados.map(_buildAlunoCard),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: _alunoSelecionadoId != null
          ? FloatingActionButton.extended(
              onPressed: _isLoading ? null : _reativarAlunoSelecionado,
              backgroundColor: t.primary,
              foregroundColor: _readableOn(t.primary),
              icon: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: _readableOn(t.primary),
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.person_add_alt_1_rounded),
              label: Text(
                _isLoading
                    ? 'PROCESSANDO...'
                    : nomeSelecionado?.isNotEmpty == true
                    ? 'VINCULAR $nomeSelecionado'
                    : 'REATIVAR E VINCULAR',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
