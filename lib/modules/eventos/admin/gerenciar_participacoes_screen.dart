import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uai_capoeira/core/permissions/permission_access_guard.dart';
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/eventos/services/evento_participantes_cache_service.dart';
import 'package:uai_capoeira/modules/eventos/services/participacao_service.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';
import 'package:uai_capoeira/modules/eventos/widgets/adicionar_participante_modal.dart';
import 'package:uai_capoeira/modules/graduacoes/services/graduacao_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uai_capoeira/shared/services/svg_service.dart';

class GerenciarParticipacoesScreen extends StatefulWidget {
  final String? eventoId;
  final String? eventoNome;
  final EventoModel? evento;

  const GerenciarParticipacoesScreen({
    super.key,
    this.eventoId,
    this.eventoNome,
    this.evento,
  });

  @override
  State<GerenciarParticipacoesScreen> createState() =>
      _GerenciarParticipacoesScreenState();
}

class _GerenciarParticipacoesScreenState
    extends State<GerenciarParticipacoesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final PermissaoService _permissaoService = PermissaoService();
  final EventoParticipantesCacheService _cacheService =
      EventoParticipantesCacheService();
  final ParticipacaoService _participacaoService = ParticipacaoService();
  final GraduacaoService _graduacaoService = GraduacaoService();
  late final PermissionAccessGuard _accessGuard = PermissionAccessGuard(
    service: _permissaoService,
  );

  String _searchQuery = '';
  String? _filtroEvento;
  List<String> _eventosList = ['Todos'];
  bool _checkingAccess = true;
  bool _accessDenied = false;
  bool _podeAdicionar = false;
  bool _podeEditar = false;
  final Map<String, String?> _fotoAlunoCache = {};
  final Map<String, ValueNotifier<String?>> _fotoAlunoNotifiers = {};
  final Map<String, _FotoRecoveryJob> _fotoRecoveryQueue = <String, _FotoRecoveryJob>{};
  final Set<String> _fotoRecoveryInFlight = <String>{};
  int _fotoRecoveryRunning = 0;
  static const int _fotoRecoveryMaxConcurrent = 3;
  Set<String> _idsAlunosParticipantesEvento = <String>{};
  Set<String> _nomesAlunosParticipantesEvento = <String>{};
  final Map<String, Map<String, dynamic>?> _graduacaoParticipacaoCache = {};
  List<Map<String, dynamic>>? _graduacoesCache;

  bool get _modoEvento => widget.eventoId != null && widget.eventoId!.isNotEmpty;

  bool get _eventoExibeGraduacao {
    if (!_modoEvento) return true;
    final evento = widget.evento;
    final tipo = (evento?.tipo ?? '').toUpperCase();
    final nome = (evento?.nome ?? widget.eventoNome ?? '').toUpperCase();
    return tipo.contains('BATIZADO') ||
        tipo.contains('TROCA DE CORDAS') ||
        nome.contains('BATIZADO') ||
        nome.contains('TROCA DE CORDAS');
  }

  bool get _temFiltroAtivo =>
      _searchQuery.trim().isNotEmpty || (!_modoEvento && _filtroEvento != null);

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });

    if (_modoEvento) {
      _filtroEvento = widget.eventoNome;
    }
    _verificarAcesso();
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final notifier in _fotoAlunoNotifiers.values) {
      notifier.dispose();
    }
    _fotoAlunoNotifiers.clear();
    _fotoRecoveryQueue.clear();
    super.dispose();
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Future<void> _verificarAcesso() async {
    if (mounted) {
      setState(() {
        _checkingAccess = true;
        _accessDenied = false;
      });
    }

    final results = await Future.wait<bool>([
      _accessGuard.canAny([
        'pode_gerenciar_participantes_evento',
        'pode_ver_participantes_evento',
        'pode_adicionar_participante_evento',
        'pode_editar_participante_evento',
        'pode_editar_dados_participacao_evento',
        'pode_ver_detalhe_participacao_evento',
        'pode_remover_participante_evento',
      ]),
      _accessGuard.canAnyDirect([
        'pode_adicionar_participante_evento',
        'pode_adcionar_aluno_a_eventos',
        'pode_adicionar_aluno_a_eventos',
      ]),
      _accessGuard.canAnyDirect([
        'pode_editar_dados_participacao_evento',
        'pode_editar_participante_evento',
        'pode_editar_participacao_evento',
      ]),
    ]);

    if (!mounted) return;

    setState(() {
      _accessDenied = !results[0];
      _podeAdicionar = results[1];
      _podeEditar = results[2];
      _checkingAccess = false;
    });

    if (results[0]) {
      await _carregarEventos();
    }
  }

  Future<void> _carregarEventos() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('eventos')
          .orderBy('nome')
          .get();

      final eventos = <String>{'Todos'};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final nome = data['nome']?.toString().trim() ?? '';
        if (nome.isNotEmpty) eventos.add(nome);
      }

      if (mounted) {
        setState(() {
          _eventosList = eventos.toList()..sort();
          _eventosList.remove('Todos');
          _eventosList.insert(0, 'Todos');
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar eventos: $e');
    }
  }

  String? _pickFirstClean(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') continue;
      return text;
    }
    return null;
  }

  void _showSnack(String message, {required _SnackType type}) {
    final t = context.uai;

    final color = switch (type) {
      _SnackType.success => t.success,
      _SnackType.error => t.error,
      _SnackType.warning => t.warning,
      _SnackType.info => t.info,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _excluirParticipacao(
    String participacaoId,
    String alunoNome,
    String eventoNome,
  ) async {
    final permitido = await _accessGuard.revalidateAnyDirect(
      context,
      permissions: const [
        'pode_remover_participante_evento',
        'pode_remover_alunos_de_eventos',
      ],
      message: 'Você não tem permissão para remover participantes.',
    );
    if (!permitido) return;

    if (!mounted) return;
    final t = context.uai;
    final error = _ensureVisible(t.error, t.surface);

    final confirm = await showDialog<bool>(
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
                            color: error.withAlpha(31),
                            borderRadius: BorderRadius.circular(t.buttonRadius),
                          ),
                          child: Icon(Icons.warning_rounded, color: error),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Excluir participação?',
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Remover a participação de "$alunoNome" no evento "$eventoNome"?\n\nEssa ação não poderá ser desfeita.',
                      style: TextStyle(color: t.textSecondary, height: 1.35),
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 380;

                        final cancel = OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: t.textPrimary,
                            side: BorderSide(color: t.border),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                t.buttonRadius,
                              ),
                            ),
                          ),
                          child: const Text(
                            'CANCELAR',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        );

                        final remove = ElevatedButton.icon(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          icon: const Icon(Icons.delete_rounded, size: 18),
                          label: const Text('EXCLUIR'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: t.error,
                            foregroundColor: _readableOn(t.error),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                t.buttonRadius,
                              ),
                            ),
                          ),
                        );

                        if (narrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              cancel,
                              const SizedBox(height: 10),
                              remove,
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: cancel),
                            const SizedBox(width: 10),
                            Expanded(child: remove),
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

    if (confirm != true) return;

    try {
      final participacaoRef = FirebaseFirestore.instance
          .collection('participacoes_eventos')
          .doc(participacaoId);
      final participacaoDoc = await participacaoRef.get();
      final participacaoData = participacaoDoc.data() ?? {};
      final eventoId = _pickFirstClean(participacaoData, const [
        'evento_id',
        'eventoId',
        'id_evento',
        'evento_doc_id',
        'eventoDocId',
        'idEvento',
      ]);

      await participacaoRef.delete();

      if (eventoId != null) {
        await _cacheService.removerCacheDaParticipacao(
          eventoId,
          participacaoId,
        );
      }

      if (!mounted) return;

      _showSnack(
        '✅ Participação excluída com sucesso!',
        type: _SnackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Erro ao excluir: $e', type: _SnackType.error);
    }
  }

  Future<void> _editarParticipacao(
    Map<String, dynamic> participacao,
    String id,
  ) {
    if (!_podeEditar) {
      _showSnack(
        'Você não tem permissão para editar participantes.',
        type: _SnackType.error,
      );
      return Future.value();
    }

    return _abrirFormulario(
      participacao: participacao,
      participacaoId: id,
      mensagemSucesso: '✅ Participação atualizada!',
    );
  }

  bool _eventoEhBatizado(EventoModel evento) {
    // REGRA DE NEGÓCIO: graduação depende EXCLUSIVAMENTE do tipo do evento.
    // O nome/título nunca deve habilitar graduação, pois eventos como
    // "EVENTO EM OUTRA CIDADE" podem conter "Batizado" no nome sem serem
    // eventos de graduação.
    final tipo = _normalizarOrdenacao(evento.tipo);
    return tipo.contains('BATIZADO') || tipo.contains('TROCA DE CORDAS');
  }

  String _normalizarOrdenacao(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[ÁÀÂÃÄ]'), 'A')
        .replaceAll(RegExp(r'[ÉÈÊË]'), 'E')
        .replaceAll(RegExp(r'[ÍÌÎÏ]'), 'I')
        .replaceAll(RegExp(r'[ÓÒÔÕÖ]'), 'O')
        .replaceAll(RegExp(r'[ÚÙÛÜ]'), 'U')
        .replaceAll('Ç', 'C');
  }


  String _graduacaoEventoNome(Map<String, dynamic> participacao) {
    return _pickFirstClean(participacao, const [
          'graduacao_final',
          'graduacao_nova',
          'graduacao',
        ]) ??
        'Graduação não informada';
  }

  Future<Map<String, dynamic>?> _resolverGraduacaoParticipacao(
    Map<String, dynamic> participacao,
  ) async {
    final id = _pickFirstClean(participacao, const [
      'graduacao_final_id',
      'graduacao_nova_id',
      'graduacao_id',
    ]);
    final nome = _graduacaoEventoNome(participacao);
    final cacheKey = (id != null && id.isNotEmpty)
        ? 'id:$id'
        : 'nome:${_normalizarOrdenacao(nome)}';
    if (_graduacaoParticipacaoCache.containsKey(cacheKey)) {
      return _graduacaoParticipacaoCache[cacheKey];
    }

    Map<String, dynamic>? grad;
    try {
      if (id != null && id.isNotEmpty) {
        grad = await _graduacaoService.buscarPorId(id);
      }
      if (grad == null) {
        _graduacoesCache ??= await _graduacaoService.buscarTodasGraduacoes();
        final alvo = _normalizarOrdenacao(nome);
        for (final item in _graduacoesCache!) {
          final itemNome = _normalizarOrdenacao(
            (item['nome_graduacao'] ?? item['nome'] ?? '').toString(),
          );
          if (itemNome == alvo) {
            grad = item;
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao resolver graduação da participação: $e');
    }
    _graduacaoParticipacaoCache[cacheKey] = grad;
    return grad;
  }

  Widget _buildCordaParticipacao(
    Map<String, dynamic> participacao, {
    double width = 60,
    double height = 58,
  }) {
    final temCoresNoDoc = [
      participacao['graduacao_hex_cor1'],
      participacao['hex_cor1'],
    ].any((v) => v != null && v.toString().trim().isNotEmpty);
    if (temCoresNoDoc) {
      return _buildCordaSvg(participacao, width: width, height: height);
    }
    return FutureBuilder<Map<String, dynamic>?>(
      future: _resolverGraduacaoParticipacao(participacao),
      builder: (_, snapshot) {
        final grad = snapshot.data;
        if (grad == null) {
          return SizedBox(
            width: width,
            height: height,
            child: Icon(
              Icons.military_tech_rounded,
              color: context.uai.textMuted,
            ),
          );
        }
        return _buildCordaSvg(grad, width: width, height: height);
      },
    );
  }

  Future<List<Map<String, dynamic>>> _carregarAlunosAtivosHistorico() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('alunos')
        .where('status_atividade', whereIn: const ['ATIVO(A)', 'ATIVO'])
        .get();
    final alunos = snapshot.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .where((aluno) {
          final id = (aluno['id'] ?? '').toString();
          final nome = _normalizarOrdenacao((aluno['nome'] ?? '').toString());
          return !_idsAlunosParticipantesEvento.contains(id) &&
              !_nomesAlunosParticipantesEvento.contains(nome);
        })
        .toList();
    alunos.sort((a, b) => _normalizarOrdenacao((a['nome'] ?? '').toString())
        .compareTo(_normalizarOrdenacao((b['nome'] ?? '').toString())));
    return alunos;
  }

  Future<List<Map<String, dynamic>>> _carregarAlunosInativosHistorico() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('alunos')
        .where('status_atividade', isEqualTo: 'INATIVO(A)')
        .get();
    final alunos = snapshot.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .where((aluno) {
          final id = (aluno['id'] ?? '').toString();
          final nome = _normalizarOrdenacao((aluno['nome'] ?? '').toString());
          return !_idsAlunosParticipantesEvento.contains(id) &&
              !_nomesAlunosParticipantesEvento.contains(nome);
        })
        .toList();
    alunos.sort((a, b) => _normalizarOrdenacao((a['nome'] ?? '').toString())
        .compareTo(_normalizarOrdenacao((b['nome'] ?? '').toString())));
    return alunos;
  }

  Future<Map<String, dynamic>?> _selecionarAlunoHistorico() async {
    final ativos = await _carregarAlunosAtivosHistorico();
    final graduacoes = await _graduacaoService.buscarTodasGraduacoes();
    final graduacoesPorId = <String, Map<String, dynamic>>{
      for (final g in graduacoes)
        if ((g['id'] ?? '').toString().isNotEmpty) (g['id']).toString(): g,
    };
    if (!mounted) return null;

    final search = TextEditingController();
    var query = '';
    var mostrarInativos = false;
    var carregandoInativos = false;
    List<Map<String, dynamic>>? inativos;

    Future<void> carregarInativos(StateSetter setSheetState) async {
      if (inativos != null || carregandoInativos) return;
      setSheetState(() => carregandoInativos = true);
      try {
        inativos = await _carregarAlunosInativosHistorico();
      } finally {
        if (mounted) setSheetState(() => carregandoInativos = false);
      }
    }

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final base = mostrarInativos ? (inativos ?? const <Map<String, dynamic>>[]) : ativos;
          final filtrados = base.where((a) {
            final nome = _normalizarOrdenacao((a['nome'] ?? '').toString());
            return nome.contains(_normalizarOrdenacao(query));
          }).toList();

          return SafeArea(
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: .90,
              minChildSize: .56,
              maxChildSize: .96,
              builder: (_, controller) => Material(
                color: context.uai.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.uai.border,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: context.uai.primary.withAlpha(26),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(Icons.person_add_alt_1_rounded, color: context.uai.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Selecionar aluno',
                                  style: TextStyle(
                                    color: context.uai.textPrimary,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  mostrarInativos
                                      ? 'Alunos inativos — carregados somente quando solicitado'
                                      : 'Alunos ativos — leitura padrão',
                                  style: TextStyle(color: context.uai.textSecondary, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: TextField(
                        controller: search,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: 'Buscar aluno...',
                          filled: true,
                          fillColor: context.uai.cardAlt,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: context.uai.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: context.uai.border),
                          ),
                        ),
                        onChanged: (v) => setSheetState(() => query = v.trim()),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        children: [
                          Expanded(
                            child: _selectorStatusButton(
                              label: 'ATIVOS',
                              icon: Icons.check_circle_rounded,
                              selected: !mostrarInativos,
                              onTap: () => setSheetState(() => mostrarInativos = false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _selectorStatusButton(
                              label: 'INATIVOS',
                              icon: Icons.pause_circle_filled_rounded,
                              selected: mostrarInativos,
                              onTap: () async {
                                setSheetState(() => mostrarInativos = true);
                                await carregarInativos(setSheetState);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: carregandoInativos && mostrarInativos
                          ? const Center(child: CircularProgressIndicator())
                          : filtrados.isEmpty
                              ? Center(
                                  child: Text(
                                    mostrarInativos ? 'Nenhum aluno inativo encontrado.' : 'Nenhum aluno ativo encontrado.',
                                    style: TextStyle(color: context.uai.textSecondary),
                                  ),
                                )
                              : ListView.separated(
                                  controller: controller,
                                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
                                  itemCount: filtrados.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                                  itemBuilder: (_, i) {
                                    final aluno = filtrados[i];
                                    final gradId = (aluno['graduacao_atual_id'] ?? aluno['graduacao_id'] ?? '').toString();
                                    return _buildAlunoSeletorHistoricoCard(
                                      aluno,
                                      graduacao: graduacoesPorId[gradId],
                                      inativo: mostrarInativos,
                                      onTap: () => Navigator.pop(sheetContext, aluno),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    search.dispose();
    return result;
  }

  Widget _selectorStatusButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final t = context.uai;
    final color = selected ? t.primary : t.textSecondary;
    return Material(
      color: selected ? t.primary.withAlpha(26) : t.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? t.primary.withAlpha(89) : t.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 7),
              Flexible(
                child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlunoSeletorHistoricoCard(
    Map<String, dynamic> aluno, {
    required Map<String, dynamic>? graduacao,
    required bool inativo,
    required VoidCallback onTap,
  }) {
    final t = context.uai;
    final nome = (aluno['nome'] ?? 'Aluno').toString();
    final foto = _pickFirstClean(aluno, const ['foto_perfil_aluno', 'foto', 'foto_url', 'fotoUrl']);
    final gradNome = (aluno['graduacao_atual'] ?? aluno['graduacao'] ?? 'SEM GRADUAÇÃO').toString();

    return SizedBox(
      height: 84,
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: t.border),
              boxShadow: t.softShadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 84,
                  child: foto != null && foto.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: foto,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => _alunoSelectorFallback(nome),
                        )
                      : _alunoSelectorFallback(nome),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(11, 8, 6, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          nome.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: t.textPrimary, fontSize: 13.2, height: 1.05, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          gradNome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: t.textSecondary, fontSize: 10.8, fontWeight: FontWeight.w700),
                        ),
                        if (inativo) ...[
                          const SizedBox(height: 4),
                          Text('INATIVO', style: TextStyle(color: t.warning, fontSize: 9.5, fontWeight: FontWeight.w900)),
                        ],
                      ],
                    ),
                  ),
                ),
                if (graduacao != null)
                  SizedBox(width: 64, child: Center(child: _buildCordaSvg(graduacao))),
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: Icon(Icons.chevron_right_rounded, color: t.textMuted, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _alunoSelectorFallback(String nome) {
    final t = context.uai;
    final initial = nome.trim().isEmpty ? '?' : nome.trim()[0].toUpperCase();
    return Container(
      color: t.cardAlt,
      alignment: Alignment.center,
      child: Text(initial, style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
    );
  }

  Widget _buildCordaSvg(Map<String, dynamic> data, {double width = 60, double height = 50}) {
    Color parse(dynamic value, Color fallback) {
      final raw = value?.toString().trim();
      if (raw == null || raw.isEmpty) return fallback;
      var hex = raw.replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      final parsed = int.tryParse(hex, radix: 16);
      return parsed == null ? fallback : Color(parsed);
    }

    final t = context.uai;
    final cor1 = parse(data['graduacao_hex_cor1'] ?? data['hex_cor1'], t.warning);
    final cor2 = parse(data['graduacao_hex_cor2'] ?? data['hex_cor2'], cor1);
    final ponta1 = parse(data['graduacao_hex_ponta1'] ?? data['hex_ponta1'], cor1);
    final ponta2 = parse(data['graduacao_hex_ponta2'] ?? data['hex_ponta2'], cor2);
    return SizedBox(
      width: width,
      height: height,
      child: FutureBuilder<String?>(
        future: SvgService.getSvgContent(context),
        builder: (_, snap) {
          final svg = SvgService.getModifiedSvg(
            svgContent: snap.data,
            cor1: cor1,
            cor2: cor2,
            ponta1: ponta1,
            ponta2: ponta2,
          );
          if (svg == null) return Icon(Icons.military_tech_rounded, color: cor1);
          final sanitized = svg.replaceAll(RegExp(r'<style\b[^>]*>[\s\S]*?</style\s*>', caseSensitive: false), '');
          return SvgPicture.string(sanitized, fit: BoxFit.contain);
        },
      ),
    );
  }

  Future<void> _adicionarParticipacaoHistorica() async {
    final evento = widget.evento;
    if (evento == null || evento.id == null) return;

    final aluno = await _selecionarAlunoHistorico();
    if (aluno == null || !mounted) return;

    final configuracao = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AdicionarParticipanteModal(
        aluno: {
          ...aluno,
          'graduacao': aluno['graduacao_atual'] ?? aluno['graduacao'] ?? '',
          'nivel_graduacao': aluno['nivel_graduacao'] ?? 0,
          'foto': aluno['foto_perfil_aluno'] ?? aluno['foto'] ?? aluno['foto_url'] ?? aluno['fotoUrl'],
        },
        evento: evento,
        isBatizado: _eventoEhBatizado(evento),
        historicoSomenteGraduacao: true,
      ),
    );
    if (configuracao == null) return;

    try {
      final eventoAtualizaGraduacao = _eventoEhBatizado(evento);
      final novaGraduacao = eventoAtualizaGraduacao && configuracao['graduacao'] is Map
          ? configuracao['graduacao']['nome_graduacao']?.toString()
          : null;
      final novaGraduacaoId = eventoAtualizaGraduacao
          ? configuracao['graduacaoId']?.toString()
          : null;
      final criada = await _participacaoService.adicionarParticipante(
        alunoId: aluno['id'].toString(),
        alunoNome: (aluno['nome'] ?? 'Aluno').toString(),
        alunoFoto: (aluno['foto_perfil_aluno'] ?? aluno['foto'] ?? aluno['foto_url'] ?? aluno['fotoUrl'])?.toString(),
        eventoId: evento.id!,
        eventoNome: evento.nome,
        dataEvento: evento.data,
        tipoEvento: evento.tipo,
        graduacao: (aluno['graduacao_atual'] ?? aluno['graduacao'])?.toString(),
        graduacaoId: aluno['graduacao_atual_id']?.toString(),
        tamanhoCamisa: configuracao['tamanhoCamisa']?.toString(),
        modelagemCamisa: (configuracao['modelagemCamisa'] ?? configuracao['modelagem_camisa'])?.toString(),
        tipoCamisa: (configuracao['tipoCamisa'] ?? configuracao['tipo_camisa'])?.toString(),
        valorInscricao: 0,
        valorCamisa: 0,
        graduacaoNova: novaGraduacao,
        graduacaoNovaId: novaGraduacaoId,
        status: 'pendente',
      );
      final participacaoId = criada['id'].toString();

      await _participacaoService.finalizarParticipacao(
        participacaoId: participacaoId,
        novaGraduacao: novaGraduacao,
        novaGraduacaoId: novaGraduacaoId,
      );

      if (novaGraduacaoId != null && novaGraduacaoId.isNotEmpty && novaGraduacao != null && novaGraduacao.isNotEmpty) {
        await _graduacaoService.atualizarGraduacaoAluno(
          alunoId: aluno['id'].toString(),
          novaGraduacaoId: novaGraduacaoId,
          novaGraduacaoNome: novaGraduacao,
          dataGraduacao: evento.data,
          eventoId: evento.id!,
        );
      }

      if (!mounted) return;
      _showSnack('Participação finalizada e registrada com sucesso!', type: _SnackType.success);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Erro ao inserir participação: $e', type: _SnackType.error);
    }
  }

  Future<void> _adicionarParticipacao() {
    if (!_podeAdicionar) {
      _showSnack(
        'Você não tem permissão para adicionar participantes.',
        type: _SnackType.error,
      );
      return Future.value();
    }

    if (_modoEvento && widget.evento != null) {
      return _adicionarParticipacaoHistorica();
    }

    return _abrirFormulario(mensagemSucesso: '✅ Participação adicionada!');
  }

  Future<void> _abrirFormulario({
    Map<String, dynamic>? participacao,
    String? participacaoId,
    required String mensagemSucesso,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FormularioParticipacao(
          participacao: participacao,
          participacaoId: participacaoId,
          onSalvo: () {
            Navigator.pop(context);
            _showSnack(mensagemSucesso, type: _SnackType.success);
          },
        );
      },
    );
  }

  void _mostrarFiltros() {
    String? filtroTemp = _filtroEvento;
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.surface);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(t.cardRadius + 4),
                  border: Border.all(color: t.border),
                  boxShadow: t.cardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dialogHandle(),
                    const SizedBox(height: 16),
                    _sectionHeader(
                      icon: Icons.filter_alt_rounded,
                      title: 'Filtrar participações',
                      subtitle: 'Escolha um evento para limitar a listagem.',
                      color: primary,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: filtroTemp ?? 'Todos',
                      isExpanded: true,
                      dropdownColor: t.surface,
                      style: TextStyle(color: t.textPrimary),
                      decoration: _inputDecoration(
                        label: 'Evento',
                        icon: Icons.event_rounded,
                      ),
                      items: _eventosList.map((evento) {
                        return DropdownMenuItem<String>(
                          value: evento,
                          child: Text(
                            evento,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: t.textPrimary),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setStateDialog(() {
                          filtroTemp = value == 'Todos' ? null : value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 390;

                        final clear = OutlinedButton.icon(
                          onPressed: () {
                            setState(() => _filtroEvento = null);
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.cleaning_services_rounded),
                          label: const Text('LIMPAR'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            foregroundColor: t.textPrimary,
                            side: BorderSide(color: t.border),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                t.buttonRadius,
                              ),
                            ),
                          ),
                        );

                        final apply = ElevatedButton.icon(
                          onPressed: () {
                            setState(() => _filtroEvento = filtroTemp);
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('APLICAR'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: t.primary,
                            foregroundColor: _readableOn(t.primary),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                t.buttonRadius,
                              ),
                            ),
                          ),
                        );

                        if (narrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              clear,
                              const SizedBox(height: 10),
                              apply,
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: clear),
                            const SizedBox(width: 10),
                            Expanded(child: apply),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _limparTudo() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _filtroEvento = null;
    });
  }

  List<QueryDocumentSnapshot> _filtrarDocs(List<QueryDocumentSnapshot> docs) {
    var filtrados = docs;

    if (_modoEvento) {
      filtrados = filtrados.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['evento_id']?.toString() == widget.eventoId;
      }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtrados = filtrados.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final nome = data['aluno_nome']?.toString().toLowerCase() ?? '';
        final evento = data['evento_nome']?.toString().toLowerCase() ?? '';
        final graduacao = data['graduacao']?.toString().toLowerCase() ?? '';

        return nome.contains(_searchQuery) ||
            evento.contains(_searchQuery) ||
            graduacao.contains(_searchQuery);
      }).toList();
    }

    if (!_modoEvento && _filtroEvento != null) {
      filtrados = filtrados.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['evento_nome'] == _filtroEvento;
      }).toList();
    }

    if (_modoEvento) {
      filtrados.sort((a, b) {
        final ad = a.data() as Map<String, dynamic>;
        final bd = b.data() as Map<String, dynamic>;
        return _normalizarOrdenacao((ad['aluno_nome'] ?? '').toString())
            .compareTo(_normalizarOrdenacao((bd['aluno_nome'] ?? '').toString()));
      });
    }

    return filtrados;
  }

  String _formatarData(dynamic data) {
    if (data == null) return 'Data não informada';

    if (data is Timestamp) {
      final d = data.toDate();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    }

    if (data is DateTime) {
      return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
    }

    final text = data.toString().trim();
    return text.isEmpty ? 'Data não informada' : text;
  }

  String _safe(Map<String, dynamic> data, String key, String fallback) {
    final text = data[key]?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    if (_checkingAccess) {
      return PermissionAccessGuard.loadingScaffold(
        context,
        title: _modoEvento ? 'Participações do evento' : 'Participações',
      );
    }

    if (_accessDenied) {
      return PermissionAccessGuard.deniedScaffold(
        context,
        title: _modoEvento ? 'Participações do evento' : 'Participações',
        message: 'Você não tem permissão para acessar participantes do evento.',
      );
    }

    return Scaffold(
      backgroundColor: t.background,
      floatingActionButton: _podeAdicionar
          ? FloatingActionButton.extended(
              onPressed: _adicionarParticipacao,
              backgroundColor: t.primary,
              foregroundColor: _readableOn(t.primary),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'NOVA',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            )
          : null,
      body: StreamBuilder<QuerySnapshot>(
        stream: _modoEvento
            ? FirebaseFirestore.instance
                .collection('participacoes_eventos')
                .where('evento_id', isEqualTo: widget.eventoId)
                .snapshots()
            : FirebaseFirestore.instance
                .collection('participacoes_eventos')
                .orderBy('data_evento', descending: true)
                .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _buildError(snapshot.error);

          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoading();
          }

          final todosDocs = snapshot.data?.docs ?? [];
          if (_modoEvento) {
            _idsAlunosParticipantesEvento = todosDocs
                .map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _pickFirstClean(data, const ['aluno_id', 'alunoId', 'id_aluno']);
                })
                .whereType<String>()
                .where((id) => id.isNotEmpty)
                .toSet();
            _nomesAlunosParticipantesEvento = todosDocs
                .map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _normalizarOrdenacao(
                    _pickFirstClean(data, const ['aluno_nome', 'nome_aluno', 'alunoNome']) ?? '',
                  );
                })
                .where((nome) => nome.isNotEmpty)
                .toSet();
          }
          final docs = _filtrarDocs(todosDocs);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 260,
                backgroundColor: t.primary,
                foregroundColor: _readableOn(t.primary),
                title: Text(
                  _modoEvento ? (widget.eventoNome ?? 'Participações do evento') : 'Participações',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                actions: [
                  if (!_modoEvento)
                    IconButton(
                      tooltip: 'Filtros',
                      onPressed: _mostrarFiltros,
                      icon: Badge(
                        isLabelVisible: _filtroEvento != null,
                        smallSize: 8,
                        child: const Icon(Icons.filter_alt_rounded),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Adicionar',
                    onPressed: _adicionarParticipacao,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildHero(
                    total: todosDocs.length,
                    exibindo: docs.length,
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(74),
                  child: _buildSearchBar(),
                ),
              ),
              if (_temFiltroAtivo)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                    child: _buildFiltrosAtivos(),
                  ),
                ),
              if (todosDocs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmpty(
                    title: 'Nenhuma participação cadastrada',
                    subtitle:
                        'Toque em Nova para cadastrar a primeira participação.',
                    showButton: true,
                  ),
                )
              else if (docs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmpty(
                    title: 'Nenhum resultado encontrado',
                    subtitle:
                        'Tente limpar os filtros ou buscar por outro termo.',
                    showButton: false,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: _buildParticipacoesLayout(docs),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHero({required int total, required int exibindo}) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      decoration: BoxDecoration(gradient: t.primaryGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 62, 18, 92),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Row(
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      color: onPrimary.withAlpha(36),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: onPrimary.withAlpha(41)),
                    ),
                    child: Icon(
                      Icons.assignment_ind_rounded,
                      color: onPrimary,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gerenciar participações',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: onPrimary,
                            fontSize: 23,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Controle histórico de alunos, eventos, graduações e certificados.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: onPrimary.withAlpha(209),
                            fontSize: 12.5,
                            height: 1.28,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _whiteChip(
                              icon: Icons.collections_bookmark_rounded,
                              label: '$total total',
                            ),
                            _whiteChip(
                              icon: Icons.visibility_rounded,
                              label: '$exibindo exibindo',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: TextField(
            controller: _searchController,
            style: TextStyle(color: onPrimary),
            decoration: InputDecoration(
              hintText: 'Buscar por aluno, evento ou graduação...',
              hintStyle: TextStyle(color: onPrimary.withAlpha(184)),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: onPrimary.withAlpha(219),
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: onPrimary.withAlpha(219),
                      ),
                      onPressed: _searchController.clear,
                    )
                  : null,
              filled: true,
              fillColor: onPrimary.withAlpha(36),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.inputRadius),
                borderSide: BorderSide(color: onPrimary.withAlpha(41)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.inputRadius),
                borderSide: BorderSide(color: onPrimary.withAlpha(41)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.inputRadius),
                borderSide: BorderSide(color: onPrimary, width: 1.2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParticipacoesLayout(List<QueryDocumentSnapshot> docs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980 ? 2 : 1;
        const spacing = 10.0;
        final itemWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: docs.map((doc) {
            final participacao = doc.data() as Map<String, dynamic>;
            return SizedBox(
              width: itemWidth,
              child: _buildParticipacaoCard(participacao, doc.id),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildParticipacaoCard(Map<String, dynamic> participacao, String id) {
    final t = context.uai;
    final alunoNome = _safe(participacao, 'aluno_nome', 'Aluno não informado');
    final eventoNome = _safe(participacao, 'evento_nome', 'Evento não informado');
    final graduacao = _graduacaoEventoNome(participacao);
    final dataEvento = _formatarData(participacao['data_evento']);
    final certificado = participacao['link_certificado']?.toString() ?? '';
    final temCertificado = certificado.trim().isNotEmpty;
    final mostraGraduacao = _eventoExibeGraduacao;
    final cardHeight = mostraGraduacao ? 104.0 : 94.0;

    return SizedBox(
      height: cardHeight,
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _editarParticipacao(participacao, id),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius - 4),
              border: Border.all(color: t.border),
              boxShadow: t.softShadow,
            ),
            child: Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: cardHeight,
                      child: _participacaoFotoCard(
                        alunoNome,
                        fotoUrl: _fotoParticipacao(participacao),
                        alunoId: _pickFirstClean(participacao, const [
                          'aluno_id',
                          'alunoId',
                          'id_aluno',
                        ]),
                        participacaoId: id,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          mostraGraduacao ? 9 : 11,
                          8,
                          mostraGraduacao ? 9 : 11,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              alunoNome.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 14.2,
                                height: 1.06,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (!_modoEvento) ...[
                              const SizedBox(height: 4),
                              Text(
                                eventoNome,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: t.textSecondary,
                                  fontSize: 10.8,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            if (mostraGraduacao) ...[
                              const SizedBox(height: 5),
                              Text(
                                graduacao,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _ensureVisible(t.warning, t.card),
                                  fontSize: 10.8,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 9,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.calendar_month_rounded,
                                      size: 12,
                                      color: t.textMuted,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      dataEvento,
                                      style: TextStyle(
                                        color: t.textMuted,
                                        fontSize: 9.8,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                if (temCertificado)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.verified_rounded,
                                        size: 12,
                                        color: t.success,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        'CERTIFICADO',
                                        style: TextStyle(
                                          color: t.success,
                                          fontSize: 9.3,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (mostraGraduacao)
                      SizedBox(
                        width: 72,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 24, 7, 7),
                          child: Center(
                            child: _buildCordaParticipacao(
                              participacao,
                              width: 60,
                              height: 58,
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 28),
                  ],
                ),
                Positioned(
                  right: 3,
                  top: 2,
                  child: PopupMenuButton<String>(
                    tooltip: 'Ações',
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: t.textSecondary,
                      size: 20,
                    ),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _editarParticipacao(participacao, id);
                      }
                      if (value == 'certificate' && temCertificado) {
                        _abrirLink(certificado);
                      }
                      if (value == 'delete') {
                        _excluirParticipacao(id, alunoNome, eventoNome);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Editar participação'),
                      ),
                      if (temCertificado)
                        const PopupMenuItem(
                          value: 'certificate',
                          child: Text('Abrir certificado'),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Excluir participação'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _participacaoFotoCard(
    String nome, {
    String? fotoUrl,
    String? alunoId,
    String? participacaoId,
  }) {
    final t = context.uai;
    final inicial = nome.trim().isEmpty ? '?' : nome.trim()[0].toUpperCase();
    final cleanAlunoId = alunoId?.trim();

    Widget fallback() => Container(
          color: t.cardAlt,
          alignment: Alignment.center,
          child: Text(
            inicial,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        );

    Widget loading() => Container(
          color: t.cardAlt,
          alignment: Alignment.center,
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.1,
              color: t.primary,
            ),
          ),
        );

    Widget image(String url, {bool recoverOnError = true}) => CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 120),
          placeholder: (_, _) => loading(),
          errorWidget: (_, _, _) {
            if (recoverOnError && cleanAlunoId != null && cleanAlunoId.isNotEmpty) {
              _agendarRecuperacaoFoto(
                alunoId: cleanAlunoId,
                participacaoId: participacaoId,
                ignorarCache: true,
              );
              final notifier = _fotoNotifier(cleanAlunoId);
              return ValueListenableBuilder<String?>(
                valueListenable: notifier,
                builder: (_, recovered, _) {
                  if (recovered == null) return loading();
                  if (recovered.trim().isEmpty || recovered.trim() == url.trim()) {
                    return fallback();
                  }
                  return image(recovered.trim(), recoverOnError: false);
                },
              );
            }
            return fallback();
          },
        );

    if (fotoUrl != null && fotoUrl.trim().isNotEmpty) {
      return image(fotoUrl.trim());
    }

    if (cleanAlunoId == null || cleanAlunoId.isEmpty) return fallback();

    final cached = _fotoAlunoCache[cleanAlunoId];
    if (cached != null && cached.trim().isNotEmpty) {
      return image(cached.trim());
    }

    _agendarRecuperacaoFoto(
      alunoId: cleanAlunoId,
      participacaoId: participacaoId,
    );

    return ValueListenableBuilder<String?>(
      valueListenable: _fotoNotifier(cleanAlunoId),
      builder: (_, recovered, _) {
        if (recovered == null) return loading();
        if (recovered.trim().isEmpty) return fallback();
        return image(recovered.trim(), recoverOnError: false);
      },
    );
  }

  ValueNotifier<String?> _fotoNotifier(String alunoId) {
    return _fotoAlunoNotifiers.putIfAbsent(
      alunoId,
      () => ValueNotifier<String?>(_fotoAlunoCache[alunoId]),
    );
  }

  void _agendarRecuperacaoFoto({
    required String alunoId,
    String? participacaoId,
    bool ignorarCache = false,
  }) {
    final id = alunoId.trim();
    if (id.isEmpty || !mounted) return;

    if (!ignorarCache && _fotoAlunoCache.containsKey(id)) {
      final cached = _fotoAlunoCache[id];
      final notifier = _fotoNotifier(id);
      final resolved = cached?.trim() ?? '';
      if (notifier.value != resolved) notifier.value = resolved;
      return;
    }

    if (_fotoRecoveryInFlight.contains(id)) return;
    final existing = _fotoRecoveryQueue[id];
    if (existing != null) {
      if ((existing.participacaoId == null || existing.participacaoId!.isEmpty) &&
          participacaoId != null && participacaoId.trim().isNotEmpty) {
        _fotoRecoveryQueue[id] = _FotoRecoveryJob(
          alunoId: id,
          participacaoId: participacaoId.trim(),
          ignorarCache: existing.ignorarCache || ignorarCache,
        );
      }
      return;
    }

    _fotoRecoveryQueue[id] = _FotoRecoveryJob(
      alunoId: id,
      participacaoId: participacaoId?.trim(),
      ignorarCache: ignorarCache,
    );
    scheduleMicrotask(_processarFilaRecuperacaoFoto);
  }

  void _processarFilaRecuperacaoFoto() {
    while (_fotoRecoveryRunning < _fotoRecoveryMaxConcurrent &&
        _fotoRecoveryQueue.isNotEmpty &&
        mounted) {
      final key = _fotoRecoveryQueue.keys.first;
      final job = _fotoRecoveryQueue.remove(key)!;
      _fotoRecoveryRunning++;
      _fotoRecoveryInFlight.add(job.alunoId);

      unawaited(_executarRecuperacaoFoto(job).whenComplete(() {
        _fotoRecoveryInFlight.remove(job.alunoId);
        _fotoRecoveryRunning--;
        if (mounted) scheduleMicrotask(_processarFilaRecuperacaoFoto);
      }));
    }
  }

  Future<void> _executarRecuperacaoFoto(_FotoRecoveryJob job) async {
    try {
      if (job.ignorarCache) {
        _fotoAlunoCache.remove(job.alunoId);
      }

      final foto = await _buscarFotoAluno(job.alunoId);
      if (!mounted || foto == null || foto.trim().isEmpty) {
        final notifier = _fotoNotifier(job.alunoId);
        if (notifier.value == null) notifier.value = '';
        return;
      }

      final cleanFoto = foto.trim();
      _fotoAlunoCache[job.alunoId] = cleanFoto;
      final notifier = _fotoNotifier(job.alunoId);
      if (notifier.value != cleanFoto) notifier.value = cleanFoto;

      final participacaoId = job.participacaoId?.trim();
      if (participacaoId == null || participacaoId.isEmpty) return;

      // Persistência em segundo plano: a UI já foi atualizada acima e não espera
      // Firestore/cache terminar. Assim dezenas de fotos antigas não travam a tela.
      unawaited(_sincronizarFotoParticipacaoEmBackground(
        participacaoId: participacaoId,
        foto: cleanFoto,
      ));
    } catch (e) {
      debugPrint('Aviso: falha silenciosa ao recuperar foto do aluno ${job.alunoId}: $e');
      if (mounted) {
        final notifier = _fotoNotifier(job.alunoId);
        if (notifier.value == null) notifier.value = '';
      }
    }
  }

  Future<void> _sincronizarFotoParticipacaoEmBackground({
    required String participacaoId,
    required String foto,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('participacoes_eventos')
          .doc(participacaoId)
          .update({
        'aluno_foto_url': foto,
        'aluno_foto': foto,
        'foto_perfil_aluno': foto,
      });
      await _cacheService.atualizarCacheDaParticipacao(participacaoId);
    } catch (e) {
      debugPrint('Aviso: não foi possível persistir foto da participação $participacaoId: $e');
    }
  }

  Widget _avatarAluno(String nome, {String? fotoUrl, String? alunoId}) {
    final t = context.uai;
    final inicial = nome.trim().isEmpty ? '?' : nome.trim()[0].toUpperCase();
    final onPrimary = _readableOn(t.primary);

    Widget fallback() {
      return Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          gradient: t.primaryGradient,
          borderRadius: BorderRadius.circular(t.buttonRadius),
        ),
        child: Center(
          child: Text(
            inicial,
            style: TextStyle(
              color: onPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
    }

    Widget image(String url) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(t.buttonRadius),
        child: SizedBox(
          width: 50,
          height: 50,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, _) => fallback(),
            errorWidget: (_, _, _) => fallback(),
          ),
        ),
      );
    }

    if (fotoUrl != null) return image(fotoUrl);

    final cleanAlunoId = alunoId?.trim();
    if (cleanAlunoId == null || cleanAlunoId.isEmpty) return fallback();

    if (_fotoAlunoCache.containsKey(cleanAlunoId)) {
      final cached = _fotoAlunoCache[cleanAlunoId];
      return cached == null ? fallback() : image(cached);
    }

    return FutureBuilder<String?>(
      future: _buscarFotoAluno(cleanAlunoId),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null || url.trim().isEmpty) return fallback();
        return image(url);
      },
    );
  }

  Future<String?> _buscarFotoAluno(String alunoId) async {
    if (_fotoAlunoCache.containsKey(alunoId)) return _fotoAlunoCache[alunoId];

    try {
      final doc = await FirebaseFirestore.instance
          .collection('alunos')
          .doc(alunoId)
          .get();
      final data = doc.data() ?? {};
      final foto = _pickFirstClean(data, const [
        'aluno_foto_url',
        'foto_perfil_aluno',
        'foto_url',
        'fotoUrl',
        'photoURL',
        'avatar',
        'avatar_url',
        'imagem_url',
        'foto',
      ]);
      _fotoAlunoCache[alunoId] = foto;
      return foto;
    } catch (e) {
      debugPrint('Erro ao buscar foto do aluno $alunoId: $e');
      _fotoAlunoCache[alunoId] = null;
      return null;
    }
  }

  String? _fotoParticipacao(Map<String, dynamic> participacao) {
    return _pickFirstClean(participacao, const [
      'aluno_foto_url',
      'aluno_foto',
      'foto_perfil_aluno',
      'foto_url',
      'fotoUrl',
      'photoURL',
      'avatar',
      'avatar_url',
      'imagem_url',
      'foto',
    ]);
  }

  Widget _infoChip(IconData icon, String text, Color color) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withAlpha(18), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withAlpha(33)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 13),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 10.8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltrosAtivos() {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Icon(
            Icons.filter_alt_rounded,
            color: _ensureVisible(t.primary, t.card),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                if (_searchQuery.isNotEmpty)
                  _filterPill('Busca: $_searchQuery'),
                if (_filtroEvento != null)
                  _filterPill('Evento: $_filtroEvento'),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Limpar filtros',
            onPressed: _limparTudo,
            icon: Icon(Icons.close_rounded, color: t.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _filterPill(String text) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(primary.withAlpha(23), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: primary.withAlpha(41)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: primary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildLoading() {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: t.primary),
              const SizedBox(height: 14),
              Text(
                'Carregando participações...',
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(Object? error) {
    final t = context.uai;
    final accent = _ensureVisible(t.error, t.card);

    return Scaffold(
      backgroundColor: t.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.all(24),
            decoration: _cardDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 74, color: accent),
                const SizedBox(height: 12),
                Text(
                  'Erro ao carregar participações',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error?.toString() ?? 'Tente novamente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.textSecondary, height: 1.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty({
    required String title,
    required String subtitle,
    required bool showButton,
  }) {
    final t = context.uai;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(24),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_busy_rounded, size: 74, color: t.textMuted),
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
              const SizedBox(height: 7),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary, height: 1.3),
              ),
              if (showButton) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _adicionarParticipacao,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('ADICIONAR PARTICIPAÇÃO'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.primary,
                    foregroundColor: _readableOn(t.primary),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
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

  Widget _whiteChip({required IconData icon, required String label}) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: onPrimary.withAlpha(36),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withAlpha(41)),
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

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: accent.withAlpha(26),
            borderRadius: BorderRadius.circular(t.buttonRadius),
          ),
          child: Icon(icon, color: accent),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 11.5,
                  height: 1.22,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: t.textSecondary),
      prefixIcon: Icon(icon, color: primary),
      filled: true,
      fillColor: t.cardAlt,
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
    );
  }

  Widget _dialogHandle() {
    final t = context.uai;

    return Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: t.border,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    final t = context.uai;

    return BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      border: Border.all(color: t.border),
      boxShadow: t.softShadow,
    );
  }

  Future<void> _abrirLink(String? url) async {
    if (url == null || url.trim().isEmpty) return;

    try {
      final uri = Uri.parse(url.trim());

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir link: $e');
    }
  }
}

class FormularioParticipacao extends StatefulWidget {
  final Map<String, dynamic>? participacao;
  final String? participacaoId;
  final VoidCallback onSalvo;

  const FormularioParticipacao({
    super.key,
    this.participacao,
    this.participacaoId,
    required this.onSalvo,
  });

  @override
  State<FormularioParticipacao> createState() => _FormularioParticipacaoState();
}

class _FormularioParticipacaoState extends State<FormularioParticipacao> {
  final EventoParticipantesCacheService _cacheService =
      EventoParticipantesCacheService();
  final ParticipacaoService _participacaoService = ParticipacaoService();
  final GraduacaoService _graduacaoService = GraduacaoService();
  final _formKey = GlobalKey<FormState>();

  final _alunoNomeController = TextEditingController();
  final _eventoNomeController = TextEditingController();
  final _dataController = TextEditingController();
  final _tipoController = TextEditingController();
  final _graduacaoController = TextEditingController();
  final _certificadoController = TextEditingController();

  String? _alunoId;
  String? _eventoId;
  String? _graduacaoSelecionadaId;
  Map<String, dynamic>? _graduacaoSelecionada;
  Future<List<Map<String, dynamic>>>? _graduacoesFuture;

  bool _isLoading = false;
  bool _isLoadingAlunos = false;
  bool _isLoadingEventos = false;

  List<Map<String, dynamic>> _alunosList = [];
  List<Map<String, dynamic>> _eventosList = [];

  String _normalizarEvento(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[ÁÀÂÃÄ]'), 'A')
        .replaceAll(RegExp(r'[ÉÈÊË]'), 'E')
        .replaceAll(RegExp(r'[ÍÌÎÏ]'), 'I')
        .replaceAll(RegExp(r'[ÓÒÔÕÖ]'), 'O')
        .replaceAll(RegExp(r'[ÚÙÛÜ]'), 'U')
        .replaceAll('Ç', 'C');
  }

  bool get _eventoPermiteGraduacao {
    // Usa somente o TIPO salvo na participação/evento.
    // Nunca inferir pelo nome do evento.
    final tipo = _normalizarEvento(_tipoController.text);
    return tipo.contains('BATIZADO') || tipo.contains('TROCA DE CORDAS');
  }

  @override
  void initState() {
    super.initState();
    if (widget.participacao != null) {
      _preencherFormulario();
      if (_eventoPermiteGraduacao) {
        _graduacoesFuture = _graduacaoService.buscarTodasGraduacoes();
      }
    } else {
      _carregarAlunos();
      _carregarEventos();
    }
  }

  @override
  void dispose() {
    _alunoNomeController.dispose();
    _eventoNomeController.dispose();
    _dataController.dispose();
    _tipoController.dispose();
    _graduacaoController.dispose();
    _certificadoController.dispose();
    super.dispose();
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance())
        .abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Future<void> _carregarAlunos() async {
    setState(() => _isLoadingAlunos = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('alunos')
          .orderBy('nome')
          .get();

      _alunosList = snapshot.docs.map((doc) {
        return {'id': doc.id, 'nome': doc.data()['nome'] ?? ''};
      }).toList();
    } catch (e) {
      debugPrint('Erro ao carregar alunos: $e');
    } finally {
      if (mounted) setState(() => _isLoadingAlunos = false);
    }
  }

  Future<void> _carregarEventos() async {
    setState(() => _isLoadingEventos = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('eventos')
          .orderBy('nome')
          .get();

      _eventosList = snapshot.docs.map((doc) {
        final data = doc.data();

        return {
          'id': doc.id,
          'nome': data['nome'] ?? '',
          'data': data['data'] ?? data['data_evento'] ?? '',
          'tipo_evento': data['tipo_evento'] ?? data['tipo'] ?? '',
        };
      }).toList();
    } catch (e) {
      debugPrint('Erro ao carregar eventos: $e');
    } finally {
      if (mounted) setState(() => _isLoadingEventos = false);
    }
  }

  void _preencherFormulario() {
    final p = widget.participacao!;

    _alunoNomeController.text = p['aluno_nome'] ?? '';
    _eventoNomeController.text = p['evento_nome'] ?? '';
    _dataController.text = _formatarData(p['data_evento']);
    _tipoController.text = p['tipo_evento'] ?? '';
    _graduacaoController.text = (p['graduacao_final'] ?? p['graduacao_nova'] ?? p['graduacao'] ?? '').toString();
    _graduacaoSelecionadaId = (p['graduacao_final_id'] ?? p['graduacao_nova_id'] ?? p['graduacao_id'])?.toString();
    _certificadoController.text = p['link_certificado'] ?? '';
    _alunoId = p['aluno_id'];
    _eventoId = p['evento_id'];
  }

  String _formatarData(dynamic data) {
    if (data == null) return '';

    if (data is Timestamp) {
      final d = data.toDate();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    }

    if (data is DateTime) {
      return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
    }

    return data.toString();
  }

  void _selecionarAluno() {
    _abrirSeletor(
      titulo: 'Selecione o aluno',
      subtitulo: 'Escolha qual aluno será vinculado à participação.',
      icon: Icons.person_rounded,
      color: context.uai.info,
      carregando: _isLoadingAlunos,
      items: _alunosList,
      labelKey: 'nome',
      onSelected: (aluno) {
        setState(() {
          _alunoNomeController.text = aluno['nome'] ?? '';
          _alunoId = aluno['id'];
        });
      },
    );
  }

  void _selecionarEvento() {
    _abrirSeletor(
      titulo: 'Selecione o evento',
      subtitulo: 'Escolha o evento dessa participação.',
      icon: Icons.event_rounded,
      color: context.uai.success,
      carregando: _isLoadingEventos,
      items: _eventosList,
      labelKey: 'nome',
      subtitleBuilder: (evento) {
        final data = _formatarData(evento['data']);
        final tipo = evento['tipo_evento']?.toString() ?? '';
        return [data, tipo].where((e) => e.trim().isNotEmpty).join(' • ');
      },
      onSelected: (evento) {
        setState(() {
          _eventoNomeController.text = evento['nome'] ?? '';
          _eventoId = evento['id'];
          _dataController.text = _formatarData(evento['data']);
          _tipoController.text = evento['tipo_evento']?.toString() ?? '';
        });
      },
    );
  }

  void _abrirSeletor({
    required String titulo,
    required String subtitulo,
    required IconData icon,
    required Color color,
    required bool carregando,
    required List<Map<String, dynamic>> items,
    required String labelKey,
    required ValueChanged<Map<String, dynamic>> onSelected,
    String Function(Map<String, dynamic> item)? subtitleBuilder,
  }) {
    final searchController = TextEditingController();
    var query = '';
    final t = context.uai;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final filtrados = items.where((item) {
              final label = item[labelKey]?.toString().toLowerCase() ?? '';
              return label.contains(query.toLowerCase());
            }).toList();

            final accent = _ensureVisible(color, t.surface);

            return SafeArea(
              child: DraggableScrollableSheet(
                initialChildSize: 0.78,
                minChildSize: 0.45,
                maxChildSize: 0.94,
                expand: false,
                builder: (context, scrollController) {
                  return Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(t.cardRadius + 4),
                      border: Border.all(color: t.border),
                      boxShadow: t.cardShadow,
                    ),
                    child: Column(
                      children: [
                        _dialogHandle(),
                        const SizedBox(height: 16),
                        _selectorHeader(
                          icon: icon,
                          title: titulo,
                          subtitle: subtitulo,
                          color: accent,
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: searchController,
                          style: TextStyle(color: t.textPrimary),
                          decoration: _inputDecoration(
                            label: 'Buscar',
                            icon: Icons.search_rounded,
                            color: accent,
                          ),
                          onChanged: (value) {
                            setStateDialog(() => query = value.trim());
                          },
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: carregando
                              ? Center(
                                  child: CircularProgressIndicator(
                                    color: accent,
                                  ),
                                )
                              : filtrados.isEmpty
                              ? Center(
                                  child: Text(
                                    'Nenhum item encontrado.',
                                    style: TextStyle(color: t.textSecondary),
                                  ),
                                )
                              : ListView.separated(
                                  controller: scrollController,
                                  itemCount: filtrados.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final item = filtrados[index];
                                    final label =
                                        item[labelKey]?.toString() ?? '';
                                    final subtitle =
                                        subtitleBuilder?.call(item) ?? '';

                                    return Material(
                                      color: Color.alphaBlend(
                                        accent.withAlpha(18),
                                        t.cardAlt,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        t.inputRadius,
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(
                                          t.inputRadius,
                                        ),
                                        onTap: () {
                                          onSelected(item);
                                          Navigator.pop(context);
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 42,
                                                height: 42,
                                                decoration: BoxDecoration(
                                                  color: accent.withAlpha(
                                                    26,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        t.buttonRadius,
                                                      ),
                                                ),
                                                child: Icon(
                                                  icon,
                                                  color: accent,
                                                ),
                                              ),
                                              const SizedBox(width: 11),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      label,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: t.textPrimary,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                    ),
                                                    if (subtitle
                                                        .isNotEmpty) ...[
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        subtitle,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          color:
                                                              t.textSecondary,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                color: accent,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    ).whenComplete(searchController.dispose);
  }


  String _normalizarNomeGraduacao(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[ÁÀÂÃÄ]'), 'A')
        .replaceAll(RegExp(r'[ÉÈÊË]'), 'E')
        .replaceAll(RegExp(r'[ÍÌÎÏ]'), 'I')
        .replaceAll(RegExp(r'[ÓÒÔÕÖ]'), 'O')
        .replaceAll(RegExp(r'[ÚÙÛÜ]'), 'U')
        .replaceAll('Ç', 'C');
  }

  Color _hexGraduacao(dynamic value, Color fallback) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return fallback;
    var hex = raw.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }

  Widget _cordaGraduacaoEdicao(Map<String, dynamic> grad) {
    final cor1 = _hexGraduacao(grad['hex_cor1'], context.uai.warning);
    final cor2 = _hexGraduacao(grad['hex_cor2'], cor1);
    final ponta1 = _hexGraduacao(grad['hex_ponta1'], cor1);
    final ponta2 = _hexGraduacao(grad['hex_ponta2'], cor2);
    return SizedBox(
      width: 78,
      height: 56,
      child: FutureBuilder<String?>(
        future: SvgService.getSvgContent(context),
        builder: (_, snap) {
          final svg = SvgService.getModifiedSvg(
            svgContent: snap.data,
            cor1: cor1,
            cor2: cor2,
            ponta1: ponta1,
            ponta2: ponta2,
          );
          if (svg == null) return Icon(Icons.military_tech_rounded, color: cor1);
          final sanitized = svg.replaceAll(
            RegExp(r'<style\b[^>]*>[\s\S]*?</style\s*>', caseSensitive: false),
            '',
          );
          return SvgPicture.string(sanitized, fit: BoxFit.contain);
        },
      ),
    );
  }

  Widget _seletorGraduacaoEdicao() {
    final t = context.uai;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _graduacoesFuture ??= _graduacaoService.buscarTodasGraduacoes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final grads = [...?snapshot.data];
        num nivelOf(Map<String, dynamic> g) {
          final value = g['nivel_graduacao'];
          if (value is num) return value;
          return num.tryParse(value?.toString() ?? '') ?? 0;
        }
        grads.sort((a, b) => nivelOf(a).compareTo(nivelOf(b)));
        if (grads.isEmpty) {
          return Text('Nenhuma graduação cadastrada.', style: TextStyle(color: t.textSecondary));
        }
        if (_graduacaoSelecionada == null) {
          final atualNome = _normalizarNomeGraduacao(_graduacaoController.text);
          for (final g in grads) {
            final id = g['id']?.toString();
            final nome = (g['nome_graduacao'] ?? '').toString();
            if ((_graduacaoSelecionadaId != null && id == _graduacaoSelecionadaId) ||
                _normalizarNomeGraduacao(nome) == atualNome) {
              _graduacaoSelecionada = g;
              _graduacaoSelecionadaId = id;
              break;
            }
          }
        }
        return LayoutBuilder(
          builder: (_, c) {
            final columns = c.maxWidth >= 900 ? 2 : 1;
            final itemWidth = (c.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: grads.map((g) {
                final id = g['id']?.toString() ?? '';
                final nome = (g['nome_graduacao'] ?? 'Graduação').toString();
                final tipo = (g['tipo_publico'] ?? '').toString();
                final nivel = (g['nivel_graduacao'] ?? '').toString();
                final selected = id.isNotEmpty && id == _graduacaoSelecionadaId;
                return SizedBox(
                  width: itemWidth,
                  child: Material(
                    color: selected ? t.primary.withAlpha(20) : t.cardAlt,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => setState(() {
                        _graduacaoSelecionadaId = id;
                        _graduacaoSelecionada = g;
                        _graduacaoController.text = nome;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected ? t.primary : t.border,
                            width: selected ? 1.7 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            _cordaGraduacaoEdicao(g),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(nome, maxLines: 2, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 12.5, height: 1.05)),
                                  const SizedBox(height: 4),
                                  Text([if (tipo.isNotEmpty) tipo, if (nivel.isNotEmpty) 'Nível $nivel'].join(' • '),
                                    style: TextStyle(color: t.textSecondary, fontSize: 10.5)),
                                ],
                              ),
                            ),
                            if (selected) Icon(Icons.check_circle_rounded, color: t.primary, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }

  Widget _infoFixaEdicao({required IconData icon, required String label, required String value, required Color color}) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: _ensureVisible(color, t.cardAlt), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: t.textMuted, fontSize: 10.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(value.isEmpty ? '—' : value, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800)),
            ]),
          ),
          Icon(Icons.lock_outline_rounded, color: t.textMuted, size: 16),
        ],
      ),
    );
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final editando = widget.participacaoId != null;
      final permiteGraduacao = _eventoPermiteGraduacao;
      final gradNome = permiteGraduacao
          ? (_graduacaoSelecionada?['nome_graduacao'] ?? _graduacaoController.text).toString().trim()
          : '';
      final gradId = permiteGraduacao ? _graduacaoSelecionadaId?.trim() : null;
      final cert = _certificadoController.text.trim();

      final Map<String, dynamic> data;
      if (editando) {
        data = {
          if (permiteGraduacao) 'graduacao': gradNome,
          if (permiteGraduacao) 'graduacao_final': gradNome,
          if (permiteGraduacao) 'graduacao_nova': gradNome,
          if (permiteGraduacao && gradId != null && gradId.isNotEmpty) 'graduacao_id': gradId,
          if (permiteGraduacao && gradId != null && gradId.isNotEmpty) 'graduacao_final_id': gradId,
          if (permiteGraduacao && gradId != null && gradId.isNotEmpty) 'graduacao_nova_id': gradId,
          'link_certificado': cert,
          'atualizado_em': FieldValue.serverTimestamp(),
        };
      } else {
        data = {
          'aluno_id': _alunoId,
          'aluno_nome': _alunoNomeController.text.trim(),
          'evento_id': _eventoId,
          'evento_nome': _eventoNomeController.text.trim(),
          'data_evento': _dataController.text.trim(),
          'tipo_evento': _tipoController.text.trim(),
          if (permiteGraduacao) 'graduacao': gradNome,
          if (permiteGraduacao && gradId != null && gradId.isNotEmpty) 'graduacao_id': gradId,
          'link_certificado': cert,
          'atualizado_em': FieldValue.serverTimestamp(),
          'criado_em': FieldValue.serverTimestamp(),
        };
      }

      final String participacaoId;
      if (!editando) {
        final docRef = await FirebaseFirestore.instance
            .collection('participacoes_eventos')
            .add(data);
        participacaoId = docRef.id;
      } else {
        participacaoId = widget.participacaoId!;
        await FirebaseFirestore.instance
            .collection('participacoes_eventos')
            .doc(participacaoId)
            .update(data);
      }

      try {
        await _cacheService.atualizarCacheDaParticipacao(participacaoId);
      } catch (e) {
        debugPrint('Erro ao atualizar cache da participação: $e');
      }

      widget.onSalvo();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: context.uai.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Color? color,
  }) {
    final t = context.uai;
    final c = _ensureVisible(color ?? t.primary, t.cardAlt);

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: t.textSecondary),
      prefixIcon: Icon(icon, color: c),
      filled: true,
      fillColor: t.cardAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: c, width: 1.4),
      ),
    );
  }

  Widget _selectorHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: accent.withAlpha(26),
            borderRadius: BorderRadius.circular(t.buttonRadius),
          ),
          child: Icon(icon, color: accent),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 11.5,
                  height: 1.22,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _formCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required List<Widget> children,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: accent.withAlpha(36)),
          boxShadow: t.softShadow,
        ),
        child: Column(
          children: [
            _selectorHeader(
              icon: icon,
              title: title,
              subtitle: subtitle,
              color: accent,
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final editando = widget.participacao != null;
    final onPrimary = _readableOn(t.primary);

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.55,
        maxChildSize: 0.96,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: t.background,
              borderRadius: BorderRadius.circular(t.cardRadius + 4),
              border: Border.all(color: t.border),
              boxShadow: t.cardShadow,
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    gradient: t.primaryGradient,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(t.cardRadius + 4),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: onPrimary.withAlpha(115),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: onPrimary.withAlpha(36),
                              borderRadius: BorderRadius.circular(
                                t.buttonRadius,
                              ),
                              border: Border.all(
                                color: onPrimary.withAlpha(41),
                              ),
                            ),
                            child: Icon(
                              editando
                                  ? Icons.edit_note_rounded
                                  : Icons.person_add_rounded,
                              color: onPrimary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              editando
                                  ? 'Editar participação'
                                  : 'Nova participação',
                              style: TextStyle(
                                color: onPrimary,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded, color: onPrimary),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(14),
                      children: [
                        if (editando) ...[
                          _formCard(
                            icon: Icons.lock_person_rounded,
                            title: 'Participação registrada',
                            subtitle: 'Aluno, evento, data e tipo ficam bloqueados para preservar o histórico.',
                            color: t.primary,
                            children: [
                              _infoFixaEdicao(icon: Icons.person_rounded, label: 'Aluno', value: _alunoNomeController.text, color: t.info),
                              const SizedBox(height: 9),
                              _infoFixaEdicao(icon: Icons.event_rounded, label: 'Evento', value: _eventoNomeController.text, color: t.success),
                              const SizedBox(height: 9),
                              Row(
                                children: [
                                  Expanded(child: _infoFixaEdicao(icon: Icons.calendar_today_rounded, label: 'Data', value: _dataController.text, color: t.warning)),
                                  const SizedBox(width: 9),
                                  Expanded(child: _infoFixaEdicao(icon: Icons.category_rounded, label: 'Tipo', value: _tipoController.text, color: t.associacao)),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (_eventoPermiteGraduacao) ...[
                            _formCard(
                              icon: Icons.military_tech_rounded,
                              title: 'Graduação adquirida',
                              subtitle: 'Escolha a corda correta registrada neste evento.',
                              color: t.warning,
                              children: [_seletorGraduacaoEdicao()],
                            ),
                            const SizedBox(height: 14),
                          ],
                          _formCard(
                            icon: Icons.workspace_premium_rounded,
                            title: 'Certificado',
                            subtitle: 'O link pode ser corrigido ou atualizado sem alterar os demais dados.',
                            color: t.success,
                            children: [
                              TextFormField(
                                controller: _certificadoController,
                                style: TextStyle(color: t.textPrimary),
                                maxLines: 2,
                                decoration: _inputDecoration(
                                  label: 'Link do certificado',
                                  icon: Icons.link_rounded,
                                  color: t.success,
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          _formCard(
                            icon: Icons.person_rounded,
                            title: 'Aluno e evento',
                            subtitle: 'Selecione os vínculos principais.',
                            color: t.primary,
                            children: [
                              _selectField(
                                label: 'Aluno *',
                                value: _alunoNomeController.text,
                                emptyText: 'Selecione um aluno',
                                icon: Icons.person_rounded,
                                color: t.info,
                                onTap: _selecionarAluno,
                              ),
                              const SizedBox(height: 12),
                              _selectField(
                                label: 'Evento *',
                                value: _eventoNomeController.text,
                                emptyText: 'Selecione um evento',
                                icon: Icons.event_rounded,
                                color: t.success,
                                onTap: _selecionarEvento,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _formCard(
                            icon: Icons.info_rounded,
                            title: 'Informações da participação',
                            subtitle: 'Dados exibidos no histórico do aluno e certificados.',
                            color: t.associacao,
                            children: [
                              TextFormField(controller: _dataController, style: TextStyle(color: t.textPrimary), decoration: _inputDecoration(label: 'Data do evento', icon: Icons.calendar_today_rounded, color: t.warning)),
                              const SizedBox(height: 12),
                              TextFormField(controller: _tipoController, style: TextStyle(color: t.textPrimary), decoration: _inputDecoration(label: 'Tipo do evento', icon: Icons.category_rounded, color: t.associacao)),
                              const SizedBox(height: 12),
                              TextFormField(controller: _graduacaoController, style: TextStyle(color: t.textPrimary), decoration: _inputDecoration(label: 'Graduação na época', icon: Icons.emoji_events_rounded, color: t.warning)),
                              const SizedBox(height: 12),
                              TextFormField(controller: _certificadoController, style: TextStyle(color: t.textPrimary), maxLines: 2, decoration: _inputDecoration(label: 'Link do certificado', icon: Icons.link_rounded, color: t.success)),
                            ],
                          ),
                        ],
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),
                _bottomBar(editando),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _selectField({
    required String label,
    required String value,
    required String emptyText,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final t = context.uai;
    final isEmpty = value.trim().isEmpty;
    final accent = _ensureVisible(color, t.cardAlt);

    return Material(
      color: t.cardAlt,
      borderRadius: BorderRadius.circular(t.inputRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.inputRadius),
        child: InputDecorator(
          decoration: _inputDecoration(label: label, icon: icon, color: accent),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  isEmpty ? emptyText : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isEmpty ? t.textMuted : t.textPrimary,
                    fontWeight: isEmpty ? FontWeight.w500 : FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.expand_more_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(bool editando) {
    final t = context.uai;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border(top: BorderSide(color: t.border)),
          boxShadow: t.softShadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                label: const Text('CANCELAR'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.textPrimary,
                  side: BorderSide(color: t.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _salvar,
                icon: _isLoading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _readableOn(t.primary),
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  _isLoading
                      ? 'SALVANDO...'
                      : editando
                      ? 'ATUALIZAR'
                      : 'SALVAR',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.primary,
                  foregroundColor: _readableOn(t.primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogHandle() {
    final t = context.uai;

    return Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: t.border,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

enum _SnackType { success, error, warning, info }

class _FotoRecoveryJob {
  final String alunoId;
  final String? participacaoId;
  final bool ignorarCache;

  const _FotoRecoveryJob({
    required this.alunoId,
    this.participacaoId,
    this.ignorarCache = false,
  });
}
