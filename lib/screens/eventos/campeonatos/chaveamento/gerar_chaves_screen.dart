import 'package:flutter/material.dart';
import 'package:uai_capoeira/services/campeonato_service.dart';
import 'package:uai_capoeira/models/inscricao_campeonato_model.dart'; // 👈 ÚNICO IMPORT!
import '../competidores/ficha_competidor_screen.dart';

class GerarChavesScreen extends StatefulWidget {
  final String campeonatoId;
  final String categoriaId;
  final String categoriaNome;

  const GerarChavesScreen({
    super.key,
    required this.campeonatoId,
    required this.categoriaId,
    required this.categoriaNome,
  });

  @override
  State<GerarChavesScreen> createState() => _GerarChavesScreenState();
}

class _GerarChavesScreenState extends State<GerarChavesScreen> {
  final CampeonatoService _campeonatoService = CampeonatoService();

  List<InscricaoCampeonatoModel> _competidores = [];
  bool _isLoading = true;
  bool _isGerando = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _carregarCompetidores();
  }

  Future<void> _carregarCompetidores() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // 👇 O SERVICE JÁ RETORNA O TIPO CORRETO!
      final competidores = await _campeonatoService.getCompetidoresPorCategoria(widget.categoriaNome);

      if (mounted) {
        setState(() {
          _competidores = competidores; // ✅ AGORA FUNCIONA!
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar competidores: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar competidores: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Filtrar competidores pela busca
  List<InscricaoCampeonatoModel> get _competidoresFiltrados {
    if (_searchQuery.isEmpty) return _competidores;
    return _competidores.where((c) =>
    c.nome.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        c.apelido.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        c.grupo.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }

  Future<void> _gerarChaves() async {
    if (_competidores.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('É necessário pelo menos 2 competidores para gerar chaves'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isGerando = true);

    try {
      final competidoresIds = _competidores
          .map((c) => c.id)
          .whereType<String>()
          .toList();

      if (competidoresIds.isEmpty) {
        throw Exception('Nenhum ID de competidor válido encontrado');
      }

      await _campeonatoService.gerarChaves(widget.categoriaId, competidoresIds);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chaves geradas com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Erro ao gerar chaves: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar chaves: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGerando = false);
    }
  }

  void _abrirFichaCompetidor(InscricaoCampeonatoModel competidor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FichaCompetidorScreen(
          competidor: competidor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Gerar Chaves - ${widget.categoriaNome}'),
        backgroundColor: Colors.amber.shade900,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Buscar competidor...',
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.15),
                hintStyle: const TextStyle(color: Colors.white70),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarCompetidores,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_competidores.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.emoji_events, size: 80, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              const Text(
                'Nenhum competidor confirmado',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'É necessário ter competidores confirmados\npara gerar as chaves',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade900,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('VOLTAR'),
              ),
            ],
          ),
        ),
      );
    }

    if (_competidoresFiltrados.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Nenhum resultado para "$_searchQuery"',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header com informações
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.amber.shade50,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total de competidores:',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      '${_competidores.length}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Formato:',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      _getFormatoChave(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Lista de competidores
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _competidoresFiltrados.length,
            itemBuilder: (context, index) {
              final comp = _competidoresFiltrados[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: InkWell(
                  onTap: () => _abrirFichaCompetidor(comp),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.amber.shade100,
                        child: Text(
                          comp.nome.isNotEmpty ? comp.nome[0] : '?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                      title: Text(
                        comp.nome,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            comp.grupo,
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                          ),
                          if (comp.graduacaoNome != null && comp.graduacaoNome!.isNotEmpty)
                            Text(
                              comp.graduacaoNome!,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                            ),
                        ],
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Colors.amber,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Botão de gerar chaves
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isGerando ? null : _gerarChaves,
              icon: _isGerando
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.account_tree),
              label: Text(
                _isGerando ? 'GERANDO...' : 'GERAR CHAVES',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade900,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _getFormatoChave() {
    int total = _competidores.length;
    if (total <= 2) return 'Final';
    if (total <= 4) return 'Semifinal + Final';
    if (total <= 8) return 'Quartas + Semi + Final';
    if (total <= 16) return 'Oitavas + Quartas + Semi + Final';
    return 'Mata-mata com múltiplas rodadas';
  }
}