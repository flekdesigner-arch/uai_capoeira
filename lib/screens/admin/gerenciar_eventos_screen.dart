import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/evento_model.dart';
import '../../services/evento_service.dart';
import '../../services/permissao_service.dart';
import '../eventos/criar_evento_screen.dart';

class GerenciarEventosScreen extends StatefulWidget {
  const GerenciarEventosScreen({super.key});

  @override
  State<GerenciarEventosScreen> createState() => _GerenciarEventosScreenState();
}

class _GerenciarEventosScreenState extends State<GerenciarEventosScreen> {
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // CONTROLE DE PERMISSÕES
  final PermissaoService _permissaoService = PermissaoService();
  bool _podeCriarEvento = false;
  bool _podeEditarEvento = false;
  bool _podeExcluirEvento = false;
  bool _carregandoPermissoes = true;

  // CONTROLE DE VIEW MODE
  int _viewMode = 0;
  final List<IconData> _viewModeIcons = [
    Icons.view_list,
    Icons.grid_view,
  ];
  final List<String> _viewModeTooltips = [
    'Visualizar em Lista',
    'Visualizar em Grade',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    _carregarPermissoes();
  }

  Future<void> _carregarPermissoes() async {
    setState(() => _carregandoPermissoes = true);

    final podeCriar = await _permissaoService.temPermissao('pode_criar_evento');
    final podeEditar = await _permissaoService.temPermissao('pode_editar_evento');
    final podeExcluir = await _permissaoService.temPermissao('pode_excluir_evento');

    if (mounted) {
      setState(() {
        _podeCriarEvento = podeCriar;
        _podeEditarEvento = podeEditar;
        _podeExcluirEvento = podeExcluir;
        _carregandoPermissoes = false;
      });
    }
  }

  // 🔥 FUNÇÃO PARA ALTERNAR O PORTFÓLIO WEB
  Future<void> _alternarPortfolioWeb(String eventoId, bool valorAtual) async {
    if (!_podeEditarEvento) {
      _mostrarSemPermissao();
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('eventos')
          .doc(eventoId)
          .update({'mostrarNoPortfolioWeb': !valorAtual});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!valorAtual
                ? 'Evento será mostrado no site 🌐'
                : 'Evento NÃO será mostrado no site'),
            backgroundColor: !valorAtual ? Colors.blue : Colors.grey,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao alterar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 🔥 FUNÇÃO DE EXCLUSÃO
  Future<void> _excluirEvento(String eventoId, String nomeEvento) async {
    if (!_podeExcluirEvento) {
      _mostrarSemPermissao();
      return;
    }

    final TextEditingController confirmController = TextEditingController();
    bool isConfirmEnabled = false;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Excluir Evento'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Esta ação é irreversível!',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  'Digite o nome do evento exatamente como está abaixo para confirmar a exclusão:',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '"$nomeEvento"',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmController,
                  decoration: InputDecoration(
                    labelText: 'Nome do evento',
                    hintText: 'Digite o nome exato do evento',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    errorText: isConfirmEnabled ? null : null,
                  ),
                  onChanged: (value) {
                    setState(() {
                      isConfirmEnabled = value.trim() == nomeEvento;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCELAR'),
              ),
              ElevatedButton(
                onPressed: isConfirmEnabled
                    ? () => Navigator.pop(context, true)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
                child: const Text('EXCLUIR'),
              ),
            ],
          );
        },
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('eventos')
            .doc(eventoId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Evento excluído com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao excluir: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _mostrarSemPermissao() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Você não tem permissão para realizar esta ação'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _alterarStatus(String eventoId, String statusAtual) async {
    if (!_podeEditarEvento) {
      _mostrarSemPermissao();
      return;
    }

    final novoStatus = statusAtual == 'andamento' ? 'finalizado' : 'andamento';

    try {
      await FirebaseFirestore.instance
          .collection('eventos')
          .doc(eventoId)
          .update({'status': novoStatus});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status alterado para ${novoStatus == 'andamento' ? 'Em andamento' : 'Finalizado'}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao alterar status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _abrirCadastroEvento({EventoModel? evento}) {
    if (evento == null && !_podeCriarEvento) {
      _mostrarSemPermissao();
      return;
    }
    if (evento != null && !_podeEditarEvento) {
      _mostrarSemPermissao();
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CriarEventoScreen(evento: evento),
      ),
    ).then((salvo) {
      if (salvo == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(evento == null ? 'Evento criado com sucesso!' : 'Evento atualizado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    });
  }

  String _formatarData(dynamic data) {
    if (data == null) return 'Não informada';
    if (data is Timestamp) {
      return _dateFormat.format(data.toDate());
    }
    return data.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Eventos'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_viewModeIcons[_viewMode]),
            tooltip: _viewModeTooltips[_viewMode],
            onPressed: () => setState(() => _viewMode = (_viewMode + 1) % 2),
          ),
          if (_podeCriarEvento)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _abrirCadastroEvento(),
            ),
        ],
      ),
      body: _carregandoPermissoes
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar eventos...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
                    : null,
              ),
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('eventos')
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
                      ],
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_busy, size: 80, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        const Text(
                          'Nenhum evento cadastrado',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        if (_podeCriarEvento) ...[
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => _abrirCadastroEvento(),
                            icon: const Icon(Icons.add),
                            label: const Text('ADICIONAR EVENTO'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade900,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                // CONVERTE OS DOCS PARA EVENTOMODEL
                final List<EventoModel> eventos = snapshot.data!.docs
                    .map((doc) => EventoModel.fromFirestore(doc))
                    .toList();

                // 🔥 ORDENAÇÃO: Eventos em andamento primeiro
                eventos.sort((a, b) {
                  if (a.status == 'andamento' && b.status != 'andamento') {
                    return -1;
                  } else if (a.status != 'andamento' && b.status == 'andamento') {
                    return 1;
                  } else {
                    return b.data.compareTo(a.data);
                  }
                });

                // Filtrar pela pesquisa
                List<EventoModel> eventosFiltrados = eventos;
                if (_searchQuery.isNotEmpty) {
                  eventosFiltrados = eventos.where((evento) {
                    return evento.nome.toLowerCase().contains(_searchQuery) ||
                        evento.cidade.toLowerCase().contains(_searchQuery) ||
                        evento.tipo.toLowerCase().contains(_searchQuery);
                  }).toList();
                }

                if (eventosFiltrados.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search_off, size: 80, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          "Nenhum evento encontrado para '$_searchQuery'",
                          style: const TextStyle(fontSize: 16, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return _viewMode == 0
                    ? _buildListView(eventosFiltrados)
                    : _buildGridView(eventosFiltrados);
              },
            ),
          ),
        ],
      ),
    );
  }

  // VIEW EM LISTA (COM BOTÃO WEB ADICIONADO)
  Widget _buildListView(List<EventoModel> eventos) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: eventos.length,
      itemBuilder: (context, index) {
        final evento = eventos[index];
        final status = evento.status;
        final corStatus = status == 'finalizado' ? Colors.grey : Colors.green;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: () {
              // TODO: Navegar para detalhes do evento
            },
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                // BANNER QUADRADO
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: corStatus.withOpacity(0.1),
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(12),
                    ),
                  ),
                  child: evento.linkBanner != null && evento.linkBanner!.isNotEmpty
                      ? ClipRRect(
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(12),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: evento.linkBanner!,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) {
                        return Center(
                          child: Icon(Icons.broken_image, color: corStatus),
                        );
                      },
                    ),
                  )
                      : Center(
                    child: Icon(evento.iconeDoTipo, color: corStatus, size: 40),
                  ),
                ),

                // INFORMAÇÕES
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // STATUS
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: corStatus.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            status == 'andamento' ? 'EM ANDAMENTO' : 'FINALIZADO',
                            style: TextStyle(
                              color: corStatus,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),

                        // NOME
                        Text(
                          evento.nome,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                        // TIPO
                        Text(
                          evento.tipo,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 4),

                        // DATA
                        Row(
                          children: [
                            Icon(Icons.calendar_today, size: 10, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                evento.dataFormatada,
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        // LOCAL
                        Row(
                          children: [
                            Icon(Icons.location_on, size: 10, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                evento.cidade,
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        // VALOR (se tiver)
                        if (evento.valorInscricao > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(Icons.attach_money, size: 10, color: Colors.green.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  'R\$ ${evento.valorInscricao.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // BOTÕES DE AÇÃO (AGORA COM ÍCONE WEB)
                Column(
                  children: [
                    // 🌐 BOTÃO WEB (NOVO!)
                    if (_podeEditarEvento)
                      IconButton(
                        icon: Icon(
                          Icons.web,
                          color: evento.mostrarNoPortfolioWeb ? Colors.blue : Colors.grey,
                          size: 20,
                        ),
                        onPressed: () => _alternarPortfolioWeb(evento.id!, evento.mostrarNoPortfolioWeb),
                        tooltip: evento.mostrarNoPortfolioWeb
                            ? 'Remover do site 🌐'
                            : 'Adicionar ao site 🌐',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),

                    // STATUS
                    if (_podeEditarEvento)
                      IconButton(
                        icon: Icon(
                          status == 'andamento' ? Icons.play_circle : Icons.check_circle,
                          color: status == 'andamento' ? Colors.green : Colors.grey,
                          size: 20,
                        ),
                        onPressed: () => _alterarStatus(evento.id!, status),
                        tooltip: 'Alterar status',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),

                    // EDITAR
                    if (_podeEditarEvento)
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                        onPressed: () => _abrirCadastroEvento(evento: evento),
                        tooltip: 'Editar',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),

                    // EXCLUIR
                    if (_podeExcluirEvento)
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                        onPressed: () => _excluirEvento(evento.id!, evento.nome),
                        tooltip: 'Excluir',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  // VIEW EM GRADE (COM BOTÃO WEB ADICIONADO)
  Widget _buildGridView(List<EventoModel> eventos) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      itemCount: eventos.length,
      itemBuilder: (context, index) {
        final evento = eventos[index];
        final status = evento.status;
        final corStatus = status == 'finalizado' ? Colors.grey : Colors.green;

        return Card(
          elevation: 4,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: () {
              // TODO: Navegar para detalhes do evento
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // BANNER
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        color: Colors.grey[200],
                        child: evento.linkBanner != null && evento.linkBanner!.isNotEmpty
                            ? CachedNetworkImage(
                          imageUrl: evento.linkBanner!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorWidget: (context, url, error) => Container(
                            color: corStatus.withOpacity(0.1),
                            child: Center(
                              child: Icon(
                                Icons.broken_image,
                                size: 40,
                                color: corStatus,
                              ),
                            ),
                          ),
                        )
                            : Container(
                          color: corStatus.withOpacity(0.1),
                          child: Center(
                            child: Icon(
                              evento.iconeDoTipo,
                              size: 50,
                              color: corStatus,
                            ),
                          ),
                        ),
                      ),

                      // TAG DE STATUS
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 28,
                          color: corStatus.withOpacity(0.9),
                          child: Center(
                            child: Text(
                              status == 'andamento' ? 'EM ANDAMENTO' : 'FINALIZADO',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 🌐 TAG WEB (NOVA!)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: evento.mostrarNoPortfolioWeb
                                ? Colors.blue
                                : Colors.grey.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            Icons.web,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // INFORMAÇÕES
                Container(
                  padding: const EdgeInsets.all(12.0),
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // NOME
                      Text(
                        evento.nome,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      // TIPO
                      const SizedBox(height: 4),
                      Text(
                        evento.tipo,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 6),

                      // DATA
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              evento.dataFormatada,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4),

                      // LOCAL
                      Row(
                        children: [
                          Icon(Icons.location_on, size: 12, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              evento.cidade,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // BOTÕES DE AÇÃO (COM WEB INCLUSO)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // 🌐 BOTÃO WEB
                          if (_podeEditarEvento)
                            IconButton(
                              icon: Icon(
                                Icons.web,
                                color: evento.mostrarNoPortfolioWeb ? Colors.blue : Colors.grey,
                                size: 20,
                              ),
                              onPressed: () => _alternarPortfolioWeb(evento.id!, evento.mostrarNoPortfolioWeb),
                              tooltip: evento.mostrarNoPortfolioWeb
                                  ? 'Remover do site'
                                  : 'Adicionar ao site',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),

                          // STATUS
                          if (_podeEditarEvento)
                            IconButton(
                              icon: Icon(
                                status == 'andamento' ? Icons.play_circle : Icons.check_circle,
                                color: status == 'andamento' ? Colors.green : Colors.grey,
                                size: 20,
                              ),
                              onPressed: () => _alterarStatus(evento.id!, status),
                              tooltip: 'Alterar status',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),

                          // EDITAR
                          if (_podeEditarEvento)
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                              onPressed: () => _abrirCadastroEvento(evento: evento),
                              tooltip: 'Editar',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),

                          // EXCLUIR
                          if (_podeExcluirEvento)
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                              onPressed: () => _excluirEvento(evento.id!, evento.nome),
                              tooltip: 'Excluir',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}