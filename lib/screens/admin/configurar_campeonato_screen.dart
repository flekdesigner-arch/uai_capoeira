import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/screens/eventos/campeonatos/grupos_convidados_screen.dart';

class ConfigurarCampeonatoScreen extends StatefulWidget {
  const ConfigurarCampeonatoScreen({super.key});

  @override
  State<ConfigurarCampeonatoScreen> createState() => _ConfigurarCampeonatoScreenState();
}

class _ConfigurarCampeonatoScreenState extends State<ConfigurarCampeonatoScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🔥 CONFIGURAÇÕES GERAIS
  bool _campeonatoAtivo = false;
  String _nomeCampeonato = '1° CAMPEONATO UAI CAPOEIRA';
  String _dataEvento = 'A definir';
  String _localEvento = 'A definir';
  String _horarioEvento = 'A definir';
  double _taxaInscricao = 30.0;
  int _vagasDisponiveis = 50;
  int _totalInscricoes = 0;

  // 🔥 NOVO: CONTROLE DE INSCRIÇÕES
  bool _recebendoInscricoes = true;
  DateTime? _dataInicioInscricoes;
  DateTime? _dataFimInscricoes;
  final TextEditingController _dataInicioController = TextEditingController();
  final TextEditingController _dataFimController = TextEditingController();

  // 🔥 CATEGORIAS (DINÂMICO)
  List<Map<String, dynamic>> _categorias = [
    {'id': 'infantil_a', 'nome': 'INFANTIL A', 'idade_min': 7, 'idade_max': 10, 'sexo': 'MISTO', 'taxa': 30.0, 'vagas': 10, 'ativo': true},
    {'id': 'infantil_b', 'nome': 'INFANTIL B', 'idade_min': 11, 'idade_max': 14, 'sexo': 'MISTO', 'taxa': 30.0, 'vagas': 10, 'ativo': true},
    {'id': 'adulto_fem', 'nome': 'ADULTO FEMININO', 'idade_min': 15, 'idade_max': 99, 'sexo': 'FEMININO', 'taxa': 30.0, 'vagas': 15, 'ativo': true},
    {'id': 'adulto_masc', 'nome': 'ADULTO MASCULINO', 'idade_min': 15, 'idade_max': 99, 'sexo': 'MASCULINO', 'taxa': 30.0, 'vagas': 15, 'ativo': true},
  ];

  // 🔥 TERMO DE RESPONSABILIDADE
  bool _recolherAssinatura = true;
  String _termoPersonalizado = '''
TERMO DE RESPONSABILIDADE - [NOME_CAMPEONATO]

Eu, [NOME_COMPLETO], portador do CPF [CPF], declaro para os devidos fins que:

1. **CIÊNCIA E ACEITAÇÃO**
   Estou ciente e de acordo com todas as normas estabelecidas no regulamento oficial do [NOME_CAMPEONATO], que ocorrerá no dia [DATA_EVENTO] às [HORARIO_EVENTO] no [LOCAL_EVENTO].

2. **RESPONSABILIDADE PELA INTEGRIDADE FÍSICA**
   Autorizo minha participação no evento, assumindo total responsabilidade por minha integridade física, estando ciente de que a capoeira é uma atividade que envolve movimentos corporais e que a organização preza pela segurança e não violência.

3. **ISENÇÃO DE RESPONSABILIDADE**
   Libero a organização do evento de qualquer responsabilidade por danos físicos ou materiais decorrentes da minha participação.

4. **USO DE IMAGEM**
   Autorizo o uso gratuito de minha imagem para divulgação do evento.

5. **VERACIDADE DAS INFORMAÇÕES**
   Confirmo que as informações prestadas são verdadeiras.

Data e hora: [DATA_HORA]

Assinatura: _____________________________
''';

  String _termoMenorPersonalizado = '''
TERMO DE RESPONSABILIDADE - [NOME_CAMPEONATO] (MENOR)

Eu, [NOME_RESPONSAVEL], portador do CPF [CPF_RESPONSAVEL], responsável legal por [NOME_MENOR], declaro:

1. **CIÊNCIA E ACEITAÇÃO**
   Estou ciente e de acordo com todas as normas do [NOME_CAMPEONATO], que ocorrerá no dia [DATA_EVENTO] às [HORARIO_EVENTO] no [LOCAL_EVENTO].

2. **AUTORIZAÇÃO DE PARTICIPAÇÃO**
   AUTORIZO a participação do menor no evento.

3. **ISENÇÃO DE RESPONSABILIDADE**
   Libero a organização de qualquer responsabilidade.

4. **USO DE IMAGEM**
   AUTORIZO o uso gratuito da imagem do menor.

5. **VERACIDADE DAS INFORMAÇÕES**
   Confirmo que as informações são verdadeiras.

Data e hora: [DATA_HORA]

Assinatura do Responsável: _____________________________
''';

  // 🔥 CAMPOS OPCIONAIS
  bool _exigirComprovantePagamento = false;
  bool _exigirFotoCompetidor = false;
  bool _exigirTermoAssinado = true;
  bool _permitirEditarAposEnvio = false;

  // 🔥 INFORMAÇÕES DE PAGAMENTO
  String _chavePix = '';
  String _informacoesBancarias = '';
  String _instrucoesPagamento = 'Pague via PIX e envie o comprovante.';

  // 🔥 INFORMAÇÕES EXTRAS
  String _informacoesAdicionais = 'Traga seu uniforme completo e instrumentos se possível.';

  // 🔥 REGULAMENTO (URL ou Texto)
  String _urlRegulamento = '';
  String _textoRegulamento = '';

  // Controladores
  final TextEditingController _nomeCampeonatoController = TextEditingController();
  final TextEditingController _dataEventoController = TextEditingController();
  final TextEditingController _localEventoController = TextEditingController();
  final TextEditingController _horarioEventoController = TextEditingController();
  final TextEditingController _taxaInscricaoController = TextEditingController();
  final TextEditingController _vagasDisponiveisController = TextEditingController();
  final TextEditingController _chavePixController = TextEditingController();
  final TextEditingController _informacoesBancariasController = TextEditingController();
  final TextEditingController _instrucoesPagamentoController = TextEditingController();
  final TextEditingController _informacoesAdicionaisController = TextEditingController();
  final TextEditingController _urlRegulamentoController = TextEditingController();
  final TextEditingController _textoRegulamentoController = TextEditingController();
  final TextEditingController _termoPersonalizadoController = TextEditingController();
  final TextEditingController _termoMenorPersonalizadoController = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
  }

  @override
  void dispose() {
    _nomeCampeonatoController.dispose();
    _dataEventoController.dispose();
    _localEventoController.dispose();
    _horarioEventoController.dispose();
    _taxaInscricaoController.dispose();
    _vagasDisponiveisController.dispose();
    _chavePixController.dispose();
    _informacoesBancariasController.dispose();
    _instrucoesPagamentoController.dispose();
    _informacoesAdicionaisController.dispose();
    _urlRegulamentoController.dispose();
    _textoRegulamentoController.dispose();
    _termoPersonalizadoController.dispose();
    _termoMenorPersonalizadoController.dispose();
    _dataInicioController.dispose();
    _dataFimController.dispose();
    super.dispose();
  }

  Future<void> _carregarConfiguracoes() async {
    try {
      final doc = await _firestore.collection('configuracoes').doc('campeonato').get();

      if (doc.exists) {
        final data = doc.data()!;

        setState(() {
          // 🔥 CONFIGURAÇÕES GERAIS
          _campeonatoAtivo = data['campeonato_ativo'] ?? false;
          _nomeCampeonato = data['nome_campeonato'] ?? '1° CAMPEONATO UAI CAPOEIRA';
          _dataEvento = data['data_evento'] ?? 'A definir';
          _localEvento = data['local_evento'] ?? 'A definir';
          _horarioEvento = data['horario_evento'] ?? 'A definir';
          _taxaInscricao = (data['taxa_inscricao'] ?? 30.0).toDouble();
          _vagasDisponiveis = data['vagas_disponiveis'] ?? 50;
          _totalInscricoes = data['total_inscricoes'] ?? 0;

          // 🔥 NOVO: CARREGAR DADOS DE INSCRIÇÃO
          _recebendoInscricoes = data['recebendo_inscricoes'] ?? true;

          if (data['data_inicio_inscricoes'] != null) {
            _dataInicioInscricoes = (data['data_inicio_inscricoes'] as Timestamp).toDate();
            _dataInicioController.text = DateFormat('dd/MM/yyyy').format(_dataInicioInscricoes!);
          }

          if (data['data_fim_inscricoes'] != null) {
            _dataFimInscricoes = (data['data_fim_inscricoes'] as Timestamp).toDate();
            _dataFimController.text = DateFormat('dd/MM/yyyy').format(_dataFimInscricoes!);
          }

          // 🔥 CATEGORIAS
          if (data.containsKey('categorias')) {
            _categorias = List<Map<String, dynamic>>.from(data['categorias']);
          }

          // 🔥 TERMO
          _recolherAssinatura = data['recolher_assinatura'] ?? true;
          _termoPersonalizado = data['termo_personalizado'] ?? _termoPersonalizado;
          _termoMenorPersonalizado = data['termo_menor_personalizado'] ?? _termoMenorPersonalizado;

          // 🔥 CAMPOS OPCIONAIS
          _exigirComprovantePagamento = data['exigir_comprovante_pagamento'] ?? false;
          _exigirFotoCompetidor = data['exigir_foto_competidor'] ?? false;
          _exigirTermoAssinado = data['exigir_termo_assinado'] ?? true;
          _permitirEditarAposEnvio = data['permitir_editar_apos_envio'] ?? false;

          // 🔥 PAGAMENTO
          _chavePix = data['chave_pix'] ?? '';
          _informacoesBancarias = data['informacoes_bancarias'] ?? '';
          _instrucoesPagamento = data['instrucoes_pagamento'] ?? 'Pague via PIX e envie o comprovante.';

          // 🔥 INFORMAÇÕES EXTRAS
          _informacoesAdicionais = data['informacoes_adicionais'] ?? '';

          // 🔥 REGULAMENTO
          _urlRegulamento = data['url_regulamento'] ?? '';
          _textoRegulamento = data['texto_regulamento'] ?? '';

          // Atualizar controladores
          _nomeCampeonatoController.text = _nomeCampeonato;
          _dataEventoController.text = _dataEvento;
          _localEventoController.text = _localEvento;
          _horarioEventoController.text = _horarioEvento;
          _taxaInscricaoController.text = _taxaInscricao.toString();
          _vagasDisponiveisController.text = _vagasDisponiveis.toString();
          _chavePixController.text = _chavePix;
          _informacoesBancariasController.text = _informacoesBancarias;
          _instrucoesPagamentoController.text = _instrucoesPagamento;
          _informacoesAdicionaisController.text = _informacoesAdicionais;
          _urlRegulamentoController.text = _urlRegulamento;
          _textoRegulamentoController.text = _textoRegulamento;
          _termoPersonalizadoController.text = _termoPersonalizado;
          _termoMenorPersonalizadoController.text = _termoMenorPersonalizado;
        });
      }

      // Carrega total atual de inscrições do campeonato
      final inscricoesSnapshot = await _firestore
          .collection('campeonato_inscricoes')
          .get();

      setState(() {
        _totalInscricoes = inscricoesSnapshot.docs.length;
        _carregando = false;
      });

    } catch (e) {
      _mostrarErro('Erro ao carregar: $e');
      setState(() => _carregando = false);
    }
  }

  Future<void> _salvarConfiguracoes() async {
    setState(() => _salvando = true);

    try {
      final taxa = double.tryParse(_taxaInscricaoController.text) ?? 30.0;
      final vagas = int.tryParse(_vagasDisponiveisController.text) ?? 50;

      Map<String, dynamic> config = {
        // 🔥 GERAIS
        'campeonato_ativo': _campeonatoAtivo,
        'nome_campeonato': _nomeCampeonatoController.text.trim().toUpperCase(),
        'data_evento': _dataEventoController.text.trim().toUpperCase(),
        'local_evento': _localEventoController.text.trim().toUpperCase(),
        'horario_evento': _horarioEventoController.text.trim().toUpperCase(),
        'taxa_inscricao': taxa,
        'vagas_disponiveis': vagas,
        'total_inscricoes': _totalInscricoes,

        // 🔥 NOVO: DADOS DE INSCRIÇÃO
        'recebendo_inscricoes': _recebendoInscricoes,
        'data_inicio_inscricoes': _dataInicioInscricoes != null
            ? Timestamp.fromDate(_dataInicioInscricoes!)
            : null,
        'data_fim_inscricoes': _dataFimInscricoes != null
            ? Timestamp.fromDate(_dataFimInscricoes!)
            : null,

        // 🔥 CATEGORIAS
        'categorias': _categorias,

        // 🔥 TERMO
        'recolher_assinatura': _recolherAssinatura,
        'termo_personalizado': _termoPersonalizadoController.text,
        'termo_menor_personalizado': _termoMenorPersonalizadoController.text,

        // 🔥 CAMPOS OPCIONAIS
        'exigir_comprovante_pagamento': _exigirComprovantePagamento,
        'exigir_foto_competidor': _exigirFotoCompetidor,
        'exigir_termo_assinado': _exigirTermoAssinado,
        'permitir_editar_apos_envio': _permitirEditarAposEnvio,

        // 🔥 PAGAMENTO
        'chave_pix': _chavePixController.text.trim(),
        'informacoes_bancarias': _informacoesBancariasController.text.trim(),
        'instrucoes_pagamento': _instrucoesPagamentoController.text.trim(),

        // 🔥 INFORMAÇÕES EXTRAS
        'informacoes_adicionais': _informacoesAdicionaisController.text.trim(),

        // 🔥 REGULAMENTO
        'url_regulamento': _urlRegulamentoController.text.trim(),
        'texto_regulamento': _textoRegulamentoController.text.trim(),

        'ultima_atualizacao': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('configuracoes').doc('campeonato').set(config);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Configurações do campeonato salvas!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _mostrarErro('Erro ao salvar: $e');
    } finally {
      setState(() => _salvando = false);
    }
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), backgroundColor: Colors.red),
    );
  }

  Future<void> _selecionarData(
      BuildContext context,
      TextEditingController controller,
      Function(DateTime) onSelected
      ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('pt', 'BR'),
    );

    if (picked != null) {
      setState(() {
        controller.text = DateFormat('dd/MM/yyyy').format(picked);
        onSelected(picked);
      });
    }
  }

  // ==================== FUNÇÕES DE CATEGORIA ====================

  void _criarCategoria() {
    String novoId = 'cat_${DateTime.now().millisecondsSinceEpoch}';
    final nomeController = TextEditingController();
    final idadeMinController = TextEditingController(text: '0');
    final idadeMaxController = TextEditingController(text: '0');
    final taxaController = TextEditingController(text: '30.0');
    final vagasController = TextEditingController(text: '10');
    String sexoSelecionado = 'MISTO';
    bool ativo = true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('➕ Nova Categoria'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nomeController,
                      decoration: const InputDecoration(
                        labelText: 'Nome da Categoria',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: idadeMinController,
                            decoration: const InputDecoration(
                              labelText: 'Idade Mínima',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: idadeMaxController,
                            decoration: const InputDecoration(
                              labelText: 'Idade Máxima',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: sexoSelecionado,
                      items: const [
                        DropdownMenuItem(value: 'MISTO', child: Text('MISTO')),
                        DropdownMenuItem(value: 'MASCULINO', child: Text('MASCULINO')),
                        DropdownMenuItem(value: 'FEMININO', child: Text('FEMININO')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() {
                            sexoSelecionado = v;
                          });
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Sexo',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: taxaController,
                            decoration: const InputDecoration(
                              labelText: 'Taxa (R\$)',
                              border: OutlineInputBorder(),
                              prefixText: 'R\$ ',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: vagasController,
                            decoration: const InputDecoration(
                              labelText: 'Vagas',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Categoria Ativa'),
                      value: ativo,
                      onChanged: (v) {
                        setDialogState(() {
                          ativo = v;
                        });
                      },
                      activeColor: Colors.green,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCELAR'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (nomeController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('O nome da categoria é obrigatório'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    setState(() {
                      _categorias.add({
                        'id': novoId,
                        'nome': nomeController.text.toUpperCase(),
                        'idade_min': int.tryParse(idadeMinController.text) ?? 0,
                        'idade_max': int.tryParse(idadeMaxController.text) ?? 0,
                        'sexo': sexoSelecionado,
                        'taxa': double.tryParse(taxaController.text) ?? 30.0,
                        'vagas': int.tryParse(vagasController.text) ?? 10,
                        'ativo': ativo,
                      });
                    });
                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✅ Categoria "${nomeController.text}" criada!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('CRIAR'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _editarCategoria(int index) {
    final categoria = _categorias[index];

    showDialog(
      context: context,
      builder: (context) {
        final nomeController = TextEditingController(text: categoria['nome']);
        final idadeMinController = TextEditingController(text: categoria['idade_min'].toString());
        final idadeMaxController = TextEditingController(text: categoria['idade_max'].toString());
        final taxaController = TextEditingController(text: categoria['taxa'].toString());
        final vagasController = TextEditingController(text: categoria['vagas'].toString());
        String sexoSelecionado = categoria['sexo'] ?? 'MISTO';
        bool ativo = categoria['ativo'] ?? true;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('✏️ Editar ${categoria['nome']}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nomeController,
                      decoration: const InputDecoration(
                        labelText: 'Nome da Categoria',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: idadeMinController,
                            decoration: const InputDecoration(
                              labelText: 'Idade Mínima',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: idadeMaxController,
                            decoration: const InputDecoration(
                              labelText: 'Idade Máxima',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: sexoSelecionado,
                      items: const [
                        DropdownMenuItem(value: 'MISTO', child: Text('MISTO')),
                        DropdownMenuItem(value: 'MASCULINO', child: Text('MASCULINO')),
                        DropdownMenuItem(value: 'FEMININO', child: Text('FEMININO')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() {
                            sexoSelecionado = v;
                          });
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Sexo',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: taxaController,
                            decoration: const InputDecoration(
                              labelText: 'Taxa (R\$)',
                              border: OutlineInputBorder(),
                              prefixText: 'R\$ ',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: vagasController,
                            decoration: const InputDecoration(
                              labelText: 'Vagas',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Categoria Ativa'),
                      value: ativo,
                      onChanged: (v) {
                        setDialogState(() {
                          ativo = v;
                        });
                      },
                      activeColor: Colors.green,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _confirmarExcluirCategoria(index);
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('EXCLUIR'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCELAR'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (nomeController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('O nome da categoria é obrigatório'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    setState(() {
                      _categorias[index] = {
                        'id': categoria['id'],
                        'nome': nomeController.text.toUpperCase(),
                        'idade_min': int.tryParse(idadeMinController.text) ?? 0,
                        'idade_max': int.tryParse(idadeMaxController.text) ?? 0,
                        'sexo': sexoSelecionado,
                        'taxa': double.tryParse(taxaController.text) ?? 30.0,
                        'vagas': int.tryParse(vagasController.text) ?? 0,
                        'ativo': ativo,
                      };
                    });
                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✅ Categoria "${nomeController.text}" atualizada!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('SALVAR'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmarExcluirCategoria(int index) {
    final categoria = _categorias[index];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('⚠️ Confirmar Exclusão'),
          content: Text(
            'Tem certeza que deseja excluir a categoria "${categoria['nome']}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _categorias.removeAt(index);
                });
                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ Categoria "${categoria['nome']}" excluída!'),
                    backgroundColor: Colors.orange,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('EXCLUIR'),
            ),
          ],
        );
      },
    );
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('🏆 Configurar Campeonato'),
        backgroundColor: Colors.amber.shade900,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _salvando ? null : _salvarConfiguracoes,
            icon: _salvando
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
                : const Icon(Icons.save, color: Colors.white),
            label: Text(
              _salvando ? 'SALVANDO...' : 'SALVAR',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 🔥 CARD PRINCIPAL - ATIVAR/DESATIVAR CAMPEONATO
          _buildCardAtivarCampeonato(),
          const SizedBox(height: 16),

          // 🔥 NOVO CARD: CONTROLE DE INSCRIÇÕES
          _buildCardControleInscricoes(),
          const SizedBox(height: 16),

          // 🔥 CARD INFORMAÇÕES GERAIS
          _buildCardInformacoesGerais(),
          const SizedBox(height: 16),

          // 🔥 CARD CATEGORIAS
          _buildCardCategorias(),
          const SizedBox(height: 16),

          // 🔥 CARD CONTROLE DE VAGAS
          _buildCardVagas(),
          const SizedBox(height: 16),

          // 🔥 CARD TERMO E ASSINATURA
          _buildCardTermo(),
          const SizedBox(height: 16),

          // 🔥 CARD CAMPOS OPCIONAIS
          _buildCardCamposOpcionais(),
          const SizedBox(height: 16),

          // 🔥 CARD PAGAMENTO
          _buildCardPagamento(),
          const SizedBox(height: 16),

          // 🔥 CARD REGULAMENTO
          _buildCardRegulamento(),
          const SizedBox(height: 16),

          // 🔥 CARD INFORMAÇÕES ADICIONAIS
          _buildCardInfoAdicionais(),
          const SizedBox(height: 24),

          // 🔥 RESUMO DAS CONFIGURAÇÕES
          _buildResumoConfiguracoes(),
          const SizedBox(height: 16),

          // 🔥 BOTÃO GRUPOS CONVIDADOS
          _buildBotaoGrupos(),
        ],
      ),
    );
  }

  // ==================== CARDS ====================

  Widget _buildCardAtivarCampeonato() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _campeonatoAtivo ? Colors.green.shade50 : Colors.red.shade50,
              Colors.white,
            ],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SwitchListTile(
                title: Row(
                  children: [
                    Icon(
                      _campeonatoAtivo ? Icons.toggle_on : Icons.toggle_off,
                      color: _campeonatoAtivo ? Colors.green : Colors.red,
                      size: 32,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'CAMPEONATO ATIVO',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                subtitle: Text(
                  _campeonatoAtivo
                      ? '✅ Visível no site - inscrições abertas'
                      : '❌ Oculto no site - inscrições fechadas',
                  style: TextStyle(
                    color: _campeonatoAtivo ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                value: _campeonatoAtivo,
                onChanged: (value) => setState(() => _campeonatoAtivo = value),
                activeColor: Colors.green,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardControleInscricoes() {
    final hoje = DateTime.now();
    bool dentroDoPeriodo = true;
    String mensagemPeriodo = '';

    if (_dataInicioInscricoes != null && _dataFimInscricoes != null) {
      if (hoje.isBefore(_dataInicioInscricoes!)) {
        dentroDoPeriodo = false;
        mensagemPeriodo = '⏳ Período de inscrições começa em ${DateFormat('dd/MM/yyyy').format(_dataInicioInscricoes!)}';
      } else if (hoje.isAfter(_dataFimInscricoes!)) {
        dentroDoPeriodo = false;
        mensagemPeriodo = '⌛ Período de inscrições encerrado em ${DateFormat('dd/MM/yyyy').format(_dataFimInscricoes!)}';
      } else {
        mensagemPeriodo = '✅ Período de inscrições ATIVO';
      }
    }

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_available, color: Colors.teal.shade900),
                const SizedBox(width: 8),
                const Text(
                  '📅 CONTROLE DE INSCRIÇÕES',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            SwitchListTile(
              title: const Text('Recebendo Inscrições'),
              subtitle: Text(
                _recebendoInscricoes
                    ? '✅ Inscrições estão abertas manualmente'
                    : '❌ Inscrições fechadas manualmente',
              ),
              value: _recebendoInscricoes,
              onChanged: (value) => setState(() => _recebendoInscricoes = value),
              activeColor: Colors.teal,
            ),

            const Divider(height: 24),

            const Text(
              'Período de Inscrições',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _dataInicioController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Data Início',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      suffixIcon: Icon(Icons.calendar_today, color: Colors.teal.shade700),
                    ),
                    onTap: () => _selecionarData(
                      context,
                      _dataInicioController,
                          (date) => _dataInicioInscricoes = date,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _dataFimController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Data Fim',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      suffixIcon: Icon(Icons.calendar_today, color: Colors.teal.shade700),
                    ),
                    onTap: () => _selecionarData(
                      context,
                      _dataFimController,
                          (date) => _dataFimInscricoes = date,
                    ),
                  ),
                ),
              ],
            ),

            if (_dataInicioInscricoes != null && _dataFimInscricoes != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: dentroDoPeriodo ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: dentroDoPeriodo ? Colors.green.shade200 : Colors.orange.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      dentroDoPeriodo ? Icons.check_circle : Icons.info,
                      color: dentroDoPeriodo ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        mensagemPeriodo,
                        style: TextStyle(
                          color: dentroDoPeriodo ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.w500,
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
    );
  }

  Widget _buildCardInformacoesGerais() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info, color: Colors.blue.shade900),
                const SizedBox(width: 8),
                const Text(
                  'INFORMAÇÕES GERAIS',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nomeCampeonatoController,
              decoration: const InputDecoration(
                labelText: 'Nome do Campeonato',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.emoji_events),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dataEventoController,
                    decoration: const InputDecoration(
                      labelText: 'Data do Evento',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today),
                      hintText: 'Ex: 15 de junho de 2025',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _horarioEventoController,
                    decoration: const InputDecoration(
                      labelText: 'Horário',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.access_time),
                      hintText: 'Ex: 09:00h',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _localEventoController,
              decoration: const InputDecoration(
                labelText: 'Local do Evento',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardCategorias() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.category, color: Colors.purple.shade900),
                    const SizedBox(width: 8),
                    const Text(
                      'CATEGORIAS',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.green, size: 28),
                  onPressed: _criarCategoria,
                  tooltip: 'Criar nova categoria',
                ),
              ],
            ),
            const SizedBox(height: 8),
            _categorias.isEmpty
                ? Container(
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(Icons.category_outlined, size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(
                    'Nenhuma categoria cadastrada',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Clique no + para adicionar',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            )
                : Column(
              children: _categorias.asMap().entries.map((entry) {
                final index = entry.key;
                final cat = entry.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: cat['ativo'] == true ? Colors.grey.shade50 : Colors.grey.shade200,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: cat['ativo'] == true ? Colors.purple : Colors.grey,
                      child: Text(
                        cat['nome'].substring(0, 1),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    title: Text(
                      cat['nome'],
                      style: TextStyle(
                        decoration: cat['ativo'] == true ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    subtitle: Text(
                      '${cat['idade_min']}-${cat['idade_max']} anos • ${cat['sexo']} • R\$ ${cat['taxa'].toStringAsFixed(2)} • ${cat['vagas']} vagas',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _editarCategoria(index),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardVagas() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people, color: Colors.orange.shade900),
                const SizedBox(width: 8),
                const Text(
                  'CONTROLE DE VAGAS',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _taxaInscricaoController,
                    decoration: const InputDecoration(
                      labelText: 'Taxa (R\$)',
                      border: OutlineInputBorder(),
                      prefixText: 'R\$ ',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _vagasDisponiveisController,
                    decoration: const InputDecoration(
                      labelText: 'Vagas Totais',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$_totalInscricoes',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      const Text(
                        'Inscritos',
                        style: TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardTermo() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.draw, color: Colors.teal.shade900),
                const SizedBox(width: 8),
                const Text(
                  'TERMO E ASSINATURA',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Recolher Assinatura Digital'),
              subtitle: Text(
                _recolherAssinatura
                    ? '✅ Usuário precisará assinar'
                    : '❌ Sem assinatura digital',
              ),
              value: _recolherAssinatura,
              onChanged: (v) => setState(() => _recolherAssinatura = v),
              activeColor: Colors.teal,
            ),
            const SizedBox(height: 8),
            const Text(
              'Termo para MAIORES de idade (com CPF):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _termoPersonalizadoController,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Digite o termo para maiores...',
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Termo para MENORES de idade (com CPF do responsável):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _termoMenorPersonalizadoController,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Digite o termo para menores...',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardCamposOpcionais() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_box, color: Colors.green.shade900),
                const SizedBox(width: 8),
                const Text(
                  'CAMPOS OPCIONAIS',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              title: const Text('Exigir comprovante de pagamento'),
              value: _exigirComprovantePagamento,
              onChanged: (v) => setState(() => _exigirComprovantePagamento = v ?? false),
            ),
            CheckboxListTile(
              title: const Text('Exigir foto do competidor'),
              subtitle: const Text('Obrigatório upload da foto na inscrição'),
              value: _exigirFotoCompetidor,
              onChanged: (v) => setState(() => _exigirFotoCompetidor = v ?? false),
            ),
            CheckboxListTile(
              title: const Text('Permitir edição após envio'),
              value: _permitirEditarAposEnvio,
              onChanged: (v) => setState(() => _permitirEditarAposEnvio = v ?? false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardPagamento() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pix, color: Colors.green.shade900),
                const SizedBox(width: 8),
                const Text(
                  'PAGAMENTO',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _chavePixController,
              decoration: const InputDecoration(
                labelText: 'Chave PIX',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _informacoesBancariasController,
              decoration: const InputDecoration(
                labelText: 'Informações Bancárias',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.account_balance),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _instrucoesPagamentoController,
              decoration: const InputDecoration(
                labelText: 'Instruções de Pagamento',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardRegulamento() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.gavel, color: Colors.brown.shade900),
                const SizedBox(width: 8),
                const Text(
                  'REGULAMENTO',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlRegulamentoController,
              decoration: const InputDecoration(
                labelText: 'URL do Regulamento (opcional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 12),
            const Text('OU'),
            const SizedBox(height: 12),
            TextField(
              controller: _textoRegulamentoController,
              decoration: const InputDecoration(
                labelText: 'Texto do Regulamento',
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardInfoAdicionais() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade900),
                const SizedBox(width: 8),
                const Text(
                  'INFORMAÇÕES ADICIONAIS',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _informacoesAdicionaisController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumoConfiguracoes() {
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              '📋 RESUMO DAS CONFIGURAÇÕES',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            _buildResumoLinha(
                'Status',
                _campeonatoAtivo ? 'ATIVO' : 'INATIVO',
                _campeonatoAtivo ? Colors.green : Colors.red
            ),
            _buildResumoLinha(
              'Inscrições',
              _recebendoInscricoes ? 'ABERTAS' : 'FECHADAS',
              _recebendoInscricoes ? Colors.teal : Colors.orange,
            ),
            if (_dataInicioInscricoes != null && _dataFimInscricoes != null) ...[
              _buildResumoLinha(
                'Período',
                '${DateFormat('dd/MM').format(_dataInicioInscricoes!)} a ${DateFormat('dd/MM/yyyy').format(_dataFimInscricoes!)}',
                Colors.teal,
              ),
            ],
            _buildResumoLinha('Evento', _nomeCampeonatoController.text, Colors.amber.shade900),
            _buildResumoLinha('Data', _dataEventoController.text, Colors.blue),
            _buildResumoLinha('Taxa', 'R\$ ${_taxaInscricaoController.text}', Colors.green),
            _buildResumoLinha(
                'Vagas',
                '${_vagasDisponiveisController.text} (${_totalInscricoes} inscritos)',
                Colors.purple
            ),
            _buildResumoLinha('Assinatura', _recolherAssinatura ? 'SIM' : 'NÃO', Colors.teal),
            _buildResumoLinha('Exigir Foto', _exigirFotoCompetidor ? 'SIM' : 'NÃO', Colors.orange),
            _buildResumoLinha('Categorias', '${_categorias.length} ativas', Colors.orange),
          ],
        ),
      ),
    );
  }

  Widget _buildResumoLinha(String label, String valor, Color cor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: cor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              valor,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotaoGrupos() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const GruposConvidadosScreen(),
            ),
          );
        },
        icon: const Icon(Icons.group),
        label: const Text('GERENCIAR GRUPOS CONVIDADOS'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple.shade700,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}