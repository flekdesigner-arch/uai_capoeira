import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart' as xml;
import 'package:cloud_firestore/cloud_firestore.dart';

// 👇 IMPORTS DO NOSSO SISTEMA
import 'package:uai_capoeira/services/campeonato_service.dart';
import 'package:uai_capoeira/models/inscricao_model.dart';
import 'package:uai_capoeira/models/grupo_model.dart';
import 'package:uai_capoeira/models/categoria_model.dart';
import 'package:uai_capoeira/constants/app_colors.dart';
import 'package:uai_capoeira/constants/app_strings.dart';

// Telas e widgets
import 'package:uai_capoeira/screens/inscricao/signature_screen.dart';
import 'package:uai_capoeira/widgets/regulamento_campeonato_dialog.dart';
import 'package:uai_capoeira/screens/site/landing_page.dart';

class InscricaoCampeonatoScreen extends StatefulWidget {
  const InscricaoCampeonatoScreen({super.key});

  @override
  State<InscricaoCampeonatoScreen> createState() => _InscricaoCampeonatoScreenState();
}

class _InscricaoCampeonatoScreenState extends State<InscricaoCampeonatoScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {

  // 👇 SERVICES
  final CampeonatoService _service = CampeonatoService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late PageController _pageController;
  late AnimationController _animController;
  int _currentStep = 0;

  // Focus Nodes
  final FocusNode _nomeFocusNode = FocusNode();

  // Controladores
  final Map<String, TextEditingController> _controllers = {
    'nome': TextEditingController(),
    'apelido': TextEditingController(),
    'data_nascimento': TextEditingController(),
    'cpf': TextEditingController(),
    'contato_aluno': TextEditingController(),
    'rua': TextEditingController(),
    'numero': TextEditingController(),
    'bairro': TextEditingController(),
    'cidade': TextEditingController(),
    'nome_responsavel': TextEditingController(),
    'contato_responsavel': TextEditingController(),
    'cpf_responsavel': TextEditingController(),
    'grupo': TextEditingController(),
    'professor_nome': TextEditingController(),
    'professor_contato': TextEditingController(),
    'outra_graduacao': TextEditingController(),
  };

  // Dados do formulário
  String? _sexo;
  String? _categoriaSelecionada;
  CategoriaModel? _categoriaInfo;
  bool _isGrupoUai = false;
  String? _graduacaoSelecionada;
  Map<String, dynamic>? _graduacaoInfo;
  List<Map<String, dynamic>> _graduacoesUai = [];
  String? _svgContent;
  int _idade = 0;
  bool _autorizacao = false;

  // Grupos convidados
  List<GrupoModel> _gruposConvidados = [];
  bool _carregandoGrupos = true;
  String? _grupoSelecionado;
  String? _erroGrupos;
  bool _isGrupoSelecionadoUai = false;

  // Configurações do campeonato
  Map<String, dynamic> _config = {};
  String _nomeCampeonato = AppStrings.campeonatoTitulo;
  String _dataEvento = 'A definir';
  String _localEvento = 'A definir';
  String _horarioEvento = 'A definir';
  double _taxaInscricao = 30.0;
  int _vagasDisponiveis = 0;
  int _vagasRestantes = 0;
  bool _configuracoesCarregadas = false;
  bool _temVagas = true;
  bool _inscricoesAbertas = true;
  bool _recolherAssinatura = true;
  bool _exigirComprovantePagamento = false;
  bool _exigirFotoCompetidor = false;

  // 🔥 NOVAS CONFIGURAÇÕES DE PERÍODO
  bool _recebendoInscricoes = true;
  DateTime? _dataInicioInscricoes;
  DateTime? _dataFimInscricoes;
  bool _periodoValido = true;
  String _mensagemPeriodo = '';

  // Dados de Pagamento
  String _chavePix = '';
  String _informacoesBancarias = '';
  String _instrucoesPagamento = '';

  // Categorias
  List<CategoriaModel> _categorias = [];

  // Arquivos
  String? _assinaturaUrl;
  String? _fotoUrl;
  String? _comprovanteUrl;
  Uint8List? _fotoBytes;
  Uint8List? _comprovanteBytes;
  String? _fotoNome;
  String? _comprovanteNome;

  // Estados
  bool _carregando = true;
  bool _enviando = false;
  bool _buscandoAluno = false;
  bool _alunoEncontrado = false;
  bool _alunoFormado = false;
  String _mensagem = '';
  bool _isMounted = true;
  bool _processandoEnvio = false;
  String? _inscricaoId;

  // Mapa de validação
  final Map<int, bool> _etapaValida = {0: false, 1: false, 2: false, 3: false};

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    WidgetsBinding.instance.addObserver(this);
    _isMounted = true;

    // 👇 Adiciona listener para quando o campo nome perder o foco
    _nomeFocusNode.addListener(_onNomeFocusLost);

    _controllers.forEach((key, controller) {
      controller.addListener(_validarCampos);
    });

    _carregarDadosIniciais();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isMounted = false;

    // 👇 Remove listener e dispose do focus node
    _nomeFocusNode.removeListener(_onNomeFocusLost);
    _nomeFocusNode.dispose();

    _controllers.forEach((_, controller) {
      controller.removeListener(_validarCampos);
      controller.dispose();
    });
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  // 👇 Chamado quando o campo nome perde o foco
  void _onNomeFocusLost() {
    if (!_nomeFocusNode.hasFocus && !_buscandoAluno && !_alunoEncontrado && !_alunoFormado) {
      _buscarAluno();
    }
  }

  void _validarCampos() {
    if (!_isMounted) return;
    if (_currentStep == 1) _validarEtapa1();
    else if (_currentStep == 2) _validarEtapa2();
    else if (_currentStep == 3) _validarEtapaFinal();
  }

  // ==================== CARREGAMENTO DE DADOS ====================

  Future<void> _carregarDadosIniciais() async {
    try {
      await Future.wait([
        _verificarInscricoes(),
        _carregarGraduacoes(),
        _loadSvg(),
      ]);

      await _carregarGruposConvidados();

    } catch (e) {
      print('❌ Erro ao carregar dados iniciais: $e');
      if (_isMounted) {
        setState(() {
          _carregando = false;
          _mensagem = AppStrings.erroCarregarDados;
        });
      }
    }
  }

  Future<void> _loadSvg() async {
    try {
      final content = await DefaultAssetBundle.of(context).loadString('assets/images/corda.svg');
      if (_isMounted) {
        setState(() {
          _svgContent = content;
        });
      }
    } catch (e) {
      print('❌ Erro ao carregar SVG: $e');
    }
  }

  String _getModifiedSvg(Map<String, dynamic> data) {
    if (_svgContent == null) return '';

    try {
      final document = xml.XmlDocument.parse(_svgContent!);

      Color colorFromHex(String? hexColor) {
        if (hexColor == null || hexColor.length < 7) return Colors.grey;
        try {
          return Color(int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16));
        } catch (e) {
          return Colors.grey;
        }
      }

      void changeColor(String id, Color color) {
        try {
          final element = document.rootElement.descendants
              .whereType<xml.XmlElement>()
              .firstWhere(
                (e) => e.getAttribute('id') == id,
            orElse: () => xml.XmlElement(xml.XmlName('')),
          );

          if (element.name.local.isNotEmpty) {
            final style = element.getAttribute('style') ?? '';
            final hex = '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
            String newStyle;
            if (style.contains('fill:')) {
              newStyle = style.replaceAll(RegExp(r'fill:#[0-9a-fA-F]{6}'), 'fill:$hex');
            } else {
              newStyle = 'fill:$hex;$style';
            }
            element.setAttribute('style', newStyle);
          }
        } catch (e) {
          print('Erro ao mudar cor da parte $id: $e');
        }
      }

      changeColor('cor1', colorFromHex(data['hex_cor1']));
      changeColor('cor2', colorFromHex(data['hex_cor2']));
      changeColor('corponta1', colorFromHex(data['hex_ponta1']));
      changeColor('corponta2', colorFromHex(data['hex_ponta2']));

      return document.toXmlString();
    } catch (e) {
      print('❌ Erro ao modificar SVG: $e');
      return _svgContent!;
    }
  }

  Future<void> _carregarGraduacoes() async {
    try {
      final graduacoes = await _service.carregarGraduacoesUai();
      if (_isMounted) {
        setState(() => _graduacoesUai = graduacoes);
      }
    } catch (e) {
      print('❌ Erro ao carregar graduações: $e');
    }
  }

  Future<void> _carregarGruposConvidados() async {
    setState(() {
      _carregandoGrupos = true;
      _erroGrupos = null;
    });

    try {
      final grupos = await _service.carregarGruposConvidados();

      if (_isMounted) {
        setState(() {
          _gruposConvidados = grupos;
          _carregandoGrupos = false;
        });
      }
    } catch (e) {
      print('❌ Erro ao carregar grupos: $e');
      if (_isMounted) {
        setState(() {
          _gruposConvidados = [];
          _carregandoGrupos = false;
          _erroGrupos = 'Erro ao carregar grupos: $e';
        });
      }
    }
  }

  // 🔥 Buscar aluno na coleção com validação de formado
  Future<void> _buscarAluno() async {
    String nomeBusca = _controllers['nome']!.text.trim();

    if (nomeBusca.isEmpty || _buscandoAluno) return;

    setState(() => _buscandoAluno = true);

    try {
      // Limpa o nome (remove espaços extras, converte para maiúsculas)
      nomeBusca = nomeBusca.replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

      final snapshot = await _firestore
          .collection('alunos')
          .where('nome', isEqualTo: nomeBusca)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty && mounted) {
        final aluno = snapshot.docs.first.data();
        final nivelGraduacao = aluno['nivel_graduacao'] ?? 0;

        // 🔥 VERIFICA SE É FORMADO (nível > 14)
        if (nivelGraduacao > 14) {
          _mostrarAlertaFormado();
          _limparTodosCampos();
          setState(() {
            _alunoFormado = true;
            _alunoEncontrado = false;
          });
        } else {
          // É aluno normal, preenche os dados
          setState(() {
            _preencherDadosAluno(aluno);
            _alunoEncontrado = true;
            _alunoFormado = false;
          });
        }
      } else {
        // Não encontrou aluno - SILÊNCIO TOTAL
        setState(() {
          _alunoEncontrado = false;
          _alunoFormado = false;
        });
      }

    } catch (e) {
      print('Erro na busca de aluno: $e');
    } finally {
      if (mounted) setState(() => _buscandoAluno = false);
    }
  }

  // 🔥 Método para formatar telefone
  String _formatarTelefone(String numero) {
    String digits = numero.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 11) {
      return '(${digits.substring(0,2)}) ${digits.substring(2,7)}-${digits.substring(7)}';
    } else if (digits.length == 10) {
      return '(${digits.substring(0,2)}) ${digits.substring(2,6)}-${digits.substring(6)}';
    }
    return numero;
  }

  // 🔥 Preencher dados do aluno encontrado
  void _preencherDadosAluno(Map<String, dynamic> aluno) {
    // ✅ Nome (travado)
    _controllers['nome']!.text = aluno['nome'] ?? '';

    // ✅ Apelido (editável)
    _controllers['apelido']!.text = aluno['apelido'] ?? '';

    // ✅ Data de nascimento (editável)
    if (aluno['data_nascimento'] != null) {
      final data = (aluno['data_nascimento'] as Timestamp).toDate();
      _controllers['data_nascimento']!.text = DateFormat('dd/MM/yyyy').format(data);
      _atualizarIdade(_controllers['data_nascimento']!.text);
    }

    // ✅ CPF (editável)
    _controllers['cpf']!.text = aluno['cpf'] ?? '';

    // ❌ Telefone do aluno (branco - editável)
    _controllers['contato_aluno']!.clear();

    // ❌ Endereço (branco - editável)
    _controllers['rua']!.clear();
    _controllers['numero']!.clear();
    _controllers['bairro']!.clear();

    // ✅ Cidade (editável)
    _controllers['cidade']!.text = aluno['cidade'] ?? '';

    // ✅ Nome do responsável (editável)
    _controllers['nome_responsavel']!.text = aluno['nome_responsavel'] ?? '';

    // ❌ Telefone do responsável (branco - editável)
    _controllers['contato_responsavel']!.clear();

    // ✅ CPF do responsável (editável)
    _controllers['cpf_responsavel']!.text = aluno['cpf_responsavel'] ?? '';

    // ✅ Sexo (editável)
    _sexo = aluno['sexo'];

    // ✅ GRUPO UAI (travado)
    _isGrupoSelecionadoUai = true;
    _grupoSelecionado = 'GRUPO UAI CAPOEIRA';
    _controllers['grupo']!.text = 'GRUPO UAI CAPOEIRA';

    // ✅ GRADUAÇÃO (travado)
    if (aluno['graduacao_id'] != null) {
      _graduacaoSelecionada = aluno['graduacao_id'];
      _graduacaoInfo = {
        'id': aluno['graduacao_id'],
        'nome_graduacao': aluno['graduacao_atual'],
        'nivel_graduacao': aluno['nivel_graduacao'],
        'hex_cor1': aluno['graduacao_cor1'],
        'hex_cor2': aluno['graduacao_cor2'],
        'hex_ponta1': aluno['graduacao_ponta1'],
        'hex_ponta2': aluno['graduacao_ponta2'],
      };
    }

    // ✅ PROFESSOR (travado)
    _controllers['professor_nome']!.text = 'TICO - TICO';
    _controllers['professor_contato']!.text = _formatarTelefone('38998262404');

    // ✅ FOTO
    if (aluno['foto_perfil_aluno'] != null) {
      _fotoUrl = aluno['foto_perfil_aluno'];
      _fotoBytes = null;
    }

    // 🔥 FORÇA VALIDAÇÃO E REBUILD!
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _validarEtapa1();
        _validarEtapa2();
        _validarEtapaFinal();
        _validarCampos();
        setState(() {});
      }
    });
  }

  // 🔥 Limpar todos os campos do formulário
  void _limparTodosCampos() {
    _controllers.forEach((key, controller) {
      controller.clear();
    });

    setState(() {
      _sexo = null;
      _categoriaSelecionada = null;
      _categoriaInfo = null;
      _graduacaoSelecionada = null;
      _graduacaoInfo = null;
      _idade = 0;
      _autorizacao = false;
      _grupoSelecionado = null;
      _isGrupoSelecionadoUai = false;
      _fotoUrl = null;
      _fotoBytes = null;
      _assinaturaUrl = null;
      _comprovanteUrl = null;
      _comprovanteBytes = null;
      _alunoEncontrado = false;

      // 🔥 Limpa as validações
      _etapaValida[1] = false;
      _etapaValida[2] = false;
      _etapaValida[3] = false;
    });
  }

  // 🔥 Mostrar alerta de formado
  void _mostrarAlertaFormado() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 32),
            ),
            const SizedBox(height: 16),
            const Text(
              'GRADUAÇÃO NÃO PERMITIDA',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'O campeonato é exclusivo para ALUNOS de capoeira (até 14º nível).\n\n'
              'Formados (Monitores, Instrutores, Professores, Contramestres e Mestres) '
              'não podem competir, mas podem participar como jurados ou apoiadores.\n\n'
              'Todos os campos foram limpos para nova tentativa.',
          textAlign: TextAlign.center,
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Volta o foco para o campo nome
              FocusScope.of(context).requestFocus(_nomeFocusNode);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('ENTENDI'),
          ),
        ],
      ),
    );
  }

  Future<void> _verificarInscricoes() async {
    try {
      final config = await _service.carregarConfiguracoes();

      if (config.isEmpty) {
        setState(() {
          _inscricoesAbertas = false;
          _configuracoesCarregadas = true;
          _etapaValida[0] = false;
          _carregando = false;
        });
        return;
      }

      final inscricoesAtivas = await _service.contarInscricoesAtivas();
      final vagasTotal = config['vagas_disponiveis'] ?? 0;
      final vagasRestantes = vagasTotal - inscricoesAtivas;

      _recebendoInscricoes = config['recebendo_inscricoes'] ?? true;

      if (config['data_inicio_inscricoes'] != null) {
        _dataInicioInscricoes = (config['data_inicio_inscricoes'] as Timestamp).toDate();
      }

      if (config['data_fim_inscricoes'] != null) {
        _dataFimInscricoes = (config['data_fim_inscricoes'] as Timestamp).toDate();
      }

      _periodoValido = true;
      _mensagemPeriodo = '';

      final hoje = DateTime.now();

      if (_dataInicioInscricoes != null && _dataFimInscricoes != null) {
        if (hoje.isBefore(_dataInicioInscricoes!)) {
          _periodoValido = false;
          _mensagemPeriodo = '⏳ As inscrições começam em ${DateFormat('dd/MM/yyyy').format(_dataInicioInscricoes!)}';
        } else if (hoje.isAfter(_dataFimInscricoes!)) {
          _periodoValido = false;
          _mensagemPeriodo = '⌛ O período de inscrições encerrou em ${DateFormat('dd/MM/yyyy').format(_dataFimInscricoes!)}';
        }
      }

      if (_isMounted) {
        setState(() {
          _inscricoesAbertas = config['campeonato_ativo'] ?? false;
          _nomeCampeonato = config['nome_campeonato'] ?? AppStrings.campeonatoTitulo;
          _dataEvento = config['data_evento'] ?? 'A definir';
          _localEvento = config['local_evento'] ?? 'A definir';
          _horarioEvento = config['horario_evento'] ?? 'A definir';
          _taxaInscricao = (config['taxa_inscricao'] ?? 30.0).toDouble();
          _vagasDisponiveis = vagasTotal;
          _vagasRestantes = vagasRestantes;
          _temVagas = vagasRestantes > 0;
          _recolherAssinatura = config['recolher_assinatura'] ?? true;
          _exigirComprovantePagamento = config['exigir_comprovante_pagamento'] ?? false;
          _exigirFotoCompetidor = config['exigir_foto_competidor'] ?? false;

          _chavePix = config['chave_pix'] ?? '';
          _informacoesBancarias = config['informacoes_bancarias'] ?? '';
          _instrucoesPagamento = config['instrucoes_pagamento'] ?? 'Pague via PIX e envie o comprovante.';

          if (config.containsKey('categorias')) {
            _categorias = _service.processarCategorias(config['categorias']);
          }

          _config = config;
          _configuracoesCarregadas = true;

          _etapaValida[0] = _inscricoesAbertas &&
              _recebendoInscricoes &&
              _periodoValido &&
              _temVagas;

          _carregando = false;
        });
      }
    } catch (e) {
      print('❌ Erro ao verificar inscrições: $e');
      if (_isMounted) {
        setState(() {
          _inscricoesAbertas = false;
          _configuracoesCarregadas = true;
          _etapaValida[0] = false;
          _carregando = false;
          _mensagem = 'Erro ao verificar disponibilidade';
        });
      }
    }
  }

  // ==================== VALIDAÇÕES ====================

  bool _validarNome(String nome) {
    if (nome.isEmpty) return false;
    final regex = RegExp(r'^[A-Za-zÀ-ÖØ-öø-ÿ0-9\s\-°ºª\.]+$');
    return regex.hasMatch(nome);
  }

  bool _isMaiorIdade() => _idade >= 18;

  int _calcularIdade(String dataNascimento) {
    try {
      if (dataNascimento.isEmpty) return 0;
      final data = DateFormat('dd/MM/yyyy').parseStrict(dataNascimento);
      final hoje = DateTime.now();
      int idade = hoje.year - data.year;
      if (hoje.month < data.month || (hoje.month == data.month && hoje.day < data.day)) idade--;
      return idade;
    } catch (e) {
      return 0;
    }
  }

  void _atualizarIdade(String dataNascimento) {
    setState(() => _idade = _calcularIdade(dataNascimento));
    _validarCampos();
  }

  void _validarEtapa1() {
    if (!_isMounted) return;

    final isMaior = _isMaiorIdade();

    final nomeValido = _controllers['nome']!.text.isNotEmpty && _validarNome(_controllers['nome']!.text);
    final apelidoValido = _controllers['apelido']!.text.isNotEmpty && _validarNome(_controllers['apelido']!.text);
    final dataValida = _controllers['data_nascimento']!.text.isNotEmpty && _idade > 0;
    final sexoValido = _sexo != null;
    final contatoValido = _controllers['contato_aluno']!.text.length >= 14;

    final ruaValida = _controllers['rua']!.text.isNotEmpty && _validarNome(_controllers['rua']!.text);
    final numeroValido = _controllers['numero']!.text.isNotEmpty;
    final bairroValido = _controllers['bairro']!.text.isNotEmpty && _validarNome(_controllers['bairro']!.text);
    final cidadeValida = _controllers['cidade']!.text.isNotEmpty;

    bool cpfValido = true;
    if (isMaior) cpfValido = _controllers['cpf']!.text.length >= 14;

    bool responsavelValido = true;
    if (!isMaior) {
      responsavelValido = _controllers['nome_responsavel']!.text.isNotEmpty &&
          _validarNome(_controllers['nome_responsavel']!.text) &&
          _controllers['contato_responsavel']!.text.length >= 14 &&
          _controllers['cpf_responsavel']!.text.length >= 14;
    }

    bool fotoValida = true;
    if (_exigirFotoCompetidor) fotoValida = _fotoUrl != null || _fotoBytes != null;

    if (_isMounted) {
      setState(() {
        _etapaValida[1] = nomeValido && apelidoValido && dataValida && cpfValido &&
            sexoValido && contatoValido && ruaValida && numeroValido &&
            bairroValido && cidadeValida && responsavelValido && fotoValida;
      });
    }
  }

  void _validarEtapa2() {
    if (!_isMounted) return;

    final grupoValido = _controllers['grupo']!.text.isNotEmpty && _validarNome(_controllers['grupo']!.text);
    final professorValido = _controllers['professor_nome']!.text.isNotEmpty && _validarNome(_controllers['professor_nome']!.text);
    final contatoValido = _controllers['professor_contato']!.text.length >= 14;

    bool graduacaoValida = true;
    if (_isGrupoSelecionadoUai) {
      graduacaoValida = _graduacaoSelecionada != null;
    } else {
      graduacaoValida = _controllers['outra_graduacao']!.text.isNotEmpty;
    }

    if (_isMounted) {
      setState(() {
        _etapaValida[2] = grupoValido && professorValido && contatoValido && graduacaoValida;
      });
    }
  }

  void _validarEtapaFinal() {
    bool categoriaValida = false;
    if (_categoriaSelecionada != null && _categoriaInfo != null) {
      categoriaValida = _categoriaInfo!.isCompativel(_idade, _sexo);
    }

    bool comprovanteValido = true;
    // 🔥 Se for aluno encontrado, não precisa de comprovante
    if (_exigirComprovantePagamento && !_alunoEncontrado) {
      comprovanteValido = _comprovanteUrl != null || _comprovanteBytes != null;
    }

    if (_isMounted) {
      setState(() {
        _etapaValida[3] = _autorizacao &&
            (_recolherAssinatura ? _assinaturaUrl != null : true) &&
            categoriaValida &&
            comprovanteValido;
      });
    }
  }

  // ==================== AÇÕES ====================

  String _toUpperCase(String? text) => text?.toUpperCase().trim() ?? '';

  String _getPrimeiroNome(String? nomeCompleto) {
    if (nomeCompleto == null || nomeCompleto.isEmpty) return '...';
    return nomeCompleto.split(' ')[0];
  }

  String _gerarEnderecoCompleto() {
    List<String> parts = [];
    if (_controllers['rua']!.text.isNotEmpty) {
      String ruaNumero = _toUpperCase(_controllers['rua']!.text);
      if (_controllers['numero']!.text.isNotEmpty) {
        ruaNumero += ' - ${_toUpperCase(_controllers['numero']!.text)}';
      }
      parts.add(ruaNumero);
    }
    if (_controllers['bairro']!.text.isNotEmpty) parts.add(_toUpperCase(_controllers['bairro']!.text));
    if (_controllers['cidade']!.text.isNotEmpty) parts.add(_toUpperCase(_controllers['cidade']!.text));
    return parts.join(', ');
  }

  String _gerarRegulamentoCompleto() {
    String texto = _config['texto_regulamento'] ?? _regulamentoPadrao;

    texto = texto
        .replaceAll('[NOME_CAMPEONATO]', _nomeCampeonato)
        .replaceAll('[DATA_EVENTO]', _dataEvento)
        .replaceAll('[HORARIO_EVENTO]', _horarioEvento)
        .replaceAll('[LOCAL_EVENTO]', _localEvento)
        .replaceAll('[TAXA_INSCRICAO]', _taxaInscricao.toStringAsFixed(2));

    String categoriasLista = '';
    for (var cat in _categorias) {
      categoriasLista += '   • ${cat.nome}: ${cat.idadeMin} a ${cat.idadeMax} anos • ${cat.sexo} • R\$ ${cat.taxa.toStringAsFixed(2)} • ${cat.vagas} vagas\n';
    }

    texto = texto.replaceAll('[CATEGORIAS_LISTA]', categoriasLista);
    texto = texto.replaceAll('[INFORMACOES_ADICIONAIS]', _config['informacoes_adicionais'] ?? '');

    return texto;
  }

  String get _regulamentoPadrao => '''
📜 REGULAMENTO OFICIAL
🏆 [NOME_CAMPEONATO]

1️⃣ DA REALIZAÇÃO E OBJETIVO
O [NOME_CAMPEONATO] tem como objetivo promover a integração entre grupos convidados, valorizando a arte da capoeira com foco no show, na técnica e no volume de jogo, priorizando a segurança e a não violência.

📍 Local do evento: [LOCAL_EVENTO]
📅 Data: [DATA_EVENTO]
⏰ Horário: [HORARIO_EVENTO]

2️⃣ DA PARTICIPAÇÃO
2.1. O campeonato é exclusivo para ALUNOS de capoeira, não sendo permitida a participação de formados (Monitores, Instrutores, Professores, Contramestres e Mestres).
2.2. A participação é restrita a grupos convidados pela organização.
2.3. Cada grupo deverá estar uniformizado com seu abadá oficial (camisa do grupo + calça branca).
2.4. Caso o grupo não possua abadá próprio, será permitido o uso de camisa branca lisa + calça branca.

3️⃣ DAS INSCRIÇÕES
💰 Valor da inscrição: R\$ [TAXA_INSCRICAO] por competidor.
📆 Prazo final para inscrição e pagamento: 25 de maio de 2025.
🌐 As inscrições devem ser realizadas exclusivamente através do formulário online.
⚠️ Após o prazo estipulado não serão aceitas novas inscrições.

💡 SOBRE A TAXA DE INSCRIÇÃO:
A taxa de inscrição tem como objetivo custear a organização do evento, incluindo:
   • 🏅 Medalhas e troféus para os vencedores
   • 🍽️ Alimentação para participantes e equipe de apoio
   • 🎤 Estrutura do evento (som, iluminação, espaço)
   • 📜 Material gráfico e certificados
   • 🩹 Equipe de primeiros socorros
   • 🧹 Limpeza e manutenção do espaço

Sua contribuição é fundamental para a realização deste campeonato e para proporcionar uma experiência de qualidade a todos os participantes!

4️⃣ DAS CATEGORIAS
📂 [CATEGORIAS_LISTA]

5️⃣ DO SISTEMA DE COMPETIÇÃO
5.1. O campeonato será no formato MATA-MATA (eliminatória simples), com chaveamento pré-definido pela organização.
5.2. Os confrontos serão sorteados e divulgados previamente.
5.3. Os competidores serão organizados em fila única por categoria e chamados por ordem dos confrontos.
5.4. Em cada confronto, os atletas serão identificados visualmente (faixas coloridas no braço):
    🟡 Um competidor receberá faixa AMARELA
    🔵 O outro competidor receberá faixa AZUL
5.5. O não comparecimento no momento da chamada implica em desclassificação automática.

6️⃣ DA DINÂMICA DO CONFRONTO
6.1. APRESENTAÇÃO SOLO (30 segundos para cada competidor)
    🟡 Inicia o competidor de faixa AMARELA, seguido pelo 🔵 competidor de faixa AZUL.
6.2. JOGO EM DUPLA (1 minuto)
    🔄 Imediatamente após os solos, inicia-se o jogo entre os dois competidores.
    🚫 O jogo deverá ser conduzido sem contato físico intencional.

7️⃣ DOS CRITÉRIOS DE AVALIAÇÃO
🎯 7.1. Na Apresentação Solo serão avaliados:
   • Domínio corporal
   • Controle e equilíbrio
   • Explosão
   • Ritmo e cadência
   • Volume de movimentação
   • Flexibilidade

🎵 7.2. No Jogo em Dupla serão avaliados:
   • Técnica do jogo
   • Encaixe das movimentações
   • Noção de jogo
   • Consciência espacial
   • Ritmo e musicalidade
   • Autocontrole
   • Qualidade das esquivas

8️⃣ DAS REGRAS DE CONDUTA
8.1. É expressamente proibido:
   🚫 Qualquer golpe direto ou traumatizante
   🚫 Contato físico intencional
   🚫 Conduta antidesportiva
8.2. Infrações poderão acarretar advertência, perda de pontos ou desclassificação.

9️⃣ DA COMISSÃO JULGADORA
9.1. A mesa será composta por número ímpar de jurados (1, 3 ou 5).
9.2. Os jurados serão Mestres e Professores dos grupos participantes.
9.3. A votação será feita de forma visual e imediata:
    ✋ Mão esquerda = competidor AMARELO
    ✋ Mão direita = competidor AZUL
9.4. A decisão dos jurados é soberana e irrecorrível.

🔟 DA PREMIAÇÃO
10.1. Haverá premiação para os 1º, 2º e 3º colocados de cada categoria.
10.2. A premiação consistirá em medalhas e troféus.

📌 Informações adicionais:
[INFORMACOES_ADICIONAIS]

Realização:
ASSOCIAÇÃO UAI CAPOEIRA
''';

  String _gerarTermoTexto() {
    final isMaior = _isMaiorIdade();
    final nomeAluno = _controllers['nome']!.text;
    final nomeResp = isMaior ? nomeAluno : _controllers['nome_responsavel']!.text;
    final cpf = isMaior
        ? _controllers['cpf']!.text
        : _controllers['cpf_responsavel']!.text;
    final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final cidade = _controllers['cidade']!.text.isNotEmpty
        ? _controllers['cidade']!.text.toUpperCase()
        : 'BOCAIÚVA';
    final data = DateFormat('dd').format(DateTime.now());
    final mes = DateFormat('MMMM', 'pt_BR').format(DateTime.now()).toUpperCase();
    final ano = DateFormat('yyyy').format(DateTime.now());

    String termoBase = isMaior
        ? (_config['termo_personalizado'] ?? _termoPadraoMaior)
        : (_config['termo_menor_personalizado'] ?? _termoPadraoMenor);

    termoBase = termoBase
        .replaceAll('[NOME_CAMPEONATO]', _nomeCampeonato)
        .replaceAll('[DATA_EVENTO]', _dataEvento)
        .replaceAll('[HORARIO_EVENTO]', _horarioEvento)
        .replaceAll('[LOCAL_EVENTO]', _localEvento)
        .replaceAll('[VALOR_INSCRICAO]', _taxaInscricao.toStringAsFixed(2))
        .replaceAll('[CIDADE]', cidade)
        .replaceAll('[DATA]', data)
        .replaceAll('[MÊS]', mes)
        .replaceAll('[ANO]', ano)
        .replaceAll('[DATA_HORA]', dataHora);

    if (isMaior) {
      termoBase = termoBase
          .replaceAll('[NOME_COMPLETO]', nomeAluno)
          .replaceAll('[CPF]', cpf)
          .replaceAll('[DATA_NASCIMENTO]', _controllers['data_nascimento']!.text);
    } else {
      termoBase = termoBase
          .replaceAll('[NOME_RESPONSAVEL]', nomeResp)
          .replaceAll('[CPF_RESPONSAVEL]', cpf)
          .replaceAll('[NOME_MENOR]', nomeAluno)
          .replaceAll('[DATA_NASCIMENTO_MENOR]', _controllers['data_nascimento']!.text)
          .replaceAll('[PARENTESCO]', 'RESPONSÁVEL LEGAL');
    }

    return termoBase;
  }

  String get _termoPadraoMaior => '''
Eu, [NOME_COMPLETO], portador do CPF nº [CPF], residente em [CIDADE], declaro para os devidos fins que:

1. Estou ciente e de acordo com o regulamento do [NOME_CAMPEONATO], que ocorrerá no dia [DATA_EVENTO], no [LOCAL_EVENTO], com início às [HORARIO_EVENTO].

2. Autorizo a utilização de minha imagem e som, para fins de divulgação do evento, em qualquer meio de comunicação.

3. Declaro estar em boas condições de saúde para participar do evento, isentando a organização de qualquer responsabilidade por acidentes ou lesões decorrentes da minha participação.

4. Comprometo-me a respeitar as regras do campeonato e a decisão dos jurados.

5. Autorizo o pagamento da taxa de inscrição no valor de R\$ [VALOR_INSCRICAO] e declaro estar ciente de que este valor não será reembolsado em caso de desistência.

[CIDADE], [DATA] de [MÊS] de [ANO]

____________________________________
Assinatura
''';

  String get _termoPadraoMenor => '''
Eu, [NOME_RESPONSAVEL], portador do CPF nº [CPF_RESPONSAVEL], responsável legal pelo menor [NOME_MENOR], nascido em [DATA_NASCIMENTO_MENOR], declaro para os devidos fins que:

1. Estou ciente e de acordo com o regulamento do [NOME_CAMPEONATO], que ocorrerá no dia [DATA_EVENTO], no [LOCAL_EVENTO], com início às [HORARIO_EVENTO].

2. Autorizo a participação do menor no evento, bem como a utilização de sua imagem e som, para fins de divulgação, em qualquer meio de comunicação.

3. Declaro que o menor está em boas condições de saúde para participar do evento, isentando a organização de qualquer responsabilidade por acidentes ou lesões decorrentes de sua participação.

4. Comprometo-me, como responsável, a orientar o menor a respeitar as regras do campeonato e a decisão dos jurados.

5. Autorizo o pagamento da taxa de inscrição no valor de R\$ [VALOR_INSCRICAO] e declaro estar ciente de que este valor não será reembolsado em caso de desistência.

[CIDADE], [DATA] de [MÊS] de [ANO]

____________________________________
Assinatura do Responsável
''';

  // ==================== UPLOAD DE ARQUIVOS ====================

  Future<void> _selecionarFoto() async {
    try {
      final bool isWeb = identical(0, 0.0);

      if (!isWeb) {
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(source: ImageSource.gallery);

        if (image != null) {
          final bytes = await image.readAsBytes();
          if (_isMounted) {
            setState(() {
              _fotoBytes = bytes;
              _fotoNome = image.name;
              _fotoUrl = null;
            });
            _validarEtapa1();
          }
        }
      } else {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
          withData: true,
        );

        if (result != null && result.files.single.bytes != null) {
          final bytes = result.files.single.bytes!;
          final nome = result.files.single.name;

          if (_isMounted) {
            setState(() {
              _fotoBytes = bytes;
              _fotoNome = nome;
              _fotoUrl = null;
            });
            _validarEtapa1();
          }
        }
      }
    } catch (e) {
      print('❌ Erro ao selecionar foto: $e');
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Erro ao selecionar arquivo')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _selecionarComprovante() async {
    // 🔥 Se for aluno encontrado, não precisa de comprovante
    if (_alunoEncontrado) return;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        final nome = result.files.single.name;

        if (_isMounted) {
          setState(() {
            _comprovanteBytes = bytes;
            _comprovanteNome = nome;
            _comprovanteUrl = null;
          });
          _validarEtapaFinal();
        }
      }
    } catch (e) {
      print('❌ Erro ao selecionar comprovante: $e');
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar comprovante'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _copiarChavePix() {
    Clipboard.setData(ClipboardData(text: _chavePix));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Chave PIX copiada!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _abrirTelaAssinatura() async {
    final isMaior = _isMaiorIdade();
    final nomeResponsavel = isMaior
        ? _controllers['nome']!.text
        : _controllers['nome_responsavel']!.text;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SignatureScreen(
          inscricaoId: 'temp_${DateTime.now().millisecondsSinceEpoch}',
          nomeResponsavel: nomeResponsavel,
          nomeAluno: _controllers['nome']!.text,
          onConfirm: (imageUrl) {
            if (_isMounted) {
              setState(() {
                _assinaturaUrl = imageUrl;
                _validarEtapaFinal();
              });
            }
          },
        ),
      ),
    );
  }

  // ==================== ENVIO DA INSCRIÇÃO ====================

  Future<void> _enviarInscricao() async {
    if (!_isMounted || _processandoEnvio) return;

    setState(() {
      _enviando = true;
      _processandoEnvio = true;
    });

    try {
      if (!await _service.verificarVagasDisponiveis(_vagasDisponiveis)) {
        if (_isMounted) {
          setState(() {
            _mensagem = 'Desculpe, as vagas estão esgotadas.';
            _enviando = false;
            _processandoEnvio = false;
          });
        }
        return;
      }

      String? fotoUrl = _fotoUrl;
      if (_fotoBytes != null && _fotoNome != null) {
        fotoUrl = await _service.uploadArquivo(
          _fotoBytes!,
          'fotos_competidores',
          '${DateTime.now().millisecondsSinceEpoch}_${_fotoNome!}',
        );
      }

      String? comprovanteUrl = _comprovanteUrl;
      // 🔥 Se for aluno encontrado, não faz upload de comprovante
      if (!_alunoEncontrado && _comprovanteBytes != null && _comprovanteNome != null) {
        comprovanteUrl = await _service.uploadArquivo(
          _comprovanteBytes!,
          'comprovantes_pagamento',
          '${DateTime.now().millisecondsSinceEpoch}_${_comprovanteNome!}',
        );
      }

      final isMaior = _isMaiorIdade();

      final inscricao = InscricaoModel(
        nome: _toUpperCase(_controllers['nome']!.text),
        apelido: _toUpperCase(_controllers['apelido']!.text),
        dataNascimento: _controllers['data_nascimento']!.text.trim(),
        idade: _idade,
        sexo: _sexo!,
        cpf: _controllers['cpf']!.text,
        contatoAluno: _controllers['contato_aluno']!.text,
        endereco: _gerarEnderecoCompleto(),
        cidade: _toUpperCase(_controllers['cidade']!.text),
        grupo: _toUpperCase(_controllers['grupo']!.text),
        professorNome: _toUpperCase(_controllers['professor_nome']!.text),
        professorContato: _controllers['professor_contato']!.text,
        isGrupoUai: _isGrupoSelecionadoUai,
        graduacaoId: _isGrupoSelecionadoUai ? _graduacaoSelecionada : null,
        graduacaoNome: _isGrupoSelecionadoUai
            ? (_graduacaoInfo?['nome_graduacao'])
            : _toUpperCase(_controllers['outra_graduacao']!.text),
        categoriaId: _categoriaSelecionada,
        categoriaNome: _categoriaInfo?.nome,
        autorizacao: _autorizacao,
        termoAutorizacao: _gerarTermoTexto(),
        regulamento: _gerarRegulamentoCompleto(),
        status: 'pendente',
        isMaiorIdade: isMaior,
        assinaturaRecolhida: _recolherAssinatura,
        assinaturaUrl: _assinaturaUrl,
        nomeCampeonato: _nomeCampeonato,
        dataEvento: _dataEvento,
        taxaPaga: _alunoEncontrado, // 🔥 Se encontrou aluno, já está pago!
        taxaInscricao: _taxaInscricao,
        fotoUrl: fotoUrl,
        comprovanteUrl: comprovanteUrl,
      );

      _inscricaoId = await _service.salvarInscricao(inscricao);

      if (_isMounted) {
        setState(() => _enviando = false);
        await _mostrarDialogSucesso();

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LandingPage()),
                (route) => false,
          );
        }
      }
    } catch (e) {
      print('❌ Erro ao salvar: $e');
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar inscrição: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _enviando = false;
          _processandoEnvio = false;
        });
      }
    }
  }

  Future<void> _mostrarDialogSucesso() async {
    final isMaior = _isMaiorIdade();
    final nomeResponsavel = _getPrimeiroNome(_controllers['nome_responsavel']!.text.isNotEmpty
        ? _controllers['nome_responsavel']!.text
        : _controllers['nome']!.text);
    final nomeAluno = _getPrimeiroNome(_controllers['nome']!.text);

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
            maxWidth: 500,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSucessoHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildSucessoBoasVindas(isMaior, nomeAluno, nomeResponsavel),
                      const SizedBox(height: 16),
                      _buildSucessoResumo(),
                      const SizedBox(height: 16),
                      _buildSucessoPassos(),
                      if (_inscricaoId != null) _buildSucessoProtocolo(),
                    ],
                  ),
                ),
              ),
              _buildSucessoBotao(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSucessoHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.emoji_events, color: Colors.white, size: 60),
          ),
          const SizedBox(height: 16),
          const Text(
            AppStrings.tituloSucesso,
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildSucessoBoasVindas(bool isMaior, String nomeAluno, String nomeResponsavel) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.waving_hand, color: AppColors.primary, size: 32),
          const SizedBox(height: 8),
          Text(
            isMaior ? 'Olá, $nomeAluno!' : 'Olá, $nomeResponsavel!',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
          ),
          const SizedBox(height: 4),
          Text(
            isMaior
                ? 'Sua inscrição foi recebida!'
                : 'Inscrição de $nomeAluno recebida!',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildSucessoResumo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _buildInfoDialog('Competidor', _controllers['nome']!.text),
          _buildInfoDialog('Categoria', _categoriaInfo?.nome),
          _buildInfoDialog('Grupo', _controllers['grupo']!.text),
          _buildInfoDialog('Graduação',
              _isGrupoSelecionadoUai
                  ? (_graduacaoInfo?['nome_graduacao'])
                  : _controllers['outra_graduacao']!.text),
          if (_alunoEncontrado) ...[
            const Divider(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.successLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: AppColors.success),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '✅ Aluno UAI - Taxa inclusa no batizado',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSucessoPassos() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.successLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.access_time, color: AppColors.success),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🔔 PRÓXIMOS PASSOS:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('1️⃣ Aguarde a confirmação da inscrição\n2️⃣ Prepare-se para o campeonato!', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSucessoProtocolo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.confirmation_number, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Protocolo: ${_inscricaoId!.substring(0, 8)}...',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSucessoBotao() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text(AppStrings.botaoFinalizar, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildInfoDialog(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          Expanded(child: Text(value ?? 'Não informado', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  // ==================== NAVEGAÇÃO ====================

  void _proximaEtapa() {
    if (_currentStep < 3 && _etapaValida[_currentStep] == true) {
      setState(() => _currentStep++);
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _etapaAnterior() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  Future<bool> _onWillPop() async {
    if (_enviando || _processandoEnvio) return false;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LandingPage()),
          (route) => false,
    );
    return false;
  }

  void _mostrarRegulamento() {
    showDialog(
      context: context,
      builder: (context) => RegulamentoCampeonatoDialog(
        regulamento: _gerarRegulamentoCompleto(),
      ),
    );
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_inscricoesAbertas) {
      return _buildInscricoesFechadas();
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: _buildAppBar(),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              width: double.infinity,
              height: double.infinity,
              child: _enviando
                  ? _buildEnviando()
                  : Column(
                children: [
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildStepWelcome(constraints),
                        _buildStepDadosCompletos(constraints),
                        _buildStepGrupoEGraduacao(constraints),
                        _buildStepRevisao(constraints),
                      ],
                    ),
                  ),
                  _buildNavigationButtons(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Text('🏆 $_nomeCampeonato'),
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _onWillPop,
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(4),
        child: LinearProgressIndicator(
          value: (_currentStep + 1) / 4,
          backgroundColor: Colors.white.withOpacity(0.3),
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      ),
    );
  }

  Widget _buildInscricoesFechadas() {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LandingPage()),
              (route) => false,
        );
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('🏆 Inscrição Campeonato'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LandingPage()),
                    (route) => false,
              );
            },
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 20),
                Text(
                  'Inscrições Fechadas',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 10),
                Text(
                  _mensagem.isNotEmpty ? _mensagem : 'No momento não estamos aceitando inscrições.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const LandingPage()),
                          (route) => false,
                    );
                  },
                  child: const Text(AppStrings.botaoVoltarInicio),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEnviando() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            'Enviando sua inscrição...',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  // ==================== ETAPA 0 - BOAS-VINDAS ====================
  Widget _buildStepWelcome(BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < 600;
    final padding = isMobile ? 16.0 : 24.0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 800),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                height: isMobile ? 100 : 120,
                child: Image.asset(
                  'assets/images/logo_principal.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: isMobile ? 100 : 120,
                      height: isMobile ? 100 : 120,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.emoji_events,
                        size: isMobile ? 50 : 60,
                        color: AppColors.primary,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              // Nome do campeonato
              Text(
                _nomeCampeonato,
                style: TextStyle(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Card de informações do evento
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primaryLight),
                ),
                child: Column(
                  children: [
                    _buildInfoRow(Icons.calendar_today, 'Data: $_dataEvento'),
                    const Divider(height: 16),
                    _buildInfoRow(Icons.access_time, 'Horário: $_horarioEvento'),
                    const Divider(height: 16),
                    _buildInfoRow(Icons.location_on, 'Local: $_localEvento'),
                    const Divider(height: 16),
                    _buildInfoRow(Icons.attach_money, 'Taxa: R\$ ${_taxaInscricao.toStringAsFixed(2)}'),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Botão do regulamento
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.info),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.infoSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.gavel, color: AppColors.info),
                  ),
                  title: const Text('REGULAMENTO', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Leia as regras do campeonato'),
                  trailing: Icon(Icons.arrow_forward, color: AppColors.info),
                  onTap: _mostrarRegulamento,
                ),
              ),
              const SizedBox(height: 16),

              // 👇 AVISOS CONDICIONAIS

              // Site inativo
              if (_configuracoesCarregadas && !_inscricoesAbertas) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock, color: AppColors.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '🔒 INSCRIÇÕES FECHADAS',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.error,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'O campeonato está inativo no momento.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Não está recebendo inscrições
              if (_configuracoesCarregadas && _inscricoesAbertas && !_recebendoInscricoes) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.pause_circle, color: AppColors.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '⏸️ INSCRIÇÕES PAUSADAS',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.error,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'As inscrições foram temporariamente pausadas.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Fora do período
              if (_configuracoesCarregadas && _inscricoesAbertas && _recebendoInscricoes && !_periodoValido) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.warning),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event, color: AppColors.warning),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _mensagemPeriodo,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Sem vagas
              if (_configuracoesCarregadas && _inscricoesAbertas && _recebendoInscricoes && _periodoValido && !_temVagas) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.warning),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_busy, color: AppColors.warning),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '⛔ INSCRIÇÕES ESGOTADAS',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.warning,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Todas as $_vagasDisponiveis vagas foram preenchidas.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ✅ Tudo ok! Pode inscrever
              if (_configuracoesCarregadas && _inscricoesAbertas && _recebendoInscricoes && _periodoValido && _temVagas) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.success),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info, color: AppColors.success),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🎯 $_vagasRestantes vagas disponíveis',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.success,
                                  fontWeight: FontWeight.bold
                              ),
                            ),
                            Text(
                              '${_categorias.length} categorias disponíveis',
                              style: TextStyle(fontSize: 12, color: AppColors.success),
                            ),
                            if (_dataInicioInscricoes != null && _dataFimInscricoes != null)
                              Text(
                                'Período: ${DateFormat('dd/MM').format(_dataInicioInscricoes!)} a ${DateFormat('dd/MM/yyyy').format(_dataFimInscricoes!)}',
                                style: TextStyle(fontSize: 11, color: AppColors.success),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==================== ETAPA 1 - DADOS COMPLETOS ====================
  Widget _buildStepDadosCompletos(BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < 600;
    final isTablet = constraints.maxWidth >= 600 && constraints.maxWidth < 900;
    final padding = isMobile ? 16.0 : 24.0;
    final isMaior = _isMaiorIdade();

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(AppStrings.tituloDadosCompetidor, AppColors.primary),
              const SizedBox(height: 16),

              // 🔥 NOME COM INDICADOR DE BUSCA
              if (isMobile) ...[
                Stack(
                  children: [
                    _buildTextField(
                      _controllers['nome']!,
                      AppStrings.labelNome,
                      readOnly: _alunoEncontrado,
                      focusNode: _nomeFocusNode,
                      onEditingComplete: () {
                        _buscarAluno();
                        FocusScope.of(context).nextFocus();
                      },
                    ),
                    if (_buscandoAluno)
                      const Positioned(
                        right: 12,
                        top: 12,
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildTextField(_controllers['apelido']!, AppStrings.labelApelido),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          _buildTextField(
                            _controllers['nome']!,
                            AppStrings.labelNome,
                            readOnly: _alunoEncontrado,
                            focusNode: _nomeFocusNode,
                            onEditingComplete: () {
                              _buscarAluno();
                              FocusScope.of(context).nextFocus();
                            },
                          ),
                          if (_buscandoAluno)
                            const Positioned(
                              right: 12,
                              top: 12,
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _buildTextField(_controllers['apelido']!, AppStrings.labelApelido)),
                  ],
                ),
              ],
              const SizedBox(height: 12),

              // 🔥 SE ENCONTROU ALUNO, MOSTRA MENSAGEM SUTIL
              if (_alunoEncontrado) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 14, color: AppColors.success),
                      SizedBox(width: 6),
                      Text(
                        'Aluno UAI identificado',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.success,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: _buildDateField(_controllers['data_nascimento']!, AppStrings.labelDataNascimento)),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _sexo,
                      decoration: const InputDecoration(
                        labelText: AppStrings.labelSexo,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: null, child: Text(AppStrings.placeholderSelecione)),
                        DropdownMenuItem(value: 'MASCULINO', child: Text(AppStrings.sexoMasculino)),
                        DropdownMenuItem(value: 'FEMININO', child: Text(AppStrings.sexoFeminino)),
                      ],
                      onChanged: (v) {
                        if (_isMounted) {
                          setState(() => _sexo = v);
                          _validarEtapa1();
                        }
                      },
                    ),
                  ),
                  if (!isMobile) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$_idade',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const Text('anos', style: TextStyle(fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (isMobile && _idade > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Idade: $_idade anos', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(child: _buildCpfField(isMaior)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildPhoneField(_controllers['contato_aluno']!, AppStrings.labelTelefone)),
                ],
              ),
              const SizedBox(height: 20),

              _buildSectionHeader(AppStrings.tituloEndereco, Colors.blue),
              const SizedBox(height: 16),

              if (isMobile) ...[
                _buildTextField(_controllers['rua']!, AppStrings.labelRua),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildTextField(
                        _controllers['numero']!,
                        AppStrings.labelNumero,
                        isNumberOnly: true,
                        maxLength: 5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: _buildTextField(_controllers['bairro']!, AppStrings.labelBairro),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(flex: 3, child: _buildTextField(_controllers['rua']!, AppStrings.labelRua)),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: _buildTextField(
                        _controllers['numero']!,
                        AppStrings.labelNumero,
                        isNumberOnly: true,
                        maxLength: 5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: _buildTextField(_controllers['bairro']!, AppStrings.labelBairro)),
                  ],
                ),
              ],
              const SizedBox(height: 12),

              _buildTextField(
                _controllers['cidade']!,
                AppStrings.labelCidade,
                allowNumbers: true,
              ),
              const SizedBox(height: 20),

              if (_controllers['data_nascimento']!.text.isNotEmpty && !isMaior) ...[
                _buildSectionHeader(AppStrings.tituloResponsavel, Colors.purple),
                const SizedBox(height: 16),
                _buildTextField(_controllers['nome_responsavel']!, 'Nome do Responsável *'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildPhoneField(_controllers['contato_responsavel']!, 'Telefone *')),
                    const SizedBox(width: 12),
                    Expanded(child: _buildCpfField(true, isResponsavel: true)),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              if (_exigirFotoCompetidor) ...[
                _buildSectionHeader('📸 FOTO DO COMPETIDOR', Colors.orange),
                const SizedBox(height: 16),
                _buildFotoUpload(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==================== ETAPA 2 - GRUPO E GRADUAÇÃO ====================
  Widget _buildStepGrupoEGraduacao(BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < 600;
    final isTablet = constraints.maxWidth >= 600 && constraints.maxWidth < 900;
    final padding = isMobile ? 16.0 : 24.0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(AppStrings.tituloGrupoGraduacao, Colors.orange),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.info),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.info),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Caso seu grupo não esteja na lista, entre em contato com a organização!',
                        style: TextStyle(color: AppColors.info, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

              _carregandoGrupos
                  ? const Center(child: CircularProgressIndicator())
                  : _gruposConvidados.isEmpty
                  ? Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning),
                ),
                child: Column(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 32),
                    const SizedBox(height: 12),
                    Text(
                      _erroGrupos ?? 'Nenhum grupo encontrado',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _carregarGruposConvidados,
                      icon: const Icon(Icons.refresh),
                      label: const Text(AppStrings.botaoTentarNovamente),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warning,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              )
                  : DropdownButtonFormField<String>(
                value: _grupoSelecionado,
                hint: const Text(AppStrings.placeholderSelecioneGrupo),
                items: _gruposConvidados.map<DropdownMenuItem<String>>((GrupoModel grupo) {
                  return DropdownMenuItem<String>(
                    value: grupo.nome,
                    child: Text(grupo.nome),
                  );
                }).toList(),
                onChanged: _alunoEncontrado
                    ? null
                    : (String? value) {
                  setState(() {
                    _grupoSelecionado = value;
                    _controllers['grupo']!.text = value ?? '';
                    _isGrupoSelecionadoUai = value == 'GRUPO UAI CAPOEIRA';
                    _graduacaoSelecionada = null;
                    _graduacaoInfo = null;
                    _controllers['outra_graduacao']!.clear();
                  });
                  _validarEtapa2();
                },
                decoration: const InputDecoration(
                  labelText: AppStrings.labelGrupo,
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return AppStrings.validacaoGrupoObrigatorio;
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),

              Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade200, Colors.orange.shade400, Colors.orange.shade200],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              if (_grupoSelecionado != null) ...[
                if (_isGrupoSelecionadoUai) ...[
                  _buildSectionHeader('🎓 GRADUAÇÃO DO COMPETIDOR', Colors.green),
                  const SizedBox(height: 16),

                  _graduacoesUai.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : Container(
                    height: isMobile ? 250 : (isTablet ? 300 : 350),
                    child: GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isMobile ? 3 : (isTablet ? 4 : 5),
                        childAspectRatio: 0.8,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _graduacoesUai.length,
                      itemBuilder: (context, index) {
                        final grad = _graduacoesUai[index];
                        final isSelected = _graduacaoSelecionada == grad['id'];

                        return GestureDetector(
                          onTap: _alunoEncontrado
                              ? null
                              : () {
                            if (_isMounted) {
                              setState(() {
                                _graduacaoSelecionada = grad['id'];
                                _graduacaoInfo = grad;
                              });
                              _validarEtapa2();
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.successLight : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? AppColors.success : Colors.grey.shade300,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_svgContent != null)
                                  Container(
                                    height: 50,
                                    child: SvgPicture.string(
                                      _getModifiedSvg(grad),
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  grad['nome_graduacao'] ?? '',
                                  style: TextStyle(
                                    fontSize: isMobile ? 10 : 11,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ] else ...[
                  _buildSectionHeader('🎓 GRADUAÇÃO DO COMPETIDOR', Colors.green),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _controllers['outra_graduacao']!,
                    AppStrings.labelGraduacao,
                    allowNumbers: true,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      AppStrings.ajudaGraduacao,
                      style: TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 20),

              _buildSectionHeader(AppStrings.tituloProfessor, Colors.purple),
              const SizedBox(height: 16),
              _buildTextField(
                _controllers['professor_nome']!,
                AppStrings.labelProfessor,
                readOnly: _alunoEncontrado,
              ),
              const SizedBox(height: 12),
              _buildPhoneField(
                _controllers['professor_contato']!,
                AppStrings.labelProfessorContato,
                readOnly: _alunoEncontrado,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== ETAPA 3 - REVISÃO E CATEGORIA ====================
  Widget _buildStepRevisao(BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < 600;
    final padding = isMobile ? 16.0 : 24.0;
    final isMaior = _isMaiorIdade();
    final precisaAssinar = _recolherAssinatura && _assinaturaUrl == null;

    // 🔥 FILTRA CATEGORIAS COMPATÍVEIS COM IDADE E SEXO
    final categoriasFiltradas = _categorias.where((cat) => cat.isCompativel(_idade, _sexo)).toList();

    // 🔥 VERIFICA SE TEM CATEGORIA PARA A GRADUAÇÃO DO ALUNO
    bool temCategoriaParaGraduacao = true;
    String mensagemGraduacao = '';

    if (_isGrupoSelecionadoUai && _graduacaoInfo != null) {
      final nivelGraduacao = _graduacaoInfo?['nivel_graduacao'] ?? 0;

      // Se for formado (nivel > 14), não tem categoria
      if (nivelGraduacao > 14) {
        temCategoriaParaGraduacao = false;
        mensagemGraduacao = '⚠️ SUA GRADUAÇÃO É SUPERIOR ÀS CATEGORIAS DISPONÍVEIS\n\n'
            'O campeonato é exclusivo para ALUNOS (até 14º nível). '
            'Formados (Monitores, Instrutores, Professores, Contramestres e Mestres) '
            'não podem competir, mas podem participar como jurados ou apoiadores.';
      }
    }

    if (categoriasFiltradas.length == 1 && _categoriaSelecionada == null && _isMounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isMounted) {
          setState(() {
            _categoriaSelecionada = categoriasFiltradas.first.id;
            _categoriaInfo = categoriasFiltradas.first;
            _validarEtapaFinal();
          });
        }
      });
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(AppStrings.tituloRevisao, Colors.green),
              const SizedBox(height: 16),

              // 🔥 ALERTA DE GRADUAÇÃO SUPERIOR
              if (!temCategoriaParaGraduacao) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error, width: 2),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 48, color: AppColors.error),
                      const SizedBox(height: 12),
                      Text(
                        'GRADUAÇÃO NÃO PERMITIDA',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        mensagemGraduacao,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          // Volta para a tela inicial
                          _pageController.jumpToPage(0);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('ENTENDI, VOLTAR'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Só mostra a seleção de categoria se tiver categoria para graduação
              if (temCategoriaParaGraduacao) ...[
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('🎯 SELECIONE A CATEGORIA', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        if (categoriasFiltradas.isEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.warningLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.info, color: AppColors.warning, size: 32),
                                const SizedBox(height: 8),
                                const Text(
                                  'Nenhuma categoria disponível para seu perfil',
                                  style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Idade: $_idade anos • Sexo: ${_sexo ?? "Não informado"}',
                                  style: TextStyle(color: AppColors.warning),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          ...categoriasFiltradas.map((cat) => RadioListTile<String>(
                            title: Text(cat.nome),
                            subtitle: Text('${cat.idadeMin}-${cat.idadeMax} anos • ${cat.sexo} • R\$ ${cat.taxa.toStringAsFixed(2)} • ${cat.vagas} vagas'),
                            value: cat.id,
                            groupValue: _categoriaSelecionada,
                            onChanged: (value) {
                              if (_isMounted) {
                                setState(() {
                                  _categoriaSelecionada = value;
                                  _categoriaInfo = cat;
                                  _validarEtapaFinal();
                                });
                              }
                            },
                            dense: true,
                          )),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Resumo dos Dados
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildResumoLinhaIcon(Icons.person, 'Competidor', _controllers['nome']!.text, Colors.blue),
                        const Divider(height: 16),
                        _buildResumoLinhaIcon(Icons.cake, 'Idade', '$_idade anos', Colors.orange),
                        const Divider(height: 16),
                        _buildResumoLinhaIcon(Icons.group, 'Grupo', _controllers['grupo']!.text, Colors.purple),
                        const Divider(height: 16),
                        _buildResumoLinhaIcon(Icons.grade, 'Graduação',
                            _isGrupoSelecionadoUai
                                ? (_graduacaoInfo?['nome_graduacao'] ?? '')
                                : _controllers['outra_graduacao']!.text,
                            Colors.green),
                        if (_alunoEncontrado) ...[
                          const Divider(height: 16),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.successLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.check_circle, size: 16, color: AppColors.success),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '✅ Aluno UAI - Taxa inclusa no batizado',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.success,
                                      fontWeight: FontWeight.bold,
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
                ),
              ],

              const SizedBox(height: 24),

              _buildTermoElaborado(),
              const SizedBox(height: 16),

              // 🔥 SÓ MOSTRA PIX E COMPROVANTE SE NÃO FOR ALUNO ENCONTRADO E TIVER CATEGORIA
              if (!_alunoEncontrado && temCategoriaParaGraduacao) ...[
                if (_exigirComprovantePagamento && _comprovanteBytes == null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.infoLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.info),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.pix, color: AppColors.info),
                            SizedBox(width: 8),
                            Text(AppStrings.tituloPix, style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 16),

                        if (_chavePix.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(AppStrings.pixChave, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(child: SelectableText(_chavePix, style: const TextStyle(fontSize: 14))),
                                    IconButton(
                                      icon: const Icon(Icons.copy, size: 20, color: AppColors.info),
                                      onPressed: _copiarChavePix,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (_informacoesBancarias.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(AppStrings.pixInfoBancaria, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                SelectableText(_informacoesBancarias, style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (_instrucoesPagamento.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(AppStrings.pixInstrucoes, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                SelectableText(_instrucoesPagamento, style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],

                        const Text(
                          AppStrings.pixAposPagamento,
                          style: TextStyle(fontSize: 12, color: AppColors.info),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_exigirComprovantePagamento && temCategoriaParaGraduacao) ...[
                  _buildComprovanteUpload(),
                  const SizedBox(height: 16),
                ],
              ],

              // SÓ MOSTRA O CHECKBOX SE TIVER CATEGORIA
              if (temCategoriaParaGraduacao) ...[
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: CheckboxListTile(
                    value: _autorizacao,
                    onChanged: (value) {
                      if (_isMounted) {
                        setState(() {
                          _autorizacao = value ?? false;
                          _validarEtapaFinal();
                        });
                      }
                    },
                    title: Text(
                      isMaior
                          ? '☑️ Li e concordo com todos os termos acima'
                          : '☑️ Li e concordo com todos os termos acima como responsável',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.success,
                  ),
                ),

                if (precisaAssinar) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: AppColors.error),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            '⚠️ Você precisa assinar o termo antes de finalizar',
                            style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_recolherAssinatura) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _assinaturaUrl == null ? _abrirTelaAssinatura : null,
                      icon: Icon(
                        _assinaturaUrl == null ? Icons.draw : Icons.check_circle,
                        color: Colors.white,
                        size: 28,
                      ),
                      label: Text(
                        _assinaturaUrl == null ? AppStrings.botaoAssinar : AppStrings.botaoAssinado,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _assinaturaUrl == null ? AppColors.primary : AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==================== WIDGETS REUTILIZÁVEIS ====================

  Widget _buildFotoUpload() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          if (_fotoBytes != null)
            Container(
              height: 150,
              child: Image.memory(
                _fotoBytes!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 50),
              ),
            )
          else if (_fotoUrl != null)
            Container(
              height: 150,
              child: Image.network(
                _fotoUrl!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 50),
              ),
            )
          else
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Icon(Icons.photo_camera, size: 40, color: Colors.grey),
              ),
            ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _selecionarFoto,
            icon: const Icon(Icons.photo_camera),
            label: Text(_fotoBytes != null ? AppStrings.botaoTrocarFoto : AppStrings.botaoSelecionarFoto),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComprovanteUpload() {
    // 🔥 Se for aluno encontrado, não mostra o botão de upload
    if (_alunoEncontrado) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(AppStrings.tituloComprovante, style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Taxa: R\$ ${_taxaInscricao.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          if (_comprovanteBytes != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.successLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _comprovanteNome ?? 'Arquivo selecionado',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _selecionarComprovante,
            icon: const Icon(Icons.upload_file),
            label: Text(_comprovanteBytes != null ? AppStrings.botaoTrocarComprovante : AppStrings.botaoUpload),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.info,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermoElaborado() {
    final isMaior = _isMaiorIdade();
    final nomeAluno = _controllers['nome']!.text;
    final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                AppStrings.tituloTermo,
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _gerarTermoTexto(),
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.infoLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: AppColors.info),
                const SizedBox(width: 8),
                Text(
                  'Data e hora: $dataHora',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.info,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String titulo, Color cor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, color: cor, size: 8),
          const SizedBox(width: 8),
          Text(
            titulo,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoLinhaIcon(IconData icon, String label, String valor, Color cor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: cor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: cor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              Text(valor, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String texto) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(texto, style: const TextStyle(fontSize: 13))),
      ],
    );
  }

  Widget _buildNavigationButtons() {
    final bool podeAvancar = _etapaValida[_currentStep] ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, -3))],
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _etapaAnterior,
                icon: const Icon(Icons.arrow_back),
                label: const Text(AppStrings.botaoVoltar),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            flex: _currentStep == 0 ? 2 : 1,
            child: ElevatedButton.icon(
              onPressed: _currentStep == 3
                  ? (podeAvancar ? _enviarInscricao : null)
                  : (podeAvancar ? _proximaEtapa : null),
              icon: Icon(_currentStep == 3 ? Icons.send : Icons.arrow_forward),
              label: Text(
                _currentStep == 3 ? AppStrings.botaoEnviar : AppStrings.botaoContinuar,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller,
      String label, {
        bool isNumberOnly = false,
        bool allowNumbers = false,
        int? maxLength,
        bool readOnly = false,
        FocusNode? focusNode,
        VoidCallback? onEditingComplete,
      }) {
    RegExp regex;
    if (allowNumbers) {
      regex = RegExp(r'^[A-Za-zÀ-ÖØ-öø-ÿ0-9\s\-°ºª\.]+$');
    } else if (isNumberOnly) {
      regex = RegExp(r'^[0-9]+$');
    } else {
      regex = RegExp(r'^[A-Za-zÀ-ÖØ-öø-ÿ\s]+$');
    }

    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      readOnly: readOnly,
      onEditingComplete: onEditingComplete,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        counterText: '',
        filled: readOnly,
        fillColor: readOnly ? Colors.grey.shade100 : null,
      ),
      keyboardType: isNumberOnly ? TextInputType.number : TextInputType.text,
      inputFormatters: [
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
      ],
      textCapitalization: TextCapitalization.characters,
      onChanged: (_) => _validarCampos(),
      validator: (value) {
        if (value == null || value.isEmpty) return null;
        if (!regex.hasMatch(value)) {
          return AppStrings.validacaoCaractereInvalido;
        }
        return null;
      },
    );
  }

  Widget _buildPhoneField(TextEditingController controller, String label, {bool readOnly = false}) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        hintText: AppStrings.placeholderTelefone,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        errorText: controller.text.isNotEmpty && controller.text.length < 14
            ? AppStrings.validacaoTelefoneIncompleto
            : null,
        filled: readOnly,
        fillColor: readOnly ? Colors.grey.shade100 : null,
      ),
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
        _PhoneInputFormatter(),
      ],
      onChanged: (_) => _validarCampos(),
    );
  }

  Widget _buildCpfField(bool isMaior, {bool isResponsavel = false}) {
    final controller = isResponsavel ? _controllers['cpf_responsavel']! : _controllers['cpf']!;
    final label = isResponsavel
        ? AppStrings.labelCpf
        : (isMaior ? AppStrings.labelCpf : AppStrings.labelCpfOpcional);

    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: AppStrings.placeholderCpf,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
        _CpfInputFormatter(),
      ],
      onChanged: (_) => _validarCampos(),
    );
  }

  Widget _buildDateField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_today),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        errorText: controller.text.isEmpty ? AppStrings.validacaoCampoObrigatorio : null,
      ),
      readOnly: true,
      onTap: () => _selectDate(context, controller),
    );
  }

  Future<void> _selectDate(BuildContext context, TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 3650)),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      locale: const Locale('pt', 'BR'),
    );

    if (picked != null && _isMounted) {
      setState(() {
        controller.text = DateFormat('dd/MM/yyyy').format(picked);
        _atualizarIdade(controller.text);
      });
    }
  }
}

class _CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 11) digits = digits.substring(0, 11);

    String formatted = '';
    if (digits.length <= 3) {
      formatted = digits;
    } else if (digits.length <= 6) {
      formatted = '${digits.substring(0, 3)}.${digits.substring(3)}';
    } else if (digits.length <= 9) {
      formatted = '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6)}';
    } else {
      formatted = '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9)}';
    }
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

class _PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 11) digits = digits.substring(0, 11);

    String formatted = '';
    if (digits.length <= 2) {
      formatted = '($digits';
    } else if (digits.length <= 6) {
      formatted = '(${digits.substring(0, 2)}) ${digits.substring(2)}';
    } else if (digits.length <= 10) {
      formatted = '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    } else {
      formatted = '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7, 11)}';
    }
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}