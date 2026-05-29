import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class GerenciarAlunosTurmaScreen extends StatefulWidget {
  final String turmaId;
  final String turmaNome;
  final String academiaNome;

  const GerenciarAlunosTurmaScreen({
    super.key,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaNome,
  });

  @override
  State<GerenciarAlunosTurmaScreen> createState() =>
      _GerenciarAlunosTurmaScreenState();
}

class _GerenciarAlunosTurmaScreenState
    extends State<GerenciarAlunosTurmaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  List<Map<String, dynamic>> _alunosVinculados = [];
  List<Map<String, dynamic>> _alunosDisponiveis = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _carregarAlunos();
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff =
    (color.computeLuminance() - background.computeLuminance()).abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  String _safeText(dynamic value, [String fallback = '']) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }

  Future<void> _carregarAlunos() async {
    setState(() => _isLoading = true);

    try {
      final alunosVinculadosSnapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get();

      final vinculados = alunosVinculadosSnapshot.docs.map((doc) {
        final data = doc.data();

        return {
          'id': doc.id,
          'nome': data['nome'] ?? 'Sem nome',
          'apelido': data['apelido'] ?? '',
          'graduacao': data['graduacao_atual'] ?? 'Sem graduação',
          'foto_url': data['foto_perfil_aluno'] ?? '',
        };
      }).toList();

      final todosAlunosSnapshot = await _firestore
          .collection('alunos')
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get();

      final alunosVinculadosIds =
      alunosVinculadosSnapshot.docs.map((doc) => doc.id).toList();

      final disponiveis = todosAlunosSnapshot.docs.map((doc) {
        final data = doc.data();

        final bool jaVinculado = alunosVinculadosIds.contains(doc.id);
        final bool temTurma =
            data['turma_id'] != null && data['turma_id'].toString().isNotEmpty;
        final bool turmaDiferente = temTurma && data['turma_id'] != widget.turmaId;

        return {
          'id': doc.id,
          'nome': data['nome'] ?? 'Sem nome',
          'apelido': data['apelido'] ?? '',
          'graduacao': data['graduacao_atual'] ?? 'Sem graduação',
          'foto_url': data['foto_perfil_aluno'] ?? '',
          'ja_vinculado': jaVinculado,
          'tem_turma_atual': temTurma,
          'turma_atual': turmaDiferente ? data['turma'] : '',
          'turma_id_atual': turmaDiferente ? data['turma_id'] : null,
        };
      }).where((aluno) {
        return aluno['ja_vinculado'] != true;
      }).toList();

      vinculados.sort((a, b) {
        return a['nome'].toString().compareTo(b['nome'].toString());
      });

      disponiveis.sort((a, b) {
        final aTemTurma = a['tem_turma_atual'] == true;
        final bTemTurma = b['tem_turma_atual'] == true;

        if (aTemTurma != bTemTurma) return aTemTurma ? 1 : -1;

        return a['nome'].toString().compareTo(b['nome'].toString());
      });

      if (!mounted) return;

      setState(() {
        _alunosVinculados = vinculados;
        _alunosDisponiveis = disponiveis;
      });
    } catch (e) {
      debugPrint('Erro ao carregar alunos: $e');

      if (mounted) {
        _showSnack(
          'Erro ao carregar alunos: $e',
          type: _SnackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _vincularAluno(
      String alunoId,
      Map<String, dynamic> alunoData,
      ) async {
    setState(() => _isLoading = true);

    try {
      await _firestore.collection('alunos').doc(alunoId).update({
        'turma_id': widget.turmaId,
        'turma': widget.turmaNome,
        'atualizado_em': FieldValue.serverTimestamp(),
        'atualizado_por': 'Sistema',
      });

      await _atualizarContadorAlunos();
      await _carregarAlunos();

      if (mounted) {
        _showSnack(
          'Aluno ${alunoData['nome']} vinculado com sucesso!',
          type: _SnackType.success,
        );
      }
    } catch (e) {
      debugPrint('Erro ao vincular aluno: $e');

      if (mounted) {
        _showSnack(
          'Erro ao vincular aluno: $e',
          type: _SnackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removerVinculoAluno(
      String alunoId,
      Map<String, dynamic> alunoData,
      ) async {
    setState(() => _isLoading = true);

    try {
      await _firestore.collection('alunos').doc(alunoId).update({
        'turma_id': null,
        'turma': null,
        'atualizado_em': FieldValue.serverTimestamp(),
        'atualizado_por': 'Sistema',
      });

      await _atualizarContadorAlunos();
      await _carregarAlunos();

      if (mounted) {
        _showSnack(
          'Aluno ${alunoData['nome']} removido da turma!',
          type: _SnackType.success,
        );
      }
    } catch (e) {
      debugPrint('Erro ao remover vínculo: $e');

      if (mounted) {
        _showSnack(
          'Erro ao remover aluno: $e',
          type: _SnackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _atualizarContadorAlunos() async {
    try {
      final alunosAtivosSnapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get();

      await _firestore.collection('turmas').doc(widget.turmaId).update({
        'alunos_count': alunosAtivosSnapshot.docs.length,
        'alunos_ativos': alunosAtivosSnapshot.docs.length,
        'atualizado_em': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Erro ao atualizar contador: $e');
    }
  }

  Widget _buildAlunoVinculadoCard(Map<String, dynamic> aluno) {
    final t = context.uai;
    final error = _ensureVisible(t.error, t.card);

    return _buildAlunoCard(
      aluno: aluno,
      accent: t.primary,
      warning: false,
      trailing: IconButton(
        icon: Icon(Icons.close_rounded, color: error),
        onPressed: () => _showConfirmacaoRemocao(aluno['id'], aluno),
        tooltip: 'Remover da turma',
      ),
    );
  }

  Widget _buildAlunoDisponivelCard(Map<String, dynamic> aluno) {
    final t = context.uai;
    final bool temTurmaAtual = aluno['tem_turma_atual'] ?? false;
    final Color accent =
    _ensureVisible(temTurmaAtual ? t.warning : t.primary, t.card);

    return _buildAlunoCard(
      aluno: aluno,
      accent: accent,
      warning: temTurmaAtual,
      trailing: ElevatedButton(
        onPressed: () => _showConfirmacaoVinculo(aluno['id'], aluno),
        style: ElevatedButton.styleFrom(
          backgroundColor: temTurmaAtual ? t.warning : t.primary,
          foregroundColor: _readableOn(temTurmaAtual ? t.warning : t.primary),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        child: Text(temTurmaAtual ? 'TROCAR' : 'VINCULAR'),
      ),
    );
  }

  Widget _buildAlunoCard({
    required Map<String, dynamic> aluno,
    required Color accent,
    required bool warning,
    required Widget trailing,
  }) {
    final t = context.uai;

    final nome = _safeText(aluno['nome'], 'Sem nome');
    final apelido = _safeText(aluno['apelido']);
    final graduacao = _safeText(aluno['graduacao'], 'Sem graduação');
    final fotoUrl = _safeText(aluno['foto_url']);
    final turmaAtual = _safeText(aluno['turma_atual']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: warning
            ? Color.alphaBlend(accent.withOpacity(0.08), t.card)
            : t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(
              color: warning ? accent.withOpacity(0.24) : t.border,
            ),
            boxShadow: t.softShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _avatarAluno(fotoUrl: fotoUrl, accent: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                    if (apelido.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Apelido: $apelido',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      'Graduação: $graduacao',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (warning && turmaAtual.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _smallPill(
                        icon: Icons.warning_amber_rounded,
                        label: 'Turma atual: $turmaAtual',
                        color: accent,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarAluno({
    required String fotoUrl,
    required Color accent,
  }) {
    final t = context.uai;

    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: t.cardAlt,
        border: Border.all(color: accent.withOpacity(0.18), width: 1.4),
      ),
      child: ClipOval(
        child: fotoUrl.isNotEmpty
            ? Image.network(
          fotoUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _avatarFallback(accent);
          },
        )
            : _avatarFallback(accent),
      ),
    );
  }

  Widget _avatarFallback(Color accent) {
    final t = context.uai;

    return Container(
      color: Color.alphaBlend(accent.withOpacity(0.09), t.cardAlt),
      child: Icon(
        Icons.person_rounded,
        color: accent,
        size: 27,
      ),
    );
  }

  void _showConfirmacaoRemocao(
      String alunoId,
      Map<String, dynamic> aluno,
      ) {
    final nome = _safeText(aluno['nome'], 'este aluno');

    _showConfirmDialog(
      title: 'Remover Aluno',
      icon: Icons.person_remove_alt_1_rounded,
      color: context.uai.error,
      message:
      'Tem certeza que deseja remover $nome da turma ${widget.turmaNome}?',
      confirmLabel: 'REMOVER',
      onConfirm: () => _removerVinculoAluno(alunoId, aluno),
    );
  }

  void _showConfirmacaoVinculo(
      String alunoId,
      Map<String, dynamic> aluno,
      ) {
    final bool temTurmaAtual = aluno['tem_turma_atual'] ?? false;
    final String turmaAtual = _safeText(aluno['turma_atual']);
    final String nome = _safeText(aluno['nome'], 'este aluno');

    final message = temTurmaAtual && turmaAtual.isNotEmpty
        ? 'Deseja vincular $nome à turma ${widget.turmaNome}?\n\nATENÇÃO: Este aluno já está na turma "$turmaAtual". Ao vincular aqui, ele será automaticamente removido da turma anterior.'
        : 'Deseja vincular $nome à turma ${widget.turmaNome}?';

    _showConfirmDialog(
      title: 'Vincular Aluno',
      icon: temTurmaAtual
          ? Icons.swap_horiz_rounded
          : Icons.person_add_alt_1_rounded,
      color: temTurmaAtual ? context.uai.warning : context.uai.success,
      message: message,
      confirmLabel: temTurmaAtual ? 'TROCAR TURMA' : 'VINCULAR',
      onConfirm: () => _vincularAluno(alunoId, aluno),
    );
  }

  Future<void> _showConfirmDialog({
    required String title,
    required IconData icon,
    required Color color,
    required String message,
    required String confirmLabel,
    required VoidCallback onConfirm,
  }) async {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 2),
              clipBehavior: Clip.antiAlias,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.cardRadius + 2),
                  border: Border.all(color: t.border),
                  boxShadow: t.cardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.12),
                            borderRadius:
                            BorderRadius.circular(t.buttonRadius),
                          ),
                          child: Icon(icon, color: accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: Icon(
                            Icons.close_rounded,
                            color: t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      message,
                      style: TextStyle(
                        color: t.textSecondary,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 380;

                        final cancel = OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: t.textPrimary,
                            side: BorderSide(color: t.border),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(t.buttonRadius),
                            ),
                          ),
                          child: const Text(
                            'CANCELAR',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        );

                        final confirm = ElevatedButton(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            onConfirm();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: color,
                            foregroundColor: _readableOn(color),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(t.buttonRadius),
                            ),
                          ),
                          child: Text(
                            confirmLabel,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        );

                        if (narrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              cancel,
                              const SizedBox(height: 10),
                              confirm,
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: cancel),
                            const SizedBox(width: 10),
                            Expanded(child: confirm),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _filtrarAlunosDisponiveis() {
    if (_searchQuery.trim().isEmpty) return _alunosDisponiveis;

    final query = _searchQuery.toLowerCase().trim();

    return _alunosDisponiveis.where((aluno) {
      final nome = aluno['nome'].toString().toLowerCase();
      final apelido = aluno['apelido'].toString().toLowerCase();
      final graduacao = aluno['graduacao'].toString().toLowerCase();

      return nome.contains(query) ||
          apelido.contains(query) ||
          graduacao.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: t.background,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Gerenciar Alunos',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              Text(
                widget.turmaNome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: t.textSecondary,
                ),
              ),
              Text(
                widget.academiaNome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: t.textMuted,
                ),
              ),
            ],
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(112),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: TextField(
                    style: TextStyle(color: t.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Buscar aluno por nome, apelido ou graduação...',
                      hintStyle: TextStyle(color: t.textMuted),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: _ensureVisible(t.primary, t.cardAlt),
                      ),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                        tooltip: 'Limpar busca',
                        onPressed: () =>
                            setState(() => _searchQuery = ''),
                        icon: Icon(
                          Icons.close_rounded,
                          color: t.textSecondary,
                        ),
                      ),
                      filled: true,
                      fillColor: t.cardAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(t.inputRadius),
                        borderSide: BorderSide(color: t.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(t.inputRadius),
                        borderSide: BorderSide(color: t.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(t.inputRadius),
                        borderSide: BorderSide(
                          color: _ensureVisible(t.primary, t.cardAlt),
                          width: 1.4,
                        ),
                      ),
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                Material(
                  color: t.surface,
                  child: TabBar(
                    isScrollable: false,
                    labelColor: t.primary,
                    unselectedLabelColor: t.textSecondary,
                    indicatorColor: t.primary,
                    indicatorWeight: 3,
                    tabs: [
                      Tab(
                        icon: const Icon(Icons.group_rounded),
                        text: 'VINCULADOS (${_alunosVinculados.length})',
                      ),
                      Tab(
                        icon: const Icon(Icons.person_add_rounded),
                        text: 'DISPONÍVEIS (${_filtrarAlunosDisponiveis().length})',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: t.primary))
            : TabBarView(
          children: [
            _buildVinculadosTab(),
            _buildDisponiveisTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildVinculadosTab() {
    final t = context.uai;

    if (_alunosVinculados.isEmpty) {
      return _emptyState(
        icon: Icons.group_off_rounded,
        title: 'Nenhum aluno vinculado',
        text: 'Vá para a aba "Disponíveis" para adicionar alunos.',
        color: t.primary,
      );
    }

    return RefreshIndicator(
      color: t.primary,
      backgroundColor: t.surface,
      onRefresh: _carregarAlunos,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        itemCount: _alunosVinculados.length,
        itemBuilder: (context, index) {
          return _buildAlunoVinculadoCard(_alunosVinculados[index]);
        },
      ),
    );
  }

  Widget _buildDisponiveisTab() {
    final t = context.uai;
    final alunos = _filtrarAlunosDisponiveis();

    if (alunos.isEmpty) {
      return _emptyState(
        icon: Icons.person_search_rounded,
        title: 'Nenhum aluno disponível',
        text: _searchQuery.trim().isEmpty
            ? 'Não há alunos ativos disponíveis para vincular.'
            : 'Nenhum aluno encontrado para essa busca.',
        color: t.warning,
      );
    }

    return RefreshIndicator(
      color: t.primary,
      backgroundColor: t.surface,
      onRefresh: _carregarAlunos,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        itemCount: alunos.length,
        itemBuilder: (context, index) {
          return _buildAlunoDisponivelCard(alunos[index]);
        },
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String text,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Material(
          color: t.card,
          borderRadius: BorderRadius.circular(t.cardRadius),
          clipBehavior: Clip.antiAlias,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius),
              border: Border.all(color: accent.withOpacity(0.16)),
              boxShadow: t.softShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 68, color: accent),
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
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _smallPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.09), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 12),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, {required _SnackType type}) {
    final t = context.uai;

    final color = switch (type) {
      _SnackType.success => t.success,
      _SnackType.error => t.error,
      _SnackType.warning => t.warning,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

enum _SnackType {
  success,
  error,
  warning,
}
