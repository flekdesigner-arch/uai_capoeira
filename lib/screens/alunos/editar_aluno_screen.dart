import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 👈 ADICIONAR
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;

// 🔐 IMPORTAR SERVIÇO DE PERMISSÕES
class PermissaoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final PermissaoService _instance = PermissaoService._internal();
  factory PermissaoService() => _instance;
  PermissaoService._internal();

  final Map<String, Map<String, bool>> _cache = {};

  Future<Map<String, bool>> carregarPermissoes(String userId) async {
    if (_cache.containsKey(userId)) {
      return _cache[userId]!;
    }

    try {
      final doc = await _firestore
          .collection('usuarios')
          .doc(userId)
          .collection('permissoes_usuario')
          .doc('configuracoes')
          .get();

      if (doc.exists) {
        final permissoes = doc.data()?.map((key, value) =>
            MapEntry(key, value as bool? ?? false)) ?? {};
        _cache[userId] = permissoes;
        return permissoes;
      }
    } catch (e) {
      print('Erro ao carregar permissões: $e');
    }
    return {};
  }

  Future<bool> temPermissao(String userId, String permissao) async {
    final permissoes = await carregarPermissoes(userId);
    return permissoes[permissao] ?? false;
  }

  Future<bool> isAdmin(String userId) async {
    try {
      final doc = await _firestore
          .collection('usuarios')
          .doc(userId)
          .get();

      if (doc.exists) {
        final peso = doc.data()?['peso_permissao'] as int? ?? 0;
        return peso >= 90;
      }
    } catch (e) {
      print('Erro ao verificar admin: $e');
    }
    return false;
  }

  void limparCache(String userId) {
    _cache.remove(userId);
  }
}

class EditarAlunoScreen extends StatefulWidget {
  final String? alunoId;

  const EditarAlunoScreen({super.key, this.alunoId});

  @override
  State<EditarAlunoScreen> createState() => _EditarAlunoScreenState();
}

class _EditarAlunoScreenState extends State<EditarAlunoScreen> {
  final _formKey = GlobalKey<FormState>();
  bool get _isEditing => widget.alunoId != null;

  // 🔐 PERMISSÕES
  final PermissaoService _permissaoService = PermissaoService();
  String? _currentUserId;
  Map<String, bool> _permissoes = {};
  bool _isAdmin = false;
  bool _carregandoPermissoes = true;
  bool _verificouPermissoes = false;

  final Map<String, TextEditingController> _controllers = {
    'nome': TextEditingController(),
    'cpf': TextEditingController(),
    'apelido': TextEditingController(),
    'data_nascimento': TextEditingController(),
    'data_graduacao_atual': TextEditingController(),
    'tempo_capoeira': TextEditingController(),
    'endereco': TextEditingController(),
    'contato_aluno': TextEditingController(),
    'nome_responsavel': TextEditingController(),
    'contato_responsavel': TextEditingController(),
    'cidade': TextEditingController(),
  };

  // Campos para academia e turma
  String? _academiaId;
  String? _academiaNome;
  String? _turmaId;
  String? _turmaNome;

  List<DropdownMenuItem<String>> _academiaItems = [];
  List<DropdownMenuItem<String>> _turmaItems = [];

  Map<String, String> _academiasMap = {}; // ID -> Nome
  Map<String, Map<String, dynamic>> _turmasMap = {}; // ID -> dados da turma

  String? _sexo;
  String? _statusAtividade = 'ATIVO(A)';
  String? _graduacaoId;
  List<DropdownMenuItem<String>> _graduacaoItems = [];
  Map<String, Map<String, dynamic>> _graduacoesData = {};
  XFile? _pickedImage;
  String? _networkImageUrl;

  bool _isLoading = true;
  bool _carregandoTurmas = false;
  bool _turmaCheia = false;
  bool _isMounted = false;

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    _carregarUsuarioLogado(); // 🔥 CARREGAR USUÁRIO PRIMEIRO
    _initializeData();
  }

  @override
  void dispose() {
    _isMounted = false;
    _controllers.forEach((_, controller) {
      controller.dispose();
    });
    super.dispose();
  }

  void _safeSetState(VoidCallback callback) {
    if (_isMounted) {
      setState(callback);
    }
  }

  // 🔐 CARREGAR USUÁRIO LOGADO
  Future<void> _carregarUsuarioLogado() async {
    try {
      await FirebaseAuth.instance.authStateChanges().first;
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        _currentUserId = user.uid;
        print('✅ Usuário logado: $_currentUserId');
        await _carregarPermissoes();
      } else {
        print('❌ Nenhum usuário logado');
        _safeSetState(() {
          _carregandoPermissoes = false;
          _verificouPermissoes = true;
        });
      }
    } catch (e) {
      print('❌ Erro ao carregar usuário: $e');
      _safeSetState(() {
        _carregandoPermissoes = false;
        _verificouPermissoes = true;
      });
    }
  }

  // 🔐 CARREGAR PERMISSÕES
  Future<void> _carregarPermissoes() async {
    if (_currentUserId == null) {
      _safeSetState(() {
        _carregandoPermissoes = false;
        _verificouPermissoes = true;
      });
      return;
    }

    try {
      final permissoes = await _permissaoService.carregarPermissoes(_currentUserId!);
      final isAdmin = await _permissaoService.isAdmin(_currentUserId!);

      print('📋 Permissões carregadas: $permissoes');
      print('👑 É admin: $isAdmin');

      _safeSetState(() {
        _permissoes = permissoes;
        _isAdmin = isAdmin;
        _carregandoPermissoes = false;
        _verificouPermissoes = true;
      });
    } catch (e) {
      print('❌ Erro ao carregar permissões: $e');
      _safeSetState(() {
        _carregandoPermissoes = false;
        _verificouPermissoes = true;
      });
    }
  }

  // 🔐 VERIFICAR PERMISSÃO
  Future<bool> _verificarPermissao(String permissao, {String? acao}) async {
    // Se ainda está carregando, aguarda
    if (_carregandoPermissoes || !_verificouPermissoes) {
      print('⏳ Aguardando carregar permissões...');
      await Future.delayed(const Duration(milliseconds: 500));
      return _verificarPermissao(permissao, acao: acao);
    }

    // Admin tem todas as permissões
    if (_isAdmin) {
      print('✅ ADMIN - Permissão concedida');
      return true;
    }

    final temPermissao = _permissoes[permissao] ?? false;
    print('🔐 Permissão "$permissao": ${temPermissao ? "✅" : "❌"}');

    if (!temPermissao) {
      await _mostrarDialogoSemPermissao(acao ?? permissao);
    }

    return temPermissao;
  }

  // 🔐 DIÁLOGO DE SEM PERMISSÃO
  Future<void> _mostrarDialogoSemPermissao(String acao) async {
    if (!_isMounted) return;

    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.no_accounts,
                color: Colors.red.shade900,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text(
                'Sem Permissão',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Você não tem permissão para $acao.',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade100),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.red.shade900,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Entre em contato com um administrador para solicitar acesso.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade900,
              ),
              child: const Text('Entendi'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _initializeData() async {
    try {
      await _fetchAcademias();
      await _fetchGraduacoes();
      if (_isEditing) {
        await _loadAlunoData();
      }
      _safeSetState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Erro ao inicializar dados: $e');
      _safeSetState(() {
        _isLoading = false;
      });
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar dados: $e')),
        );
      }
    }
  }

  // Buscar academias ativas
  Future<void> _fetchAcademias() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('academias')
          .where('status', isEqualTo: 'ativa')
          .orderBy('nome')
          .get();

      final items = <DropdownMenuItem<String>>[];
      final academiasMap = <String, String>{};
      final uniqueIds = <String>{};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final nome = data['nome'] ?? 'Sem nome';
        final id = doc.id;

        // Evitar duplicatas
        if (uniqueIds.contains(id)) {
          debugPrint('⚠️ Academia duplicada ignorada: $id - $nome');
          continue;
        }
        uniqueIds.add(id);

        academiasMap[id] = nome;
        items.add(DropdownMenuItem(
          value: id,
          child: Text(nome),
        ));
      }

      _safeSetState(() {
        _academiasMap = academiasMap;
        _academiaItems = items;
      });
    } catch (e) {
      debugPrint('Erro ao buscar academias: $e');
      rethrow;
    }
  }

  // Buscar turmas da academia selecionada (coleção separada)
  Future<void> _fetchTurmas(String? academiaId) async {
    if (academiaId == null || academiaId.isEmpty) {
      _safeSetState(() {
        _turmaItems = [];
        _turmasMap = {};
        _turmaId = null;
        _turmaNome = null;
        _carregandoTurmas = false;
        _turmaCheia = false;
      });
      return;
    }

    _safeSetState(() {
      _carregandoTurmas = true;
    });

    try {
      debugPrint('🔄 Buscando turmas para academia ID: $academiaId');

      final snapshot = await FirebaseFirestore.instance
          .collection('turmas')
          .where('academia_id', isEqualTo: academiaId)
          .where('status', isEqualTo: 'ATIVA')
          .orderBy('nome')
          .get();

      debugPrint('✅ ${snapshot.docs.length} turmas encontradas');

      final items = <DropdownMenuItem<String>>[];
      final turmasMap = <String, Map<String, dynamic>>{};
      final uniqueTurmaIds = <String>{};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final nome = data['nome'] ?? 'Sem nome';
        final id = doc.id;

        if (uniqueTurmaIds.contains(id)) {
          debugPrint('⚠️ Turma duplicada ignorada: $id - $nome');
          continue;
        }
        uniqueTurmaIds.add(id);

        final capacidadeMaxima = data['capacidade_maxima'] ?? 0;
        final alunosCount = data['alunos_count'] ?? 0;
        final alunosAtivos = data['alunos_ativos'] ?? 0;
        final totalAlunos = alunosAtivos > 0 ? alunosAtivos : alunosCount;
        final turmaCheia = capacidadeMaxima > 0 && totalAlunos >= capacidadeMaxima;

        turmasMap[id] = {
          'id': id,
          'nome': nome,
          'horario': data['horario_display'] ?? data['horario'] ?? '',
          'dias_semana': data['dias_semana_display'] ?? data['dias_semana'] ?? [],
          'capacidade_maxima': capacidadeMaxima,
          'alunos_count': alunosCount,
          'alunos_ativos': alunosAtivos,
          'faixa_etaria': data['faixa_etaria'] ?? '',
          'nivel': data['nivel'] ?? '',
          'academia_id': data['academia_id'] ?? '',
          'cheia': turmaCheia,
        };

        items.add(DropdownMenuItem(
          value: id,
          child: Text(
            nome,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: turmaCheia ? Colors.grey : null,
              fontWeight: turmaCheia ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          enabled: !turmaCheia,
        ));
      }

      final finalItems = <DropdownMenuItem<String>>[];
      final seenValues = <String>{};

      for (var item in items) {
        if (!seenValues.contains(item.value)) {
          seenValues.add(item.value!);
          finalItems.add(item);
        }
      }

      _safeSetState(() {
        _turmasMap = turmasMap;
        _turmaItems = finalItems;
        _carregandoTurmas = false;

        if (_turmaId != null && turmasMap.containsKey(_turmaId)) {
          final turmaData = turmasMap[_turmaId];
          _turmaCheia = turmaData?['cheia'] == true;
        }

        if (_turmaId != null && !seenValues.contains(_turmaId)) {
          _turmaId = null;
          _turmaNome = null;
          _turmaCheia = false;
        }

        if (_turmaId == null && finalItems.length == 1 && finalItems.first.enabled) {
          _turmaId = finalItems.first.value;
          final turmaData = _turmasMap[_turmaId];
          _turmaNome = turmaData != null ? turmaData['nome'] as String? : null;
          _turmaCheia = turmaData?['cheia'] == true;
        }
      });
    } catch (e) {
      debugPrint('❌ Erro ao buscar turmas: $e');
      _safeSetState(() {
        _carregandoTurmas = false;
      });
    }
  }

  Future<void> _fetchGraduacoes() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('graduacoes')
          .orderBy('nivel_graduacao')
          .get();

      Map<String, Map<String, dynamic>> dataMap = {};
      final uniqueGraduacoes = <String>{};
      final items = <DropdownMenuItem<String>>[];

      for (var doc in snapshot.docs) {
        final id = doc.id;
        if (uniqueGraduacoes.contains(id)) {
          debugPrint('⚠️ Graduação duplicada ignorada: $id');
          continue;
        }
        uniqueGraduacoes.add(id);

        final data = doc.data();
        dataMap[id] = data;

        final cor1 = _colorFromHex(data['hex_cor1']);
        final cor2 = _colorFromHex(data['hex_cor2']);

        items.add(DropdownMenuItem(
          value: id,
          child: Row(
            children: [
              Container(
                width: 80,
                height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(colors: [cor2, cor1], stops: const [0.5, 0.5]),
                  border: Border.all(color: Colors.black38, width: 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(data['nome_graduacao'] ?? '',
                      overflow: TextOverflow.ellipsis)),
            ],
          ),
        ));
      }

      final finalItems = <DropdownMenuItem<String>>[];
      final seenValues = <String>{};

      finalItems.add(const DropdownMenuItem(value: null, child: Text("Sem Graduação")));

      for (var item in items) {
        if (!seenValues.contains(item.value)) {
          seenValues.add(item.value!);
          finalItems.add(item);
        }
      }

      _safeSetState(() {
        _graduacoesData = dataMap;
        _graduacaoItems = finalItems;
      });
    } catch (e) {
      debugPrint('Erro ao buscar graduações: $e');
      rethrow;
    }
  }

  Future<void> _loadAlunoData() async {
    try {
      if (widget.alunoId == null || widget.alunoId!.isEmpty) {
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('alunos')
          .doc(widget.alunoId)
          .get();

      final data = doc.data();
      if (data == null) {
        if (_isMounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aluno não encontrado')),
          );
        }
        return;
      }

      // Preencher controllers com dados textuais
      _controllers.forEach((key, controller) {
        if (data.containsKey(key) && data[key] != null && data[key] is! Timestamp) {
          controller.text = data[key].toString();
        }
      });

      void safeSetDate(String fieldName, dynamic timestamp) {
        if (timestamp != null && timestamp is Timestamp) {
          _controllers[fieldName]!.text = _formatTimestamp(timestamp);
        }
      }

      safeSetDate('data_nascimento', data['data_nascimento']);
      safeSetDate('data_graduacao_atual', data['data_graduacao_atual']);
      safeSetDate('tempo_capoeira', data['tempo_capoeira']);

      String? academiaId = data['academia_id'] as String?;
      String? turmaId = data['turma_id'] as String?;
      String? academiaNome = data['academia'] as String?;
      String? turmaNome = data['turma'] as String?;

      _safeSetState(() {
        _sexo = data['sexo'] as String?;
        _statusAtividade = data['status_atividade'] as String? ?? 'ATIVO(A)';
        _graduacaoId = data['graduacao_id'] as String?;
        _networkImageUrl = data['foto_perfil_aluno'] as String?;

        _academiaId = academiaId;
        _academiaNome = academiaNome;
        _turmaId = turmaId;
        _turmaNome = turmaNome;
      });

      if (academiaId != null && academiaId.isNotEmpty) {
        if (academiaNome == null || academiaNome.isEmpty) {
          try {
            final academiaDoc = await FirebaseFirestore.instance
                .collection('academias')
                .doc(academiaId)
                .get();

            if (academiaDoc.exists) {
              final academiaData = academiaDoc.data();
              _safeSetState(() {
                _academiaNome = academiaData?['nome'] as String?;
              });
            }
          } catch (e) {
            debugPrint('Erro ao buscar dados da academia: $e');
          }
        }

        await _fetchTurmas(academiaId);
      } else if (academiaNome != null && academiaNome.isNotEmpty) {
        final academiaIdPorNome = _academiasMap.entries
            .firstWhere(
              (entry) => entry.value == academiaNome,
          orElse: () => const MapEntry('', ''),
        )
            .key;

        if (academiaIdPorNome.isNotEmpty) {
          _safeSetState(() {
            _academiaId = academiaIdPorNome;
          });
          await _fetchTurmas(academiaIdPorNome);
        }
      }

    } catch (e) {
      debugPrint('Erro ao carregar dados do aluno: $e');
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao carregar dados: $e')));
      }
      rethrow;
    }
  }

  Color _colorFromHex(String? hexColor) {
    if (hexColor == null || hexColor.length < 7) return Colors.grey;
    return Color(int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16));
  }

  Future<void> _selectDate(
      BuildContext context, TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _parseDate(controller.text) ?? DateTime.now(),
        firstDate: DateTime(1920),
        lastDate: DateTime(2100));

    if (picked != null && _isMounted) {
      _safeSetState(() => controller.text = DateFormat('dd/MM/yyyy').format(picked));
    }
  }

  void _showImageSourceActionSheet() {
    if (!_isMounted) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Escolher da Galeria'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Tirar Foto com a Câmera'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await ImagePicker().pickImage(
          source: source, imageQuality: 50, maxWidth: 800);
      if (image != null && _isMounted) {
        _safeSetState(() => _pickedImage = image);
      }
    } catch (e) {
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erro ao selecionar imagem: $e")));
      }
    }
  }

  Future<File?> _comprimirImagem(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final originalImage = img.decodeImage(bytes);

      if (originalImage == null) {
        return imageFile;
      }

      final compressedBytes = img.encodeJpg(originalImage, quality: 70);

      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(compressedBytes);

      debugPrint('✅ Imagem comprimida: ${imageFile.lengthSync()} → ${tempFile.lengthSync()} bytes');

      return tempFile;
    } catch (e) {
      debugPrint('⚠️ Erro ao comprimir imagem: $e');
      return imageFile;
    }
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate() || !_isMounted) return;

    // Verificar se a turma está cheia
    if (_turmaId != null && _turmaId!.isNotEmpty) {
      final turmaData = _turmasMap[_turmaId];
      final capacidadeMaxima = turmaData?['capacidade_maxima'] ?? 0;
      final alunosCount = turmaData?['alunos_count'] ?? 0;
      final alunosAtivos = turmaData?['alunos_ativos'] ?? 0;
      final totalAlunos = alunosAtivos > 0 ? alunosAtivos : alunosCount;

      if (capacidadeMaxima > 0 && totalAlunos >= capacidadeMaxima) {
        if (_isMounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('A turma "${turmaData?['nome']}" está cheia! ($totalAlunos/$capacidadeMaxima alunos)'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    // Upload da imagem se houver nova com compressão
    if (_pickedImage != null) {
      try {
        File? imagemParaUpload = File(_pickedImage!.path);

        final imagemComprimida = await _comprimirImagem(imagemParaUpload);
        if (imagemComprimida != null) {
          imagemParaUpload = imagemComprimida;
        }

        final ref = FirebaseStorage.instance
            .ref()
            .child('foto_alunos')
            .child('${widget.alunoId ?? UniqueKey().toString()}.jpg');

        final metadata = SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {'compressed': 'true', 'quality': '70'},
        );

        await ref.putFile(imagemParaUpload, metadata);
        _networkImageUrl = await ref.getDownloadURL();
      } catch (e) {
        if (_isMounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Erro ao fazer upload da imagem: $e")));
        }
        return;
      }
    }

    // Preparar dados para salvar
    Map<String, dynamic> dataToSave = {};

    _controllers.forEach((key, controller) {
      if (dateKeys.contains(key)) {
        final date = _parseDate(controller.text.trim());
        if (date != null) {
          dataToSave[key] = Timestamp.fromDate(date);
        }
      } else {
        final text = controller.text.trim();
        if (text.isNotEmpty) {
          dataToSave[key] = text;
        }
      }
    });

    if (_academiaId != null && _academiaId!.isNotEmpty) {
      dataToSave['academia_id'] = _academiaId;
      dataToSave['academia'] = _academiaNome ?? _academiasMap[_academiaId];
    }

    if (_turmaId != null && _turmaId!.isNotEmpty) {
      dataToSave['turma_id'] = _turmaId;
      final turmaData = _turmasMap[_turmaId];
      dataToSave['turma'] = _turmaNome ?? (turmaData != null ? turmaData['nome'] as String? : null);
    }

    final graduacaoRef = _graduacaoId != null
        ? FirebaseFirestore.instance.collection('graduacoes').doc(_graduacaoId)
        : null;
    final graduacaoData = _graduacaoId != null ? _graduacoesData[_graduacaoId] : null;

    final camposObrigatorios = {
      'sexo': _sexo,
      'status_atividade': _statusAtividade ?? 'ATIVO(A)',
      'foto_perfil_aluno': _networkImageUrl,
      'graduacao_id': _graduacaoId,
      'graduacao_ref': graduacaoRef,
      'cpf': _controllers['cpf']!.text.isEmpty ? '0' : _controllers['cpf']!.text,
      'atualizado_em': FieldValue.serverTimestamp(),
      'editavel': true,
    };

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

    dataToSave.addAll(camposObrigatorios);

    try {
      if (_isEditing) {
        await FirebaseFirestore.instance
            .collection('alunos')
            .doc(widget.alunoId)
            .update(dataToSave);

        if (_turmaId != null && _turmaId!.isNotEmpty) {
          await _atualizarContadorTurma(_turmaId!);
        }
      } else {
        dataToSave['criado_em'] = FieldValue.serverTimestamp();

        final docRef = await FirebaseFirestore.instance
            .collection('alunos')
            .add(dataToSave);

        if (_turmaId != null && _turmaId!.isNotEmpty) {
          await _atualizarContadorTurma(_turmaId!);
        }
      }

      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_isEditing ? 'Aluno atualizado!' : 'Aluno criado!')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (_isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao salvar: $e')));
      }
    }
  }

  Future<void> _atualizarContadorTurma(String turmaId) async {
    if (_academiaId == null || _academiaId!.isEmpty) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('alunos')
          .where('turma_id', isEqualTo: turmaId)
          .where('status_atividade', isEqualTo: 'ATIVO(A)')
          .get();

      final alunosCount = snapshot.docs.length;

      await FirebaseFirestore.instance
          .collection('turmas')
          .doc(turmaId)
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
    'tempo_capoeira'
  ];

  // 🔥 FUNÇÃO DE EXCLUIR COM VALIDAÇÃO DE PERMISSÃO
  Future<void> _deleteAluno() async {
    if (!_isEditing || !_isMounted) return;

    // 🔐 VERIFICAR PERMISSÃO DE EXCLUIR
    final temPermissao = await _verificarPermissao(
      'pode_excluir_aluno',
      acao: 'excluir aluno',
    );

    if (!temPermissao) return; // ✅ Diálogo já é mostrado no _verificarPermissao

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("⚠️ Confirmar Exclusão"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Você tem certeza que deseja excluir o aluno(a):",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _controllers['nome']!.text,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade900,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Text(
                'Esta ação é permanente e irreversível. Todos os dados do aluno serão removidos do sistema.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("EXCLUIR PERMANENTEMENTE"),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        // Mostrar loading
        if (_isMounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Deletar foto do Storage
        if (_networkImageUrl != null && _networkImageUrl!.isNotEmpty) {
          try {
            await FirebaseStorage.instance.refFromURL(_networkImageUrl!).delete();
            debugPrint('✅ Foto deletada do Storage');
          } catch (e) {
            debugPrint("⚠️ Aviso: Falha ao deletar foto do Storage: $e");
          }
        }

        // Deletar documento do Firestore
        await FirebaseFirestore.instance
            .collection('alunos')
            .doc(widget.alunoId)
            .delete();

        debugPrint('✅ Aluno deletado do Firestore');

        // Atualizar contador da turma se houver
        if (_turmaId != null && _turmaId!.isNotEmpty) {
          await _atualizarContadorTurma(_turmaId!);
          debugPrint('✅ Contador da turma atualizado');
        }

        // Fechar loading
        if (_isMounted) {
          Navigator.of(context).pop(); // Fecha o loading

          // Mostrar sucesso
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text("Aluno excluído com sucesso."),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );

          // Voltar para a tela anterior
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e) {
        debugPrint('❌ Erro ao excluir aluno: $e');

        // Fechar loading se estiver aberto
        if (_isMounted) {
          Navigator.of(context).pop();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao excluir aluno: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatTimestamp(Timestamp timestamp) =>
      DateFormat('dd/MM/yyyy').format(timestamp.toDate());

  DateTime? _parseDate(String dateStr) {
    if (dateStr.isEmpty) return null;
    try {
      return DateFormat('dd/MM/yyyy').parseStrict(dateStr);
    } catch (e) {
      debugPrint("Erro ao parsear data: $dateStr");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 MOSTRAR LOADING ENQUANTO CARREGA PERMISSÕES
    if (_isLoading || _carregandoPermissoes) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.red),
              SizedBox(height: 20),
              Text('Carregando...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Aluno' : 'Novo Aluno'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          // ✅ BOTÃO SALVAR - SEMPRE VISÍVEL
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveForm,
            tooltip: "Salvar Alterações",
          ),

          // ✅ BOTÃO EXCLUIR - SÓ APARECE SE FOR EDIÇÃO E TIVER PERMISSÃO
          if (_isEditing && _verificouPermissoes && (_isAdmin || _permissoes['pode_excluir_aluno'] == true))
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteAluno,
              tooltip: "Excluir Aluno",
            ),

          // 🔥 BOTÃO DE DEBUG (OPCIONAL - SÓ PARA ADMIN)
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.bug_report, size: 20),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('🐞 DEBUG PERMISSÕES'),
                    content: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('User ID: $_currentUserId', style: const TextStyle(fontWeight: FontWeight.bold)),
                          const Divider(),
                          Text('Admin: ${_isAdmin ? "✅" : "❌"}'),
                          const Divider(),
                          const Text('Permissões:', style: TextStyle(fontWeight: FontWeight.bold)),
                          ..._permissoes.entries.map((e) =>
                              Padding(
                                padding: const EdgeInsets.only(left: 8, top: 4),
                                child: Text('${e.key}: ${e.value ? "✅" : "❌"}'),
                              )
                          ),
                          if (_permissoes.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text('Nenhuma permissão encontrada!', style: TextStyle(color: Colors.red)),
                            ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Fechar'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Foto do aluno
              GestureDetector(
                onTap: _showImageSourceActionSheet,
                child: CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: _pickedImage != null
                      ? FileImage(File(_pickedImage!.path))
                      : (_networkImageUrl != null && _networkImageUrl!.isNotEmpty
                      ? CachedNetworkImageProvider(_networkImageUrl!)
                      : null)
                  as ImageProvider?,
                  child: _pickedImage == null && (_networkImageUrl == null || _networkImageUrl!.isEmpty)
                      ? const Icon(Icons.camera_alt, size: 50)
                      : null,
                ),
              ),
              const SizedBox(height: 16),

              // Dados Pessoais
              _buildSectionTitle('Dados Pessoais'),
              _buildTextField(_controllers['nome']!, 'Nome do Aluno',
                  isRequired: true),
              _buildTextField(_controllers['apelido']!, 'Apelido'),
              _buildTextField(_controllers['cpf']!, 'CPF',
                  keyboardType: TextInputType.number),

              DropdownButtonFormField<String>(
                  value: _sexo,
                  items: ['MASCULINO', 'FEMININO']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => _sexo = v),
                  decoration: const InputDecoration(
                      labelText: 'Sexo', border: OutlineInputBorder()),
                  validator: (v) => v == null ? 'Campo obrigatório' : null),

              _buildDateField(_controllers['data_nascimento']!,
                  'Data de Nascimento', isRequired: true),

              // Contato
              _buildSectionTitle('Contato'),
              _buildTextField(_controllers['contato_aluno']!,
                  'Contato do Aluno',
                  keyboardType: TextInputType.phone),
              _buildTextField(_controllers['nome_responsavel']!,
                  'Nome do Responsável'),
              _buildTextField(_controllers['contato_responsavel']!,
                  'Contato do Responsável',
                  keyboardType: TextInputType.phone),
              _buildTextField(_controllers['endereco']!, 'Endereço'),
              _buildTextField(_controllers['cidade']!, 'Cidade'),

              // Academia e Turma
              _buildSectionTitle('Academia e Turma'),

              // Seleção de Academia
              DropdownButtonFormField<String>(
                value: _academiaId,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Selecione uma academia'),
                  ),
                  ..._academiaItems,
                ],
                onChanged: (String? newValue) {
                  setState(() {
                    _academiaId = newValue;
                    _academiaNome = newValue != null
                        ? _academiasMap[newValue]
                        : null;
                    _turmaId = null;
                    _turmaNome = null;
                    _turmaItems = [];
                    _turmaCheia = false;
                    if (newValue != null) {
                      _fetchTurmas(newValue);
                    }
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Academia/Núcleo',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.school),
                ),
                validator: (value) =>
                value == null ? 'Selecione uma academia' : null,
              ),

              const SizedBox(height: 16),

              // Seleção de Turma
              Stack(
                children: [
                  DropdownButtonFormField<String>(
                    value: _turmaId,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Selecione uma turma'),
                      ),
                      ..._turmaItems,
                    ],
                    onChanged: (String? newValue) {
                      setState(() {
                        _turmaId = newValue;
                        if (newValue != null) {
                          final turmaData = _turmasMap[newValue];
                          _turmaNome = turmaData != null ? turmaData['nome'] as String? : null;
                          _turmaCheia = turmaData?['cheia'] == true;
                        } else {
                          _turmaNome = null;
                          _turmaCheia = false;
                        }
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Turma',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.group),
                    ),
                    validator: (value) {
                      if (_academiaId != null && value == null) {
                        return 'Selecione uma turma';
                      }
                      return null;
                    },
                  ),
                  if (_carregandoTurmas)
                    Positioned.fill(
                      child: Container(
                        color: Colors.white.withOpacity(0.7),
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ),
                ],
              ),

              if (_turmaCheia)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Esta turma está CHEIA! Não é possível adicionar mais alunos.',
                            style: TextStyle(
                              color: Colors.red.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (_academiaId != null && _turmaItems.isEmpty && !_carregandoTurmas)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Nenhuma turma disponível para esta academia',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),

              if (_turmaId != null && _turmasMap.containsKey(_turmaId) && _turmasMap[_turmaId] != null)
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Informações da Turma:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                            'Horário: ${_turmasMap[_turmaId]!['horario'] ?? 'Não informado'}'),
                        Text(
                            'Capacidade: ${_turmasMap[_turmaId]!['alunos_ativos'] ?? _turmasMap[_turmaId]!['alunos_count'] ?? 0}/${_turmasMap[_turmaId]!['capacidade_maxima'] ?? 0} alunos'),
                        if (_turmaCheia)
                          Text(
                            'STATUS: CHEIA ❌',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        Text(
                            'Faixa Etária: ${_turmasMap[_turmaId]!['faixa_etaria'] ?? ''}'),
                        Text(
                            'Nível: ${_turmasMap[_turmaId]!['nivel'] ?? ''}'),
                        if (_turmasMap[_turmaId]!['dias_semana'] != null && (_turmasMap[_turmaId]!['dias_semana'] as List).isNotEmpty)
                          Text(
                              'Dias: ${(_turmasMap[_turmaId]!['dias_semana'] as List).join(', ')}'),
                      ],
                    ),
                  ),
                ),

              // Dados da Capoeira
              _buildSectionTitle('Dados da Capoeira'),

              DropdownButtonFormField<String>(
                value: _graduacaoId,
                items: _graduacaoItems,
                onChanged: (v) => setState(() => _graduacaoId = v),
                decoration: const InputDecoration(
                    labelText: 'Graduação Atual',
                    border: OutlineInputBorder()),
                isExpanded: true,
                selectedItemBuilder: (BuildContext context) {
                  return _graduacaoItems.map<Widget>((DropdownMenuItem<String> item) {
                    return Text(
                      item.value == null
                          ? "Sem Graduação"
                          : (_graduacoesData[item.value!]?['nome_graduacao'] ?? ''),
                      overflow: TextOverflow.ellipsis,
                    );
                  }).toList();
                },
              ),

              _buildDateField(_controllers['data_graduacao_atual']!,
                  'Data da Graduação'),
              _buildDateField(_controllers['tempo_capoeira']!,
                  'Início na Capoeira'),

              DropdownButtonFormField<String>(
                  value: _statusAtividade,
                  items: ['ATIVO(A)', 'INATIVO(A)']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => _statusAtividade = v),
                  decoration: const InputDecoration(
                      labelText: 'Status', border: OutlineInputBorder()),
                  validator: (v) => v == null ? 'Campo obrigatório' : null),

            ].map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 16), child: e)).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
      child: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: Colors.red.shade900)),
    );
  }

  TextFormField _buildTextField(TextEditingController controller, String label,
      {TextInputType keyboardType = TextInputType.text,
        bool isRequired = false}) {
    return TextFormField(
        controller: controller,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        keyboardType: keyboardType,
        inputFormatters: keyboardType == TextInputType.phone ||
            keyboardType == TextInputType.number
            ? [FilteringTextInputFormatter.digitsOnly]
            : [],
        validator: (value) => (isRequired && (value == null || value.isEmpty))
            ? 'Campo obrigatório'
            : null);
  }

  TextFormField _buildDateField(
      TextEditingController controller, String label,
      {bool isRequired = false}) {
    return TextFormField(
        controller: controller,
        decoration: InputDecoration(
            labelText: label,
            suffixIcon: const Icon(Icons.calendar_today),
            border: const OutlineInputBorder()),
        readOnly: true,
        onTap: () => _selectDate(context, controller),
        validator: (value) => (isRequired && (value == null || value.isEmpty))
            ? 'Campo obrigatório'
            : null);
  }
}