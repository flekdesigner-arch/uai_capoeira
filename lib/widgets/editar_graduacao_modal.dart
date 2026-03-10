import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/graduacao_service.dart';

class EditarGraduacaoModal extends StatefulWidget {
  final String? graduacaoAtualId;
  final String? graduacaoNovaId;
  final String eventoId;
  final Map<String, dynamic>? aluno; // 🔥 NOVO: dados completos do aluno

  const EditarGraduacaoModal({
    super.key,
    this.graduacaoAtualId,
    this.graduacaoNovaId,
    required this.eventoId,
    this.aluno, // 🔥 Opcional, mas importante para regras de idade
  });

  @override
  State<EditarGraduacaoModal> createState() => _EditarGraduacaoModalState();
}

class _EditarGraduacaoModalState extends State<EditarGraduacaoModal> {
  final GraduacaoService _graduacaoService = GraduacaoService();

  List<Map<String, dynamic>> _graduacoes = [];
  List<Map<String, dynamic>> _todasGraduacoes = [];
  String? _graduacaoSelecionada;
  bool _isLoading = true;

  // Dados do aluno
  int? _nivelAtual;
  String? _tipoPublicoAluno;
  int? _idadeAluno;
  String? _graduacaoAtualTexto;

  // 🔥 ÚLTIMO NÍVEL INFANTIL
  final int _ultimoNivelInfantil = 8;

  @override
  void initState() {
    super.initState();
    _carregarGraduacoes();
  }

  // 🔥 CALCULAR IDADE
  int _calcularIdade(DateTime dataNascimento) {
    final hoje = DateTime.now();
    int idade = hoje.year - dataNascimento.year;
    if (hoje.month < dataNascimento.month ||
        (hoje.month == dataNascimento.month && hoje.day < dataNascimento.day)) {
      idade--;
    }
    return idade;
  }

  // 🔥 CONVERSÃO DE DATA
  DateTime? _converterData(dynamic data) {
    if (data == null) return null;

    try {
      if (data is Timestamp) {
        return data.toDate();
      }
      if (data is String) {
        try {
          return DateTime.parse(data);
        } catch (e) {
          return null;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 🔥 DETERMINAR CATEGORIA POR IDADE
  String _determinarCategoriaPorIdade() {
    if (widget.aluno != null && widget.aluno!['data_nascimento'] != null) {
      final dataNascimento = _converterData(widget.aluno!['data_nascimento']);
      if (dataNascimento != null) {
        final idade = _calcularIdade(dataNascimento);
        return idade < 13 ? 'INFANTIL' : 'ADULTO';
      }
    }
    return _tipoPublicoAluno ?? 'ADULTO';
  }

  // 🔥 VERIFICAR SE PODE MUDAR PARA ADULTO
  bool _podeMudarParaAdulto(int nivelAtual, int idade) {
    // Se já atingiu o último nível infantil
    if (nivelAtual >= _ultimoNivelInfantil) {
      return true;
    }

    // Se a idade já permite ADULTO (13+)
    if (idade >= 13) {
      return true;
    }

    return false;
  }

  Future<void> _carregarGraduacoes() async {
    setState(() => _isLoading = true);

    try {
      // Busca todas as graduações primeiro
      _todasGraduacoes = await _graduacaoService.buscarTodasGraduacoes();

      // 🔥 Dados do aluno (prioridade para dados passados)
      if (widget.aluno != null) {
        // Tenta pegar graduação atual do mapa do aluno
        _graduacaoAtualTexto = widget.aluno!['graduacao'];

        // Calcula idade se tiver data de nascimento
        if (widget.aluno!['data_nascimento'] != null) {
          final dataNascimento = _converterData(widget.aluno!['data_nascimento']);
          if (dataNascimento != null) {
            _idadeAluno = _calcularIdade(dataNascimento);
          }
        }
      }

      // Busca dados da graduação atual pelo ID (se tiver)
      if (widget.graduacaoAtualId != null && widget.graduacaoAtualId!.isNotEmpty) {
        final graduacaoAtual = _todasGraduacoes.firstWhere(
              (g) => g['id'] == widget.graduacaoAtualId,
          orElse: () => {},
        );

        if (graduacaoAtual.isNotEmpty) {
          _nivelAtual = graduacaoAtual['nivel_graduacao'] ?? 0;
          _tipoPublicoAluno = graduacaoAtual['tipo_publico'] ?? 'ADULTO';
        }
      }
      // Se não tem ID mas tem texto, tenta determinar pela graduação
      else if (_graduacaoAtualTexto != null && _graduacaoAtualTexto != 'SEM GRADUÇÃO') {
        if (_graduacaoAtualTexto!.contains('INFANTIL')) {
          _tipoPublicoAluno = 'INFANTIL';
          // Tenta encontrar o nível aproximado
          for (var g in _todasGraduacoes) {
            if (_graduacaoAtualTexto!.contains(g['nome_graduacao']?.split(' ').take(2).join(' '))) {
              _nivelAtual = g['nivel_graduacao'];
              break;
            }
          }
        } else {
          _tipoPublicoAluno = 'ADULTO';
        }
      }

      // Se ainda não tem tipo, determina pela idade
      if (_tipoPublicoAluno == null && _idadeAluno != null) {
        _tipoPublicoAluno = _idadeAluno! < 13 ? 'INFANTIL' : 'ADULTO';
      }

      debugPrint('🎯 Dados do aluno:');
      debugPrint('   - Nível atual: $_nivelAtual');
      debugPrint('   - Tipo: $_tipoPublicoAluno');
      debugPrint('   - Idade: $_idadeAluno');
      debugPrint('   - Graduação: $_graduacaoAtualTexto');

      // Busca dados do evento
      final eventoDoc = await FirebaseFirestore.instance
          .collection('eventos')
          .doc(widget.eventoId)
          .get();

      final tipoEvento = eventoDoc.data()?['tipo'] ?? '';
      final isBatizado = tipoEvento.toString().toUpperCase().contains('BATIZADO');

      if (!isBatizado) {
        setState(() => _isLoading = false);
        return;
      }

      // 🔥 CASO 1: Aluno SEM graduação
      if (_nivelAtual == null || _nivelAtual == 0 ||
          _graduacaoAtualTexto == 'SEM GRADUÇÃO') {

        debugPrint('📌 Aluno SEM graduação');

        final String categoria = _determinarCategoriaPorIdade();
        debugPrint('📌 Categoria determinada: $categoria');

        // Busca graduações da categoria
        _graduacoes = _todasGraduacoes
            .where((g) => g['tipo_publico'] == categoria)
            .toList();

        // Filtra por idade se tiver
        if (_idadeAluno != null) {
          _graduacoes = _graduacoes.where((g) {
            final idadeMinima = g['idade_minima'] ?? 0;
            return _idadeAluno! >= idadeMinima;
          }).toList();
        }

        debugPrint('📚 Opções disponíveis: ${_graduacoes.length}');
      }
      // 🔥 CASO 2: Aluno COM graduação
      else {
        debugPrint('📌 Aluno COM graduação');

        // Separa por categoria
        final graduacoesInfantis = _todasGraduacoes
            .where((g) => g['tipo_publico'] == 'INFANTIL')
            .toList()
          ..sort((a, b) => (a['nivel_graduacao'] ?? 0).compareTo(b['nivel_graduacao'] ?? 0));

        final graduacoesAdultas = _todasGraduacoes
            .where((g) => g['tipo_publico'] == 'ADULTO')
            .toList()
          ..sort((a, b) => (a['nivel_graduacao'] ?? 0).compareTo(b['nivel_graduacao'] ?? 0));

        List<Map<String, dynamic>> resultados = [];

        // SE É INFANTIL ATUALMENTE
        if (_tipoPublicoAluno == 'INFANTIL') {
          debugPrint('📌 Aluno INFANTIL');

          // Próximas graduações INFANTIS
          final proximasInfantis = graduacoesInfantis
              .where((g) => (g['nivel_graduacao'] ?? 0) > (_nivelAtual ?? 0))
              .toList();
          resultados.addAll(proximasInfantis);
          debugPrint('   • Próximas INFANTIS: ${proximasInfantis.length}');

          // Verifica se pode mostrar ADULTAS
          bool podeMostrarAdultas = _podeMudarParaAdulto(_nivelAtual ?? 0, _idadeAluno ?? 0);

          if (podeMostrarAdultas) {
            debugPrint('   ✅ Pode mostrar ADULTAS');
            resultados.addAll(graduacoesAdultas);
          } else {
            debugPrint('   ❌ Não pode mostrar ADULTAS');
          }
        }
        // SE É ADULTO ATUALMENTE
        else {
          debugPrint('📌 Aluno ADULTO');
          final proximasAdultas = graduacoesAdultas
              .where((g) => (g['nivel_graduacao'] ?? 0) > (_nivelAtual ?? 0))
              .toList();
          resultados.addAll(proximasAdultas);
          debugPrint('   • Próximas ADULTAS: ${proximasAdultas.length}');
        }

        // Remove duplicatas e ordena
        _graduacoes = resultados.toSet().toList();
        _graduacoes.sort((a, b) {
          if (a['tipo_publico'] != b['tipo_publico']) {
            return a['tipo_publico'] == 'INFANTIL' ? -1 : 1;
          }
          return (a['nivel_graduacao'] ?? 0).compareTo(b['nivel_graduacao'] ?? 0);
        });
      }

      // Define a selecionada como a nova atual se existir
      if (widget.graduacaoNovaId != null) {
        _graduacaoSelecionada = widget.graduacaoNovaId;
      }

      debugPrint('📊 TOTAL DE OPÇÕES: ${_graduacoes.length}');

    } catch (e) {
      debugPrint('❌ Erro ao carregar graduações: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Color _getCorGraduacao(Map<String, dynamic> graduacao) {
    try {
      return Color(int.parse(graduacao['hex_cor1'].replaceFirst('#', '0xff')));
    } catch (e) {
      return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título
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
            const SizedBox(height: 16),

            const Text(
              '🎓 EDITAR GRADUAÇÃO',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
              textAlign: TextAlign.center,
            ),

            // Info do nível atual
            if (_nivelAtual != null && _nivelAtual! > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.info, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      'Nível atual: $_nivelAtual • Só pode evoluir',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Info de idade para alunos sem graduação
            if ((_nivelAtual == null || _nivelAtual == 0) && _idadeAluno != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cake, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      'Idade: $_idadeAluno anos • Categoria: ${_determinarCategoriaPorIdade()}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            if (_isLoading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_graduacoes.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        _nivelAtual != null && _nivelAtual! > 0
                            ? 'Não há graduações disponíveis acima do nível $_nivelAtual'
                            : 'Não há graduações disponíveis para este aluno',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _graduacoes.length,
                  itemBuilder: (context, index) {
                    final graduacao = _graduacoes[index];
                    final isSelected = _graduacaoSelecionada == graduacao['id'];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: isSelected ? Colors.orange : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _getCorGraduacao(graduacao),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Center(
                            child: Text(
                              graduacao['nivel_graduacao'].toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          graduacao['nome_graduacao'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Nível: ${graduacao['nivel_graduacao']}'),
                            if (graduacao['titulo_graduacao'] != null)
                              Text(
                                graduacao['titulo_graduacao'],
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            if (graduacao['idade_minima'] != null)
                              Text(
                                'Idade mínima: ${graduacao['idade_minima']} anos',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                        trailing: Radio<String>(
                          value: graduacao['id'],
                          groupValue: _graduacaoSelecionada,
                          onChanged: (value) {
                            setState(() {
                              _graduacaoSelecionada = value;
                            });
                          },
                          activeColor: Colors.orange,
                        ),
                        onTap: () {
                          setState(() {
                            _graduacaoSelecionada = graduacao['id'];
                          });
                        },
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 16),

            // Botões
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('CANCELAR'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _graduacaoSelecionada != null
                        ? () => Navigator.pop(context, _graduacaoSelecionada)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('SALVAR'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}