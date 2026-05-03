import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ArvoreVisitasDialog extends StatefulWidget {
  const ArvoreVisitasDialog({super.key});

  @override
  State<ArvoreVisitasDialog> createState() => _ArvoreVisitasDialogState();
}

class _ArvoreVisitasDialogState extends State<ArvoreVisitasDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, dynamic> _dadosAgregados = {};
  bool _carregando = true;
  String? _paisExpandido;
  String? _estadoExpandido;

  @override
  void initState() {
    super.initState();
    _carregarContadores();
  }

  Future<void> _carregarContadores() async {
    try {
      print('🔍 Buscando documento contadores_agregados...');

      final doc = await _firestore
          .collection('estatisticas')
          .doc('contadores_agregados')
          .get(GetOptions(source: Source.server));

      print('📄 Documento existe? ${doc.exists}');

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        print('📊 Dados carregados: $data');

        // Converte a notação de ponto para estrutura aninhada
        final dadosConvertidos = _converterNotacaoPontoParaArvore(data);

        setState(() {
          _dadosAgregados = dadosConvertidos;
          _carregando = false;
        });
      } else {
        print('⚠️ Documento não encontrado ou vazio');
        setState(() {
          _dadosAgregados = {};
          _carregando = false;
        });
      }
    } catch (e) {
      print('❌ Erro ao carregar contadores: $e');
      setState(() => _carregando = false);
    }
  }

  // Função mágica que converte "paises.Brazil.total" em estrutura aninhada
  Map<String, dynamic> _converterNotacaoPontoParaArvore(
    Map<dynamic, dynamic> dados,
  ) {
    final Map<String, dynamic> resultado = {};

    dados.forEach((chave, valor) {
      final chaveString = chave.toString();

      if (chaveString == 'total_visitas' ||
          chaveString == 'ultima_atualizacao') {
        resultado[chaveString] = valor;
      } else {
        final partes = chaveString.split('.');
        Map<String, dynamic> atual = resultado;

        // Cria a estrutura aninhada
        for (int i = 0; i < partes.length - 1; i++) {
          final parte = partes[i];
          if (!atual.containsKey(parte)) {
            atual[parte] = <String, dynamic>{};
          }
          atual = atual[parte] as Map<String, dynamic>;
        }

        // Define o valor na última parte
        final ultimaParte = partes.last;
        atual[ultimaParte] = valor;
      }
    });

    print('✅ Dados convertidos: $resultado');
    return resultado;
  }

  @override
  Widget build(BuildContext context) {
    final totalVisitas = (_dadosAgregados['total_visitas'] ?? 0) as int;

    Map<String, dynamic> paises = {};
    if (_dadosAgregados['paises'] != null) {
      paises = Map<String, dynamic>.from(_dadosAgregados['paises'] as Map);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.red.shade900.withOpacity(0.2),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Column(
          children: [
            // Cabeçalho ESTILIZADO
            _buildCabecalho(totalVisitas),

            // Corpo com os dados
            Expanded(
              child: _carregando
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.red),
                    )
                  : paises.isEmpty
                  ? _buildVazio()
                  : _buildListaPaises(paises),
            ),

            // Rodapé
            _buildRodape(totalVisitas, paises),
          ],
        ),
      ),
    );
  }

  Widget _buildCabecalho(int totalVisitas) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.red.shade800, Colors.red.shade900],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.travel_explore,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Visitantes',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Distribuição geográfica dos acessos',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              // Total em destaque
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility,
                      color: Colors.red.shade900,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$totalVisitas',
                      style: TextStyle(
                        color: Colors.red.shade900,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 24),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVazio() {
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
              Icons.public_off,
              size: 64,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Nenhuma visita registrada',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Os acessos aparecerão aqui',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildListaPaises(Map<String, dynamic> paises) {
    // Ordena países por total (maior primeiro)
    final paisesOrdenados = paises.entries.toList()
      ..sort((a, b) {
        final totalA = (a.value as Map<String, dynamic>)['total'] ?? 0;
        final totalB = (b.value as Map<String, dynamic>)['total'] ?? 0;
        return (totalB as int).compareTo(totalA as int);
      });

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: paisesOrdenados.length,
      itemBuilder: (context, index) {
        final entry = paisesOrdenados[index];
        final paisNome = entry.key;
        final paisData = entry.value as Map<String, dynamic>;
        return _buildPaisItem(paisNome, paisData);
      },
    );
  }

  Widget _buildPaisItem(String paisNome, Map<String, dynamic> paisData) {
    final totalPais = (paisData['total'] ?? 0) as int;
    final expandido = _paisExpandido == paisNome;

    Map<String, dynamic> estados = {};
    if (paisData['estados'] != null) {
      estados = Map<String, dynamic>.from(paisData['estados'] as Map);
    }

    // Ordena estados
    final estadosOrdenados = estados.entries.toList()
      ..sort((a, b) {
        final totalA = (a.value as Map<String, dynamic>)['total'] ?? 0;
        final totalB = (b.value as Map<String, dynamic>)['total'] ?? 0;
        return (totalB as int).compareTo(totalA as int);
      });

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: expandido ? Colors.red.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: expandido ? Colors.red.shade300 : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: expandido
            ? [
                BoxShadow(
                  color: Colors.red.shade100.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _paisExpandido = expandido ? null : paisNome;
                _estadoExpandido = null;
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Ícone do país
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        _getBandeira(paisNome),
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Nome do país
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          paisNome,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 14,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${estados.length} estado${estados.length != 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Total
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade600,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$totalPais',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Ícone expandir
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: expandido
                          ? Colors.red.shade100
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      expandido ? Icons.expand_less : Icons.expand_more,
                      color: expandido
                          ? Colors.red.shade900
                          : Colors.grey.shade600,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Estados (expandido)
          if (expandido && estadosOrdenados.isNotEmpty)
            Container(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: Column(
                children: estadosOrdenados.map((entry) {
                  final estadoNome = entry.key;
                  final estadoData = entry.value as Map<String, dynamic>;
                  return _buildEstadoItem(paisNome, estadoNome, estadoData);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEstadoItem(
    String paisNome,
    String estadoNome,
    Map<String, dynamic> estadoData,
  ) {
    final totalEstado = (estadoData['total'] ?? 0) as int;
    final chaveEstado = '$paisNome|$estadoNome';
    final expandido = _estadoExpandido == chaveEstado;

    Map<String, dynamic> cidades = {};
    if (estadoData['cidades'] != null) {
      cidades = Map<String, dynamic>.from(estadoData['cidades'] as Map);
    }

    // Ordena cidades
    final cidadesOrdenadas = cidades.entries.toList()
      ..sort((a, b) {
        final totalA = (a.value as Map<String, dynamic>)['total'] ?? 0;
        final totalB = (b.value as Map<String, dynamic>)['total'] ?? 0;
        return (totalB as int).compareTo(totalA as int);
      });

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: expandido ? Colors.green.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: expandido ? Colors.green.shade300 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _estadoExpandido = expandido ? null : chaveEstado;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.map, color: Colors.green, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      estadoNome,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '$totalEstado',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expandido ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),

          // Cidades (expandido)
          if (expandido && cidadesOrdenadas.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 12, bottom: 8),
              child: Column(
                children: cidadesOrdenadas.map((entry) {
                  final cidadeNome = entry.key;
                  final cidadeData = entry.value as Map<String, dynamic>;
                  final totalCidade = (cidadeData['total'] ?? 0) as int;

                  return Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.location_city,
                            color: Colors.orange.shade700,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            cidadeNome,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.orange.shade400,
                                Colors.orange.shade600,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$totalCidade',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRodape(int totalVisitas, Map<String, dynamic> paises) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildEstatisticaRodape(
            icon: Icons.visibility,
            value: '$totalVisitas',
            label: 'Total de visitas',
            color: Colors.red,
          ),
          Container(width: 1, height: 30, color: Colors.grey.shade300),
          _buildEstatisticaRodape(
            icon: Icons.public,
            value: '${paises.length}',
            label: 'Países',
            color: Colors.blue,
          ),
          Container(width: 1, height: 30, color: Colors.grey.shade300),
          _buildEstatisticaRodape(
            icon: Icons.location_city,
            value: '${_contarCidades(paises)}',
            label: 'Cidades',
            color: Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildEstatisticaRodape({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ),
      ],
    );
  }

  int _contarCidades(Map<String, dynamic> paises) {
    int total = 0;
    for (var pais in paises.values) {
      final estados =
          (pais as Map<String, dynamic>)['estados'] as Map<String, dynamic>?;
      if (estados != null) {
        for (var estado in estados.values) {
          final cidades =
              (estado as Map<String, dynamic>)['cidades']
                  as Map<String, dynamic>?;
          if (cidades != null) {
            total += cidades.length;
          }
        }
      }
    }
    return total;
  }

  String _getBandeira(String pais) {
    switch (pais.toLowerCase()) {
      case 'brasil':
      case 'brazil':
        return '🇧🇷';
      case 'estados unidos':
      case 'united states':
        return '🇺🇸';
      case 'portugal':
        return '🇵🇹';
      case 'argentina':
        return '🇦🇷';
      case 'espanha':
      case 'spain':
        return '🇪🇸';
      case 'frança':
      case 'france':
        return '🇫🇷';
      case 'alemanha':
      case 'germany':
        return '🇩🇪';
      case 'italia':
      case 'italy':
        return '🇮🇹';
      case 'japao':
      case 'japan':
        return '🇯🇵';
      default:
        return '🌍';
    }
  }
}
