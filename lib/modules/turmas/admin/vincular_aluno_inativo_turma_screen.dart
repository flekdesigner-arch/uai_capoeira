import 'dart:ui' show ImageFilter;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/core/theme/app_theme_tokens.dart';
import 'package:uai_capoeira/modules/alunos/services/aluno_historico_edicao_service.dart';
import 'package:uai_capoeira/modules/alunos/screens/editar_aluno_screen.dart';
import 'package:uai_capoeira/modules/disciplina/disciplina_service.dart';

class VincularAlunoInativoTurmaScreen extends StatefulWidget {
  final String? turmaId;
  final String? turmaNome;
  final List<Map<String, dynamic>> turmasDisponiveis;
  final String academiaId;
  final String academiaNome;
  final String? alunoIdInicial;

  const VincularAlunoInativoTurmaScreen({
    super.key,
    this.turmaId,
    this.turmaNome,
    this.turmasDisponiveis = const [],
    required this.academiaId,
    required this.academiaNome,
    this.alunoIdInicial,
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
  bool _abrindoFluxo = false;
  List<Map<String, dynamic>> _alunosInativos = [];
  String? _alunoSelecionadoId;
  Map<String, dynamic>? _alunoSelecionado;
  String _searchQuery = '';
  bool _aberturaInicialRealizada = false;

  String? _turmaDestinoId;
  String? _turmaDestinoNome;

  String get _turmaId => _turmaDestinoId ?? widget.turmaId ?? '';
  String get _turmaNome => _turmaDestinoNome ?? widget.turmaNome ?? 'A escolher';

  @override
  void initState() {
    super.initState();
    _carregarAlunosInativos();
  }

  Color _readableOn(Color background) => background.computeLuminance() > 0.48
      ? const Color(0xFF111827)
      : const Color(0xFFFFFFFF);

  // Contraste do cabeçalho original, inclusive no tema Verde Neon.
  Color _onPrimaryText(UaiThemeTokens t) {
    final temaEscuro =
        t.background.computeLuminance() < 0.45 ||
        t.surface.computeLuminance() < 0.45;
    return temaEscuro ? Colors.white : _readableOn(t.primary);
  }

  // Informações resumidas da turma no diálogo original de seleção.
  String _descricaoCurtaTurma(Map<String, dynamic> turma) {
    final dias = turma['dias_semana']?.toString() ?? '';
    final horario = turma['horario']?.toString() ?? '';
    final alunos = turma['alunos_ativos']?.toString() ?? '0';
    final capacidade = turma['capacidade_maxima']?.toString() ?? '0';
    final partes = <String>[
      if (dias.isNotEmpty) dias,
      if (horario.isNotEmpty) horario,
      '$alunos/$capacidade alunos',
    ];
    return partes.join(' • ');
  }

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
      // Quando vier dos Detalhes do Aluno, abrir apenas o aluno solicitado.
      if (!_aberturaInicialRealizada && widget.alunoIdInicial != null) {
        _aberturaInicialRealizada = true;
        final candidatos = _alunosInativos.where(
          (item) => item['id']?.toString() == widget.alunoIdInicial,
        );
        if (candidatos.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _abrirAlunoParaReativacao(candidatos.first);
          });
        } else {
          _mostrarSnack('Este aluno não está mais inativo nesta academia.', context.uai.warning);
        }
      }
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
        .doc(_turmaId)
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

  Future<Map<String, dynamic>?> _escolherTurmaDestino() async {
    final turmas = widget.turmasDisponiveis;
    if (turmas.isEmpty) {
      if (widget.turmaId == null || widget.turmaId!.isEmpty) {
        _mostrarSnack('Nenhuma turma disponível para reativação.', context.uai.warning);
        return null;
      }
      return {'id': widget.turmaId!, 'nome': widget.turmaNome ?? 'Turma'};
    }
    // O mesmo diálogo de seleção de turma que existia no AppBar de Inativos,
    // antes da inversão do fluxo. Apenas o resultado do clique muda.
    return _abrirDialogoOriginalSelecaoTurma(turmas);
  }

  Future<Map<String, dynamic>?> _abrirDialogoOriginalSelecaoTurma(List<Map<String, dynamic>> turmas) {
    final t = context.uai;

    final onPrimary = _onPrimaryText(t);

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: t.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.cardRadius),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: t.primaryGradient,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(t.cardRadius),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: onPrimary.withAlpha(36),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          Icons.group_add_rounded,
                          color: onPrimary,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Selecione uma turma',
                          style: TextStyle(
                            color: onPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    itemCount: turmas.length,
                    itemBuilder: (context, index) {
                      final turma = turmas[index];
                      final corTurma = _getColorFromHex(turma['cor_turma']);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: t.card,
                          borderRadius: BorderRadius.circular(t.cardRadius - 6),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => Navigator.pop(context, turma),
                            child: Container(
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  t.cardRadius - 6,
                                ),
                                border: Border.all(color: t.border),
                              ),
                              child: Row(
                                children: [
                                  _buildLogoTurma(turma, size: 44),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          turma['nome']?.toString() ?? 'Turma',
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w900,
                                            color: t.textPrimary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _descricaoCurtaTurma(turma),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: t.textSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: corTurma,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('CANCELAR'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  Widget _buildLogoTurma(Map<String, dynamic> turma, {double size = 40}) {
    final corTurma = _getColorFromHex(turma['cor_turma']);

    if (turma['logo_url'] != null && turma['logo_url'].toString().isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.uai.cardAlt,
          border: Border.all(color: corTurma.withAlpha(71), width: 2),
        ),
        child: ClipOval(
          child: Image.network(
            turma['logo_url'],
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildFallbackLogo(turma, size, corTurma);
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;

              return Center(
                child: SizedBox(
                  width: size * 0.38,
                  height: size * 0.38,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(corTurma),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return _buildFallbackLogo(turma, size, corTurma);
  }

  Widget _buildFallbackLogo(
    Map<String, dynamic> turma,
    double size,
    Color corTurma,
  ) {
    final nome = turma['nome']?.toString() ?? '';
    final iniciais = nome.isNotEmpty ? nome.substring(0, 1).toUpperCase() : 'T';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: corTurma.withAlpha(31),
        border: Border.all(color: corTurma.withAlpha(128), width: 2),
      ),
      child: Center(
        child: Text(
          iniciais,
          style: TextStyle(
            color: corTurma,
            fontWeight: FontWeight.w900,
            fontSize: size * 0.4,
          ),
        ),
      ),
    );
  }

  Color _getColorFromHex(String hexColor) {
    try {
      return Color(int.parse(hexColor.replaceFirst('#', '0xFF')));
    } catch (_) {
      return context.uai.uniformes;
    }
  }


  Future<bool> _podeAutorizarRetornoExpulso() async {
    final uid=_auth.currentUser?.uid;
    if(uid == null) return false;
    final doc=await _firestore.collection('usuarios').doc(uid)
      .get(const GetOptions(source:Source.server));
    final u=doc.data() ?? <String,dynamic>{};
    final peso=(u['peso_permissao'] as num?)?.toInt() ?? 0;
    final tipo=u['tipo']?.toString().toLowerCase() ?? '';
    return peso>=90 || ['admin','administrador','super_admin','superadmin'].contains(tipo)
      || u['admin']==true || u['administrador']==true || u['isAdmin']==true
      || u['super_admin']==true || u['superadmin']==true;
  }

  Future<bool?> _alertaExpulso(Map<String,dynamic> aluno) => showDialog<bool>(
    context:context,barrierDismissible:false,builder:(ctx)=>AlertDialog(
      title:const Row(children:[Icon(Icons.gpp_bad_rounded,color:Colors.red),
        SizedBox(width:8),Expanded(child:Text('ATENÇÃO: ALUNO EXPULSO'))]),
      content:Text('Este cadastro foi DESATIVADO POR EXPULSÃO.\n\n'
        'Aluno: ${aluno['nome'] ?? 'Não informado'}\n'
        'Motivo: ${aluno['expulsao_motivo_titulo'] ?? 'Não informado'}\n'
        'Quem expulsou: ${aluno['expulsao_por_nome'] ?? 'Não identificado'}\n\n'
        'Reativar exigirá revisão completa, uma justificativa adicional '
        'e autorização administrativa auditada. Deseja continuar?'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Iniciar revisão'))],
    ));

  Future<String?> _confirmarReintegracaoExpulso(Map<String,dynamic> aluno) async {
    final ctrl=TextEditingController();
    var aceito=false;
    try {
      return await showDialog<String>(context:context,barrierDismissible:false,
        builder:(ctx)=>StatefulBuilder(builder:(ctx,setModal)=>AlertDialog(
          title:const Row(children:[Icon(Icons.warning_amber_rounded,color:Colors.red),
            SizedBox(width:8),Expanded(child:Text('Reativar aluno anteriormente expulso?'))]),
          content:SizedBox(width:450,child:SingleChildScrollView(child:Column(
            mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('Aluno: ${aluno['nome'] ?? ''}'),
              const SizedBox(height:8),
              Text('Expulso por: ${aluno['expulsao_por_nome'] ?? 'Não identificado'}'),
              Text('Motivo: ${aluno['expulsao_motivo_titulo'] ?? 'Não informado'}'),
              const SizedBox(height:12),
              const Text('A expulsão permanecerá no histórico. Esta decisão registrará quem autorizou o retorno, motivo e justificativa.'),
              const SizedBox(height:12),
              TextField(controller:ctrl,maxLength:500,minLines:2,maxLines:4,onChanged:(_)=>setModal((){}),
                decoration:const InputDecoration(labelText:'Justificativa da reintegração (mínimo 8 caracteres)',
                  border:OutlineInputBorder())),
              CheckboxListTile(contentPadding:EdgeInsets.zero,value:aceito,
                onChanged:(v)=>setModal(()=>aceito=v??false),
                title:const Text('Confirmo que revisei a expulsão e autorizo formalmente a reativação.')),
            ]))),
          actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
            FilledButton(onPressed:aceito&&ctrl.text.trim().length>=8
              ?()=>Navigator.pop(ctx,ctrl.text.trim()):null,
              child:const Text('Confirmar reintegração'))],
        )));
    } finally {ctrl.dispose();}
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
    // Alunos expulsos devem ser identificados antes de iniciar qualquer revisão.
    if (_alunoSelecionado!['expulso_ativo'] == true) {
      if (!await _podeAutorizarRetornoExpulso()) {
        if(mounted)_mostrarSnack('Somente administrador pode reintegrar um aluno expulso.',context.uai.error);
        return;
      }
      if(!mounted)return;
      final confirmado = await _alertaExpulso(_alunoSelecionado!);
      if (!mounted || confirmado != true) return;
    }
    final payload = await _mostrarDialogReativacao(_alunoSelecionado!);
    if (payload == null || !mounted) return;
    final destino = await _escolherTurmaDestino();
    if (destino == null || !mounted) return;
    final idDestino = destino['id']?.toString() ?? '';
    if (idDestino.isEmpty) return;
    setState(() {
      _turmaDestinoId = idDestino;
      _turmaDestinoNome = destino['nome']?.toString() ?? 'Turma';
      _isLoading = true;
    });
    try {
      final temVaga = await _turmaTemVagaNoServidor();
      if (!mounted) return;
      if (!temVaga) {
        _mostrarSnack(
          'Esta turma está lotada. Escolha outra turma ou aumente a capacidade.',
          context.uai.warning,
        );
        return;
      }
      // A escolha da turma não reativa ninguém: primeiro revisão obrigatória.
      // Cancelar/voltar deixa o aluno INATIVO, sem atualizar turma nem contadores.
      setState(() => _isLoading = false);
      final revisado = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => EditarAlunoScreen(
            alunoId: _alunoSelecionadoId,
            modoReativacao: true,
            turmaReativacaoNome: _turmaDestinoNome,
          ),
        ),
      );
      if (!mounted || revisado != true) return;
      setState(() => _isLoading = true);
      // Revalidar permissão/vaga após o tempo de revisão, antes da gravação.
      if (!await _podeReativarAluno()) {
        throw StateError('Sua permissão de reativação mudou durante a revisão.');
      }
      if (!await _turmaTemVagaNoServidor()) {
        throw StateError('A turma ficou lotada durante a revisão. Escolha outra turma.');
      }
      final usuario = await _dadosUsuarioAtual();
      final alunoRef = _firestore.collection('alunos').doc(_alunoSelecionadoId);
      final alunoDoc = await alunoRef.get(GetOptions(source: Source.server));
      if (!alunoDoc.exists) throw Exception('Aluno não encontrado.');
      final dadosAntes = Map<String, dynamic>.from(alunoDoc.data() ?? {});
      if (dadosAntes['status_atividade'] == 'ATIVO(A)') {
        throw StateError('Este aluno já está ativo. Atualize a lista antes de prosseguir.');
      }
      // Para um expulso, NÃO é permitido ativar por batch no cliente.
      // Exige nova confirmação após a revisão, pois a situação pode mudar.
      final eraExpulso = dadosAntes['expulso_ativo'] == true;
      if (eraExpulso) {
        final justificativa = await _confirmarReintegracaoExpulso(dadosAntes);
        if (!mounted || justificativa == null) return;
        await DisciplinaService.reativarExpulso(
          alunoId:_alunoSelecionadoId!,turmaId:_turmaId,
          motivoId:payload.motivo.id,motivoTitulo:payload.motivo.titulo,
          justificativa:justificativa,
          comandoId:'retorno_${DateTime.now().microsecondsSinceEpoch}_${_alunoSelecionadoId!}',
        );
      } else {
      final updateAluno = <String, dynamic>{
        'turma_id': _turmaId,
        'turma': _turmaNome,
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
        'reativacao_turma_id': _turmaId,
        'reativacao_turma_nome': _turmaNome,
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
      final turmaRef = _firestore.collection('turmas').doc(_turmaId);
      final batch = _firestore.batch();
      batch.update(alunoRef, updateAluno);
      batch.set(turmaRef, {
        'alunos': FieldValue.arrayUnion([_alunoSelecionadoId]),
        'atualizado_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
      final dadosDepois = Map<String, dynamic>.from(dadosAntes)
        ..addAll({
          'turma_id': _turmaId,
          'turma': _turmaNome,
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
      }
      await _atualizarContadorTurma();
      await _invalidarCacheAluno(_alunoSelecionadoId!);
      final dadosDepois = <String,dynamic>{...dadosAntes,
        'turma_id':_turmaId,'turma':_turmaNome,
        'academia_id':widget.academiaId,'academia':widget.academiaNome,
        'status_atividade':'ATIVO(A)','expulso_ativo':false,'data_desativacao':null};
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
        { _mostrarSnack('Erro ao reativar aluno: $e', context.uai.error); }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _atualizarContadorTurma() async {
    try {
      final snapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: _turmaId)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get(GetOptions(source: Source.server));
      final alunosCount = snapshot.docs.length;
      await _firestore.collection('turmas').doc(_turmaId).set({
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
    final result = await showGeneralDialog<_ReativacaoPayload>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fechar reativação',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        // O BackdropFilter cobre a rota inteira; o formulário permanece nítido.
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
          child: ColoredBox(
            color: Colors.black.withAlpha(95),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Material(
                type: MaterialType.transparency,
                child: StatefulBuilder(
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
                  constraints: BoxConstraints(
                    maxWidth: 720,
                    maxHeight: MediaQuery.sizeOf(context).height * 0.87,
                  ),
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
                            color: t.success.withAlpha(26),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: t.success.withAlpha(56),
                            ),
                          ),
                          child: Row(
                            children: [
                              _buildAvatar(nome,
                                  aluno['foto_url']?.toString() ?? '', false, t.success),
                              const SizedBox(width: 12),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(nome.toUpperCase(), maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: t.textPrimary,
                                          fontSize: 14, fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 5),
                                  Text('INATIVO • ${widget.academiaNome}',
                                      style: TextStyle(color: t.textSecondary,
                                          fontSize: 11, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text('Turma será escolhida na próxima etapa',
                                      style: TextStyle(color: t.textSecondary, fontSize: 11)),
                                ],
                              )),
                            ],
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
                        DropdownButtonFormField<String>(
                          initialValue: motivoSelecionado?.id,
                          isExpanded: true,
                          dropdownColor: t.surface,
                          decoration: InputDecoration(
                            labelText: 'Selecione o motivo',
                            prefixIcon: Icon(
                              motivoSelecionado?.icone ?? Icons.flag_outlined,
                              color: motivoSelecionado?.cor ?? t.textSecondary,
                            ),
                            filled: true,
                            fillColor: t.card,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: t.border),
                            ),
                          ),
                          items: motivos.map((motivo) => DropdownMenuItem<String>(
                            value: motivo.id,
                            child: Row(
                              children: [
                                Icon(motivo.icone, size: 18, color: motivo.cor),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    motivo.titulo,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: TextStyle(
                                      color: t.textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )).toList(),
                          onChanged: (id) {
                            setSheetState(() {
                              for (final motivo in motivos) {
                                if (motivo.id == id) {
                                  motivoSelecionado = motivo;
                                  break;
                                }
                              }
                            });
                          },
                        ),
                        if (motivoSelecionado != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: motivoSelecionado!.cor.withAlpha(20),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: motivoSelecionado!.cor.withAlpha(65),
                              ),
                            ),
                            child: Text(
                              motivoSelecionado!.descricao,
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
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
                            label: const Text('CONTINUAR'),
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
                ),
              ),
            ),
          ),
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
      'Turma: $_turmaNome',
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

  Future<void> _abrirAlunoParaReativacao(Map<String, dynamic> aluno) async {
    if (_isLoading || _abrindoFluxo) return;
    _abrindoFluxo = true;
    setState(() {
      _alunoSelecionadoId = aluno['id']?.toString();
      _alunoSelecionado = aluno;
    });
    try {
      await _reativarAlunoSelecionado();
    } finally {
      _abrindoFluxo = false;
      if (mounted && !_isLoading) {
        setState(() {
          _alunoSelecionadoId = null;
          _alunoSelecionado = null;
        });
      }
    }
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
    final nome = aluno['nome']?.toString() ?? 'Sem nome';
    final expulso = aluno['expulso_ativo'] == true;
    final fotoUrl = aluno['foto_url']?.toString() ?? '';
    final graduacao = aluno['graduacao']?.toString().trim() ?? '';
    final data = aluno['desativado_em'] ?? aluno['data_desativacao'];
    final temFoto = fotoUrl.startsWith('https://') || fotoUrl.startsWith('http://');
    final dataFormatada = data == null
        ? 'Data de desativação não registrada'
        : 'Desativado em: ${AlunoHistoricoEdicaoService.formatarValor(data)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(17),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _isLoading || _abrindoFluxo ? null : () => _abrirAlunoParaReativacao(aluno),
          child: Container(
            constraints: const BoxConstraints(minHeight: 110),
            decoration: BoxDecoration(
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 98,
                  height: 116,
                  child: Stack(fit: StackFit.expand, children: [
                    temFoto
                        ? Image.network(fotoUrl, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _avatarFallback(nome))
                        : _avatarFallback(nome),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        color: t.error,
                        child: Text(expulso ? 'EXPULSO' : 'INATIVO', textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 10,
                            fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ]),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nome.toUpperCase(), maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: t.textPrimary, fontSize: 13,
                            height: 1.15, fontWeight: FontWeight.w900)),
                        if (expulso) ...[
                          const SizedBox(height:5),
                          Text('EXPULSÃO DISCIPLINAR · REATIVAÇÃO RESTRITA',
                            style:TextStyle(color:t.error,fontWeight:FontWeight.w900,fontSize:10)),
                          Text('${aluno['expulsao_motivo_titulo'] ?? 'Motivo não informado'}',
                            maxLines:2,overflow:TextOverflow.ellipsis,
                            style:TextStyle(color:t.error,fontSize:10)),
                        ],
                        const SizedBox(height: 8),
                        Text(graduacao.isEmpty ? 'SEM GRADUAÇÃO' : graduacao.toUpperCase(),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: t.textSecondary,
                            fontSize: 10.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Row(children: [
                          Icon(Icons.event_busy_rounded, size: 13, color: t.textMuted),
                          const SizedBox(width: 5),
                          Expanded(child: Text(dataFormatada,
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: t.textSecondary,
                              fontSize: 10, fontWeight: FontWeight.w600))),
                        ]),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.chevron_right_rounded, color: t.primary, size: 20),
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
                errorBuilder: (_, _, _) => _avatarFallback(nome),
              )
            : _avatarFallback(nome),
      ),
    );
  }

  Widget _avatarFallback(String nome) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);
    return Container(
      color: Color.alphaBlend(primary.withAlpha(26), t.cardAlt),
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
              '1. Aluno  →  2. Motivo  →  3. Turma',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _appBarFg().withAlpha(199),
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
                          _buildSearchField(),
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
    );
  }
}
