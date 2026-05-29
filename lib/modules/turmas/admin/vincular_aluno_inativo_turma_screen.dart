import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';

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

class _VincularAlunoInativoTurmaScreenState
    extends State<VincularAlunoInativoTurmaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool _carregandoAlunos = false;

  List<Map<String, dynamic>> _alunosInativos = [];
  List<String> _alunosSelecionadosIds = [];

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _carregarAlunosInativos();
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

  Color _appBarBg() =>
      Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;

  Color _appBarFg() =>
      Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());

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
            'id': doc.id,
            'nome': data['nome'] ?? 'Sem nome',
            'apelido': data['apelido'] ?? '',
            'graduacao': data['graduacao_atual'] ?? 'Sem graduação',
            'foto_url': data['foto_perfil_aluno'] ?? '',
            'idade': data['idade'] ?? '',
            'telefone': data['telefone'] ?? '',
            'selecionado': false,
          };
        }).toList();

        _alunosSelecionadosIds.clear();
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
      if (mounted) {
        setState(() => _carregandoAlunos = false);
      }
    }
  }

  Future<void> _vincularAlunosSelecionados() async {
    if (_alunosSelecionadosIds.isEmpty) {
      _mostrarSnack(
        'Selecione pelo menos um aluno',
        context.uai.warning,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final batch = _firestore.batch();

      for (final alunoId in _alunosSelecionadosIds) {
        final alunoRef = _firestore.collection('alunos').doc(alunoId);

        batch.update(alunoRef, {
          'turma_id': widget.turmaId,
          'turma': widget.turmaNome,
          'status_atividade': 'ATIVO(A)',
          'atualizado_em': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      await _atualizarContadorTurma();

      if (!mounted) return;

      _mostrarSnack(
        '${_alunosSelecionadosIds.length} aluno(s) vinculado(s) e ativado(s)!',
        context.uai.success,
      );

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Erro ao vincular alunos: $e');

      if (mounted) {
        _mostrarSnack(
          'Erro ao vincular alunos: $e',
          context.uai.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _atualizarContadorTurma() async {
    try {
      final snapshot = await _firestore
          .collection('alunos')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get();

      final alunosCount = snapshot.docs.length;

      await _firestore.collection('turmas').doc(widget.turmaId).update({
        'alunos_count': alunosCount,
        'alunos_ativos': alunosCount,
        'atualizado_em': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Erro ao atualizar contador da turma: $e');
    }
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

  void _toggleSelecaoAluno(String alunoId, bool selecionado) {
    setState(() {
      if (selecionado) {
        if (!_alunosSelecionadosIds.contains(alunoId)) {
          _alunosSelecionadosIds.add(alunoId);
        }
      } else {
        _alunosSelecionadosIds.remove(alunoId);
      }

      final index =
      _alunosInativos.indexWhere((aluno) => aluno['id'] == alunoId);

      if (index != -1) {
        _alunosInativos[index]['selecionado'] = selecionado;
      }
    });
  }

  void _selecionarTodosFiltrados() {
    final filtrados = _filtrarAlunos();

    setState(() {
      for (final aluno in filtrados) {
        final id = aluno['id'].toString();

        if (!_alunosSelecionadosIds.contains(id)) {
          _alunosSelecionadosIds.add(id);
        }

        aluno['selecionado'] = true;

        final index = _alunosInativos.indexWhere((a) => a['id'] == id);
        if (index != -1) {
          _alunosInativos[index]['selecionado'] = true;
        }
      }
    });
  }

  void _limparSelecao() {
    setState(() {
      _alunosSelecionadosIds.clear();

      for (final aluno in _alunosInativos) {
        aluno['selecionado'] = false;
      }
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
        .where((parte) => parte.trim().isNotEmpty)
        .toList();

    if (partes.isEmpty) return '?';

    if (partes.length == 1) {
      return partes.first.characters.first.toUpperCase();
    }

    return '${partes.first.characters.first}${partes.last.characters.first}'
        .toUpperCase();
  }

  Widget _buildAlunoCard(Map<String, dynamic> aluno) {
    final t = context.uai;
    final bool selecionado = aluno['selecionado'] == true;
    final primary = _ensureVisible(t.primary, t.card);
    final success = _ensureVisible(t.success, t.card);
    final accent = selecionado ? success : primary;

    final nome = aluno['nome']?.toString() ?? 'Sem nome';
    final fotoUrl = aluno['foto_url']?.toString() ?? '';
    final apelido = aluno['apelido']?.toString() ?? '';
    final graduacao = aluno['graduacao']?.toString() ?? 'Sem graduação';
    final idade = aluno['idade']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Material(
        color: selecionado
            ? Color.alphaBlend(accent.withOpacity(0.08), t.card)
            : t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _toggleSelecaoAluno(aluno['id'], !selecionado),
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
                _buildAvatar(
                  nome: nome,
                  fotoUrl: fotoUrl,
                  selecionado: selecionado,
                  accent: accent,
                ),
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
                              icon: Icons.alternate_email_rounded,
                              label: apelido,
                              color: t.info,
                            ),
                          _buildMiniChip(
                            icon: Icons.workspace_premium_rounded,
                            label: graduacao,
                            color: t.primary,
                          ),
                          if (idade.isNotEmpty)
                            _buildMiniChip(
                              icon: Icons.cake_rounded,
                              label: '$idade anos',
                              color: t.success,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Checkbox(
                  value: selecionado,
                  onChanged: (value) {
                    _toggleSelecaoAluno(aluno['id'], value ?? false);
                  },
                  activeColor: accent,
                  checkColor: _readableOn(accent),
                  side: BorderSide(
                    color: selecionado ? accent : t.border,
                    width: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar({
    required String nome,
    required String fotoUrl,
    required bool selecionado,
    required Color accent,
  }) {
    final t = context.uai;
    final temFoto = fotoUrl.trim().isNotEmpty &&
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
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;

            return Container(
              color: t.cardAlt,
              alignment: Alignment.center,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.primary,
                ),
              ),
            );
          },
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

  Widget _buildMiniChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
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
            constraints: const BoxConstraints(maxWidth: 180),
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
                  widget.turmaNome,
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
                  widget.academiaNome,
                  maxLines: 1,
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
                      icon: Icons.person_off_rounded,
                      label: '${_alunosInativos.length} inativo(s)',
                    ),
                    _buildWhiteChip(
                      icon: Icons.check_circle_rounded,
                      label: '${_alunosSelecionadosIds.length} selecionado(s)',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhiteChip({
    required IconData icon,
    required String label,
  }) {
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
          Text(
            label,
            style: TextStyle(
              color: onPrimary,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
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
      style: TextStyle(
        color: t.textPrimary,
        fontWeight: FontWeight.w700,
      ),
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
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                  icon: Icons.filter_alt_rounded,
                  label: '${filtrados.length} exibido(s)',
                  color: primary,
                ),
                _buildResumoChip(
                  icon: Icons.check_circle_rounded,
                  label: '${_alunosSelecionadosIds.length} selecionado(s)',
                  color: success,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextButton(
                onPressed:
                filtrados.isNotEmpty ? _selecionarTodosFiltrados : null,
                style: TextButton.styleFrom(
                  foregroundColor: primary,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'TODOS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
              TextButton(
                onPressed:
                _alunosSelecionadosIds.isNotEmpty ? _limparSelecao : null,
                style: TextButton.styleFrom(
                  foregroundColor: t.textSecondary,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'LIMPAR',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResumoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
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
              'Vincular alunos inativos',
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
          final maxWidth =
          constraints.maxWidth > 860 ? 860.0 : constraints.maxWidth;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                children: [
                  Expanded(
                    child: RefreshIndicator(
                      color: t.primary,
                      backgroundColor: t.surface,
                      onRefresh: _carregarAlunosInativos,
                      child: ListView(
                        padding:
                        const EdgeInsets.fromLTRB(14, 14, 14, 100),
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
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: _alunosSelecionadosIds.isNotEmpty
          ? FloatingActionButton.extended(
        onPressed: _isLoading ? null : _vincularAlunosSelecionados,
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
            : const Icon(Icons.check_rounded),
        label: Text(
          _isLoading
              ? 'PROCESSANDO...'
              : 'VINCULAR (${_alunosSelecionadosIds.length})',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
