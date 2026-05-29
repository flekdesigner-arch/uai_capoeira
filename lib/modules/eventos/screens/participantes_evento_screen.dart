import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';
import 'package:uai_capoeira/modules/eventos/services/participacao_service.dart';
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/modules/graduacoes/services/graduacao_service.dart';
import 'package:uai_capoeira/modules/eventos/services/certificado_service.dart';
import 'package:uai_capoeira/modules/eventos/models/participacao_model.dart';
import 'aluno_detalhe_participacao_screen.dart';
import 'package:uai_capoeira/modules/eventos/widgets/adicionar_participante_modal.dart';
import 'selecionar_participantes_csv_screen.dart';
import 'package:uai_capoeira/modules/eventos/reports/evento_financeiro_pdf_service.dart';


class _DashboardMiniData {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _DashboardMiniData(this.icon, this.value, this.label, this.color);
}

class _PermissaoChipData {
  final String label;
  final bool liberado;
  final IconData icon;

  const _PermissaoChipData(this.label, this.liberado, this.icon);
}

class CachedAlunoData {
  final Map<String, dynamic> data;
  final DateTime timestamp;
  CachedAlunoData(this.data) : timestamp = DateTime.now();
  bool get isExpired =>
      DateTime.now().difference(timestamp) > const Duration(days: 1);
}

class RobustAvatar extends StatelessWidget {
  final String? fotoUrl;
  final double radius;
  final Color? borderColor;

  const RobustAvatar({
    super.key,
    required this.fotoUrl,
    required this.radius,
    this.borderColor,
  });

  bool _isValidUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    return url.startsWith('http://') || url.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    final Widget avatarChild = _isValidUrl(fotoUrl)
        ? ClipOval(
      child: Image.network(
        fotoUrl!,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const SizedBox.shrink();
        },
        errorBuilder: (context, error, stackTrace) {
          return Icon(Icons.person, size: radius * 0.8, color: context.uai.textMuted);
        },
      ),
    )
        : Icon(Icons.person, size: radius * 0.8, color: context.uai.textMuted);

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: borderColor != null
            ? Border.all(color: borderColor!, width: 3)
            : Border.all(color: context.uai.border),
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: context.uai.cardAlt,
        child: avatarChild,
      ),
    );
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _StickyHeaderDelegate({required this.child, required this.height});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: context.uai.surface,
      elevation: 0,
      child: SizedBox(height: height, child: child),
    );
  }

  @override
  double get maxExtent => height;
  @override
  double get minExtent => height;
  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child.key != child.key;
  }
}

class ParticipantesEventoScreen extends StatefulWidget {
  final String eventoId;
  final String eventoNome;
  final EventoModel? evento;

  const ParticipantesEventoScreen({
    super.key,
    required this.eventoId,
    required this.eventoNome,
    this.evento,
  });

  @override
  State<ParticipantesEventoScreen> createState() => _ParticipantesEventoScreenState();
}

class _ParticipantesEventoScreenState extends State<ParticipantesEventoScreen>
    with TickerProviderStateMixin {
  final ParticipacaoService _participacaoService = ParticipacaoService();
  final PermissaoService _permissaoService = PermissaoService();
  final GraduacaoService _graduacaoService = GraduacaoService();
  final CertificadoService _certificadoService = CertificadoService();

  late final TabController _tabController;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _searchParticipantesController = TextEditingController();
  String _searchQuery = '';
  String _searchParticipantesQuery = '';
  List<Map<String, dynamic>> _alunosDisponiveis = [];
  List<String> _alunosParticipantesIds = [];
  bool _isLoadingAlunos = false;
  EventoModel? _eventoCarregado;

  int _viewMode = 0; // 0: grade, 1: lista, 2: planilha
  String _filtroStatus = 'todos';
  bool _isRefreshing = false;

  Set<String> _filtroStatusPagamento = {};
  String? _filtroGraduacaoId;
  String? _filtroStatusCamisa;

  double _totalArrecadado = 0;
  double _totalInscricoes = 0;
  int _totalParticipantes = 0;
  int _participantesPagos = 0;
  Map<String, int> _camisasPorTamanho = {};

  int _ultimoTotalParticipantes = -1;
  String _assinaturaEstatisticas = '';
  final Map<String, CachedAlunoData> _cacheAlunos = {};
  List<Map<String, dynamic>> _graduacoes = [];
  Map<String, Map<String, String>> _coresGraduacao = {};

  List<Map<String, dynamic>> _usosPatrocinio = [];
  Set<String> _participantesPatrocinados = {};

  List<ParticipacaoModel> _allParticipants = [];

  Timer? _debounceTimer;
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _searchParticipantesFocusNode = FocusNode();

  bool _podeGerenciarParticipantes = false;
  bool _podeAdicionar = false;
  bool _podeEditarParticipacao = false;
  bool _podeRemover = false;
  bool _podeConcluirParticipacao = false;
  bool _podeGerarCertificados = false;
  bool _podeExportarListas = false;
  bool _carregandoPermissoes = true;

  bool get _isBatizado {
    final tipo = (widget.evento ?? _eventoCarregado)?.tipo.toUpperCase() ?? '';
    return tipo.contains('BATIZADO');
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _onCard() => _readableOn(context.uai.card);
  Color _onCardMuted() => _onCard().withOpacity(0.68);
  Color _appBarBg() => Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary;
  Color _appBarFg() => Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(_appBarBg());

  void _onSearchAlunosChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() => _searchQuery = value.toLowerCase().trim());
    });
  }

  void _onSearchParticipantesChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() => _searchParticipantesQuery = value.toLowerCase().trim());
    });
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required bool hasValue,
    required VoidCallback onClear,
    required ValueChanged<String> onChanged,
  }) {
    final appBarLike = _appBarBg();
    final accent = _ensureVisible(context.uai.primary, context.uai.card);

    return TextField(
      controller: controller,
      focusNode: focusNode,
      style: TextStyle(
        color: context.uai.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      cursorColor: accent,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: context.uai.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(Icons.search_rounded, color: accent),
        suffixIcon: hasValue
            ? IconButton(
          icon: Icon(Icons.clear_rounded, color: context.uai.textMuted),
          onPressed: onClear,
        )
            : null,
        filled: true,
        fillColor: context.uai.card,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.uai.buttonRadius),
          borderSide: BorderSide(color: context.uai.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.uai.buttonRadius),
          borderSide: BorderSide(color: context.uai.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.uai.buttonRadius),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
      ),
      onChanged: onChanged,
    );
  }

  // ==================== INICIALIZAÇÃO ====================
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    if (widget.evento == null) _buscarEventoDoFirestore();
    _carregarGraduacoes();
    _carregarPatrocinios();
    _carregarParticipantesExistentes().then((_) => _carregarAlunos());
    _verificarPermissoes();
  }

  Future<void> _buscarEventoDoFirestore() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('eventos').doc(widget.eventoId).get();
      if (doc.exists) setState(() => _eventoCarregado = EventoModel.fromFirestore(doc));
    } catch (e) { debugPrint('Erro ao buscar evento: $e'); }
  }

  Future<void> _verificarPermissoes() async {
    if (mounted) {
      setState(() => _carregandoPermissoes = true);
    }

    try {
      final permissoes = await Future.wait<bool>([
        _permissaoService.temQualquerPermissao([
          'pode_gerenciar_participantes_evento',
          'pode_gerenciar_participantes',
        ]),
        // 🔒 AÇÕES SENSÍVEIS: checagem direta.
        // Não usa compatibilidade inversa, para "gerenciar participantes"
        // não virar automaticamente "adicionar/remover/editar".
        _permissaoService.temQualquerPermissaoDireta([
          'pode_adicionar_participante_evento',
          'pode_adcionar_aluno_a_eventos',
          'pode_adicionar_aluno_a_eventos',
        ]),
        _permissaoService.temQualquerPermissaoDireta([
          'pode_editar_participacao_evento',
          'pode_editar_participante_evento',
        ]),
        _permissaoService.temQualquerPermissaoDireta([
          'pode_remover_participante_evento',
          'pode_remover_alunos_de_eventos',
        ]),
        _permissaoService.temQualquerPermissaoDireta([
          'pode_concluir_participacao_evento',
        ]),
        _permissaoService.temQualquerPermissao([
          'pode_gerar_certificados_evento',
          'pode_gerar_certificados',
        ]),
        _permissaoService.temQualquerPermissao([
          'pode_ver_relatorio_evento',
          'pode_ver_relatorios',
          'pode_visualizar_relatorios',
        ]),
      ]);

      if (!mounted) return;

      setState(() {
        _podeGerenciarParticipantes = permissoes[0] ||
            permissoes[1] ||
            permissoes[2] ||
            permissoes[3] ||
            permissoes[4];
        _podeAdicionar = permissoes[1];
        _podeEditarParticipacao = permissoes[2];
        _podeRemover = permissoes[3];
        _podeConcluirParticipacao = permissoes[4];
        _podeGerarCertificados = permissoes[5];
        _podeExportarListas = permissoes[5] || permissoes[6];
        _carregandoPermissoes = false;
      });

      debugPrint('🔐 Permissões participantes: '
          'gerenciar=$_podeGerenciarParticipantes | '
          'adicionar=$_podeAdicionar | '
          'editar=$_podeEditarParticipacao | '
          'remover=$_podeRemover | '
          'concluir=$_podeConcluirParticipacao | '
          'certificados=$_podeGerarCertificados | '
          'exportar=$_podeExportarListas');
    } catch (e) {
      debugPrint('Erro ao verificar permissões dos participantes: $e');
      if (!mounted) return;
      setState(() => _carregandoPermissoes = false);
    }
  }

  Future<void> _carregarPatrocinios() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('patrocinadores_eventos')
          .where('evento_id', isEqualTo: widget.eventoId)
          .get();
      final usos = <Map<String, dynamic>>[];
      for (var doc in snap.docs) {
        final sub = await doc.reference.collection('usos').orderBy('data', descending: true).get();
        for (var uso in sub.docs) {
          usos.add({
            'aluno_nome': uso.data()['aluno_nome'],
            'valor': (uso.data()['valor'] as num?)?.toDouble() ?? 0,
          });
        }
      }
      setState(() {
        _usosPatrocinio = usos;
        _participantesPatrocinados = usos.map((u) => u['aluno_nome'] as String).toSet();
      });
    } catch (e) { debugPrint('Erro patrocínios: $e'); }
  }

  Future<void> _carregarGraduacoes() async {
    final grad = await _graduacaoService.buscarTodasGraduacoes();
    setState(() {
      _graduacoes = grad;
      _coresGraduacao.clear();
      for (var g in grad) {
        final id = g['id'] as String?;
        if (id != null) {
          _coresGraduacao[id] = {
            'hex_cor1': (g['hex_cor1'] as String?) ?? '',
            'hex_cor2': (g['hex_cor2'] as String?) ?? '',
          };
        }
      }
    });
  }

  Future<void> _carregarParticipantesExistentes() async {
    try {
      final participantes = await _participacaoService.listarParticipantesEmAndamento(widget.eventoId);
      setState(() => _alunosParticipantesIds = participantes.map((p) => p['aluno_id'] as String).toList());
    } catch (e) { debugPrint('Erro ao listar participantes: $e'); }
  }

  Future<Map<String, dynamic>> _buscarDadosAluno(String alunoId) async {
    final cached = _cacheAlunos[alunoId];
    if (cached != null && !cached.isExpired) return cached.data;
    try {
      final doc = await FirebaseFirestore.instance.collection('alunos').doc(alunoId).get();
      if (doc.exists) {
        final data = doc.data()!;
        final dados = {
          'nome': data['nome'] ?? '',
          'foto': data['foto_perfil_aluno'] as String?,
          'graduacao': data['graduacao_atual'] ?? '',
          'turma': data['turma'] as String?,
          'data_nascimento': data['data_nascimento'],
        };
        _cacheAlunos[alunoId] = CachedAlunoData(dados);
        return dados;
      }
    } catch (e) { debugPrint('Erro ao buscar aluno $alunoId: $e'); }
    return {'nome': '', 'foto': null, 'graduacao': '', 'turma': null, 'data_nascimento': null};
  }

  int? _calcularIdade(dynamic dataNascimento) {
    if (dataNascimento == null) return null;
    DateTime nasc;
    if (dataNascimento is Timestamp) {
      nasc = dataNascimento.toDate();
    } else if (dataNascimento is DateTime) {
      nasc = dataNascimento;
    } else {
      return null;
    }
    final hoje = DateTime.now();
    int idade = hoje.year - nasc.year;
    if (hoje.month < nasc.month || (hoje.month == nasc.month && hoje.day < nasc.day)) idade--;
    return idade;
  }

  Future<void> _limparCacheERecarregar() async {
    setState(() {
      _cacheAlunos.clear();
      _assinaturaEstatisticas = '';
      _isRefreshing = true;
    });

    await Future.wait([
      _carregarParticipantesExistentes(),
      _verificarPermissoes(),
    ]);

    await _carregarAlunos();

    if (!mounted) return;
    setState(() => _isRefreshing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Lista e permissões atualizadas!'),
        backgroundColor: context.uai.success,
      ),
    );
  }

  void _calcularEstatisticas(List<ParticipacaoModel> participantes) {
    final assinatura = participantes
        .map((p) => '${p.id}|${p.totalPago}|${p.valorTotal}|${p.tamanhoCamisa}|${p.estaQuitado}')
        .join(';');

    if (_assinaturaEstatisticas == assinatura) return;

    double arrecadado = 0, inscricoes = 0;
    int pagos = 0;
    Map<String, int> camisasPorTamanho = {};

    for (var p in participantes) {
      arrecadado += p.totalPago;
      inscricoes += p.valorTotal;
      if (p.estaQuitado) pagos++;
      if (p.tamanhoCamisa != null && p.tamanhoCamisa!.isNotEmpty) {
        camisasPorTamanho[p.tamanhoCamisa!] = (camisasPorTamanho[p.tamanhoCamisa!] ?? 0) + 1;
      }
    }

    if (!mounted) return;
    setState(() {
      _totalArrecadado = arrecadado;
      _totalInscricoes = inscricoes;
      _totalParticipantes = participantes.length;
      _participantesPagos = pagos;
      _camisasPorTamanho = Map.from(camisasPorTamanho);
      _ultimoTotalParticipantes = participantes.length;
      _assinaturaEstatisticas = assinatura;
    });
  }

  // ==================== DASHBOARD (apenas grade) ====================
  Widget _buildDashboard() {
    final saldoDevedor = _totalInscricoes - _totalArrecadado;
    final inadimplentes =
    (_totalParticipantes - _participantesPagos).clamp(0, _totalParticipantes);
    final percentualPago = _totalParticipantes > 0
        ? (_participantesPagos / _totalParticipantes * 100).toStringAsFixed(1)
        : '0';
    final evento = widget.evento ?? _eventoCarregado;
    final temCamisa = evento?.temCamisa ?? false;

    return Container(
      margin: EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(context.uai.cardRadius),
        border: Border.all(color: context.uai.border),
        boxShadow: context.uai.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _dashboardIconBox(Icons.analytics_rounded, context.uai.primary),
              SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumo dos participantes',
                      style: TextStyle(
                        color: _onCard(),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Pagamentos, pendências e camisas do evento.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _onCardMuted(),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: context.uai.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: context.uai.primary.withOpacity(0.18)),
                ),
                child: Text(
                  '$percentualPago%',
                  style: TextStyle(
                    color: _ensureVisible(context.uai.primary, context.uai.card),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 430 ? 2 : 4;
              const spacing = 10.0;
              final itemWidth =
                  (constraints.maxWidth - (spacing * (columns - 1))) / columns;

              final items = [
                _DashboardMiniData(
                  Icons.people_rounded,
                  '$_totalParticipantes',
                  'Total',
                  context.uai.info,
                ),
                _DashboardMiniData(
                  Icons.paid_rounded,
                  '$_participantesPagos',
                  'Pagos',
                  context.uai.success,
                ),
                _DashboardMiniData(
                  Icons.warning_amber_rounded,
                  '$inadimplentes',
                  'Pendentes',
                  context.uai.warning,
                ),
                _DashboardMiniData(
                  Icons.percent_rounded,
                  '$percentualPago%',
                  'Taxa',
                  context.uai.primary,
                ),
              ];

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: items
                    .map(
                      (item) => SizedBox(
                    width: itemWidth,
                    child: _dashboardMiniCard(
                      icon: item.icon,
                      value: item.value,
                      label: item.label,
                      color: item.color,
                    ),
                  ),
                )
                    .toList(),
              );
            },
          ),
          SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 480;
              final children = [
                _financeCard(
                  icon: Icons.attach_money_rounded,
                  label: 'Arrecadado',
                  value: 'R\$ ${_totalArrecadado.toStringAsFixed(2)}',
                  color: context.uai.success,
                ),
                _financeCard(
                  icon: Icons.trending_down_rounded,
                  label: 'A receber',
                  value: 'R\$ ${saldoDevedor.toStringAsFixed(2)}',
                  color: context.uai.error,
                ),
              ];

              if (wide) {
                return Row(
                  children: [
                    Expanded(child: children[0]),
                    SizedBox(width: 10),
                    Expanded(child: children[1]),
                  ],
                );
              }

              return Column(
                children: [
                  children[0],
                  SizedBox(height: 10),
                  children[1],
                ],
              );
            },
          ),
          if (temCamisa && _camisasPorTamanho.isNotEmpty) ...[
            SizedBox(height: 13),
            Divider(color: context.uai.border, height: 1),
            SizedBox(height: 12),
            Row(
              children: [
                _dashboardIconBox(Icons.shopping_bag_rounded, context.uai.warning, compact: true),
                SizedBox(width: 9),
                Text(
                  'Camisas:',
                  style: TextStyle(
                    color: _onCard(),
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _camisasPorTamanho.entries.map((e) {
                        final accent = _ensureVisible(context.uai.warning, context.uai.card);

                        return Container(
                          margin: EdgeInsets.only(right: 8),
                          padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: accent.withOpacity(0.18)),
                          ),
                          child: Text(
                            '${e.key}: ${e.value}',
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w900,
                              fontSize: 11.5,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _dashboardIconBox(IconData icon, Color color, {bool compact = false}) {
    final accent = _ensureVisible(color, context.uai.card);
    final size = compact ? 34.0 : 42.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(compact ? 12 : 15),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Icon(icon, color: accent, size: compact ? 18 : 22),
    );
  }

  Widget _dashboardMiniCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    final accent = _ensureVisible(color, context.uai.card);

    return Container(
      constraints: BoxConstraints(minHeight: 92),
      padding: EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), context.uai.cardAlt),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: accent, size: 22),
          SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ),
          SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _onCardMuted(),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _financeCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final accent = _ensureVisible(color, context.uai.card);

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), context.uai.cardAlt),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          _dashboardIconBox(icon, accent, compact: true),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 15.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: _onCardMuted(),
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== CARREGAR ALUNOS ====================
  Future<void> _carregarAlunos() async {
    setState(() => _isLoadingAlunos = true);
    try {
      final gradList = await _graduacaoService.buscarTodasGraduacoes();
      final Map<String, Map<String, dynamic>> mapaGrad = {for (var g in gradList) g['id']: g};
      final snap = await FirebaseFirestore.instance
          .collection('alunos')
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get();
      final alunos = snap.docs
          .where((doc) => !_alunosParticipantesIds.contains(doc.id))
          .map((doc) {
        final data = doc.data();
        final gradId = data['graduacao_atual_id'] ?? '';
        final gradInfo = mapaGrad[gradId];
        String tipoPublico = 'ADULTO';
        int nivel = data['nivel_graduacao'] ?? 0;
        if (gradInfo != null) {
          tipoPublico = gradInfo['tipo_publico'] ?? 'ADULTO';
          nivel = gradInfo['nivel_graduacao'] ?? nivel;
        } else {
          final gradTexto = data['graduacao_atual'] ?? '';
          if (gradTexto.contains('INFANTIL')) tipoPublico = 'INFANTIL';
        }
        return {
          'id': doc.id,
          'nome': data['nome'] ?? '',
          'foto': data['foto_perfil_aluno'] as String?,
          'graduacao': data['graduacao_atual'] ?? '',
          'graduacao_id': gradId,
          'nivel_graduacao': nivel,
          'tipo_publico': tipoPublico,
          'turma': data['turma'] as String?,
          'data_nascimento': data['data_nascimento'],
        };
      })
          .toList()
        ..sort((a, b) => (a['nome'] as String).compareTo(b['nome'] as String));

      setState(() => _alunosDisponiveis = alunos);
    } catch (e) {
      debugPrint('❌ Erro ao carregar alunos: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: context.uai.error));
    } finally {
      if (mounted) setState(() => _isLoadingAlunos = false);
    }
  }

  // ==================== ADICIONAR / REMOVER ====================
  Future<void> _mostrarModalAdicionar(Map<String, dynamic> aluno) async {
    if (!_podeAdicionar) {
      _mostrarSemPermissao('Você não tem permissão para adicionar participantes.');
      return;
    }

    final evento = widget.evento ?? _eventoCarregado;
    if (evento == null) return;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => AdicionarParticipanteModal(aluno: aluno, evento: evento, isBatizado: _isBatizado),
    );
    if (result != null) {
      await _adicionarParticipante(aluno,
          tamanhoCamisa: result['tamanhoCamisa'],
          novaGraduacao: result['graduacao']?['nome_graduacao'],
          novaGraduacaoId: result['graduacaoId']);
    }
  }

  Future<void> _adicionarParticipante(Map<String, dynamic> aluno,
      {String? tamanhoCamisa, String? novaGraduacao, String? novaGraduacaoId}) async {
    if (!_podeAdicionar) { _mostrarSemPermissao('Você não tem permissão para adicionar participantes.'); return; }
    try {
      final evento = widget.evento ?? _eventoCarregado;
      await _participacaoService.adicionarParticipante(
        alunoId: aluno['id'], alunoNome: aluno['nome'], alunoFoto: aluno['foto'],
        eventoId: widget.eventoId, eventoNome: widget.eventoNome,
        dataEvento: evento?.data ?? DateTime.now(), tipoEvento: evento?.tipo ?? 'EVENTO',
        graduacao: aluno['graduacao'], graduacaoId: aluno['nivel_graduacao'].toString(),
        tamanhoCamisa: tamanhoCamisa, status: 'pendente',
        graduacaoNova: novaGraduacao, graduacaoNovaId: novaGraduacaoId,
        valorInscricao: evento?.valorInscricao ?? 0,
        valorCamisa: evento?.temCamisa == true ? (evento?.valorCamisa ?? 0) : 0,
      );
      setState(() {
        _alunosParticipantesIds.add(aluno['id']);
        _alunosDisponiveis.removeWhere((a) => a['id'] == aluno['id']);
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isBatizado && novaGraduacao != null
            ? '✅ ${aluno['nome']} será graduado para $novaGraduacao!'
            : '✅ ${aluno['nome']} adicionado!'),
        backgroundColor: context.uai.success,
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: context.uai.error));
    }
  }

  Future<void> _removerParticipante(String id, String nome, String alunoId) async {
    if (!_podeRemover) { _mostrarSemPermissao('Você não tem permissão para remover participantes.'); return; }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover Participante'),
        content: Text('Remover $nome do evento?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('REMOVER')),
        ],
      ),
    );
    if (confirm == true) {
      await _participacaoService.removerParticipante(id);
      _cacheAlunos.remove(alunoId);
      setState(() { _alunosParticipantesIds.remove(alunoId); _carregarAlunos(); });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🗑️ $nome removido!'), backgroundColor: context.uai.warning));
    }
  }

  void _mostrarSemPermissao([String mensagem = 'Sem permissão']) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: context.uai.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _abrirDetalhe(ParticipacaoModel p) {
    final podeAbrirDetalhe = _podeEditarParticipacao ||
        _podeConcluirParticipacao ||
        _podeGerarCertificados;

    if (!podeAbrirDetalhe) {
      _mostrarSemPermissao(
        'Você não tem permissão para abrir/editar detalhes da participação.',
      );
      return;
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => DetalheParticipacaoScreen(
      participacao: p.toMap(),
      participacaoId: p.id!,
      eventoId: widget.eventoId,
    )));
  }

  String _formatarValorResumido(double valor) =>
      valor >= 100 ? 'R\$${valor.toStringAsFixed(0)}' : 'R\$${valor.toStringAsFixed(2)}';

  // ==================== FILTROS ====================
  List<ParticipacaoModel> _aplicarFiltros(List<ParticipacaoModel> lista) {
    final Map<String, String> idParaNome = {};
    for (var g in _graduacoes) {
      idParaNome[g['id'] as String] = g['nome_graduacao'] as String? ?? '';
    }

    return lista.where((p) {
      // Pesquisa de participantes removida a pedido.
      // Mantém apenas filtros por status, pagamento, graduação e camisa.
      if (_filtroStatus == 'pagos' && !p.estaQuitado) return false;
      if (_filtroStatus == 'pendentes' && p.estaQuitado) return false;

      if (_filtroStatusPagamento.isNotEmpty) {
        if (_filtroStatusPagamento.contains('quitado') && !p.estaQuitado) return false;
        if (_filtroStatusPagamento.contains('pendente') && p.estaQuitado) return false;
        if (_filtroStatusPagamento.contains('patrocinado') &&
            !_participantesPatrocinados.contains(p.alunoNome)) return false;
      }

      if (_filtroGraduacaoId != null && _filtroGraduacaoId!.isNotEmpty) {
        final nomeGraduacaoFiltrada = idParaNome[_filtroGraduacaoId!] ?? '';
        if (nomeGraduacaoFiltrada.isNotEmpty &&
            p.graduacao != nomeGraduacaoFiltrada &&
            p.graduacaoNova != nomeGraduacaoFiltrada) return false;
      }

      if (_filtroStatusCamisa != null) {
        final temCamisa = p.tamanhoCamisa != null && p.tamanhoCamisa!.isNotEmpty;
        if (_filtroStatusCamisa == 'com' && !temCamisa) return false;
        if (_filtroStatusCamisa == 'sem' && temCamisa) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _mostrarFiltrosAvancados() async {
    Set<String> statusPagamento = Set<String>.from(_filtroStatusPagamento);
    String? graduacaoId = _filtroGraduacaoId;
    String? statusCamisa = _filtroStatusCamisa;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filtros Avançados', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  const Text('Status de Pagamento:'),
                  Wrap(spacing: 8, children: [
                    FilterChip(
                      label: const Text('Quitado'),
                      selected: statusPagamento.contains('quitado'),
                      onSelected: (v) => setSheetState(() => v ? statusPagamento.add('quitado') : statusPagamento.remove('quitado')),
                    ),
                    FilterChip(
                      label: const Text('Pendente'),
                      selected: statusPagamento.contains('pendente'),
                      onSelected: (v) => setSheetState(() => v ? statusPagamento.add('pendente') : statusPagamento.remove('pendente')),
                    ),
                    FilterChip(
                      label: const Text('Patrocinado'),
                      selected: statusPagamento.contains('patrocinado'),
                      onSelected: (v) => setSheetState(() => v ? statusPagamento.add('patrocinado') : statusPagamento.remove('patrocinado')),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  const Text('Graduação:'),
                  DropdownButtonFormField<String?>(
                    value: graduacaoId,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todas')),
                      ..._graduacoes.map((g) => DropdownMenuItem(value: g['id'], child: Text(g['nome_graduacao']))),
                    ],
                    onChanged: (v) => setSheetState(() => graduacaoId = v),
                  ),
                  const SizedBox(height: 16),
                  const Text('Camisa:'),
                  Wrap(spacing: 8, children: [
                    FilterChip(
                      label: const Text('Com camisa'),
                      selected: statusCamisa == 'com',
                      onSelected: (v) => setSheetState(() => statusCamisa = v ? 'com' : null),
                    ),
                    FilterChip(
                      label: const Text('Sem camisa'),
                      selected: statusCamisa == 'sem',
                      onSelected: (v) => setSheetState(() => statusCamisa = v ? 'sem' : null),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => setSheetState(() {
                          statusPagamento.clear();
                          graduacaoId = null;
                          statusCamisa = null;
                        }),
                        child: const Text('Limpar tudo'),
                      ),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _filtroStatusPagamento = statusPagamento;
                            _filtroGraduacaoId = graduacaoId;
                            _filtroStatusCamisa = statusCamisa;
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('Aplicar filtros'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ==================== WIDGETS DE APOIO ====================
  Widget _buildViewModeButton(IconData icon, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? context.uai.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: isSelected ? _readableOn(context.uai.primary) : context.uai.textSecondary, size: 20),
      ),
    );
  }

  Widget _buildViewModeRow() {
    return Container(
      decoration: BoxDecoration(color: context.uai.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.uai.border)),
      child: Row(
        children: [
          _buildViewModeButton(Icons.grid_view, _viewMode == 0, () => setState(() => _viewMode = 0)),
          _buildViewModeButton(Icons.list, _viewMode == 1, () => setState(() => _viewMode = 1)),
          _buildViewModeButton(Icons.table_chart, _viewMode == 2, () => setState(() => _viewMode = 2)),
        ],
      ),
    );
  }

  Widget _buildFiltroChip(String label, String valor) {
    final selected = _filtroStatus == valor;
    final accent = _ensureVisible(context.uai.primary, context.uai.card);

    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (v) => setState(() => _filtroStatus = v ? valor : 'todos'),
      backgroundColor: context.uai.card,
      selectedColor: accent.withOpacity(0.14),
      checkmarkColor: accent,
      side: BorderSide(color: selected ? accent.withOpacity(0.55) : context.uai.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      labelStyle: TextStyle(
        color: selected ? accent : context.uai.textSecondary,
        fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
      ),
    );
  }

  // ==================== CORES DAS BORDAS ====================
  Color _statusBorderColor(ParticipacaoModel p) {
    if (_participantesPatrocinados.contains(p.alunoNome)) return context.uai.associacao;
    return p.estaQuitado ? context.uai.success : context.uai.warning;
  }

  // ==================== CARDS COM BORDAS COLORIDAS ====================
  Widget _buildParticipantCardGrade(ParticipacaoModel p) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _buscarDadosAluno(p.alunoId),
      builder: (_, snap) {
        final dados = snap.data;
        final fotoUrl = dados?['foto'];
        final nome = dados?['nome'] ?? p.alunoNome;
        final grad = dados?['graduacao'] ?? p.graduacao;
        final borderColor = _statusBorderColor(p);

        return Card(
          color: context.uai.card,
          surfaceTintColor: Colors.transparent,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: borderColor.withOpacity(0.6), width: 2),
          ),
          child: InkWell(
            onTap: () => _abrirDetalhe(p),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        RobustAvatar(fotoUrl: fotoUrl, radius: 32, borderColor: borderColor),
                        if (p.aguardandoFinalizacao)
                          Positioned(
                            bottom: -2,
                            right: -2,
                            child: Container(
                              padding: EdgeInsets.all(4),
                              decoration: BoxDecoration(color: context.uai.warning, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                              child: Icon(Icons.access_time, color: Colors.white, size: 10),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(nome.split(' ').first, style: TextStyle(color: _onCard(), fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 2),
                    _gradChip(grad, p.graduacaoNova),
                    const SizedBox(height: 4),
                    _statusBadge(p),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _graduacaoFluxoLista(String gradAtualAluno, ParticipacaoModel p) {
    final antiga = gradAtualAluno.trim().isNotEmpty
        ? gradAtualAluno.trim()
        : (p.graduacao ?? '').trim();
    final nova = (p.graduacaoNova ?? '').trim();

    if (nova.isEmpty || nova == antiga) {
      return _gradChip(antiga, null);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _gradChip(antiga, null),
          SizedBox(width: 5),
          Icon(Icons.arrow_forward_rounded, size: 13, color: context.uai.textMuted),
          SizedBox(width: 5),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: context.uai.success.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.uai.success.withOpacity(0.18)),
            ),
            child: Text(
              nova,
              style: TextStyle(
                fontSize: 10.5,
                color: context.uai.success,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantCardLista(ParticipacaoModel p) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _buscarDadosAluno(p.alunoId),
      builder: (_, snap) {
        final dados = snap.data;
        final fotoUrl = dados?['foto'];
        final nome = dados?['nome'] ?? p.alunoNome;
        final grad = dados?['graduacao'] ?? p.graduacao;
        final turma = dados?['turma'];
        final idade = _calcularIdade(dados?['data_nascimento']);
        final borderColor = _statusBorderColor(p);

        return Container(
          margin: EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: context.uai.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor.withOpacity(0.6), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: InkWell(
            onTap: () => _abrirDetalhe(p),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 8, 10),
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        children: [
                          RobustAvatar(fotoUrl: fotoUrl, radius: 30, borderColor: borderColor),
                          if (p.aguardandoFinalizacao)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: context.uai.warning,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: Icon(Icons.access_time, color: Colors.white, size: 12),
                              ),
                            ),
                        ],
                      ),
                      if (idade != null)
                        Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            '$idade anos',
                            style: TextStyle(
                              fontSize: 10,
                              color: context.uai.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: constraints.maxWidth,
                              height: 20,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  nome,
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: _onCard(),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            _graduacaoFluxoLista(grad, p),
                            const SizedBox(height: 7),
                            _infoRow(p, turma),
                          ],
                        );
                      },
                    ),
                  ),
                  SizedBox(width: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_podeRemover)
                        IconButton(
                          tooltip: 'Remover',
                          constraints: BoxConstraints(minWidth: 34, minHeight: 34),
                          padding: EdgeInsets.zero,
                          icon: Icon(Icons.delete_outline_rounded, color: context.uai.error, size: 20),
                          onPressed: () => _removerParticipante(p.id!, p.alunoNome, p.alunoId),
                        ),
                      Icon(Icons.chevron_right, color: context.uai.primary, size: 22),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _gradChip(String gradAtual, String? gradNova) {
    final texto = gradNova != null
        ? gradNova.split(' ').take(2).join(' ')
        : gradAtual.split(' ').take(2).join(' ');
    final accent = _ensureVisible(context.uai.primary, context.uai.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Text(
        texto,
        style: TextStyle(fontSize: 9, color: accent, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _statusBadge(ParticipacaoModel p) {
    final isPaid = p.estaQuitado;
    final accent = _ensureVisible(isPaid ? context.uai.success : context.uai.warning, context.uai.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isPaid ? Icons.check_circle : Icons.hourglass_empty, size: 10, color: accent),
          const SizedBox(width: 2),
          Text(
            isPaid ? 'Pago' : 'R\$ ${p.saldoDevedor.toStringAsFixed(0)}',
            style: TextStyle(fontSize: 8, color: accent, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(ParticipacaoModel p, String? turma) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _statusBadge(p),
        if (turma != null && turma.isNotEmpty) ...[
          SizedBox(width: 8),
          _chip(Icons.class_, context.uai.associacao, turma),
        ],
        if (p.tamanhoCamisa != null) ...[
          SizedBox(width: 8),
          _chip(Icons.shopping_bag, context.uai.info, p.tamanhoCamisa!),
        ],
      ]),
    );
  }

  Widget _chip(IconData icon, Color color, String label) {
    final accent = _ensureVisible(color, context.uai.card);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: accent),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  // ==================== PLANILHA COM SCROLL VERTICAL E HORIZONTAL ====================
  Widget _buildPlanilhaView(List<ParticipacaoModel> participantes) {
    final filtrados = _aplicarFiltros(participantes);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Row(
            children: [
              _buildViewModeRow(),
              const Spacer(),
              if (_podeExportarListas)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.download),
                  tooltip: 'Exportar PDFs',
                  onSelected: (v) => _exportarPdf(v, participantes),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'lista', child: Text('📋 PDF Lista Participantes')),
                    PopupMenuItem(value: 'conferencia', child: Text('📋 PDF Conferência de Nomes')),
                    PopupMenuItem(value: 'completa', child: Text('📋 PDF Lista Completa')),
                  ],
                ),
            ],
          ),
          SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Card(
                  color: context.uai.card,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: context.uai.border),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: constraints.maxHeight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 16,
                          columns: const [
                            DataColumn(label: Text('Nome', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Camisa', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Valor Pago', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Graduação', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('')),
                          ],
                          rows: filtrados.map((p) {
                            final borderColor = _statusBorderColor(p);
                            return DataRow(
                              onSelectChanged: (_) => _abrirDetalhe(p),
                              cells: [
                                DataCell(Row(children: [
                                  Container(width: 4, height: 24, decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2))),
                                  const SizedBox(width: 8),
                                  Text(p.alunoNome),
                                ])),
                                DataCell(_statusChip(p)),
                                DataCell(Text(p.tamanhoCamisa ?? '---')),
                                DataCell(Text(NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(p.totalPago))),
                                DataCell(Text(p.graduacaoNova ?? p.graduacao ?? '---')),
                                const DataCell(Icon(Icons.chevron_right)),
                              ],
                            );
                          }).toList(),
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
    );
  }

  Widget _statusChip(ParticipacaoModel p) {
    if (_participantesPatrocinados.contains(p.alunoNome)) return _miniChip('Patrocinado', context.uai.associacao);
    if (p.estaQuitado) return _miniChip('Quitado', context.uai.success);
    return _miniChip('Pendente', context.uai.warning);
  }

  Widget _miniChip(String label, Color color) {
    final accent = _ensureVisible(color, context.uai.card);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Text(label, style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

  // ==================== GRID COM DASHBOARD ROLANDO + FILTRO FIXO ====================
  Widget _buildGridView(List<ParticipacaoModel> participantes) {
    final filtrados = _aplicarFiltros(participantes);

    return CustomScrollView(
      key: const PageStorageKey('participantes_grid_custom_scroll_view'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      slivers: [
        SliverToBoxAdapter(child: _buildDashboard()),
        SliverPersistentHeader(
          pinned: true,
          delegate: _StickyHeaderDelegate(
            height: 74,
            child: _buildParticipantesFilterHeader(
              totalFiltrado: filtrados.length,
              totalGeral: participantes.length,
            ),
          ),
        ),
        if (filtrados.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_outline_rounded,
                      size: 62,
                      color: context.uai.textMuted,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Nenhum participante nesse filtro',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.uai.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Altere o filtro para visualizar outros participantes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.uai.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.75,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _buildParticipantCardGrade(filtrados[i]),
                childCount: filtrados.length,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
      ],
    );
  }

  Widget _buildParticipantesFilterHeader({
    required int totalFiltrado,
    required int totalGeral,
  }) {
    final primary = _ensureVisible(context.uai.primary, context.uai.surface);

    return Container(
      key: const ValueKey('participantes_filter_header_sticky'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: context.uai.surface,
        border: Border(
          top: BorderSide(color: context.uai.border),
          bottom: BorderSide(color: context.uai.border),
        ),
        boxShadow: context.uai.softShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              child: Row(
                children: [
                  _buildFiltroChip('TODOS', 'todos'),
                  const SizedBox(width: 8),
                  _buildFiltroChip('💰 PAGOS', 'pagos'),
                  const SizedBox(width: 8),
                  _buildFiltroChip('⏳ PENDENTES', 'pendentes'),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: primary.withOpacity(0.14)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people_alt_rounded,
                          size: 14,
                          color: primary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '$totalFiltrado/$totalGeral',
                          style: TextStyle(
                            color: primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildViewModeRow(),
        ],
      ),
    );
  }

  // ==================== LIST SEM DASHBOARD ====================
  Widget _buildListView(List<ParticipacaoModel> participantes) {
    final filtrados = _aplicarFiltros(participantes);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Text('${filtrados.length} participantes', style: TextStyle(color: context.uai.textSecondary, fontSize: 12)),
              const Spacer(),
              _buildViewModeRow(),
            ],
          ),
          SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              itemCount: filtrados.length + 1,
              itemBuilder: (ctx, i) {
                if (i == filtrados.length) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('🔹 MAIS PARTICIPANTES...',
                          style: TextStyle(color: context.uai.error, fontWeight: FontWeight.w600)),
                    ),
                  );
                }
                return _buildParticipantCardLista(filtrados[i]);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==================== BUILD PRINCIPAL ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text(
          '${widget.eventoNome} - Participantes',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        backgroundColor: _appBarBg(),
        foregroundColor: _appBarFg(),
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _limparCacheERecarregar,
            tooltip: 'Atualizar lista',
          ),
          if (_podeExportarListas)
            IconButton(
              icon: Icon(Icons.table_chart),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SelecionarParticipantesCsvScreen(
                  eventoId: widget.eventoId,
                  eventoNome: widget.eventoNome,
                )),
              ),
              tooltip: 'Selecionar para CSV',
            ),
        ],
        bottom: _podeAdicionar
            ? TabBar(
          controller: _tabController,
          labelColor: _appBarFg(),
          unselectedLabelColor: _appBarFg().withOpacity(0.66),
          indicatorColor: _appBarFg(),
          tabs: const [
            Tab(text: 'PARTICIPANTES', icon: Icon(Icons.people)),
            Tab(text: 'ADICIONAR', icon: Icon(Icons.person_add)),
          ],
        )
            : null,
      ),
      body: _podeAdicionar
          ? TabBarView(
        controller: _tabController,
        children: [
          _buildParticipantesList(),
          _buildAdicionarParticipantes(),
        ],
      )
          : _buildParticipantesList(),
    );
  }

  Widget _buildParticipantesList() {
    return RefreshIndicator(
      onRefresh: _limparCacheERecarregar,
      color: context.uai.primary,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('participacoes_eventos_em_andamento')
            .where('evento_id', isEqualTo: widget.eventoId)
            .orderBy('aluno_nome')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 60, color: context.uai.error.withOpacity(0.50)),
                  const SizedBox(height: 16),
                  Text('Erro: ${snapshot.error}'),
                  ElevatedButton(onPressed: _limparCacheERecarregar, child: const Text('Tentar novamente')),
                ],
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: context.uai.primary));
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 60, color: context.uai.border),
                  SizedBox(height: 16),
                  Text('Nenhum participante ainda', style: TextStyle(fontSize: 16, color: context.uai.textMuted)),
                  SizedBox(height: 8),
                  Text(
                    _podeAdicionar
                        ? 'Adicione participantes na aba "ADICIONAR"'
                        : 'Nenhum participante cadastrado ainda',
                    style: TextStyle(fontSize: 14, color: context.uai.textMuted),
                  ),
                ],
              ),
            );
          }

          final participantes = docs
              .map((doc) => ParticipacaoModel.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>))
              .toList();
          _allParticipants = participantes;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _calcularEstatisticas(participantes);
          });

          return Column(
            children: [
              if (_viewMode == 2)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Row(
                    children: [
                      const Spacer(),
                      IconButton(
                        tooltip: 'Filtros avançados',
                        icon: Icon(
                          Icons.filter_alt_rounded,
                          color: _filtroStatusPagamento.isNotEmpty ||
                              _filtroGraduacaoId != null ||
                              _filtroStatusCamisa != null
                              ? context.uai.primary
                              : context.uai.textMuted,
                        ),
                        onPressed: _mostrarFiltrosAvancados,
                      ),
                    ],
                  ),
                ),
              if (_viewMode == 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _buildFiltroChip('TODOS', 'todos'), const SizedBox(width: 8),
                      _buildFiltroChip('💰 PAGOS', 'pagos'), const SizedBox(width: 8),
                      _buildFiltroChip('⏳ PENDENTES', 'pendentes'),
                    ]),
                  ),
                ),
              Expanded(
                child: _viewMode == 0
                    ? _buildGridView(participantes)
                    : _viewMode == 1
                    ? _buildListView(participantes)
                    : _buildPlanilhaView(participantes),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==================== ABA ADICIONAR ====================
  Widget _buildAdicionarParticipantes() {
    if (!_podeAdicionar) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock, size: 60, color: context.uai.textMuted),
            SizedBox(height: 16),
            Text(
              'Você não tem permissão para adicionar participantes',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.uai.textSecondary),
            ),
            SizedBox(height: 8),
            Text(
              'Peça para o administrador liberar “Adicionar participante” nas permissões do evento.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.uai.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final alunosFiltrados = _alunosDisponiveis
        .where((aluno) => _searchQuery.isEmpty || aluno['nome'].toLowerCase().contains(_searchQuery))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: _buildSearchField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            hint: 'Buscar alunos...',
            hasValue: _searchQuery.isNotEmpty,
            onChanged: _onSearchAlunosChanged,
            onClear: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
              _searchFocusNode.requestFocus();
            },
          ),
        ),
        Expanded(
          child: _isLoadingAlunos
              ? Center(child: CircularProgressIndicator(color: context.uai.primary))
              : _alunosDisponiveis.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 60, color: context.uai.border),
                SizedBox(height: 16),
                Text('Nenhum aluno disponível', style: TextStyle(fontSize: 16, color: context.uai.textMuted)),
                SizedBox(height: 8),
                Text('Todos os alunos já estão participando!', style: TextStyle(fontSize: 14, color: context.uai.textMuted)),
              ],
            ),
          )
              : alunosFiltrados.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 60, color: context.uai.textMuted),
                SizedBox(height: 16),
                Text('Nenhum aluno encontrado para "$_searchQuery"', style: TextStyle(color: context.uai.textSecondary, fontSize: 16)),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.clear),
                  label: const Text('Limpar busca'),
                ),
              ],
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: alunosFiltrados.length,
            itemBuilder: (context, index) {
              final aluno = alunosFiltrados[index];
              final idade = _calcularIdade(aluno['data_nascimento']);
              return Card(
                color: context.uai.card,
                surfaceTintColor: Colors.transparent,
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  onTap: () => _mostrarModalAdicionar(aluno),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      children: [
                        RobustAvatar(fotoUrl: aluno['foto'], radius: 28),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(aluno['nome'], style: TextStyle(color: _onCard(), fontWeight: FontWeight.bold, fontSize: 16)),
                              SizedBox(height: 4),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: context.uai.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
                                    child: Text(aluno['graduacao'], style: TextStyle(fontSize: 11, color: context.uai.error)),
                                  ),
                                  if (aluno['turma'] != null && aluno['turma'].toString().isNotEmpty)
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: context.uai.info.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
                                      child: Text(aluno['turma'], style: TextStyle(fontSize: 11, color: context.uai.info)),
                                    ),
                                  if (idade != null)
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: context.uai.success.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.cake, size: 12, color: context.uai.success),
                                          SizedBox(width: 4),
                                          Text('$idade anos', style: TextStyle(fontSize: 11, color: context.uai.success)),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          margin: EdgeInsets.only(left: 8),
                          child: ElevatedButton(
                            onPressed: () => _mostrarModalAdicionar(aluno),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.uai.primary,
                              foregroundColor: _readableOn(context.uai.primary),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add, size: 18),
                                SizedBox(width: 4),
                                Text('ADICIONAR'),
                              ],
                            ),
                          ),
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
    );
  }

  // ==================== EXPORTAÇÃO PDF ====================
  Future<Map<String, dynamic>?> _mostrarDialogoOrdenacao() async {
    String campoSelecionado = 'nome';
    bool crescente = true;

    const campos = {
      'nome': 'Nome',
      'status': 'Status',
      'camisa': 'Tamanho Camisa',
      'valor': 'Valor Pago',
      'graduacao': 'Graduação',
    };

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Ordenar lista'),
          content: StatefulBuilder(
            builder: (BuildContext context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: campoSelecionado,
                    decoration: const InputDecoration(labelText: 'Campo de ordenação'),
                    items: campos.entries.map((entry) {
                      return DropdownMenuItem(value: entry.key, child: Text(entry.value));
                    }).toList(),
                    onChanged: (value) => setState(() => campoSelecionado = value!),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Direção:'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ToggleButtons(
                          isSelected: [crescente, !crescente],
                          onPressed: (index) => setState(() => crescente = index == 0),
                          children: const [
                            Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Crescente')),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Decrescente')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {'campo': campoSelecionado, 'crescente': crescente}),
              child: const Text('Gerar PDF'),
            ),
          ],
        );
      },
    );
  }

  List<ParticipacaoModel> _ordenarParticipantes(List<ParticipacaoModel> lista, String campo, bool crescente) {
    final copia = List<ParticipacaoModel>.from(lista);
    copia.sort((a, b) {
      dynamic valA, valB;
      switch (campo) {
        case 'nome':
          valA = a.alunoNome;
          valB = b.alunoNome;
          break;
        case 'status':
          valA = _statusParaTexto(a);
          valB = _statusParaTexto(b);
          break;
        case 'camisa':
          valA = a.tamanhoCamisa ?? '';
          valB = b.tamanhoCamisa ?? '';
          break;
        case 'valor':
          valA = a.totalPago;
          valB = b.totalPago;
          break;
        case 'graduacao':
          valA = a.graduacaoNova ?? a.graduacao ?? '';
          valB = b.graduacaoNova ?? b.graduacao ?? '';
          break;
        default:
          return 0;
      }
      int cmp;
      if (valA is String && valB is String) {
        cmp = valA.compareTo(valB);
      } else if (valA is num && valB is num) {
        cmp = valA.compareTo(valB);
      } else {
        cmp = 0;
      }
      return crescente ? cmp : -cmp;
    });
    return copia;
  }

  String _statusParaTexto(ParticipacaoModel p) {
    if (_participantesPatrocinados.contains(p.alunoNome)) return 'Patrocinado';
    if (p.estaQuitado) return 'Quitado';
    return 'Inadimplente';
  }

  List<Map<String, dynamic>> _participantesParaExportacao(List<ParticipacaoModel> participantes) {
    return participantes.map((p) {
      final Map<String, dynamic> map = {
        'nome': p.alunoNome,
        'status': _statusParaTexto(p),
        'tamanho_camisa': p.tamanhoCamisa ?? '---',
        'valor_pago': p.totalPago,
        'graduacao_nova': p.graduacaoNova ?? p.graduacao ?? '---',
        'graduacao_nova_id': p.graduacaoNovaId ?? '',
        'hex_cor1': null,
        'hex_cor2': null,
      };
      final gId = p.graduacaoNovaId;
      if (gId != null && _coresGraduacao.containsKey(gId)) {
        map['hex_cor1'] = _coresGraduacao[gId]?['hex_cor1'];
        map['hex_cor2'] = _coresGraduacao[gId]?['hex_cor2'];
      }
      return map;
    }).toList();
  }

  Future<void> _exportarPdf(String tipo, List<ParticipacaoModel> todos) async {
    if (!_podeExportarListas) {
      _mostrarSemPermissao('Você não tem permissão para exportar listas/PDFs.');
      return;
    }

    final opcoes = await _mostrarDialogoOrdenacao();
    if (opcoes == null) return;

    final filtrados = _aplicarFiltros(todos);
    final ordenados = _ordenarParticipantes(filtrados, opcoes['campo'] as String, opcoes['crescente'] as bool);
    final mapa = _participantesParaExportacao(ordenados);

    try {
      switch (tipo) {
        case 'lista':
          await EventoFinanceiroPdfService.gerarPdfListaParticipantes(participantes: mapa, eventoNome: widget.eventoNome);
          break;
        case 'conferencia':
          await EventoFinanceiroPdfService.gerarPdfConferenciaNomes(participantes: mapa, eventoNome: widget.eventoNome);
          break;
        case 'completa':
          await EventoFinanceiroPdfService.gerarPdfListaCompleta(participantes: mapa, eventoNome: widget.eventoNome);
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao gerar PDF: $e'), backgroundColor: context.uai.error));
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchParticipantesController.dispose();
    _searchFocusNode.dispose();
    _searchParticipantesFocusNode.dispose();
    _debounceTimer?.cancel();
    _cacheAlunos.clear();
    super.dispose();
  }
}
