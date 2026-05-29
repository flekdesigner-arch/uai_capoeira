import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'editar_academia_screen.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/turmas/admin/gerenciar_turmas_screen.dart';
import 'package:uai_capoeira/modules/usuarios/admin/usuario_detalhe_screen.dart';

class GerenciarAcademiasScreen extends StatefulWidget {
  const GerenciarAcademiasScreen({super.key});

  @override
  State<GerenciarAcademiasScreen> createState() =>
      _GerenciarAcademiasScreenState();
}

class _GerenciarAcademiasScreenState extends State<GerenciarAcademiasScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _filterCidade = 'Todas';
  String _filterModalidade = 'Todas';
  List<String> _cidades = ['Todas'];
  List<String> _modalidades = ['Todas'];

  bool _calculandoContadores = false;

  @override
  void initState() {
    super.initState();
    _carregarFiltros();
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

  String _textFrom(Map<String, dynamic> data, String key, String fallback) {
    final value = data[key]?.toString().trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  int _intFrom(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _carregarFiltros() async {
    try {
      final snapshot =
      await _firestore.collection('academias').orderBy('nome').get();

      final cidadesUnicas = <String>{'Todas'};
      final modalidadesUnicas = <String>{'Todas'};

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final cidade = data['cidade']?.toString().trim();
        final modalidade = data['modalidade']?.toString().trim();

        if (cidade != null && cidade.isNotEmpty) {
          cidadesUnicas.add(cidade);
        }

        if (modalidade != null && modalidade.isNotEmpty) {
          modalidadesUnicas.add(modalidade);
        }
      }

      if (!mounted) return;

      setState(() {
        _cidades = cidadesUnicas.toList()..sort();
        _modalidades = modalidadesUnicas.toList()..sort();
      });
    } catch (e) {
      debugPrint('Erro ao carregar filtros: $e');
    }
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
                              border:
                              Border.all(color: primary.withOpacity(0.16)),
                            ),
                            child: Icon(icon, color: primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              titulo,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
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

  Widget _buildFiltroCidade() {
    return _buildFilterChip(
      icon: Icons.location_city_rounded,
      label: _filterCidade,
      selected: _filterCidade != 'Todas',
      onSelected: (selected) {
        if (!selected) {
          setState(() => _filterCidade = 'Todas');
          return;
        }

        _abrirSelecaoFiltro(
          titulo: 'Filtrar por cidade',
          icon: Icons.location_city_rounded,
          opcoes: _cidades,
          valorAtual: _filterCidade,
          onSelected: (value) => setState(() => _filterCidade = value),
        );
      },
    );
  }

  Widget _buildFiltroModalidade() {
    return _buildFilterChip(
      icon: Icons.sports_martial_arts_rounded,
      label: _filterModalidade,
      selected: _filterModalidade != 'Todas',
      onSelected: (selected) {
        if (!selected) {
          setState(() => _filterModalidade = 'Todas');
          return;
        }

        _abrirSelecaoFiltro(
          titulo: 'Filtrar por modalidade',
          icon: Icons.sports_martial_arts_rounded,
          opcoes: _modalidades,
          valorAtual: _filterModalidade,
          onSelected: (value) => setState(() => _filterModalidade = value),
        );
      },
    );
  }

  Widget _buildFilterChip({
    required IconData icon,
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);
    final foreground = selected ? _readableOn(primary) : t.textPrimary;

    return FilterChip(
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      backgroundColor: t.cardAlt,
      selectedColor: primary,
      side: BorderSide(color: selected ? primary : t.border),
      avatar: Icon(
        icon,
        size: 18,
        color: foreground,
      ),
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

  Future<void> _showLoadingDialog(String message, {String? subtitle}) async {
    final t = context.uai;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(22),
          backgroundColor: Colors.transparent,
          child: Material(
            color: t.surface,
            borderRadius: BorderRadius.circular(t.cardRadius),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: t.primary),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showResultDialog({
    required bool success,
    required String title,
    required String message,
  }) async {
    final t = context.uai;
    final color = success ? t.success : t.error;
    final accent = _ensureVisible(color, t.surface);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
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
                          child: Icon(
                            success
                                ? Icons.check_circle_rounded
                                : Icons.error_rounded,
                            color: accent,
                          ),
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
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: success ? t.primary : t.error,
                          foregroundColor:
                          _readableOn(success ? t.primary : t.error),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(t.buttonRadius),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: const Text(
                          'OK',
                          style: TextStyle(fontWeight: FontWeight.w900),
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
  }

  Future<void> _calcularAtualizarContadores() async {
    if (!mounted) return;

    setState(() => _calculandoContadores = true);

    await _showLoadingDialog(
      'Calculando contadores...',
      subtitle: 'Aguarde enquanto atualizamos os contadores de alunos.',
    );

    try {
      final academiasSnapshot = await _firestore.collection('academias').get();

      int academiasProcessadas = 0;

      for (final academiaDoc in academiasSnapshot.docs) {
        final academiaId = academiaDoc.id;
        final academiaRef = academiaDoc.reference;

        final turmasSnapshot = await _firestore
            .collection('turmas')
            .where('academia_id', isEqualTo: academiaId)
            .get();

        int totalAlunosAcademia = 0;
        int totalTurmasAtivas = 0;

        for (final turmaDoc in turmasSnapshot.docs) {
          final turmaId = turmaDoc.id;
          final turmaRef = turmaDoc.reference;
          final turmaData = turmaDoc.data();

          final alunosAtivosSnapshot = await _firestore
              .collection('alunos')
              .where('turma_id', isEqualTo: turmaId)
              .where('status_atividade', isEqualTo: 'ATIVO(A)')
              .get();

          final alunosInativosSnapshot = await _firestore
              .collection('alunos')
              .where('turma_id', isEqualTo: turmaId)
              .where('status_atividade', isEqualTo: 'INATIVO(A)')
              .get();

          final alunosAtivosCount = alunosAtivosSnapshot.docs.length;
          final alunosInativosCount = alunosInativosSnapshot.docs.length;
          final totalAlunosTurma = alunosAtivosCount + alunosInativosCount;

          totalAlunosAcademia += alunosAtivosCount;

          final statusTurma = turmaData['status']?.toString();
          if (statusTurma == 'ATIVA') {
            totalTurmasAtivas++;
          }

          await turmaRef.update({
            'alunos_ativos': alunosAtivosCount,
            'alunos_inativos': alunosInativosCount,
            'alunos_count': totalAlunosTurma,
            'atualizado_em': FieldValue.serverTimestamp(),
            'ultima_atualizacao': FieldValue.serverTimestamp(),
          });
        }

        await academiaRef.update({
          'turmas_count': turmasSnapshot.docs.length,
          'turmas_ativas_count': totalTurmasAtivas,
          'alunos_count': totalAlunosAcademia,
          'ultima_atualizacao': FieldValue.serverTimestamp(),
          'atualizado_em': FieldValue.serverTimestamp(),
        });

        academiasProcessadas++;
      }

      if (mounted) Navigator.pop(context);

      if (mounted) {
        await _showResultDialog(
          success: true,
          title: 'Sucesso!',
          message:
          'Contadores atualizados com sucesso!\nProcessadas $academiasProcessadas academias.',
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);

      if (mounted) {
        await _showResultDialog(
          success: false,
          title: 'Erro',
          message: 'Erro ao calcular contadores: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _calculandoContadores = false);
    }
  }

  Future<void> _calcularContadoresAcademia(
      String academiaId,
      String academiaNome,
      ) async {
    await _showLoadingDialog('Calculando $academiaNome...');

    try {
      final academiaRef = _firestore.collection('academias').doc(academiaId);

      final turmasSnapshot = await _firestore
          .collection('turmas')
          .where('academia_id', isEqualTo: academiaId)
          .get();

      int totalAlunosAcademia = 0;
      int totalTurmasAtivas = 0;

      for (final turmaDoc in turmasSnapshot.docs) {
        final turmaId = turmaDoc.id;
        final turmaRef = turmaDoc.reference;
        final turmaData = turmaDoc.data();

        final alunosAtivosSnapshot = await _firestore
            .collection('alunos')
            .where('turma_id', isEqualTo: turmaId)
            .where('status_atividade', isEqualTo: 'ATIVO(A)')
            .get();

        final alunosInativosSnapshot = await _firestore
            .collection('alunos')
            .where('turma_id', isEqualTo: turmaId)
            .where('status_atividade', isEqualTo: 'INATIVO(A)')
            .get();

        final alunosAtivosCount = alunosAtivosSnapshot.docs.length;
        final alunosInativosCount = alunosInativosSnapshot.docs.length;
        final totalAlunosTurma = alunosAtivosCount + alunosInativosCount;

        totalAlunosAcademia += alunosAtivosCount;

        final statusTurma = turmaData['status']?.toString();
        if (statusTurma == 'ATIVA') {
          totalTurmasAtivas++;
        }

        await turmaRef.update({
          'alunos_ativos': alunosAtivosCount,
          'alunos_inativos': alunosInativosCount,
          'alunos_count': totalAlunosTurma,
          'atualizado_em': FieldValue.serverTimestamp(),
          'ultima_atualizacao': FieldValue.serverTimestamp(),
        });
      }

      await academiaRef.update({
        'turmas_count': turmasSnapshot.docs.length,
        'turmas_ativas_count': totalTurmasAtivas,
        'alunos_count': totalAlunosAcademia,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
        'atualizado_em': FieldValue.serverTimestamp(),
      });

      if (mounted) Navigator.pop(context);

      if (mounted) {
        await _showResultDialog(
          success: true,
          title: 'Contadores atualizados!',
          message: 'Academia "$academiaNome" atualizada.\n'
              'Total de alunos: $totalAlunosAcademia\n'
              'Total de turmas: ${turmasSnapshot.docs.length}\n'
              'Turmas ativas: $totalTurmasAtivas',
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);

      if (mounted) {
        await _showResultDialog(
          success: false,
          title: 'Erro',
          message: 'Erro ao calcular "$academiaNome": $e',
        );
      }
    }
  }

  Future<void> _abrirAcademia({String? academiaId}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditarAcademiaScreen(academiaId: academiaId),
      ),
    );

    if (mounted) _carregarFiltros();
  }

  Future<void> _abrirTurmas({
    required String academiaId,
    required String academiaNome,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GerenciarTurmasScreen(
          academiaId: academiaId,
          academiaNome: academiaNome,
        ),
      ),
    );
  }

  Future<void> _abrirResponsavel(String? responsavelId) async {
    if (responsavelId == null || responsavelId.trim().isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UsuarioDetalheScreen(userId: responsavelId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: t.background,
        appBar: AppBar(
          title: const Text(
            'Gerenciar Academias',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          actions: [
            IconButton(
              onPressed:
              _calculandoContadores ? null : _calcularAtualizarContadores,
              icon: _calculandoContadores
                  ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _readableOn(t.primary),
                ),
              )
                  : const Icon(Icons.calculate_rounded),
              tooltip: 'Calcular contadores de alunos',
            ),
          ],
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _firestore.collection('academias').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingState();
            }

            if (snapshot.hasError) {
              return _buildStateCard(
                icon: Icons.error_outline_rounded,
                title: 'Erro ao carregar academias',
                text: snapshot.error.toString(),
                color: t.error,
              );
            }

            final docs = snapshot.data?.docs ?? [];

            if (docs.isEmpty) {
              return _buildEmptyState();
            }

            var academias = docs.toList();

            if (_filterCidade != 'Todas') {
              academias = academias.where((doc) {
                return doc.data()['cidade']?.toString() == _filterCidade;
              }).toList();
            }

            if (_filterModalidade != 'Todas') {
              academias = academias.where((doc) {
                return doc.data()['modalidade']?.toString() ==
                    _filterModalidade;
              }).toList();
            }

            academias.sort((a, b) {
              final nomeA = a.data()['nome']?.toString().toLowerCase() ?? '';
              final nomeB = b.data()['nome']?.toString().toLowerCase() ?? '';
              return nomeA.compareTo(nomeB);
            });

            return RefreshIndicator(
              color: t.primary,
              backgroundColor: t.surface,
              onRefresh: () async {
                await _carregarFiltros();
                if (mounted) setState(() {});
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeroCard(
                            total: docs.length,
                            filtradas: academias.length,
                          ),
                          const SizedBox(height: 14),
                          _buildSearchAndFilters(),
                          const SizedBox(height: 14),
                          if (academias.isEmpty)
                            _buildStateCard(
                              icon: Icons.search_off_rounded,
                              title: 'Nenhuma academia encontrada',
                              text:
                              'Tente limpar os filtros ou buscar por outro termo.',
                              color: t.warning,
                              compact: true,
                            )
                          else
                            _buildAcademiasGrid(academias),
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
          onPressed: () => _abrirAcademia(),
          backgroundColor: t.primary,
          foregroundColor: _readableOn(t.primary),
          child: const Icon(Icons.add_rounded),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    final t = context.uai;

    return Center(
      child: CircularProgressIndicator(color: t.primary),
    );
  }

  Widget _buildHeroCard({
    required int total,
    required int filtradas,
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
              Icons.business_rounded,
              color: onPrimary,
              size: 34,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Academias e Núcleos',
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
                'Gerencie núcleos, responsáveis, professores, turmas e contadores.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
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
                  _heroChip(Icons.business_rounded, '$total academias'),
                  _heroChip(Icons.filter_alt_rounded, '$filtradas exibidas'),
                  _heroChip(Icons.calculate_rounded, 'Contadores'),
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
              _buildFiltroCidade(),
              _buildFiltroModalidade(),
              if (_filterCidade != 'Todas' || _filterModalidade != 'Todas')
                ActionChip(
                  onPressed: () {
                    setState(() {
                      _filterCidade = 'Todas';
                      _filterModalidade = 'Todas';
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

  Widget _buildAcademiasGrid(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> academias,
      ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final crossAxisCount = width >= 980
            ? 3
            : width >= 680
            ? 2
            : 1;

        const spacing = 12.0;
        final itemWidth =
            (width - (spacing * (crossAxisCount - 1))) / crossAxisCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: academias.map((academia) {
            return SizedBox(
              width: itemWidth,
              child: _buildAcademiaCard(academia),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildAcademiaCard(
      QueryDocumentSnapshot<Map<String, dynamic>> academia,
      ) {
    final t = context.uai;
    final data = academia.data();

    final nome = _textFrom(data, 'nome', 'Sem nome');
    final cidade = _textFrom(data, 'cidade', 'Sem cidade');
    final modalidade = _textFrom(data, 'modalidade', 'Sem modalidade');
    final responsavelNome = _textFrom(data, 'responsavel', 'Sem responsável');
    final responsavelId = data['responsavel_id']?.toString();
    final status = _textFrom(data, 'status', 'ativa').toLowerCase();
    final turmasCount = _intFrom(data['turmas_count']);
    final alunosCount = _intFrom(data['alunos_count']);
    final turmasAtivasCount = _intFrom(data['turmas_ativas_count']);
    final ultimaAtualizacao = data['ultima_atualizacao'];

    final isActive = status == 'ativa';
    final primary = _ensureVisible(isActive ? t.primary : t.textMuted, t.card);
    final info = _ensureVisible(t.info, t.card);
    final success = _ensureVisible(t.success, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirAcademia(academiaId: academia.id),
        child: Container(
          constraints: const BoxConstraints(minHeight: 246),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(
              color: isActive
                  ? primary.withOpacity(0.16)
                  : t.border,
            ),
            boxShadow: t.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.11),
                      borderRadius: BorderRadius.circular(t.buttonRadius),
                      border: Border.all(color: primary.withOpacity(0.16)),
                    ),
                    child: Icon(
                      Icons.business_rounded,
                      size: 28,
                      color: primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nome,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              height: 1.12,
                              color: isActive ? t.textPrimary : t.textMuted,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 14,
                                color: t.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '$cidade • $modalidade',
                                  style: TextStyle(
                                    color: t.textSecondary,
                                    fontSize: 12.2,
                                    height: 1.25,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildPopupMenu(
                    academiaId: academia.id,
                    academiaNome: nome,
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildInfoChip(
                    icon: Icons.group_rounded,
                    label: '$turmasCount turma${turmasCount != 1 ? 's' : ''}',
                    color: info,
                  ),
                  if (turmasAtivasCount > 0)
                    _buildInfoChip(
                      icon: Icons.check_circle_rounded,
                      label:
                      '$turmasAtivasCount ativa${turmasAtivasCount != 1 ? 's' : ''}',
                      color: success,
                    ),
                  _buildInfoChip(
                    icon: Icons.person_rounded,
                    label: '$alunosCount aluno${alunosCount != 1 ? 's' : ''}',
                    color: primary,
                  ),
                  _buildStatusChip(status),
                ],
              ),
              if (responsavelNome.isNotEmpty) ...[
                const SizedBox(height: 12),
                Material(
                  color: t.cardAlt,
                  borderRadius: BorderRadius.circular(t.inputRadius),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: responsavelId != null
                        ? () => _abrirResponsavel(responsavelId)
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(t.inputRadius),
                        border: Border.all(color: t.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_outline_rounded,
                            size: 16,
                            color: responsavelId != null
                                ? info
                                : t.textSecondary,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'Resp: $responsavelNome',
                              style: TextStyle(
                                color:
                                responsavelId != null ? info : t.textSecondary,
                                fontWeight: responsavelId != null
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (responsavelId != null) ...[
                            const SizedBox(width: 5),
                            Icon(
                              Icons.open_in_new_rounded,
                              size: 13,
                              color: info,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (ultimaAtualizacao is Timestamp) ...[
                const SizedBox(height: 9),
                Row(
                  children: [
                    Icon(
                      Icons.update_rounded,
                      size: 13,
                      color: t.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Atualizado: ${_formatarData(ultimaAtualizacao)}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: t.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPopupMenu({
    required String academiaId,
    required String academiaNome,
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
          _abrirAcademia(academiaId: academiaId);
        } else if (value == 'turmas') {
          _abrirTurmas(
            academiaId: academiaId,
            academiaNome: academiaNome,
          );
        } else if (value == 'calcular') {
          _calcularContadoresAcademia(academiaId, academiaNome);
        }
      },
      itemBuilder: (context) => [
        _popupItem(
          value: 'editar',
          icon: Icons.edit_rounded,
          label: 'Editar Academia',
          color: t.info,
        ),
        _popupItem(
          value: 'turmas',
          icon: Icons.group_rounded,
          label: 'Gerenciar Turmas',
          color: t.success,
        ),
        _popupItem(
          value: 'calcular',
          icon: Icons.calculate_rounded,
          label: 'Recalcular Contadores',
          color: t.warning,
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

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final t = context.uai;
    final isActive = status == 'ativa';
    final color = _ensureVisible(isActive ? t.success : t.textMuted, t.cardAlt);

    return _buildInfoChip(
      icon: isActive ? Icons.check_circle_rounded : Icons.block_rounded,
      label: status.toUpperCase(),
      color: color,
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
      icon: Icons.business_outlined,
      title: 'Nenhuma academia cadastrada',
      text: 'Toque no botão + para adicionar a primeira academia ou núcleo.',
      color: t.primary,
    );
  }

  String _formatarData(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'agora há pouco';
        }

        return 'há ${difference.inMinutes} min';
      }

      return 'há ${difference.inHours} h';
    }

    if (difference.inDays == 1) {
      return 'ontem';
    }

    if (difference.inDays < 7) {
      return 'há ${difference.inDays} dias';
    }

    return '${date.day}/${date.month}/${date.year}';
  }
}
