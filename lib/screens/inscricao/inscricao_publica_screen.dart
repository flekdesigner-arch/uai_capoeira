import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:uai_capoeira/screens/inscricao/signature_screen.dart';
import 'package:uai_capoeira/widgets/regimento_dialog.dart';
import 'package:uai_capoeira/screens/site/landing_page.dart';
import 'package:uai_capoeira/services/rastreio_site.dart';

class InscricaoPublicaScreen extends StatefulWidget {
  const InscricaoPublicaScreen({super.key});

  @override
  State<InscricaoPublicaScreen> createState() => _InscricaoPublicaScreenState();
}

class _InscricaoPublicaScreenState extends State<InscricaoPublicaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final RastreioSiteService _rastreioService = RastreioSiteService();
  final PageController _pageController = PageController();
  final Map<String, Timer> _debounceRastreioCampos = {};

  int _currentStep = 0;
  DateTime _inicioTelaInscricao = DateTime.now();
  DateTime _inicioEtapaAtual = DateTime.now();
  bool _rastreioInscricaoIniciado = false;
  bool _inscricaoFinalizadaComSucesso = false;

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
    0: false, // Boas-vindas
    1: false, // Foto
    2: false, // Dados do aluno
    3: false, // Contato
    4: false, // Endereço
    5: true,  // Documento opcional
    6: false, // Revisão
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

  bool _isMaiorIdade() {
    final dataNasc = _controllers['data_nascimento']!.text;
    if (dataNasc.isEmpty) return false;
    return _calcularIdade(dataNasc) >= 18;
  }

  bool _temFoto() => _fotoBytes != null || _fotoUrl != null;

  bool _telefoneCompleto(String value) => value.trim().length >= 15;

  bool _validarNomePessoa(String valor) {
    if (valor.trim().isEmpty) return false;
    final regex = RegExp(r'^[A-Za-zÀ-ÖØ-öø-ÿ\s]+$');
    return regex.hasMatch(valor.trim());
  }

  bool _validarEnderecoTexto(String valor) {
    if (valor.trim().isEmpty) return false;
    final regex = RegExp(r'^[A-Za-zÀ-ÖØ-öø-ÿ0-9\s\.,\-ºª/]+$');
    return regex.hasMatch(valor.trim());
  }

  int _calcularIdade(String dataNascimento) {
    try {
      final data = DateFormat('dd/MM/yyyy').parse(dataNascimento);
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

  String _toUpperCase(String? text) {
    return text?.toUpperCase().trim() ?? '';
  }

  String _etapaAtualRastreio() {
    return _nomeEtapaRastreio(_currentStep);
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

    _debounceRastreioCampos[campo] = Timer(
      const Duration(milliseconds: 850),
          () {
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
      },
    );
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
      camposSensiveis: const [
        'cpf',
        'contato_aluno',
        'contato_responsavel',
      ],
      metadata: {
        'etapa_atual': _etapaAtualRastreio(),
        'etapa_numero': _currentStep + 1,
        ...?metadata,
      },
    );
  }


  void _showSuccessSnackbar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
  }


  static const List<String> _nomesEtapasRastreio = [
    'boas_vindas',
    'foto_aluno',
    'dados_aluno',
    'contato',
    'endereco',
    'documento',
    'revisao',
  ];

  String _nomeEtapaRastreio(int etapa) {
    if (etapa < 0 || etapa >= _nomesEtapasRastreio.length) {
      return 'etapa_$etapa';
    }
    return _nomesEtapasRastreio[etapa];
  }

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

    unawaited(
      _rastreioService.registrarPaginaVista(
        'inscricao_publica',
        'landing_page',
      ),
    );

    unawaited(_registrarEntradaEtapa(0, origem: 'init'));
  }

  Future<void> _registrarEntradaEtapa(
      int etapa, {
        String origem = 'navegacao',
      }) async {
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
        metadata: {
          ..._metadataResumoInscricao(),
          ...?metadata,
        },
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
        metadata: {
          ..._metadataResumoInscricao(),
          ...?metadata,
        },
      ),
    );
  }

  void _registrarSaidaInscricaoSeNecessario({required String motivo}) {
    if (!_rastreioInscricaoIniciado || _inscricaoFinalizadaComSucesso) return;

    unawaited(
      _registrarSaidaEtapa(
        _currentStep,
        destino: motivo,
        origem: 'saida_inscricao',
      ),
    );

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

  void _showCustomErrorDialog({
    required String titulo,
    required List<String> erros,
  }) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFF5F5), Colors.white],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red.shade700,
                  size: 40,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: erros
                      .map(
                        (erro) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '• ',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              erro,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.red.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                      .toList(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'ENTENDI',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarFeedbackErros() {
    final erros = _errosPorEtapa[_currentStep] ?? [];
    final errosRastreio = erros.isEmpty
        ? ['Preencha os campos obrigatórios.']
        : erros;

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

    _showCustomErrorDialog(
      titulo: '⚠️ Campos pendentes',
      erros: erros,
    );
  }

  void _validarEtapa1() {
    if (!mounted) return;

    final erros = <String>[];

    final nome = _controllers['nome']!.text.trim();
    final apelido = _controllers['apelido']!.text.trim();
    final dataNascimento = _controllers['data_nascimento']!.text.trim();

    final nomeValido = _validarNomePessoa(nome);
    if (!nomeValido) {
      erros.add(nome.isEmpty
          ? 'Preencha o nome completo.'
          : 'O nome completo deve conter apenas letras.');
    }

    final apelidoValido = _validarNomePessoa(apelido);
    if (!apelidoValido) {
      erros.add(apelido.isEmpty
          ? 'Preencha o apelido.'
          : 'O apelido deve conter apenas letras.');
    }

    final dataValida = dataNascimento.isNotEmpty;
    if (!dataValida) {
      erros.add('Informe a data de nascimento.');
    }

    final sexoValido = _sexo != null;
    if (!sexoValido) {
      erros.add('Selecione o sexo.');
    }

    bool idadeValida = true;
    if (dataValida) {
      final idade = _calcularIdade(dataNascimento);
      idadeValida = idade >= _idadeMinima && idade <= _idadeMaxima;
      if (!idadeValida) {
        erros.add('A idade permitida é de $_idadeMinima a $_idadeMaxima anos.');
      }
    }

    setState(() {
      _etapaValida[2] = nomeValido &&
          apelidoValido &&
          dataValida &&
          sexoValido &&
          idadeValida;
      _errosPorEtapa[2] = erros;
    });
  }

  void _validarEtapaFoto() {
    if (!mounted) return;

    final erros = <String>[];

    final fotoValida = _temFoto();
    if (!fotoValida) {
      erros.add('Tire a foto do aluno para identificação.');
    }

    setState(() {
      _etapaValida[1] = fotoValida;
      _errosPorEtapa[1] = erros;
    });
  }

  void _validarEtapa2() {
    if (!mounted) return;

    final erros = <String>[];

    final contatoAlunoValido =
    _telefoneCompleto(_controllers['contato_aluno']!.text);
    if (!contatoAlunoValido) {
      erros.add('Informe o telefone completo do aluno.');
    }

    bool nomeRespValido = true;
    bool contatoRespValido = true;

    if (!_isMaiorIdade()) {
      final nomeResp = _controllers['nome_responsavel']!.text.trim();
      nomeRespValido = _validarNomePessoa(nomeResp);
      if (!nomeRespValido) {
        erros.add(nomeResp.isEmpty
            ? 'Preencha o nome do responsável.'
            : 'O nome do responsável deve conter apenas letras.');
      }

      contatoRespValido =
          _telefoneCompleto(_controllers['contato_responsavel']!.text);
      if (!contatoRespValido) {
        erros.add('Informe o telefone completo do responsável.');
      }
    }

    setState(() {
      _etapaValida[3] =
          contatoAlunoValido && nomeRespValido && contatoRespValido;
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
    if (!ruaValida) {
      erros.add(rua.isEmpty
          ? 'Preencha a rua.'
          : 'A rua contém caracteres inválidos.');
    }

    final numeroValido = numero.isNotEmpty && numero.length <= 5;
    if (!numeroValido) {
      erros.add(numero.isEmpty
          ? 'Preencha o número do endereço.'
          : 'O número deve ter no máximo 5 dígitos.');
    }

    final bairroValido = _validarEnderecoTexto(bairro);
    if (!bairroValido) {
      erros.add(bairro.isEmpty
          ? 'Preencha o bairro.'
          : 'O bairro contém caracteres inválidos.');
    }

    final cidadeValida = _validarEnderecoTexto(cidade);
    if (!cidadeValida) {
      erros.add(cidade.isEmpty
          ? 'Preencha a cidade.'
          : 'A cidade contém caracteres inválidos.');
    }

    setState(() {
      _etapaValida[4] =
          ruaValida && numeroValido && bairroValido && cidadeValida;
      _errosPorEtapa[4] = erros;
    });
  }

  void _validarEtapaFinal() {
    final erros = <String>[];

    if (!_autorizacao) {
      erros.add('Aceite os termos de responsabilidade.');
    }

    if (_recolherAssinatura && _assinaturaUrl == null && _assinaturaBytes == null) {
      erros.add('Assine o termo digitalmente.');
    }

    if (!_temFoto()) {
      erros.add('A foto do aluno é obrigatória.');
    }

    setState(() {
      _etapaValida[6] =
          _autorizacao &&
              (_recolherAssinatura
                  ? (_assinaturaUrl != null || _assinaturaBytes != null)
                  : true) &&
              _temFoto();
      _errosPorEtapa[6] = erros;
    });
  }

  Future<void> _verificarInscricoes() async {
    try {
      final doc =
      await _firestore.collection('configuracoes').doc('inscricoes').get();

      if (!doc.exists) {
        setState(() {
          _inscricoesAbertas = false;
          _configuracoesCarregadas = true;
          _etapaValida[0] = false;
          _carregando = false;
        });
        _rastrearAcaoInscricao(
          'configuracao_inscricao_nao_encontrada',
          origem: 'verificar_inscricoes',
        );
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
      setState(() {
        _inscricoesAbertas = false;
        _configuracoesCarregadas = true;
        _etapaValida[0] = false;
        _carregando = false;
        _mensagem = 'Erro ao verificar disponibilidade';
      });
    }
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
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 430),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(
                    Icons.center_focus_strong_rounded,
                    color: Colors.red.shade900,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Foto para identificação',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade900,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tire a foto do aluno de frente, com o rosto bem visível. Depois da câmera, ajuste a foto usando o retângulo e as linhas guia.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    height: 1.35,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: 180,
                  height: 230,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.green.shade500, width: 2),
                  ),
                  child: CustomPaint(
                    painter: _GuiaRostoInscricaoPainter(),
                    child: Center(
                      child: Icon(
                        Icons.face_rounded,
                        size: 74,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('CANCELAR'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        icon: const Icon(Icons.camera_alt_rounded),
                        label: const Text('ABRIR CÂMERA'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade900,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          textStyle: const TextStyle(fontWeight: FontWeight.w900),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    return result == true;
  }

  Future<void> _selecionarFoto() async {
    var loadingAberto = false;

    Future<void> abrirLoading({
      required String titulo,
      required String subtitulo,
      required IconData icon,
    }) async {
      if (!mounted) return;

      loadingAberto = true;

      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _ProcessandoFotoDialog(
            titulo: titulo,
            subtitulo: subtitulo,
            icon: icon,
          ),
        ),
      );

      // Garante pelo menos um frame para o usuário enxergar o feedback.
      await Future.delayed(const Duration(milliseconds: 120));
    }

    void fecharLoading() {
      if (!mounted || !loadingAberto) return;

      loadingAberto = false;

      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
    }

    try {
      _rastrearAcaoInscricao('foto_orientacao_aberta', origem: 'etapa_foto');

      final continuar = await _mostrarOrientacaoFotoAluno();
      if (!continuar) {
        _rastrearAcaoInscricao('foto_orientacao_cancelada', origem: 'etapa_foto');
        return;
      }

      _rastrearAcaoInscricao('foto_orientacao_confirmada', origem: 'etapa_foto');

      _setProcessandoFotoLocal('Preparando câmera...');

      await abrirLoading(
        titulo: 'Aguardando foto do aluno...',
        subtitulo: 'A câmera será aberta agora. Tire uma foto de frente e confirme.',
        icon: Icons.camera_alt_rounded,
      );

      await Future.delayed(const Duration(milliseconds: 280));

      fecharLoading();

      final picker = ImagePicker();

      _rastrearAcaoInscricao('camera_aberta', origem: 'etapa_foto');

      _rastreioService.registrarAcaoFormulario(
        formulario: 'inscricao_publica',
        acao: 'abrir_camera',
        etapa: _etapaAtualRastreio(),
      );

      final image = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 92,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (image == null) {
        _limparProcessandoFotoLocal();
        _rastrearAcaoInscricao('foto_camera_cancelada', origem: 'camera');
        return;
      }

      _rastrearAcaoInscricao('foto_capturada', origem: 'camera');

      _setProcessandoFotoLocal('Foto recebida. Processando...');

      await abrirLoading(
        titulo: 'Analisando foto do aluno...',
        subtitulo: 'A foto foi recebida. Estamos preparando o ajuste para identificação.',
        icon: Icons.center_focus_strong_rounded,
      );

      // Dá tempo para a interface atualizar antes da leitura/processamento.
      await Future.delayed(const Duration(milliseconds: 160));

      final originalBytes = await image.readAsBytes();

      _rastreioService.registrarAcaoFormulario(
        formulario: 'inscricao_publica',
        acao: 'foto_capturada',
        etapa: _etapaAtualRastreio(),
        metadata: {
          'bytes': originalBytes.length,
        },
      );

      _setProcessandoFotoLocal('Abrindo editor de ajuste...');

      // Tempo mínimo visual para evitar sensação de tela vazia/travada.
      await Future.delayed(const Duration(milliseconds: 520));

      fecharLoading();

      if (!mounted) {
        _limparProcessandoFotoLocal();
        return;
      }

      _rastrearAcaoInscricao('editor_foto_aberto', origem: 'camera');

      final bytesEditados = await showDialog<Uint8List?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _EditorFotoInscricaoDialog(
          imageBytes: originalBytes,
          nomeAluno: _controllers['nome']!.text.trim(),
        ),
      );

      if (bytesEditados == null) {
        _limparProcessandoFotoLocal();
        _rastrearAcaoInscricao('editor_foto_cancelado', origem: 'editor_foto');
        return;
      }

      _rastrearAcaoInscricao('foto_ajustada', origem: 'editor_foto');

      setState(() {
        _fotoBytes = bytesEditados;
        _fotoNome = 'foto_aluno_${DateTime.now().millisecondsSinceEpoch}.jpg';
        _fotoUrl = null;
        _uploadingFoto = false;
        _processandoFotoLocal = false;
        _statusFotoLocal = '';
      });

      _rastreioService.registrarAcaoFormulario(
        formulario: 'inscricao_publica',
        acao: 'foto_ajustada',
        etapa: _etapaAtualRastreio(),
        metadata: {
          'bytes_editados': bytesEditados.length,
        },
      );

      _validarEtapaFoto();
      _showSuccessSnackbar('📸 Foto ajustada! Ela será enviada ao finalizar a inscrição.');
    } catch (e) {
      _rastrearErroInscricao(
        'foto_aluno',
        ['Erro ao tirar/processar foto: $e'],
        origem: 'foto',
      );
      fecharLoading();
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
      final nomeAluno = _controllers['nome']!.text.trim().replaceAll(RegExp(r'\s+'), '_');
      final fileName = '${timestamp}_${nomeAluno.isEmpty ? 'aluno' : nomeAluno}.jpg';

      final fotoRef = _storage.ref().child('fotos_inscricoes/$fileName');

      await fotoRef.putData(
        _fotoBytes!,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'origem': 'camera_inscricao_publica',
            'crop': 'rosto_centralizado',
          },
        ),
      );

      final downloadUrl = await fotoRef.getDownloadURL();

      _rastrearAcaoInscricao('upload_foto_concluido', origem: 'envio_final');

      _rastreioService.registrarAcaoFormulario(
        formulario: 'inscricao_publica',
        acao: 'upload_foto_sucesso',
        etapa: _etapaAtualRastreio(),
      );

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
      _rastrearErroInscricao(
        'upload_foto',
        ['Erro ao fazer upload da foto: $e'],
        origem: 'firebase_storage',
      );
      _rastreioService.registrarErroFormulario(
        formulario: 'inscricao_publica',
        etapa: _etapaAtualRastreio(),
        erro: 'Erro ao fazer upload da foto: $e',
      );
      _showErrorSnackbar('Erro ao fazer upload da foto: $e');
      rethrow;
    }
  }

  void _removerFoto() {
    _rastrearAcaoInscricao('remover_foto_dialog_aberto', origem: 'foto_aluno');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover foto'),
        content: const Text('Tem certeza que deseja remover esta foto?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('REMOVER'),
          ),
        ],
      ),
    );
  }

  String _gerarTermoTexto() {
    final isMaior = _isMaiorIdade();
    final nomeAluno = _controllers['nome']!.text;
    final nomeResp =
    isMaior ? nomeAluno : _controllers['nome_responsavel']!.text;
    final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    if (isMaior) {
      return '''
TERMO DE RESPONSABILIDADE

Eu, $nomeAluno, declaro para os devidos fins que:

1. ESTOU CIENTE de que a Capoeira é uma arte marcial que envolve atividades físicas de médio a alto impacto, podendo resultar em lesões.

2. ASSUMO total responsabilidade por qualquer dano físico que possa ocorrer durante a prática, isentando o Grupo UAI CAPOEIRA de qualquer ônus.

3. COMPROMETO-ME a informar previamente qualquer condição de saúde ou limitação física.

4. AUTORIZO a participação na aula experimental de Capoeira.

5. CONCORDO com as filmagens e fotografias para fins institucionais.

Data e hora: $dataHora

Assinatura: ${(_assinaturaUrl != null || _assinaturaBytes != null) ? '[ASSINATURA DIGITAL]' : '_____________________________'}
''';
    }

    return '''
TERMO DE RESPONSABILIDADE

Eu, $nomeResp, responsável legal por $nomeAluno, declaro para os devidos fins que:

1. AUTORIZO a participação do(a) menor acima identificado(a) na aula experimental de Capoeira oferecida pelo Grupo UAI CAPOEIRA.

2. ESTOU CIENTE dos riscos da prática esportiva e assumo total responsabilidade.

3. COMPROMETO-ME a informar previamente qualquer condição de saúde ou limitação física do aluno.

4. CONCORDO com as filmagens e fotografias para fins institucionais.

Data e hora: $dataHora

Assinatura do Responsável: ${(_assinaturaUrl != null || _assinaturaBytes != null) ? '[ASSINATURA DIGITAL]' : '_____________________________'}
''';
  }

  Future<void> _abrirTelaAssinatura() async {
    _rastrearAcaoInscricao('assinatura_abriu', origem: 'revisao');

    final isMaior = _isMaiorIdade();
    final nomeResponsavel =
    isMaior ? _controllers['nome']!.text : _controllers['nome_responsavel']!.text;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SignatureScreen(
          inscricaoId: 'temp_${DateTime.now().millisecondsSinceEpoch}',
          nomeResponsavel: nomeResponsavel,
          nomeAluno: _controllers['nome']!.text,
          onConfirm: (imageBytes) {
            _rastreioService.registrarAcaoFormulario(
              formulario: 'inscricao_publica',
              acao: 'assinatura_confirmada',
              etapa: _etapaAtualRastreio(),
              metadata: {
                'bytes': imageBytes.length,
              },
            );

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

            _rastrearAcaoInscricao('assinatura_registrada', origem: 'signature_screen');
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
          customMetadata: {
            'origem': 'assinatura_inscricao_publica',
            'modo': 'upload_no_envio_final',
          },
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
      _rastrearErroInscricao(
        'upload_assinatura',
        ['Erro ao enviar assinatura: $e'],
        origem: 'firebase_storage',
      );
      _showErrorSnackbar('Erro ao enviar assinatura: $e');
      rethrow;
    }
  }

  Future<void> _enviarInscricao() async {
    _rastrearAcaoInscricao('tentou_enviar_inscricao', origem: 'revisao');

    _validarEtapaFinal();

    if (!(_etapaValida[6] ?? false)) {
      _rastrearErroInscricao(
        'revisao_envio',
        _errosPorEtapa[6] ?? ['Revisão inválida'],
        origem: 'tentativa_envio',
      );
      _mostrarFeedbackErros();
      return;
    }

    setState(() => _enviando = true);

    try {
      final configDoc =
      await _firestore.collection('configuracoes').doc('inscricoes').get();
      final config = configDoc.data() ?? {};
      final vagasDisponiveis = config['vagas_disponiveis'] ?? 0;

      final inscricoesSnapshot = await _firestore
          .collection('inscricoes')
          .where('status', isEqualTo: 'pendente')
          .get();

      if (vagasDisponiveis > 0 &&
          inscricoesSnapshot.docs.length >= vagasDisponiveis) {
        setState(() {
          _mensagem = 'Desculpe, as vagas para inscrições estão esgotadas.';
          _enviando = false;
        });
        _rastrearErroInscricao(
          'envio_inscricao',
          ['Vagas esgotadas no momento do envio.'],
          origem: 'vagas',
          metadata: {'vagas_disponiveis': vagasDisponiveis},
        );
        _showErrorSnackbar('❌ Vagas esgotadas!');
        return;
      }

      final isMaior = _isMaiorIdade();

      final dados = <String, dynamic>{
        'nome': _toUpperCase(_controllers['nome']!.text),
        'apelido': _toUpperCase(_controllers['apelido']!.text),
        'data_nascimento': _controllers['data_nascimento']!.text.trim(),
        'sexo': _sexo,
        'contato_aluno':
        _controllers['contato_aluno']!.text.replaceAll(RegExp(r'[^0-9]'), ''),
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
          ((_assinaturaUrl == null || _assinaturaUrl?.isEmpty == true) &&
              _assinaturaBytes != null)) {
        await _uploadAssinaturaFirebase();
      }

      if (_recolherAssinatura &&
          (_assinaturaUrl == null || _assinaturaUrl?.isEmpty == true) &&
          _assinaturaBytes == null) {
        throw Exception('Assinatura é obrigatória');
      }

      if (_assinaturaUrl?.isNotEmpty == true) {
        dados['assinatura_url'] = _assinaturaUrl;
      }

      if (!isMaior) {
        dados['nome_responsavel'] =
            _toUpperCase(_controllers['nome_responsavel']!.text);
        dados['contato_responsavel'] = _controllers['contato_responsavel']!
            .text
            .replaceAll(RegExp(r'[^0-9]'), '');
      } else {
        dados['nome_responsavel'] = _toUpperCase(_controllers['nome']!.text);
        dados['contato_responsavel'] = _controllers['contato_aluno']!
            .text
            .replaceAll(RegExp(r'[^0-9]'), '');
      }

      if (_controllers['cpf']!.text.trim().isNotEmpty) {
        dados['cpf'] =
            _controllers['cpf']!.text.replaceAll(RegExp(r'[^0-9]'), '');
      }

      final enderecoParts = <String>[];

      if (_controllers['rua']!.text.isNotEmpty) {
        var ruaNumero = _toUpperCase(_controllers['rua']!.text);
        if (_controllers['numero']!.text.isNotEmpty) {
          ruaNumero += ' - ${_toUpperCase(_controllers['numero']!.text)}';
        }
        enderecoParts.add(ruaNumero);
      }

      if (_controllers['bairro']!.text.isNotEmpty) {
        enderecoParts.add(_toUpperCase(_controllers['bairro']!.text));
      }
      if (_controllers['cidade']!.text.isNotEmpty) {
        enderecoParts.add(_toUpperCase(_controllers['cidade']!.text));
      }

      dados['endereco'] = enderecoParts.join(', ');

      final inscricaoRef = await _firestore.collection('inscricoes').add(dados);

      final novoTotal = inscricoesSnapshot.docs.length + 1;
      await _firestore.collection('configuracoes').doc('inscricoes').set({
        'total_inscricoes': novoTotal,
      }, SetOptions(merge: true));

      _inscricaoFinalizadaComSucesso = true;

      unawaited(
        _registrarSaidaEtapa(
          _currentStep,
          destino: 'inscricao_enviada',
          origem: 'conversao',
        ),
      );

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

      unawaited(
        _rastreioService.finalizarTela(
          destino: 'inscricao_enviada',
          metadata: _metadataResumoInscricao(),
        ),
      );

      _rastreioService.registrarConversao(
        nome: 'inscricao_enviada',
        origem: 'inscricao_publica',
        valor: 1,
        metadata: {
          'is_maior_idade': isMaior,
          'idade_calculada': _calcularIdade(_controllers['data_nascimento']!.text),
          'tem_cpf': _controllers['cpf']!.text.trim().isNotEmpty,
          'tem_foto': _fotoUrl != null && _fotoUrl!.isNotEmpty,
          'tem_assinatura': _assinaturaUrl != null && _assinaturaUrl!.isNotEmpty,
        },
      );

      _registrarSnapshotInscricao(
        momento: 'envio_sucesso',
      );

      if (mounted) {
        _mostrarDialogSucesso(dados);
      }
    } catch (e) {
      _rastrearErroInscricao(
        'envio_inscricao',
        ['Erro ao enviar inscrição: $e'],
        origem: 'firestore_storage',
      );
      setState(() {
        _mensagem = 'Erro ao enviar inscrição: $e';
        _enviando = false;
      });
      _showErrorSnackbar('Erro ao enviar inscrição: $e');
    }
  }

  void _mostrarDialogSucesso(Map<String, dynamic> dados) {
    final isMaior = dados['is_maior_idade'] ?? false;
    final nomeResponsavel = _getPrimeiroNome(dados['nome_responsavel']);
    final nomeAluno = _getPrimeiroNome(dados['nome']);
    final idadeAluno = _calcularIdade(dados['data_nascimento']);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
            maxWidth: 520,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade700, Colors.green.shade500],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withOpacity(0.20)),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                        size: 54,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Inscrição enviada!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isMaior
                          ? 'Recebemos seus dados com sucesso.'
                          : 'Recebemos a inscrição de $nomeAluno com sucesso.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.86),
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
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
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.waving_hand_rounded, color: Colors.blue.shade800),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isMaior ? 'Olá, $nomeAluno!' : 'Olá, $nomeResponsavel!',
                                style: TextStyle(
                                  color: Colors.blue.shade900,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            _buildInfoDialog('Aluno', dados['nome']),
                            _buildInfoDialog('Idade', '$idadeAluno anos'),
                            _buildInfoDialog('Contato', dados['contato_aluno']),
                            if (!isMaior)
                              _buildInfoDialog('Responsável', dados['nome_responsavel']),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.amber.shade100),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.notifications_active_rounded, color: Colors.amber.shade800),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Agora é só aguardar o contato do professor para combinar os próximos detalhes da aula experimental.',
                                style: TextStyle(
                                  color: Colors.amber.shade900,
                                  fontSize: 12.5,
                                  height: 1.35,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_recolherAssinatura) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.green.shade100),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.draw_rounded, color: Colors.green.shade700),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  (_assinaturaUrl != null || _assinaturaBytes != null)
                                      ? 'Assinatura digital registrada.'
                                      : 'Termo de responsabilidade aceito.',
                                  style: TextStyle(
                                    color: Colors.green.shade900,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
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
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _rastrearAcaoInscricao('finalizou_dialog_sucesso', origem: 'sucesso');
                        Navigator.of(context).pop();
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LandingPage(),
                          ),
                              (route) => false,
                        );
                      },
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('FINALIZAR'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
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

  Widget _buildInfoDialog(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value ?? 'Não informado',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _proximaEtapa() {
    if (_currentStep >= 6) return;

    _rastrearAcaoInscricao(
      'clicou_avancar_etapa',
      origem: _nomeEtapaRastreio(_currentStep),
    );

    if (_currentStep == 1) _validarEtapaFoto();
    if (_currentStep == 2) _validarEtapa1();
    if (_currentStep == 3) _validarEtapa2();
    if (_currentStep == 4) _validarEtapa3();
    if (_currentStep == 5) {
      // CPF/documento é opcional. Esta etapa nunca deve bloquear o avanço.
      _etapaValida[5] = true;
      _errosPorEtapa[5] = [];
    }
    if (_currentStep == 6) _validarEtapaFinal();

    final isValido = _currentStep == 5 ? true : (_etapaValida[_currentStep] ?? false);

    if (!isValido) {
      _mostrarFeedbackErros();
      return;
    }

    final etapaAnterior = _currentStep;
    final proxima = _currentStep + 1;

    unawaited(
      _registrarSaidaEtapa(
        etapaAnterior,
        destino: _nomeEtapaRastreio(proxima),
        origem: 'avancar',
      ),
    );

    setState(() => _currentStep++);

    unawaited(_registrarEntradaEtapa(proxima, origem: 'avancar'));

    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _etapaAnterior() {
    if (_currentStep <= 0) return;

    _rastrearAcaoInscricao(
      'clicou_voltar_etapa',
      origem: _nomeEtapaRastreio(_currentStep),
    );

    final etapaAnterior = _currentStep;
    final destino = _currentStep - 1;

    unawaited(
      _registrarSaidaEtapa(
        etapaAnterior,
        destino: _nomeEtapaRastreio(destino),
        origem: 'voltar',
      ),
    );

    setState(() => _currentStep--);

    unawaited(_registrarEntradaEtapa(destino, origem: 'voltar'));

    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<bool> _onWillPop() async {
    _rastrearAcaoInscricao(
      'pressionou_voltar_sistema',
      origem: _nomeEtapaRastreio(_currentStep),
    );

    if (_currentStep == 0) {
      final shouldExit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.exit_to_app,
                  color: Colors.orange.shade700,
                  size: 32,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Sair da inscrição?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            'Se você sair agora, os dados preenchidos serão perdidos.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'CONTINUAR',
                style: TextStyle(color: Colors.green),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('SAIR'),
            ),
          ],
        ),
      );

      if (shouldExit == true) {
        _registrarSaidaInscricaoSeNecessario(motivo: 'voltar_sistema_confirmado');
        Navigator.pop(context);
      } else {
        _rastrearAcaoInscricao('cancelou_saida_inscricao', origem: 'dialog_saida');
      }

      return false;
    }

    _etapaAnterior();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.red.shade900),
                const SizedBox(height: 14),
                Text(
                  'Verificando inscrições...',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_inscricoesAbertas) {
      _rastreioService.registrarPaginaVista('inscricao_fechada', 'inscricao_publica');
      return WillPopScope(
        onWillPop: () async {
          Navigator.pop(context);
          return false;
        },
        child: Scaffold(
          backgroundColor: Colors.grey.shade50,
          appBar: AppBar(
            title: const Text(
              'Inscrição',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            backgroundColor: Colors.red.shade900,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.grey.shade100),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.035),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Icon(
                        Icons.lock_rounded,
                        size: 42,
                        color: Colors.red.shade900,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Inscrições fechadas',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        color: Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _mensagem.isNotEmpty
                          ? _mensagem
                          : 'No momento não estamos aceitando novas inscrições.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('VOLTAR'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade900,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: const Text(
            'Aula Experimental',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          centerTitle: true,
          toolbarHeight: 50,
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: (_currentStep + 1) / 7,
              backgroundColor: Colors.white.withOpacity(0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
        body: _enviando
            ? _buildSendingState()
            : Center(
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
        ),
      ),
    );
  }

  Widget _buildSendingState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(18),
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.red.shade900),
            const SizedBox(height: 18),
            Text(
              _uploadingAssinatura
                  ? 'Enviando assinatura...'
                  : _uploadingFoto
                  ? 'Enviando foto...'
                  : 'Enviando sua inscrição...',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade900,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Aguarde só um instante. Estamos enviando foto, assinatura e dados com segurança.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepHeader() {
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
          margin: EdgeInsets.fromLTRB(
            compact ? 10 : 14,
            compact ? 8 : 12,
            compact ? 10 : 14,
            0,
          ),
          padding: EdgeInsets.all(compact ? 10 : 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.red.shade900, Colors.red.shade700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(compact ? 18 : 22),
            boxShadow: [
              BoxShadow(
                color: Colors.red.shade900.withOpacity(0.10),
                blurRadius: 7,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 38 : 44,
                height: compact ? 38 : 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(compact ? 14 : 16),
                  border: Border.all(color: Colors.white.withOpacity(0.16)),
                ),
                child: Icon(
                  atual.$2,
                  color: Colors.white,
                  size: compact ? 21 : 24,
                ),
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
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: compact ? 14 : 15.5,
                        height: 1.05,
                      ),
                    ),
                    SizedBox(height: compact ? 1 : 2),
                    Row(
                      children: [
                        Text(
                          'Etapa ${_currentStep + 1}/7',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.78),
                            fontSize: compact ? 10.5 : 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              minHeight: compact ? 5 : 6,
                              value: (_currentStep + 1) / 7,
                              backgroundColor: Colors.white.withOpacity(0.18),
                              valueColor:
                              const AlwaysStoppedAnimation<Color>(Colors.white),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: _temVagas ? Colors.blue.shade50 : Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _temVagas ? Icons.waving_hand : Icons.warning,
              size: 58,
              color: _temVagas ? Colors.blue : Colors.red,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _temVagas ? 'Olá! Vamos começar?' : 'Que pena!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _temVagas ? Colors.black87 : Colors.red.shade700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _temVagas
                ? 'Precisamos de algumas informações para oferecer a melhor experiência.'
                : 'No momento todas as vagas estão preenchidas.',
            style: const TextStyle(fontSize: 13.5, color: Colors.grey, height: 1.3),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Material(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                _rastrearAcaoInscricao('abriu_regimento_interno', origem: 'boas_vindas');
                showDialog(
                  context: context,
                  builder: (context) => const RegimentoDialog(),
                );
              },
              borderRadius: BorderRadius.circular(16),
              splashColor: Colors.amber.withOpacity(0.16),
              highlightColor: Colors.amber.withOpacity(0.08),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(
                            Icons.menu_book_rounded,
                            color: Colors.amber.shade900,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'REGIMENTO INTERNO',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey.shade900,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14.5,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Leia as regras e diretrizes do grupo',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 11.5,
                                  height: 1.22,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.amber.shade900,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.58),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade100),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 15,
                            color: Colors.amber.shade900,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Leia atentamente antes de prosseguir',
                              style: TextStyle(
                                fontSize: 11.2,
                                color: Colors.amber.shade900,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_configuracoesCarregadas)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _temVagas ? Colors.blue.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _temVagas ? Colors.blue.shade200 : Colors.red.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _temVagas ? Icons.info : Icons.error,
                    color: _temVagas
                        ? Colors.blue.shade900
                        : Colors.red.shade900,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _temVagas
                              ? '✅ Aceitamos alunos de $_idadeMinima a $_idadeMaxima anos'
                              : '❌ Vagas esgotadas!',
                          style: TextStyle(
                            fontSize: 14,
                            color: _temVagas
                                ? Colors.blue.shade900
                                : Colors.red.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_temVagas)
                          Text(
                            '🎯 $_vagasRestantes vagas disponíveis',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepAluno() {
    final idade = _controllers['data_nascimento']!.text.isNotEmpty
        ? _calcularIdade(_controllers['data_nascimento']!.text)
        : 0;
    final idadeValida = idade >= _idadeMinima && idade <= _idadeMaxima;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📋 DADOS DO ALUNO',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Quem vai praticar capoeira?',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            _controllers['nome']!,
            'Nome Completo *',
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
          Row(
            children: [
              Expanded(
                child: _buildDateField(
                  _controllers['data_nascimento']!,
                  'Data Nasc. *',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _sexo,
                  decoration: InputDecoration(
                    labelText: 'Sexo *',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    errorText: _sexo == null ? 'Campo obrigatório' : null,
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.red, width: 2),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.red, width: 2),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'MASCULINO',
                      child: Text('MASCULINO'),
                    ),
                    DropdownMenuItem(
                      value: 'FEMININO',
                      child: Text('FEMININO'),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => _sexo = v);
                    _rastrearAcaoInscricao(
                      'selecionou_sexo',
                      origem: 'dados_aluno',
                      metadata: {'sexo': v},
                    );
                    _validarEtapa1();
                  },
                ),
              ),
            ],
          ),
          if (_controllers['data_nascimento']!.text.isNotEmpty && !idadeValida)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red.shade700,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Idade não permitida. Aceitamos de $_idadeMinima a $_idadeMaxima anos.',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepFoto() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red.shade900, Colors.red.shade700],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.shade900.withOpacity(0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 34),
                const SizedBox(height: 10),
                const Text(
                  'Foto do aluno',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Essa foto ajuda o professor a identificar o aluno na chamada. Tire uma foto de frente, bem iluminada e com o rosto visível.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildFotoAlunoCard(tamanhoGrande: true),
          const SizedBox(height: 14),
          if (_processandoFotoLocal) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.orange.shade100),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.3,
                      color: Colors.orange.shade800,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _statusFotoLocal.isNotEmpty
                          ? _statusFotoLocal
                          : 'Processando foto do aluno...',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontSize: 12.5,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.green.shade100),
            ),
            child: Row(
              children: [
                Icon(Icons.center_focus_strong_rounded, color: Colors.green.shade800),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Depois de tirar a foto, alinhe o rosto usando o retângulo e as linhas guia.',
                    style: TextStyle(
                      color: Colors.green.shade900,
                      fontSize: 12.5,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFotoAlunoCard({bool tamanhoGrande = false}) {
    final temFoto = _temFoto();

    // Mesmo conceito visual do card da chamada: retrato, não quadrado.
    final double cardW = tamanhoGrande ? 154 : 112;
    final double cardH = cardW / 0.76;
    final double imageH = cardH - (tamanhoGrande ? 42 : 36);

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
                    color: Colors.grey.shade200,
                    border: Border.all(
                      color: temFoto ? Colors.green.shade700 : Colors.red.shade900,
                      width: temFoto ? 3 : 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Column(
                      children: [
                        SizedBox(
                          width: cardW,
                          height: imageH,
                          child: _fotoUrl != null
                              ? Image.network(
                            _fotoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildFotoPlaceholder(),
                          )
                              : _fotoBytes != null
                              ? Image.memory(
                            _fotoBytes!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildFotoPlaceholder(),
                          )
                              : _buildFotoPlaceholder(),
                        ),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            color: temFoto ? Colors.green.shade50 : Colors.red.shade50,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              temFoto ? 'Foto pronta' : 'Tirar foto',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: temFoto ? Colors.green.shade800 : Colors.red.shade900,
                                fontSize: tamanhoGrande ? 10.8 : 10.0,
                                fontWeight: FontWeight.w900,
                              ),
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
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      color: Colors.black.withOpacity(0.62),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.6,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _statusFotoLocal.isNotEmpty
                                ? _statusFotoLocal
                                : 'Processando foto...',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                            ),
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
                    decoration: BoxDecoration(
                      color: Colors.red.shade900,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Icon(
                      temFoto ? Icons.edit : Icons.camera_alt,
                      color: Colors.white,
                      size: 20,
                    ),
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
                    : '⚠️ FOTO OBRIGATÓRIA • Toque para abrir a câmera',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: _processandoFotoLocal
                      ? Colors.orange.shade800
                      : temFoto
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                  fontWeight: _processandoFotoLocal || !temFoto
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              if (!temFoto)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Tire uma foto de frente, com o rosto bem visível',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFotoPlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 4),
          Text(
            'Tirar\nfoto',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContato() {
    final isMaior = _isMaiorIdade();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📞 CONTATO',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            isMaior ? 'Como vamos falar com você?' : 'Como vamos falar com vocês?',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          _buildPhoneField(_controllers['contato_aluno']!, 'Telefone do Aluno *'),
          const SizedBox(height: 12),
          if (!isMaior) ...[
            _buildTextField(
              _controllers['nome_responsavel']!,
              'Nome do Responsável *',
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) return 'Campo obrigatório';
                if (!_validarNomePessoa(v)) return 'Use apenas letras';
                return null;
              },
              personNameOnly: true,
            ),
            const SizedBox(height: 16),
            _buildPhoneField(
              _controllers['contato_responsavel']!,
              'Telefone do Responsável *',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepEndereco() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🏠 ENDEREÇO',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Onde vocês moram?',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildTextField(
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
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: _buildTextField(
                  _controllers['bairro']!,
                  'Bairro *',
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return 'Campo obrigatório';
                    if (!_validarEnderecoTexto(v)) return 'Texto inválido';
                    return null;
                  },
                  addressText: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📄 DOCUMENTO',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'CPF (opcional)',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'O CPF é opcional, mas ajuda no cadastro futuro.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildCpfField(),
        ],
      ),
    );
  }

  Widget _buildStepRevisao() {
    final isMaior = _isMaiorIdade();
    final nomeResponsavel =
    isMaior ? _controllers['nome']!.text : _controllers['nome_responsavel']!.text;
    final nomeAluno = _controllers['nome']!.text;
    final idadeAluno = _calcularIdade(_controllers['data_nascimento']!.text);
    final precisaAssinar = _recolherAssinatura && _assinaturaUrl == null && _assinaturaBytes == null;
    final temFoto = _temFoto();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '✅ REVISÃO E AUTORIZAÇÃO',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildResumoLinhaIcon(Icons.person, 'Aluno', nomeAluno, Colors.blue),
                  const Divider(height: 16),
                  _buildResumoLinhaIcon(Icons.cake, 'Idade', '$idadeAluno anos', Colors.orange),
                  const Divider(height: 16),
                  _buildResumoLinhaIcon(
                    Icons.phone,
                    'Contato',
                    _controllers['contato_aluno']!.text,
                    Colors.green,
                  ),
                  const Divider(height: 16),
                  _buildResumoLinhaIcon(
                    Icons.photo_camera,
                    'Foto',
                    temFoto ? '✅ Foto do aluno cadastrada' : '❌ FOTO NÃO CADASTRADA',
                    temFoto ? Colors.purple : Colors.red,
                  ),
                  if (!isMaior) ...[
                    const Divider(height: 16),
                    _buildResumoLinhaIcon(
                      Icons.person_outline,
                      'Responsável',
                      nomeResponsavel,
                      Colors.purple,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildTermoElaborado(),
          const SizedBox(height: 16),
          Material(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                setState(() => _autorizacao = !_autorizacao);
                _validarEtapaFinal();
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _autorizacao ? Colors.green : Colors.grey.shade300,
                    width: _autorizacao ? 2 : 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _autorizacao,
                      onChanged: (value) {
                        setState(() => _autorizacao = value ?? false);
                        _validarEtapaFinal();
                      },
                      activeColor: Colors.green.shade700,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          isMaior
                              ? '☑️ Li e concordo com todos os termos acima'
                              : '☑️ Li e concordo com todos os termos acima como responsável',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _autorizacao ? Colors.green.shade800 : Colors.grey.shade800,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (precisaAssinar)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '⚠️ Você precisa assinar o termo antes de finalizar',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          if (!temFoto)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '⚠️ Foto obrigatória! Volte na etapa Foto do aluno.',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          if (_recolherAssinatura) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _assinaturaUrl == null && _assinaturaBytes == null ? _abrirTelaAssinatura : null,
                icon: Icon(
                  _assinaturaUrl == null && _assinaturaBytes == null ? Icons.draw : Icons.check_circle,
                  color: Colors.white,
                  size: 28,
                ),
                label: Text(
                  _assinaturaUrl == null && _assinaturaBytes == null ? '✍️ ASSINAR TERMO' : '✅ TERMO ASSINADO',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  _assinaturaUrl == null && _assinaturaBytes == null ? Colors.blue.shade900 : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTermoElaborado() {
    final isMaior = _isMaiorIdade();
    final nomeAluno = _controllers['nome']!.text;
    final nomeResp =
    isMaior ? nomeAluno : _controllers['nome_responsavel']!.text;
    final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'TERMO DE RESPONSABILIDADE',
                style: TextStyle(
                  color: Colors.red.shade900,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMaior) ...[
                  _buildTermoLinha('📌', 'Eu, $nomeAluno, declaro para os devidos fins que:'),
                  const SizedBox(height: 8),
                  _buildTermoLinha(
                    '1️⃣',
                    'ESTOU CIENTE de que a Capoeira é uma arte marcial que envolve atividades físicas de médio a alto impacto, podendo resultar em lesões.',
                  ),
                  _buildTermoLinha(
                    '2️⃣',
                    'ASSUMO total responsabilidade por qualquer dano físico que possa ocorrer durante a prática, isentando o Grupo UAI CAPOEIRA de qualquer ônus.',
                  ),
                  _buildTermoLinha(
                    '3️⃣',
                    'COMPROMETO-ME a informar previamente qualquer condição de saúde ou limitação física.',
                  ),
                  _buildTermoLinha(
                    '4️⃣',
                    'AUTORIZO a participação na aula experimental de Capoeira.',
                  ),
                  _buildTermoLinha(
                    '5️⃣',
                    'CONCORDO com as filmagens e fotografias para fins institucionais.',
                  ),
                ] else ...[
                  _buildTermoLinha(
                    '📌',
                    'Eu, $nomeResp, responsável legal por $nomeAluno, declaro para os devidos fins que:',
                  ),
                  const SizedBox(height: 8),
                  _buildTermoLinha(
                    '1️⃣',
                    'AUTORIZO a participação do(a) menor acima identificado(a) na aula experimental de Capoeira oferecida pelo Grupo UAI CAPOEIRA.',
                  ),
                  _buildTermoLinha(
                    '2️⃣',
                    'ESTOU CIENTE dos riscos da prática esportiva e assumo total responsabilidade.',
                  ),
                  _buildTermoLinha(
                    '3️⃣',
                    'COMPROMETO-ME a informar previamente qualquer condição de saúde ou limitação física do aluno.',
                  ),
                  _buildTermoLinha(
                    '4️⃣',
                    'CONCORDO com as filmagens e fotografias para fins institucionais.',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.blue.shade900),
                const SizedBox(width: 8),
                Text(
                  'Data e hora: $dataHora',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade900,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_recolherAssinatura)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Assinatura:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final screenWidth = constraints.maxWidth;
                      final isMobile = screenWidth < 600;

                      return Center(
                        child: Container(
                          width: isMobile ? screenWidth * 0.8 : 300,
                          height: isMobile ? 60 : 100,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade400),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: (_assinaturaUrl != null || _assinaturaBytes != null)
                              ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _assinaturaUrl != null
                                ? Image.network(
                              _assinaturaUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => _buildAssinaturaPreviewFallback(),
                            )
                                : Image.memory(
                              _assinaturaBytes!,
                              fit: BoxFit.contain,
                            ),
                          )
                              : const Center(
                            child: Text(
                              '____________________________',
                              style: TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTermoLinha(String bullet, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$bullet ',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 12, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoLinhaIcon(
      IconData icon,
      String label,
      String valor,
      Color cor,
      ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: cor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              Text(
                valor,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons() {
    final isLast = _currentStep == 6;

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 380;
          final tiny = constraints.maxWidth < 330;

          final continuarLabel = isLast
              ? (compact ? 'ENVIAR' : 'ENVIAR INSCRIÇÃO')
              : (compact ? 'PRÓXIMO' : 'CONTINUAR');

          final voltarButton = OutlinedButton.icon(
            onPressed: _etapaAnterior,
            icon: Icon(Icons.arrow_back_rounded, size: compact ? 17 : 18),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(compact ? 'VOLTAR' : 'VOLTAR'),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey.shade800,
              side: BorderSide(color: Colors.grey.shade300),
              padding: EdgeInsets.symmetric(vertical: compact ? 11 : 13),
              textStyle: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: compact ? 11.5 : 13,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(compact ? 13 : 16),
              ),
            ),
          );

          final nextButton = ElevatedButton.icon(
            onPressed: isLast ? _enviarInscricao : _proximaEtapa,
            icon: Icon(
              isLast ? Icons.send_rounded : Icons.arrow_forward_rounded,
              size: compact ? 17 : 19,
            ),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(continuarLabel),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade900,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: compact ? 12 : 14),
              textStyle: TextStyle(
                fontSize: compact ? 11.5 : 13.5,
                fontWeight: FontWeight.w900,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(compact ? 13 : 16),
              ),
            ),
          );

          return Container(
            padding: EdgeInsets.fromLTRB(
              compact ? 10 : 14,
              compact ? 7 : 9,
              compact ? 10 : 14,
              compact ? 10 : 13,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.045),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: _currentStep == 0
                ? SizedBox(width: double.infinity, child: nextButton)
                : tiny
                ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: double.infinity, child: nextButton),
                const SizedBox(height: 7),
                SizedBox(width: double.infinity, child: voltarButton),
              ],
            )
                : Row(
              children: [
                Expanded(child: voltarButton),
                SizedBox(width: compact ? 8 : 10),
                Expanded(flex: isLast ? 2 : 1, child: nextButton),
              ],
            ),
          );
        },
      ),
    );
  }

  InputDecoration _modernInputDecoration({
    required String label,
    String? hint,
    IconData? icon,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      prefixIcon: icon == null ? null : Icon(icon, color: Colors.red.shade900),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.red.shade900, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.red, width: 1.4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.red, width: 1.4),
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller,
      String label, {
        bool isNumberOnly = false,
        bool personNameOnly = false,
        bool addressText = false,
        int? maxLength,
        String? Function(String?)? validator,
      }) {
    List<TextInputFormatter> formatters = [];

    if (isNumberOnly) {
      formatters = [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(maxLength ?? 5),
      ];
    } else if (personNameOnly) {
      formatters = [
        FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÀ-ÖØ-öø-ÿ\s]")),
      ];
    } else if (addressText) {
      formatters = [
        FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÀ-ÖØ-öø-ÿ0-9\s\.,\-ºª/]")),
      ];
    }

    IconData icon = Icons.edit_rounded;
    if (label.toLowerCase().contains('nome')) icon = Icons.person_rounded;
    if (label.toLowerCase().contains('apelido')) icon = Icons.badge_rounded;
    if (label.toLowerCase().contains('rua')) icon = Icons.location_on_rounded;
    if (label.toLowerCase().contains('número')) icon = Icons.numbers_rounded;
    if (label.toLowerCase().contains('bairro')) icon = Icons.map_rounded;
    if (label.toLowerCase().contains('cidade')) icon = Icons.location_city_rounded;

    return TextFormField(
      controller: controller,
      decoration: _modernInputDecoration(
        label: label,
        icon: icon,
        errorText: validator?.call(controller.text),
      ).copyWith(counterText: ''),
      keyboardType: isNumberOnly ? TextInputType.number : TextInputType.text,
      inputFormatters: formatters,
      textCapitalization: TextCapitalization.characters,
      onChanged: (_) {
        if (_currentStep == 1) _validarEtapa1();
        if (_currentStep == 2) _validarEtapa2();
        if (_currentStep == 3) _validarEtapa3();
      },
    );
  }

  Widget _buildPhoneField(TextEditingController controller, String label) {
    final hasError = controller.text.isNotEmpty && !_telefoneCompleto(controller.text);

    return TextFormField(
      controller: controller,
      decoration: _modernInputDecoration(
        label: label,
        hint: '(00) 00000-0000',
        icon: Icons.phone_android_rounded,
        errorText: hasError ? 'Telefone incompleto' : null,
      ),
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
        _PhoneInputFormatter(),
      ],
      onChanged: (_) {
        if (_currentStep == 2) _validarEtapa2();
      },
    );
  }

  Widget _buildCpfField() {
    return TextFormField(
      controller: _controllers['cpf'],
      decoration: _modernInputDecoration(
        label: 'CPF (opcional)',
        hint: '000.000.000-00',
        icon: Icons.badge_rounded,
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
        _CpfInputFormatter(),
      ],
    );
  }

  Widget _buildDateField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      decoration: _modernInputDecoration(
        label: label,
        icon: Icons.cake_rounded,
        errorText: controller.text.isEmpty ? 'Campo obrigatório' : null,
      ).copyWith(
        suffixIcon: Icon(Icons.calendar_month_rounded, color: Colors.red.shade900),
      ),
      readOnly: true,
      onTap: () => _selectDate(context, controller),
    );
  }

  Future<void> _selectDate(
      BuildContext context,
      TextEditingController controller,
      ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 3650)),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        controller.text = DateFormat('dd/MM/yyyy').format(picked);
      });
      _validarEtapa1();
    }
  }
}




Widget _buildAssinaturaPreviewFallback() {
  return Center(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.draw_rounded, color: Colors.green, size: 18),
        SizedBox(width: 6),
        Text(
          'Assinatura registrada',
          style: TextStyle(
            color: Colors.green,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}


class _ProcessandoFotoDialog extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final IconData icon;

  const _ProcessandoFotoDialog({
    required this.titulo,
    required this.subtitulo,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        padding: const EdgeInsets.all(22),
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 62,
                  height: 62,
                  child: CircularProgressIndicator(
                    color: Colors.red.shade900,
                    strokeWidth: 3,
                  ),
                ),
                Icon(icon, color: Colors.red.shade900, size: 26),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade900,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                height: 1.35,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _EditorFotoInscricaoDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final String nomeAluno;

  const _EditorFotoInscricaoDialog({
    required this.imageBytes,
    required this.nomeAluno,
  });

  @override
  State<_EditorFotoInscricaoDialog> createState() =>
      _EditorFotoInscricaoDialogState();
}

class _EditorFotoInscricaoDialogState extends State<_EditorFotoInscricaoDialog> {
  double _zoom = 1.0;
  double _offsetX = 0.0;
  double _offsetY = 0.0;
  bool _processando = false;

  void _resetar() {
    setState(() {
      _zoom = 1.0;
      _offsetX = 0.0;
      _offsetY = 0.0;
    });
  }

  Future<void> _selecionarFoto() async {
    if (_processando) return;

    setState(() => _processando = true);

    // Garante que o botão e o overlay de carregando apareçam antes do crop pesado.
    await Future.delayed(const Duration(milliseconds: 80));

    try {
      final bytes = await _gerarImagemFinal();
      if (!mounted) return;
      Navigator.pop(context, bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _processando = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao ajustar foto: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<Uint8List> _gerarImagemFinal() async {
    final original = img.decodeImage(widget.imageBytes);
    if (original == null) {
      throw Exception('Imagem inválida');
    }

    // Foto final em retrato, no mesmo conceito visual do card da chamada.
    // Aqui NÃO usamos canvas branco. Fazemos resize cobrindo tudo e depois crop.
    // Isso evita aquela área branca satânica aparecendo embaixo da foto kkkkk.
    const outputW = 600;
    const outputH = 789; // 600 / 0.76

    final safeZoom = math.max(_zoom, 1.0);

    final scaleBase = math.max(
      outputW / original.width,
      outputH / original.height,
    );

    final scale = scaleBase * safeZoom;
    final resizedW = math.max(outputW, (original.width * scale).round());
    final resizedH = math.max(outputH, (original.height * scale).round());

    final resized = img.copyResize(
      original,
      width: resizedW,
      height: resizedH,
      interpolation: img.Interpolation.linear,
    );

    final maxCropX = math.max(0, resizedW - outputW);
    final maxCropY = math.max(0, resizedH - outputH);

    // Mesma lógica visual do preview:
    // offset positivo move a imagem para a direita/baixo,
    // então o crop precisa andar no sentido oposto.
    final centerCropX = maxCropX / 2;
    final centerCropY = maxCropY / 2;

    final cropX = (centerCropX - (_offsetX * outputW * 0.42))
        .round()
        .clamp(0, maxCropX);

    final cropY = (centerCropY - (_offsetY * outputH * 0.42))
        .round()
        .clamp(0, maxCropY);

    final cropped = img.copyCrop(
      resized,
      x: cropX,
      y: cropY,
      width: outputW,
      height: outputH,
    );

    return Uint8List.fromList(img.encodeJpg(cropped, quality: 88));
  }

  @override
  Widget build(BuildContext context) {
    final alturaTela = MediaQuery.of(context).size.height;
    final larguraTela = MediaQuery.of(context).size.width;
    final bemPequeno = alturaTela < 720 || larguraTela < 370;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: bemPequeno ? 10 : 18,
        vertical: bemPequeno ? 10 : 18,
      ),
      backgroundColor: Colors.transparent,
      child: SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: alturaTela * 0.94,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFFFECEC),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _buildHeader(bemPequeno),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    bemPequeno ? 12 : 18,
                    bemPequeno ? 12 : 16,
                    bemPequeno ? 12 : 18,
                    bemPequeno ? 12 : 16,
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Alinhe o rosto usando o retângulo e as linhas guia. Essa foto será usada para identificar o aluno na chamada.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          height: 1.35,
                          fontSize: bemPequeno ? 12.2 : 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: bemPequeno ? 10 : 14),
                      _buildEditorArea(bemPequeno),
                      SizedBox(height: bemPequeno ? 10 : 14),
                      _buildControlsSlim(bemPequeno),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool compacto) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        compacto ? 14 : 18,
        compacto ? 14 : 18,
        compacto ? 10 : 14,
        compacto ? 13 : 18,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.center_focus_strong_rounded, color: Colors.white, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ajustar foto do aluno',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compacto ? 17 : 21,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.nomeAluno.trim().isEmpty ? 'Aluno' : widget.nomeAluno.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: compacto ? 11.5 : 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: _processando ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorArea(bool compacto) {
    // Mesma proporção visual do card da chamada:
    // SliverGridDelegateWithFixedCrossAxisCount(childAspectRatio: 0.76)
    final previewW = compacto ? 218.0 : 248.0;
    final cardH = previewW / 0.76;
    final actionH = compacto ? 58.0 : 62.0;
    final previewH = cardH - actionH;

    return Center(
      child: Container(
        width: previewW,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.green.shade500, width: 2.2),
          boxShadow: [
            BoxShadow(
              color: Colors.green.shade900.withOpacity(0.14),
              blurRadius: 13,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: previewW,
              height: previewH,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRect(
                      child: Transform.translate(
                        offset: Offset(
                          _offsetX * previewW * 0.42,
                          _offsetY * previewH * 0.42,
                        ),
                        child: Transform.scale(
                          scale: _zoom,
                          child: Image.memory(
                            widget.imageBytes,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _FotoAlunoGuiaPainter(),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withOpacity(0.72),
                            Colors.black.withOpacity(0.46),
                            Colors.transparent,
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                      ),
                      child: const Text(
                        'Rosto alinhado nas guias',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  if (_processando)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.58),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white.withOpacity(0.12)),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.6,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  'Preparando foto...',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                compacto ? 9 : 11,
                compacto ? 8 : 10,
                compacto ? 9 : 11,
                compacto ? 10 : 12,
              ),
              color: Colors.green.shade50,
              child: Row(
                children: [
                  _buildResetButton(
                    onTap: _processando ? null : _resetar,
                    compacto: compacto,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: _buildActionButton(
                      label: 'Usar esta foto',
                      icon: Icons.check_circle_rounded,
                      background: Colors.green.shade700,
                      onTap: _processando ? null : _selecionarFoto,
                      compacto: compacto,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color background,
    required VoidCallback? onTap,
    required bool compacto,
  }) {
    final loading = _processando;

    return ElevatedButton.icon(
      onPressed: onTap,
      icon: loading
          ? SizedBox(
        width: compacto ? 16 : 18,
        height: compacto ? 16 : 18,
        child: const CircularProgressIndicator(
          strokeWidth: 2.2,
          color: Colors.white,
        ),
      )
          : Icon(icon, size: compacto ? 17 : 19),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(loading ? 'Preparando...' : label),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: Colors.white,
        disabledBackgroundColor: background.withOpacity(0.72),
        elevation: 0,
        padding: EdgeInsets.symmetric(
          horizontal: compacto ? 12 : 14,
          vertical: compacto ? 11 : 13,
        ),
        textStyle: TextStyle(
          fontSize: compacto ? 12.5 : 13.5,
          fontWeight: FontWeight.w900,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }

  Widget _buildResetButton({
    required VoidCallback? onTap,
    required bool compacto,
  }) {
    return Tooltip(
      message: 'Resetar ajuste',
      child: Material(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            width: compacto ? 43 : 48,
            height: compacto ? 43 : 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Icon(
              Icons.restart_alt_rounded,
              color: Colors.red.shade800,
              size: compacto ? 22 : 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlsSlim(bool compacto) {
    return Column(
      children: [
        _buildSliderTile(
          label: 'Zoom',
          icon: Icons.zoom_in_rounded,
          value: _zoom,
          min: 1.0,
          max: 2.4,
          onChanged: (v) => setState(() => _zoom = v),
          compacto: compacto,
        ),
        SizedBox(height: compacto ? 8 : 10),
        Row(
          children: [
            Expanded(
              child: _buildMiniSliderTile(
                label: 'Horizontal',
                icon: Icons.swap_horiz_rounded,
                value: _offsetX,
                min: -1,
                max: 1,
                onChanged: (v) => setState(() => _offsetX = v),
                compacto: compacto,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMiniSliderTile(
                label: 'Vertical',
                icon: Icons.swap_vert_rounded,
                value: _offsetY,
                min: -1,
                max: 1,
                onChanged: (v) => setState(() => _offsetY = v),
                compacto: compacto,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSliderTile({
    required String label,
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required bool compacto,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 12 : 16,
        vertical: compacto ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.red.shade50),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.red.shade900, size: compacto ? 20 : 22),
          const SizedBox(width: 8),
          SizedBox(
            width: compacto ? 54 : 76,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade900,
                fontSize: compacto ? 12 : 13.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.red.shade700,
                inactiveTrackColor: Colors.red.shade100,
                thumbColor: Colors.red.shade700,
                overlayColor: Colors.red.shade700.withOpacity(0.12),
                trackHeight: 4,
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                onChanged: _processando ? null : onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniSliderTile({
    required String label,
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required bool compacto,
  }) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        compacto ? 8 : 10,
        compacto ? 8 : 9,
        compacto ? 8 : 10,
        compacto ? 7 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.shade50),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.red.shade900, size: 17),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade900,
                    fontSize: compacto ? 10.5 : 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.red.shade700,
              inactiveTrackColor: Colors.red.shade100,
              thumbColor: Colors.red.shade700,
              overlayColor: Colors.red.shade700.withOpacity(0.12),
              trackHeight: 3.2,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: _processando ? null : onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _FotoAlunoGuiaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final green = Paint()
      ..color = Colors.green.shade500
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;

    final grid = Paint()
      ..color = Colors.white.withOpacity(0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    final faceRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.46),
        width: size.width * 0.72,
        height: size.height * 0.58,
      ),
      const Radius.circular(22),
    );

    canvas.drawRRect(faceRect, green);

    canvas.drawLine(
      Offset(size.width / 3, 0),
      Offset(size.width / 3, size.height),
      grid,
    );
    canvas.drawLine(
      Offset(size.width * 2 / 3, 0),
      Offset(size.width * 2 / 3, size.height),
      grid,
    );
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      grid,
    );
    canvas.drawLine(
      Offset(0, size.height * 2 / 3),
      Offset(size.width, size.height * 2 / 3),
      grid,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


class _GuiaRostoInscricaoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final squarePaint = Paint()
      ..color = Colors.green.withOpacity(0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    final safeSquare = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.16,
        size.height * 0.14,
        size.width * 0.68,
        size.height * 0.64,
      ),
      const Radius.circular(14),
    );

    canvas.drawRRect(safeSquare, squarePaint);

    final guidePaint = Paint()
      ..color = Colors.white.withOpacity(0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final centerY = size.height * 0.42;

    canvas.drawLine(
      Offset(size.width / 2, size.height * 0.10),
      Offset(size.width / 2, size.height * 0.82),
      guidePaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.10, centerY),
      Offset(size.width * 0.90, centerY),
      guidePaint,
    );

    final thinPaint = Paint()
      ..color = Colors.white.withOpacity(0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    canvas.drawLine(
      Offset(size.width * 0.33, size.height * 0.14),
      Offset(size.width * 0.33, size.height * 0.78),
      thinPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.67, size.height * 0.14),
      Offset(size.width * 0.67, size.height * 0.78),
      thinPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 11) digits = digits.substring(0, 11);

    String formatted = '';
    if (digits.length <= 3) {
      formatted = digits;
    } else if (digits.length <= 6) {
      formatted = '${digits.substring(0, 3)}.${digits.substring(3)}';
    } else if (digits.length <= 9) {
      formatted =
      '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6)}';
    } else {
      formatted =
      '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 11) digits = digits.substring(0, 11);

    String formatted = '';
    if (digits.length <= 2) {
      formatted = '($digits';
    } else if (digits.length <= 6) {
      formatted = '(${digits.substring(0, 2)}) ${digits.substring(2)}';
    } else if (digits.length <= 10) {
      formatted =
      '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    } else {
      formatted =
      '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7, 11)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}