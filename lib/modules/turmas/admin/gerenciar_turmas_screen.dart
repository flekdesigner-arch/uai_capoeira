import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

import 'editar_turma_screen.dart';
import 'gerenciar_alunos_turma_screen.dart';

class GerenciarTurmasScreen extends StatefulWidget {
  final String academiaId;
  final String academiaNome;

  const GerenciarTurmasScreen({
    super.key,
    required this.academiaId,
    required this.academiaNome,
  });

  @override
  State<GerenciarTurmasScreen> createState() => _GerenciarTurmasScreenState();
}

class _GerenciarTurmasScreenState extends State<GerenciarTurmasScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _filterStatus = 'Todas';
  String _filterFaixaEtaria = 'Todas';

  final List<String> _statusOptions = const [
    'Todas',
    'ATIVA',
    'INATIVA',
    'ESGOTADA',
  ];

  final List<String> _faixaEtariaOptions = const [
    'Todas',
    'INFANTIL',
    'JUVENIL',
    'ADULTO',
    'SENIOR',
    'MISTA',
  ];

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

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  String _text(dynamic value, [String fallback = '']) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }

  Color _parseColor(dynamic value, {Color fallback = const Color(0xFF059669)}) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty) return fallback;

    try {
      final clean = text.replaceAll('#', '').toUpperCase();

      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      }

      if (clean.length == 8) {
        return Color(int.parse(clean, radix: 16));
      }
    } catch (_) {}

    return fallback;
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'ATIVA':
        return context.uai.success;
      case 'ESGOTADA':
        return context.uai.warning;
      case 'INATIVA':
        return context.uai.textMuted;
      default:
        return context.uai.error;
    }
  }

  Color _ocupacaoColor(int ocupacao) {
    if (ocupacao >= 90) return context.uai.error;
    if (ocupacao >= 70) return context.uai.warning;
    return context.uai.success;
  }

  String _faixaEtariaIcon(String faixa) {
    switch (faixa.toUpperCase()) {
      case 'INFANTIL':
        return '👶';
      case 'JUVENIL':
        return '🧒';
      case 'ADULTO':
        return '👨';
      case 'SENIOR':
        return '👴';
      case 'MISTA':
        return '👥';
      default:
        return '👥';
    }
  }

  String _diasSemanaAbreviados(List<dynamic> dias) {
    if (dias.isEmpty) return 'Sem horário';

    final abreviacoes = {
      'SEGUNDA': 'SEG',
      'TERCA': 'TER',
      'TERÇA': 'TER',
      'QUARTA': 'QUA',
      'QUINTA': 'QUI',
      'SEXTA': 'SEX',
      'SABADO': 'SAB',
      'SÁBADO': 'SAB',
      'DOMINGO': 'DOM',
    };

    return dias.map((dia) {
      final key = dia.toString().toUpperCase();
      return abreviacoes[key] ?? key;
    }).join(', ');
  }

  Future<void> _abrirTurma({String? turmaId}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditarTurmaScreen(
          academiaId: widget.academiaId,
          academiaNome: widget.academiaNome,
          turmaId: turmaId,
        ),
      ),
    );
  }

  Future<void> _abrirAlunosTurma({
    required String turmaId,
    required String turmaNome,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GerenciarAlunosTurmaScreen(
          turmaId: turmaId,
          turmaNome: turmaNome,
          academiaNome: widget.academiaNome,
        ),
      ),
    );
  }

  Future<void> _showDeleteConfirmation(String turmaId, String turmaNome) async {
    int alunosCount = 0;

    try {
      final turmaDoc = await _firestore.collection('turmas').doc(turmaId).get();
      final data = turmaDoc.data();
      alunosCount = _toInt(data?['alunos_count']);
    } catch (e) {
      debugPrint('Erro ao buscar turma para exclusão: $e');
    }

    if (!mounted) return;

    final confirmacaoController = TextEditingController();
    bool nomeConfere = false;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final t = context.uai;
        final error = _ensureVisible(t.error, t.surface);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final currentConfere =
                confirmacaoController.text.trim() == turmaNome;

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
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: error.withOpacity(0.12),
                                  borderRadius:
                                  BorderRadius.circular(t.buttonRadius),
                                ),
                                child: Icon(
                                  Icons.warning_rounded,
                                  color: error,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Confirmar Exclusão',
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: t.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            alunosCount > 0
                                ? 'A turma "$turmaNome" possui $alunosCount aluno(s) matriculado(s).\n\nTodos os vínculos com alunos serão removidos.'
                                : 'Tem certeza que deseja excluir a turma "$turmaNome"?\n\nEsta ação não pode ser desfeita.',
                            style: TextStyle(
                              color: t.textSecondary,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Para confirmar, digite o nome da turma:',
                            style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: Color.alphaBlend(
                                error.withOpacity(0.10),
                                t.cardAlt,
                              ),
                              borderRadius:
                              BorderRadius.circular(t.inputRadius),
                              border:
                              Border.all(color: error.withOpacity(0.16)),
                            ),
                            child: Text(
                              '"$turmaNome"',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: error,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: confirmacaoController,
                            style: TextStyle(color: t.textPrimary),
                            decoration: InputDecoration(
                              labelText: 'Digite o nome da turma',
                              labelStyle: TextStyle(color: t.textSecondary),
                              filled: true,
                              fillColor: t.cardAlt,
                              prefixIcon: Icon(
                                Icons.warning_amber_rounded,
                                color: error,
                              ),
                              suffixIcon:
                              confirmacaoController.text.isNotEmpty
                                  ? Icon(
                                currentConfere
                                    ? Icons.check_circle_rounded
                                    : Icons.error_rounded,
                                color: currentConfere
                                    ? t.success
                                    : t.error,
                              )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius:
                                BorderRadius.circular(t.inputRadius),
                                borderSide: BorderSide(color: t.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius:
                                BorderRadius.circular(t.inputRadius),
                                borderSide: BorderSide(color: t.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius:
                                BorderRadius.circular(t.inputRadius),
                                borderSide:
                                BorderSide(color: error, width: 1.4),
                              ),
                            ),
                            onChanged: (value) {
                              setDialogState(() {
                                nomeConfere = value.trim() == turmaNome;
                              });
                            },
                          ),
                          const SizedBox(height: 18),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 380;

                              final cancel = OutlinedButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: t.textPrimary,
                                  side: BorderSide(color: t.border),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      t.buttonRadius,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  'CANCELAR',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              );

                              final excluir = ElevatedButton(
                                onPressed: nomeConfere
                                    ? () => Navigator.pop(dialogContext, true)
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: t.error,
                                  foregroundColor: _readableOn(t.error),
                                  disabledBackgroundColor: t.cardAlt,
                                  disabledForegroundColor: t.textMuted,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      t.buttonRadius,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  'EXCLUIR TURMA',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              );

                              if (narrow) {
                                return Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                                  children: [
                                    cancel,
                                    const SizedBox(height: 10),
                                    excluir,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: cancel),
                                  const SizedBox(width: 10),
                                  Expanded(child: excluir),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    confirmacaoController.dispose();

    if (confirmado == true) {
      await _realizarExclusaoTurma(turmaId, turmaNome, alunosCount);
    }
  }

  Future<void> _realizarExclusaoTurma(
      String turmaId,
      String turmaNome,
      int alunosCount,
      ) async {
    try {
      if (alunosCount > 0) {
        final vinculosSnapshot = await _firestore
            .collection('alunos_turmas')
            .where('turma_id', isEqualTo: turmaId)
            .get();

        for (final vinculo in vinculosSnapshot.docs) {
          await vinculo.reference.delete();
        }
      }

      await _firestore.collection('turmas').doc(turmaId).delete();

      await _atualizarContadorTurmas();

      if (mounted) {
        _showSnack(
          'Turma "$turmaNome" excluída com sucesso!',
          type: _SnackType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
          'Erro ao excluir: $e',
          type: _SnackType.error,
        );
      }
    }
  }

  Future<void> _atualizarContadorTurmas() async {
    try {
      final turmasSnapshot = await _firestore
          .collection('turmas')
          .where('academia_id', isEqualTo: widget.academiaId)
          .get();

      await _firestore.collection('academias').doc(widget.academiaId).update({
        'turmas_count': turmasSnapshot.docs.length,
        'atualizado_em': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Erro ao atualizar contador: $e');
    }
  }

  Widget _buildFiltroStatus() {
    return _buildFilterChip(
      label: _filterStatus,
      icon: Icons.circle_rounded,
      selected: _filterStatus != 'Todas',
      onSelected: (selected) {
        if (!selected) {
          setState(() => _filterStatus = 'Todas');
          return;
        }

        _abrirSelecaoFiltro(
          titulo: 'Filtrar por status',
          icon: Icons.circle_rounded,
          opcoes: _statusOptions,
          valorAtual: _filterStatus,
          onSelected: (value) => setState(() => _filterStatus = value),
        );
      },
    );
  }

  Widget _buildFiltroFaixaEtaria() {
    return _buildFilterChip(
      label: _filterFaixaEtaria,
      icon: Icons.people_rounded,
      selected: _filterFaixaEtaria != 'Todas',
      onSelected: (selected) {
        if (!selected) {
          setState(() => _filterFaixaEtaria = 'Todas');
          return;
        }

        _abrirSelecaoFiltro(
          titulo: 'Filtrar por faixa etária',
          icon: Icons.people_rounded,
          opcoes: _faixaEtariaOptions,
          valorAtual: _filterFaixaEtaria,
          onSelected: (value) => setState(() => _filterFaixaEtaria = value),
        );
      },
    );
  }

  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);
    final foreground = selected ? _readableOn(primary) : t.textPrimary;

    return FilterChip(
      selected: selected,
      showCheckmark: false,
      selectedColor: primary,
      backgroundColor: t.cardAlt,
      side: BorderSide(color: selected ? primary : t.border),
      onSelected: onSelected,
      avatar: Icon(icon, size: 17, color: foreground),
      label: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Future<void> _abrirSelecaoFiltro({
    required String titulo,
    required IconData icon,
    required List<String> opcoes,
    required String valorAtual,
    required ValueChanged<String> onSelected,
  }) async {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.surface);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Material(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 2),
              clipBehavior: Clip.antiAlias,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.cardRadius + 2),
                  border: Border.all(color: t.border),
                  boxShadow: t.cardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 8, 10),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.12),
                              borderRadius:
                              BorderRadius.circular(t.buttonRadius),
                              border: Border.all(
                                color: primary.withOpacity(0.16),
                              ),
                            ),
                            child: Icon(icon, color: primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              titulo,
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
                    ),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                        itemCount: opcoes.length,
                        itemBuilder: (context, index) {
                          final opcao = opcoes[index];
                          final selected = valorAtual == opcao;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: selected
                                  ? Color.alphaBlend(
                                primary.withOpacity(0.11),
                                t.cardAlt,
                              )
                                  : t.cardAlt,
                              borderRadius:
                              BorderRadius.circular(t.inputRadius),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () {
                                  onSelected(opcao);
                                  Navigator.pop(dialogContext);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius:
                                    BorderRadius.circular(t.inputRadius),
                                    border: Border.all(
                                      color: selected
                                          ? primary.withOpacity(0.34)
                                          : t.border,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          opcao,
                                          style: TextStyle(
                                            color: selected
                                                ? primary
                                                : t.textPrimary,
                                            fontWeight: selected
                                                ? FontWeight.w900
                                                : FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (selected)
                                        Icon(
                                          Icons.check_circle_rounded,
                                          color: primary,
                                          size: 20,
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
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _aplicarFiltros(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    var turmas = docs.toList();

    if (_filterStatus != 'Todas') {
      turmas = turmas.where((doc) {
        return doc.data()['status']?.toString() == _filterStatus;
      }).toList();
    }

    if (_filterFaixaEtaria != 'Todas') {
      turmas = turmas.where((doc) {
        return doc.data()['faixa_etaria']?.toString() == _filterFaixaEtaria;
      }).toList();
    }

    turmas.sort((a, b) {
      final dataA = a.data();
      final dataB = b.data();

      final statusA = dataA['status']?.toString() ?? '';
      final statusB = dataB['status']?.toString() ?? '';

      if (statusA == 'ATIVA' && statusB != 'ATIVA') return -1;
      if (statusA != 'ATIVA' && statusB == 'ATIVA') return 1;

      final nomeA = dataA['nome']?.toString().toLowerCase() ?? '';
      final nomeB = dataB['nome']?.toString().toLowerCase() ?? '';
      return nomeA.compareTo(nomeB);
    });

    return turmas;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Gerenciar Turmas',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              widget.academiaNome,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore
            .collection('turmas')
            .where('academia_id', isEqualTo: widget.academiaId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState();
          }

          if (snapshot.hasError) {
            return _buildStateCard(
              icon: Icons.error_outline_rounded,
              title: 'Erro ao carregar turmas',
              text: snapshot.error.toString(),
              color: t.error,
            );
          }

          final docs = snapshot.data?.docs ?? [];
          final turmas = _aplicarFiltros(docs);

          return RefreshIndicator(
            color: t.primary,
            backgroundColor: t.surface,
            onRefresh: () async {
              if (mounted) setState(() {});
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeroCard(
                          total: docs.length,
                          exibidas: turmas.length,
                        ),
                        const SizedBox(height: 14),
                        _buildSearchAndFilters(),
                        const SizedBox(height: 14),
                        if (docs.isEmpty)
                          _buildEmptyState()
                        else if (turmas.isEmpty)
                          _buildStateCard(
                            icon: Icons.search_off_rounded,
                            title: 'Nenhuma turma encontrada',
                            text:
                            'Tente limpar os filtros ou buscar por outro termo.',
                            color: t.warning,
                            compact: true,
                          )
                        else
                          _buildTurmasList(turmas),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _abrirTurma(),
        backgroundColor: t.primary,
        foregroundColor: _readableOn(t.primary),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _buildLoadingState() {
    final t = context.uai;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: t.primary),
          const SizedBox(height: 16),
          Text(
            'Carregando turmas...',
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard({
    required int total,
    required int exibidas,
  }) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final iconBox = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.groups_rounded,
              color: onPrimary,
              size: 34,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Turmas da Academia',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 22 : 27,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.academiaNome,
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.82),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment:
                narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _heroChip(Icons.group_rounded, '$total turmas'),
                  _heroChip(Icons.filter_alt_rounded, '$exibidas exibidas'),
                  _heroChip(Icons.person_add_alt_1_rounded, 'Alunos'),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [
                iconBox,
                const SizedBox(height: 14),
                text,
              ],
            );
          }

          return Row(
            children: [
              iconBox,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _heroChip(IconData icon, String label) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onPrimary, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: onPrimary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    final t = context.uai;

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: t.border),
          boxShadow: t.softShadow,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFiltroStatus(),
              _buildFiltroFaixaEtaria(),
              if (_filterStatus != 'Todas' || _filterFaixaEtaria != 'Todas')
                ActionChip(
                  onPressed: () {
                    setState(() {
                      _filterStatus = 'Todas';
                      _filterFaixaEtaria = 'Todas';
                    });
                  },
                  backgroundColor: t.cardAlt,
                  side: BorderSide(color: t.border),
                  avatar: Icon(
                    Icons.cleaning_services_rounded,
                    color: t.textSecondary,
                    size: 17,
                  ),
                  label: Text(
                    'Limpar filtros',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTurmasList(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> turmas,
      ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;

        if (!wide) {
          return Column(
            children: turmas.map((turma) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildTurmaCard(turma, compact: true),
              );
            }).toList(),
          );
        }

        const spacing = 12.0;
        final itemWidth = (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: turmas.map((turma) {
            return SizedBox(
              width: itemWidth,
              child: _buildTurmaCard(turma, compact: false),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildTurmaCard(
      QueryDocumentSnapshot<Map<String, dynamic>> turma, {
        required bool compact,
      }) {
    final t = context.uai;
    final data = turma.data();

    final nome = _text(data['nome'], 'Sem nome');
    final nivel = _text(data['nivel'], 'Sem nível');
    final faixaEtaria = _text(data['faixa_etaria'], 'Sem faixa');
    final professor = _text(
      data['professor_principal'] ?? data['professor'],
      'Sem professor',
    );
    final status = _text(data['status'], 'INATIVA');
    final horarioDisplay = _text(data['horario_display'], 'Sem horário');
    final diasSemana = data['dias_semana'] as List<dynamic>? ?? [];
    final alunosCount = _toInt(data['alunos_count']);
    final capacidade = _toInt(data['capacidade_maxima']);
    final ocupacao = capacidade > 0 ? ((alunosCount / capacidade) * 100).toInt() : 0;
    final corTurma = _parseColor(data['cor_turma'], fallback: t.primary);
    final logoUrl = data['logo_url']?.toString();

    final turmaColor = _ensureVisible(corTurma, t.card);
    final statusAccent = _ensureVisible(_statusColor(status), t.cardAlt);
    final ocupacaoAccent = _ensureVisible(_ocupacaoColor(ocupacao), t.cardAlt);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirTurma(turmaId: turma.id),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: turmaColor.withOpacity(0.14)),
            boxShadow: t.softShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTurmaAvatar(
                logoUrl: logoUrl,
                faixaEtaria: faixaEtaria,
                color: turmaColor,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCardTitleRow(
                      nome: nome,
                      status: status,
                      statusAccent: statusAccent,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoLine(
                      icon: Icons.schedule_rounded,
                      text:
                      '$horarioDisplay • ${_diasSemanaAbreviados(diasSemana)}',
                    ),
                    const SizedBox(height: 6),
                    _buildInfoLine(
                      icon: Icons.category_rounded,
                      text: '$nivel • $faixaEtaria',
                    ),
                    const SizedBox(height: 6),
                    _buildInfoLine(
                      icon: Icons.person_outline_rounded,
                      text: professor,
                    ),
                    const SizedBox(height: 12),
                    _buildOcupacaoBar(
                      alunosCount: alunosCount,
                      capacidade: capacidade,
                      ocupacao: ocupacao,
                      color: ocupacaoAccent,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              _buildPopupMenu(
                turmaId: turma.id,
                turmaNome: nome,
                alunosCount: alunosCount,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTurmaAvatar({
    required String? logoUrl,
    required String faixaEtaria,
    required Color color,
  }) {
    final t = context.uai;

    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: t.border, width: 1.2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t.inputRadius - 1),
        child: logoUrl != null && logoUrl.isNotEmpty
            ? Image.network(
          logoUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildTurmaAvatarFallback(
              faixaEtaria: faixaEtaria,
              color: color,
            );
          },
        )
            : _buildTurmaAvatarFallback(
          faixaEtaria: faixaEtaria,
          color: color,
        ),
      ),
    );
  }

  Widget _buildTurmaAvatarFallback({
    required String faixaEtaria,
    required Color color,
  }) {
    final t = context.uai;

    return Container(
      color: Color.alphaBlend(color.withOpacity(0.10), t.cardAlt),
      child: Center(
        child: Text(
          _faixaEtariaIcon(faixaEtaria),
          style: const TextStyle(fontSize: 28),
        ),
      ),
    );
  }

  Widget _buildCardTitleRow({
    required String nome,
    required String status,
    required Color statusAccent,
  }) {
    final t = context.uai;

    return Row(
      children: [
        Expanded(
          child: Text(
            nome,
            style: TextStyle(
              color: status == 'ATIVA' ? t.textPrimary : t.textMuted,
              fontWeight: FontWeight.w900,
              fontSize: 15.5,
              height: 1.15,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: Color.alphaBlend(statusAccent.withOpacity(0.10), t.cardAlt),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: statusAccent.withOpacity(0.18)),
          ),
          child: Text(
            status,
            style: TextStyle(
              color: statusAccent,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoLine({
    required IconData icon,
    required String text,
  }) {
    final t = context.uai;

    return Row(
      children: [
        Icon(icon, size: 16, color: t.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12.5,
              height: 1.2,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildOcupacaoBar({
    required int alunosCount,
    required int capacidade,
    required int ocupacao,
    required Color color,
  }) {
    final t = context.uai;
    final value = capacidade > 0 ? (alunosCount / capacidade).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: value,
                  backgroundColor: t.border,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 10,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$alunosCount/$capacidade',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: t.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          '($ocupacao% ocupado)',
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildPopupMenu({
    required String turmaId,
    required String turmaNome,
    required int alunosCount,
  }) {
    final t = context.uai;

    return PopupMenuButton<String>(
      color: t.surface,
      icon: Icon(Icons.more_vert_rounded, color: t.textSecondary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.cardRadius),
      ),
      onSelected: (value) {
        if (value == 'editar') {
          _abrirTurma(turmaId: turmaId);
        } else if (value == 'alunos') {
          _abrirAlunosTurma(
            turmaId: turmaId,
            turmaNome: turmaNome,
          );
        } else if (value == 'excluir') {
          _showDeleteConfirmation(turmaId, turmaNome);
        }
      },
      itemBuilder: (context) => [
        _popupItem(
          value: 'editar',
          icon: Icons.edit_rounded,
          label: 'Editar Turma',
          color: t.info,
        ),
        PopupMenuItem<String>(
          value: 'alunos',
          child: Row(
            children: [
              Icon(
                Icons.group_add_rounded,
                color: _ensureVisible(t.success, t.surface),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Gerenciar Alunos',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (alunosCount > 0)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      t.success.withOpacity(0.10),
                      t.cardAlt,
                    ),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    alunosCount.toString(),
                    style: TextStyle(
                      color: _ensureVisible(t.success, t.cardAlt),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
        ),
        _popupItem(
          value: 'excluir',
          icon: Icons.delete_rounded,
          label: 'Excluir Turma',
          color: t.error,
        ),
      ],
    );
  }

  PopupMenuItem<String> _popupItem({
    required String value,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateCard({
    required IconData icon,
    required String title,
    required String text,
    required Color color,
    bool compact = false,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 0 : 22),
        child: Material(
          color: t.card,
          borderRadius: BorderRadius.circular(t.cardRadius),
          clipBehavior: Clip.antiAlias,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: EdgeInsets.all(compact ? 18 : 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius),
              border: Border.all(color: accent.withOpacity(0.16)),
              boxShadow: compact ? null : t.softShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: compact ? 46 : 70, color: accent),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: compact ? 16 : 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
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

  Widget _buildEmptyState() {
    final t = context.uai;

    return _buildStateCard(
      icon: Icons.group_outlined,
      title: 'Nenhuma turma cadastrada',
      text: 'Toque no botão + para adicionar a primeira turma desta academia.',
      color: t.primary,
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
