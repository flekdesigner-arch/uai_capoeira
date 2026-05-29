import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';

import 'package:uai_capoeira/core/theme/app_theme.dart';

class EditarTurmaScreen extends StatefulWidget {
  final String academiaId;
  final String academiaNome;
  final String? turmaId;

  const EditarTurmaScreen({
    super.key,
    required this.academiaId,
    required this.academiaNome,
    this.turmaId,
  });

  @override
  State<EditarTurmaScreen> createState() => _EditarTurmaScreenState();
}

class _EditarTurmaScreenState extends State<EditarTurmaScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _imagePicker = ImagePicker();

  bool get _isEditing => widget.turmaId != null;
  bool _isLoading = false;
  File? _logoFile;

  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _nivelController = TextEditingController();
  final TextEditingController _capacidadeController = TextEditingController();
  final TextEditingController _idadeMinController = TextEditingController();
  final TextEditingController _idadeMaxController = TextEditingController();
  final TextEditingController _duracaoController = TextEditingController();
  final TextEditingController _observacoesController = TextEditingController();
  final TextEditingController _whatsappController = TextEditingController();
  final TextEditingController _pesoUsuarioAcessarController = TextEditingController();
  final TextEditingController _msgConviteWhatsappController = TextEditingController();

  String _faixaEtariaSelecionada = 'INFANTIL';
  String _statusSelecionado = 'ATIVA';
  DateTime? _dataInicioSelecionada;
  String _corSelecionada = '#059669';

  List<String> _professoresSelecionados = [];
  List<Map<String, dynamic>> _professoresDisponiveis = [];

  final Map<String, Map<String, dynamic>> _diasConfiguracao = {
    'SEGUNDA': {
      'selecionado': false,
      'tipoAula': 'OBJETIVA',
      'horario_inicio': '19:00',
      'horario_fim': '20:30',
    },
    'TERCA': {
      'selecionado': false,
      'tipoAula': 'OBJETIVA',
      'horario_inicio': '19:00',
      'horario_fim': '20:30',
    },
    'QUARTA': {
      'selecionado': false,
      'tipoAula': 'OBJETIVA',
      'horario_inicio': '19:00',
      'horario_fim': '20:30',
    },
    'QUINTA': {
      'selecionado': false,
      'tipoAula': 'OBJETIVA',
      'horario_inicio': '19:00',
      'horario_fim': '20:30',
    },
    'SEXTA': {
      'selecionado': false,
      'tipoAula': 'OBJETIVA',
      'horario_inicio': '19:00',
      'horario_fim': '20:30',
    },
    'SABADO': {
      'selecionado': false,
      'tipoAula': 'OBJETIVA',
      'horario_inicio': '09:00',
      'horario_fim': '10:30',
    },
    'DOMINGO': {
      'selecionado': false,
      'tipoAula': 'OBJETIVA',
      'horario_inicio': '09:00',
      'horario_fim': '10:30',
    },
  };

  String? _logoUrlAtual;
  String? _logoUrlNova;

  final List<String> _faixaEtariaOptions = const [
    'INFANTIL',
    'JUVENIL',
    'ADULTO',
    'SENIOR',
    'MISTA',
  ];

  final List<String> _statusOptions = const [
    'ATIVA',
    'INATIVA',
    'ESGOTADA',
  ];

  final List<String> _tiposAula = const [
    'OBJETIVA',
    'INSTRUMENTAÇÃO',
    'RODA',
  ];

  final List<String> _cores = const [
    '#059669',
    '#3B82F6',
    '#8B5CF6',
    '#EF4444',
    '#F59E0B',
    '#10B981',
    '#6366F1',
    '#EC4899',
  ];

  final Map<String, String> _diasDisplay = const {
    'SEGUNDA': 'Segunda',
    'TERCA': 'Terça',
    'QUARTA': 'Quarta',
    'QUINTA': 'Quinta',
    'SEXTA': 'Sexta',
    'SABADO': 'Sábado',
    'DOMINGO': 'Domingo',
  };

  @override
  void initState() {
    super.initState();
    _inicializarValoresPadrao();
    _carregarProfessores();
    if (_isEditing) {
      _carregarTurma();
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _nivelController.dispose();
    _capacidadeController.dispose();
    _idadeMinController.dispose();
    _idadeMaxController.dispose();
    _duracaoController.dispose();
    _observacoesController.dispose();
    _whatsappController.dispose();
    _pesoUsuarioAcessarController.dispose();
    _msgConviteWhatsappController.dispose();
    super.dispose();
  }

  void _inicializarValoresPadrao() {
    _capacidadeController.text = '25';
    _duracaoController.text = '60';
    _idadeMinController.text = '6';
    _idadeMaxController.text = '12';
    _pesoUsuarioAcessarController.text = '1';
    _msgConviteWhatsappController.text =
    'Olá! Você foi convidado(a) para participar do grupo da turma. Clique no link abaixo para entrar:\n\n';
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
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

  Color _colorFromHex(String hexColor) {
    try {
      final clean = hexColor.replaceAll('#', '').toUpperCase();
      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      }
      if (clean.length == 8) {
        return Color(int.parse(clean, radix: 16));
      }
    } catch (_) {}
    return context.uai.success;
  }

  bool _usuarioPodeSerProfessor(Map<String, dynamic> data) {
    final tipo = (data['tipo'] ?? '').toString().toLowerCase().trim();
    final status = (data['status_conta'] ?? '').toString().toLowerCase().trim();
    final peso = _toInt(data['peso_permissao']);

    if (status == 'bloqueada' || status == 'inativa') return false;
    if (peso >= 50) return true;

    return tipo == 'professor' ||
        tipo == 'administrador' ||
        tipo == 'admin' ||
        tipo == 'mestre' ||
        tipo == 'contra-mestre' ||
        tipo == 'contramestre' ||
        tipo == 'instrutor';
  }

  Map<String, dynamic> _mapUsuarioProfessor(
      String id,
      Map<String, dynamic> data, {
        bool selecionadoForaFiltro = false,
      }) {
    final nome = (data['nome_completo'] ??
        data['name'] ??
        data['nome'] ??
        'Sem nome')
        .toString()
        .trim();

    return {
      'id': id,
      'nome': nome.isEmpty ? 'Sem nome' : nome,
      'email': (data['email'] ?? 'Sem email').toString(),
      'tipo': (data['tipo'] ?? 'usuário').toString(),
      'peso': _toInt(data['peso_permissao']),
      'status': (data['status_conta'] ?? '').toString(),
      'selecionadoForaFiltro': selecionadoForaFiltro,
    };
  }

  void _ordenarProfessoresDisponiveis() {
    _professoresDisponiveis.sort((a, b) {
      final aSelecionado = _professoresSelecionados.contains(a['id']);
      final bSelecionado = _professoresSelecionados.contains(b['id']);

      if (aSelecionado != bSelecionado) return aSelecionado ? -1 : 1;

      final pesoA = _toInt(a['peso']);
      final pesoB = _toInt(b['peso']);
      if (pesoA != pesoB) return pesoB.compareTo(pesoA);

      return (a['nome'] ?? '')
          .toString()
          .compareTo((b['nome'] ?? '').toString());
    });
  }

  Future<void> _garantirProfessoresSelecionadosVisiveis() async {
    if (_professoresSelecionados.isEmpty) return;

    final idsVisiveis = _professoresDisponiveis
        .map((professor) => professor['id'].toString())
        .toSet();

    final idsFaltando = _professoresSelecionados
        .where((id) => !idsVisiveis.contains(id))
        .toList();

    if (idsFaltando.isEmpty) {
      if (mounted) setState(() => _ordenarProfessoresDisponiveis());
      return;
    }

    final extras = <Map<String, dynamic>>[];

    for (final id in idsFaltando) {
      try {
        final doc = await _firestore.collection('usuarios').doc(id).get();

        if (doc.exists && doc.data() != null) {
          extras.add(
            _mapUsuarioProfessor(
              doc.id,
              doc.data()!,
              selecionadoForaFiltro: true,
            ),
          );
        } else {
          extras.add({
            'id': id,
            'nome': 'Usuário não encontrado',
            'email': 'ID: $id',
            'tipo': 'indefinido',
            'peso': 0,
            'status': 'não encontrado',
            'selecionadoForaFiltro': true,
          });
        }
      } catch (e) {
        debugPrint('Erro ao buscar professor selecionado $id: $e');
      }
    }

    if (!mounted || extras.isEmpty) return;

    setState(() {
      final idsAtuais = _professoresDisponiveis
          .map((professor) => professor['id'].toString())
          .toSet();

      for (final extra in extras) {
        if (!idsAtuais.contains(extra['id'].toString())) {
          _professoresDisponiveis.add(extra);
        }
      }

      _ordenarProfessoresDisponiveis();
    });
  }

  Future<void> _carregarProfessores() async {
    try {
      final snapshot = await _firestore.collection('usuarios').get();

      final professores = snapshot.docs
          .where((doc) => _usuarioPodeSerProfessor(doc.data()))
          .map((doc) => _mapUsuarioProfessor(doc.id, doc.data()))
          .toList();

      if (!mounted) return;

      setState(() {
        _professoresDisponiveis = professores;
        _ordenarProfessoresDisponiveis();
      });

      await _garantirProfessoresSelecionadosVisiveis();
    } catch (e) {
      debugPrint('Erro ao carregar professores/usuários autorizados: $e');
      if (mounted) {
        _showSnack('Erro ao carregar professores: $e', type: _SnackType.error);
      }
    }
  }

  Future<void> _carregarTurma() async {
    setState(() => _isLoading = true);
    try {
      final doc = await _firestore.collection('turmas').doc(widget.turmaId).get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;

        _nomeController.text = data['nome'] ?? '';
        _nivelController.text = data['nivel'] ?? '';
        _capacidadeController.text =
            (data['capacidade_maxima'] ?? 25).toString();
        _idadeMinController.text = (data['idade_minima'] ?? 6).toString();
        _idadeMaxController.text = (data['idade_maxima'] ?? 12).toString();
        _duracaoController.text =
            (data['duracao_aula_minutos'] ?? 60).toString();
        _observacoesController.text = data['observacoes'] ?? '';
        _whatsappController.text = data['whatsapp_url'] ?? '';
        _pesoUsuarioAcessarController.text =
            (data['peso_do_usuario_para_acessar'] ?? 1).toString();
        _msgConviteWhatsappController.text =
            data['msg_convite_grupo_whatsapp'] ?? '';

        _faixaEtariaSelecionada = data['faixa_etaria'] ?? 'INFANTIL';
        _statusSelecionado = data['status'] ?? 'ATIVA';
        _corSelecionada = data['cor_turma'] ?? '#059669';
        _logoUrlAtual = data['logo_url'];

        if (data['data_inicio'] != null) {
          _dataInicioSelecionada = (data['data_inicio'] as Timestamp).toDate();
        }

        final professoresIds = data['professores_ids'] as List<dynamic>? ?? [];
        setState(() {
          _professoresSelecionados =
              professoresIds.map((id) => id.toString()).toList();
          _ordenarProfessoresDisponiveis();
        });

        await _garantirProfessoresSelecionadosVisiveis();

        final diasConfiguracao =
        data['dias_configuracao'] as Map<String, dynamic>?;

        if (diasConfiguracao != null) {
          for (final dia in _diasConfiguracao.keys) {
            if (diasConfiguracao.containsKey(dia)) {
              final config = diasConfiguracao[dia] as Map<String, dynamic>;
              _diasConfiguracao[dia] = {
                'selecionado': config['selecionado'] ?? false,
                'tipoAula': config['tipoAula'] ?? 'OBJETIVA',
                'horario_inicio': config['horario_inicio'] ?? '19:00',
                'horario_fim': config['horario_fim'] ?? '20:30',
              };
            }
          }
        } else {
          final horarioInicio = data['horario_inicio'] ?? '19:00';
          final horarioFim = data['horario_fim'] ?? '20:30';
          final dias = data['dias_semana'] as List<dynamic>? ?? [];

          for (final dia in _diasConfiguracao.keys) {
            _diasConfiguracao[dia] = {
              'selecionado': dias.contains(dia),
              'tipoAula': 'OBJETIVA',
              'horario_inicio': horarioInicio,
              'horario_fim': horarioFim,
            };
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar turma: $e');
      if (mounted) {
        _showSnack('Erro ao carregar dados: $e', type: _SnackType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selecionarDataInicio() async {
    final DateTime? dataSelecionada = await showDatePicker(
      context: context,
      initialDate: _dataInicioSelecionada ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (dataSelecionada != null) {
      setState(() => _dataInicioSelecionada = dataSelecionada);
    }
  }

  Future<void> _selecionarHorarioParaDia(String dia, bool isInicio) async {
    final TimeOfDay? horarioSelecionado = await showTimePicker(
      context: context,
      initialTime: _timeFromString(
        isInicio
            ? _diasConfiguracao[dia]!['horario_inicio']
            : _diasConfiguracao[dia]!['horario_fim'],
      ),
    );

    if (horarioSelecionado != null) {
      final formattedTime = _timeToString(horarioSelecionado);
      setState(() {
        if (isInicio) {
          _diasConfiguracao[dia]!['horario_inicio'] = formattedTime;
        } else {
          _diasConfiguracao[dia]!['horario_fim'] = formattedTime;
        }
      });
    }
  }

  TimeOfDay _timeFromString(String time) {
    final parts = time.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }

  String _timeToString(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _escolherLogo() async {
    final XFile? imagem = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (imagem != null) {
      setState(() => _logoFile = File(imagem.path));
      await _uploadLogo();
    }
  }

  Future<void> _uploadLogo() async {
    if (_logoFile == null) return;

    try {
      setState(() => _isLoading = true);

      final fileName =
          'turma_logo_${DateTime.now().millisecondsSinceEpoch}_${widget.turmaId ?? 'nova'}';
      final Reference storageRef = _storage
          .ref()
          .child('turmas_logos')
          .child(widget.academiaId)
          .child(fileName);

      final UploadTask uploadTask = storageRef.putFile(_logoFile!);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      if (!mounted) return;

      setState(() {
        _logoUrlNova = downloadUrl;
        _isLoading = false;
      });

      _showSnack('Logo enviada com sucesso!', type: _SnackType.success);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      if (mounted) {
        _showSnack('Erro ao enviar logo: $e', type: _SnackType.error);
      }
    }
  }

  Future<void> _salvarTurma() async {
    if (!_formKey.currentState!.validate()) return;

    final diasSelecionados = _diasConfiguracao.entries
        .where((entry) => entry.value['selecionado'] == true)
        .map((entry) => entry.key)
        .toList();

    if (diasSelecionados.isEmpty) {
      _showSnack(
        'Selecione pelo menos um dia da semana',
        type: _SnackType.error,
      );
      return;
    }

    if (_professoresSelecionados.isEmpty) {
      _showSnack(
        'Selecione pelo menos um professor',
        type: _SnackType.error,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final professoresNomes = _professoresSelecionados.map((id) {
        final professor = _professoresDisponiveis.firstWhere(
              (p) => p['id'] == id,
          orElse: () => {'nome': 'Professor não encontrado'},
        );
        return professor['nome'];
      }).toList();

      final diasConfiguracaoParaSalvar = {};
      final diasSemanaDisplay = <String>[];

      for (final entry in _diasConfiguracao.entries) {
        final dia = entry.key;
        final config = entry.value;

        if (config['selecionado'] == true) {
          diasSemanaDisplay.add(_diasDisplay[dia] ?? dia);
          diasConfiguracaoParaSalvar[dia] = {
            'selecionado': true,
            'tipoAula': config['tipoAula'],
            'horario_inicio': config['horario_inicio'],
            'horario_fim': config['horario_fim'],
          };
        } else {
          diasConfiguracaoParaSalvar[dia] = {
            'selecionado': false,
            'tipoAula': config['tipoAula'],
            'horario_inicio': config['horario_inicio'],
            'horario_fim': config['horario_fim'],
          };
        }
      }

      final data = {
        'academia_id': widget.academiaId,
        'nucleo': widget.academiaNome,
        'nome': _nomeController.text.trim(),
        'nivel': _nivelController.text.trim().toUpperCase(),
        'faixa_etaria': _faixaEtariaSelecionada,
        'professores_ids': _professoresSelecionados,
        'professores_nomes': professoresNomes,
        'professor_principal':
        professoresNomes.isNotEmpty ? professoresNomes.first : '',
        'capacidade_maxima': int.tryParse(_capacidadeController.text) ?? 25,
        'idade_minima': int.tryParse(_idadeMinController.text) ?? 6,
        'idade_maxima': int.tryParse(_idadeMaxController.text) ?? 12,
        'duracao_aula_minutos': int.tryParse(_duracaoController.text) ?? 60,
        'dias_semana': diasSelecionados,
        'dias_semana_display': diasSemanaDisplay,
        'dias_configuracao': diasConfiguracaoParaSalvar,
        'status': _statusSelecionado,
        'cor_turma': _corSelecionada,
        'observacoes': _observacoesController.text.trim(),
        'whatsapp_url': _whatsappController.text.trim(),
        'msg_convite_grupo_whatsapp':
        _msgConviteWhatsappController.text.trim(),
        'peso_do_usuario_para_acessar':
        int.tryParse(_pesoUsuarioAcessarController.text) ?? 1,
        'atualizado_em': FieldValue.serverTimestamp(),
      };

      if (_dataInicioSelecionada != null) {
        data['data_inicio'] = Timestamp.fromDate(_dataInicioSelecionada!);
      }

      if (_logoUrlNova != null) {
        data['logo_url'] = _logoUrlNova;
      } else if (_logoUrlAtual != null && !_isEditing) {
        data['logo_url'] = _logoUrlAtual;
      }

      if (_isEditing) {
        await _firestore.collection('turmas').doc(widget.turmaId).update(data);
      } else {
        data['criado_em'] = FieldValue.serverTimestamp();
        data['alunos_count'] = 0;
        data['alunos_ativos'] = 0;
        data['alunos_inativos'] = 0;

        await _firestore.collection('turmas').add(data);
      }

      await _atualizarContadorTurmas();

      if (mounted) {
        _showSnack(
          _isEditing
              ? 'Turma atualizada com sucesso!'
              : 'Turma criada com sucesso!',
          type: _SnackType.success,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Erro ao salvar: $e', type: _SnackType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _atualizarContadorTurmas() async {
    try {
      final turmasSnapshot = await _firestore
          .collection('turmas')
          .where('academia_id', isEqualTo: widget.academiaId)
          .get();

      await _firestore.collection('academias').doc(widget.academiaId).update({
        'turmas_count': turmasSnapshot.docs.length,
        'atualizado_em': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Erro ao atualizar contador: $e');
    }
  }

  Future<void> _excluirTurma() async {
    final nomeTurma = _nomeController.text.trim();
    final confirmacaoController = TextEditingController();
    bool nomeConfere = false;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final t = context.uai;
        final error = _ensureVisible(t.error, t.surface);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final currentConfere =
                confirmacaoController.text.trim() == nomeTurma;

            return Dialog(
              insetPadding: const EdgeInsets.all(18),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
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
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: error.withOpacity(0.12),
                                  borderRadius:
                                  BorderRadius.circular(t.buttonRadius),
                                ),
                                child: Icon(Icons.warning_rounded, color: error),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Confirmar Exclusão',
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: t.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Tem certeza que deseja excluir esta turma?\n\nEsta ação não pode ser desfeita.',
                            style: TextStyle(
                              color: t.textSecondary,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Para confirmar, digite o nome da turma:',
                            style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Color.alphaBlend(
                                error.withOpacity(0.10),
                                t.cardAlt,
                              ),
                              borderRadius:
                              BorderRadius.circular(t.inputRadius),
                              border: Border.all(
                                color: error.withOpacity(0.18),
                              ),
                            ),
                            child: Text(
                              '"$nomeTurma"',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: error,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: confirmacaoController,
                            style: TextStyle(color: t.textPrimary),
                            decoration: _inputDecoration(
                              label: 'Digite o nome da turma',
                              icon: Icons.warning_amber_rounded,
                            ).copyWith(
                              suffixIcon: confirmacaoController.text.isNotEmpty
                                  ? Icon(
                                currentConfere
                                    ? Icons.check_circle_rounded
                                    : Icons.error_rounded,
                                color: currentConfere
                                    ? t.success
                                    : t.error,
                              )
                                  : null,
                            ),
                            onChanged: (value) {
                              setDialogState(() {
                                nomeConfere = value.trim() == nomeTurma;
                              });
                            },
                          ),
                          const SizedBox(height: 18),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 380;

                              final cancel = OutlinedButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: t.textPrimary,
                                  side: BorderSide(color: t.border),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      t.buttonRadius,
                                    ),
                                  ),
                                ),
                                child: const Text('CANCELAR'),
                              );

                              final remove = ElevatedButton(
                                onPressed: nomeConfere
                                    ? () => Navigator.pop(dialogContext, true)
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: t.error,
                                  foregroundColor: _readableOn(t.error),
                                  disabledBackgroundColor: t.cardAlt,
                                  disabledForegroundColor: t.textMuted,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      t.buttonRadius,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  'EXCLUIR TURMA',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              );

                              if (narrow) {
                                return Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                                  children: [
                                    cancel,
                                    const SizedBox(height: 10),
                                    remove,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: cancel),
                                  const SizedBox(width: 10),
                                  Expanded(child: remove),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    confirmacaoController.dispose();

    if (confirmado == true) {
      await _realizarExclusaoTurma();
    }
  }

  Future<void> _realizarExclusaoTurma() async {
    setState(() => _isLoading = true);

    try {
      await _firestore.collection('turmas').doc(widget.turmaId).delete();
      await _atualizarContadorTurmas();

      if (mounted) {
        _showSnack('Turma excluída com sucesso!', type: _SnackType.success);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Erro ao excluir: $e', type: _SnackType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    IconData? icon,
    String? hint,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: t.textSecondary),
      hintStyle: TextStyle(color: t.textMuted),
      prefixIcon: icon == null ? null : Icon(icon, color: primary, size: 20),
      filled: true,
      fillColor: t.cardAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.error, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.background);

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: Row(
        children: [
          Icon(icon, color: primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: t.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Widget child) {
    final t = context.uai;

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: t.border),
          boxShadow: t.softShadow,
        ),
        child: child,
      ),
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obrigatorio = false,
    TextInputType? keyboardType,
    int? maxLines,
    String? Function(String?)? validator,
    String? hintText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        style: TextStyle(color: context.uai.textPrimary),
        decoration: _inputDecoration(
          label: label + (obrigatorio ? ' *' : ''),
          hint: hintText,
          icon: icon,
        ).copyWith(
          alignLabelWithHint: (maxLines ?? 1) > 1,
        ),
        keyboardType: keyboardType,
        maxLines: maxLines ?? 1,
        validator: validator ??
            (obrigatorio
                ? (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Campo obrigatório';
              }
              return null;
            }
                : null),
      ),
    );
  }

  Widget _buildDropdownField({
    required String value,
    required List<String> items,
    required String label,
    required IconData icon,
    required ValueChanged<String?> onChanged,
  }) {
    final t = context.uai;

    final normalizedItems = <String>[
      ...items,
      if (value.trim().isNotEmpty && !items.contains(value)) value,
    ].toSet().toList();

    final safeValue =
    normalizedItems.contains(value) ? value : normalizedItems.first;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: safeValue,
        isExpanded: true,
        dropdownColor: t.surface,
        style: TextStyle(color: t.textPrimary),
        decoration: _inputDecoration(label: label, icon: icon),
        items: normalizedItems.map((item) {
          return DropdownMenuItem<String>(
            value: item,
            child: Text(
              item,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.textPrimary),
            ),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildDiasSemanaComHorarios() {
    final t = context.uai;
    final selecionados = _diasConfiguracao.entries
        .where((entry) => entry.value['selecionado'] == true)
        .length;
    final countColor = _ensureVisible(
      selecionados == 0 ? t.warning : t.success,
      t.card,
    );

    return _buildCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Configuração de Dias, Horários e Tipos de Aula *',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    color: t.textPrimary,
                  ),
                ),
              ),
              Text(
                '$selecionados/7',
                style: TextStyle(
                  color: countColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._diasConfiguracao.entries.map((entry) {
            final dia = entry.key;
            final config = entry.value;
            final selecionado = config['selecionado'] as bool;
            final tipoAula = config['tipoAula'] as String;
            final horarioInicio = config['horario_inicio'] as String;
            final horarioFim = config['horario_fim'] as String;
            final primary = _ensureVisible(t.primary, t.cardAlt);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: selecionado
                    ? Color.alphaBlend(primary.withOpacity(0.10), t.cardAlt)
                    : t.cardAlt,
                borderRadius: BorderRadius.circular(t.inputRadius),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(t.inputRadius),
                    border: Border.all(
                      color: selecionado
                          ? primary.withOpacity(0.22)
                          : t.border,
                    ),
                  ),
                  child: Column(
                    children: [
                      CheckboxListTile(
                        dense: true,
                        contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8),
                        value: selecionado,
                        activeColor: primary,
                        title: Text(
                          _diasDisplay[dia] ?? dia,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: selecionado ? primary : t.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          selecionado
                              ? '$horarioInicio às $horarioFim • $tipoAula'
                              : 'Dia desativado',
                          style: TextStyle(color: t.textSecondary),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _diasConfiguracao[dia] = {
                              ...config,
                              'selecionado': value ?? false,
                            };
                          });
                        },
                      ),
                      if (selecionado)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                          child: Column(
                            children: [
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final narrow = constraints.maxWidth < 360;

                                  final inicio = _buildHorarioField(
                                    label: 'Início',
                                    horario: horarioInicio,
                                    onTap: () =>
                                        _selecionarHorarioParaDia(dia, true),
                                  );

                                  final termino = _buildHorarioField(
                                    label: 'Término',
                                    horario: horarioFim,
                                    onTap: () =>
                                        _selecionarHorarioParaDia(dia, false),
                                  );

                                  if (narrow) {
                                    return Column(
                                      children: [
                                        inicio,
                                        const SizedBox(height: 8),
                                        termino,
                                      ],
                                    );
                                  }

                                  return Row(
                                    children: [
                                      Expanded(child: inicio),
                                      const SizedBox(width: 8),
                                      Expanded(child: termino),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              _buildTipoAulaDropdown(dia: dia, value: tipoAula),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
          if (selecionados == 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Selecione pelo menos um dia da semana.',
                style: TextStyle(
                  color: countColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _tipoAulaColor(String tipo) {
    switch (tipo) {
      case 'OBJETIVA':
        return context.uai.info;
      case 'INSTRUMENTAÇÃO':
        return context.uai.success;
      case 'RODA':
        return context.uai.associacao;
      default:
        return context.uai.textMuted;
    }
  }

  Widget _buildHorarioField({
    required String label,
    required String horario,
    required VoidCallback onTap,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.inputRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.inputRadius),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Icon(Icons.access_time_rounded, size: 16, color: primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$label: $horario',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTipoAulaDropdown({
    required String dia,
    required String value,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(_tipoAulaColor(value), t.cardAlt);

    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      dropdownColor: t.surface,
      style: TextStyle(color: t.textPrimary),
      decoration: _inputDecoration(
        label: 'Tipo de aula',
        icon: Icons.sports_martial_arts_rounded,
      ).copyWith(
        prefixIcon: Icon(
          Icons.sports_martial_arts_rounded,
          color: accent,
          size: 20,
        ),
      ),
      items: _tiposAula.map((tipo) {
        return DropdownMenuItem<String>(
          value: tipo,
          child: Text(
            tipo,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.textPrimary),
          ),
        );
      }).toList(),
      onChanged: (newValue) {
        if (newValue != null) {
          setState(() {
            _diasConfiguracao[dia] = {
              ..._diasConfiguracao[dia]!,
              'tipoAula': newValue,
            };
          });
        }
      },
    );
  }

  Widget _buildCoresDisponiveis() {
    final t = context.uai;

    return _buildCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cor da Turma',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _cores.map((cor) {
              final isSelecionada = _corSelecionada == cor;
              final color = _colorFromHex(cor);
              final checkColor = _readableOn(color);

              return InkWell(
                onTap: () => setState(() => _corSelecionada = cor),
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelecionada ? t.textPrimary : t.border,
                      width: isSelecionada ? 3 : 2,
                    ),
                    boxShadow: isSelecionada ? t.softShadow : null,
                  ),
                  child: isSelecionada
                      ? Icon(Icons.check_rounded, color: checkColor, size: 21)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSelecaoProfessores() {
    final t = context.uai;
    final professoresOrdenados = [..._professoresDisponiveis];

    professoresOrdenados.sort((a, b) {
      final aSelecionado = _professoresSelecionados.contains(a['id']);
      final bSelecionado = _professoresSelecionados.contains(b['id']);

      if (aSelecionado != bSelecionado) return aSelecionado ? -1 : 1;

      final pesoA = _toInt(a['peso']);
      final pesoB = _toInt(b['peso']);
      if (pesoA != pesoB) return pesoB.compareTo(pesoA);

      return (a['nome'] ?? '')
          .toString()
          .compareTo((b['nome'] ?? '').toString());
    });

    final selecionadosVisiveis = professoresOrdenados
        .where((professor) => _professoresSelecionados.contains(professor['id']))
        .length;

    final selectedAccent = _ensureVisible(t.primary, t.cardAlt);

    return _buildCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Professores / Responsáveis *',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: t.textPrimary,
                  ),
                ),
              ),
              _smallPill(
                icon: Icons.check_circle_rounded,
                label:
                '${_professoresSelecionados.length} selecionado${_professoresSelecionados.length == 1 ? '' : 's'}',
                color: _professoresSelecionados.isEmpty
                    ? t.warning
                    : t.success,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Aparecem aqui usuários com peso de permissão 50 ou maior, além de tipos compatíveis como professor, instrutor, mestre e administrador.',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12,
              height: 1.25,
            ),
          ),
          if (_professoresSelecionados.isNotEmpty &&
              selecionadosVisiveis != _professoresSelecionados.length) ...[
            const SizedBox(height: 10),
            _infoBox(
              icon: Icons.warning_amber_rounded,
              color: t.warning,
              text:
              'Atenção: ${_professoresSelecionados.length - selecionadosVisiveis} professor(es) selecionado(s) não foram encontrados na lista normal e serão buscados pelo ID salvo na turma.',
            ),
          ],
          const SizedBox(height: 12),
          if (professoresOrdenados.isEmpty)
            _emptyBox(
              icon: Icons.person_search_rounded,
              title: 'Nenhum usuário com permissão de professor encontrado',
              subtitle:
              'Verifique se o usuário está ativo e com peso_permissao 50 ou maior.',
            )
          else
            Column(
              children: professoresOrdenados.map((professor) {
                final id = professor['id'].toString();
                final isSelecionado = _professoresSelecionados.contains(id);
                final foraFiltro = professor['selecionadoForaFiltro'] == true;
                final peso = _toInt(professor['peso']);
                final tipo = (professor['tipo'] ?? 'usuário').toString();
                final status = (professor['status'] ?? '').toString();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Material(
                    color: isSelecionado
                        ? Color.alphaBlend(
                      selectedAccent.withOpacity(0.10),
                      t.cardAlt,
                    )
                        : t.cardAlt,
                    borderRadius: BorderRadius.circular(t.inputRadius),
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(t.inputRadius),
                        border: Border.all(
                          color: isSelecionado
                              ? selectedAccent.withOpacity(0.26)
                              : t.border,
                          width: isSelecionado ? 1.4 : 1,
                        ),
                      ),
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        title: Text(
                          professor['nome'].toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: isSelecionado
                                ? selectedAccent
                                : t.textPrimary,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              professor['email'].toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: t.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Wrap(
                              spacing: 6,
                              runSpacing: 5,
                              children: [
                                _buildProfessorBadge(
                                  label: tipo.toUpperCase(),
                                  color: t.info,
                                  icon: Icons.badge_rounded,
                                ),
                                _buildProfessorBadge(
                                  label: 'PESO $peso',
                                  color:
                                  peso >= 50 ? t.success : t.warning,
                                  icon: Icons.security_rounded,
                                ),
                                if (status.trim().isNotEmpty)
                                  _buildProfessorBadge(
                                    label: status.toUpperCase(),
                                    color:
                                    status.toLowerCase() == 'ativa'
                                        ? t.success
                                        : t.warning,
                                    icon: Icons.circle,
                                  ),
                                if (foraFiltro)
                                  _buildProfessorBadge(
                                    label: 'SALVO NA TURMA',
                                    color: t.warning,
                                    icon: Icons.warning_amber_rounded,
                                  ),
                              ],
                            ),
                          ],
                        ),
                        value: isSelecionado,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              if (!_professoresSelecionados.contains(id)) {
                                _professoresSelecionados.add(id);
                              }
                            } else {
                              _professoresSelecionados.remove(id);
                            }
                            _ordenarProfessoresDisponiveis();
                          });
                        },
                        secondary: CircleAvatar(
                          backgroundColor:
                          isSelecionado ? selectedAccent : t.border,
                          child: Icon(
                            isSelecionado
                                ? Icons.check_rounded
                                : Icons.person_rounded,
                            color: isSelecionado
                                ? _readableOn(selectedAccent)
                                : t.textSecondary,
                            size: 20,
                          ),
                        ),
                        controlAffinity: ListTileControlAffinity.trailing,
                        activeColor: selectedAccent,
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

  Widget _buildProfessorBadge({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.09), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 10.5),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoUpload() {
    final t = context.uai;
    final hasLogo =
        _logoFile != null || (_logoUrlAtual != null && _logoUrlAtual!.isNotEmpty);

    return _buildCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Logo da Turma',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Material(
            color: t.cardAlt,
            borderRadius: BorderRadius.circular(t.inputRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _isLoading ? null : _escolherLogo,
              child: Container(
                height: 92,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.inputRadius),
                  border: Border.all(color: t.border),
                ),
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: t.primary))
                    : Row(
                  children: [
                    const SizedBox(width: 12),
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: t.card,
                        borderRadius:
                        BorderRadius.circular(t.inputRadius),
                        border: Border.all(color: t.border),
                      ),
                      child: ClipRRect(
                        borderRadius:
                        BorderRadius.circular(t.inputRadius - 1),
                        child: _logoFile != null
                            ? Image.file(_logoFile!, fit: BoxFit.cover)
                            : hasLogo
                            ? Image.network(
                          _logoUrlAtual!,
                          fit: BoxFit.cover,
                          cacheWidth: 180,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.image_not_supported_rounded,
                            color: t.textMuted,
                          ),
                        )
                            : Icon(
                          Icons.add_photo_alternate_rounded,
                          color: t.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        hasLogo
                            ? 'Toque para trocar a logo'
                            : 'Toque para adicionar uma logo',
                        style: TextStyle(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: _ensureVisible(t.primary, t.cardAlt),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcademiaHeaderLeve() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius),
        boxShadow: t.softShadow,
      ),
      child: Row(
        children: [
          Icon(Icons.business_rounded, color: onPrimary, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.academiaNome,
              style: TextStyle(
                color: onPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataInicioField() {
    final t = context.uai;
    final label = _dataInicioSelecionada == null
        ? 'Selecionar data de início'
        : DateFormat('dd/MM/yyyy').format(_dataInicioSelecionada!);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.inputRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _selecionarDataInicio,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.inputRadius),
              border: Border.all(color: t.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_month_rounded,
                  color: _ensureVisible(t.primary, t.cardAlt),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: _dataInicioSelecionada == null
                          ? t.textSecondary
                          : t.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: t.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _smallPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.09), t.cardAlt),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyBox({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final t = context.uai;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: t.textMuted, size: 34),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, {required _SnackType type}) {
    final t = context.uai;

    final color = switch (type) {
      _SnackType.success => t.success,
      _SnackType.error => t.error,
      _SnackType.warning => t.warning,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Editar Turma' : 'Nova Turma',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _isLoading ? null : _excluirTurma,
              tooltip: 'Excluir Turma',
            ),
        ],
      ),
      body: _isLoading && !_isEditing
          ? Center(child: CircularProgressIndicator(color: t.primary))
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAcademiaHeaderLeve(),
                    _buildSectionTitle(
                      'Informações Básicas',
                      Icons.info_outline_rounded,
                    ),
                    _buildCard(
                      Column(
                        children: [
                          _buildFormField(
                            controller: _nomeController,
                            label: 'Nome da Turma',
                            icon: Icons.group_rounded,
                            obrigatorio: true,
                          ),
                          _buildFormField(
                            controller: _nivelController,
                            label: 'Nível',
                            icon: Icons.star_rounded,
                            obrigatorio: true,
                            hintText:
                            'INICIANTE, INTERMEDIÁRIO, AVANÇADO',
                          ),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 560;

                              final faixa = _buildDropdownField(
                                value: _faixaEtariaSelecionada,
                                items: _faixaEtariaOptions,
                                label: 'Faixa Etária',
                                icon: Icons.people_rounded,
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() =>
                                    _faixaEtariaSelecionada = value);
                                  }
                                },
                              );

                              final status = _buildDropdownField(
                                value: _statusSelecionado,
                                items: _statusOptions,
                                label: 'Status',
                                icon: Icons.circle_rounded,
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(
                                          () => _statusSelecionado = value,
                                    );
                                  }
                                },
                              );

                              if (narrow) {
                                return Column(
                                  children: [
                                    faixa,
                                    status,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: faixa),
                                  const SizedBox(width: 12),
                                  Expanded(child: status),
                                ],
                              );
                            },
                          ),
                          _buildDataInicioField(),
                        ],
                      ),
                    ),
                    _buildSectionTitle('Professores', Icons.person_rounded),
                    _buildSelecaoProfessores(),
                    _buildSectionTitle(
                      'Dias e Horários',
                      Icons.calendar_today_rounded,
                    ),
                    _buildDiasSemanaComHorarios(),
                    _buildSectionTitle(
                      'Personalização',
                      Icons.palette_rounded,
                    ),
                    _buildLogoUpload(),
                    _buildCoresDisponiveis(),
                    _buildSectionTitle(
                      'Capacidade e Idades',
                      Icons.format_list_numbered_rounded,
                    ),
                    _buildCard(
                      Column(
                        children: [
                          _buildFormField(
                            controller: _capacidadeController,
                            label: 'Capacidade Máxima',
                            icon: Icons.people_rounded,
                            keyboardType: TextInputType.number,
                            obrigatorio: true,
                          ),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 560;

                              final idadeMin = _buildFormField(
                                controller: _idadeMinController,
                                label: 'Idade Mínima',
                                icon: Icons.child_care_rounded,
                                keyboardType: TextInputType.number,
                              );

                              final idadeMax = _buildFormField(
                                controller: _idadeMaxController,
                                label: 'Idade Máxima',
                                icon: Icons.person_rounded,
                                keyboardType: TextInputType.number,
                              );

                              if (narrow) {
                                return Column(
                                  children: [
                                    idadeMin,
                                    idadeMax,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: idadeMin),
                                  const SizedBox(width: 10),
                                  Expanded(child: idadeMax),
                                ],
                              );
                            },
                          ),
                          _buildFormField(
                            controller: _duracaoController,
                            label: 'Duração da Aula (minutos)',
                            icon: Icons.timer_rounded,
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                    ),
                    _buildSectionTitle(
                      'Configurações Avançadas',
                      Icons.settings_rounded,
                    ),
                    _buildCard(
                      Column(
                        children: [
                          _buildFormField(
                            controller: _pesoUsuarioAcessarController,
                            label: 'Peso de Acesso',
                            icon: Icons.lock_rounded,
                            keyboardType: TextInputType.number,
                            obrigatorio: true,
                            hintText:
                            'Comparar com peso_permissao do usuário',
                          ),
                        ],
                      ),
                    ),
                    _buildSectionTitle(
                      'Comunicação',
                      Icons.chat_rounded,
                    ),
                    _buildCard(
                      Column(
                        children: [
                          _buildFormField(
                            controller: _whatsappController,
                            label: 'Link do Grupo WhatsApp',
                            icon: Icons.chat_rounded,
                            keyboardType: TextInputType.url,
                            hintText: 'https://chat.whatsapp.com/...',
                          ),
                          _buildFormField(
                            controller: _msgConviteWhatsappController,
                            label: 'Mensagem de Convite',
                            icon: Icons.message_rounded,
                            maxLines: 4,
                            hintText: 'Digite a mensagem de convite...',
                          ),
                        ],
                      ),
                    ),
                    _buildSectionTitle('Observações', Icons.note_rounded),
                    _buildCard(
                      Column(
                        children: [
                          _buildFormField(
                            controller: _observacoesController,
                            label: 'Observações',
                            icon: Icons.note_rounded,
                            maxLines: 4,
                            hintText: 'Digite observações importantes...',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
            onPressed: _isLoading ? null : _salvarTurma,
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: _readableOn(t.primary),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
            icon: _isLoading
                ? SizedBox(
              width: 19,
              height: 19,
              child: CircularProgressIndicator(
                color: _readableOn(t.primary),
                strokeWidth: 2,
              ),
            )
                : Icon(_isEditing ? Icons.save_rounded : Icons.add_rounded),
            label: Text(_isEditing ? 'ATUALIZAR TURMA' : 'CRIAR TURMA'),
          ),
        ),
      ),
    );
  }
}

enum _SnackType {
  success,
  error,
  warning,
}
