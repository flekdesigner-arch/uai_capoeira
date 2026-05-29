import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 👈 ADICIONAR
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;

Color _readableOn(Color background) {
  return background.computeLuminance() > 0.48
      ? const Color(0xFF111827)
      : const Color(0xFFFFFFFF);
}


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

  EditarAlunoScreen({super.key, this.alunoId});

  @override
  State<EditarAlunoScreen> createState() => _EditarAlunoScreenState();
}

class _EditarAlunoScreenState extends State<EditarAlunoScreen> {
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
      await Future.delayed(Duration(milliseconds: 500));
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
                color: context.uai.primary,
                size: 28,
              ),
              SizedBox(width: 12),
              Text(
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
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.uai.error.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.uai.error.withOpacity(0.16)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: context.uai.primary,
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Entre em contato com um administrador para solicitar acesso.',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.uai.textPrimary.withOpacity(0.87),
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
                foregroundColor: context.uai.primary,
              ),
              child: Text('Entendi'),
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
              color: turmaCheia ? context.uai.textMuted : null,
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
                  gradient: LinearGradient(colors: [cor2, cor1], stops: [0.5, 0.5]),
                  border: Border.all(color: context.uai.textPrimary.withOpacity(0.38), width: 1),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                  child: Text(data['nome_graduacao'] ?? '',
                      overflow: TextOverflow.ellipsis)),
            ],
          ),
        ));
      }

      final finalItems = <DropdownMenuItem<String>>[];
      final seenValues = <String>{};

      finalItems.add(DropdownMenuItem(value: null, child: Text("Sem Graduação")));

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
            SnackBar(content: Text('Aluno não encontrado')),
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
          orElse: () => MapEntry('', ''),
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
    if (hexColor == null || hexColor.length < 7) return context.uai.textMuted;
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                margin: EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: context.uai.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: context.uai.primary),
                title: Text('Escolher da Galeria'),
                subtitle: Text('Selecionar uma nova foto do aluno'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt, color: context.uai.primary),
                title: Text('Tirar Foto com a Câmera'),
                subtitle: Text('Abrir a câmera do celular'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.crop_rounded, color: context.uai.success),
                title: Text('Editar foto do aluno'),
                subtitle: Text('Centralizar o rosto para aparecer certo nos cards'),
                onTap: () {
                  Navigator.of(context).pop();
                  _editarFotoAluno();
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
      if (url.isEmpty || (!url.startsWith('http://') && !url.startsWith('https://'))) {
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

      final tempFile = await _criarArquivoTemporarioSeguro('foto_aluno_editar');
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
        SnackBar(
          content: Text('Selecione ou tire uma foto primeiro para editar.'),
          backgroundColor: context.uai.warning,
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
          SnackBar(
            content: Text('Erro: a foto editada não foi encontrada. Tente novamente.'),
            backgroundColor: context.uai.error,
          ),
        );
        return;
      }

      _safeSetState(() => _pickedImage = XFile(arquivoEditado.path));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Foto ajustada! Toque em Salvar para enviar.'),
          backgroundColor: context.uai.success,
        ),
      );
    }
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

      final tempDir = Directory('${Directory.systemTemp.path}/uai_capoeira_fotos_editor');
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      final tempFile = File('${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(compressedBytes, flush: true);

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
              backgroundColor: context.uai.error,
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

  final List<String> dateKeys = [
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
        title: Text("⚠️ Confirmar Exclusão"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Você tem certeza que deseja excluir o aluno(a):",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              _controllers['nome']!.text,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.uai.primary,
              ),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.uai.error.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.uai.error.withOpacity(0.30)),
              ),
              child: Text(
                'Esta ação é permanente e irreversível. Todos os dados do aluno serão removidos do sistema.',
                style: TextStyle(
                  fontSize: 14,
                  color: context.uai.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
              foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
            ),
            child: Text("EXCLUIR PERMANENTEMENTE"),
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
            builder: (context) => Center(
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
                  Icon(Icons.check_circle, color: context.uai.card),
                  SizedBox(width: 8),
                  Text("Aluno excluído com sucesso."),
                ],
              ),
              backgroundColor: context.uai.success,
              duration: Duration(seconds: 2),
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
              backgroundColor: context.uai.error,
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
      return Scaffold(
        backgroundColor: context.uai.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: context.uai.error),
              SizedBox(height: 20),
              Text('Carregando...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Aluno' : 'Novo Aluno'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
        actions: [
          // ✅ BOTÃO SALVAR - SEMPRE VISÍVEL
          IconButton(
            icon: Icon(Icons.save),
            onPressed: _saveForm,
            tooltip: "Salvar Alterações",
          ),

          // ✅ BOTÃO EXCLUIR - SÓ APARECE SE FOR EDIÇÃO E TIVER PERMISSÃO
          if (_isEditing && _verificouPermissoes && (_isAdmin || _permissoes['pode_excluir_aluno'] == true))
            IconButton(
              icon: Icon(Icons.delete),
              onPressed: _deleteAluno,
              tooltip: "Excluir Aluno",
            ),

          // 🔥 BOTÃO DE DEBUG (OPCIONAL - SÓ PARA ADMIN)
          if (_isAdmin)
            IconButton(
              icon: Icon(Icons.bug_report, size: 20),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('🐞 DEBUG PERMISSÕES'),
                    content: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('User ID: $_currentUserId', style: TextStyle(fontWeight: FontWeight.bold)),
                          Divider(),
                          Text('Admin: ${_isAdmin ? "✅" : "❌"}'),
                          Divider(),
                          Text('Permissões:', style: TextStyle(fontWeight: FontWeight.bold)),
                          ..._permissoes.entries.map((e) =>
                              Padding(
                                padding: EdgeInsets.only(left: 8, top: 4),
                                child: Text('${e.key}: ${e.value ? "✅" : "❌"}'),
                              )
                          ),
                          if (_permissoes.isEmpty)
                            Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text('Nenhuma permissão encontrada!', style: TextStyle(color: context.uai.error)),
                            ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Fechar'),
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
          padding: EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Foto do aluno
              GestureDetector(
                onTap: _showImageSourceActionSheet,
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: context.uai.cardAlt,
                          backgroundImage: _pickedImage != null
                              ? FileImage(File(_pickedImage!.path))
                              : (_networkImageUrl != null && _networkImageUrl!.isNotEmpty
                              ? CachedNetworkImageProvider(_networkImageUrl!)
                              : null)
                          as ImageProvider?,
                          child: _pickedImage == null && (_networkImageUrl == null || _networkImageUrl!.isEmpty)
                              ? Icon(Icons.camera_alt, size: 50)
                              : null,
                        ),
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: context.uai.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: context.uai.textPrimary, width: 3),
                          ),
                          child: Icon(Icons.edit, color: context.uai.textPrimary, size: 18),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Toque na foto para galeria, câmera ou editor de enquadramento',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.uai.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),

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
                  decoration: InputDecoration(
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
                  DropdownMenuItem(
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
                decoration: InputDecoration(
                  labelText: 'Academia/Núcleo',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.school),
                ),
                validator: (value) =>
                value == null ? 'Selecione uma academia' : null,
              ),

              SizedBox(height: 16),

              // Seleção de Turma
              Stack(
                children: [
                  DropdownButtonFormField<String>(
                    value: _turmaId,
                    items: [
                      DropdownMenuItem(
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
                    decoration: InputDecoration(
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
                        color: context.uai.card.withOpacity(0.7),
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ),
                ],
              ),

              if (_turmaCheia)
                Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.uai.error.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.uai.error.withOpacity(0.30)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: context.uai.primaryDark),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Esta turma está CHEIA! Não é possível adicionar mais alunos.',
                            style: TextStyle(
                              color: context.uai.primaryDark,
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
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Nenhuma turma disponível para esta academia',
                    style: TextStyle(
                      color: context.uai.warning,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),

              if (_turmaId != null && _turmasMap.containsKey(_turmaId) && _turmasMap[_turmaId] != null)
                Card(
                  margin: EdgeInsets.only(top: 8),
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Informações da Turma:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.uai.primary,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                            'Horário: ${_turmasMap[_turmaId]!['horario'] ?? 'Não informado'}'),
                        Text(
                            'Capacidade: ${_turmasMap[_turmaId]!['alunos_ativos'] ?? _turmasMap[_turmaId]!['alunos_count'] ?? 0}/${_turmasMap[_turmaId]!['capacidade_maxima'] ?? 0} alunos'),
                        if (_turmaCheia)
                          Text(
                            'STATUS: CHEIA ❌',
                            style: TextStyle(
                              color: context.uai.error,
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
                decoration: InputDecoration(
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
                  decoration: InputDecoration(
                      labelText: 'Status', border: OutlineInputBorder()),
                  validator: (v) => v == null ? 'Campo obrigatório' : null),

            ].map((e) => Padding(
                padding: EdgeInsets.only(bottom: 16), child: e)).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.only(top: 24.0, bottom: 8.0),
      child: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: context.uai.primary)),
    );
  }

  TextFormField _buildTextField(TextEditingController controller, String label,
      {TextInputType keyboardType = TextInputType.text,
        bool isRequired = false}) {
    return TextFormField(
        controller: controller,
        decoration: InputDecoration(
            labelText: label, border: OutlineInputBorder()),
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
            suffixIcon: Icon(Icons.calendar_today),
            border: OutlineInputBorder()),
        readOnly: true,
        onTap: () => _selectDate(context, controller),
        validator: (value) => (isRequired && (value == null || value.isEmpty))
            ? 'Campo obrigatório'
            : null);
  }
}

class _EditorFotoAlunoDialog extends StatefulWidget {
  final File imageFile;
  final String nomeAluno;

  _EditorFotoAlunoDialog({
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

      // IMPORTANTE:
      // No preview, o slider move a IMAGEM dentro do quadro.
      // No recorte real, precisamos mover a JANELA DE CORTE no sentido contrário.
      // Sem esse sinal invertido, ao puxar a foto para baixo no editor,
      // o arquivo final cortava mais para baixo ainda e focava barriga/pernas.
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
          backgroundColor: context.uai.error,
        ),
      );
      setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nome = widget.nomeAluno.trim().isEmpty ? 'Aluno' : widget.nomeAluno.trim();

    return Dialog(
      insetPadding: EdgeInsets.all(12),
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
                padding: EdgeInsets.fromLTRB(16, 16, 8, 14),
                decoration: BoxDecoration(
                  gradient: context.uai.primaryGradient,
                ),
                child: Row(
                  children: [
                    Icon(Icons.crop_rounded, color: context.uai.card),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Editar foto do aluno',
                            style: TextStyle(
                              color: context.uai.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          Text(
                            nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.uai.card.withOpacity(0.78),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _salvando ? null : () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: context.uai.card),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'Use o card como referência: deixe o rosto bem no centro para aparecer certo nos cards do app.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.uai.textSecondary, fontSize: 13, height: 1.3),
                      ),
                      SizedBox(height: 14),
                      _buildCardReferencia(),
                      SizedBox(height: 16),
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
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _salvando ? null : _resetar,
                              icon: Icon(Icons.refresh_rounded),
                              label: Text('Resetar'),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _salvando ? null : _salvarImagemEditada,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary,
                                foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? _readableOn(Theme.of(context).appBarTheme.backgroundColor ?? context.uai.primary),
                                padding: EdgeInsets.symmetric(vertical: 13),
                              ),
                              icon: _salvando
                                  ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: context.uai.textPrimary,
                                ),
                              )
                                  : Icon(Icons.check_rounded),
                              label: Text(_salvando ? 'Salvando...' : 'Aplicar'),
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
          color: context.uai.textPrimary,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: context.uai.success, width: 2.2),
          boxShadow: [
            BoxShadow(
              color: context.uai.textPrimary.withOpacity(0.12),
              blurRadius: 14,
              offset: Offset(0, 5),
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
                      color: context.uai.cardAlt,
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
                        child: CustomPaint(
                          painter: _GuiaRostoPainter(),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.center,
                            colors: [Colors.black.withOpacity(0.55), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Text(
                        'Prévia no card',
                        style: TextStyle(
                          color: context.uai.textPrimary,
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
                padding: EdgeInsets.fromLTRB(9, 9, 9, 10),
                color: context.uai.success.withOpacity(0.10),
                child: Center(
                  child: Container(
                    width: 128,
                    height: 38,
                    decoration: BoxDecoration(
                      color: context.uai.success,
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded, color: context.uai.textPrimary, size: 17),
                        SizedBox(width: 6),
                        Text(
                          'Presente',
                          style: TextStyle(color: context.uai.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5),
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
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.uai.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.uai.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: context.uai.primary),
          SizedBox(width: 8),
          SizedBox(
            width: 74,
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: context.uai.primary,
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
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), paint..color = Colors.white.withOpacity(0.35));
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint..color = Colors.white.withOpacity(0.35));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
