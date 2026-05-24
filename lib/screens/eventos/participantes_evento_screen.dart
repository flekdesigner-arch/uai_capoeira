import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../../models/evento_model.dart';
import '../../services/participacao_service.dart';
import '../../services/permissao_service.dart';
import '../../services/graduacao_service.dart';
import '../../services/certificado_service.dart';
import '../../models/participacao_model.dart';
import 'aluno_detalhe_participacao_screen.dart';
import 'adicionar_participante_modal.dart';
import 'selecionar_participantes_csv_screen.dart';
import '../relatorios/evento_financeiro_pdf_service.dart';

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
          return Icon(Icons.person, size: radius * 0.8, color: Colors.grey);
        },
      ),
    )
        : Icon(Icons.person, size: radius * 0.8, color: Colors.grey);

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: borderColor != null
            ? Border.all(color: borderColor!, width: 3)
            : null,
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey.shade100,
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
      elevation: 2,
      child: SizedBox(height: height, child: child),
    );
  }

  @override
  double get maxExtent => height;
  @override
  double get minExtent => height;
  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => true;
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

  bool _podeAdicionar = false;
  bool _podeRemover = false;
  bool _podeGerarCertificados = false;

  bool get _isBatizado {
    final tipo = (widget.evento ?? _eventoCarregado)?.tipo.toUpperCase() ?? '';
    return tipo.contains('BATIZADO');
  }

  // ==================== INICIALIZAÇÃO ====================
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _searchController.addListener(() {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _searchQuery = _searchController.text.toLowerCase());
      });
    });

    _searchParticipantesController.addListener(() {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _searchParticipantesQuery = _searchParticipantesController.text.toLowerCase());
      });
    });

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
    final permissoes = await _permissaoService.getTodasPermissoes();
    _podeAdicionar = permissoes['pode_adcionar_aluno_a_eventos'] ?? false;
    _podeRemover = permissoes['pode_remover_alunos_de_eventos'] ?? false;
    _podeGerarCertificados = permissoes['pode_gerar_certificados'] ?? false;
    if (mounted) setState(() {});
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
    setState(() { _cacheAlunos.clear(); _assinaturaEstatisticas = ''; _isRefreshing = true; });
    await _carregarParticipantesExistentes();
    await _carregarAlunos();
    setState(() => _isRefreshing = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Lista atualizada!'), backgroundColor: Colors.green));
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
    final inadimplentes = (_totalParticipantes - _participantesPagos).clamp(0, _totalParticipantes);
    final percentualPago = _totalParticipantes > 0
        ? (_participantesPagos / _totalParticipantes * 100).toStringAsFixed(1)
        : '0';
    final evento = widget.evento ?? _eventoCarregado;
    final temCamisa = evento?.temCamisa ?? false;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.red.shade900, Colors.red.shade700],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade200,
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _dashboardItem(Icons.people, '$_totalParticipantes', 'Total')),
              _vDivider(),
              Expanded(child: _dashboardItem(Icons.paid, '$_participantesPagos', 'Pagos')),
              _vDivider(),
              Expanded(child: _dashboardItem(Icons.warning_amber_rounded, '$inadimplentes', 'Pendentes')),
              _vDivider(),
              Expanded(child: _dashboardItem(Icons.percent, '$percentualPago%', 'Taxa')),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: Colors.white.withOpacity(0.3)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _dashboardItem(Icons.attach_money, 'R\$ ${_totalArrecadado.toStringAsFixed(2)}', 'Arrecadado')),
              _vDivider(),
              Expanded(child: _dashboardItem(Icons.warning, 'R\$ ${saldoDevedor.toStringAsFixed(2)}', 'A Receber')),
            ],
          ),
          if (temCamisa && _camisasPorTamanho.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.shopping_bag, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Camisas:',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _camisasPorTamanho.entries.map((e) => Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${e.key}: ${e.value}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      )).toList(),
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

  Widget _vDivider() => Container(height: 40, width: 1, color: Colors.white.withOpacity(0.3));

  Widget _dashboardItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.9), size: 20),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11)),
      ],
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoadingAlunos = false);
    }
  }

  // ==================== ADICIONAR / REMOVER ====================
  Future<void> _mostrarModalAdicionar(Map<String, dynamic> aluno) async {
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
    if (!_podeAdicionar) { _mostrarSemPermissao(); return; }
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
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _removerParticipante(String id, String nome, String alunoId) async {
    if (!_podeRemover) { _mostrarSemPermissao(); return; }
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🗑️ $nome removido!'), backgroundColor: Colors.orange));
    }
  }

  void _mostrarSemPermissao() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sem permissão'), backgroundColor: Colors.red));
  }

  void _abrirDetalhe(ParticipacaoModel p) {
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
      if (_searchParticipantesQuery.isNotEmpty &&
          !p.alunoNome.toLowerCase().contains(_searchParticipantesQuery)) return false;
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.red.shade900 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: isSelected ? Colors.white : Colors.grey.shade600, size: 20),
      ),
    );
  }

  Widget _buildViewModeRow() {
    return Container(
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
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
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (v) => setState(() => _filtroStatus = v ? valor : 'todos'),
      backgroundColor: Colors.grey.shade100,
      selectedColor: Colors.red.shade100,
      checkmarkColor: Colors.red.shade900,
      labelStyle: TextStyle(
        color: selected ? Colors.red.shade900 : Colors.grey.shade700,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  // ==================== CORES DAS BORDAS ====================
  Color _statusBorderColor(ParticipacaoModel p) {
    if (_participantesPatrocinados.contains(p.alunoNome)) return Colors.purple;
    return p.estaQuitado ? Colors.green : Colors.orange;
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
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(color: Colors.orange, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                              child: const Icon(Icons.access_time, color: Colors.white, size: 10),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(nome.split(' ').first, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
          const SizedBox(width: 5),
          Icon(Icons.arrow_forward_rounded, size: 13, color: Colors.grey.shade500),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade100),
            ),
            child: Text(
              nova,
              style: TextStyle(
                fontSize: 10.5,
                color: Colors.green.shade800,
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
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor.withOpacity(0.6), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade200,
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
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Icon(Icons.access_time, color: Colors.white, size: 12),
                              ),
                            ),
                        ],
                      ),
                      if (idade != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '$idade anos',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
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
                                  style: const TextStyle(
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
                  const SizedBox(width: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_podeRemover)
                        IconButton(
                          tooltip: 'Remover',
                          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                          onPressed: () => _removerParticipante(p.id!, p.alunoNome, p.alunoId),
                        ),
                      Icon(Icons.chevron_right, color: Colors.red.shade900, size: 22),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
      child: Text(texto, style: TextStyle(fontSize: 9, color: Colors.red.shade700, fontWeight: FontWeight.bold)),
    );
  }

  Widget _statusBadge(ParticipacaoModel p) {
    final isPaid = p.estaQuitado;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isPaid ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isPaid ? Icons.check_circle : Icons.hourglass_empty, size: 10, color: isPaid ? Colors.green : Colors.orange),
          const SizedBox(width: 2),
          Text(
            isPaid ? 'Pago' : 'R\$ ${p.saldoDevedor.toStringAsFixed(0)}',
            style: TextStyle(fontSize: 8, color: isPaid ? Colors.green : Colors.orange, fontWeight: FontWeight.bold),
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
          const SizedBox(width: 8),
          _chip(Icons.class_, Colors.purple, turma),
        ],
        if (p.tamanhoCamisa != null) ...[
          const SizedBox(width: 8),
          _chip(Icons.shopping_bag, Colors.blue, p.tamanhoCamisa!),
        ],
      ]),
    );
  }

  Widget _chip(IconData icon, MaterialColor color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color.shade700)),
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
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    if (_participantesPatrocinados.contains(p.alunoNome)) return _miniChip('Patrocinado', Colors.purple);
    if (p.estaQuitado) return _miniChip('Quitado', Colors.green);
    return _miniChip('Pendente', Colors.orange);
  }

  Widget _miniChip(String label, MaterialColor color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(12)),
    child: Text(label, style: TextStyle(color: color, fontSize: 12)),
  );

  // ==================== GRID COM HEADER STICKY ====================
  Widget _buildGridView(List<ParticipacaoModel> participantes) {
    final filtrados = _aplicarFiltros(participantes);
    const double headerHeight = 110.0;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildDashboard()),
        SliverPersistentHeader(
          pinned: true,
          delegate: _StickyHeaderDelegate(
            height: headerHeight,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextField(
                    controller: _searchParticipantesController,
                    decoration: InputDecoration(
                      hintText: 'Pesquisar participantes...',
                      prefixIcon: Icon(Icons.search, color: Colors.red),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      suffixIcon: _searchParticipantesQuery.isNotEmpty
                          ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.red),
                        onPressed: () {
                          _searchParticipantesController.clear();
                          setState(() => _searchParticipantesQuery = '');
                        },
                      )
                          : null,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            _buildFiltroChip('TODOS', 'todos'),
                            const SizedBox(width: 8),
                            _buildFiltroChip('💰 PAGOS', 'pagos'),
                            const SizedBox(width: 8),
                            _buildFiltroChip('⏳ PENDENTES', 'pendentes'),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildViewModeRow(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
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
      ],
    );
  }

  // ==================== LIST SEM DASHBOARD ====================
  Widget _buildListView(List<ParticipacaoModel> participantes) {
    final filtrados = _aplicarFiltros(participantes);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Text('${filtrados.length} participantes', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              const Spacer(),
              _buildViewModeRow(),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: filtrados.length + 1,
              itemBuilder: (ctx, i) {
                if (i == filtrados.length) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('🔹 MAIS PARTICIPANTES...',
                          style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600)),
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
      appBar: AppBar(
        title: Text('${widget.eventoNome} - Participantes', style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _limparCacheERecarregar,
            tooltip: 'Atualizar lista',
          ),
          if (_podeGerarCertificados)
            IconButton(
              icon: const Icon(Icons.table_chart),
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'PARTICIPANTES', icon: Icon(Icons.people)),
            Tab(text: 'ADICIONAR', icon: Icon(Icons.person_add)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildParticipantesList(),
          _buildAdicionarParticipantes(),
        ],
      ),
    );
  }

  Widget _buildParticipantesList() {
    return RefreshIndicator(
      onRefresh: _limparCacheERecarregar,
      color: Colors.red.shade900,
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
                  Icon(Icons.error_outline, size: 60, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  Text('Erro: ${snapshot.error}'),
                  ElevatedButton(onPressed: _limparCacheERecarregar, child: const Text('Tentar novamente')),
                ],
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 60, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text('Nenhum participante ainda', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text('Adicione participantes na aba "ADICIONAR"', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
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
              if (_viewMode != 0)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _searchParticipantesController,
                        decoration: InputDecoration(
                          hintText: 'Pesquisar participantes...',
                          prefixIcon: Icon(Icons.search, color: Colors.red),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          suffixIcon: _searchParticipantesQuery.isNotEmpty
                              ? IconButton(
                            icon: Icon(Icons.clear, color: Colors.red),
                            onPressed: () {
                              _searchParticipantesController.clear();
                              setState(() => _searchParticipantesQuery = '');
                            },
                          )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.filter_alt,
                          color: _filtroStatusPagamento.isNotEmpty || _filtroGraduacaoId != null || _filtroStatusCamisa != null
                              ? Colors.red
                              : Colors.grey),
                      onPressed: _mostrarFiltrosAvancados,
                    ),
                  ]),
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
            Icon(Icons.lock, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('Você não tem permissão para adicionar participantes',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
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
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar alunos...',
              prefixIcon: Icon(Icons.search, color: Colors.red),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.clear, color: Colors.red),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
                  : null,
            ),
          ),
        ),
        Expanded(
          child: _isLoadingAlunos
              ? const Center(child: CircularProgressIndicator())
              : _alunosDisponiveis.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 60, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                const Text('Nenhum aluno disponível', style: TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 8),
                Text('Todos os alunos já estão participando!', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
              ],
            ),
          )
              : alunosFiltrados.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 60, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text('Nenhum aluno encontrado para "$_searchQuery"', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
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
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  onTap: () => _mostrarModalAdicionar(aluno),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        RobustAvatar(fotoUrl: aluno['foto'], radius: 28),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(aluno['nome'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                                    child: Text(aluno['graduacao'], style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
                                  ),
                                  if (aluno['turma'] != null && aluno['turma'].toString().isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                                      child: Text(aluno['turma'], style: TextStyle(fontSize: 11, color: Colors.blue.shade700)),
                                    ),
                                  if (idade != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(12)),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.cake, size: 12, color: Colors.teal),
                                          const SizedBox(width: 4),
                                          Text('$idade anos', style: TextStyle(fontSize: 11, color: Colors.teal.shade700)),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          child: ElevatedButton(
                            onPressed: () => _mostrarModalAdicionar(aluno),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao gerar PDF: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchParticipantesController.dispose();
    _debounceTimer?.cancel();
    _cacheAlunos.clear();
    super.dispose();
  }
}