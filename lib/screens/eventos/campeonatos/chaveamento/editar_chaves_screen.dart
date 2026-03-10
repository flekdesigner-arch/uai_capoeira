import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uai_capoeira/services/campeonato_service.dart';
import 'package:uai_capoeira/models/inscricao_campeonato_model.dart'; // 👈 IMPORT CORRETO!

class EditarChavesScreen extends StatefulWidget {
  final String categoriaId;
  final String categoriaNome;
  final Map<String, dynamic> chavesAtuais;
  final Map<String, InscricaoCampeonatoModel> competidoresMap;

  const EditarChavesScreen({
    super.key,
    required this.categoriaId,
    required this.categoriaNome,
    required this.chavesAtuais,
    required this.competidoresMap,
  });

  @override
  State<EditarChavesScreen> createState() => _EditarChavesScreenState();
}

class _EditarChavesScreenState extends State<EditarChavesScreen> {
  late List<dynamic> _chaves;
  bool _isSaving = false;
  final CampeonatoService _campeonatoService = CampeonatoService();

  @override
  void initState() {
    super.initState();
    _chaves = List.from(widget.chavesAtuais['chaves']);
  }

  Future<void> _salvarChaves() async {
    setState(() => _isSaving = true);

    try {
      await _campeonatoService.atualizarChaves(widget.categoriaId, _chaves);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Chaves salvas com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // TROCAR COMPETIDORES ENTRE CONFRONTOS
  void _trocarCompetidores(int sourceIndex, int targetIndex) {
    if (sourceIndex == targetIndex) return;

    setState(() {
      final temp = _chaves[sourceIndex];
      _chaves[sourceIndex] = _chaves[targetIndex];
      _chaves[targetIndex] = temp;
    });
  }

  // TROCAR COMPETIDORES DENTRO DO MESMO CONFRONTO
  void _trocarOrdemInterna(int index) {
    setState(() {
      final chave = _chaves[index];
      final temp1 = chave['competidor1'];
      final temp2 = chave['competidor2'];

      chave['competidor1'] = temp2;
      chave['competidor2'] = temp1;
    });
  }

  String _getNomeCompetidor(String? id) {
    if (id == null) return 'BYE';
    final comp = widget.competidoresMap[id];
    return comp?.nome ?? 'Competidor $id';
  }

  String _getApelidoCompetidor(String? id) {
    if (id == null) return '';
    final comp = widget.competidoresMap[id];
    return comp?.apelido ?? '';
  }

  InscricaoCampeonatoModel? _getCompetidor(String? id) {
    if (id == null) return null;
    return widget.competidoresMap[id];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('✏️ Editar Chaves - ${widget.categoriaNome}'),
        backgroundColor: Colors.amber.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.save),
            onPressed: _isSaving ? null : _salvarChaves,
            tooltip: 'Salvar',
          ),
        ],
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Instruções
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.amber.shade50,
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade900),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '🖐️ Arraste um card e solte sobre outro para trocar confrontos inteiros\n'
                        '🔄 Use o botão swap para trocar a ordem dos competidores no mesmo confronto',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Lista com Drag & Drop
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _chaves.length,
              onReorder: (oldIndex, newIndex) {
                _trocarCompetidores(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final chave = _chaves[index];
                final comp1Id = chave['competidor1'];
                final comp2Id = chave['competidor2'];

                final nome1 = _getNomeCompetidor(comp1Id);
                final nome2 = comp2Id != null ? _getNomeCompetidor(comp2Id) : null;
                final apelido1 = _getApelidoCompetidor(comp1Id);
                final apelido2 = comp2Id != null ? _getApelidoCompetidor(comp2Id) : null;

                final isBye = comp2Id == null;

                return Card(
                  key: ValueKey('chave_$index'),
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isBye ? Colors.blue.shade200 : Colors.amber.shade200,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Cabeçalho do confronto
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isBye
                                ? Colors.blue.shade50
                                : Colors.amber.shade50,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Confronto ${index + 1}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isBye
                                      ? Colors.blue.shade900
                                      : Colors.amber.shade900,
                                ),
                              ),
                              if (!isBye)
                                IconButton(
                                  icon: const Icon(
                                    Icons.swap_horiz,
                                    size: 16,
                                    color: Colors.amber,
                                  ),
                                  onPressed: () => _trocarOrdemInterna(index),
                                  tooltip: 'Trocar ordem dos competidores',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                            ],
                          ),
                        ),

                        // Conteúdo do confronto com DRAG HANDLE
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              // Competidor 1 (AMARELO) - ARRASTÁVEL
                              _buildDraggableCompetidor(
                                index: index,
                                posicao: 'comp1',
                                numero: '1',
                                nome: nome1,
                                apelido: apelido1,
                                cor: Colors.amber,
                                chave: chave,
                              ),

                              if (!isBye) ...[
                                const SizedBox(height: 8),

                                // VS
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        height: 1,
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 8),
                                      child: const Text(
                                        'VS',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber,
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

                                const SizedBox(height: 8),

                                // Competidor 2 (AZUL) - ARRASTÁVEL
                                _buildDraggableCompetidor(
                                  index: index,
                                  posicao: 'comp2',
                                  numero: '2',
                                  nome: nome2!,
                                  apelido: apelido2!,
                                  cor: Colors.blue,
                                  chave: chave,
                                ),
                              ] else ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(
                                        Icons.arrow_forward,
                                        size: 14,
                                        color: Colors.blue,
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'BYE - Avança automaticamente',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
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

  // WIDGET PARA COMPETIDOR ARRASTÁVEL COM FOTO
  Widget _buildDraggableCompetidor({
    required int index,
    required String posicao,
    required String numero,
    required String nome,
    required String apelido,
    required Color cor,
    required Map<String, dynamic> chave,
  }) {
    final competidorId = chave[posicao == 'comp1' ? 'competidor1' : 'competidor2'];
    final comp = _getCompetidor(competidorId);

    return Draggable<Map<String, dynamic>>(
      data: {
        'chaveIndex': index,
        'posicao': posicao,
        'competidorId': competidorId,
        'nome': nome,
      },
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cor, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Foto no feedback
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: cor, width: 2),
                ),
                child: comp?.fotoUrl != null
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: CachedNetworkImage(
                    imageUrl: comp!.fotoUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Center(
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1),
                      ),
                    ),
                    errorWidget: (context, url, error) => Center(
                      child: Text(
                        numero,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: cor,
                        ),
                      ),
                    ),
                  ),
                )
                    : Center(
                  child: Text(
                    numero,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: cor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    nome,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (apelido.isNotEmpty)
                    Text(
                      apelido,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildCompetidorCard(
          numero: numero,
          nome: nome,
          apelido: apelido,
          cor: cor,
          fotoUrl: comp?.fotoUrl,
        ),
      ),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      child: DragTarget<Map<String, dynamic>>(
        onWillAcceptWithDetails: (details) {
          final data = details.data;
          return data != null && data['competidorId'] != competidorId;
        },
        onAcceptWithDetails: (details) {
          final data = details.data;
          setState(() {
            final sourceIndex = data['chaveIndex'];
            final sourcePosicao = data['posicao'];
            final targetIndex = index;
            final targetPosicao = posicao;

            // Troca os competidores
            final sourceChave = _chaves[sourceIndex];
            final targetChave = _chaves[targetIndex];

            final sourceId = sourceChave[sourcePosicao == 'comp1' ? 'competidor1' : 'competidor2'];
            final targetId = targetChave[targetPosicao == 'comp1' ? 'competidor1' : 'competidor2'];

            sourceChave[sourcePosicao == 'comp1' ? 'competidor1' : 'competidor2'] = targetId;
            targetChave[targetPosicao == 'comp1' ? 'competidor1' : 'competidor2'] = sourceId;
          });
        },
        builder: (context, candidateData, rejectedData) {
          return _buildCompetidorCard(
            numero: numero,
            nome: nome,
            apelido: apelido,
            cor: cor,
            fotoUrl: comp?.fotoUrl,
          );
        },
      ),
    );
  }

  // Widget base do competidor com foto
  Widget _buildCompetidorCard({
    required String numero,
    required String nome,
    required String apelido,
    required Color cor,
    String? fotoUrl,
  }) {
    return Row(
      children: [
        // Container com foto ou inicial
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(color: cor, width: 2),
          ),
          child: fotoUrl != null
              ? ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: CachedNetworkImage(
              imageUrl: fotoUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Center(
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1),
                ),
              ),
              errorWidget: (context, url, error) => Center(
                child: Text(
                  numero,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: cor,
                  ),
                ),
              ),
            ),
          )
              : Center(
            child: Text(
              numero,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: cor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nome,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (apelido.isNotEmpty)
                Text(
                  apelido,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
            ],
          ),
        ),
        Icon(
          Icons.drag_indicator,
          color: Colors.grey.shade400,
          size: 20,
        ),
      ],
    );
  }
}