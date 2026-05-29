
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:xml/xml.dart' as xml;

import 'package:uai_capoeira/core/constants/app_strings.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/campeonatos/models/categoria_model.dart';
import 'package:uai_capoeira/modules/campeonatos/models/grupo_model.dart';
import 'package:uai_capoeira/modules/campeonatos/services/campeonato_service.dart';
import 'package:uai_capoeira/modules/campeonatos/widgets/regulamento_campeonato_dialog.dart';
import 'package:uai_capoeira/modules/inscricoes/models/inscricao_model.dart';
import 'package:uai_capoeira/modules/inscricoes/public/signature_screen.dart';
import 'package:uai_capoeira/modules/site/screens/landing_page.dart';

class InscricaoCampeonatoScreen extends StatefulWidget {
  const InscricaoCampeonatoScreen({super.key});

  @override
  State<InscricaoCampeonatoScreen> createState() =>
      _InscricaoCampeonatoScreenState();
}

class _InscricaoCampeonatoScreenState extends State<InscricaoCampeonatoScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final CampeonatoService _service = CampeonatoService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late final PageController _pageController;
  late final AnimationController _animController;
  final FocusNode _nomeFocusNode = FocusNode();

  int _currentStep = 0;

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

  String? _sexo;
  String? _categoriaSelecionada;
  CategoriaModel? _categoriaInfo;

  String? _graduacaoSelecionada;
  Map<String, dynamic>? _graduacaoInfo;
  List<Map<String, dynamic>> _graduacoesUai = [];
  String? _svgContent;

  int _idade = 0;
  bool _autorizacao = false;

  List<GrupoModel> _gruposConvidados = [];
  bool _carregandoGrupos = true;
  String? _grupoSelecionado;
  String? _erroGrupos;
  bool _isGrupoSelecionadoUai = false;

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

  bool _recebendoInscricoes = true;
  DateTime? _dataInicioInscricoes;
  DateTime? _dataFimInscricoes;
  bool _periodoValido = true;
  String _mensagemPeriodo = '';

  String _chavePix = '';
  String _informacoesBancarias = '';
  String _instrucoesPagamento = '';

  List<CategoriaModel> _categorias = [];

  String? _assinaturaUrl;
  Uint8List? _assinaturaBytes;
  bool _uploadingAssinatura = false;

  String? _fotoUrl;
  String? _comprovanteUrl;
  Uint8List? _fotoBytes;
  Uint8List? _comprovanteBytes;
  String? _fotoNome;
  String? _comprovanteNome;

  bool _carregando = true;
  bool _enviando = false;
  bool _buscandoAluno = false;
  bool _alunoEncontrado = false;
  bool _alunoFormado = false;
  String _mensagem = '';
  bool _isMounted = true;
  bool _processandoEnvio = false;
  String? _inscricaoId;

  final Map<int, bool> _etapaValida = {
    0: false,
    1: false,
    2: false,
    3: false,
  };

  final TextInputFormatter _phoneFormatter =
  FilteringTextInputFormatter.allow(RegExp(r'[0-9()\-\s]'));
  final TextInputFormatter _cpfFormatter =
  FilteringTextInputFormatter.allow(RegExp(r'[0-9\.\-]'));

  @override
  void initState() {
    super.initState();

    _pageController = PageController();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    WidgetsBinding.instance.addObserver(this);
    _nomeFocusNode.addListener(_onNomeFocusLost);

    for (final controller in _controllers.values) {
      controller.addListener(_validarCampos);
    }

    _carregarDadosIniciais();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isMounted = false;

    _nomeFocusNode.removeListener(_onNomeFocusLost);
    _nomeFocusNode.dispose();

    for (final controller in _controllers.values) {
      controller.removeListener(_validarCampos);
      controller.dispose();
    }

    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff =
    (color.computeLuminance() - background.computeLuminance()).abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  void _showSnack(String message, {Color? color}) {
    final t = context.uai;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color ?? t.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _carregarDadosIniciais() async {
    try {
      await Future.wait([
        _verificarInscricoes(),
        _carregarGraduacoes(),
        _loadSvg(),
      ]);

      await _carregarGruposConvidados();
    } catch (e) {
      debugPrint('❌ Erro ao carregar dados iniciais: $e');
      if (_isMounted) {
        setState(() {
          _carregando = false;
          _mensagem = 'Erro ao carregar dados do campeonato.';
        });
      }
    }
  }

  Future<void> _loadSvg() async {
    try {
      final content = await DefaultAssetBundle.of(context)
          .loadString('assets/images/corda.svg');

      if (_isMounted) {
        setState(() => _svgContent = content);
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar SVG: $e');
    }
  }

  Future<void> _carregarGraduacoes() async {
    try {
      final graduacoes = await _service.carregarGraduacoesUai();

      if (_isMounted) {
        setState(() => _graduacoesUai = graduacoes);
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar graduações: $e');
    }
  }

  Future<void> _carregarGruposConvidados() async {
    if (_isMounted) {
      setState(() {
        _carregandoGrupos = true;
        _erroGrupos = null;
      });
    }

    try {
      final grupos = await _service.carregarGruposConvidados();

      if (_isMounted) {
        setState(() {
          _gruposConvidados = grupos;
          _carregandoGrupos = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar grupos: $e');

      if (_isMounted) {
        setState(() {
          _gruposConvidados = [];
          _carregandoGrupos = false;
          _erroGrupos = 'Erro ao carregar grupos: $e';
        });
      }
    }
  }

  Future<void> _verificarInscricoes() async {
    try {
      final config = await _service.carregarConfiguracoes();

      if (config.isEmpty) {
        if (_isMounted) {
          setState(() {
            _inscricoesAbertas = false;
            _configuracoesCarregadas = true;
            _etapaValida[0] = false;
            _carregando = false;
          });
        }
        return;
      }

      final inscricoesAtivas = await _service.contarInscricoesAtivas();
      final vagasTotal = _parseInt(config['vagas_disponiveis'], 0);
      final vagasRestantes = vagasTotal - inscricoesAtivas;

      _recebendoInscricoes = config['recebendo_inscricoes'] ?? true;

      if (config['data_inicio_inscricoes'] != null) {
        _dataInicioInscricoes =
            (config['data_inicio_inscricoes'] as Timestamp).toDate();
      }

      if (config['data_fim_inscricoes'] != null) {
        _dataFimInscricoes =
            (config['data_fim_inscricoes'] as Timestamp).toDate();
      }

      _periodoValido = true;
      _mensagemPeriodo = '';

      final hoje = DateTime.now();

      if (_dataInicioInscricoes != null && _dataFimInscricoes != null) {
        if (hoje.isBefore(_dataInicioInscricoes!)) {
          _periodoValido = false;
          _mensagemPeriodo =
          '⏳ As inscrições começam em ${DateFormat('dd/MM/yyyy').format(_dataInicioInscricoes!)}';
        } else if (hoje.isAfter(_dataFimInscricoes!)) {
          _periodoValido = false;
          _mensagemPeriodo =
          '⌛ O período de inscrições encerrou em ${DateFormat('dd/MM/yyyy').format(_dataFimInscricoes!)}';
        }
      }

      if (_isMounted) {
        setState(() {
          _inscricoesAbertas = config['campeonato_ativo'] ?? false;
          _nomeCampeonato =
              config['nome_campeonato'] ?? AppStrings.campeonatoTitulo;
          _dataEvento = config['data_evento'] ?? 'A definir';
          _localEvento = config['local_evento'] ?? 'A definir';
          _horarioEvento = config['horario_evento'] ?? 'A definir';
          _taxaInscricao = (config['taxa_inscricao'] ?? 30.0).toDouble();

          _vagasDisponiveis = vagasTotal;
          _vagasRestantes = vagasRestantes;
          _temVagas = vagasRestantes > 0;

          _recolherAssinatura = config['recolher_assinatura'] ?? true;
          _exigirComprovantePagamento =
              config['exigir_comprovante_pagamento'] ?? false;
          _exigirFotoCompetidor =
              config['exigir_foto_competidor'] ?? false;

          _chavePix = config['chave_pix'] ?? '';
          _informacoesBancarias = config['informacoes_bancarias'] ?? '';
          _instrucoesPagamento =
              config['instrucoes_pagamento'] ??
                  'Pague via PIX e envie o comprovante.';

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
      debugPrint('❌ Erro ao verificar inscrições: $e');

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

  int _parseInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  void _onNomeFocusLost() {
    if (!_nomeFocusNode.hasFocus &&
        !_buscandoAluno &&
        !_alunoEncontrado &&
        !_alunoFormado) {
      _buscarAluno();
    }
  }

  Future<void> _buscarAluno() async {
    var nomeBusca = _controllers['nome']!.text.trim();

    if (nomeBusca.isEmpty || _buscandoAluno) return;

    setState(() => _buscandoAluno = true);

    try {
      nomeBusca = nomeBusca.replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

      final snapshot = await _firestore
          .collection('alunos')
          .where('nome', isEqualTo: nomeBusca)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty && mounted) {
        final aluno = snapshot.docs.first.data();
        final nivelGraduacao = _parseInt(aluno['nivel_graduacao'], 0);

        if (nivelGraduacao > 14) {
          _mostrarAlertaFormado();
          _limparTodosCampos();
          setState(() {
            _alunoFormado = true;
            _alunoEncontrado = false;
          });
        } else {
          setState(() {
            _preencherDadosAluno(aluno);
            _alunoEncontrado = true;
            _alunoFormado = false;
          });
        }
      } else {
        setState(() {
          _alunoEncontrado = false;
          _alunoFormado = false;
        });
      }
    } catch (e) {
      debugPrint('Erro na busca de aluno: $e');
    } finally {
      if (mounted) setState(() => _buscandoAluno = false);
    }
  }

  String _formatarTelefone(String numero) {
    final digits = numero.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.length == 11) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7)}';
    }

    if (digits.length == 10) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    }

    return numero;
  }

  void _preencherDadosAluno(Map<String, dynamic> aluno) {
    _controllers['nome']!.text = aluno['nome'] ?? '';
    _controllers['apelido']!.text = aluno['apelido'] ?? '';

    if (aluno['data_nascimento'] != null) {
      final data = (aluno['data_nascimento'] as Timestamp).toDate();
      _controllers['data_nascimento']!.text =
          DateFormat('dd/MM/yyyy').format(data);
      _atualizarIdade(_controllers['data_nascimento']!.text);
    }

    _controllers['cpf']!.text = aluno['cpf'] ?? '';
    _controllers['contato_aluno']!.clear();

    _controllers['rua']!.clear();
    _controllers['numero']!.clear();
    _controllers['bairro']!.clear();
    _controllers['cidade']!.text = aluno['cidade'] ?? '';

    _controllers['nome_responsavel']!.text = aluno['nome_responsavel'] ?? '';
    _controllers['contato_responsavel']!.clear();
    _controllers['cpf_responsavel']!.text = aluno['cpf_responsavel'] ?? '';

    _sexo = aluno['sexo'];

    _isGrupoSelecionadoUai = true;
    _grupoSelecionado = 'GRUPO UAI CAPOEIRA';
    _controllers['grupo']!.text = 'GRUPO UAI CAPOEIRA';

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

    _controllers['professor_nome']!.text = 'TICO - TICO';
    _controllers['professor_contato']!.text = _formatarTelefone('38998262404');

    if (aluno['foto_perfil_aluno'] != null) {
      _fotoUrl = aluno['foto_perfil_aluno'];
      _fotoBytes = null;
    }

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

  void _limparTodosCampos() {
    for (final controller in _controllers.values) {
      controller.clear();
    }

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
      _assinaturaBytes = null;
      _uploadingAssinatura = false;
      _comprovanteUrl = null;
      _comprovanteBytes = null;
      _alunoEncontrado = false;
      _etapaValida[1] = false;
      _etapaValida[2] = false;
      _etapaValida[3] = false;
    });
  }

  void _mostrarAlertaFormado() {
    final t = context.uai;
    final danger = _ensureVisible(t.error, t.surface);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Material(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 2),
              clipBehavior: Clip.antiAlias,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(t.cardRadius + 2),
                  boxShadow: t.cardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: danger.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: danger,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'GRADUAÇÃO NÃO PERMITIDA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'O campeonato é exclusivo para ALUNOS de capoeira até o 14º nível.\n\nFormados não podem competir, mas podem participar como jurados ou apoiadores.\n\nTodos os campos foram limpos para nova tentativa.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: t.textSecondary,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          FocusScope.of(context).requestFocus(_nomeFocusNode);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.primary,
                          foregroundColor: _readableOn(t.primary),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                            BorderRadius.circular(t.buttonRadius),
                          ),
                        ),
                        child: const Text(
                          'ENTENDI',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _validarCampos() {
    if (!_isMounted) return;

    if (_currentStep == 1) {
      _validarEtapa1();
    } else if (_currentStep == 2) {
      _validarEtapa2();
    } else if (_currentStep == 3) {
      _validarEtapaFinal();
    }
  }

  bool _validarNome(String nome) {
    if (nome.trim().isEmpty) return false;
    final regex = RegExp(r'^[A-Za-zÀ-ÖØ-öø-ÿ0-9\s\-°ºª\.]+$');
    return regex.hasMatch(nome);
  }

  bool _isMaiorIdade() => _idade >= 18;

  int _calcularIdade(String dataNascimento) {
    try {
      if (dataNascimento.isEmpty) return 0;
      final data = DateFormat('dd/MM/yyyy').parseStrict(dataNascimento);
      final hoje = DateTime.now();

      var idade = hoje.year - data.year;

      if (hoje.month < data.month ||
          (hoje.month == data.month && hoje.day < data.day)) {
        idade--;
      }

      return idade;
    } catch (_) {
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

    final nomeValido = _controllers['nome']!.text.isNotEmpty &&
        _validarNome(_controllers['nome']!.text);
    final apelidoValido = _controllers['apelido']!.text.isNotEmpty &&
        _validarNome(_controllers['apelido']!.text);
    final dataValida =
        _controllers['data_nascimento']!.text.isNotEmpty && _idade > 0;
    final sexoValido = _sexo != null;
    final contatoValido = _controllers['contato_aluno']!.text.length >= 14;

    final ruaValida = _controllers['rua']!.text.isNotEmpty &&
        _validarNome(_controllers['rua']!.text);
    final numeroValido = _controllers['numero']!.text.isNotEmpty;
    final bairroValido = _controllers['bairro']!.text.isNotEmpty &&
        _validarNome(_controllers['bairro']!.text);
    final cidadeValida = _controllers['cidade']!.text.isNotEmpty;

    var cpfValido = true;
    if (isMaior) cpfValido = _controllers['cpf']!.text.length >= 14;

    var responsavelValido = true;
    if (!isMaior) {
      responsavelValido =
          _controllers['nome_responsavel']!.text.isNotEmpty &&
              _validarNome(_controllers['nome_responsavel']!.text) &&
              _controllers['contato_responsavel']!.text.length >= 14 &&
              _controllers['cpf_responsavel']!.text.length >= 14;
    }

    var fotoValida = true;
    if (_exigirFotoCompetidor) {
      fotoValida = _fotoUrl != null || _fotoBytes != null;
    }

    if (_isMounted) {
      setState(() {
        _etapaValida[1] = nomeValido &&
            apelidoValido &&
            dataValida &&
            cpfValido &&
            sexoValido &&
            contatoValido &&
            ruaValida &&
            numeroValido &&
            bairroValido &&
            cidadeValida &&
            responsavelValido &&
            fotoValida;
      });
    }
  }

  void _validarEtapa2() {
    if (!_isMounted) return;

    final grupoValido = _controllers['grupo']!.text.isNotEmpty &&
        _validarNome(_controllers['grupo']!.text);
    final professorValido =
        _controllers['professor_nome']!.text.isNotEmpty &&
            _validarNome(_controllers['professor_nome']!.text);
    final contatoValido =
        _controllers['professor_contato']!.text.length >= 14;

    bool graduacaoValida;
    if (_isGrupoSelecionadoUai) {
      graduacaoValida = _graduacaoSelecionada != null;
    } else {
      graduacaoValida = _controllers['outra_graduacao']!.text.isNotEmpty;
    }

    if (_isMounted) {
      setState(() {
        _etapaValida[2] =
            grupoValido && professorValido && contatoValido && graduacaoValida;
      });
    }
  }

  void _validarEtapaFinal() {
    var categoriaValida = false;

    if (_categoriaSelecionada != null && _categoriaInfo != null) {
      categoriaValida = _categoriaInfo!.isCompativel(_idade, _sexo);
    }

    var comprovanteValido = true;
    if (_exigirComprovantePagamento && !_alunoEncontrado) {
      comprovanteValido =
          _comprovanteUrl != null || _comprovanteBytes != null;
    }

    if (_isMounted) {
      setState(() {
        _etapaValida[3] = _autorizacao &&
            (_recolherAssinatura
                ? (_assinaturaUrl != null || _assinaturaBytes != null)
                : true) &&
            categoriaValida &&
            comprovanteValido;
      });
    }
  }

  String _toUpperCase(String? text) => text?.toUpperCase().trim() ?? '';

  String _getPrimeiroNome(String? nomeCompleto) {
    if (nomeCompleto == null || nomeCompleto.isEmpty) return '...';
    return nomeCompleto.split(' ')[0];
  }

  String _gerarEnderecoCompleto() {
    final parts = <String>[];

    if (_controllers['rua']!.text.isNotEmpty) {
      var ruaNumero = _toUpperCase(_controllers['rua']!.text);

      if (_controllers['numero']!.text.isNotEmpty) {
        ruaNumero += ' - ${_toUpperCase(_controllers['numero']!.text)}';
      }

      parts.add(ruaNumero);
    }

    if (_controllers['bairro']!.text.isNotEmpty) {
      parts.add(_toUpperCase(_controllers['bairro']!.text));
    }

    if (_controllers['cidade']!.text.isNotEmpty) {
      parts.add(_toUpperCase(_controllers['cidade']!.text));
    }

    return parts.join(', ');
  }

  String _gerarRegulamentoCompleto() {
    var texto = _config['texto_regulamento'] ?? _regulamentoPadrao;

    texto = texto
        .replaceAll('[NOME_CAMPEONATO]', _nomeCampeonato)
        .replaceAll('[DATA_EVENTO]', _dataEvento)
        .replaceAll('[HORARIO_EVENTO]', _horarioEvento)
        .replaceAll('[LOCAL_EVENTO]', _localEvento)
        .replaceAll('[TAXA_INSCRICAO]', _taxaInscricao.toStringAsFixed(2));

    var categoriasLista = '';

    for (final cat in _categorias) {
      categoriasLista +=
      '   • ${cat.nome}: ${cat.idadeMin} a ${cat.idadeMax} anos • ${cat.sexo} • R\$ ${cat.taxa.toStringAsFixed(2)} • ${cat.vagas} vagas\n';
    }

    texto = texto.replaceAll('[CATEGORIAS_LISTA]', categoriasLista);
    texto = texto.replaceAll(
      '[INFORMACOES_ADICIONAIS]',
      _config['informacoes_adicionais'] ?? '',
    );

    return texto;
  }

  String get _regulamentoPadrao => '''
📜 REGULAMENTO OFICIAL
🏆 [NOME_CAMPEONATO]

📍 Local do evento: [LOCAL_EVENTO]
📅 Data: [DATA_EVENTO]
⏰ Horário: [HORARIO_EVENTO]

O campeonato tem como objetivo promover a integração entre grupos convidados, valorizando a capoeira com foco no show, na técnica e no volume de jogo, priorizando a segurança e a não violência.

💰 Valor da inscrição: R\$ [TAXA_INSCRICAO] por competidor.

📂 CATEGORIAS:
[CATEGORIAS_LISTA]

📌 Informações adicionais:
[INFORMACOES_ADICIONAIS]

Realização:
ASSOCIAÇÃO UAI CAPOEIRA
''';

  String _gerarTermoTexto() {
    final isMaior = _isMaiorIdade();
    final nomeAluno = _controllers['nome']!.text;
    final nomeResp =
    isMaior ? nomeAluno : _controllers['nome_responsavel']!.text;
    final cpf =
    isMaior ? _controllers['cpf']!.text : _controllers['cpf_responsavel']!.text;
    final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    var termoBase = isMaior
        ? (_config['termo_personalizado'] ?? _termoPadraoMaior)
        : (_config['termo_menor_personalizado'] ?? _termoPadraoMenor);

    return termoBase
        .replaceAll('[NOME_CAMPEONATO]', _nomeCampeonato)
        .replaceAll('[DATA_EVENTO]', _dataEvento)
        .replaceAll('[HORARIO_EVENTO]', _horarioEvento)
        .replaceAll('[LOCAL_EVENTO]', _localEvento)
        .replaceAll('[NOME_COMPLETO]', nomeResp)
        .replaceAll('[NOME_RESPONSAVEL]', nomeResp)
        .replaceAll('[NOME_MENOR]', nomeAluno)
        .replaceAll('[CPF]', cpf)
        .replaceAll('[CPF_RESPONSAVEL]', cpf)
        .replaceAll('[DATA_HORA]', dataHora);
  }

  String get _termoPadraoMaior => '''
TERMO DE RESPONSABILIDADE - [NOME_CAMPEONATO]

Eu, [NOME_COMPLETO], portador do CPF [CPF], declaro estar ciente e de acordo com todas as normas do campeonato, assumindo responsabilidade por minha participação.

Autorizo o uso gratuito de minha imagem para divulgação do evento e confirmo que as informações prestadas são verdadeiras.

Data e hora: [DATA_HORA]
''';

  String get _termoPadraoMenor => '''
TERMO DE RESPONSABILIDADE - [NOME_CAMPEONATO] (MENOR)

Eu, [NOME_RESPONSAVEL], portador do CPF [CPF_RESPONSAVEL], responsável legal por [NOME_MENOR], autorizo sua participação no campeonato e declaro estar ciente de todas as normas do evento.

Autorizo o uso gratuito da imagem do menor para divulgação do evento e confirmo que as informações prestadas são verdadeiras.

Data e hora: [DATA_HORA]
''';

  Future<void> _selecionarDataNascimento() async {
    final now = DateTime.now();
    final initial = DateTime(now.year - 12, now.month, now.day);

    final data = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 90),
      lastDate: now,
      helpText: 'Data de nascimento',
    );

    if (data == null) return;

    final text = DateFormat('dd/MM/yyyy').format(data);

    _controllers['data_nascimento']!.text = text;
    _atualizarIdade(text);
  }

  Future<void> _selecionarImagemCompetidor() async {
    try {
      final picker = ImagePicker();

      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1400,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();

      setState(() {
        _fotoBytes = bytes;
        _fotoNome = image.name;
        _fotoUrl = null;
      });

      _validarEtapa1();
    } catch (e) {
      _showSnack('Erro ao selecionar foto: $e', color: context.uai.error);
    }
  }

  Future<void> _selecionarComprovante() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      var bytes = file.bytes;

      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }

      if (bytes == null) {
        throw Exception('Não foi possível ler o arquivo selecionado.');
      }

      setState(() {
        _comprovanteBytes = bytes;
        _comprovanteNome = file.name;
        _comprovanteUrl = null;
      });

      _validarEtapaFinal();
    } catch (e) {
      _showSnack(
        'Erro ao selecionar comprovante: $e',
        color: context.uai.error,
      );
    }
  }

  Future<void> _abrirAssinatura() async {
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
          onConfirm: (imageBytes) {
            if (_isMounted) {
              setState(() {
                _assinaturaBytes = imageBytes;
                _assinaturaUrl = null;
              });

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _validarEtapaFinal();
                  setState(() {});
                }
              });

              _showSnack(
                '✅ Assinatura registrada com sucesso!',
                color: context.uai.success,
              );
            }
          },
        ),
      ),
    );
  }

  Future<String?> _uploadAssinaturaFirebase() async {
    if (_assinaturaUrl != null && _assinaturaUrl!.isNotEmpty) {
      return _assinaturaUrl;
    }

    if (_assinaturaBytes == null) return null;

    if (_isMounted) {
      setState(() => _uploadingAssinatura = true);
    }

    try {
      final isMaior = _isMaiorIdade();
      final nomeResponsavel = isMaior
          ? _controllers['nome']!.text.trim()
          : _controllers['nome_responsavel']!.text.trim();

      final nomeSeguro = nomeResponsavel
          .replaceAll(RegExp(r'\s+'), '_')
          .replaceAll(RegExp(r'[^A-Za-zÀ-ÖØ-öø-ÿ0-9_\-]'), '');

      final assinaturaUrl = await _service.uploadArquivo(
        _assinaturaBytes!,
        'assinaturas_campeonato',
        '${DateTime.now().millisecondsSinceEpoch}_${nomeSeguro.isEmpty ? 'responsavel' : nomeSeguro}.png',
      );

      if (_isMounted) {
        setState(() {
          _assinaturaUrl = assinaturaUrl;
          _uploadingAssinatura = false;
        });
      }

      return assinaturaUrl;
    } catch (e) {
      if (_isMounted) {
        setState(() => _uploadingAssinatura = false);
      }

      debugPrint('❌ Erro ao enviar assinatura: $e');
      rethrow;
    }
  }

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

      var fotoUrl = _fotoUrl;

      if (_fotoBytes != null && _fotoNome != null) {
        fotoUrl = await _service.uploadArquivo(
          _fotoBytes!,
          'fotos_competidores',
          '${DateTime.now().millisecondsSinceEpoch}_${_fotoNome!}',
        );
      }

      var comprovanteUrl = _comprovanteUrl;

      if (!_alunoEncontrado &&
          _comprovanteBytes != null &&
          _comprovanteNome != null) {
        comprovanteUrl = await _service.uploadArquivo(
          _comprovanteBytes!,
          'comprovantes_pagamento',
          '${DateTime.now().millisecondsSinceEpoch}_${_comprovanteNome!}',
        );
      }

      var assinaturaUrl = _assinaturaUrl;

      if (_recolherAssinatura) {
        assinaturaUrl = await _uploadAssinaturaFirebase();

        if (assinaturaUrl == null || assinaturaUrl.isEmpty) {
          throw Exception('Assinatura é obrigatória');
        }
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
        assinaturaUrl: assinaturaUrl,
        nomeCampeonato: _nomeCampeonato,
        dataEvento: _dataEvento,
        taxaPaga: _alunoEncontrado,
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
      debugPrint('❌ Erro ao salvar: $e');

      if (_isMounted) {
        _showSnack('Erro ao enviar inscrição: $e', color: context.uai.error);
        setState(() {
          _enviando = false;
          _processandoEnvio = false;
        });
      }
    }
  }

  Future<void> _mostrarDialogSucesso() async {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    final nomeResponsavel = _getPrimeiroNome(
      _controllers['nome_responsavel']!.text.isNotEmpty
          ? _controllers['nome_responsavel']!.text
          : _controllers['nome']!.text,
    );
    final nomeAluno = _getPrimeiroNome(_controllers['nome']!.text);

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 2),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(gradient: t.primaryGradient),
                    child: Column(
                      children: [
                        Icon(
                          Icons.emoji_events_rounded,
                          color: onPrimary,
                          size: 62,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Inscrição enviada!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: onPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Parabéns, ${nomeAluno.isEmpty ? nomeResponsavel : nomeAluno}!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: onPrimary.withOpacity(0.82),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          _infoResumo(
                            icon: Icons.event_rounded,
                            label: 'Campeonato',
                            value: _nomeCampeonato,
                          ),
                          _infoResumo(
                            icon: Icons.person_rounded,
                            label: 'Competidor',
                            value: _controllers['nome']!.text,
                          ),
                          _infoResumo(
                            icon: Icons.category_rounded,
                            label: 'Categoria',
                            value:
                            _categoriaInfo?.nome ?? 'Categoria não informada',
                          ),
                          _infoResumo(
                            icon: Icons.payments_rounded,
                            label: 'Taxa',
                            value: _alunoEncontrado
                                ? 'Taxa já identificada como paga'
                                : 'R\$ ${_taxaInscricao.toStringAsFixed(2)}',
                          ),
                          if (_inscricaoId != null)
                            _infoResumo(
                              icon: Icons.confirmation_number_rounded,
                              label: 'Protocolo',
                              value: '${_inscricaoId!.substring(0, 8)}...',
                            ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: t.card,
                      border: Border(top: BorderSide(color: t.border)),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.primary,
                          foregroundColor: _readableOn(t.primary),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                            BorderRadius.circular(t.buttonRadius),
                          ),
                        ),
                        child: const Text(
                          'FINALIZAR',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _infoResumo({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: primary, size: 20),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _proximaEtapa() {
    if (_currentStep < 3 && _etapaValida[_currentStep] == true) {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _etapaAnterior() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<bool> _onWillPop() async {
    if (_enviando || _processandoEnvio) return false;

    if (_currentStep > 0) {
      _etapaAnterior();
      return false;
    }

    return true;
  }

  void _mostrarRegulamento() {
    showDialog<void>(
      context: context,
      builder: (context) => RegulamentoCampeonatoDialog(
        regulamento: _gerarRegulamentoCompleto(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    // Esta tela roda dentro da LandingPage, que já possui AppBar.
    // Por isso não existe Scaffold/AppBar aqui, evitando duas barras.
    if (_carregando) {
      return ColoredBox(
        color: t.background,
        child: Center(child: CircularProgressIndicator(color: t.primary)),
      );
    }

    if (!_inscricoesAbertas) {
      return _buildInscricoesFechadas();
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: ColoredBox(
        color: t.background,
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return _enviando
                  ? _buildEnviando()
                  : Column(
                children: [
                  _buildTopProgress(),
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
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTopProgress() {
    final t = context.uai;
    final progress = (_currentStep + 1) / 4;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: BorderSide(color: t.border)),
        boxShadow: t.softShadow,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.emoji_events_rounded, color: t.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _nomeCampeonato,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '${_currentStep + 1}/4',
                    style: TextStyle(
                      color: t.textSecondary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: t.border,
                  valueColor: AlwaysStoppedAnimation<Color>(t.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInscricoesFechadas() {
    final t = context.uai;

    return ColoredBox(
      color: t.background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.all(24),
            decoration: _cardDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 78, color: t.textMuted),
                const SizedBox(height: 16),
                Text(
                  'Inscrições Fechadas',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _mensagem.isNotEmpty
                      ? _mensagem
                      : 'No momento não estamos aceitando inscrições.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textSecondary,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_mensagemPeriodo.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _infoBox(
                    icon: Icons.schedule_rounded,
                    color: t.warning,
                    text: _mensagemPeriodo,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepWelcome(BoxConstraints constraints) {
    final t = context.uai;
    final isMobile = constraints.maxWidth < 600;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeroWelcome(isMobile),
              const SizedBox(height: 14),
              _buildInfoCardsEvento(),
              const SizedBox(height: 14),
              _buildDisponibilidadeCard(),
              const SizedBox(height: 14),
              _sectionCard(
                icon: Icons.rule_rounded,
                title: 'Regulamento',
                subtitle: 'Leia as regras antes de continuar.',
                color: t.info,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _infoBox(
                      icon: Icons.info_rounded,
                      color: t.info,
                      text:
                      'A inscrição confirma que você está ciente das regras, categorias e critérios do campeonato.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _mostrarRegulamento,
                      icon: const Icon(Icons.menu_book_rounded),
                      label: const Text('LER REGULAMENTO'),
                      style: _outlineStyle(t.info),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroWelcome(bool isMobile) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.softShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final icon = Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              Icons.emoji_events_rounded,
              color: onPrimary,
              size: 38,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                _nomeCampeonato,
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 24 : 31,
                  fontWeight: FontWeight.w900,
                  height: 1.04,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Preencha sua inscrição com atenção e confirme os dados antes de enviar.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.82),
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _whiteChip(Icons.event_rounded, _dataEvento),
                  _whiteChip(
                    Icons.payments_rounded,
                    'R\$ ${_taxaInscricao.toStringAsFixed(2)}',
                  ),
                  _whiteChip(
                    Icons.groups_rounded,
                    '$_vagasRestantes vagas',
                  ),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [
                icon,
                const SizedBox(height: 14),
                text,
              ],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _whiteChip(IconData icon, String label) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

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
          Text(
            label,
            style: TextStyle(
              color: onPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCardsEvento() {
    final t = context.uai;

    final items = [
      _InfoEvento(Icons.calendar_month_rounded, 'Data', _dataEvento, t.info),
      _InfoEvento(
        Icons.access_time_rounded,
        'Horário',
        _horarioEvento,
        t.warning,
      ),
      _InfoEvento(
        Icons.location_on_rounded,
        'Local',
        _localEvento,
        t.associacao,
      ),
      _InfoEvento(
        Icons.payments_rounded,
        'Taxa',
        'R\$ ${_taxaInscricao.toStringAsFixed(2)}',
        t.success,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 560 ? 1 : 2;
        const spacing = 10.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items.map((item) {
            return SizedBox(width: width, child: _infoEventoCard(item));
          }).toList(),
        );
      },
    );
  }

  Widget _infoEventoCard(_InfoEvento item) {
    final t = context.uai;
    final accent = _ensureVisible(item.color, t.card);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: _cardDecoration(borderColor: accent.withOpacity(0.13)),
      child: Row(
        children: [
          Icon(item.icon, color: accent),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            child: Text(
              item.label,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              item.value,
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisponibilidadeCard() {
    final t = context.uai;

    final liberado = _inscricoesAbertas &&
        _recebendoInscricoes &&
        _periodoValido &&
        _temVagas;
    final color = liberado ? t.success : t.warning;

    return _sectionCard(
      icon: liberado ? Icons.check_circle_rounded : Icons.warning_rounded,
      title: liberado ? 'Inscrições disponíveis' : 'Atenção',
      subtitle: liberado
          ? 'Você pode iniciar sua inscrição.'
          : 'Confira a situação antes de continuar.',
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _infoBox(
            icon: liberado ? Icons.verified_rounded : Icons.info_rounded,
            color: color,
            text: liberado
                ? 'Inscrições abertas. Restam $_vagasRestantes vagas disponíveis.'
                : (_mensagemPeriodo.isNotEmpty
                ? _mensagemPeriodo
                : 'Inscrições indisponíveis no momento.'),
          ),
          if (_chavePix.isNotEmpty ||
              _informacoesBancarias.isNotEmpty ||
              _instrucoesPagamento.isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoBox(
              icon: Icons.pix_rounded,
              color: t.info,
              text: [
                if (_chavePix.isNotEmpty) 'PIX: $_chavePix',
                if (_informacoesBancarias.isNotEmpty) _informacoesBancarias,
                if (_instrucoesPagamento.isNotEmpty) _instrucoesPagamento,
              ].join('\n'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepDadosCompletos(BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < 600;
    final t = context.uai;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionCard(
                icon: Icons.person_rounded,
                title: 'Dados pessoais',
                subtitle: 'Dados do competidor.',
                color: t.primary,
                child: Column(
                  children: [
                    _textField(
                      keyName: 'nome',
                      label: 'Nome completo',
                      icon: Icons.person_rounded,
                      focusNode: _nomeFocusNode,
                      onEditingComplete: _buscarAluno,
                    ),
                    if (_buscandoAluno) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(color: t.primary),
                    ],
                    if (_alunoEncontrado) ...[
                      const SizedBox(height: 8),
                      _infoBox(
                        icon: Icons.verified_rounded,
                        color: t.success,
                        text:
                        'Aluno encontrado no sistema. Alguns dados foram preenchidos automaticamente.',
                      ),
                    ],
                    const SizedBox(height: 12),
                    _textField(
                      keyName: 'apelido',
                      label: 'Apelido',
                      icon: Icons.badge_rounded,
                    ),
                    const SizedBox(height: 12),
                    _dateField(),
                    const SizedBox(height: 12),
                    _segmentedSexo(),
                    const SizedBox(height: 12),
                    _textField(
                      keyName: 'cpf',
                      label: 'CPF',
                      icon: Icons.credit_card_rounded,
                      keyboardType: TextInputType.number,
                      formatter: _cpfFormatter,
                    ),
                    const SizedBox(height: 12),
                    _textField(
                      keyName: 'contato_aluno',
                      label: 'Contato do aluno',
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                      formatter: _phoneFormatter,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _sectionCard(
                icon: Icons.home_rounded,
                title: 'Endereço',
                subtitle: 'Informe o endereço do competidor.',
                color: t.info,
                child: Column(
                  children: [
                    _textField(
                      keyName: 'rua',
                      label: 'Rua',
                      icon: Icons.route_rounded,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _textField(
                            keyName: 'numero',
                            label: 'Número',
                            icon: Icons.numbers_rounded,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: _textField(
                            keyName: 'bairro',
                            label: 'Bairro',
                            icon: Icons.location_city_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _textField(
                      keyName: 'cidade',
                      label: 'Cidade',
                      icon: Icons.location_on_rounded,
                    ),
                  ],
                ),
              ),
              if (!_isMaiorIdade()) ...[
                const SizedBox(height: 14),
                _sectionCard(
                  icon: Icons.family_restroom_rounded,
                  title: 'Responsável',
                  subtitle: 'Obrigatório para menores de idade.',
                  color: t.warning,
                  child: Column(
                    children: [
                      _textField(
                        keyName: 'nome_responsavel',
                        label: 'Nome do responsável',
                        icon: Icons.person_pin_rounded,
                      ),
                      const SizedBox(height: 12),
                      _textField(
                        keyName: 'contato_responsavel',
                        label: 'Contato do responsável',
                        icon: Icons.phone_in_talk_rounded,
                        keyboardType: TextInputType.phone,
                        formatter: _phoneFormatter,
                      ),
                      const SizedBox(height: 12),
                      _textField(
                        keyName: 'cpf_responsavel',
                        label: 'CPF do responsável',
                        icon: Icons.credit_card_rounded,
                        keyboardType: TextInputType.number,
                        formatter: _cpfFormatter,
                      ),
                    ],
                  ),
                ),
              ],
              if (_exigirFotoCompetidor) ...[
                const SizedBox(height: 14),
                _sectionCard(
                  icon: Icons.photo_camera_rounded,
                  title: 'Foto do competidor',
                  subtitle: 'Envie uma foto para identificação.',
                  color: t.associacao,
                  child: _buildFotoUpload(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required String keyName,
    required String label,
    required IconData icon,
    FocusNode? focusNode,
    VoidCallback? onEditingComplete,
    TextInputType? keyboardType,
    TextInputFormatter? formatter,
    int maxLines = 1,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return TextFormField(
      controller: _controllers[keyName],
      focusNode: focusNode,
      keyboardType: keyboardType,
      inputFormatters: formatter == null ? null : [formatter],
      maxLines: maxLines,
      onEditingComplete: onEditingComplete,
      style: TextStyle(color: t.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: t.textSecondary),
        prefixIcon: Icon(icon, color: primary),
        filled: true,
        fillColor: t.cardAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
      ),
    );
  }

  Widget _dateField() {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return Material(
      color: t.cardAlt,
      borderRadius: BorderRadius.circular(t.inputRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _selecionarDataNascimento,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Data de nascimento',
            labelStyle: TextStyle(color: t.textSecondary),
            prefixIcon: Icon(Icons.cake_rounded, color: primary),
            filled: true,
            fillColor: t.cardAlt,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(t.inputRadius),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(t.inputRadius),
              borderSide: BorderSide(color: t.border),
            ),
          ),
          child: Text(
            _controllers['data_nascimento']!.text.isEmpty
                ? 'Selecionar data'
                : '${_controllers['data_nascimento']!.text} • $_idade anos',
            style: TextStyle(
              color: _controllers['data_nascimento']!.text.isEmpty
                  ? t.textMuted
                  : t.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _segmentedSexo() {
    final t = context.uai;
    final options = const ['MASCULINO', 'FEMININO'];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((item) {
        final selected = _sexo == item;
        final color = selected ? t.primary : t.textSecondary;
        final visible = _ensureVisible(color, t.cardAlt);

        return ChoiceChip(
          selected: selected,
          label: Text(item),
          selectedColor: visible,
          backgroundColor: t.cardAlt,
          labelStyle: TextStyle(
            color: selected ? _readableOn(visible) : t.textPrimary,
            fontWeight: FontWeight.w900,
          ),
          side: BorderSide(color: selected ? visible : t.border),
          onSelected: (_) {
            setState(() => _sexo = item);
            _validarEtapa1();
            _validarEtapaFinal();
          },
        );
      }).toList(),
    );
  }

  Widget _buildStepGrupoEGraduacao(BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < 600;
    final t = context.uai;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionCard(
                icon: Icons.groups_rounded,
                title: 'Grupo e graduação',
                subtitle: 'Grupo, professor e graduação do competidor.',
                color: t.warning,
                child: Column(
                  children: [
                    _infoBox(
                      icon: Icons.info_outline_rounded,
                      color: t.info,
                      text:
                      'Caso seu grupo não esteja na lista, entre em contato com a organização.',
                    ),
                    const SizedBox(height: 14),
                    _buildGrupoDropdown(),
                    const SizedBox(height: 14),
                    _textField(
                      keyName: 'professor_nome',
                      label: 'Nome do professor',
                      icon: Icons.school_rounded,
                    ),
                    const SizedBox(height: 12),
                    _textField(
                      keyName: 'professor_contato',
                      label: 'Contato do professor',
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                      formatter: _phoneFormatter,
                    ),
                  ],
                ),
              ),
              if (_grupoSelecionado != null) ...[
                const SizedBox(height: 14),
                _isGrupoSelecionadoUai
                    ? _buildGraduacoesUaiCard()
                    : _sectionCard(
                  icon: Icons.workspace_premium_rounded,
                  title: 'Graduação do competidor',
                  subtitle: 'Informe a graduação usada no seu grupo.',
                  color: t.success,
                  child: _textField(
                    keyName: 'outra_graduacao',
                    label: 'Outra graduação',
                    icon: Icons.edit_rounded,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrupoDropdown() {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    if (_carregandoGrupos) {
      return Center(child: CircularProgressIndicator(color: t.primary));
    }

    if (_gruposConvidados.isEmpty) {
      return Column(
        children: [
          _infoBox(
            icon: Icons.warning_amber_rounded,
            color: t.warning,
            text: _erroGrupos ?? 'Nenhum grupo encontrado.',
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _carregarGruposConvidados,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
            style: _outlineStyle(t.warning),
          ),
        ],
      );
    }

    return DropdownButtonFormField<String>(
      value: _grupoSelecionado,
      isExpanded: true,
      hint: Text(
        'Selecione o grupo',
        style: TextStyle(color: t.textMuted),
      ),
      dropdownColor: t.surface,
      style: TextStyle(color: t.textPrimary),
      decoration: InputDecoration(
        labelText: 'Grupo',
        labelStyle: TextStyle(color: t.textSecondary),
        prefixIcon: Icon(Icons.groups_rounded, color: primary),
        filled: true,
        fillColor: t.cardAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
      ),
      items: _gruposConvidados.map<DropdownMenuItem<String>>((grupo) {
        return DropdownMenuItem<String>(
          value: grupo.nome,
          child: Text(
            grupo.nome,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: _alunoEncontrado
          ? null
          : (value) {
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
    );
  }

  Widget _buildGraduacoesUaiCard() {
    final t = context.uai;

    return _sectionCard(
      icon: Icons.workspace_premium_rounded,
      title: 'Graduação do competidor',
      subtitle: 'Selecione a graduação atual.',
      color: t.success,
      child: _graduacoesUai.isEmpty
          ? Center(child: CircularProgressIndicator(color: t.primary))
          : LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 420
              ? 2
              : constraints.maxWidth < 760
              ? 3
              : 4;
          const spacing = 10.0;
          final width =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: _graduacoesUai.map((g) {
              final id = g['id']?.toString();
              final selected = _graduacaoSelecionada == id;
              final cor = _hexToColor(g['hex_cor2'], fallback: t.primary);
              final accent = _ensureVisible(cor, t.cardAlt);

              return SizedBox(
                width: width,
                child: Material(
                  color: selected
                      ? Color.alphaBlend(
                    accent.withOpacity(0.14),
                    t.cardAlt,
                  )
                      : t.cardAlt,
                  borderRadius: BorderRadius.circular(t.inputRadius),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _alunoEncontrado
                        ? null
                        : () {
                      setState(() {
                        _graduacaoSelecionada = id;
                        _graduacaoInfo = g;
                      });
                      _validarEtapa2();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius:
                        BorderRadius.circular(t.inputRadius),
                        border: Border.all(
                          color: selected
                              ? accent.withOpacity(0.42)
                              : t.border,
                          width: selected ? 1.4 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          if (_svgContent != null)
                            SizedBox(
                              height: 50,
                              child: SvgPicture.string(
                                _getModifiedSvg(g),
                                fit: BoxFit.contain,
                              ),
                            )
                          else
                            Icon(
                              Icons.workspace_premium_rounded,
                              color: accent,
                            ),
                          const SizedBox(height: 7),
                          Text(
                            g['nome_graduacao']?.toString() ??
                                'Graduação',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: selected ? accent : t.textPrimary,
                              fontSize: 11,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  String _getModifiedSvg(Map<String, dynamic> data) {
    if (_svgContent == null) return '';

    try {
      final document = xml.XmlDocument.parse(_svgContent!);

      Color colorFromHex(String? hexColor) {
        if (hexColor == null || hexColor.length < 7) return Colors.grey;

        try {
          return Color(
            int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16),
          );
        } catch (_) {
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
            final hex =
                '#${color.value.toRadixString(16).substring(2).toUpperCase()}';

            final newStyle = style.contains('fill:')
                ? style.replaceAll(
              RegExp(r'fill:#[0-9a-fA-F]{6}'),
              'fill:$hex',
            )
                : 'fill:$hex;$style';

            element.setAttribute('style', newStyle);
          }
        } catch (e) {
          debugPrint('Erro ao mudar cor da parte $id: $e');
        }
      }

      changeColor('cor1', colorFromHex(data['hex_cor1']));
      changeColor('cor2', colorFromHex(data['hex_cor2']));
      changeColor('corponta1', colorFromHex(data['hex_ponta1']));
      changeColor('corponta2', colorFromHex(data['hex_ponta2']));

      return document.toXmlString();
    } catch (e) {
      debugPrint('❌ Erro ao modificar SVG: $e');
      return _svgContent!;
    }
  }

  Color _hexToColor(dynamic raw, {required Color fallback}) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return fallback;

    try {
      final clean = text.replaceAll('#', '');
      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      }
      if (clean.length == 8) {
        return Color(int.parse(clean, radix: 16));
      }
    } catch (_) {
      return fallback;
    }

    return fallback;
  }

  Widget _buildStepRevisao(BoxConstraints constraints) {
    final isMobile = constraints.maxWidth < 600;
    final t = context.uai;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionCard(
                icon: Icons.category_rounded,
                title: 'Categoria',
                subtitle: 'Escolha uma categoria compatível.',
                color: t.associacao,
                child: _buildCategorias(),
              ),
              const SizedBox(height: 14),
              _sectionCard(
                icon: Icons.payments_rounded,
                title: 'Pagamento',
                subtitle: _alunoEncontrado
                    ? 'Aluno encontrado: taxa marcada como paga.'
                    : 'Confira as instruções de pagamento.',
                color: t.success,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _infoBox(
                      icon: Icons.pix_rounded,
                      color: t.success,
                      text: _alunoEncontrado
                          ? 'Taxa já identificada como paga pelo sistema.'
                          : [
                        if (_chavePix.isNotEmpty) 'PIX: $_chavePix',
                        if (_informacoesBancarias.isNotEmpty)
                          _informacoesBancarias,
                        if (_instrucoesPagamento.isNotEmpty)
                          _instrucoesPagamento,
                        'Valor: R\$ ${_taxaInscricao.toStringAsFixed(2)}',
                      ].join('\n'),
                    ),
                    if (_exigirComprovantePagamento && !_alunoEncontrado) ...[
                      const SizedBox(height: 12),
                      _uploadButton(
                        icon: Icons.upload_file_rounded,
                        label: _comprovanteBytes == null &&
                            _comprovanteUrl == null
                            ? 'Enviar comprovante'
                            : 'Comprovante selecionado',
                        color: t.success,
                        onTap: _selecionarComprovante,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _sectionCard(
                icon: Icons.fact_check_rounded,
                title: 'Termo e autorização',
                subtitle: 'Confirme os dados e autorize a participação.',
                color: t.warning,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _infoBox(
                      icon: Icons.description_rounded,
                      color: t.warning,
                      text: _gerarTermoTexto(),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: _autorizacao,
                      activeColor: t.primary,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Li e aceito o regulamento e o termo de responsabilidade.',
                        style: TextStyle(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() => _autorizacao = value ?? false);
                        _validarEtapaFinal();
                      },
                    ),
                    if (_recolherAssinatura) ...[
                      const SizedBox(height: 8),
                      _uploadButton(
                        icon: Icons.draw_rounded,
                        label: _assinaturaBytes == null &&
                            _assinaturaUrl == null
                            ? 'Assinar termo'
                            : 'Assinatura registrada',
                        color: t.primary,
                        onTap: _abrirAssinatura,
                        loading: _uploadingAssinatura,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _sectionCard(
                icon: Icons.checklist_rounded,
                title: 'Resumo',
                subtitle: 'Confira antes de enviar.',
                color: t.info,
                child: Column(
                  children: [
                    _reviewRow('Nome', _controllers['nome']!.text),
                    _reviewRow('Apelido', _controllers['apelido']!.text),
                    _reviewRow('Idade', '$_idade anos'),
                    _reviewRow('Sexo', _sexo ?? 'Não informado'),
                    _reviewRow('Grupo', _controllers['grupo']!.text),
                    _reviewRow(
                      'Graduação',
                      _isGrupoSelecionadoUai
                          ? (_graduacaoInfo?['nome_graduacao']?.toString() ??
                          '')
                          : _controllers['outra_graduacao']!.text,
                    ),
                    _reviewRow(
                      'Categoria',
                      _categoriaInfo?.nome ?? 'Não selecionada',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategorias() {
    final t = context.uai;

    if (_categorias.isEmpty) {
      return _infoBox(
        icon: Icons.warning_rounded,
        color: t.warning,
        text: 'Nenhuma categoria cadastrada.',
      );
    }

    return Column(
      children: _categorias.map((cat) {
        final selected = _categoriaSelecionada == cat.id;
        final compativel = cat.isCompativel(_idade, _sexo);
        final color = compativel ? t.success : t.textMuted;
        final accent = _ensureVisible(selected ? t.primary : color, t.cardAlt);

        return Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Material(
            color: selected
                ? Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt)
                : t.cardAlt,
            borderRadius: BorderRadius.circular(t.inputRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: compativel
                  ? () {
                setState(() {
                  _categoriaSelecionada = cat.id;
                  _categoriaInfo = cat;
                });
                _validarEtapaFinal();
              }
                  : null,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.inputRadius),
                  border: Border.all(
                    color: selected
                        ? accent.withOpacity(0.38)
                        : t.border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cat.nome,
                            style: TextStyle(
                              color: compativel
                                  ? t.textPrimary
                                  : t.textMuted,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${cat.idadeMin} a ${cat.idadeMax} anos • ${cat.sexo} • R\$ ${cat.taxa.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: compativel
                                  ? t.textSecondary
                                  : t.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!compativel)
                      Icon(Icons.lock_outline_rounded, color: t.textMuted),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _reviewRow(String label, String value) {
    final t = context.uai;

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? 'Não informado' : value,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFotoUpload() {
    final t = context.uai;
    final hasFoto = _fotoBytes != null || (_fotoUrl?.isNotEmpty ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasFoto) ...[
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: t.cardAlt,
              borderRadius: BorderRadius.circular(t.inputRadius),
              border: Border.all(color: t.border),
            ),
            child: _fotoBytes != null
                ? ClipRRect(
              borderRadius: BorderRadius.circular(t.inputRadius),
              child: Image.memory(_fotoBytes!, fit: BoxFit.cover),
            )
                : Center(
              child: Icon(
                Icons.check_circle_rounded,
                color: t.success,
                size: 44,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        _uploadButton(
          icon: Icons.photo_camera_rounded,
          label: hasFoto ? 'Trocar foto' : 'Selecionar foto',
          color: t.associacao,
          onTap: _selecionarImagemCompetidor,
        ),
      ],
    );
  }

  Widget _uploadButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool loading = false,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Material(
      color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
      borderRadius: BorderRadius.circular(t.inputRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: loading ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.inputRadius),
            border: Border.all(color: accent.withOpacity(0.14)),
          ),
          child: Row(
            children: [
              loading
                  ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: accent,
                  strokeWidth: 2,
                ),
              )
                  : Icon(icon, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEnviando() {
    final t = context.uai;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.all(20),
        decoration: _cardDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: t.primary),
            const SizedBox(height: 16),
            Text(
              'Enviando inscrição...',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Aguarde sem fechar a tela.',
              style: TextStyle(color: t.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationButtons() {
    final t = context.uai;
    final podeAvancar = _etapaValida[_currentStep] == true;
    final isLast = _currentStep == 3;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border(top: BorderSide(color: t.border)),
          boxShadow: t.softShadow,
        ),
        child: Row(
          children: [
            if (_currentStep > 0)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _etapaAnterior,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('VOLTAR'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: t.textPrimary,
                    side: BorderSide(color: t.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(t.buttonRadius),
                    ),
                  ),
                ),
              ),
            if (_currentStep > 0) const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: podeAvancar
                    ? (isLast ? _enviarInscricao : _proximaEtapa)
                    : null,
                icon: Icon(
                  isLast
                      ? Icons.send_rounded
                      : Icons.arrow_forward_rounded,
                ),
                label: Text(isLast ? 'ENVIAR INSCRIÇÃO' : 'CONTINUAR'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.primary,
                  foregroundColor: _readableOn(t.primary),
                  disabledBackgroundColor: t.cardAlt,
                  disabledForegroundColor: t.textMuted,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Widget child,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: _cardDecoration(borderColor: accent.withOpacity(0.13)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: icon,
            title: title,
            subtitle: subtitle,
            color: accent,
          ),
          const SizedBox(height: 14),
          child,
        ],
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

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(t.buttonRadius),
            border: Border.all(color: color.withOpacity(0.15)),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoBox({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: accent,
                height: 1.28,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _outlineStyle(Color color) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return OutlinedButton.styleFrom(
      foregroundColor: accent,
      side: BorderSide(color: accent.withOpacity(0.24)),
      padding: const EdgeInsets.symmetric(vertical: 13),
      textStyle: const TextStyle(fontWeight: FontWeight.w900),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.buttonRadius),
      ),
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
}

class _InfoEvento {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoEvento(this.icon, this.label, this.value, this.color);
}
