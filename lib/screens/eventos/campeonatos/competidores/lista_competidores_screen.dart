import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/services/campeonato_service.dart';
import 'package:uai_capoeira/models/inscricao_campeonato_model.dart'; // 👈 IMPORT CORRETO!
import 'ficha_competidor_screen.dart';

class ListaCompetidoresScreen extends StatefulWidget {
  final String campeonatoId;
  final String categoriaId;
  final String categoriaNome;

  const ListaCompetidoresScreen({
    super.key,
    required this.campeonatoId,
    required this.categoriaId,
    required this.categoriaNome,
  });

  @override
  State<ListaCompetidoresScreen> createState() => _ListaCompetidoresScreenState();
}

class _ListaCompetidoresScreenState extends State<ListaCompetidoresScreen> {
  final CampeonatoService _campeonatoService = CampeonatoService();
  List<InscricaoCampeonatoModel> _competidores = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filtroPresenca = 'todos'; // 'todos', 'presentes', 'ausentes'

  @override
  void initState() {
    super.initState();
    _carregarCompetidores();
  }

  Future<void> _carregarCompetidores() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final competidores = await _campeonatoService.getCompetidoresPorCategoria(widget.categoriaNome);

      if (mounted) {
        setState(() {
          // 👇 CORREÇÃO: garantir que é List<InscricaoCampeonatoModel> e não é nula
          _competidores = competidores != null
              ? List<InscricaoCampeonatoModel>.from(competidores)
              : [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar competidores: $e');
      if (mounted) {
        setState(() {
          _competidores = [];
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar competidores'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 👇 FILTROS
  List<InscricaoCampeonatoModel> get _competidoresFiltrados {
    // Primeiro aplica busca
    var resultado = _competidores.where((c) {
      if (_searchQuery.isEmpty) return true;

      // 👇 CORREÇÃO: verificações de segurança para evitar null
      final nomeMatch = c.nome.toLowerCase().contains(_searchQuery.toLowerCase());
      final apelidoMatch = c.apelido.toLowerCase().contains(_searchQuery.toLowerCase());
      final grupoMatch = c.grupo.toLowerCase().contains(_searchQuery.toLowerCase());

      return nomeMatch || apelidoMatch || grupoMatch;
    }).toList();

    // Depois aplica filtro de presença (quando implementado no service)
    if (_filtroPresenca != 'todos') {
      // TODO: Implementar quando tiver campo presente no model
    }

    return resultado;
  }

  int get _totalPresentes => _competidores.length; // TODO: Implementar quando tiver campo presente
  int get _totalAusentes => 0; // TODO: Implementar quando tiver campo presente

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('👥 ${widget.categoriaNome}'),
        backgroundColor: Colors.amber.shade900,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
              // Campo de busca
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: 'Buscar competidor...',
                    prefixIcon: const Icon(Icons.search, color: Colors.white),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white),
                      onPressed: () => setState(() => _searchQuery = ''),
                    )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.2),
                    hintStyle: const TextStyle(color: Colors.white70),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              // Filtros de presença
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildFiltroPresenca('todos', 'Todos', _competidores.length),
                    _buildFiltroPresenca('presentes', 'Presentes', _totalPresentes),
                    _buildFiltroPresenca('ausentes', 'Ausentes', _totalAusentes),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (mounted) _carregarCompetidores();
            },
            tooltip: 'Atualizar',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportarLista,
            tooltip: 'Exportar lista',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _competidores.isEmpty
          ? _buildEmptyState()
          : _buildList(),
    );
  }

  // 👇 BOTÕES DE FILTRO
  Widget _buildFiltroPresenca(String valor, String label, int quantidade) {
    final isSelecionado = _filtroPresenca == valor;

    return InkWell(
      onTap: () {
        if (mounted) setState(() => _filtroPresenca = valor);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelecionado ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '$label ($quantidade)',
          style: TextStyle(
            color: isSelecionado ? Colors.amber.shade900 : Colors.white,
            fontWeight: isSelecionado ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'Nenhum competidor',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Nenhum competidor confirmado nesta categoria',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final filtrados = _competidoresFiltrados;

    if (filtrados.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty
                  ? 'Nenhum competidor encontrado'
                  : 'Nenhum resultado para "$_searchQuery"',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: filtrados.length,
      itemBuilder: (context, index) {
        final comp = filtrados[index];
        return _buildCompetidorCard(comp);
      },
    );
  }

  Widget _buildCompetidorCard(InscricaoCampeonatoModel comp) {
    // 👇 CORREÇÃO: verificação de segurança para o nome
    final String primeiraLetra = comp.nome.isNotEmpty ? comp.nome[0] : '?';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        onTap: () {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FichaCompetidorScreen(
                  competidor: comp,
                ),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Foto com borda colorida
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: comp.isMaiorIdade ? Colors.green.shade400 : Colors.orange.shade400,
                    width: 2,
                  ),
                ),
                child: comp.fotoUrl != null && comp.fotoUrl!.isNotEmpty
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: CachedNetworkImage(
                    imageUrl: comp.fotoUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    errorWidget: (context, url, error) => Center(
                      child: Text(
                        primeiraLetra,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ),
                )
                    : Center(
                  child: Text(
                    primeiraLetra,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Informações
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            comp.nome,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: comp.isMaiorIdade
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            comp.isMaiorIdade ? 'MAIOR' : 'MENOR',
                            style: TextStyle(
                              fontSize: 9,
                              color: comp.isMaiorIdade
                                  ? Colors.green.shade800
                                  : Colors.orange.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (comp.apelido.isNotEmpty)
                      Text(
                        'Apelido: ${comp.apelido}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.group, size: 12, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            comp.grupo,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.grade, size: 12, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            comp.graduacaoNome ?? 'Sem graduação',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Seta
              const Icon(
                Icons.chevron_right,
                color: Colors.amber,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 👇 Exportar lista (CSV)
  void _exportarLista() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('📤 Exportar Lista'),
        content: const Text(
          'Escolha o formato para exportar a lista de competidores:',
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (mounted) Navigator.pop(context);
            },
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              if (mounted) {
                Navigator.pop(context);
                _gerarCSV();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('CSV'),
          ),
          ElevatedButton(
            onPressed: () {
              if (mounted) {
                Navigator.pop(context);
                _gerarPDF();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
            child: const Text('PDF'),
          ),
        ],
      ),
    );
  }

  void _gerarCSV() {
    if (!mounted) return;
    // TODO: Implementar geração de CSV
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📄 CSV gerado com sucesso!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _gerarPDF() {
    if (!mounted) return;
    // TODO: Implementar geração de PDF
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📄 PDF gerado com sucesso!'),
        backgroundColor: Colors.green,
      ),
    );
  }
}