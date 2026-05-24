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

class InscricaoPublicaScreen extends StatefulWidget {
  const InscricaoPublicaScreen({super.key});

  @override
  State<InscricaoPublicaScreen> createState() => _InscricaoPublicaScreenState();
}

class _InscricaoPublicaScreenState extends State<InscricaoPublicaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final PageController _pageController = PageController();

  int _currentStep = 0;

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

    for (final controller in _controllers.values) {
      controller.dispose();
    }

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
              const SizedBox(height: 16),
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
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
    } catch (_) {
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
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
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
      final continuar = await _mostrarOrientacaoFotoAluno();
      if (!continuar) return;

      _setProcessandoFotoLocal('Preparando câmera...');

      await abrirLoading(
        titulo: 'Aguardando foto do aluno...',
        subtitulo: 'A câmera será aberta agora. Tire uma foto de frente e confirme.',
        icon: Icons.camera_alt_rounded,
      );

      await Future.delayed(const Duration(milliseconds: 280));

      fecharLoading();

      final picker = ImagePicker();

      final image = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 92,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (image == null) {
        _limparProcessandoFotoLocal();
        return;
      }

      _setProcessandoFotoLocal('Foto recebida. Processando...');

      await abrirLoading(
        titulo: 'Analisando foto do aluno...',
        subtitulo: 'A foto foi recebida. Estamos preparando o ajuste para identificação.',
        icon: Icons.center_focus_strong_rounded,
      );

      // Dá tempo para a interface atualizar antes da leitura/processamento.
      await Future.delayed(const Duration(milliseconds: 160));

      final originalBytes = await image.readAsBytes();

      _setProcessandoFotoLocal('Abrindo editor de ajuste...');

      // Tempo mínimo visual para evitar sensação de tela vazia/travada.
      await Future.delayed(const Duration(milliseconds: 520));

      fecharLoading();

      if (!mounted) {
        _limparProcessandoFotoLocal();
        return;
      }

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
        return;
      }

      setState(() {
        _fotoBytes = bytesEditados;
        _fotoNome = 'foto_aluno_${DateTime.now().millisecondsSinceEpoch}.jpg';
        _fotoUrl = null;
        _uploadingFoto = false;
        _processandoFotoLocal = false;
        _statusFotoLocal = '';
      });

      _validarEtapaFoto();
      _showSuccessSnackbar('📸 Foto ajustada! Ela será enviada ao finalizar a inscrição.');
    } catch (e) {
      fecharLoading();
      _limparProcessandoFotoLocal();

      if (mounted) setState(() => _uploadingFoto = false);

      _showErrorSnackbar('Erro ao tirar foto: $e');
    }
  }

  Future<void> _uploadFotoFirebase() async {
    if (_fotoBytes == null || _fotoNome == null) return;

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
      _showErrorSnackbar('Erro ao fazer upload da foto: $e');
      rethrow;
    }
  }

  void _removerFoto() {
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

            _showSuccessSnackbar('✅ Assinatura registrada com sucesso!');
          },
        ),
      ),
    );

    if (result == true && mounted) {
      _validarEtapaFinal();
    }
  }

  Future<void> _uploadAssinaturaFirebase() async {
    if (_assinaturaUrl?.isNotEmpty == true) return;
    if (_assinaturaBytes == null) return;

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

      setState(() {
        _assinaturaUrl = downloadUrl;
        _assinaturaBytes = null;
        _uploadingAssinatura = false;
      });
    } catch (e) {
      setState(() => _uploadingAssinatura = false);
      _showErrorSnackbar('Erro ao enviar assinatura: $e');
      rethrow;
    }
  }

  Future<void> _enviarInscricao() async {
    _validarEtapaFinal();

    if (!(_etapaValida[6] ?? false)) {
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

      await _firestore.collection('inscricoes').add(dados);

      final novoTotal = inscricoesSnapshot.docs.length + 1;
      await _firestore.collection('configuracoes').doc('inscricoes').set({
        'total_inscricoes': novoTotal,
      }, SetOptions(merge: true));

      if (mounted) {
        _mostrarDialogSucesso(dados);
      }
    } catch (e) {
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
            borderRadius: BorderRadius.circular(28),
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
                        fontSize: 24,
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

    setState(() => _currentStep++);
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _etapaAnterior() {
    if (_currentStep <= 0) return;

    setState(() => _currentStep--);
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<bool> _onWillPop() async {
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
              const SizedBox(height: 16),
              const Text(
                'Sair da inscrição?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
        Navigator.pop(context);
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
                padding: const EdgeInsets.all(24),
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
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(7),
            child: LinearProgressIndicator(
              minHeight: 7,
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

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: Icon(atual.$2, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  atual.$1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Etapa ${_currentStep + 1} de 7',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: (_currentStep + 1) / 7,
                    backgroundColor: Colors.white.withOpacity(0.18),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepWelcome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: _temVagas ? Colors.blue.shade50 : Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _temVagas ? Icons.waving_hand : Icons.warning,
              size: 80,
              color: _temVagas ? Colors.blue : Colors.red,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            _temVagas ? 'Olá! Vamos começar?' : 'Que pena!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _temVagas ? Colors.black87 : Colors.red.shade700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            _temVagas
                ? 'Precisamos de algumas informações para oferecer a melhor experiência.'
                : 'No momento todas as vagas estão preenchidas.',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.menu_book, color: Colors.amber.shade900),
                  ),
                  title: const Text(
                    'REGIMENTO INTERNO',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  subtitle: const Text(
                    'Leia as regras e diretrizes do grupo',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_forward,
                      color: Colors.amber.shade900,
                      size: 20,
                    ),
                  ),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => const RegimentoDialog(),
                    );
                  },
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.amber),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Leia atentamente antes de prosseguir',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.amber,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📋 DADOS DO ALUNO',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Quem vai praticar capoeira?',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 24),
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
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
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
                const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 42),
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
          const SizedBox(height: 18),
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
    final double size = tamanhoGrande ? 176 : 120;

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
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
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
                    borderRadius: BorderRadius.circular(26),
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
                ),
                if (_uploadingFoto || _processandoFotoLocal)
                  Container(
                    width: size,
                    height: size,
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📞 CONTATO',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            isMaior ? 'Como vamos falar com você?' : 'Como vamos falar com vocês?',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          _buildPhoneField(_controllers['contato_aluno']!, 'Telefone do Aluno *'),
          const SizedBox(height: 16),
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
      padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 24),
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
      padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 24),
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
          const SizedBox(height: 24),
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
                fontSize: 18,
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
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _autorizacao ? Colors.green : Colors.grey.shade300,
                width: _autorizacao ? 2 : 1,
              ),
            ),
            child: CheckboxListTile(
              value: _autorizacao,
              onChanged: (value) {
                setState(() => _autorizacao = value ?? false);
                _validarEtapaFinal();
              },
              title: Text(
                isMaior
                    ? '☑️ Li e concordo com todos os termos acima'
                    : '☑️ Li e concordo com todos os termos acima como responsável',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: _autorizacao ? Colors.green.shade800 : Colors.black87,
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: Colors.green,
              checkboxShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
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
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
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
        child: Row(
          children: [
            if (_currentStep > 0) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _etapaAnterior,
                  icon: const Icon(Icons.arrow_back_rounded, size: 19),
                  label: const Text('VOLTAR'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade800,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: _currentStep == 0 ? 2 : 1,
              child: ElevatedButton.icon(
                onPressed: isLast ? _enviarInscricao : _proximaEtapa,
                icon: Icon(
                  isLast ? Icons.send_rounded : Icons.arrow_forward_rounded,
                  size: 20,
                ),
                label: Text(isLast ? 'ENVIAR INSCRIÇÃO' : 'CONTINUAR'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
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
  State<_EditorFotoInscricaoDialog> createState() => _EditorFotoInscricaoDialogState();
}

class _EditorFotoInscricaoDialogState extends State<_EditorFotoInscricaoDialog> {
  double _zoom = 1.35;
  double _offsetX = 0;
  double _offsetY = 0;
  bool _salvando = false;

  void _resetar() {
    setState(() {
      _zoom = 1.35;
      _offsetX = 0;
      _offsetY = 0;
    });
  }

  Future<void> _salvarImagemEditada() async {
    if (_salvando) return;

    setState(() => _salvando = true);

    try {
      final decoded = img.decodeImage(widget.imageBytes);

      if (decoded == null) {
        throw Exception('Não foi possível abrir essa imagem.');
      }

      final original = img.bakeOrientation(decoded);
      final menorLado = math.min(original.width, original.height).toDouble();
      final cropSize = (menorLado / _zoom)
          .round()
          .clamp(120, menorLado.round())
          .toInt();

      final maxDx = math.max(0.0, (original.width - cropSize) / 2);
      final maxDy = math.max(0.0, (original.height - cropSize) / 2);

      final cropX = ((original.width - cropSize) / 2 - (_offsetX * maxDx))
          .round()
          .clamp(0, original.width - cropSize)
          .toInt();
      final cropY = ((original.height - cropSize) / 2 - (_offsetY * maxDy))
          .round()
          .clamp(0, original.height - cropSize)
          .toInt();

      final cropped = img.copyCrop(
        original,
        x: cropX,
        y: cropY,
        width: cropSize,
        height: cropSize,
      );

      final resized = img.copyResize(
        cropped,
        width: 900,
        height: 900,
        interpolation: img.Interpolation.cubic,
      );

      final jpg = Uint8List.fromList(img.encodeJpg(resized, quality: 86));

      if (!mounted) return;
      Navigator.pop(context, jpg);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao ajustar foto: $e'),
          backgroundColor: Colors.red,
        ),
      );

      setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nome = widget.nomeAluno.trim().isEmpty ? 'Aluno' : widget.nomeAluno.trim();

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.94,
            maxWidth: 520,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red.shade900, Colors.red.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.center_focus_strong_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Ajustar foto do aluno',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                          Text(
                            nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.78),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _salvando ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'Alinhe o rosto usando o retângulo e as linhas guia. Essa foto será usada para identificar o aluno na chamada.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildCardReferencia(),
                      const SizedBox(height: 16),
                      _buildSlider(
                        label: 'Zoom',
                        value: _zoom,
                        min: 1.0,
                        max: 3.0,
                        divisions: 40,
                        icon: Icons.zoom_in_rounded,
                        onChanged: (v) => setState(() => _zoom = v),
                      ),
                      _buildSlider(
                        label: 'Horizontal',
                        value: _offsetX,
                        min: -1,
                        max: 1,
                        divisions: 40,
                        icon: Icons.swap_horiz_rounded,
                        onChanged: (v) => setState(() => _offsetX = v),
                      ),
                      _buildSlider(
                        label: 'Vertical',
                        value: _offsetY,
                        min: -1,
                        max: 1,
                        divisions: 40,
                        icon: Icons.swap_vert_rounded,
                        onChanged: (v) => setState(() => _offsetY = v),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _salvando ? null : _resetar,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Resetar'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _salvando ? null : _salvarImagemEditada,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade900,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                              icon: _salvando
                                  ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                                  : const Icon(Icons.check_rounded),
                              label: Text(_salvando ? 'Salvando...' : 'Usar foto'),
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildCardReferencia() {
    return Center(
      child: Container(
        width: 210,
        height: 292,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.green.shade500, width: 2.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: Colors.grey.shade100,
                      child: ClipRect(
                        child: Transform.translate(
                          offset: Offset(_offsetX * 58, _offsetY * 58),
                          child: Transform.scale(
                            scale: _zoom,
                            child: Image.memory(
                              widget.imageBytes,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _GuiaRostoInscricaoPainter(),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.center,
                            colors: [
                              Colors.black.withOpacity(0.55),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Text(
                        'Rosto alinhado nas guias',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(9, 9, 9, 10),
                color: Colors.green.shade50,
                child: Center(
                  child: Container(
                    width: 142,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded, color: Colors.white, size: 17),
                        SizedBox(width: 6),
                        Text(
                          'Boa para chamada',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
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

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required IconData icon,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: Colors.red.shade900),
          const SizedBox(width: 8),
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: Colors.red.shade900,
              onChanged: _salvando ? null : onChanged,
            ),
          ),
        ],
      ),
    );
  }
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