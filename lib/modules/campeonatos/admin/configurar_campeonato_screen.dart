import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/campeonatos/screens/grupos_convidados_screen.dart';

class ConfigurarCampeonatoScreen extends StatefulWidget {
  const ConfigurarCampeonatoScreen({super.key});

  @override
  State<ConfigurarCampeonatoScreen> createState() => _ConfigurarCampeonatoScreenState();
}

class _ConfigurarCampeonatoScreenState extends State<ConfigurarCampeonatoScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _campeonatoAtivo = false;
  String _nomeCampeonato = '1° CAMPEONATO UAI CAPOEIRA';
  String _dataEvento = 'A definir';
  String _localEvento = 'A definir';
  String _horarioEvento = 'A definir';
  double _taxaInscricao = 30.0;
  int _vagasDisponiveis = 50;
  int _totalInscricoes = 0;

  bool _recebendoInscricoes = true;
  DateTime? _dataInicioInscricoes;
  DateTime? _dataFimInscricoes;
  final TextEditingController _dataInicioController = TextEditingController();
  final TextEditingController _dataFimController = TextEditingController();

  List<Map<String, dynamic>> _categorias = [
    {'id': 'infantil_a', 'nome': 'INFANTIL A', 'idade_min': 7, 'idade_max': 10, 'sexo': 'MISTO', 'taxa': 30.0, 'vagas': 10, 'ativo': true},
    {'id': 'infantil_b', 'nome': 'INFANTIL B', 'idade_min': 11, 'idade_max': 14, 'sexo': 'MISTO', 'taxa': 30.0, 'vagas': 10, 'ativo': true},
    {'id': 'adulto_fem', 'nome': 'ADULTO FEMININO', 'idade_min': 15, 'idade_max': 99, 'sexo': 'FEMININO', 'taxa': 30.0, 'vagas': 15, 'ativo': true},
    {'id': 'adulto_masc', 'nome': 'ADULTO MASCULINO', 'idade_min': 15, 'idade_max': 99, 'sexo': 'MASCULINO', 'taxa': 30.0, 'vagas': 15, 'ativo': true},
  ];

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

  bool _exigirComprovantePagamento = false;
  bool _exigirFotoCompetidor = false;
  bool _exigirTermoAssinado = true;
  bool _permitirEditarAposEnvio = false;

  String _chavePix = '';
  String _informacoesBancarias = '';
  String _instrucoesPagamento = 'Pague via PIX e envie o comprovante.';
  String _informacoesAdicionais = 'Traga seu uniforme completo e instrumentos se possível.';
  String _urlRegulamento = '';
  String _textoRegulamento = '';

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

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _onPrimary() => _readableOn(context.uai.primary);

  double get _percentualVagas {
    final vagas = int.tryParse(_vagasDisponiveisController.text) ?? _vagasDisponiveis;
    if (vagas <= 0) return 0;
    return (_totalInscricoes / vagas).clamp(0.0, 1.0);
  }

  int get _categoriasAtivas => _categorias.where((e) => e['ativo'] == true).length;

  void _sincronizarControllers() {
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
  }

  Future<void> _carregarConfiguracoes() async {
    try {
      final doc = await _firestore.collection('configuracoes').doc('campeonato').get();

      if (doc.exists) {
        final data = doc.data()!;

        _campeonatoAtivo = data['campeonato_ativo'] ?? false;
        _nomeCampeonato = data['nome_campeonato'] ?? '1° CAMPEONATO UAI CAPOEIRA';
        _dataEvento = data['data_evento'] ?? 'A definir';
        _localEvento = data['local_evento'] ?? 'A definir';
        _horarioEvento = data['horario_evento'] ?? 'A definir';
        _taxaInscricao = (data['taxa_inscricao'] ?? 30.0).toDouble();
        _vagasDisponiveis = data['vagas_disponiveis'] ?? 50;
        _totalInscricoes = data['total_inscricoes'] ?? 0;
        _recebendoInscricoes = data['recebendo_inscricoes'] ?? true;

        if (data['data_inicio_inscricoes'] != null) {
          _dataInicioInscricoes = (data['data_inicio_inscricoes'] as Timestamp).toDate();
          _dataInicioController.text = DateFormat('dd/MM/yyyy').format(_dataInicioInscricoes!);
        }

        if (data['data_fim_inscricoes'] != null) {
          _dataFimInscricoes = (data['data_fim_inscricoes'] as Timestamp).toDate();
          _dataFimController.text = DateFormat('dd/MM/yyyy').format(_dataFimInscricoes!);
        }

        if (data.containsKey('categorias')) {
          _categorias = List<Map<String, dynamic>>.from(data['categorias']);
        }

        _recolherAssinatura = data['recolher_assinatura'] ?? true;
        _termoPersonalizado = data['termo_personalizado'] ?? _termoPersonalizado;
        _termoMenorPersonalizado = data['termo_menor_personalizado'] ?? _termoMenorPersonalizado;
        _exigirComprovantePagamento = data['exigir_comprovante_pagamento'] ?? false;
        _exigirFotoCompetidor = data['exigir_foto_competidor'] ?? false;
        _exigirTermoAssinado = data['exigir_termo_assinado'] ?? true;
        _permitirEditarAposEnvio = data['permitir_editar_apos_envio'] ?? false;
        _chavePix = data['chave_pix'] ?? '';
        _informacoesBancarias = data['informacoes_bancarias'] ?? '';
        _instrucoesPagamento = data['instrucoes_pagamento'] ?? 'Pague via PIX e envie o comprovante.';
        _informacoesAdicionais = data['informacoes_adicionais'] ?? '';
        _urlRegulamento = data['url_regulamento'] ?? '';
        _textoRegulamento = data['texto_regulamento'] ?? '';
      }

      final inscricoesSnapshot = await _firestore.collection('campeonato_inscricoes').get();
      _totalInscricoes = inscricoesSnapshot.docs.length;
      _sincronizarControllers();

      if (mounted) setState(() => _carregando = false);
    } catch (e) {
      _mostrarErro('Erro ao carregar: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvarConfiguracoes() async {
    if (!mounted) return;
    setState(() => _salvando = true);

    try {
      final taxa = double.tryParse(_taxaInscricaoController.text.replaceAll(',', '.')) ?? 30.0;
      final vagas = int.tryParse(_vagasDisponiveisController.text) ?? 50;

      final config = <String, dynamic>{
        'campeonato_ativo': _campeonatoAtivo,
        'nome_campeonato': _nomeCampeonatoController.text.trim().toUpperCase(),
        'data_evento': _dataEventoController.text.trim().toUpperCase(),
        'local_evento': _localEventoController.text.trim().toUpperCase(),
        'horario_evento': _horarioEventoController.text.trim().toUpperCase(),
        'taxa_inscricao': taxa,
        'vagas_disponiveis': vagas,
        'total_inscricoes': _totalInscricoes,
        'recebendo_inscricoes': _recebendoInscricoes,
        'data_inicio_inscricoes': _dataInicioInscricoes != null ? Timestamp.fromDate(_dataInicioInscricoes!) : null,
        'data_fim_inscricoes': _dataFimInscricoes != null ? Timestamp.fromDate(_dataFimInscricoes!) : null,
        'categorias': _categorias,
        'recolher_assinatura': _recolherAssinatura,
        'termo_personalizado': _termoPersonalizadoController.text,
        'termo_menor_personalizado': _termoMenorPersonalizadoController.text,
        'exigir_comprovante_pagamento': _exigirComprovantePagamento,
        'exigir_foto_competidor': _exigirFotoCompetidor,
        'exigir_termo_assinado': _exigirTermoAssinado,
        'permitir_editar_apos_envio': _permitirEditarAposEnvio,
        'chave_pix': _chavePixController.text.trim(),
        'informacoes_bancarias': _informacoesBancariasController.text.trim(),
        'instrucoes_pagamento': _instrucoesPagamentoController.text.trim(),
        'informacoes_adicionais': _informacoesAdicionaisController.text.trim(),
        'url_regulamento': _urlRegulamentoController.text.trim(),
        'texto_regulamento': _textoRegulamentoController.text.trim(),
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('configuracoes').doc('campeonato').set(config);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ Configurações do campeonato salvas!'),
          backgroundColor: context.uai.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      _mostrarErro('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: context.uai.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _selecionarData(
      BuildContext context,
      TextEditingController controller,
      Function(DateTime) onSelected,
      ) async {
    final picked = await showDatePicker(
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

  void _criarCategoria() {
    final novoId = 'cat_${DateTime.now().millisecondsSinceEpoch}';
    _abrirDialogCategoria(
      titulo: 'Nova categoria',
      textoBotao: 'CRIAR',
      onSalvar: (dados) {
        setState(() {
          _categorias.add({'id': novoId, ...dados});
        });
        _mostrarSnack('✅ Categoria "${dados['nome']}" criada!', context.uai.success);
      },
    );
  }

  void _editarCategoria(int index) {
    final categoria = _categorias[index];
    _abrirDialogCategoria(
      titulo: 'Editar ${categoria['nome']}',
      textoBotao: 'SALVAR',
      categoria: categoria,
      onExcluir: () {
        Navigator.pop(context);
        _confirmarExcluirCategoria(index);
      },
      onSalvar: (dados) {
        setState(() {
          _categorias[index] = {'id': categoria['id'], ...dados};
        });
        _mostrarSnack('✅ Categoria "${dados['nome']}" atualizada!', context.uai.success);
      },
    );
  }

  void _abrirDialogCategoria({
    required String titulo,
    required String textoBotao,
    Map<String, dynamic>? categoria,
    VoidCallback? onExcluir,
    required ValueChanged<Map<String, dynamic>> onSalvar,
  }) {
    final nomeController = TextEditingController(text: categoria?['nome']?.toString() ?? '');
    final idadeMinController = TextEditingController(text: (categoria?['idade_min'] ?? 0).toString());
    final idadeMaxController = TextEditingController(text: (categoria?['idade_max'] ?? 0).toString());
    final taxaController = TextEditingController(text: (categoria?['taxa'] ?? 30.0).toString());
    final vagasController = TextEditingController(text: (categoria?['vagas'] ?? 10).toString());
    String sexoSelecionado = categoria?['sexo']?.toString() ?? 'MISTO';
    bool ativo = categoria?['ativo'] ?? true;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final t = context.uai;
            final accent = _ensureVisible(t.warning, t.surface);

            return Dialog(
              insetPadding: const EdgeInsets.all(14),
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 560),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(t.cardRadius + 2),
                  border: Border.all(color: t.border),
                  boxShadow: t.cardShadow,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _dialogHandle(),
                      const SizedBox(height: 16),
                      _sectionHeader(
                        icon: categoria == null ? Icons.add_circle_rounded : Icons.edit_rounded,
                        title: titulo,
                        subtitle: 'Informe categoria, idade, sexo, taxa e vagas.',
                        color: accent,
                      ),
                      const SizedBox(height: 16),
                      _textField(nomeController, 'Nome da categoria', Icons.category_rounded),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 430;
                          final fields = [
                            _textField(idadeMinController, 'Idade mínima', Icons.child_care_rounded, keyboardType: TextInputType.number),
                            _textField(idadeMaxController, 'Idade máxima', Icons.elderly_rounded, keyboardType: TextInputType.number),
                          ];
                          return narrow
                              ? Column(children: [fields[0], const SizedBox(height: 12), fields[1]])
                              : Row(children: [Expanded(child: fields[0]), const SizedBox(width: 10), Expanded(child: fields[1])]);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: sexoSelecionado,
                        dropdownColor: t.surface,
                        style: TextStyle(color: t.textPrimary),
                        items: const [
                          DropdownMenuItem(value: 'MISTO', child: Text('MISTO')),
                          DropdownMenuItem(value: 'MASCULINO', child: Text('MASCULINO')),
                          DropdownMenuItem(value: 'FEMININO', child: Text('FEMININO')),
                        ],
                        onChanged: (v) {
                          if (v != null) setDialogState(() => sexoSelecionado = v);
                        },
                        decoration: _inputDecoration('Sexo', Icons.wc_rounded),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 430;
                          final fields = [
                            _textField(taxaController, 'Taxa (R\$)', Icons.payments_rounded, keyboardType: TextInputType.number, prefixText: 'R\$ '),
                            _textField(vagasController, 'Vagas', Icons.event_seat_rounded, keyboardType: TextInputType.number),
                          ];
                          return narrow
                              ? Column(children: [fields[0], const SizedBox(height: 12), fields[1]])
                              : Row(children: [Expanded(child: fields[0]), const SizedBox(width: 10), Expanded(child: fields[1])]);
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Categoria ativa', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800)),
                        subtitle: Text('Define se aparece no formulário público.', style: TextStyle(color: t.textSecondary)),
                        value: ativo,
                        activeColor: t.success,
                        onChanged: (v) => setDialogState(() => ativo = v),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          if (onExcluir != null) ...[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: onExcluir,
                                icon: const Icon(Icons.delete_rounded),
                                label: const Text('EXCLUIR'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: t.error,
                                  side: BorderSide(color: t.error.withOpacity(0.34)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('CANCELAR'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                final nome = nomeController.text.trim().toUpperCase();
                                if (nome.isEmpty) {
                                  _mostrarErro('O nome da categoria é obrigatório');
                                  return;
                                }
                                onSalvar({
                                  'nome': nome,
                                  'idade_min': int.tryParse(idadeMinController.text) ?? 0,
                                  'idade_max': int.tryParse(idadeMaxController.text) ?? 0,
                                  'sexo': sexoSelecionado,
                                  'taxa': double.tryParse(taxaController.text.replaceAll(',', '.')) ?? 30.0,
                                  'vagas': int.tryParse(vagasController.text) ?? 0,
                                  'ativo': ativo,
                                });
                                Navigator.pop(dialogContext);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: t.success,
                                foregroundColor: _readableOn(t.success),
                              ),
                              child: Text(textoBotao),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmarExcluirCategoria(int index) {
    final categoria = _categorias[index];
    final t = context.uai;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: t.surface,
        insetPadding: const EdgeInsets.all(18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.cardRadius)),
        title: Row(
          children: [
            Icon(Icons.warning_rounded, color: t.error),
            const SizedBox(width: 8),
            Expanded(child: Text('Confirmar exclusão', style: TextStyle(color: t.textPrimary))),
          ],
        ),
        content: Text(
          'Tem certeza que deseja excluir a categoria "${categoria['nome']}"?',
          style: TextStyle(color: t.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          ElevatedButton(
            onPressed: () {
              setState(() => _categorias.removeAt(index));
              Navigator.pop(context);
              _mostrarSnack('Categoria removida.', t.warning);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: t.error,
              foregroundColor: _readableOn(t.error),
            ),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );
  }

  void _mostrarSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    if (_carregando) {
      return Scaffold(
        backgroundColor: t.background,
        body: Center(child: CircularProgressIndicator(color: t.primary)),
      );
    }

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Configurar Campeonato'),
        actions: [
          IconButton(
            tooltip: 'Salvar',
            onPressed: _salvando ? null : _salvarConfiguracoes,
            icon: _salvando
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: _onPrimary(), strokeWidth: 2),
            )
                : const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: t.primary,
        backgroundColor: t.surface,
        onRefresh: _carregarConfiguracoes,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 108),
              children: [
                _buildHero(),
                const SizedBox(height: 14),
                _buildQuickStats(),
                const SizedBox(height: 14),
                _buildCardAtivarCampeonato(),
                const SizedBox(height: 14),
                _buildCardControleInscricoes(),
                const SizedBox(height: 14),
                _buildCardInformacoesGerais(),
                const SizedBox(height: 14),
                _buildCardCategorias(),
                const SizedBox(height: 14),
                _buildCardVagas(),
                const SizedBox(height: 14),
                _buildCardTermo(),
                const SizedBox(height: 14),
                _buildCardCamposOpcionais(),
                const SizedBox(height: 14),
                _buildCardPagamento(),
                const SizedBox(height: 14),
                _buildCardRegulamento(),
                const SizedBox(height: 14),
                _buildCardInfoAdicionais(),
                const SizedBox(height: 18),
                _buildResumoConfiguracoes(),
                const SizedBox(height: 14),
                _buildBotaoGrupos(),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border(top: BorderSide(color: t.border)),
            boxShadow: t.softShadow,
          ),
          child: ElevatedButton.icon(
            onPressed: _salvando ? null : _salvarConfiguracoes,
            icon: _salvando
                ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(color: _readableOn(t.primary), strokeWidth: 2),
            )
                : const Icon(Icons.save_rounded),
            label: Text(_salvando ? 'SALVANDO...' : 'SALVAR CAMPEONATO'),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: _readableOn(t.primary),
              minimumSize: const Size.fromHeight(50),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.buttonRadius)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    final t = context.uai;
    final onPrimary = _onPrimary();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          final icon = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(Icons.emoji_events_rounded, color: onPrimary, size: 34),
          );

          final text = Column(
            crossAxisAlignment: narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Campeonato UAI Capoeira',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(color: onPrimary, fontSize: narrow ? 22 : 28, fontWeight: FontWeight.w900, height: 1.05),
              ),
              const SizedBox(height: 6),
              Text(
                'Configure evento, inscrições, categorias, vagas, termos, pagamento e regulamento.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(color: onPrimary.withOpacity(0.82), fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _whiteChip(icon: _campeonatoAtivo ? Icons.visibility_rounded : Icons.visibility_off_rounded, label: _campeonatoAtivo ? 'Ativo no site' : 'Oculto'),
                  _whiteChip(icon: _recebendoInscricoes ? Icons.how_to_reg_rounded : Icons.block_rounded, label: _recebendoInscricoes ? 'Inscrições abertas' : 'Inscrições fechadas'),
                  _whiteChip(icon: Icons.category_rounded, label: '$_categoriasAtivas categorias'),
                ],
              ),
            ],
          );

          return narrow
              ? Column(children: [icon, const SizedBox(height: 14), text])
              : Row(children: [icon, const SizedBox(width: 16), Expanded(child: text)]);
        },
      ),
    );
  }

  Widget _whiteChip({required IconData icon, required String label}) {
    final onPrimary = _onPrimary();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onPrimary, size: 14),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: onPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    final t = context.uai;
    final cards = [
      _StatData('Status', _campeonatoAtivo ? 'Ativo' : 'Inativo', Icons.toggle_on_rounded, _campeonatoAtivo ? t.success : t.error),
      _StatData('Inscrições', _recebendoInscricoes ? 'Abertas' : 'Fechadas', Icons.app_registration_rounded, _recebendoInscricoes ? t.success : t.warning),
      _StatData('Inscritos', '$_totalInscricoes', Icons.people_rounded, t.info),
      _StatData('Categorias', '$_categoriasAtivas', Icons.category_rounded, t.associacao),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth < 680 ? 2 : 4;
        const spacing = 10.0;
        final width = (constraints.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((c) => SizedBox(width: width, child: _miniStat(c))).toList(),
        );
      },
    );
  }

  Widget _miniStat(_StatData data) {
    final t = context.uai;
    final accent = _ensureVisible(data.color, t.card);
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(borderColor: accent.withOpacity(0.16)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(data.icon, color: accent, size: 25),
          const SizedBox(height: 7),
          Text(data.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: accent, fontSize: 18, fontWeight: FontWeight.w900, height: 1)),
          const SizedBox(height: 4),
          Text(data.title, style: TextStyle(color: t.textSecondary, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildCardAtivarCampeonato() {
    final t = context.uai;
    final color = _campeonatoAtivo ? t.success : t.error;
    return _cardShell(
      color: color,
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: _iconBox(_campeonatoAtivo ? Icons.toggle_on_rounded : Icons.toggle_off_rounded, color),
        title: Text('Campeonato ativo', style: TextStyle(color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w900)),
        subtitle: Text(
          _campeonatoAtivo ? 'Visível no site e pronto para receber inscrições.' : 'Oculto no site e inscrições fechadas.',
          style: TextStyle(color: t.textSecondary, height: 1.25),
        ),
        value: _campeonatoAtivo,
        activeColor: color,
        onChanged: (value) => setState(() => _campeonatoAtivo = value),
      ),
    );
  }

  Widget _buildCardControleInscricoes() {
    final t = context.uai;
    final hoje = DateTime.now();
    bool dentroDoPeriodo = true;
    String mensagemPeriodo = 'Defina início e fim para controlar melhor o período.';

    if (_dataInicioInscricoes != null && _dataFimInscricoes != null) {
      if (hoje.isBefore(_dataInicioInscricoes!)) {
        dentroDoPeriodo = false;
        mensagemPeriodo = 'Período de inscrições começa em ${DateFormat('dd/MM/yyyy').format(_dataInicioInscricoes!)}';
      } else if (hoje.isAfter(_dataFimInscricoes!)) {
        dentroDoPeriodo = false;
        mensagemPeriodo = 'Período de inscrições encerrado em ${DateFormat('dd/MM/yyyy').format(_dataFimInscricoes!)}';
      } else {
        mensagemPeriodo = 'Período de inscrições ativo.';
      }
    }

    final periodoColor = dentroDoPeriodo ? t.success : t.warning;

    return _cardShell(
      color: t.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(icon: Icons.event_available_rounded, title: 'Controle de inscrições', subtitle: 'Defina abertura manual e período público.', color: t.info),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Recebendo inscrições', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800)),
            subtitle: Text(_recebendoInscricoes ? 'Inscrições abertas manualmente.' : 'Inscrições fechadas manualmente.', style: TextStyle(color: t.textSecondary)),
            value: _recebendoInscricoes,
            activeColor: t.success,
            onChanged: (value) => setState(() => _recebendoInscricoes = value),
          ),
          Divider(color: t.border, height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;
              final inicio = _dateField(_dataInicioController, 'Data início', () => _selecionarData(context, _dataInicioController, (date) => _dataInicioInscricoes = date));
              final fim = _dateField(_dataFimController, 'Data fim', () => _selecionarData(context, _dataFimController, (date) => _dataFimInscricoes = date));
              return narrow
                  ? Column(children: [inicio, const SizedBox(height: 10), fim])
                  : Row(children: [Expanded(child: inicio), const SizedBox(width: 10), Expanded(child: fim)]);
            },
          ),
          const SizedBox(height: 12),
          _noticeBox(
            icon: dentroDoPeriodo ? Icons.check_circle_rounded : Icons.info_rounded,
            color: periodoColor,
            text: mensagemPeriodo,
          ),
        ],
      ),
    );
  }

  Widget _buildCardInformacoesGerais() {
    final t = context.uai;
    return _cardShell(
      color: t.info,
      child: Column(
        children: [
          _sectionHeader(icon: Icons.info_rounded, title: 'Informações gerais', subtitle: 'Nome, data, horário e local do evento.', color: t.info),
          const SizedBox(height: 14),
          _textField(_nomeCampeonatoController, 'Nome do campeonato', Icons.emoji_events_rounded),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;
              final fields = [
                _textField(_dataEventoController, 'Data do evento', Icons.calendar_today_rounded, hint: 'Ex: 15 de junho de 2025'),
                _textField(_horarioEventoController, 'Horário', Icons.access_time_rounded, hint: 'Ex: 09:00h'),
              ];
              return narrow
                  ? Column(children: [fields[0], const SizedBox(height: 12), fields[1]])
                  : Row(children: [Expanded(child: fields[0]), const SizedBox(width: 10), Expanded(child: fields[1])]);
            },
          ),
          const SizedBox(height: 12),
          _textField(_localEventoController, 'Local do evento', Icons.location_on_rounded),
        ],
      ),
    );
  }

  Widget _buildCardCategorias() {
    final t = context.uai;
    return _cardShell(
      color: t.associacao,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionHeader(icon: Icons.category_rounded, title: 'Categorias', subtitle: 'Crie, edite e ative categorias do campeonato.', color: t.associacao)),
              IconButton(
                icon: Icon(Icons.add_circle_rounded, color: t.success, size: 30),
                onPressed: _criarCategoria,
                tooltip: 'Criar nova categoria',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_categorias.isEmpty)
            _emptyBox(icon: Icons.category_outlined, title: 'Nenhuma categoria cadastrada', subtitle: 'Toque no + para adicionar.')
          else
            Column(
              children: _categorias.asMap().entries.map((entry) {
                final index = entry.key;
                final cat = entry.value;
                final ativo = cat['ativo'] == true;
                final accent = ativo ? t.associacao : t.textMuted;
                final nome = cat['nome']?.toString() ?? 'Categoria';
                final taxa = _asDouble(cat['taxa']);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: ativo ? Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt) : t.cardAlt,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      onTap: () => _editarCategoria(index),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: ativo ? accent.withOpacity(0.18) : t.border),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: accent.withOpacity(0.16),
                              child: Text(
                                nome.isNotEmpty ? nome.substring(0, 1) : '?',
                                style: TextStyle(color: _ensureVisible(accent, t.cardAlt), fontWeight: FontWeight.w900, fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nome,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: ativo ? t.textPrimary : t.textMuted,
                                      fontWeight: FontWeight.w900,
                                      decoration: ativo ? null : TextDecoration.lineThrough,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${cat['idade_min']}-${cat['idade_max']} anos • ${cat['sexo']} • R\$ ${taxa.toStringAsFixed(2)} • ${cat['vagas']} vagas',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: t.textSecondary, fontSize: 11.5, height: 1.25),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _statusChip(ativo ? 'ATIVA' : 'INATIVA', ativo ? t.success : t.textMuted),
                            Icon(Icons.chevron_right_rounded, color: t.textMuted),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildCardVagas() {
    final t = context.uai;
    return _cardShell(
      color: t.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(icon: Icons.people_rounded, title: 'Controle de vagas', subtitle: 'Taxa, vagas totais e inscritos atuais.', color: t.warning),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 560;
              final fields = [
                _textField(_taxaInscricaoController, 'Taxa (R\$)', Icons.payments_rounded, keyboardType: TextInputType.number, prefixText: 'R\$ '),
                _textField(_vagasDisponiveisController, 'Vagas totais', Icons.event_seat_rounded, keyboardType: TextInputType.number),
              ];
              final resumo = _buildInscritosResumo();
              return narrow
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [fields[0], const SizedBox(height: 12), fields[1], const SizedBox(height: 12), resumo])
                  : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: fields[0]), const SizedBox(width: 10), Expanded(child: fields[1]), const SizedBox(width: 10), resumo]);
            },
          ),
          if ((int.tryParse(_vagasDisponiveisController.text) ?? _vagasDisponiveis) > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 9,
                value: _percentualVagas,
                backgroundColor: t.cardAlt,
                valueColor: AlwaysStoppedAnimation<Color>(_percentualVagas >= 1 ? t.error : t.success),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_percentualVagas * 100).toStringAsFixed(1)}% das vagas preenchidas',
              style: TextStyle(color: _percentualVagas >= 1 ? t.error : t.success, fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInscritosResumo() {
    final t = context.uai;
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.info.withOpacity(0.10), t.cardAlt),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.info.withOpacity(0.18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$_totalInscricoes', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _ensureVisible(t.info, t.cardAlt))),
          Text('Inscritos', textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: t.textSecondary, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildCardTermo() {
    final t = context.uai;
    return _cardShell(
      color: t.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(icon: Icons.description_rounded, title: 'Termo e assinatura', subtitle: 'Personalize termos para maiores e menores.', color: t.error),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Recolher assinatura digital', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800)),
            subtitle: Text('Quando ativo, o participante/responsável assina no formulário.', style: TextStyle(color: t.textSecondary)),
            value: _recolherAssinatura,
            activeColor: t.success,
            onChanged: (v) => setState(() => _recolherAssinatura = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Exigir termo assinado', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800)),
            subtitle: Text('Bloqueia envio sem aceite/assinatura do termo.', style: TextStyle(color: t.textSecondary)),
            value: _exigirTermoAssinado,
            activeColor: t.success,
            onChanged: (v) => setState(() => _exigirTermoAssinado = v),
          ),
          Divider(color: t.border, height: 24),
          _textField(_termoPersonalizadoController, 'Termo para maiores', Icons.article_rounded, maxLines: 8, hint: 'Digite o termo para maiores...'),
          const SizedBox(height: 12),
          _textField(_termoMenorPersonalizadoController, 'Termo para menores', Icons.family_restroom_rounded, maxLines: 8, hint: 'Digite o termo para menores...'),
        ],
      ),
    );
  }

  Widget _buildCardCamposOpcionais() {
    final t = context.uai;
    return _cardShell(
      color: t.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(icon: Icons.check_box_rounded, title: 'Campos opcionais', subtitle: 'Defina quais dados extras serão exigidos.', color: t.success),
          const SizedBox(height: 8),
          _checkboxTile('Exigir comprovante de pagamento', null, _exigirComprovantePagamento, (v) => setState(() => _exigirComprovantePagamento = v ?? false)),
          _checkboxTile('Exigir foto do competidor', 'Obrigatório upload da foto na inscrição.', _exigirFotoCompetidor, (v) => setState(() => _exigirFotoCompetidor = v ?? false)),
          _checkboxTile('Permitir edição após envio', 'Permite que o inscrito altere dados depois de enviar.', _permitirEditarAposEnvio, (v) => setState(() => _permitirEditarAposEnvio = v ?? false)),
        ],
      ),
    );
  }

  Widget _buildCardPagamento() {
    final t = context.uai;
    return _cardShell(
      color: t.success,
      child: Column(
        children: [
          _sectionHeader(icon: Icons.pix_rounded, title: 'Pagamento', subtitle: 'Configure PIX, banco e instruções.', color: t.success),
          const SizedBox(height: 14),
          _textField(_chavePixController, 'Chave PIX', Icons.qr_code_rounded),
          const SizedBox(height: 12),
          _textField(_informacoesBancariasController, 'Informações bancárias', Icons.account_balance_rounded),
          const SizedBox(height: 12),
          _textField(_instrucoesPagamentoController, 'Instruções de pagamento', Icons.notes_rounded, maxLines: 3),
        ],
      ),
    );
  }

  Widget _buildCardRegulamento() {
    final t = context.uai;
    return _cardShell(
      color: t.associacao,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(icon: Icons.gavel_rounded, title: 'Regulamento', subtitle: 'Use uma URL ou escreva o regulamento na tela.', color: t.associacao),
          const SizedBox(height: 14),
          _textField(_urlRegulamentoController, 'URL do regulamento (opcional)', Icons.link_rounded, keyboardType: TextInputType.url),
          const SizedBox(height: 12),
          Center(child: Text('OU', style: TextStyle(color: t.textMuted, fontWeight: FontWeight.w900))),
          const SizedBox(height: 12),
          _textField(_textoRegulamentoController, 'Texto do regulamento', Icons.rule_rounded, maxLines: 5),
        ],
      ),
    );
  }

  Widget _buildCardInfoAdicionais() {
    final t = context.uai;
    return _cardShell(
      color: t.warning,
      child: Column(
        children: [
          _sectionHeader(icon: Icons.info_outline_rounded, title: 'Informações adicionais', subtitle: 'Mensagem extra exibida aos inscritos.', color: t.warning),
          const SizedBox(height: 14),
          _textField(_informacoesAdicionaisController, 'Informações adicionais', Icons.notes_rounded, maxLines: 5),
        ],
      ),
    );
  }

  Widget _buildResumoConfiguracoes() {
    final t = context.uai;
    return _cardShell(
      color: t.warning,
      child: Column(
        children: [
          _sectionHeader(icon: Icons.fact_check_rounded, title: 'Resumo das configurações', subtitle: 'Confira os principais dados antes de salvar.', color: t.warning),
          Divider(color: t.border, height: 24),
          _buildResumoLinha('Status', _campeonatoAtivo ? 'ATIVO' : 'INATIVO', _campeonatoAtivo ? t.success : t.error),
          _buildResumoLinha('Inscrições', _recebendoInscricoes ? 'ABERTAS' : 'FECHADAS', _recebendoInscricoes ? t.success : t.warning),
          if (_dataInicioInscricoes != null && _dataFimInscricoes != null)
            _buildResumoLinha('Período', '${DateFormat('dd/MM').format(_dataInicioInscricoes!)} a ${DateFormat('dd/MM/yyyy').format(_dataFimInscricoes!)}', t.info),
          _buildResumoLinha('Evento', _nomeCampeonatoController.text, t.warning),
          _buildResumoLinha('Data', _dataEventoController.text, t.info),
          _buildResumoLinha('Taxa', 'R\$ ${_taxaInscricaoController.text}', t.success),
          _buildResumoLinha('Vagas', '${_vagasDisponiveisController.text} ($_totalInscricoes inscritos)', t.associacao),
          _buildResumoLinha('Assinatura', _recolherAssinatura ? 'SIM' : 'NÃO', t.success),
          _buildResumoLinha('Exigir foto', _exigirFotoCompetidor ? 'SIM' : 'NÃO', t.warning),
          _buildResumoLinha('Categorias', '$_categoriasAtivas ativas', t.associacao),
        ],
      ),
    );
  }

  Widget _buildResumoLinha(String label, String valor, Color cor) {
    final t = context.uai;
    final accent = _ensureVisible(cor, t.card);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: TextStyle(fontSize: 12, color: t.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withOpacity(0.16)),
                ),
                child: Text(valor, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: accent), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotaoGrupos() {
    final t = context.uai;
    final accent = _ensureVisible(t.associacao, t.background);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const GruposConvidadosScreen()));
        },
        icon: const Icon(Icons.group_rounded),
        label: const Text('GERENCIAR GRUPOS CONVIDADOS'),
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: _readableOn(accent),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.buttonRadius)),
        ),
      ),
    );
  }

  Widget _checkboxTile(String title, String? subtitle, bool value, ValueChanged<bool?> onChanged) {
    final t = context.uai;
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800)),
      subtitle: subtitle == null ? null : Text(subtitle, style: TextStyle(color: t.textSecondary)),
      value: value,
      activeColor: t.success,
      onChanged: onChanged,
    );
  }

  Widget _dateField(TextEditingController controller, String label, VoidCallback onTap) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      style: TextStyle(color: context.uai.textPrimary),
      decoration: _inputDecoration(label, Icons.calendar_today_rounded),
      onTap: onTap,
    );
  }

  Widget _textField(
      TextEditingController controller,
      String label,
      IconData icon, {
        String? hint,
        TextInputType? keyboardType,
        int maxLines = 1,
        String? prefixText,
      }) {
    final t = context.uai;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(color: t.textPrimary, height: maxLines > 1 ? 1.35 : 1.0),
      decoration: _inputDecoration(label, icon, hint: hint, prefixText: prefixText, maxLines: maxLines),
    );
  }

  InputDecoration _inputDecoration(
      String label,
      IconData icon, {
        String? hint,
        String? prefixText,
        int maxLines = 1,
      }) {
    final t = context.uai;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
      labelStyle: TextStyle(color: t.textSecondary),
      hintStyle: TextStyle(color: t.textMuted),
      prefixStyle: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800),
      prefixIcon: Padding(
        padding: EdgeInsets.only(bottom: maxLines > 1 ? 72 : 0),
        child: Icon(icon, color: t.primary),
      ),
      filled: true,
      fillColor: t.cardAlt,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(t.inputRadius)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.primary, width: 1.4),
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);
    return Row(
      children: [
        _iconBox(icon, accent),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: t.textPrimary, fontSize: 15.5, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: t.textSecondary, fontSize: 11.5, height: 1.25)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _iconBox(IconData icon, Color color) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(t.buttonRadius),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Icon(icon, color: accent, size: 24),
    );
  }

  Widget _noticeBox({required IconData icon, required Color color, required String text}) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700, height: 1.3))),
        ],
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Text(label, style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w900)),
    );
  }

  Widget _emptyBox({required IconData icon, required String title, required String subtitle}) {
    final t = context.uai;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: t.textMuted),
          const SizedBox(height: 8),
          Text(title, textAlign: TextAlign.center, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: t.textSecondary)),
        ],
      ),
    );
  }

  Widget _dialogHandle() {
    return Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: context.uai.border,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }

  Widget _cardShell({required Widget child, Color? color}) {
    final t = context.uai;
    final border = color == null ? t.border : _ensureVisible(color, t.card).withOpacity(0.16);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(borderColor: border),
      child: child,
    );
  }

  BoxDecoration _cardDecoration({Color? borderColor}) {
    final t = context.uai;
    return BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      border: Border.all(color: borderColor ?? t.border),
      boxShadow: t.softShadow,
    );
  }

  double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}

class _StatData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatData(this.title, this.value, this.icon, this.color);
}
