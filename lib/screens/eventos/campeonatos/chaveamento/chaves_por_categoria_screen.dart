import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/services/campeonato_service.dart';
import 'package:uai_capoeira/models/inscricao_campeonato_model.dart';
import 'gerar_chaves_screen.dart';
import 'registrar_resultado_screen.dart';
import 'editar_chaves_screen.dart';
import '../competidores/lista_competidores_screen.dart';

class ChavesPorCategoriaScreen extends StatefulWidget {
  final String campeonatoId;
  final String categoriaId;
  final String categoriaNome;

  const ChavesPorCategoriaScreen({
    super.key,
    required this.campeonatoId,
    required this.categoriaId,
    required this.categoriaNome,
  });

  @override
  State<ChavesPorCategoriaScreen> createState() => _ChavesPorCategoriaScreenState();
}

class _ChavesPorCategoriaScreenState extends State<ChavesPorCategoriaScreen> {
  final CampeonatoService _campeonatoService = CampeonatoService();

  Map<String, dynamic>? _chaves;
  Map<String, InscricaoCampeonatoModel> _competidoresMap = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _isLoading = true);

    try {
      // Carregar chaves
      final chaves = await _campeonatoService.getChaves(widget.categoriaId);

      // Carregar competidores para mapear IDs -> nomes
      final competidores = await _campeonatoService.getCompetidoresPorCategoria(widget.categoriaNome);

      final Map<String, InscricaoCampeonatoModel> map = {};
      for (var comp in competidores) {
        map[comp.id] = comp;
      }

      if (mounted) {
        setState(() {
          _chaves = chaves;
          _competidoresMap = map;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar chaves: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _gerarNovasChaves() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GerarChavesScreen(
          campeonatoId: widget.campeonatoId,
          categoriaId: widget.categoriaId,
          categoriaNome: widget.categoriaNome,
        ),
      ),
    );

    if (result == true) {
      _carregarDados();
    }
  }

  Future<void> _avancarRodada() async {
    try {
      await _campeonatoService.avancarRodada(widget.categoriaId);
      _carregarDados();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Próxima rodada gerada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao avançar rodada'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // MÉTODO DE RESET DE CHAVES
  Future<void> _resetChaves() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('🔄 Resetar Chaves'),
        content: const Text(
          'Tem certeza que deseja resetar todas as chaves?\n'
              'Todo o histórico de resultados será perdido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('RESETAR'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Busca os competidores novamente
      final competidores = await _campeonatoService.getCompetidoresPorCategoria(widget.categoriaNome);

      // 👇 CORREÇÃO AQUI!
      final List<String> competidoresIds = competidores.map((c) => c.id).toList().cast<String>();

      // Gera novas chaves
      await _campeonatoService.gerarChaves(widget.categoriaId, competidoresIds);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Chaves resetadas com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        _carregarDados();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao resetar chaves'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // MÉTODO PARA ABRIR EDIÇÃO MANUAL
  void _editarChavesManualmente() {
    if (_chaves == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditarChavesScreen(
          categoriaId: widget.categoriaId,
          categoriaNome: widget.categoriaNome,
          chavesAtuais: _chaves!,
          competidoresMap: _competidoresMap,
        ),
      ),
    ).then((salvou) {
      if (salvou == true) {
        _carregarDados();
      }
    });
  }

  // MÉTODO PARA ABRIR LISTA DE COMPETIDORES
  void _abrirListaCompetidores() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ListaCompetidoresScreen(
          campeonatoId: widget.campeonatoId,
          categoriaId: widget.categoriaId,
          categoriaNome: widget.categoriaNome,
        ),
      ),
    );
  }

  String _getNomeCompetidor(String? id) {
    if (id == null) return 'BYE';
    final comp = _competidoresMap[id];
    return comp?.nome ?? 'Competidor $id';
  }

  String _getApelidoCompetidor(String? id) {
    if (id == null) return '';
    final comp = _competidoresMap[id];
    return comp?.apelido ?? '';
  }

  String? _getFotoCompetidor(String? id) {
    if (id == null) return null;
    final comp = _competidoresMap[id];
    return comp?.fotoUrl;
  }

  InscricaoCampeonatoModel? _getCompetidor(String? id) {
    if (id == null) return null;
    return _competidoresMap[id];
  }

  bool _isTodasChavesFinalizadas(List<dynamic> chaves) {
    for (var chave in chaves) {
      if (chave['status'] == 'pendente' && chave['competidor2'] != null) {
        return false;
      }
    }
    return true;
  }

  int _getTotalRodadas(int numCompetidores) {
    int rodadas = 0;
    int n = numCompetidores;
    while (n > 1) {
      n = (n / 2).ceil();
      rodadas++;
    }
    return rodadas;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chaves - ${widget.categoriaNome}'),
        backgroundColor: Colors.amber.shade900,
        foregroundColor: Colors.white,
        actions: [
          // BOTÃO PARA VER COMPETIDORES
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: _abrirListaCompetidores,
            tooltip: 'Ver competidores',
          ),
          if (_chaves != null) ...[
            // BOTÃO DE EDIÇÃO MANUAL
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              onPressed: _editarChavesManualmente,
              tooltip: 'Editar chaves manualmente',
            ),
            // BOTÃO DE RESET
            IconButton(
              icon: const Icon(Icons.restart_alt, color: Colors.orange),
              onPressed: _resetChaves,
              tooltip: 'Resetar chaves',
            ),
            // BOTÃO DE ATUALIZAR
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _carregarDados,
              tooltip: 'Atualizar',
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _chaves == null
          ? _buildSemChaves()
          : _buildChavesContent(),
    );
  }

  Widget _buildSemChaves() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_tree, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'Nenhuma chave gerada',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Clique no botão abaixo para gerar as chaves',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _gerarNovasChaves,
            icon: const Icon(Icons.add),
            label: const Text('GERAR CHAVES'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade900,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChavesContent() {
    final chaves = _chaves!['chaves'] as List<dynamic>;
    final rodadaAtual = _chaves!['rodada'] ?? 1;
    final totalRodadas = _chaves!['total_rodadas'] ?? _getTotalRodadas(_competidoresMap.length);
    final todasFinalizadas = _isTodasChavesFinalizadas(chaves);

    return Column(
      children: [
        // Header com informações da rodada
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
                      'Rodada',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      '$rodadaAtual de $totalRodadas',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ),
              if (todasFinalizadas && rodadaAtual < totalRodadas)
                Expanded(
                  child: ElevatedButton(
                    onPressed: _avancarRodada,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('PRÓXIMA RODADA'),
                  ),
                ),
              if (rodadaAtual == totalRodadas && todasFinalizadas)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'CAMPEÃO DEFINIDO!',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Lista de chaves
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: chaves.length,
            itemBuilder: (context, index) {
              final chave = chaves[index];
              return _buildChaveCard(chave, index, rodadaAtual, totalRodadas);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChaveCard(Map<String, dynamic> chave, int index, int rodadaAtual, int totalRodadas) {
    final comp1Id = chave['competidor1'];
    final comp2Id = chave['competidor2'];
    final vencedorId = chave['vencedor'];
    final status = chave['status'];

    final comp1 = _getCompetidor(comp1Id);
    final comp2 = _getCompetidor(comp2Id);

    final nome1 = _getNomeCompetidor(comp1Id);
    final nome2 = _getNomeCompetidor(comp2Id);
    final apelido1 = _getApelidoCompetidor(comp1Id);
    final apelido2 = _getApelidoCompetidor(comp2Id);
    final foto1 = _getFotoCompetidor(comp1Id);
    final foto2 = _getFotoCompetidor(comp2Id);

    final isVencedor1 = vencedorId == comp1Id;
    final isVencedor2 = vencedorId == comp2Id;

    Color getStatusColor() {
      if (status == 'bye') return Colors.blue;
      if (vencedorId != null) return Colors.green;
      return Colors.orange;
    }

    String getStatusText() {
      if (status == 'bye') return 'BYE';
      if (vencedorId != null) return 'FINALIZADO';
      return 'PENDENTE';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          if (status == 'pendente' && comp2Id != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RegistrarResultadoScreen(
                  categoriaId: widget.categoriaId,
                  chaveIndex: index,
                  competidor1Id: comp1Id!,
                  competidor2Id: comp2Id!,
                  nome1: nome1,
                  nome2: nome2,
                  apelido1: apelido1,
                  apelido2: apelido2,
                  fotoUrl1: comp1?.fotoUrl,
                  fotoUrl2: comp2?.fotoUrl,
                ),
              ),
            ).then((_) => _carregarDados());
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // Header da chave
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: getStatusColor().withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.sports_score,
                          size: 12,
                          color: getStatusColor(),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          getStatusText(),
                          style: TextStyle(
                            fontSize: 10,
                            color: getStatusColor(),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (rodadaAtual == totalRodadas && vencedorId != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '🏆 FINAL',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Competidor 1
              _buildCompetidorRow(
                nome: nome1,
                apelido: apelido1,
                isVencedor: isVencedor1,
                isBye: status == 'bye' && comp2Id == null,
                fotoUrl: foto1,
                cor: Colors.amber.shade700,
                mostrarIndicadorCor: true,
              ),

              // VS
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 1,
                        color: Colors.grey.shade300,
                      ),
                    ),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          'VS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: Colors.grey.shade300,
                      ),
                    ),
                  ],
                ),
              ),

              // Competidor 2
              if (comp2Id != null)
                _buildCompetidorRow(
                  nome: nome2,
                  apelido: apelido2,
                  isVencedor: isVencedor2,
                  isBye: false,
                  fotoUrl: foto2,
                  cor: Colors.blue.shade700,
                  mostrarIndicadorCor: true,
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200, width: 1),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward,
                          size: 14,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'BYE - Avança automaticamente',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              if (status == 'pendente' && comp2Id != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade200, width: 1),
                    ),
                    child: const Center(
                      child: Text(
                        '👆 Clique para registrar resultado',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.amber,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompetidorRow({
    required String nome,
    required String apelido,
    required bool isVencedor,
    required bool isBye,
    String? fotoUrl,
    required Color cor,
    bool mostrarIndicadorCor = true,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isVencedor ? Colors.green.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: isVencedor
            ? Border.all(color: Colors.green, width: 1)
            : Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Row(
        children: [
          // Indicador de cor (faixa lateral)
          if (mostrarIndicadorCor && !isBye)
            Container(
              width: 4,
              height: 40,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: cor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

          // Foto ou ícone
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isVencedor ? Colors.green : cor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: isVencedor ? Colors.green : cor,
                width: 2,
              ),
            ),
            child: fotoUrl != null && fotoUrl.isNotEmpty
                ? ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: CachedNetworkImage(
                imageUrl: fotoUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1,
                      valueColor: AlwaysStoppedAnimation<Color>(cor),
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Icon(
                  isVencedor ? Icons.emoji_events : Icons.person,
                  size: 18,
                  color: isVencedor ? Colors.green : cor,
                ),
              ),
            )
                : Icon(
              isVencedor ? Icons.emoji_events : Icons.person,
              size: 18,
              color: isVencedor ? Colors.green : cor,
            ),
          ),
          const SizedBox(width: 12),

          // Informações do competidor
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        nome,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isVencedor ? FontWeight.bold : FontWeight.normal,
                          color: isVencedor ? Colors.green.shade900 : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isBye)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'BYE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                  ],
                ),
                if (apelido.isNotEmpty)
                  Text(
                    apelido,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Badge de vencedor
          if (isVencedor)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.emoji_events,
                    size: 10,
                    color: Colors.white,
                  ),
                  SizedBox(width: 2),
                  Text(
                    'VENC',
                    style: TextStyle(
                      fontSize: 8,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}