import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class GerenciarParticipacoesScreen extends StatefulWidget {
  const GerenciarParticipacoesScreen({super.key});

  @override
  State<GerenciarParticipacoesScreen> createState() =>
      _GerenciarParticipacoesScreenState();
}

class _GerenciarParticipacoesScreenState
    extends State<GerenciarParticipacoesScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String? _filtroEvento;
  List<String> _eventosList = ['Todos'];

  bool get _temFiltroAtivo =>
      _searchQuery.trim().isNotEmpty || _filtroEvento != null;

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });

    _carregarEventos();
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

  Future<void> _excluirParticipacao(
      String participacaoId,
      String alunoNome,
      String eventoNome,
      ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.warning_rounded, color: Colors.red.shade800),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Excluir participação?',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          content: Text(
            'Remover a participação de "$alunoNome" no evento "$eventoNome"?\n\nEssa ação não poderá ser desfeita.',
            style: const TextStyle(height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.delete_rounded, size: 18),
              label: const Text('EXCLUIR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('participacoes_eventos')
          .doc(participacaoId)
          .delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Participação excluída com sucesso!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao excluir: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _editarParticipacao(
      Map<String, dynamic> participacao,
      String id,
      ) {
    return _abrirFormulario(
      participacao: participacao,
      participacaoId: id,
      mensagemSucesso: '✅ Participação atualizada!',
    );
  }

  Future<void> _adicionarParticipacao() {
    return _abrirFormulario(
      mensagemSucesso: '✅ Participação adicionada!',
    );
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(mensagemSucesso),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        );
      },
    );
  }

  void _mostrarFiltros() {
    String? filtroTemp = _filtroEvento;

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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.16),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
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
                      color: Colors.red.shade900,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: filtroTemp ?? 'Todos',
                      isExpanded: true,
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
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() => _filtroEvento = null);
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.cleaning_services_rounded),
                            label: const Text('LIMPAR'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              foregroundColor: Colors.grey.shade800,
                              side: BorderSide(color: Colors.grey.shade300),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() => _filtroEvento = filtroTemp);
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('APLICAR'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade900,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ],
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

    if (_filtroEvento != null) {
      filtrados = filtrados.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['evento_nome'] == _filtroEvento;
      }).toList();
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
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adicionarParticipacao,
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'NOVA',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('participacoes_eventos')
            .orderBy('data_evento', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _buildError(snapshot.error);

          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoading();
          }

          final todosDocs = snapshot.data?.docs ?? [];
          final docs = _filtrarDocs(todosDocs);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 260,
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
                title: const Text(
                  'Participações',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                actions: [
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
                    subtitle: 'Toque em Nova para cadastrar a primeira participação.',
                    showButton: true,
                  ),
                )
              else if (docs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmpty(
                    title: 'Nenhum resultado encontrado',
                    subtitle: 'Tente limpar os filtros ou buscar por outro termo.',
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

  Widget _buildHero({
    required int total,
    required int exibindo,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
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
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.16)),
                    ),
                    child: const Icon(
                      Icons.assignment_ind_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Gerenciar participações',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
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
                            color: Colors.white.withOpacity(0.82),
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
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar por aluno, evento ou graduação...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.72)),
              prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.86)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.86)),
                onPressed: _searchController.clear,
              )
                  : null,
              filled: true,
              fillColor: Colors.white.withOpacity(0.14),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.16)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.16)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: Colors.white, width: 1.2),
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
        final width = constraints.maxWidth;
        final columns = width < 620
            ? 1
            : width < 980
            ? 2
            : 3;

        const spacing = 12.0;
        final itemWidth = (width - spacing * (columns - 1)) / columns;

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
    final alunoNome = _safe(participacao, 'aluno_nome', 'Aluno não informado');
    final eventoNome = _safe(participacao, 'evento_nome', 'Evento não informado');
    final tipoEvento = _safe(participacao, 'tipo_evento', 'Tipo não informado');
    final graduacao = _safe(participacao, 'graduacao', 'Graduação não informada');
    final dataEvento = _formatarData(participacao['data_evento']);
    final certificado = participacao['link_certificado']?.toString() ?? '';
    final temCertificado = certificado.trim().isNotEmpty;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _editarParticipacao(participacao, id),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: _cardDecoration(),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _avatarAluno(alunoNome),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alunoNome,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade900,
                              fontSize: 15,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            eventoNome,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _infoChip(Icons.calendar_month_rounded, dataEvento, Colors.blue),
                    _infoChip(Icons.category_rounded, tipoEvento, Colors.purple),
                    _infoChip(Icons.emoji_events_rounded, graduacao, Colors.orange),
                    if (temCertificado)
                      _infoChip(Icons.verified_rounded, 'Certificado', Colors.green),
                  ],
                ),
                const SizedBox(height: 13),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _editarParticipacao(participacao, id),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: const Text('EDITAR'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue.shade700,
                            side: BorderSide(color: Colors.blue.shade100),
                            textStyle: const TextStyle(fontWeight: FontWeight.w900),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      if (temCertificado) ...[
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Abrir certificado',
                          onPressed: () => _abrirLink(certificado),
                          icon: const Icon(Icons.open_in_new_rounded),
                          style: IconButton.styleFrom(
                            foregroundColor: Colors.green.shade700,
                            backgroundColor: Colors.green.withOpacity(0.08),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Excluir',
                        onPressed: () => _excluirParticipacao(id, alunoNome, eventoNome),
                        icon: const Icon(Icons.delete_rounded),
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          backgroundColor: Colors.red.withOpacity(0.08),
                        ),
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

  Widget _avatarAluno(String nome) {
    final inicial = nome.trim().isEmpty ? '?' : nome.trim()[0].toUpperCase();

    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: Text(
          inicial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Icon(Icons.filter_alt_rounded, color: Colors.red.shade900),
          const SizedBox(width: 9),
          Expanded(
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                if (_searchQuery.isNotEmpty) _filterPill('Busca: $_searchQuery'),
                if (_filtroEvento != null) _filterPill('Evento: $_filtroEvento'),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Limpar filtros',
            onPressed: _limparTudo,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _filterPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.red.shade900,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.red.shade900),
              const SizedBox(height: 14),
              Text(
                'Carregando participações...',
                style: TextStyle(
                  color: Colors.grey.shade700,
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
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
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
                Icon(Icons.error_outline_rounded,
                    size: 74, color: Colors.red.shade700),
                const SizedBox(height: 12),
                const Text(
                  'Erro ao carregar participações',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
                const SizedBox(height: 8),
                Text(
                  error?.toString() ?? 'Tente novamente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.3),
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
              Icon(Icons.event_busy_rounded, size: 74, color: Colors.grey.shade300),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, height: 1.3),
              ),
              if (showButton) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _adicionarParticipacao,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('ADICIONAR PARTICIPAÇÃO'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade900,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _whiteChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
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
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey.shade600,
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
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.red.shade900),
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.red.shade900, width: 1.4),
      ),
    );
  }

  Widget _dialogHandle() {
    return Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.grey.shade100),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.035),
          blurRadius: 7,
          offset: const Offset(0, 3),
        ),
      ],
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

// =====================================================
// FORMULÁRIO DE PARTICIPAÇÃO
// =====================================================
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
  final _formKey = GlobalKey<FormState>();

  final _alunoNomeController = TextEditingController();
  final _eventoNomeController = TextEditingController();
  final _dataController = TextEditingController();
  final _tipoController = TextEditingController();
  final _graduacaoController = TextEditingController();
  final _certificadoController = TextEditingController();

  String? _alunoId;
  String? _eventoId;

  bool _isLoading = false;
  bool _isLoadingAlunos = false;
  bool _isLoadingEventos = false;

  List<Map<String, dynamic>> _alunosList = [];
  List<Map<String, dynamic>> _eventosList = [];

  @override
  void initState() {
    super.initState();
    _carregarAlunos();
    _carregarEventos();

    if (widget.participacao != null) {
      _preencherFormulario();
    }
  }

  Future<void> _carregarAlunos() async {
    setState(() => _isLoadingAlunos = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('alunos')
          .orderBy('nome')
          .get();

      _alunosList = snapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'nome': doc.data()['nome'] ?? '',
        };
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
    _graduacaoController.text = p['graduacao'] ?? '';
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
      color: Colors.blue,
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
      color: Colors.green,
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _selectorHeader(
                          icon: icon,
                          title: titulo,
                          subtitle: subtitulo,
                          color: color,
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: searchController,
                          decoration: _inputDecoration(
                            label: 'Buscar',
                            icon: Icons.search_rounded,
                            color: color,
                          ),
                          onChanged: (value) {
                            setStateDialog(() => query = value.trim());
                          },
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: carregando
                              ? Center(
                            child: CircularProgressIndicator(color: color),
                          )
                              : filtrados.isEmpty
                              ? Center(
                            child: Text(
                              'Nenhum item encontrado.',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          )
                              : ListView.separated(
                            controller: scrollController,
                            itemCount: filtrados.length,
                            separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = filtrados[index];
                              final label =
                                  item[labelKey]?.toString() ?? '';
                              final subtitle =
                                  subtitleBuilder?.call(item) ?? '';

                              return Material(
                                color: color.withOpacity(0.05),
                                borderRadius:
                                BorderRadius.circular(18),
                                child: InkWell(
                                  borderRadius:
                                  BorderRadius.circular(18),
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
                                            color:
                                            color.withOpacity(0.10),
                                            borderRadius:
                                            BorderRadius.circular(15),
                                          ),
                                          child: Icon(icon, color: color),
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
                                                  color:
                                                  Colors.grey.shade900,
                                                  fontWeight:
                                                  FontWeight.w900,
                                                ),
                                              ),
                                              if (subtitle.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  subtitle,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: Colors.grey.shade600,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.chevron_right_rounded,
                                          color: color,
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

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final data = {
        'aluno_id': _alunoId,
        'aluno_nome': _alunoNomeController.text.trim(),
        'evento_id': _eventoId,
        'evento_nome': _eventoNomeController.text.trim(),
        'data_evento': _dataController.text.trim(),
        'tipo_evento': _tipoController.text.trim(),
        'graduacao': _graduacaoController.text.trim(),
        'link_certificado': _certificadoController.text.trim(),
        'atualizado_em': FieldValue.serverTimestamp(),
      };

      if (widget.participacaoId == null) {
        data['criado_em'] = FieldValue.serverTimestamp();

        await FirebaseFirestore.instance
            .collection('participacoes_eventos')
            .add(data);
      } else {
        await FirebaseFirestore.instance
            .collection('participacoes_eventos')
            .doc(widget.participacaoId)
            .update(data);
      }

      widget.onSalvo();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: Colors.red,
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
    final c = color ?? Colors.red.shade900;

    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: c),
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
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
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey.shade600,
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
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.032),
            blurRadius: 7,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          _selectorHeader(
            icon: icon,
            title: title,
            subtitle: subtitle,
            color: color,
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.participacao != null;

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
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.red.shade900, Colors.red.shade700],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.45),
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
                              color: Colors.white.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.16),
                              ),
                            ),
                            child: Icon(
                              editando
                                  ? Icons.edit_note_rounded
                                  : Icons.person_add_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              editando
                                  ? 'Editar participação'
                                  : 'Nova participação',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white),
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
                        _formCard(
                          icon: Icons.person_rounded,
                          title: 'Aluno e evento',
                          subtitle: 'Selecione os vínculos principais.',
                          color: Colors.red.shade900,
                          children: [
                            _selectField(
                              label: 'Aluno *',
                              value: _alunoNomeController.text,
                              emptyText: 'Selecione um aluno',
                              icon: Icons.person_rounded,
                              color: Colors.blue,
                              onTap: _selecionarAluno,
                            ),
                            const SizedBox(height: 12),
                            _selectField(
                              label: 'Evento *',
                              value: _eventoNomeController.text,
                              emptyText: 'Selecione um evento',
                              icon: Icons.event_rounded,
                              color: Colors.green,
                              onTap: _selecionarEvento,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _formCard(
                          icon: Icons.info_rounded,
                          title: 'Informações da participação',
                          subtitle:
                          'Dados exibidos no histórico do aluno e certificados.',
                          color: Colors.purple,
                          children: [
                            TextFormField(
                              controller: _dataController,
                              decoration: _inputDecoration(
                                label: 'Data do evento',
                                icon: Icons.calendar_today_rounded,
                                color: Colors.orange,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _tipoController,
                              decoration: _inputDecoration(
                                label: 'Tipo do evento',
                                icon: Icons.category_rounded,
                                color: Colors.purple,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _graduacaoController,
                              decoration: _inputDecoration(
                                label: 'Graduação na época',
                                icon: Icons.emoji_events_rounded,
                                color: Colors.amber.shade800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _certificadoController,
                              maxLines: 2,
                              decoration: _inputDecoration(
                                label: 'Link do certificado',
                                icon: Icons.link_rounded,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
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
    final isEmpty = value.trim().isEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: _inputDecoration(label: label, icon: icon, color: color),
        child: Row(
          children: [
            Expanded(
              child: Text(
                isEmpty ? emptyText : value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isEmpty ? Colors.grey.shade500 : Colors.grey.shade900,
                  fontWeight: isEmpty ? FontWeight.w500 : FontWeight.w800,
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded, color: color),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(bool editando) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.045),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                label: const Text('CANCELAR'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade800,
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _salvar,
                icon: _isLoading
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.save_rounded),
                label: Text(_isLoading
                    ? 'SALVANDO...'
                    : editando
                    ? 'ATUALIZAR'
                    : 'SALVAR'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
}
