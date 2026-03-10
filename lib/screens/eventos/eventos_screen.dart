import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/evento_model.dart';
import 'detalhes_evento_screen.dart';
import 'detalhes_evento_andamento_screen.dart';
import 'package:uai_capoeira/screens/eventos/campeonatos/gestao_campeonato_screen.dart';

class EventosScreen extends StatefulWidget {
  const EventosScreen({super.key});

  @override
  State<EventosScreen> createState() => _EventosScreenState();
}

class _EventosScreenState extends State<EventosScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

  // Filtros
  String _filtroCidade = 'Todas';
  String _filtroTipo = 'Todos';

  // Listas para os filtros
  List<String> _cidades = ['Todas'];
  List<String> _tipos = ['Todos'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 0);
    _verificarEventosEmAndamento();
    _carregarFiltros();
  }

  Future<void> _verificarEventosEmAndamento() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('eventos')
          .where('status', isEqualTo: 'andamento')
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty && mounted) {
        _tabController.animateTo(1);
      }
    } catch (e) {
      debugPrint('Erro ao verificar eventos em andamento: $e');
    }
  }

  Future<void> _carregarFiltros() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('eventos')
          .get();

      final eventos = snapshot.docs
          .map((doc) => EventoModel.fromFirestore(doc))
          .toList();

      Set<String> cidadesSet = {};
      Set<String> tiposSet = {};

      for (var evento in eventos) {
        if (evento.cidade.isNotEmpty) {
          cidadesSet.add(evento.cidade);
        }
        if (evento.tipo.isNotEmpty) {
          tiposSet.add(evento.tipo);
        }
      }

      if (mounted) {
        setState(() {
          _cidades = ['Todas', ...cidadesSet.toList()..sort()];
          _tipos = ['Todos', ...tiposSet.toList()..sort()];
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar filtros: $e');
    }
  }

  Stream<QuerySnapshot> _getEventosStream() {
    Query query = FirebaseFirestore.instance
        .collection('eventos')
        .orderBy('data', descending: true);

    if (_filtroCidade != 'Todas') {
      query = query.where('cidade', isEqualTo: _filtroCidade);
    }
    if (_filtroTipo != 'Todos') {
      query = query.where('tipo', isEqualTo: _filtroTipo);
    }

    return query.snapshots();
  }

  void _mostrarFiltrosDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Filtrar Eventos',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  value: _filtroCidade,
                  decoration: InputDecoration(
                    labelText: 'Cidade',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.location_city, color: Colors.red),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  items: _cidades.map((cidade) {
                    return DropdownMenuItem(
                      value: cidade,
                      child: Text(cidade),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setStateDialog(() {
                      _filtroCidade = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _filtroTipo,
                  decoration: InputDecoration(
                    labelText: 'Tipo de Evento',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.category, color: Colors.red),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  items: _tipos.map((tipo) {
                    return DropdownMenuItem(
                      value: tipo,
                      child: Text(tipo),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setStateDialog(() {
                      _filtroTipo = value!;
                    });
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setStateDialog(() {
                            _filtroCidade = 'Todas';
                            _filtroTipo = 'Todos';
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('LIMPAR'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {});
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('APLICAR'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'EVENTOS',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.normal,
            fontSize: 12,
          ),
          tabs: const [
            Tab(text: 'TODOS', icon: Icon(Icons.event, size: 18)),
            Tab(text: 'EM ANDAMENTO', icon: Icon(Icons.pending, size: 18)),
            Tab(text: 'FINALIZADOS', icon: Icon(Icons.history, size: 18)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: _mostrarFiltrosDialog,
              tooltip: 'Filtrar eventos',
            ),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEventosGrid('todos'),
          _buildEventosGrid('andamento'),
          _buildEventosGrid('finalizado'),
        ],
      ),
    );
  }

  Widget _buildEventosGrid(String status) {
    return StreamBuilder<QuerySnapshot>(
      stream: _getEventosStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.error_outline,
                    size: 60,
                    color: Colors.red.shade200,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Erro ao carregar eventos',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                ),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.red),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState('Nenhum evento encontrado');
        }

        // Converte para EventoModel
        List<EventoModel> eventos = snapshot.data!.docs
            .map((doc) => EventoModel.fromFirestore(doc))
            .toList();

        // Filtrar por status
        if (status != 'todos') {
          eventos = eventos.where((e) => e.status == status).toList();
        }

        if (eventos.isEmpty) {
          String mensagem = status == 'andamento'
              ? 'Nenhum evento em andamento'
              : status == 'finalizado'
              ? 'Nenhum evento finalizado'
              : 'Nenhum evento encontrado';
          return _buildEmptyState(mensagem);
        }

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.75,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: eventos.length,
          itemBuilder: (context, index) {
            final evento = eventos[index];
            return _buildEventoCard(evento, evento.id!);
          },
        );
      },
    );
  }

  Widget _buildEmptyState(String mensagem) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.event_busy,
              size: 60,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            mensagem,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventoCard(EventoModel evento, String docId) {
    final status = evento.status;
    final corStatus = status == 'finalizado' ? Colors.grey : Colors.green;
    final textoStatus = status == 'finalizado' ? 'Finalizado' : 'Ativo';

    return GestureDetector(
      onTap: () {
        // 👇 VERIFICA SE É CAMPEONATO E NÃO ESTÁ FINALIZADO
        if (evento.tipo.toLowerCase() == 'campeonato' && status != 'finalizado') {
          // Campeonato em andamento abre gestão
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GestaoCampeonatoScreen(
                campeonatoId: docId,
                nomeCampeonato: evento.nome,
              ),
            ),
          );
        }
        // 👇 SE É CAMPEONATO FINALIZADO, VAI PARA DETALHES NORMAIS
        else if (evento.tipo.toLowerCase() == 'campeonato' && status == 'finalizado') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DetalhesEventoScreen(
                evento: evento,
                eventoId: docId,
              ),
            ),
          );
        }
        // 👇 SE NÃO É CAMPEONATO, SEGUE A REGRA NORMAL
        else if (status == 'andamento') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DetalhesEventoAndamentoScreen(
                evento: evento,
                eventoId: docId,
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DetalhesEventoScreen(
                evento: evento,
                eventoId: docId,
              ),
            ),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // BANNER
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: evento.linkBanner != null && evento.linkBanner!.isNotEmpty
                        ? CachedNetworkImage(
                      imageUrl: evento.linkBanner!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey.shade200,
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey.shade200,
                        child: Icon(Icons.image, color: Colors.grey.shade400),
                      ),
                    )
                        : Container(
                      color: Colors.grey.shade200,
                      child: Icon(Icons.image, color: Colors.grey.shade400),
                    ),
                  ),
                ),

                // STATUS (esquerda)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: corStatus,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      textoStatus,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // DATA (direita)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      evento.dataFormatada,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // NOME DO EVENTO (CENTRALIZADO)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                evento.nome,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}