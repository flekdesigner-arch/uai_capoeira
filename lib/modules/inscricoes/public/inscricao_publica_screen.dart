
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/inscricoes/public/signature_screen.dart';
import 'package:uai_capoeira/modules/rastreio/services/rastreio_site.dart';
import 'package:uai_capoeira/modules/site/screens/landing_page.dart';
import 'package:uai_capoeira/modules/site/widgets/regimento_dialog.dart';

class InscricaoPublicaScreen extends StatefulWidget {
  const InscricaoPublicaScreen({super.key});

  @override
  State<InscricaoPublicaScreen> createState() => _InscricaoPublicaScreenState();
}

class _InscricaoPublicaScreenState extends State<InscricaoPublicaScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _rastreioService = RastreioSiteService();
  final _pageController = PageController();
  final Map<String, Timer> _debounceRastreioCampos = {};

  final Map<String, TextEditingController> _controllers = {
    'nome': TextEditingController(),
    'apelido': TextEditingController(),
    'cpf': TextEditingController(),
    'data_nascimento': TextEditingController(),
    'rua': TextEditingController(),
    'numero': TextEditingController(),
    'bairro': TextEditingController(),
    'cidade': TextEditingController(),
    'contato_aluno': TextEditingController(),
    'nome_responsavel': TextEditingController(),
    'contato_responsavel': TextEditingController(),
  };

  int _currentStep = 0;
  DateTime _inicioTelaInscricao = DateTime.now();
  DateTime _inicioEtapaAtual = DateTime.now();

  bool _rastreioInscricaoIniciado = false;
  bool _inscricaoFinalizadaComSucesso = false;

  String? _sexo;
  bool _inscricoesAbertas = true;
  bool _carregando = true;
  bool _enviando = false;
  String _mensagem = '';
  bool _autorizacao = false;

  int _idadeMinima = 5;
  int _idadeMaxima = 16;
  int _vagasDisponiveis = 0;
  int _vagasRestantes = 0;
  bool _configuracoesCarregadas = false;
  bool _temVagas = true;
  bool _recolherAssinatura = true;

  String? _assinaturaUrl;
  Uint8List? _assinaturaBytes;
  bool _uploadingAssinatura = false;

  Uint8List? _fotoBytes;
  String? _fotoNome;
  String? _fotoUrl;
  bool _uploadingFoto = false;
  bool _processandoFotoLocal = false;
  String _statusFotoLocal = '';

  final Map<int, bool> _etapaValida = {
    0: false,
    1: false,
    2: false,
    3: false,
    4: false,
    5: true,
    6: false,
  };

  final Map<int, List<String>> _errosPorEtapa = {
    0: [],
    1: [],
    2: [],
    3: [],
    4: [],
    5: [],
    6: [],
  };

  static const List<String> _nomesEtapasRastreio = [
    'boas_vindas',
    'foto_aluno',
    'dados_aluno',
    'contato',
    'endereco',
    'documento',
    'revisao',
  ];

  @override
  void initState() {
    super.initState();
    _controllers['cidade']!.text = 'BOCAIÚVA-MG';
    _configurarRastreioCamposDigitados();
    _iniciarRastreioInscricao();

    _controllers['nome']!.addListener(_validarEtapa1);
    _controllers['apelido']!.addListener(_validarEtapa1);
    _controllers['data_nascimento']!.addListener(_validarEtapa1);
    _controllers['contato_aluno']!.addListener(_validarEtapa2);
    _controllers['nome_responsavel']!.addListener(_validarEtapa2);
    _controllers['contato_responsavel']!.addListener(_validarEtapa2);
    _controllers['rua']!.addListener(_validarEtapa3);
    _controllers['numero']!.addListener(_validarEtapa3);
    _controllers['bairro']!.addListener(_validarEtapa3);
    _controllers['cidade']!.addListener(_validarEtapa3);

    _verificarInscricoes();
  }

  @override
  void dispose() {
    _controllers['nome']!.removeListener(_validarEtapa1);
    _controllers['apelido']!.removeListener(_validarEtapa1);
    _controllers['data_nascimento']!.removeListener(_validarEtapa1);
    _controllers['contato_aluno']!.removeListener(_validarEtapa2);
    _controllers['nome_responsavel']!.removeListener(_validarEtapa2);
    _controllers['contato_responsavel']!.removeListener(_validarEtapa2);
    _controllers['rua']!.removeListener(_validarEtapa3);
    _controllers['numero']!.removeListener(_validarEtapa3);
    _controllers['bairro']!.removeListener(_validarEtapa3);
    _controllers['cidade']!.removeListener(_validarEtapa3);

    _registrarSaidaInscricaoSeNecessario(motivo: 'dispose');

    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final timer in _debounceRastreioCampos.values) {
      timer.cancel();
    }
    _debounceRastreioCampos.clear();
    _pageController.dispose();
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

  bool _isMaiorIdade() {
    final dataNasc = _controllers['data_nascimento']!.text;
    if (dataNasc.isEmpty) return false;
    return _calcularIdade(dataNasc) >= 18;
  }

  bool _temFoto() => _fotoBytes != null || (_fotoUrl?.isNotEmpty == true);

  bool _telefoneCompleto(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '').length >= 10;
  }

  bool _validarNomePessoa(String valor) {
    if (valor.trim().isEmpty) return false;
    return RegExp(r'^[A-Za-zÀ-ÖØ-öø-ÿ\s]+$').hasMatch(valor.trim());
  }

  bool _validarEnderecoTexto(String valor) {
    if (valor.trim().isEmpty) return false;
    return RegExp(r'^[A-Za-zÀ-ÖØ-öø-ÿ0-9\s\.,\-ºª/]+$').hasMatch(valor.trim());
  }

  int _calcularIdade(String dataNascimento) {
    try {
      final data = DateFormat('dd/MM/yyyy').parseStrict(dataNascimento);
      final hoje = DateTime.now();
      int idade = hoje.year - data.year;
      if (hoje.month < data.month ||
          (hoje.month == data.month && hoje.day < data.day)) {
        idade--;
      }
      return idade;
    } catch (_) {
      return 0;
    }
  }

  String _getPrimeiroNome(String? nomeCompleto) {
    if (nomeCompleto == null || nomeCompleto.trim().isEmpty) return '...';
    return nomeCompleto.trim().split(' ').first;
  }

  String _toUpperCase(String? text) => text?.toUpperCase().trim() ?? '';

  String _nomeEtapaRastreio(int etapa) {
    if (etapa < 0 || etapa >= _nomesEtapasRastreio.length) return 'etapa_$etapa';
    return _nomesEtapasRastreio[etapa];
  }

  String _etapaAtualRastreio() => _nomeEtapaRastreio(_currentStep);

  int get _tempoTotalInscricaoSegundos {
    return DateTime.now().difference(_inicioTelaInscricao).inSeconds;
  }

  int get _tempoEtapaAtualSegundos {
    return DateTime.now().difference(_inicioEtapaAtual).inSeconds;
  }

  Map<String, dynamic> _metadataResumoInscricao() {
    return {
      'etapa_atual': _currentStep,
      'nome_etapa_atual': _nomeEtapaRastreio(_currentStep),
      'tempo_total_segundos': _tempoTotalInscricaoSegundos,
      'tempo_etapa_segundos': _tempoEtapaAtualSegundos,
      'tem_foto': _temFoto(),
      'tem_assinatura': _assinaturaBytes != null || (_assinaturaUrl?.isNotEmpty == true),
      'recolher_assinatura': _recolherAssinatura,
      'autorizacao': _autorizacao,
      'inscricoes_abertas': _inscricoesAbertas,
      'tem_vagas': _temVagas,
      'vagas_restantes': _vagasRestantes,
      'idade_minima': _idadeMinima,
      'idade_maxima': _idadeMaxima,
    };
  }

  Map<String, dynamic> _snapshotCamposInscricao() {
    return {
      'nome': _controllers['nome']!.text.trim(),
      'apelido': _controllers['apelido']!.text.trim(),
      'cpf': _controllers['cpf']!.text.trim(),
      'data_nascimento': _controllers['data_nascimento']!.text.trim(),
      'sexo': _sexo ?? '',
      'rua': _controllers['rua']!.text.trim(),
      'numero': _controllers['numero']!.text.trim(),
      'bairro': _controllers['bairro']!.text.trim(),
      'cidade': _controllers['cidade']!.text.trim(),
      'contato_aluno': _controllers['contato_aluno']!.text.trim(),
      'nome_responsavel': _controllers['nome_responsavel']!.text.trim(),
      'contato_responsavel': _controllers['contato_responsavel']!.text.trim(),
      'foto_preenchida': _temFoto(),
      'assinatura_preenchida': _assinaturaUrl != null || _assinaturaBytes != null,
      'autorizacao': _autorizacao,
      'idade_calculada': _controllers['data_nascimento']!.text.trim().isEmpty
          ? null
          : _calcularIdade(_controllers['data_nascimento']!.text.trim()),
      'is_maior_idade': _isMaiorIdade(),
    };
  }

  bool _campoSensivelRastreio(String campo) {
    return campo == 'cpf' ||
        campo == 'contato_aluno' ||
        campo == 'contato_responsavel';
  }

  String _campoParaEtapaRastreio(String campo) {
    switch (campo) {
      case 'nome':
      case 'apelido':
      case 'data_nascimento':
        return 'dados_aluno';
      case 'cpf':
        return 'documento';
      case 'rua':
      case 'numero':
      case 'bairro':
      case 'cidade':
        return 'endereco';
      case 'contato_aluno':
      case 'nome_responsavel':
      case 'contato_responsavel':
        return 'contato';
      default:
        return _etapaAtualRastreio();
    }
  }

  void _configurarRastreioCamposDigitados() {
    for (final entry in _controllers.entries) {
      final campo = entry.key;
      final controller = entry.value;

      controller.addListener(() {
        _registrarCampoDigitadoDebounce(campo, controller.text);
      });
    }
  }

  void _registrarCampoDigitadoDebounce(String campo, String valor) {
    _debounceRastreioCampos[campo]?.cancel();
    _debounceRastreioCampos[campo] = Timer(const Duration(milliseconds: 850), () {
      if (!mounted) return;

      _rastreioService.registrarCampoFormulario(
        formulario: 'inscricao_publica',
        campo: campo,
        valor: valor,
        etapa: _campoParaEtapaRastreio(campo),
        origem: 'digitacao',
        sensivel: _campoSensivelRastreio(campo),
        metadata: {
          'etapa_atual': _etapaAtualRastreio(),
          'etapa_numero': _currentStep + 1,
        },
      );
    });
  }

  void _registrarSnapshotInscricao({
    required String momento,
    Map<String, dynamic>? metadata,
  }) {
    _rastreioService.registrarSnapshotFormulario(
      formulario: 'inscricao_publica',
      momento: momento,
      etapa: _etapaAtualRastreio(),
      origem: 'inscricao_publica',
      campos: _snapshotCamposInscricao(),
      camposSensiveis: const ['cpf', 'contato_aluno', 'contato_responsavel'],
      metadata: {
        'etapa_atual': _etapaAtualRastreio(),
        'etapa_numero': _currentStep + 1,
        ...?metadata,
      },
    );
  }

  void _iniciarRastreioInscricao() {
    _inicioTelaInscricao = DateTime.now();
    _inicioEtapaAtual = DateTime.now();
    _rastreioInscricaoIniciado = true;

    unawaited(
      _rastreioService.iniciarTela(
        'inscricao_publica',
        origem: 'landing_page',
        metadata: {
          'formulario': 'aula_experimental',
          'total_etapas': 7,
        },
      ),
    );

    unawaited(_rastreioService.registrarPaginaVista('inscricao_publica', 'landing_page'));
    unawaited(_registrarEntradaEtapa(0, origem: 'init'));
  }

  Future<void> _registrarEntradaEtapa(int etapa, {String origem = 'navegacao'}) async {
    _inicioEtapaAtual = DateTime.now();

    await _rastreioService.registrarEtapaFormulario(
      formulario: 'inscricao_publica',
      etapa: etapa + 1,
      nomeEtapa: _nomeEtapaRastreio(etapa),
      acao: 'entrou',
      origem: origem,
      metadata: _metadataResumoInscricao(),
    );
  }

  Future<void> _registrarSaidaEtapa(
      int etapa, {
        required String destino,
        String origem = 'navegacao',
      }) async {
    await _rastreioService.registrarEtapaFormulario(
      formulario: 'inscricao_publica',
      etapa: etapa + 1,
      nomeEtapa: _nomeEtapaRastreio(etapa),
      acao: 'saiu',
      origem: origem,
      metadata: {
        ..._metadataResumoInscricao(),
        'destino': destino,
        'duracao_etapa_segundos': _tempoEtapaAtualSegundos,
      },
    );
  }

  void _rastrearAcaoInscricao(
      String acao, {
        String? origem,
        Map<String, dynamic>? metadata,
      }) {
    unawaited(
      _rastreioService.registrarAcaoFormulario(
        formulario: 'inscricao_publica',
        acao: acao,
        origem: origem,
        metadata: {..._metadataResumoInscricao(), ...?metadata},
      ),
    );
  }

  void _rastrearErroInscricao(
      String local,
      List<String> erros, {
        String? origem,
        Map<String, dynamic>? metadata,
      }) {
    unawaited(
      _rastreioService.registrarErroFormulario(
        formulario: 'inscricao_publica',
        local: local,
        erros: erros,
        origem: origem,
        metadata: {..._metadataResumoInscricao(), ...?metadata},
      ),
    );
  }

  void _registrarSaidaInscricaoSeNecessario({required String motivo}) {
    if (!_rastreioInscricaoIniciado || _inscricaoFinalizadaComSucesso) return;

    unawaited(_registrarSaidaEtapa(_currentStep, destino: motivo, origem: 'saida_inscricao'));

    unawaited(
      _rastreioService.registrarAcaoFormulario(
        formulario: 'inscricao_publica',
        acao: 'abandonou_inscricao',
        origem: motivo,
        metadata: _metadataResumoInscricao(),
      ),
    );

    unawaited(
      _rastreioService.finalizarTela(
        destino: motivo,
        metadata: _metadataResumoInscricao(),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    if (!mounted) return;
    final t = context.uai;
    final bg = _ensureVisible(t.success, t.background);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: _readableOn(bg)),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: TextStyle(color: _readableOn(bg)))),
            ],
          ),
          backgroundColor: bg,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.buttonRadius)),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    final t = context.uai;
    final bg = _ensureVisible(t.error, t.background);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: _readableOn(bg)),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: TextStyle(color: _readableOn(bg)))),
            ],
          ),
          backgroundColor: bg,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.buttonRadius)),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> _verificarInscricoes() async {
    try {
      final doc = await _firestore.collection('configuracoes').doc('inscricoes').get();

      if (!doc.exists) {
        if (!mounted) return;
        setState(() {
          _inscricoesAbertas = false;
          _configuracoesCarregadas = true;
          _etapaValida[0] = false;
          _carregando = false;
        });
        _rastrearAcaoInscricao('configuracao_inscricao_nao_encontrada', origem: 'verificar_inscricoes');
        return;
      }

      final data = doc.data()!;
      final inscricoesSnapshot = await _firestore
          .collection('inscricoes')
          .where('status', isEqualTo: 'pendente')
          .get();

      final vagasTotal = data['vagas_disponiveis'] ?? 0;
      final inscricoesPendentes = inscricoesSnapshot.docs.length;
      final vagasRestantes = vagasTotal - inscricoesPendentes;

      if (!mounted) return;
      setState(() {
        _inscricoesAbertas = data['inscricoes_abertas'] ?? false;
        _vagasDisponiveis = vagasTotal;
        _vagasRestantes = vagasRestantes;
        _temVagas = vagasRestantes > 0;
        _idadeMinima = data['idade_minima'] ?? 5;
        _idadeMaxima = data['idade_maxima'] ?? 16;
        _recolherAssinatura = data['recolher_assinatura'] ?? true;
        _configuracoesCarregadas = true;
        _etapaValida[0] = _inscricoesAbertas && _temVagas;
        _carregando = false;
      });

      _rastrearAcaoInscricao(
        'configuracao_inscricao_carregada',
        origem: 'verificar_inscricoes',
        metadata: {
          'inscricoes_abertas': _inscricoesAbertas,
          'vagas_total': _vagasDisponiveis,
          'vagas_restantes': _vagasRestantes,
          'tem_vagas': _temVagas,
          'idade_minima': _idadeMinima,
          'idade_maxima': _idadeMaxima,
          'recolher_assinatura': _recolherAssinatura,
        },
      );
    } catch (e) {
      _rastrearErroInscricao(
        'verificar_inscricoes',
        ['Erro ao verificar disponibilidade: $e'],
        origem: 'firestore',
      );
      if (!mounted) return;
      setState(() {
        _inscricoesAbertas = false;
        _configuracoesCarregadas = true;
        _etapaValida[0] = false;
        _carregando = false;
        _mensagem = 'Erro ao verificar disponibilidade';
      });
    }
  }

  void _validarEtapa1() {
    if (!mounted) return;
    final erros = <String>[];

    final nome = _controllers['nome']!.text.trim();
    final apelido = _controllers['apelido']!.text.trim();
    final dataNascimento = _controllers['data_nascimento']!.text.trim();

    final nomeValido = _validarNomePessoa(nome);
    if (!nomeValido) {
      erros.add(nome.isEmpty ? 'Preencha o nome completo.' : 'O nome completo deve conter apenas letras.');
    }

    final apelidoValido = _validarNomePessoa(apelido);
    if (!apelidoValido) {
      erros.add(apelido.isEmpty ? 'Preencha o apelido.' : 'O apelido deve conter apenas letras.');
    }

    final dataValida = dataNascimento.isNotEmpty;
    if (!dataValida) erros.add('Informe a data de nascimento.');

    final sexoValido = _sexo != null;
    if (!sexoValido) erros.add('Selecione o sexo.');

    bool idadeValida = true;
    if (dataValida) {
      final idade = _calcularIdade(dataNascimento);
      idadeValida = idade >= _idadeMinima && idade <= _idadeMaxima;
      if (!idadeValida) {
        erros.add('A idade permitida é de $_idadeMinima a $_idadeMaxima anos.');
      }
    }

    setState(() {
      _etapaValida[2] = nomeValido && apelidoValido && dataValida && sexoValido && idadeValida;
      _errosPorEtapa[2] = erros;
    });
  }

  void _validarEtapaFoto() {
    if (!mounted) return;
    final erros = <String>[];
    if (!_temFoto()) erros.add('Tire a foto do aluno para identificação.');
    setState(() {
      _etapaValida[1] = _temFoto();
      _errosPorEtapa[1] = erros;
    });
  }

  void _validarEtapa2() {
    if (!mounted) return;
    final erros = <String>[];

    final contatoAlunoValido = _telefoneCompleto(_controllers['contato_aluno']!.text);
    if (!contatoAlunoValido) erros.add('Informe o telefone completo do aluno.');

    bool nomeRespValido = true;
    bool contatoRespValido = true;

    if (!_isMaiorIdade()) {
      final nomeResp = _controllers['nome_responsavel']!.text.trim();
      nomeRespValido = _validarNomePessoa(nomeResp);
      if (!nomeRespValido) {
        erros.add(nomeResp.isEmpty ? 'Preencha o nome do responsável.' : 'O nome do responsável deve conter apenas letras.');
      }

      contatoRespValido = _telefoneCompleto(_controllers['contato_responsavel']!.text);
      if (!contatoRespValido) erros.add('Informe o telefone completo do responsável.');
    }

    setState(() {
      _etapaValida[3] = contatoAlunoValido && nomeRespValido && contatoRespValido;
      _errosPorEtapa[3] = erros;
    });
  }

  void _validarEtapa3() {
    if (!mounted) return;
    final erros = <String>[];

    final rua = _controllers['rua']!.text.trim();
    final numero = _controllers['numero']!.text.trim();
    final bairro = _controllers['bairro']!.text.trim();
    final cidade = _controllers['cidade']!.text.trim();

    final ruaValida = _validarEnderecoTexto(rua);
    if (!ruaValida) erros.add(rua.isEmpty ? 'Preencha a rua.' : 'A rua contém caracteres inválidos.');

    final numeroValido = numero.isNotEmpty && numero.length <= 5;
    if (!numeroValido) {
      erros.add(numero.isEmpty ? 'Preencha o número do endereço.' : 'O número deve ter no máximo 5 dígitos.');
    }

    final bairroValido = _validarEnderecoTexto(bairro);
    if (!bairroValido) erros.add(bairro.isEmpty ? 'Preencha o bairro.' : 'O bairro contém caracteres inválidos.');

    final cidadeValida = _validarEnderecoTexto(cidade);
    if (!cidadeValida) erros.add(cidade.isEmpty ? 'Preencha a cidade.' : 'A cidade contém caracteres inválidos.');

    setState(() {
      _etapaValida[4] = ruaValida && numeroValido && bairroValido && cidadeValida;
      _errosPorEtapa[4] = erros;
    });
  }

  void _validarEtapaFinal() {
    final erros = <String>[];

    if (!_autorizacao) erros.add('Aceite os termos de responsabilidade.');

    if (_recolherAssinatura && _assinaturaUrl == null && _assinaturaBytes == null) {
      erros.add('Assine o termo digitalmente.');
    }

    if (!_temFoto()) erros.add('A foto do aluno é obrigatória.');

    setState(() {
      _etapaValida[6] = _autorizacao &&
          (_recolherAssinatura ? (_assinaturaUrl != null || _assinaturaBytes != null) : true) &&
          _temFoto();
      _errosPorEtapa[6] = erros;
    });
  }

  void _mostrarFeedbackErros() {
    final erros = _errosPorEtapa[_currentStep] ?? [];
    final errosRastreio = erros.isEmpty ? ['Preencha os campos obrigatórios.'] : erros;

    _rastrearErroInscricao(
      _nomeEtapaRastreio(_currentStep),
      errosRastreio,
      origem: 'tentativa_avancar',
    );

    if (erros.isEmpty) {
      _showErrorSnackbar('Preencha os campos obrigatórios.');
      return;
    }

    if (erros.length == 1) {
      _showErrorSnackbar(erros.first);
      return;
    }

    _showCustomErrorDialog(titulo: 'Campos pendentes', erros: erros);
  }

  void _showCustomErrorDialog({
    required String titulo,
    required List<String> erros,
  }) {
    if (!mounted) return;

    final t = context.uai;
    final danger = _ensureVisible(t.error, t.surface);

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Material(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 2),
              clipBehavior: Clip.antiAlias,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.cardRadius + 2),
                  border: Border.all(color: t.border),
                  boxShadow: t.cardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _roundIcon(icon: Icons.warning_amber_rounded, color: danger, size: 42),
                    const SizedBox(height: 12),
                    Text(
                      titulo,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: t.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(danger.withOpacity(0.08), t.cardAlt),
                        borderRadius: BorderRadius.circular(t.inputRadius),
                        border: Border.all(color: danger.withOpacity(0.16)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: erros.map((erro) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.error_outline_rounded, color: danger, size: 17),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    erro,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: t.textPrimary,
                                      height: 1.25,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: danger,
                          foregroundColor: _readableOn(danger),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.buttonRadius)),
                        ),
                        child: const Text('ENTENDI', style: TextStyle(fontWeight: FontWeight.w900)),
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

  void _setProcessandoFotoLocal(String status) {
    if (!mounted) return;
    setState(() {
      _processandoFotoLocal = true;
      _statusFotoLocal = status;
    });
  }

  void _limparProcessandoFotoLocal() {
    if (!mounted) return;
    setState(() {
      _processandoFotoLocal = false;
      _statusFotoLocal = '';
    });
  }

  Future<bool> _mostrarOrientacaoFotoAluno() async {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.surface);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Material(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 2),
              clipBehavior: Clip.antiAlias,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.cardRadius + 2),
                  border: Border.all(color: t.border),
                  boxShadow: t.cardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _roundIcon(icon: Icons.center_focus_strong_rounded, color: primary, size: 34),
                    const SizedBox(height: 14),
                    Text(
                      'Foto para identificação',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.textPrimary, fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tire a foto do aluno de frente, com o rosto bem visível.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.textSecondary, height: 1.35, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: 176,
                      height: 222,
                      decoration: BoxDecoration(
                        color: t.cardAlt,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: t.success.withOpacity(0.80), width: 2),
                      ),
                      child: CustomPaint(
                        painter: _GuiaRostoInscricaoPainter(
                          lineColor: t.success.withOpacity(0.60),
                          borderColor: t.border,
                        ),
                        child: Center(
                          child: Icon(Icons.face_rounded, size: 74, color: t.textMuted),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 360;

                        final cancel = OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('CANCELAR'),
                        );

                        final ok = ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context, true),
                          icon: const Icon(Icons.camera_alt_rounded),
                          label: const Text('ABRIR CÂMERA'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: t.primary,
                            foregroundColor: _readableOn(t.primary),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            textStyle: const TextStyle(fontWeight: FontWeight.w900),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.buttonRadius)),
                          ),
                        );

                        if (narrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [cancel, const SizedBox(height: 10), ok],
                          );
                        }

                        return Row(
                          children: [Expanded(child: cancel), const SizedBox(width: 10), Expanded(child: ok)],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    return result == true;
  }

  Future<void> _selecionarFoto() async {
    try {
      _rastrearAcaoInscricao('foto_orientacao_aberta', origem: 'etapa_foto');

      final continuar = await _mostrarOrientacaoFotoAluno();
      if (!continuar) {
        _rastrearAcaoInscricao('foto_orientacao_cancelada', origem: 'etapa_foto');
        return;
      }

      _rastrearAcaoInscricao('foto_orientacao_confirmada', origem: 'etapa_foto');

      _setProcessandoFotoLocal('Abrindo câmera...');

      final picker = ImagePicker();

      _rastrearAcaoInscricao('camera_aberta', origem: 'etapa_foto');

      final image = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 88,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (image == null) {
        _limparProcessandoFotoLocal();
        _rastrearAcaoInscricao('foto_camera_cancelada', origem: 'camera');
        return;
      }

      _setProcessandoFotoLocal('Preparando foto...');

      final bytes = await image.readAsBytes();

      setState(() {
        _fotoBytes = bytes;
        _fotoNome = 'foto_aluno_${DateTime.now().millisecondsSinceEpoch}.jpg';
        _fotoUrl = null;
        _uploadingFoto = false;
        _processandoFotoLocal = false;
        _statusFotoLocal = '';
      });

      _rastrearAcaoInscricao(
        'foto_capturada',
        origem: 'camera',
        metadata: {'bytes': bytes.length},
      );

      _validarEtapaFoto();
      _showSuccessSnackbar('📸 Foto registrada! Ela será enviada ao finalizar.');
    } catch (e) {
      _rastrearErroInscricao('foto_aluno', ['Erro ao tirar/processar foto: $e'], origem: 'foto');
      _limparProcessandoFotoLocal();
      if (mounted) setState(() => _uploadingFoto = false);
      _showErrorSnackbar('Erro ao tirar foto: $e');
    }
  }

  Future<void> _uploadFotoFirebase() async {
    if (_fotoBytes == null || _fotoNome == null) return;

    _rastrearAcaoInscricao('upload_foto_iniciado', origem: 'envio_final');

    setState(() {
      _uploadingFoto = true;
      _processandoFotoLocal = true;
      _statusFotoLocal = 'Enviando foto com segurança...';
    });

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final nomeAluno = _controllers['nome']!
          .text
          .trim()
          .replaceAll(RegExp(r'\s+'), '_')
          .replaceAll(RegExp(r'[^A-Za-zÀ-ÖØ-öø-ÿ0-9_\-]'), '');

      final fileName = '${timestamp}_${nomeAluno.isEmpty ? 'aluno' : nomeAluno}.jpg';
      final fotoRef = _storage.ref().child('fotos_inscricoes/$fileName');

      await fotoRef.putData(
        _fotoBytes!,
        SettableMetadata(contentType: 'image/jpeg', customMetadata: {'origem': 'camera_inscricao_publica'}),
      );

      final downloadUrl = await fotoRef.getDownloadURL();

      _rastrearAcaoInscricao('upload_foto_concluido', origem: 'envio_final');

      setState(() {
        _fotoUrl = downloadUrl;
        _uploadingFoto = false;
        _processandoFotoLocal = false;
        _statusFotoLocal = '';
      });
    } catch (e) {
      setState(() {
        _uploadingFoto = false;
        _processandoFotoLocal = false;
        _statusFotoLocal = '';
      });
      _rastrearErroInscricao('upload_foto', ['Erro ao fazer upload da foto: $e'], origem: 'firebase_storage');
      _showErrorSnackbar('Erro ao fazer upload da foto: $e');
      rethrow;
    }
  }

  void _removerFoto() {
    _rastrearAcaoInscricao('remover_foto_dialog_aberto', origem: 'foto_aluno');

    final t = context.uai;
    final danger = _ensureVisible(t.error, t.surface);

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: t.surface,
          title: Text('Remover foto', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900)),
          content: Text('Tem certeza que deseja remover esta foto?', style: TextStyle(color: t.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _fotoBytes = null;
                  _fotoNome = null;
                  _fotoUrl = null;
                  _processandoFotoLocal = false;
                  _statusFotoLocal = '';
                });
                Navigator.pop(context);
                _validarEtapaFoto();
                _rastrearAcaoInscricao('foto_removida', origem: 'foto_aluno');
                _showSuccessSnackbar('Foto removida com sucesso');
              },
              style: ElevatedButton.styleFrom(backgroundColor: danger, foregroundColor: _readableOn(danger)),
              child: const Text('REMOVER'),
            ),
          ],
        );
      },
    );
  }

  String _gerarTermoTexto() {
    final isMaior = _isMaiorIdade();
    final nomeAluno = _controllers['nome']!.text;
    final nomeResp = isMaior ? nomeAluno : _controllers['nome_responsavel']!.text;
    final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    if (isMaior) {
      return """
TERMO DE RESPONSABILIDADE

Eu, $nomeAluno, declaro para os devidos fins que:

1. ESTOU CIENTE de que a Capoeira é uma arte marcial que envolve atividades físicas de médio a alto impacto, podendo resultar em lesões.

2. ASSUMO total responsabilidade por qualquer dano físico que possa ocorrer durante a prática, isentando o Grupo UAI CAPOEIRA de qualquer ônus.

3. COMPROMETO-ME a informar previamente qualquer condição de saúde ou limitação física.

4. AUTORIZO a participação na aula experimental de Capoeira.

5. CONCORDO com as filmagens e fotografias para fins institucionais.

Data e hora: $dataHora

Assinatura: ${(_assinaturaUrl != null || _assinaturaBytes != null) ? '[ASSINATURA DIGITAL]' : '_____________________________'}
""";
    }

    return """
TERMO DE RESPONSABILIDADE

Eu, $nomeResp, responsável legal por $nomeAluno, declaro para os devidos fins que:

1. AUTORIZO a participação do(a) menor acima identificado(a) na aula experimental de Capoeira oferecida pelo Grupo UAI CAPOEIRA.

2. ESTOU CIENTE dos riscos da prática esportiva e assumo total responsabilidade.

3. COMPROMETO-ME a informar previamente qualquer condição de saúde ou limitação física do aluno.

4. CONCORDO com as filmagens e fotografias para fins institucionais.

Data e hora: $dataHora

Assinatura do Responsável: ${(_assinaturaUrl != null || _assinaturaBytes != null) ? '[ASSINATURA DIGITAL]' : '_____________________________'}
""";
  }

  Future<void> _abrirTelaAssinatura() async {
    _rastrearAcaoInscricao('assinatura_abriu', origem: 'revisao');

    final isMaior = _isMaiorIdade();
    final nomeResponsavel = isMaior ? _controllers['nome']!.text : _controllers['nome_responsavel']!.text;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => SignatureScreen(
          inscricaoId: 'temp_${DateTime.now().millisecondsSinceEpoch}',
          nomeResponsavel: nomeResponsavel,
          nomeAluno: _controllers['nome']!.text,
          onConfirm: (imageBytes) {
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

            _rastrearAcaoInscricao('assinatura_registrada', origem: 'signature_screen', metadata: {'bytes': imageBytes.length});
            _showSuccessSnackbar('✅ Assinatura registrada com sucesso!');
          },
        ),
      ),
    );

    if (result == true && mounted) {
      _rastrearAcaoInscricao('assinatura_confirmada', origem: 'signature_screen');
      _validarEtapaFinal();
    } else {
      _rastrearAcaoInscricao('assinatura_cancelada_ou_voltou', origem: 'signature_screen');
    }
  }

  Future<void> _uploadAssinaturaFirebase() async {
    if (_assinaturaUrl?.isNotEmpty == true) return;
    if (_assinaturaBytes == null) return;

    _rastrearAcaoInscricao('upload_assinatura_iniciado', origem: 'envio_final');
    setState(() => _uploadingAssinatura = true);

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final nomeResponsavel = _controllers['nome_responsavel']!.text.trim().isNotEmpty
          ? _controllers['nome_responsavel']!.text.trim()
          : _controllers['nome']!.text.trim();

      final nomeSeguro = nomeResponsavel
          .replaceAll(RegExp(r'\s+'), '_')
          .replaceAll(RegExp(r'[^A-Za-zÀ-ÖØ-öø-ÿ0-9_\-]'), '');

      final fileName = '${timestamp}_${nomeSeguro.isEmpty ? 'responsavel' : nomeSeguro}.png';
      final assinaturaRef = _storage.ref().child('assinaturas_inscricoes/$fileName');

      await assinaturaRef.putData(
        _assinaturaBytes!,
        SettableMetadata(
          contentType: 'image/png',
          customMetadata: {'origem': 'assinatura_inscricao_publica', 'modo': 'upload_no_envio_final'},
        ),
      );

      final downloadUrl = await assinaturaRef.getDownloadURL();

      _rastrearAcaoInscricao('upload_assinatura_concluido', origem: 'envio_final');

      setState(() {
        _assinaturaUrl = downloadUrl;
        _assinaturaBytes = null;
        _uploadingAssinatura = false;
      });
    } catch (e) {
      setState(() => _uploadingAssinatura = false);
      _rastrearErroInscricao('upload_assinatura', ['Erro ao enviar assinatura: $e'], origem: 'firebase_storage');
      _showErrorSnackbar('Erro ao enviar assinatura: $e');
      rethrow;
    }
  }

  Future<void> _enviarInscricao() async {
    _rastrearAcaoInscricao('tentou_enviar_inscricao', origem: 'revisao');
    _validarEtapaFinal();

    if (!(_etapaValida[6] ?? false)) {
      _rastrearErroInscricao('revisao_envio', _errosPorEtapa[6] ?? ['Revisão inválida'], origem: 'tentativa_envio');
      _mostrarFeedbackErros();
      return;
    }

    setState(() => _enviando = true);

    try {
      final configDoc = await _firestore.collection('configuracoes').doc('inscricoes').get();
      final config = configDoc.data() ?? {};
      final vagasDisponiveis = config['vagas_disponiveis'] ?? 0;

      final inscricoesSnapshot = await _firestore
          .collection('inscricoes')
          .where('status', isEqualTo: 'pendente')
          .get();

      if (vagasDisponiveis > 0 && inscricoesSnapshot.docs.length >= vagasDisponiveis) {
        setState(() {
          _mensagem = 'Desculpe, as vagas para inscrições estão esgotadas.';
          _enviando = false;
        });
        _rastrearErroInscricao('envio_inscricao', ['Vagas esgotadas no momento do envio.'], origem: 'vagas');
        _showErrorSnackbar('❌ Vagas esgotadas!');
        return;
      }

      final isMaior = _isMaiorIdade();

      final dados = <String, dynamic>{
        'nome': _toUpperCase(_controllers['nome']!.text),
        'apelido': _toUpperCase(_controllers['apelido']!.text),
        'data_nascimento': _controllers['data_nascimento']!.text.trim(),
        'sexo': _sexo,
        'contato_aluno': _controllers['contato_aluno']!.text.replaceAll(RegExp(r'[^0-9]'), ''),
        'autorizacao': _autorizacao,
        'termo_autorizacao': _gerarTermoTexto(),
        'status': 'pendente',
        'data_inscricao': FieldValue.serverTimestamp(),
        'is_maior_idade': isMaior,
        'assinatura_recolhida': _recolherAssinatura,
      };

      if (_fotoUrl == null || _fotoUrl!.isEmpty) {
        await _uploadFotoFirebase();
      }

      if (_fotoUrl != null && _fotoUrl!.isNotEmpty) {
        dados['foto_url'] = _fotoUrl;
      } else {
        throw Exception('Foto é obrigatória');
      }

      if (_recolherAssinatura &&
          ((_assinaturaUrl == null || _assinaturaUrl?.isEmpty == true) && _assinaturaBytes != null)) {
        await _uploadAssinaturaFirebase();
      }

      if (_recolherAssinatura &&
          (_assinaturaUrl == null || _assinaturaUrl?.isEmpty == true) &&
          _assinaturaBytes == null) {
        throw Exception('Assinatura é obrigatória');
      }

      if (_assinaturaUrl?.isNotEmpty == true) dados['assinatura_url'] = _assinaturaUrl;

      if (!isMaior) {
        dados['nome_responsavel'] = _toUpperCase(_controllers['nome_responsavel']!.text);
        dados['contato_responsavel'] = _controllers['contato_responsavel']!.text.replaceAll(RegExp(r'[^0-9]'), '');
      } else {
        dados['nome_responsavel'] = _toUpperCase(_controllers['nome']!.text);
        dados['contato_responsavel'] = _controllers['contato_aluno']!.text.replaceAll(RegExp(r'[^0-9]'), '');
      }

      if (_controllers['cpf']!.text.trim().isNotEmpty) {
        dados['cpf'] = _controllers['cpf']!.text.replaceAll(RegExp(r'[^0-9]'), '');
      }

      final enderecoParts = <String>[];
      if (_controllers['rua']!.text.isNotEmpty) {
        var ruaNumero = _toUpperCase(_controllers['rua']!.text);
        if (_controllers['numero']!.text.isNotEmpty) {
          ruaNumero += ' - ${_toUpperCase(_controllers['numero']!.text)}';
        }
        enderecoParts.add(ruaNumero);
      }
      if (_controllers['bairro']!.text.isNotEmpty) enderecoParts.add(_toUpperCase(_controllers['bairro']!.text));
      if (_controllers['cidade']!.text.isNotEmpty) enderecoParts.add(_toUpperCase(_controllers['cidade']!.text));
      dados['endereco'] = enderecoParts.join(', ');

      final inscricaoRef = await _firestore.collection('inscricoes').add(dados);

      final novoTotal = inscricoesSnapshot.docs.length + 1;
      await _firestore.collection('configuracoes').doc('inscricoes').set(
        {'total_inscricoes': novoTotal},
        SetOptions(merge: true),
      );

      _inscricaoFinalizadaComSucesso = true;

      unawaited(_registrarSaidaEtapa(_currentStep, destino: 'inscricao_enviada', origem: 'conversao'));

      unawaited(
        _rastreioService.registrarConversao(
          nome: 'inscricao_publica_enviada',
          origem: 'formulario_aula_experimental',
          metadata: {
            ..._metadataResumoInscricao(),
            'inscricao_id': inscricaoRef.id,
            'idade_aluno': _calcularIdade(_controllers['data_nascimento']!.text),
            'is_maior_idade': isMaior,
            'tem_cpf': _controllers['cpf']!.text.trim().isNotEmpty,
            'tempo_total_inscricao_segundos': _tempoTotalInscricaoSegundos,
          },
        ),
      );

      unawaited(_rastreioService.finalizarTela(destino: 'inscricao_enviada', metadata: _metadataResumoInscricao()));
      _registrarSnapshotInscricao(momento: 'envio_sucesso');

      if (mounted) {
        setState(() => _enviando = false);
        _mostrarDialogSucesso(dados);
      }
    } catch (e) {
      _rastrearErroInscricao('envio_inscricao', ['Erro ao enviar inscrição: $e'], origem: 'firestore_storage');
      if (!mounted) return;
      setState(() {
        _mensagem = 'Erro ao enviar inscrição: $e';
        _enviando = false;
      });
      _showErrorSnackbar('Erro ao enviar inscrição: $e');
    }
  }

  void _mostrarDialogSucesso(Map<String, dynamic> dados) {
    final t = context.uai;
    final success = _ensureVisible(t.success, t.surface);

    final isMaior = dados['is_maior_idade'] ?? false;
    final nomeResponsavel = _getPrimeiroNome(dados['nome_responsavel']);
    final nomeAluno = _getPrimeiroNome(dados['nome']);
    final idadeAluno = _calcularIdade(dados['data_nascimento']);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92, maxWidth: 520),
            child: Material(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 4),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [success, t.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 82,
                          height: 82,
                          decoration: BoxDecoration(
                            color: _readableOn(success).withOpacity(0.18),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: _readableOn(success).withOpacity(0.20)),
                          ),
                          child: Icon(Icons.check_circle_rounded, color: _readableOn(success), size: 54),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Inscrição enviada!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _readableOn(success), fontSize: 20, height: 1.05, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isMaior ? 'Recebemos seus dados com sucesso.' : 'Recebemos a inscrição de $nomeAluno com sucesso.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _readableOn(success).withOpacity(0.86), fontSize: 13, height: 1.35, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          _successMessageBox(
                            icon: Icons.waving_hand_rounded,
                            text: isMaior ? 'Olá, $nomeAluno!' : 'Olá, $nomeResponsavel!',
                            color: t.info,
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: _cardDecoration(),
                            child: Column(
                              children: [
                                _buildInfoDialog('Aluno', dados['nome']),
                                _buildInfoDialog('Idade', '$idadeAluno anos'),
                                _buildInfoDialog('Contato', dados['contato_aluno']),
                                if (!isMaior) _buildInfoDialog('Responsável', dados['nome_responsavel']),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _successMessageBox(
                            icon: Icons.notifications_active_rounded,
                            text: 'Agora é só aguardar o contato do professor para combinar os próximos detalhes da aula experimental.',
                            color: t.warning,
                          ),
                          if (_recolherAssinatura) ...[
                            const SizedBox(height: 12),
                            _successMessageBox(
                              icon: Icons.draw_rounded,
                              text: (_assinaturaUrl != null || _assinaturaBytes != null)
                                  ? 'Assinatura digital registrada.'
                                  : 'Termo de responsabilidade aceito.',
                              color: t.success,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                      decoration: BoxDecoration(color: t.card, border: Border(top: BorderSide(color: t.border))),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _rastrearAcaoInscricao('finalizou_dialog_sucesso', origem: 'sucesso');
                            Navigator.of(context).pop();
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (context) => const LandingPage()),
                                  (route) => false,
                            );
                          },
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('FINALIZAR'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: success,
                            foregroundColor: _readableOn(success),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            textStyle: const TextStyle(fontWeight: FontWeight.w900),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.buttonRadius)),
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
      },
    );
  }

  Widget _successMessageBox({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: t.textPrimary, fontSize: 13, height: 1.32, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoDialog(String label, String? value) {
    final t = context.uai;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 82, child: Text(label, style: TextStyle(fontSize: 12, color: t.textSecondary))),
          Expanded(
            child: Text(
              value ?? 'Não informado',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  void _proximaEtapa() {
    if (_currentStep >= 6) return;

    _rastrearAcaoInscricao('clicou_avancar_etapa', origem: _nomeEtapaRastreio(_currentStep));

    if (_currentStep == 1) _validarEtapaFoto();
    if (_currentStep == 2) _validarEtapa1();
    if (_currentStep == 3) _validarEtapa2();
    if (_currentStep == 4) _validarEtapa3();
    if (_currentStep == 5) {
      _etapaValida[5] = true;
      _errosPorEtapa[5] = [];
    }

    final isValido = _currentStep == 5 ? true : (_etapaValida[_currentStep] ?? false);

    if (!isValido) {
      _mostrarFeedbackErros();
      return;
    }

    final etapaAnterior = _currentStep;
    final proxima = _currentStep + 1;

    unawaited(_registrarSaidaEtapa(etapaAnterior, destino: _nomeEtapaRastreio(proxima), origem: 'avancar'));

    setState(() => _currentStep++);

    unawaited(_registrarEntradaEtapa(proxima, origem: 'avancar'));

    _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _etapaAnterior() {
    if (_currentStep <= 0) return;

    _rastrearAcaoInscricao('clicou_voltar_etapa', origem: _nomeEtapaRastreio(_currentStep));

    final etapaAnterior = _currentStep;
    final destino = _currentStep - 1;

    unawaited(_registrarSaidaEtapa(etapaAnterior, destino: _nomeEtapaRastreio(destino), origem: 'voltar'));

    setState(() => _currentStep--);

    unawaited(_registrarEntradaEtapa(destino, origem: 'voltar'));

    _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Future<bool> _onWillPop() async {
    _rastrearAcaoInscricao('pressionou_voltar_sistema', origem: _nomeEtapaRastreio(_currentStep));

    if (_currentStep == 0) {
      final shouldExit = await _confirmarSaida();
      if (shouldExit == true) {
        _registrarSaidaInscricaoSeNecessario(motivo: 'voltar_sistema_confirmado');
        if (mounted) Navigator.pop(context);
      } else {
        _rastrearAcaoInscricao('cancelou_saida_inscricao', origem: 'dialog_saida');
      }
      return false;
    }

    _etapaAnterior();
    return false;
  }

  Future<bool?> _confirmarSaida() {
    final t = context.uai;
    final warning = _ensureVisible(t.warning, t.surface);

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: t.surface,
          title: Column(
            children: [
              _roundIcon(icon: Icons.exit_to_app_rounded, color: warning, size: 34),
              const SizedBox(height: 12),
              Text('Sair da inscrição?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: t.textPrimary)),
            ],
          ),
          content: Text(
            'Se você sair agora, os dados preenchidos serão perdidos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textSecondary),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CONTINUAR')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: warning, foregroundColor: _readableOn(warning)),
              child: const Text('SAIR'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    // Esta tela roda dentro da LandingPage. Não use Scaffold/AppBar aqui,
    // para evitar duas barras na área pública.
    return WillPopScope(
      onWillPop: _onWillPop,
      child: ColoredBox(
        color: t.background,
        child: _buildBodyState(),
      ),
    );
  }

  Widget _buildBodyState() {
    if (_carregando) return _buildLoadingScreen();

    if (!_inscricoesAbertas) {
      _rastreioService.registrarPaginaVista('inscricao_fechada', 'inscricao_publica');
      return _buildInscricoesFechadas();
    }

    return _enviando ? _buildSendingState() : _buildFormulario();
  }

  Widget _buildLoadingScreen() {
    final t = context.uai;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(22),
        margin: const EdgeInsets.all(18),
        decoration: _cardDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: t.primary),
            const SizedBox(height: 14),
            Text('Verificando inscrições...', style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _buildInscricoesFechadas() {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.surface);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          decoration: _cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _roundIcon(icon: Icons.lock_rounded, color: primary, size: 42, large: true),
              const SizedBox(height: 18),
              Text(
                'Inscrições fechadas',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: t.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                _mensagem.isNotEmpty ? _mensagem : 'No momento não estamos aceitando novas inscrições.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('VOLTAR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.primary,
                    foregroundColor: _readableOn(t.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.buttonRadius)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormulario() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: [
            _buildStepHeader(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStepWelcome(),
                  _buildStepFoto(),
                  _buildStepAluno(),
                  _buildStepContato(),
                  _buildStepEndereco(),
                  _buildStepCpf(),
                  _buildStepRevisao(),
                ],
              ),
            ),
            _buildNavigationButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildSendingState() {
    final t = context.uai;

    return Center(
      child: Container(
        margin: const EdgeInsets.all(18),
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: _cardDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: t.primary),
            const SizedBox(height: 18),
            Text(
              _uploadingAssinatura
                  ? 'Enviando assinatura...'
                  : _uploadingFoto
                  ? 'Enviando foto...'
                  : 'Enviando sua inscrição...',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Aguarde só um instante. Estamos enviando foto, assinatura e dados com segurança.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textSecondary, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepHeader() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    final etapas = [
      ('Boas-vindas', Icons.waving_hand_rounded),
      ('Foto do aluno', Icons.camera_alt_rounded),
      ('Dados do aluno', Icons.person_rounded),
      ('Contato', Icons.phone_rounded),
      ('Endereço', Icons.home_rounded),
      ('Documento', Icons.badge_rounded),
      ('Revisão', Icons.check_circle_rounded),
    ];

    final atual = etapas[_currentStep];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 380;

        return Container(
          margin: EdgeInsets.fromLTRB(compact ? 10 : 14, compact ? 8 : 12, compact ? 10 : 14, 0),
          padding: EdgeInsets.all(compact ? 10 : 12),
          decoration: BoxDecoration(
            gradient: t.primaryGradient,
            borderRadius: BorderRadius.circular(compact ? 18 : 22),
            boxShadow: t.softShadow,
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 38 : 44,
                height: compact ? 38 : 44,
                decoration: BoxDecoration(
                  color: onPrimary.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(compact ? 14 : 16),
                  border: Border.all(color: onPrimary.withOpacity(0.16)),
                ),
                child: Icon(atual.$2, color: onPrimary, size: compact ? 21 : 24),
              ),
              SizedBox(width: compact ? 9 : 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      atual.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: onPrimary, fontWeight: FontWeight.w900, fontSize: compact ? 14 : 15.5, height: 1.05),
                    ),
                    SizedBox(height: compact ? 1 : 2),
                    Row(
                      children: [
                        Text(
                          'Etapa ${_currentStep + 1}/7',
                          style: TextStyle(color: onPrimary.withOpacity(0.78), fontSize: compact ? 10.5 : 11.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              minHeight: compact ? 5 : 6,
                              value: (_currentStep + 1) / 7,
                              backgroundColor: onPrimary.withOpacity(0.18),
                              valueColor: AlwaysStoppedAnimation<Color>(onPrimary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStepWelcome() {
    final t = context.uai;
    final info = _ensureVisible(_temVagas ? t.info : t.error, t.background);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: Column(
        children: [
          _heroMini(
            icon: _temVagas ? Icons.waving_hand_rounded : Icons.warning_rounded,
            title: _temVagas ? 'Olá! Vamos começar?' : 'Que pena!',
            subtitle: _temVagas
                ? 'Precisamos de algumas informações para oferecer a melhor experiência.'
                : 'No momento todas as vagas estão preenchidas.',
            color: info,
          ),
          const SizedBox(height: 14),
          _buildRegimentoCard(),
          const SizedBox(height: 14),
          if (_configuracoesCarregadas)
            _statusBox(
              icon: _temVagas ? Icons.info_rounded : Icons.error_rounded,
              color: _temVagas ? t.info : t.error,
              title: _temVagas ? 'Aceitamos alunos de $_idadeMinima a $_idadeMaxima anos' : 'Vagas esgotadas',
              subtitle: _temVagas ? '$_vagasRestantes vagas disponíveis' : 'No momento não temos vagas disponíveis.',
            ),
        ],
      ),
    );
  }

  Widget _buildRegimentoCard() {
    final t = context.uai;
    final accent = _ensureVisible(t.warning, t.card);

    return Material(
      color: Color.alphaBlend(accent.withOpacity(0.07), t.card),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _rastrearAcaoInscricao('abriu_regimento_interno', origem: 'boas_vindas');
          showDialog<void>(context: context, builder: (context) => const RegimentoDialog());
        },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withOpacity(0.16)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _iconBox(Icons.menu_book_rounded, accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _titleSubtitle(
                      title: 'REGIMENTO INTERNO',
                      subtitle: 'Leia as regras e diretrizes do grupo',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.arrow_forward_rounded, color: accent),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: t.cardAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 15, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Leia atentamente antes de prosseguir',
                        style: TextStyle(fontSize: 11.2, color: accent, fontWeight: FontWeight.w800),
                      ),
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

  Widget _buildStepFoto() {
    final t = context.uai;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heroMini(
            icon: Icons.camera_alt_rounded,
            title: 'Foto do aluno',
            subtitle: 'Essa foto ajuda o professor a identificar o aluno na chamada. Tire uma foto de frente, bem iluminada e com o rosto visível.',
            color: t.primary,
          ),
          const SizedBox(height: 14),
          _buildFotoAlunoCard(tamanhoGrande: true),
          const SizedBox(height: 14),
          if (_processandoFotoLocal) ...[
            _statusBox(
              icon: Icons.hourglass_top_rounded,
              color: t.warning,
              title: 'Processando foto',
              subtitle: _statusFotoLocal.isNotEmpty ? _statusFotoLocal : 'Processando foto do aluno...',
              loading: true,
            ),
            const SizedBox(height: 14),
          ],
          _statusBox(
            icon: Icons.center_focus_strong_rounded,
            color: t.success,
            title: 'Dica para a foto',
            subtitle: 'Tire uma foto de frente, com rosto visível e boa iluminação.',
          ),
        ],
      ),
    );
  }

  Widget _buildStepAluno() {
    final t = context.uai;
    final idade = _controllers['data_nascimento']!.text.isNotEmpty ? _calcularIdade(_controllers['data_nascimento']!.text) : 0;
    final idadeValida = idade >= _idadeMinima && idade <= _idadeMaxima;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(icon: Icons.person_rounded, title: 'Dados do aluno', subtitle: 'Quem vai praticar capoeira?', color: t.primary),
          const SizedBox(height: 14),
          _buildTextField(
            _controllers['nome']!,
            'Nome completo *',
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return 'Campo obrigatório';
              if (!_validarNomePessoa(v)) return 'Use apenas letras';
              return null;
            },
            personNameOnly: true,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            _controllers['apelido']!,
            'Apelido *',
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return 'Campo obrigatório';
              if (!_validarNomePessoa(v)) return 'Use apenas letras';
              return null;
            },
            personNameOnly: true,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;
              final dateField = _buildDateField(_controllers['data_nascimento']!, 'Data de nascimento *');
              final sexoField = _buildSexoField();

              if (narrow) {
                return Column(children: [dateField, const SizedBox(height: 12), sexoField]);
              }

              return Row(children: [Expanded(child: dateField), const SizedBox(width: 12), Expanded(child: sexoField)]);
            },
          ),
          if (_controllers['data_nascimento']!.text.isNotEmpty && !idadeValida) ...[
            const SizedBox(height: 10),
            _statusBox(
              icon: Icons.warning_amber_rounded,
              color: t.error,
              title: 'Idade não permitida',
              subtitle: 'Aceitamos alunos de $_idadeMinima a $_idadeMaxima anos.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepContato() {
    final t = context.uai;
    final isMaior = _isMaiorIdade();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.phone_rounded,
            title: 'Contato',
            subtitle: isMaior ? 'Como vamos falar com você?' : 'Como vamos falar com vocês?',
            color: t.info,
          ),
          const SizedBox(height: 14),
          _buildPhoneField(_controllers['contato_aluno']!, 'Telefone do aluno *'),
          const SizedBox(height: 12),
          if (!isMaior) ...[
            _buildTextField(
              _controllers['nome_responsavel']!,
              'Nome do responsável *',
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return 'Campo obrigatório';
                if (!_validarNomePessoa(v)) return 'Use apenas letras';
                return null;
              },
              personNameOnly: true,
            ),
            const SizedBox(height: 12),
            _buildPhoneField(_controllers['contato_responsavel']!, 'Telefone do responsável *'),
          ],
        ],
      ),
    );
  }

  Widget _buildStepEndereco() {
    final t = context.uai;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(icon: Icons.home_rounded, title: 'Endereço', subtitle: 'Onde vocês moram?', color: t.success),
          const SizedBox(height: 14),
          _buildTextField(
            _controllers['rua']!,
            'Rua *',
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return 'Campo obrigatório';
              if (!_validarEnderecoTexto(v)) return 'Texto inválido';
              return null;
            },
            addressText: true,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;

              final numero = _buildTextField(
                _controllers['numero']!,
                'Número *',
                isNumberOnly: true,
                maxLength: 5,
                validator: (value) {
                  final v = value?.trim() ?? '';
                  if (v.isEmpty) return 'Campo obrigatório';
                  if (v.length > 5) return 'Máximo 5 dígitos';
                  return null;
                },
              );

              final bairro = _buildTextField(
                _controllers['bairro']!,
                'Bairro *',
                validator: (value) {
                  final v = value?.trim() ?? '';
                  if (v.isEmpty) return 'Campo obrigatório';
                  if (!_validarEnderecoTexto(v)) return 'Texto inválido';
                  return null;
                },
                addressText: true,
              );

              if (narrow) {
                return Column(children: [numero, const SizedBox(height: 12), bairro]);
              }

              return Row(children: [Expanded(flex: 2, child: numero), const SizedBox(width: 12), Expanded(flex: 3, child: bairro)]);
            },
          ),
          const SizedBox(height: 12),
          _buildTextField(
            _controllers['cidade']!,
            'Cidade *',
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return 'Campo obrigatório';
              if (!_validarEnderecoTexto(v)) return 'Texto inválido';
              return null;
            },
            addressText: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStepCpf() {
    final t = context.uai;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(icon: Icons.badge_rounded, title: 'Documento', subtitle: 'CPF opcional', color: t.associacao),
          const SizedBox(height: 14),
          _statusBox(
            icon: Icons.info_outline_rounded,
            color: t.info,
            title: 'Documento opcional',
            subtitle: 'O CPF ajuda no cadastro futuro, mas não bloqueia o avanço.',
          ),
          const SizedBox(height: 14),
          _buildCpfField(),
        ],
      ),
    );
  }

  Widget _buildStepRevisao() {
    final t = context.uai;

    final isMaior = _isMaiorIdade();
    final nomeResponsavel = isMaior ? _controllers['nome']!.text : _controllers['nome_responsavel']!.text;
    final nomeAluno = _controllers['nome']!.text;
    final idadeAluno = _calcularIdade(_controllers['data_nascimento']!.text);
    final precisaAssinar = _recolherAssinatura && _assinaturaUrl == null && _assinaturaBytes == null;
    final temFoto = _temFoto();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(icon: Icons.check_circle_rounded, title: 'Revisão e autorização', subtitle: 'Confira os dados antes de enviar.', color: t.success),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _cardDecoration(),
            child: Column(
              children: [
                _buildResumoLinhaIcon(Icons.person_rounded, 'Aluno', nomeAluno, t.info),
                _divider(),
                _buildResumoLinhaIcon(Icons.cake_rounded, 'Idade', '$idadeAluno anos', t.warning),
                _divider(),
                _buildResumoLinhaIcon(Icons.phone_rounded, 'Contato', _controllers['contato_aluno']!.text, t.success),
                _divider(),
                _buildResumoLinhaIcon(
                  Icons.photo_camera_rounded,
                  'Foto',
                  temFoto ? '✅ Foto do aluno cadastrada' : '❌ Foto não cadastrada',
                  temFoto ? t.associacao : t.error,
                ),
                if (!isMaior) ...[
                  _divider(),
                  _buildResumoLinhaIcon(Icons.person_outline_rounded, 'Responsável', nomeResponsavel, t.associacao),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildTermoElaborado(),
          const SizedBox(height: 14),
          _buildAutorizacaoCard(),
          if (_recolherAssinatura) ...[
            const SizedBox(height: 14),
            _buildAssinaturaCard(precisaAssinar),
          ],
        ],
      ),
    );
  }

  Widget _buildAutorizacaoCard() {
    final t = context.uai;
    final success = _ensureVisible(t.success, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          setState(() => _autorizacao = !_autorizacao);
          _validarEtapaFinal();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _autorizacao ? success : t.border, width: _autorizacao ? 1.5 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _autorizacao,
                activeColor: success,
                onChanged: (value) {
                  setState(() => _autorizacao = value ?? false);
                  _validarEtapaFinal();
                },
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Declaro que li e aceito o termo de responsabilidade e autorizo a participação na aula experimental.',
                  style: TextStyle(color: t.textPrimary, fontSize: 13.2, height: 1.35, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssinaturaCard(bool precisaAssinar) {
    final t = context.uai;
    final success = _ensureVisible(t.success, t.card);
    final warning = _ensureVisible(t.warning, t.card);
    final assinada = _assinaturaBytes != null || _assinaturaUrl != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(borderColor: assinada ? success.withOpacity(0.20) : warning.withOpacity(0.20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _iconBox(assinada ? Icons.check_circle_rounded : Icons.draw_rounded, assinada ? success : warning),
              const SizedBox(width: 10),
              Expanded(
                child: _titleSubtitle(
                  title: assinada ? 'Assinatura registrada' : 'Assinatura obrigatória',
                  subtitle: assinada ? 'A assinatura digital foi recebida.' : 'Assine o termo digitalmente para enviar.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _abrirTelaAssinatura,
            icon: Icon(assinada ? Icons.edit_rounded : Icons.draw_rounded),
            label: Text(assinada ? 'REFAZER ASSINATURA' : 'ASSINAR AGORA'),
            style: ElevatedButton.styleFrom(
              backgroundColor: assinada ? success : t.primary,
              foregroundColor: _readableOn(assinada ? success : t.primary),
              padding: const EdgeInsets.symmetric(vertical: 13),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.buttonRadius)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermoElaborado() {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.description_rounded,
            title: 'Termo de responsabilidade',
            subtitle: 'Texto gerado automaticamente com os dados preenchidos.',
            color: t.primary,
            dense: true,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 260),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: t.cardAlt,
              borderRadius: BorderRadius.circular(t.inputRadius),
              border: Border.all(color: t.border),
            ),
            child: SingleChildScrollView(
              child: Text(
                _gerarTermoTexto(),
                style: TextStyle(color: t.textPrimary, height: 1.45, fontSize: 12.3, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFotoAlunoCard({bool tamanhoGrande = false}) {
    final t = context.uai;
    final temFoto = _temFoto();

    final double cardW = tamanhoGrande ? 154 : 112;
    final double cardH = cardW / 0.76;
    final double imageH = cardH - (tamanhoGrande ? 42 : 36);

    final accent = temFoto ? _ensureVisible(t.success, t.card) : _ensureVisible(t.primary, t.card);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: GestureDetector(
            onTap: (_uploadingFoto || _processandoFotoLocal) ? null : _selecionarFoto,
            onLongPress: temFoto ? _removerFoto : null,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: cardW,
                  height: cardH,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: t.cardAlt,
                    border: Border.all(color: accent, width: temFoto ? 3 : 2),
                    boxShadow: t.softShadow,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Column(
                      children: [
                        SizedBox(
                          width: cardW,
                          height: imageH,
                          child: _fotoUrl != null
                              ? Image.network(_fotoUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _buildFotoPlaceholder())
                              : _fotoBytes != null
                              ? Image.memory(_fotoBytes!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _buildFotoPlaceholder())
                              : _buildFotoPlaceholder(),
                        ),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            color: Color.alphaBlend(accent.withOpacity(0.08), t.card),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              temFoto ? 'Foto pronta' : 'Tirar foto',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: accent, fontSize: tamanhoGrande ? 10.8 : 10.0, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_uploadingFoto || _processandoFotoLocal)
                  Container(
                    width: cardW,
                    height: cardH,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), color: Colors.black.withOpacity(0.62)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.6),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _statusFotoLocal.isNotEmpty ? _statusFotoLocal : 'Processando foto...',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.2, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle, border: Border.all(color: t.card, width: 2)),
                    child: Icon(temFoto ? Icons.edit_rounded : Icons.camera_alt_rounded, color: _readableOn(accent), size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Column(
            children: [
              Text(
                _processandoFotoLocal
                    ? (_statusFotoLocal.isNotEmpty ? _statusFotoLocal : 'Processando foto...')
                    : temFoto
                    ? '✅ Foto pronta! Toque para tirar outra • Segure para remover'
                    : '⚠️ Foto obrigatória • Toque para abrir a câmera',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: _processandoFotoLocal ? _ensureVisible(t.warning, t.background) : accent,
                  fontWeight: _processandoFotoLocal || !temFoto ? FontWeight.bold : FontWeight.w600,
                ),
              ),
              if (!temFoto)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Tire uma foto de frente, com o rosto bem visível',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: t.textSecondary),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFotoPlaceholder() {
    final t = context.uai;

    return Container(
      color: t.cardAlt,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt_rounded, size: 40, color: t.textMuted),
          const SizedBox(height: 4),
          Text('Tirar\nfoto', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: t.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons() {
    final t = context.uai;
    final isLast = _currentStep == 6;

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 380;
          final continuarLabel = isLast ? (compact ? 'ENVIAR' : 'ENVIAR INSCRIÇÃO') : (compact ? 'PRÓXIMO' : 'CONTINUAR');

          final voltarButton = OutlinedButton.icon(
            onPressed: _currentStep == 0 ? null : _etapaAnterior,
            icon: Icon(Icons.arrow_back_rounded, size: compact ? 17 : 18),
            label: FittedBox(fit: BoxFit.scaleDown, child: Text(compact ? 'VOLTAR' : 'VOLTAR')),
            style: OutlinedButton.styleFrom(
              foregroundColor: t.textPrimary,
              side: BorderSide(color: t.border),
              padding: EdgeInsets.symmetric(vertical: compact ? 11 : 13),
              textStyle: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 11.5 : 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 13 : t.buttonRadius)),
            ),
          );

          final nextButton = ElevatedButton.icon(
            onPressed: isLast ? _enviarInscricao : _proximaEtapa,
            icon: Icon(isLast ? Icons.send_rounded : Icons.arrow_forward_rounded, size: compact ? 17 : 19),
            label: FittedBox(fit: BoxFit.scaleDown, child: Text(continuarLabel)),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: _readableOn(t.primary),
              padding: EdgeInsets.symmetric(vertical: compact ? 12 : 14),
              textStyle: TextStyle(fontSize: compact ? 11.5 : 13.5, fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 13 : t.buttonRadius)),
            ),
          );

          return Container(
            padding: EdgeInsets.fromLTRB(compact ? 10 : 14, compact ? 7 : 9, compact ? 10 : 14, compact ? 10 : 14),
            decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.border)), boxShadow: t.softShadow),
            child: Row(children: [Expanded(child: voltarButton), const SizedBox(width: 10), Expanded(flex: 2, child: nextButton)]),
          );
        },
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller,
      String label, {
        String? Function(String?)? validator,
        bool isNumberOnly = false,
        bool personNameOnly = false,
        bool addressText = false,
        int? maxLength,
      }) {
    final inputFormatters = <TextInputFormatter>[];

    if (isNumberOnly) {
      inputFormatters.add(FilteringTextInputFormatter.digitsOnly);
    } else if (personNameOnly) {
      inputFormatters.add(FilteringTextInputFormatter.allow(RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ\s]')));
    } else if (addressText) {
      inputFormatters.add(FilteringTextInputFormatter.allow(RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ0-9\s\.,\-ºª/]')));
    }

    if (maxLength != null) inputFormatters.add(LengthLimitingTextInputFormatter(maxLength));

    return TextFormField(
      controller: controller,
      style: TextStyle(color: context.uai.textPrimary),
      inputFormatters: inputFormatters,
      textCapitalization: TextCapitalization.characters,
      decoration: _modernInputDecoration(label: label, icon: Icons.edit_rounded, errorText: validator?.call(controller.text)),
      onChanged: (_) {
        _validarEtapa1();
        _validarEtapa2();
        _validarEtapa3();
      },
    );
  }

  Widget _buildPhoneField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      style: TextStyle(color: context.uai.textPrimary),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11), _PhoneInputFormatter()],
      decoration: _modernInputDecoration(
        label: label,
        icon: Icons.phone_rounded,
        errorText: controller.text.isEmpty ? 'Campo obrigatório' : !_telefoneCompleto(controller.text) ? 'Telefone incompleto' : null,
      ),
      onChanged: (_) => _validarEtapa2(),
    );
  }

  Widget _buildCpfField() {
    final controller = _controllers['cpf']!;

    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: TextStyle(color: context.uai.textPrimary),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11), _CpfInputFormatter()],
      decoration: _modernInputDecoration(label: 'CPF opcional', icon: Icons.badge_rounded),
    );
  }

  Widget _buildDateField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      style: TextStyle(color: context.uai.textPrimary),
      decoration: _modernInputDecoration(
        label: label,
        icon: Icons.cake_rounded,
        errorText: controller.text.isEmpty ? 'Campo obrigatório' : null,
      ).copyWith(
        suffixIcon: Icon(Icons.calendar_month_rounded, color: _ensureVisible(context.uai.primary, context.uai.card)),
      ),
      onTap: () => _selectDate(controller),
    );
  }

  Widget _buildSexoField() {
    final t = context.uai;

    return DropdownButtonFormField<String>(
      value: _sexo,
      isExpanded: true,
      dropdownColor: t.surface,
      style: TextStyle(color: t.textPrimary),
      decoration: _modernInputDecoration(label: 'Sexo *', icon: Icons.wc_rounded, errorText: _sexo == null ? 'Campo obrigatório' : null),
      items: const [
        DropdownMenuItem(value: 'MASCULINO', child: Text('MASCULINO')),
        DropdownMenuItem(value: 'FEMININO', child: Text('FEMININO')),
      ],
      onChanged: (v) {
        setState(() => _sexo = v);
        _rastrearAcaoInscricao('selecionou_sexo', origem: 'dados_aluno', metadata: {'sexo': v});
        _validarEtapa1();
      },
    );
  }

  Future<void> _selectDate(TextEditingController controller) async {
    final t = context.uai;

    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 3650)),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: t.primary, surface: t.surface, onSurface: t.textPrimary),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (picked != null) {
      setState(() => controller.text = DateFormat('dd/MM/yyyy').format(picked));
      _validarEtapa1();
    }
  }

  InputDecoration _modernInputDecoration({
    required String label,
    required IconData icon,
    String? errorText,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: t.textSecondary),
      prefixIcon: Icon(icon, color: primary),
      filled: true,
      fillColor: t.card,
      errorText: errorText,
      errorMaxLines: 2,
      counterText: '',
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(t.inputRadius)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(t.inputRadius), borderSide: BorderSide(color: t.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(t.inputRadius), borderSide: BorderSide(color: primary, width: 1.4)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(t.inputRadius), borderSide: BorderSide(color: t.error, width: 1.2)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(t.inputRadius), borderSide: BorderSide(color: t.error, width: 1.4)),
    );
  }

  Widget _heroMini({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: t.primaryGradient, borderRadius: BorderRadius.circular(24), boxShadow: t.softShadow),
      child: Column(
        children: [
          Icon(icon, color: onPrimary, size: 34),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(color: onPrimary, fontSize: 22, fontWeight: FontWeight.w900, height: 1.1),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: onPrimary.withOpacity(0.82), fontSize: 13, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    bool dense = false,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.background);

    return Row(
      children: [
        _iconBox(icon, accent, compact: dense),
        const SizedBox(width: 10),
        Expanded(child: _titleSubtitle(title: title, subtitle: subtitle, titleSize: dense ? 14.5 : 17)),
      ],
    );
  }

  Widget _titleSubtitle({
    required String title,
    required String subtitle,
    double titleSize = 14.5,
  }) {
    final t = context.uai;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: titleSize, height: 1.12),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: t.textSecondary, fontSize: 11.8, height: 1.25, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _statusBox({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    bool loading = false,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.card),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          if (loading)
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.3, color: accent))
          else
            Icon(icon, color: accent),
          const SizedBox(width: 10),
          Expanded(child: _titleSubtitle(title: title, subtitle: subtitle, titleSize: 13.5)),
        ],
      ),
    );
  }

  Widget _buildResumoLinhaIcon(IconData icon, String label, String valor, Color cor) {
    final t = context.uai;
    final accent = _ensureVisible(cor, t.card);

    return Row(
      children: [
        _iconBox(icon, accent, compact: true),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: t.textSecondary)),
              Text(valor, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: t.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _divider() => Divider(height: 18, color: context.uai.border);

  Widget _iconBox(IconData icon, Color color, {bool compact = false}) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      width: compact ? 36 : 42,
      height: compact ? 36 : 42,
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
        borderRadius: BorderRadius.circular(compact ? 13 : 15),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Icon(icon, color: accent, size: compact ? 19 : 22),
    );
  }

  Widget _roundIcon({
    required IconData icon,
    required Color color,
    double size = 34,
    bool large = false,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    return Container(
      width: large ? 78 : 64,
      height: large ? 78 : 64,
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
        borderRadius: BorderRadius.circular(large ? 26 : 22),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Icon(icon, color: accent, size: size),
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

class _PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    var formatted = digits;

    if (digits.length >= 2) {
      formatted = '(${digits.substring(0, 2)})';
      if (digits.length > 2) {
        formatted += ' ${digits.substring(2, digits.length > 7 ? 7 : digits.length)}';
      }
      if (digits.length > 7) {
        formatted += '-${digits.substring(7, digits.length > 11 ? 11 : digits.length)}';
      }
    }

    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

class _CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    var formatted = digits;

    if (digits.length > 3) {
      formatted = '${digits.substring(0, 3)}.${digits.substring(3)}';
    }
    if (digits.length > 6) {
      formatted = '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6)}';
    }
    if (digits.length > 9) {
      formatted = '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9, digits.length > 11 ? 11 : digits.length)}';
    }

    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

class _GuiaRostoInscricaoPainter extends CustomPainter {
  final Color lineColor;
  final Color borderColor;

  const _GuiaRostoInscricaoPainter({
    required this.lineColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final soft = Paint()
      ..color = borderColor.withOpacity(0.55)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final faceRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: size.width * 0.56,
      height: size.height * 0.38,
    );

    canvas.drawOval(faceRect, line);

    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.24, size.height * 0.62, size.width * 0.52, size.height * 0.22),
      const Radius.circular(18),
    );

    canvas.drawRRect(bodyRect, soft);

    canvas.drawLine(Offset(size.width * 0.20, size.height * 0.50), Offset(size.width * 0.80, size.height * 0.50), soft);
    canvas.drawLine(Offset(size.width * 0.50, size.height * 0.16), Offset(size.width * 0.50, size.height * 0.86), soft);
  }

  @override
  bool shouldRepaint(covariant _GuiaRostoInscricaoPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor || oldDelegate.borderColor != borderColor;
  }
}
