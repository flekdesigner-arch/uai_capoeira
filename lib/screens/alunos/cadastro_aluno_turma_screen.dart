import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class CadastroAlunoTurmaScreen extends StatefulWidget {
  final String? alunoId;
  final String turmaId;
  final String turmaNome;
  final String academiaId;
  final String academiaNome;
  final Map<String, dynamic>? dadosIniciais;

  const CadastroAlunoTurmaScreen({
    super.key,
    this.alunoId,
    required this.turmaId,
    required this.turmaNome,
    required this.academiaId,
    required this.academiaNome,
    this.dadosIniciais,
  });

  @override
  State<CadastroAlunoTurmaScreen> createState() =>
      _CadastroAlunoTurmaScreenState();
}

class _CadastroAlunoTurmaScreenState extends State<CadastroAlunoTurmaScreen> {
  final _formKey = GlobalKey<FormState>();

  bool get _isEditing => widget.alunoId != null;

  bool get _isFromInscricao => widget.dadosIniciais != null && !_isEditing;

  final Map<String, TextEditingController> _controllers = {
    'nome': TextEditingController(),
    'cpf': TextEditingController(),
    'apelido': TextEditingController(),
    'data_nascimento': TextEditingController(),
    'data_graduacao_atual': TextEditingController(),
    'tempo_capoeira': TextEditingController(),
    'rua': TextEditingController(),
    'numero': TextEditingController(),
    'bairro': TextEditingController(),
    'cidade': TextEditingController(),
    'contato_aluno': TextEditingController(),
    'nome_responsavel': TextEditingController(),
    'contato_responsavel': TextEditingController(),
  };

  final TextEditingController _enderecoCompletoController =
  TextEditingController();

  String? _sexo;
  String? _graduacaoId;
  List<DropdownMenuItem<String>> _graduacaoItems = [];
  Map<String, Map<String, dynamic>> _graduacoesData = {};
  XFile? _pickedImage;
  String? _networkImageUrl;

  bool _isLoading = true;
  bool _turmaCheia = false;
  bool _isMounted = false;
  bool _fotoCarregada = false;
  bool _fotoVeioDaInscricao = false;
  bool _salvando = false;

  String? _usuarioLogadoNome;
  String? _usuarioLogadoEmail;
  String? _usuarioLogadoUid;

  Map<String, dynamic> _turmaData = {};

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    _initializeData();
  }

  @override
  void dispose() {
    _isMounted = false;
    _controllers.forEach((_, controller) => controller.dispose());
    _enderecoCompletoController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback callback) {
    if (_isMounted) setState(callback);
  }

  Future<void> _carregarUsuarioLogado() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _usuarioLogadoUid = user.uid;
        _usuarioLogadoEmail = user.email;
        final userDoc = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          final userData = userDoc.data();
          _usuarioLogadoNome = userData?['nome']?.toString() ?? user.email;
        } else {
          _usuarioLogadoNome = user.email;
        }
      } else {
        _usuarioLogadoNome = 'Sistema';
        _usuarioLogadoEmail = 'sistema@uai.capoeira';
      }
    } catch (e) {
      _usuarioLogadoNome = 'Sistema';
      _usuarioLogadoEmail = 'sistema@uai.capoeira';
    }
  }

  String _extrairRua(String enderecoCompleto) {
    try {
      final partes = enderecoCompleto.split(', ');
      if (partes.isNotEmpty) {
        final ruaNumero = partes[0].split(' - ');
        return ruaNumero[0];
      }
    } catch (_) {}
    return '';
  }

  String _extrairNumero(String enderecoCompleto) {
    try {
      final partes = enderecoCompleto.split(', ');
      if (partes.isNotEmpty) {
        final ruaNumero = partes[0].split(' - ');
        if (ruaNumero.length > 1) return ruaNumero[1];
      }
    } catch (_) {}
    return '';
  }

  String _extrairBairro(String enderecoCompleto) {
    try {
      final partes = enderecoCompleto.split(', ');
      if (partes.length > 1) return partes[1];
    } catch (_) {}
    return '';
  }

  String? _extrairCidade(String enderecoCompleto) {
    try {
      final partes = enderecoCompleto.split(', ');
      if (partes.length > 2) return partes[2];
    } catch (_) {}
    return null;
  }

  void _preencherDadosIniciais(Map<String, dynamic> dados) {
    _controllers['nome']?.text = dados['nome'] ?? '';
    _controllers['apelido']?.text = dados['apelido'] ?? '';
    _controllers['cpf']?.text = dados['cpf'] ?? '';
    _controllers['data_nascimento']?.text = dados['data_nascimento'] ?? '';

    final endereco = dados['endereco'] ?? '';
    _controllers['rua']?.text = _extrairRua(endereco);
    _controllers['numero']?.text = _extrairNumero(endereco);
    _controllers['bairro']?.text = _extrairBairro(endereco);

    final cidade = _extrairCidade(endereco);
    if (cidade != null && cidade.isNotEmpty) {
      _controllers['cidade']?.text = cidade;
    }

    _enderecoCompletoController.text = endereco;
    _controllers['contato_aluno']?.text = dados['contato_aluno'] ?? '';
    _controllers['nome_responsavel']?.text = dados['nome_responsavel'] ?? '';
    _controllers['contato_responsavel']?.text =
        dados['contato_responsavel'] ?? '';
    _sexo = dados['sexo'];

    // 🔥 FOTO VINDO DA INSCRIÇÃO
    // A inscrição normalmente salva a foto em foto_url.
    // Ao aprovar, reaproveitamos essa mesma URL como foto de perfil do aluno,
    // mas o usuário ainda pode tocar na foto e tirar/carregar outra.
    final fotoInscricao =
    (dados['foto_url'] ??
        dados['foto_perfil_aluno'] ??
        dados['foto_aluno_url'] ??
        dados['imagem_url'] ??
        '')
        .toString()
        .trim();

    if (fotoInscricao.isNotEmpty) {
      _networkImageUrl = fotoInscricao;
      _fotoCarregada = true;
      _fotoVeioDaInscricao = true;
      debugPrint('📸 Foto da inscrição reaproveitada: $fotoInscricao');
    }
  }

  Future<void> _initializeData() async {
    try {
      await _carregarUsuarioLogado();
      await _fetchGraduacoes();
      await _loadTurmaData();

      if (!_isEditing) {
        try {
          final academiaDoc = await FirebaseFirestore.instance
              .collection('academias')
              .doc(widget.academiaId)
              .get();
          if (academiaDoc.exists) {
            final cidadeAcademia = academiaDoc.data()?['cidade'] ?? '';
            if (cidadeAcademia.isNotEmpty &&
                _controllers['cidade']!.text.isEmpty) {
              _controllers['cidade']!.text = cidadeAcademia;
            }
          }
        } catch (_) {}
      }

      if (_isFromInscricao) _preencherDadosIniciais(widget.dadosIniciais!);
      if (_isEditing) await _loadAlunoData();

      _safeSetState(() => _isLoading = false);
    } catch (e) {
      _safeSetState(() => _isLoading = false);
      if (_isMounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar dados: $e')));
      }
    }
  }

  Future<void> _loadTurmaData() async {
    try {
      final turmaDoc = await FirebaseFirestore.instance
          .collection('turmas')
          .doc(widget.turmaId)
          .get();
      if (turmaDoc.exists) {
        final data = turmaDoc.data()!;
        _safeSetState(() {
          _turmaData = data;
          final capacidadeMaxima = data['capacidade_maxima'] ?? 0;
          final alunosAtivos = data['alunos_ativos'] ?? 0;
          final alunosCount = data['alunos_count'] ?? 0;
          final totalAlunos = alunosAtivos > 0 ? alunosAtivos : alunosCount;
          _turmaCheia = capacidadeMaxima > 0 && totalAlunos >= capacidadeMaxima;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchGraduacoes() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('graduacoes')
          .orderBy('nivel_graduacao')
          .get();

      final Map<String, Map<String, dynamic>> dataMap = {};
      final items = <DropdownMenuItem<String>>[];
      items.add(
        const DropdownMenuItem(value: null, child: Text('Não informado')),
      );

      for (var doc in snapshot.docs) {
        final id = doc.id;
        final data = doc.data();
        dataMap[id] = data;
        final cor1 = _colorFromHex(data['hex_cor1']);
        final cor2 = _colorFromHex(data['hex_cor2']);
        items.add(
          DropdownMenuItem(
            value: id,
            child: Row(
              children: [
                Container(
                  width: 80,
                  height: 20,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      colors: [cor2, cor1],
                      stops: const [0.5, 0.5],
                    ),
                    border: Border.all(color: Colors.black38, width: 1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    data['nome_graduacao'] ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      _safeSetState(() {
        _graduacoesData = dataMap;
        _graduacaoItems = items;
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _loadAlunoData() async {
    try {
      if (widget.alunoId == null || widget.alunoId!.isEmpty) return;
      final doc = await FirebaseFirestore.instance
          .collection('alunos')
          .doc(widget.alunoId)
          .get();
      final data = doc.data();
      if (data == null) return;

      _controllers.forEach((key, controller) {
        if (data.containsKey(key) &&
            data[key] != null &&
            data[key] is! Timestamp) {
          controller.text = data[key].toString();
        }
      });

      if (data.containsKey('endereco') && data['endereco'] != null) {
        _parseEndereco(data['endereco'].toString());
        _enderecoCompletoController.text = data['endereco'].toString();
      }

      void safeSetDate(String fieldName, dynamic timestamp) {
        if (timestamp is Timestamp) {
          _controllers[fieldName]!.text = DateFormat(
            'dd/MM/yyyy',
          ).format(timestamp.toDate());
        }
      }

      safeSetDate('data_nascimento', data['data_nascimento']);
      safeSetDate('data_graduacao_atual', data['data_graduacao_atual']);
      safeSetDate('tempo_capoeira', data['tempo_capoeira']);

      if (_controllers['contato_aluno']!.text.isNotEmpty) {
        _controllers['contato_aluno']!.text = _formatPhoneNumber(
          _controllers['contato_aluno']!.text,
        );
      }
      if (_controllers['contato_responsavel']!.text.isNotEmpty) {
        _controllers['contato_responsavel']!.text = _formatPhoneNumber(
          _controllers['contato_responsavel']!.text,
        );
      }
      if (_controllers['cpf']!.text.isNotEmpty) {
        _controllers['cpf']!.text = _formatCpf(_controllers['cpf']!.text);
      }

      _safeSetState(() {
        _sexo = data['sexo'] as String?;
        _graduacaoId = data['graduacao_id'] as String?;
        _networkImageUrl = data['foto_perfil_aluno'] as String?;
        _fotoCarregada =
            _networkImageUrl != null && _networkImageUrl!.isNotEmpty;
      });
    } catch (e) {
      rethrow;
    }
  }

  void _parseEndereco(String enderecoCompleto) {
    if (enderecoCompleto.isEmpty) return;
    try {
      List<String> partes = enderecoCompleto.split(', ');
      if (partes.length >= 2) {
        String ruaNumero = partes[0];
        String resto = partes.sublist(1).join(', ');
        List<String> ruaNumeroParts = ruaNumero.split(' - ');
        if (ruaNumeroParts.length >= 1) {
          _controllers['rua']!.text = ruaNumeroParts[0];
          if (ruaNumeroParts.length >= 2)
            _controllers['numero']!.text = ruaNumeroParts[1];
        }
        List<String> restoParts = resto.split(', ');
        if (restoParts.length >= 2) {
          _controllers['bairro']!.text = restoParts[0];
          _controllers['cidade']!.text = restoParts[1];
        }
      }
    } catch (_) {}
  }

  Color _colorFromHex(String? hexColor) {
    if (hexColor == null || hexColor.length < 7) return Colors.grey;
    return Color(int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16));
  }

  Future<void> _selectDate(
      BuildContext context,
      TextEditingController controller,
      ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _parseDate(controller.text) ?? DateTime.now(),
      firstDate: DateTime(1920),
      lastDate: DateTime(2100),
    );
    if (picked != null && _isMounted) {
      _safeSetState(
            () => controller.text = DateFormat('dd/MM/yyyy').format(picked),
      );
    }
  }

  void _showImageSourceActionSheet() {
    if (!_isMounted) return;

    final bool temFotoAtual =
        _pickedImage != null ||
            (_networkImageUrl != null && _networkImageUrl!.isNotEmpty);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                child: Row(
                  children: [
                    Icon(
                      temFotoAtual
                          ? Icons.photo_camera_back
                          : Icons.add_a_photo,
                      color: Colors.red.shade900,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        temFotoAtual
                            ? 'Foto do aluno'
                            : 'Adicionar foto do aluno',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (temFotoAtual)
                ListTile(
                  leading: Icon(
                    Icons.check_circle,
                    color: Colors.green.shade700,
                  ),
                  title: Text(
                    _fotoVeioDaInscricao
                        ? 'Usar foto da inscrição'
                        : 'Manter foto atual',
                  ),
                  subtitle: const Text(
                    'Salvar usando a foto que já está na tela',
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                  },
                ),
              if (temFotoAtual)
                ListTile(
                  leading: Icon(
                    Icons.crop_rounded,
                    color: Colors.green.shade700,
                  ),
                  title: const Text('Editar foto atual'),
                  subtitle: Text(
                    _fotoVeioDaInscricao
                        ? 'Ajustar o enquadramento da foto da inscrição'
                        : 'Centralizar o rosto para aparecer certo nos cards',
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _editarFotoAluno();
                  },
                ),
              ListTile(
                leading: Icon(Icons.photo_library, color: Colors.red.shade900),
                title: const Text('Escolher nova foto da galeria'),
                subtitle: const Text('Selecionar outra imagem do celular'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt, color: Colors.red.shade900),
                title: const Text('Tirar nova foto com a câmera'),
                subtitle: const Text('Abrir a câmera do celular'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<File> _criarArquivoTemporarioSeguro(String prefixo) async {
    final baseDir = Directory.systemTemp;
    final dir = Directory('${baseDir.path}/uai_capoeira_fotos_editor');

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File(
      '${dir.path}/${prefixo}_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );

    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    return file;
  }

  Future<File?> _obterArquivoImagemParaEditar() async {
    try {
      if (_pickedImage != null) {
        final file = File(_pickedImage!.path);
        if (await file.exists()) return file;
      }

      final url = _networkImageUrl?.trim() ?? '';
      if (url.isEmpty ||
          (!url.startsWith('http://') && !url.startsWith('https://'))) {
        return null;
      }

      final request = await HttpClient().getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final bytesBuilder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        bytesBuilder.add(chunk);
      }

      final tempFile = await _criarArquivoTemporarioSeguro(
        'foto_inscricao_editar',
      );
      await tempFile.writeAsBytes(bytesBuilder.takeBytes(), flush: true);
      return tempFile;
    } catch (e) {
      debugPrint('Erro ao preparar foto para edição: $e');
      return null;
    }
  }

  Future<void> _editarFotoAluno() async {
    final imagemOrigem = await _obterArquivoImagemParaEditar();

    if (imagemOrigem == null) {
      if (!_isMounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecione, tire ou reaproveite uma foto primeiro para editar.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_isMounted) return;

    final arquivoEditado = await showDialog<File?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditorFotoAlunoDialog(
        imageFile: imagemOrigem,
        nomeAluno: _controllers['nome']?.text.trim() ?? 'Aluno',
      ),
    );

    if (arquivoEditado != null && _isMounted) {
      if (!await arquivoEditado.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Erro: a foto editada não foi encontrada. Tente novamente.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      _safeSetState(() {
        _pickedImage = XFile(arquivoEditado.path);
        _networkImageUrl = null;
        _fotoCarregada = true;
        _fotoVeioDaInscricao = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Foto ajustada! Toque em Salvar para enviar.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 50,
        maxWidth: 800,
      );
      if (image != null && _isMounted) {
        _safeSetState(() {
          _pickedImage = image;
          _networkImageUrl = null;
          _fotoCarregada = true;
          _fotoVeioDaInscricao = false;
        });
      }
    } catch (e) {
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao selecionar imagem: $e")),
        );
      }
    }
  }

  String _formatCpf(String value) {
    String digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 11) digits = digits.substring(0, 11);
    if (digits.length <= 3) return digits;
    if (digits.length <= 6)
      return '${digits.substring(0, 3)}.${digits.substring(3)}';
    if (digits.length <= 9)
      return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6)}';
    return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9, 11)}';
  }

  String _formatPhoneNumber(String value) {
    String digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 11) digits = digits.substring(0, 11);
    if (digits.length <= 2) return '($digits';
    if (digits.length <= 6)
      return '(${digits.substring(0, 2)}) ${digits.substring(2)}';
    if (digits.length <= 10)
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7, 11)}';
  }

  String _limparMascara(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

  String _montarEndereco() {
    if (_isFromInscricao && _enderecoCompletoController.text.isNotEmpty) {
      return _enderecoCompletoController.text;
    }
    List<String> partes = [];
    if (_controllers['rua']!.text.isNotEmpty) {
      String ruaNumero = _controllers['rua']!.text;
      if (_controllers['numero']!.text.isNotEmpty)
        ruaNumero += ' - ${_controllers['numero']!.text}';
      partes.add(ruaNumero);
    }
    if (_controllers['bairro']!.text.isNotEmpty)
      partes.add(_controllers['bairro']!.text);
    if (_controllers['cidade']!.text.isNotEmpty)
      partes.add(_controllers['cidade']!.text);
    return partes.join(', ');
  }

  // ==================== MÉTODOS PARA CONVITE ====================

  // Aplica as variáveis usadas no modelo da mensagem de convite.
  //
  // Aceita os dois formatos:
  // {nome_aluno} e {{nome_aluno}}
  // {turma_nome} e {{turma_nome}}
  // {academia_nome} e {{academia_nome}}
  //
  // Isso corrige o caso em que a mensagem estava indo com {{turma_nome}}
  // sem ser substituído pelo nome real da turma.
  String _aplicarVariaveisConvite(String mensagem) {
    final nomeAluno = _controllers['nome']!.text.trim();
    final turmaNome = widget.turmaNome.trim();
    final academiaNome = widget.academiaNome.trim();

    return mensagem
        .replaceAll('{{nome_aluno}}', nomeAluno)
        .replaceAll('{nome_aluno}', nomeAluno)
        .replaceAll('{{aluno_nome}}', nomeAluno)
        .replaceAll('{aluno_nome}', nomeAluno)
        .replaceAll('{{turma_nome}}', turmaNome)
        .replaceAll('{turma_nome}', turmaNome)
        .replaceAll('{{nome_turma}}', turmaNome)
        .replaceAll('{nome_turma}', turmaNome)
        .replaceAll('{{academia_nome}}', academiaNome)
        .replaceAll('{academia_nome}', academiaNome)
        .replaceAll('{{nome_academia}}', academiaNome)
        .replaceAll('{nome_academia}', academiaNome);
  }

  Future<String> _buscarMensagemConvite() async {
    try {
      final turmaDoc = await FirebaseFirestore.instance
          .collection('turmas')
          .doc(widget.turmaId)
          .get(const GetOptions(source: Source.server));

      if (turmaDoc.exists) {
        final data = turmaDoc.data();
        String msg = data?['msg_convite_grupo_whatsapp'] as String? ?? '';

        if (msg.trim().isNotEmpty) {
          return _aplicarVariaveisConvite(msg);
        }
      }
    } catch (e) {
      debugPrint('Erro ao buscar mensagem de convite: $e');
    }

    // Mensagem padrão
    return _aplicarVariaveisConvite(
      '🥋 SEJA BEM-VINDO(A) AO GRUPO UAI CAPOEIRA! 🥋\n\n'
          'Olá {nome_aluno}, seja muito bem-vindo(a)! 👊\n'
          'Este é o canal oficial da Turma {turma_nome}.',
    );
  }

  Future<String?> _buscarLinkGrupo() async {
    try {
      final turmaDoc = await FirebaseFirestore.instance
          .collection('turmas')
          .doc(widget.turmaId)
          .get(const GetOptions(source: Source.server));
      if (turmaDoc.exists) {
        return turmaDoc.data()?['whatsapp_url'] as String?;
      }
    } catch (e) {
      debugPrint('Erro ao buscar link do grupo: $e');
    }
    return null;
  }

  Future<void> _enviarWhatsApp(String numero, String mensagem) async {
    String cleanedPhone = numero.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanedPhone.startsWith('0')) cleanedPhone = cleanedPhone.substring(1);
    if (!cleanedPhone.startsWith('55')) cleanedPhone = '55$cleanedPhone';
    final encodedMessage = Uri.encodeComponent(mensagem);
    final url = 'https://wa.me/$cleanedPhone?text=$encodedMessage';
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o WhatsApp.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _areaAlunoEstaAtivaNoSite() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('configuracoes_site')
          .doc('area_aluno')
          .get(const GetOptions(source: Source.server));

      final data = doc.data();

      return data?['visivel_site'] == true;
    } catch (e) {
      debugPrint('Erro ao verificar Área do Aluno ativa: $e');
      return false;
    }
  }

  String _gerarIniciaisAreaAluno(String nomeCompleto) {
    final ignorar = {'DE', 'DA', 'DO', 'DAS', 'DOS', 'E'};

    final partes = nomeCompleto
        .trim()
        .toUpperCase()
        .split(RegExp(r'\s+'))
        .where((parte) => parte.trim().isNotEmpty)
        .where((parte) => !ignorar.contains(parte.trim()))
        .toList();

    final iniciais = partes.map((parte) {
      final texto = parte.trim();
      return texto.isEmpty ? '' : texto.substring(0, 1);
    }).join();

    return iniciais.replaceAll(RegExp(r'[^A-ZÀ-Ú0-9]'), '');
  }

  String _ultimos4DigitosTelefoneAreaAluno({
    required String contatoAluno,
    required String contatoResponsavel,
  }) {
    final aluno = _limparMascara(contatoAluno);
    final responsavel = _limparMascara(contatoResponsavel);

    final base = aluno.length >= 8 ? aluno : responsavel;

    if (base.length < 4) return '';

    return base.substring(base.length - 4);
  }

  String _montarMensagemAcessoAreaAluno() {
    final nomeAluno = _controllers['nome']!.text.trim();
    final dataNascimento = _controllers['data_nascimento']!.text.trim();
    final contatoAluno = _controllers['contato_aluno']!.text.trim();
    final contatoResponsavel = _controllers['contato_responsavel']!.text.trim();

    final iniciais = _gerarIniciaisAreaAluno(nomeAluno);
    final telefoneFinal = _ultimos4DigitosTelefoneAreaAluno(
      contatoAluno: contatoAluno,
      contatoResponsavel: contatoResponsavel,
    );

    return '''
🥋 ÁREA DO ALUNO - UAI CAPOEIRA 🥋

Olá! Seguem os dados para acessar a Área do Aluno de $nomeAluno.

🌐 Acesse o site:
http://uaicapoeira.com.br

No site, toque em *Área do Aluno* e preencha:

📅 Data de nascimento: *$dataNascimento*
🔤 Iniciais do nome: *$iniciais*
📱 Últimos 4 dígitos do telefone: *$telefoneFinal*

✅ Depois de entrar, será possível consultar dados, turma, frequência, eventos e certificados.

⚠️ Não compartilhe esses dados com outras pessoas.
'''.trim();
  }

  bool _dadosAcessoAreaAlunoValidos() {
    final nomeAluno = _controllers['nome']!.text.trim();
    final dataNascimento = _controllers['data_nascimento']!.text.trim();
    final contatoAluno = _controllers['contato_aluno']!.text.trim();
    final contatoResponsavel = _controllers['contato_responsavel']!.text.trim();

    final iniciais = _gerarIniciaisAreaAluno(nomeAluno);
    final telefoneFinal = _ultimos4DigitosTelefoneAreaAluno(
      contatoAluno: contatoAluno,
      contatoResponsavel: contatoResponsavel,
    );

    return nomeAluno.isNotEmpty &&
        dataNascimento.isNotEmpty &&
        iniciais.isNotEmpty &&
        telefoneFinal.isNotEmpty;
  }

  Future<void> _mostrarDialogoConviteWhatsApp() async {
    final nomeAluno = _controllers['nome']!.text.trim();
    final contatoAluno = _limparMascara(
      _controllers['contato_aluno']!.text.trim(),
    );
    final contatoResponsavel = _limparMascara(
      _controllers['contato_responsavel']!.text.trim(),
    );

    final temContatoAluno = contatoAluno.length >= 8;
    final temContatoResponsavel = contatoResponsavel.length >= 8;

    if (!temContatoAluno && !temContatoResponsavel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Aluno cadastrado com sucesso! Nenhum contato válido para WhatsApp.'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    String mensagemBase = await _buscarMensagemConvite();
    mensagemBase = _aplicarVariaveisConvite(mensagemBase);

    final String? linkGrupo = await _buscarLinkGrupo();
    final bool temGrupo = linkGrupo != null && linkGrupo.trim().isNotEmpty;

    final String mensagemGrupo = temGrupo
        ? '$mensagemBase\n\n👇 ENTRE NO GRUPO PELO LINK ABAIXO:\n$linkGrupo'
        : '';

    final bool areaAlunoAtiva = await _areaAlunoEstaAtivaNoSite();
    final bool dadosAreaAlunoOk = _dadosAcessoAreaAlunoValidos();
    final String mensagemAreaAluno =
    areaAlunoAtiva && dadosAreaAlunoOk ? _montarMensagemAcessoAreaAluno() : '';

    if (!temGrupo && !areaAlunoAtiva) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Aluno cadastrado com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    Widget buildBotaoEnvio({
      required String label,
      required IconData icon,
      required Color color,
      required String numero,
      required String mensagem,
      required String snack,
    }) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () async {
            await _enviarWhatsApp(numero, mensagem);

            if (_isMounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(snack),
                  backgroundColor: Colors.green,
                ),
              );
            }
          },
          icon: Icon(icon, size: 19),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
    }

    Widget buildSecao({
      required IconData icon,
      required Color color,
      required String titulo,
      required String descricao,
      required List<Widget> botoes,
      String? aviso,
    }) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 39,
                  height: 39,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        descricao,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 11.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (aviso != null && aviso.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade100),
                ),
                child: Text(
                  aviso,
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
            ],
            if (botoes.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...botoes.map(
                    (botao) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: botao,
                ),
              ),
            ],
          ],
        ),
      );
    }

    final botoesGrupo = <Widget>[];

    if (temGrupo && temContatoAluno) {
      botoesGrupo.add(
        buildBotaoEnvio(
          label: 'Convidar aluno • $nomeAluno',
          icon: Icons.person_rounded,
          color: Colors.green.shade700,
          numero: contatoAluno,
          mensagem: mensagemGrupo,
          snack: 'Convite do grupo enviado para o aluno!',
        ),
      );
    }

    if (temGrupo && temContatoResponsavel && contatoResponsavel != contatoAluno) {
      botoesGrupo.add(
        buildBotaoEnvio(
          label: 'Convidar responsável',
          icon: Icons.family_restroom_rounded,
          color: Colors.blue.shade700,
          numero: contatoResponsavel,
          mensagem: mensagemGrupo,
          snack: 'Convite do grupo enviado para o responsável!',
        ),
      );
    }

    final botoesAreaAluno = <Widget>[];

    if (areaAlunoAtiva && dadosAreaAlunoOk && temContatoAluno) {
      botoesAreaAluno.add(
        buildBotaoEnvio(
          label: 'Enviar acesso para aluno • $nomeAluno',
          icon: Icons.person_rounded,
          color: Colors.green.shade700,
          numero: contatoAluno,
          mensagem: mensagemAreaAluno,
          snack: 'Dados da Área do Aluno enviados para o aluno!',
        ),
      );
    }

    if (areaAlunoAtiva &&
        dadosAreaAlunoOk &&
        temContatoResponsavel &&
        contatoResponsavel != contatoAluno) {
      botoesAreaAluno.add(
        buildBotaoEnvio(
          label: 'Enviar acesso para responsável',
          icon: Icons.family_restroom_rounded,
          color: Colors.blue.shade700,
          numero: contatoResponsavel,
          mensagem: mensagemAreaAluno,
          snack: 'Dados da Área do Aluno enviados para o responsável!',
        ),
      );
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.all(14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
          actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade700, size: 30),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Cadastro realizado!',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.of(context).size.height * 0.68,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$nomeAluno foi cadastrado com sucesso na turma ${widget.turmaNome}.',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  if (temGrupo)
                    buildSecao(
                      icon: Icons.group_add_rounded,
                      color: Colors.green,
                      titulo: 'Grupo do WhatsApp',
                      descricao:
                      'Envie o link do grupo com a mensagem personalizada da turma.',
                      botoes: botoesGrupo,
                    )
                  else
                    buildSecao(
                      icon: Icons.group_off_rounded,
                      color: Colors.grey,
                      titulo: 'Grupo do WhatsApp',
                      descricao: 'Essa turma não possui link de grupo cadastrado.',
                      botoes: const [],
                    ),
                  if (areaAlunoAtiva)
                    buildSecao(
                      icon: Icons.school_rounded,
                      color: Colors.red.shade900,
                      titulo: 'Área do Aluno',
                      descricao:
                      'Envie os dados de acesso para o aluno ou responsável.',
                      aviso: dadosAreaAlunoOk
                          ? 'Para crianças, o ideal é enviar para o responsável.'
                          : 'Não foi possível montar os dados de acesso. Confira data de nascimento, nome e telefone.',
                      botoes: botoesAreaAluno,
                    )
                  else
                    buildSecao(
                      icon: Icons.visibility_off_rounded,
                      color: Colors.grey,
                      titulo: 'Área do Aluno',
                      descricao:
                      'A Área do Aluno está desativada no site, por isso os botões de acesso não aparecem.',
                      botoes: const [],
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'CONCLUIR',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _moverInscricaoParaAprovadas(String alunoId) async {
    if (!_isFromInscricao || widget.dadosIniciais == null) return;
    final inscricaoId = widget.dadosIniciais?['id'];
    if (inscricaoId == null) return;
    try {
      final inscricaoDoc = await FirebaseFirestore.instance
          .collection('inscricoes')
          .doc(inscricaoId)
          .get();
      if (!inscricaoDoc.exists) return;
      final dadosInscricao = inscricaoDoc.data()!;
      final dadosAprovados = {
        ...dadosInscricao,
        'aluno_id': alunoId,
        'aluno_nome': _controllers['nome']!.text,
        'aluno_apelido': _controllers['apelido']!.text,
        'turma_id': widget.turmaId,
        'turma_nome': widget.turmaNome,
        'academia_id': widget.academiaId,
        'academia_nome': widget.academiaNome,
        'aprovado_em': FieldValue.serverTimestamp(),
        'aprovado_por': _usuarioLogadoNome ?? _usuarioLogadoEmail ?? 'Sistema',
        'aprovado_por_uid': _usuarioLogadoUid,
        'status': 'aprovado',
      };
      await FirebaseFirestore.instance
          .collection('inscricoes_aprovadas')
          .doc(inscricaoId)
          .set(dadosAprovados);
      await FirebaseFirestore.instance
          .collection('inscricoes')
          .doc(inscricaoId)
          .delete();
    } catch (e) {
      debugPrint('Erro ao mover inscrição: $e');
    }
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate() || !_isMounted) return;

    if (_turmaCheia) {
      final capacidadeMaxima = _turmaData['capacidade_maxima'] ?? 0;
      final alunosAtivos = _turmaData['alunos_ativos'] ?? 0;
      final alunosCount = _turmaData['alunos_count'] ?? 0;
      final totalAlunos = alunosAtivos > 0 ? alunosAtivos : alunosCount;
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ Turma "${widget.turmaNome}" está cheia! ($totalAlunos/$capacidadeMaxima alunos)',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!_fotoCarregada &&
        (_pickedImage == null &&
            (_networkImageUrl == null || _networkImageUrl!.isEmpty))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foto de perfil é obrigatória'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _safeSetState(() => _salvando = true);

    try {
      if (_pickedImage != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('foto_alunos')
            .child('${widget.alunoId ?? UniqueKey().toString()}.jpg');
        await ref.putFile(File(_pickedImage!.path));
        _networkImageUrl = await ref.getDownloadURL();
      }

      Map<String, dynamic> dataToSave = {};

      _controllers.forEach((key, controller) {
        if (key == 'contato_aluno' || key == 'contato_responsavel') {
          dataToSave[key] = _limparMascara(controller.text.trim());
        } else if (key == 'cpf') {
          dataToSave[key] = _limparMascara(controller.text.trim());
        } else if (dateKeys.contains(key)) {
          if (controller.text.trim().isNotEmpty) {
            final date = _parseDate(controller.text.trim());
            if (date != null) dataToSave[key] = Timestamp.fromDate(date);
          } else if (key == 'tempo_capoeira') {
            dataToSave[key] = Timestamp.fromDate(DateTime.now());
          }
        } else if (key != 'rua' && key != 'numero' && key != 'bairro') {
          final text = controller.text.trim();
          if (text.isNotEmpty) dataToSave[key] = text;
        }
      });

      dataToSave['endereco'] = _montarEndereco();
      if (_controllers['cidade']!.text.trim().isNotEmpty)
        dataToSave['cidade'] = _controllers['cidade']!.text.trim();
      dataToSave['academia_id'] = widget.academiaId;
      dataToSave['academia'] = widget.academiaNome;
      dataToSave['turma_id'] = widget.turmaId;
      dataToSave['turma'] = widget.turmaNome;

      final graduacaoRef = _graduacaoId != null
          ? FirebaseFirestore.instance
          .collection('graduacoes')
          .doc(_graduacaoId)
          : null;
      final graduacaoData = _graduacaoId != null
          ? _graduacoesData[_graduacaoId]
          : null;

      final camposObrigatorios = {
        'sexo': _sexo,
        'status_atividade': 'ATIVO(A)',
        'foto_perfil_aluno': _networkImageUrl,
        'atualizado_em': FieldValue.serverTimestamp(),
        'editavel': true,
      };

      if (_graduacaoId != null) {
        dataToSave['graduacao_id'] = _graduacaoId;
        dataToSave['graduacao_ref'] = graduacaoRef;
        if (graduacaoData != null) {
          final camposGraduacao = {
            'graduacao_nome': graduacaoData['nome_graduacao'],
            'graduacao_cor1': graduacaoData['hex_cor1'],
            'graduacao_cor2': graduacaoData['hex_cor2'],
            'graduacao_ponta1': graduacaoData['hex_ponta1'],
            'graduacao_ponta2': graduacaoData['hex_ponta2'],
          };
          camposGraduacao.removeWhere((key, value) => value == null);
          dataToSave.addAll(camposGraduacao);
        }
      }

      if (_controllers['cpf']!.text.trim().isNotEmpty)
        dataToSave['cpf'] = _limparMascara(_controllers['cpf']!.text.trim());
      dataToSave.addAll(camposObrigatorios);

      if (_isEditing) {
        await FirebaseFirestore.instance
            .collection('alunos')
            .doc(widget.alunoId)
            .update(dataToSave);
        await _atualizarContadorTurma();
        if (_isMounted) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Aluno atualizado com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        dataToSave['criado_em'] = FieldValue.serverTimestamp();
        dataToSave['data_do_cadastro'] = FieldValue.serverTimestamp();
        dataToSave['cadastro_realizado_por'] =
            _usuarioLogadoNome ?? _usuarioLogadoEmail ?? 'Sistema';
        dataToSave['cadastro_realizado_por_uid'] = _usuarioLogadoUid;
        dataToSave['cadastro_realizado_em'] = FieldValue.serverTimestamp();
        if (!dataToSave.containsKey('tempo_capoeira'))
          dataToSave['tempo_capoeira'] = FieldValue.serverTimestamp();

        final docRef = await FirebaseFirestore.instance
            .collection('alunos')
            .add(dataToSave);
        await _atualizarContadorTurma();

        if (_isFromInscricao && widget.dadosIniciais?['id'] != null) {
          await docRef.update({'inscricao_id': widget.dadosIniciais!['id']});
        }

        if (_isFromInscricao) await _moverInscricaoParaAprovadas(docRef.id);

        // 🔥 CORREÇÃO: Exibe o diálogo de convite ANTES de fechar a tela
        if (_isMounted) {
          await _mostrarDialogoConviteWhatsApp();
          // Fecha a tela de cadastro APÓS o diálogo
          if (mounted) Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _safeSetState(() => _salvando = false);
    }
  }

  Future<void> _atualizarContadorTurma() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('alunos')
          .where('turma_id', isEqualTo: widget.turmaId)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get();
      final alunosCount = snapshot.docs.length;
      await FirebaseFirestore.instance
          .collection('turmas')
          .doc(widget.turmaId)
          .update({
        'alunos_count': alunosCount,
        'alunos_ativos': alunosCount,
        'atualizado_em': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Erro ao atualizar contador da turma: $e');
    }
  }

  final List<String> dateKeys = const [
    'data_nascimento',
    'data_graduacao_atual',
    'tempo_capoeira',
  ];

  Future<void> _deleteAluno() async {
    if (!_isEditing || !_isMounted) return;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirmar Exclusão"),
        content: Text(
          "Você tem certeza que deseja excluir o aluno(a) ${_controllers['nome']!.text}?\n\nEsta ação é permanente e irreversível.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("EXCLUIR"),
          ),
        ],
      ),
    );
    if (shouldDelete == true) {
      try {
        if (_networkImageUrl != null && _networkImageUrl!.isNotEmpty) {
          try {
            await FirebaseStorage.instance
                .refFromURL(_networkImageUrl!)
                .delete();
          } catch (_) {}
        }
        await FirebaseFirestore.instance
            .collection('alunos')
            .doc(widget.alunoId)
            .delete();
        await _atualizarContadorTurma();
        if (_isMounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Aluno excluído com sucesso.")),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e) {
        if (_isMounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Erro ao excluir aluno: $e")));
      }
    }
  }

  DateTime? _parseDate(String dateStr) {
    if (dateStr.isEmpty) return null;
    try {
      return DateFormat('dd/MM/yyyy').parseStrict(dateStr);
    } catch (e) {
      return null;
    }
  }

  // ==================== WIDGETS ====================
  Widget _buildFotoSection() {
    final bool temFotoAtual =
        _pickedImage != null ||
            (_networkImageUrl != null && _networkImageUrl!.isNotEmpty);

    final ImageProvider? imageProvider = _pickedImage != null
        ? FileImage(File(_pickedImage!.path))
        : (_networkImageUrl != null && _networkImageUrl!.isNotEmpty
        ? CachedNetworkImageProvider(_networkImageUrl!)
        : null);

    return Column(
      children: [
        GestureDetector(
          onTap: _salvando ? null : _showImageSourceActionSheet,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 60,
                backgroundColor: Colors.grey[300],
                backgroundImage: imageProvider,
                child: imageProvider == null
                    ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.camera_alt, size: 40),
                    Text(
                      'Adicionar Foto',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                )
                    : null,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.edit, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_fotoVeioDaInscricao && _pickedImage == null)
          Text(
            'Foto reaproveitada da inscrição',
            style: TextStyle(
              color: Colors.green.shade700,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          )
        else if (temFotoAtual)
          Text(
            'Toque para trocar a foto',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        if (!_fotoCarregada && !temFotoAtual)
          const Text(
            'Foto de perfil é obrigatória',
            style: TextStyle(color: Colors.red, fontSize: 12),
          ),
      ],
    );
  }

  Widget _buildInfoTurma() {
    final capacidadeMaxima = _turmaData['capacidade_maxima'] ?? 0;
    final alunosAtivos = _turmaData['alunos_ativos'] ?? 0;
    final alunosCount = _turmaData['alunos_count'] ?? 0;
    final totalAlunos = alunosAtivos > 0 ? alunosAtivos : alunosCount;
    final horario =
        _turmaData['horario_display'] ?? _turmaData['horario'] ?? '';
    final nivel = _turmaData['nivel'] ?? '';
    final faixaEtaria = _turmaData['faixa_etaria'] ?? '';

    return Card(
      color: _turmaCheia ? Colors.red.shade50 : Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.school,
                  color: _turmaCheia ? Colors.red : Colors.blue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.academiaNome,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _turmaCheia ? Colors.red : Colors.blue,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        widget.turmaNome,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (horario.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    horario,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ],
            if (nivel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.star, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    nivel,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ],
            if (faixaEtaria.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.people, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    faixaEtaria,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Capacidade:',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  '$totalAlunos/$capacidadeMaxima',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _turmaCheia ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
            if (_turmaCheia) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.warning, size: 16, color: Colors.red),
                  const SizedBox(width: 6),
                  const Text(
                    'TURMA CHEIA',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Aluno será cadastrado automaticamente nesta turma',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnderecoSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildSectionTitle('Endereço'),
      if (_isFromInscricao && _enderecoCompletoController.text.isNotEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Endereço da inscrição:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _enderecoCompletoController.text,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                'Você pode alterar os campos abaixo se necessário',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 16),
      if (_isEditing && _controllers['rua']!.text.isNotEmpty)
        _buildTextField(
          _controllers['rua']!,
          'Endereço Completo',
          isRequired: true,
          maxLines: 2,
        )
      else
        Column(
          children: [
            _buildTextField(_controllers['rua']!, 'Rua', isRequired: true),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildTextField(
                    _controllers['numero']!,
                    'Número',
                    isRequired: true,
                    isNumberOnly: true,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: _buildTextField(
                    _controllers['bairro']!,
                    'Bairro',
                    isRequired: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildTextField(
              _controllers['cidade']!,
              'Cidade',
              isRequired: true,
            ),
          ],
        ),
    ],
  );

  Widget _buildGraduacaoSection() => Column(
    children: [
      DropdownButtonFormField<String>(
        value: _graduacaoId,
        items: _graduacaoItems,
        onChanged: _salvando ? null : (v) => setState(() => _graduacaoId = v),
        decoration: const InputDecoration(
          labelText: 'Graduação Atual (opcional)',
          border: OutlineInputBorder(),
        ),
        isExpanded: true,
        selectedItemBuilder: (context) => _graduacaoItems
            .map(
              (item) => Text(
            item.value == null
                ? "Não informado"
                : (_graduacoesData[item.value!]?['nome_graduacao'] ?? ''),
            overflow: TextOverflow.ellipsis,
          ),
        )
            .toList(),
      ),
      const SizedBox(height: 16),
      _buildDateField(
        _controllers['data_graduacao_atual']!,
        'Data da Graduação (opcional)',
        isRequired: false,
      ),
      const SizedBox(height: 16),
      _buildDateField(
        _controllers['tempo_capoeira']!,
        'Início na Capoeira (opcional)',
        isRequired: false,
      ),
    ],
  );

  Widget _buildStatusContainer() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.green.shade50,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.green.shade200),
    ),
    child: Row(
      children: [
        Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
        const SizedBox(width: 8),
        const Text(
          'Status: ATIVO(A)',
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );

  Widget _buildSectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(color: Colors.red.shade900),
    ),
  );

  Widget _buildCpfField() => TextFormField(
    controller: _controllers['cpf'],
    readOnly: _salvando,
    decoration: const InputDecoration(
      labelText: 'CPF (opcional)',
      hintText: '000.000.000-00',
      border: OutlineInputBorder(),
    ),
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(11),
      _CpfInputFormatter(),
    ],
    validator: (value) {
      if (value != null && value.isNotEmpty) {
        final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length != 11) return 'CPF deve ter 11 dígitos';
      }
      return null;
    },
  );

  Widget _buildPhoneField(
      TextEditingController controller,
      String label, {
        bool isRequired = true,
      }) => TextFormField(
    controller: controller,
    readOnly: _salvando,
    decoration: InputDecoration(
      labelText: '$label${isRequired ? ' *' : ''}',
      hintText: '(00) 00000-0000',
      border: const OutlineInputBorder(),
    ),
    keyboardType: TextInputType.phone,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(11),
      _PhoneInputFormatter(),
    ],
    validator: (value) {
      if (isRequired) {
        if (value == null || value.trim().isEmpty) return 'Campo obrigatório';
        final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length != 11)
          return 'Telefone deve ter 11 dígitos (DDD + 9 números)';
      }
      return null;
    },
  );

  TextFormField _buildTextField(
      TextEditingController controller,
      String label, {
        TextInputType keyboardType = TextInputType.text,
        bool isRequired = true,
        bool isNumberOnly = false,
        int maxLines = 1,
      }) => TextFormField(
    controller: controller,
    readOnly: _salvando,
    maxLines: maxLines,
    decoration: InputDecoration(
      labelText: '$label${isRequired ? ' *' : ''}',
      border: const OutlineInputBorder(),
    ),
    keyboardType: isNumberOnly ? TextInputType.number : keyboardType,
    inputFormatters: isNumberOnly
        ? [FilteringTextInputFormatter.digitsOnly]
        : [],
    validator: (value) => (isRequired && (value == null || value.isEmpty))
        ? 'Campo obrigatório'
        : null,
  );

  TextFormField _buildDateField(
      TextEditingController controller,
      String label, {
        bool isRequired = true,
      }) => TextFormField(
    controller: controller,
    readOnly: _salvando,
    decoration: InputDecoration(
      labelText: '$label${isRequired ? ' *' : ''}',
      suffixIcon: const Icon(Icons.calendar_today),
      border: const OutlineInputBorder(),
    ),
    onTap: _salvando ? null : () => _selectDate(context, controller),
    validator: (value) => (isRequired && (value == null || value.isEmpty))
        ? 'Campo obrigatório'
        : null,
  );

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_salvando) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Editar Aluno' : 'Cadastrar Novo Aluno'),
          backgroundColor: Colors.red.shade900,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                color: Colors.red,
                strokeWidth: 3,
              ),
              const SizedBox(height: 24),
              Text(
                _isEditing ? 'Salvando alterações...' : 'Cadastrando aluno...',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Por favor, aguarde',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Aluno' : 'Cadastrar Novo Aluno'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveForm,
            tooltip: "Salvar Alterações",
          ),
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteAluno,
              tooltip: "Excluir Aluno",
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildInfoTurma(),
              const SizedBox(height: 16),
              _buildFotoSection(),
              const SizedBox(height: 16),
              _buildSectionTitle('Dados Pessoais'),
              _buildTextField(
                _controllers['nome']!,
                'Nome do Aluno',
                isRequired: true,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                _controllers['apelido']!,
                'Apelido',
                isRequired: true,
              ),
              const SizedBox(height: 16),
              _buildCpfField(),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _sexo,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Selecione o sexo'),
                  ),
                  ...[
                    'MASCULINO',
                    'FEMININO',
                  ].map((e) => DropdownMenuItem(value: e, child: Text(e))),
                ],
                onChanged: _salvando ? null : (v) => setState(() => _sexo = v),
                decoration: const InputDecoration(
                  labelText: 'Sexo',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 16),
              _buildDateField(
                _controllers['data_nascimento']!,
                'Data de Nascimento',
                isRequired: true,
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('Contato'),
              _buildPhoneField(
                _controllers['contato_aluno']!,
                'Contato do Aluno',
                isRequired: true,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                _controllers['nome_responsavel']!,
                'Nome do Responsável',
                isRequired: true,
              ),
              const SizedBox(height: 16),
              _buildPhoneField(
                _controllers['contato_responsavel']!,
                'Contato do Responsável',
                isRequired: true,
              ),
              const SizedBox(height: 16),
              _buildEnderecoSection(),
              const SizedBox(height: 16),
              _buildSectionTitle('Dados da Capoeira'),
              _buildGraduacaoSection(),
              const SizedBox(height: 16),
              _buildStatusContainer(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== FORMATTERS ====================
class _CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 11) digits = digits.substring(0, 11);
    String formatted = '';
    if (digits.length <= 3)
      formatted = digits;
    else if (digits.length <= 6)
      formatted = '${digits.substring(0, 3)}.${digits.substring(3)}';
    else if (digits.length <= 9)
      formatted =
      '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6)}';
    else
      formatted =
      '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9)}';
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
    if (digits.length <= 2)
      formatted = '($digits';
    else if (digits.length <= 6)
      formatted = '(${digits.substring(0, 2)}) ${digits.substring(2)}';
    else if (digits.length <= 10)
      formatted =
      '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6)}';
    else
      formatted =
      '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7, 11)}';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ==================== EDITOR DE FOTO DO ALUNO ====================
class _EditorFotoAlunoDialog extends StatefulWidget {
  final File imageFile;
  final String nomeAluno;

  const _EditorFotoAlunoDialog({
    required this.imageFile,
    required this.nomeAluno,
  });

  @override
  State<_EditorFotoAlunoDialog> createState() => _EditorFotoAlunoDialogState();
}

class _EditorFotoAlunoDialogState extends State<_EditorFotoAlunoDialog> {
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
      final bytes = await widget.imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);

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

      // No preview, o slider move a IMAGEM dentro do quadro.
      // No recorte real, a janela de corte precisa mover no sentido contrário.
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

      final jpg = img.encodeJpg(resized, quality: 86);

      final baseDir = Directory.systemTemp;
      final dir = Directory('${baseDir.path}/uai_capoeira_fotos_editor');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final output = File(
        '${dir.path}/foto_aluno_crop_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      if (!await output.parent.exists()) {
        await output.parent.create(recursive: true);
      }

      await output.writeAsBytes(jpg, flush: true);

      if (!await output.exists()) {
        throw Exception('Arquivo editado não foi criado.');
      }

      if (!mounted) return;
      Navigator.pop(context, output);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao editar foto: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nome = widget.nomeAluno.trim().isEmpty
        ? 'Aluno'
        : widget.nomeAluno.trim();

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
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
                    const Icon(Icons.crop_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Editar foto do aluno',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
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
                      onPressed: _salvando
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
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
                        'Use o card como referência: deixe o rosto bem no centro para aparecer certo nos cards do app.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                          height: 1.3,
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
                              onPressed: _salvando
                                  ? null
                                  : _salvarImagemEditada,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade900,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
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
                              label: Text(
                                _salvando ? 'Salvando...' : 'Aplicar',
                              ),
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
                            child: Image.file(
                              widget.imageFile,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: _GuiaRostoPainter()),
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
                        'Prévia no card',
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
                    width: 128,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 17,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Presente',
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

class _GuiaRostoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final center = Offset(size.width / 2, size.height * 0.42);
    final oval = Rect.fromCenter(
      center: center,
      width: size.width * 0.46,
      height: size.height * 0.36,
    );

    canvas.drawOval(oval, paint);

    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      linePaint,
    );
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
