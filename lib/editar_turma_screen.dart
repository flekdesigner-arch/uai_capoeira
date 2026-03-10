import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

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

  // Controllers
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _nivelController = TextEditingController();
  final TextEditingController _horarioInicioController = TextEditingController();
  final TextEditingController _horarioFimController = TextEditingController();
  final TextEditingController _capacidadeController = TextEditingController();
  final TextEditingController _idadeMinController = TextEditingController();
  final TextEditingController _idadeMaxController = TextEditingController();
  final TextEditingController _duracaoController = TextEditingController();
  final TextEditingController _observacoesController = TextEditingController();
  final TextEditingController _whatsappController = TextEditingController();
  final TextEditingController _pesoUsuarioAcessarController = TextEditingController();
  final TextEditingController _msgConviteWhatsappController = TextEditingController();

  // Valores selecionados
  String _faixaEtariaSelecionada = 'INFANTIL';
  String _statusSelecionado = 'ATIVA';
  DateTime? _dataInicioSelecionada;
  String _corSelecionada = '#059669';

  // Professores selecionados
  List<String> _professoresSelecionados = [];
  List<Map<String, dynamic>> _professoresDisponiveis = [];

  // Dias da semana e tipos de aula
  final Map<String, Map<String, dynamic>> _diasConfiguracao = {
    'SEGUNDA': {'selecionado': false, 'tipoAula': 'OBJETIVA'},
    'TERCA': {'selecionado': false, 'tipoAula': 'OBJETIVA'},
    'QUARTA': {'selecionado': false, 'tipoAula': 'OBJETIVA'},
    'QUINTA': {'selecionado': false, 'tipoAula': 'OBJETIVA'},
    'SEXTA': {'selecionado': false, 'tipoAula': 'OBJETIVA'},
    'SABADO': {'selecionado': false, 'tipoAula': 'OBJETIVA'},
    'DOMINGO': {'selecionado': false, 'tipoAula': 'OBJETIVA'},
  };

  // Logo
  String? _logoUrlAtual;
  String? _logoUrlNova;

  // Opções
  final List<String> _faixaEtariaOptions = ['INFANTIL', 'JUVENIL', 'ADULTO', 'SENIOR', 'MISTA'];
  final List<String> _statusOptions = ['ATIVA', 'INATIVA', 'ESGOTADA'];
  final List<String> _tiposAula = ['OBJETIVA', 'INSTRUMENTAÇÃO', 'RODA'];
  final List<String> _cores = [
    '#059669', '#3B82F6', '#8B5CF6', '#EF4444',
    '#F59E0B', '#10B981', '#6366F1', '#EC4899'
  ];

  final Map<String, String> _diasDisplay = {
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

  void _inicializarValoresPadrao() {
    _capacidadeController.text = '25';
    _duracaoController.text = '60';
    _idadeMinController.text = '6';
    _idadeMaxController.text = '12';
    _pesoUsuarioAcessarController.text = '1';
    _msgConviteWhatsappController.text = 'Olá! Você foi convidado(a) para participar do grupo da turma. Clique no link abaixo para entrar:\n\n';
  }

  Future<void> _carregarProfessores() async {
    try {
      final snapshot = await _firestore
          .collection('usuarios')
          .where('tipo', isEqualTo: 'professor')
          .get();

      setState(() {
        _professoresDisponiveis = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'nome': data['nome_completo'] ?? 'Sem nome',
            'email': data['email'] ?? 'Sem email',
          };
        }).toList();
      });
    } catch (e) {
      debugPrint('Erro ao carregar professores: $e');
    }
  }

  Future<void> _carregarTurma() async {
    setState(() => _isLoading = true);
    try {
      final doc = await _firestore
          .collection('turmas')
          .doc(widget.turmaId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;

        _nomeController.text = data['nome'] ?? '';
        _nivelController.text = data['nivel'] ?? '';
        _horarioInicioController.text = data['horario_inicio'] ?? '';
        _horarioFimController.text = data['horario_fim'] ?? '';
        _capacidadeController.text = (data['capacidade_maxima'] ?? 25).toString();
        _idadeMinController.text = (data['idade_minima'] ?? 6).toString();
        _idadeMaxController.text = (data['idade_maxima'] ?? 12).toString();
        _duracaoController.text = (data['duracao_aula_minutos'] ?? 60).toString();
        _observacoesController.text = data['observacoes'] ?? '';
        _whatsappController.text = data['whatsapp_url'] ?? '';
        _pesoUsuarioAcessarController.text = (data['peso_do_usuario_para_acessar'] ?? 1).toString();
        _msgConviteWhatsappController.text = data['msg_convite_grupo_whatsapp'] ?? '';

        _faixaEtariaSelecionada = data['faixa_etaria'] ?? 'INFANTIL';
        _statusSelecionado = data['status'] ?? 'ATIVA';
        _corSelecionada = data['cor_turma'] ?? '#059669';
        _logoUrlAtual = data['logo_url'];

        if (data['data_inicio'] != null) {
          _dataInicioSelecionada = (data['data_inicio'] as Timestamp).toDate();
        }

        // Carregar professores da turma
        final professoresIds = data['professores_ids'] as List<dynamic>? ?? [];
        setState(() {
          _professoresSelecionados = professoresIds.map((id) => id.toString()).toList();
        });

        // Dias da semana e tipos de aula
        final diasConfiguracao = data['dias_configuracao'] as Map<String, dynamic>?;
        if (diasConfiguracao != null) {
          for (var dia in _diasConfiguracao.keys) {
            if (diasConfiguracao.containsKey(dia)) {
              final config = diasConfiguracao[dia] as Map<String, dynamic>;
              _diasConfiguracao[dia] = {
                'selecionado': config['selecionado'] ?? false,
                'tipoAula': config['tipoAula'] ?? 'OBJETIVA',
              };
            }
          }
        } else {
          // Fallback para dados antigos
          final dias = data['dias_semana'] as List<dynamic>? ?? [];
          for (var dia in _diasConfiguracao.keys) {
            _diasConfiguracao[dia] = {
              'selecionado': dias.contains(dia),
              'tipoAula': 'OBJETIVA',
            };
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar turma: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar dados: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
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
      setState(() {
        _dataInicioSelecionada = dataSelecionada;
      });
    }
  }

  Future<void> _selecionarHorario(BuildContext context,
      TextEditingController controller) async {
    final TimeOfDay? horarioSelecionado = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (horarioSelecionado != null) {
      final formattedTime = horarioSelecionado.format(context);
      controller.text = formattedTime;
    }
  }

  Future<void> _escolherLogo() async {
    final XFile? imagem = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (imagem != null) {
      setState(() {
        _logoFile = File(imagem.path);
      });
      await _uploadLogo();
    }
  }

  Future<void> _uploadLogo() async {
    if (_logoFile == null) return;

    try {
      setState(() => _isLoading = true);

      final fileName = 'turma_logo_${DateTime.now().millisecondsSinceEpoch}_${widget.turmaId ?? 'nova'}';
      final Reference storageRef = _storage
          .ref()
          .child('turmas_logos')
          .child(widget.academiaId)
          .child(fileName);

      final UploadTask uploadTask = storageRef.putFile(_logoFile!);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      setState(() {
        _logoUrlNova = downloadUrl;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logo enviada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar logo: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecione pelo menos um dia da semana'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (_professoresSelecionados.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecione pelo menos um professor'),
            backgroundColor: Colors.red,
          ),
        );
      }
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

      final data = {
        'academia_id': widget.academiaId,
        'nucleo': widget.academiaNome,
        'nome': _nomeController.text.trim(),
        'nivel': _nivelController.text.trim().toUpperCase(),
        'faixa_etaria': _faixaEtariaSelecionada,
        'professores_ids': _professoresSelecionados,
        'professores_nomes': professoresNomes,
        'professor_principal': professoresNomes.isNotEmpty ? professoresNomes.first : '',
        'horario_inicio': _horarioInicioController.text.trim(),
        'horario_fim': _horarioFimController.text.trim(),
        'horario_display': '${_horarioInicioController.text} às ${_horarioFimController.text}',
        'capacidade_maxima': int.tryParse(_capacidadeController.text) ?? 25,
        'idade_minima': int.tryParse(_idadeMinController.text) ?? 6,
        'idade_maxima': int.tryParse(_idadeMaxController.text) ?? 12,
        'duracao_aula_minutos': int.tryParse(_duracaoController.text) ?? 60,
        'dias_semana': diasSelecionados,
        'dias_semana_display': diasSelecionados
            .map((dia) => _diasDisplay[dia] ?? dia)
            .toList(),
        'dias_configuracao': _diasConfiguracao.map((key, value) => MapEntry(key, {
          'selecionado': value['selecionado'],
          'tipoAula': value['tipoAula'],
        })),
        'status': _statusSelecionado,
        'cor_turma': _corSelecionada,
        'observacoes': _observacoesController.text.trim(),
        'whatsapp_url': _whatsappController.text.trim(),
        'msg_convite_grupo_whatsapp': _msgConviteWhatsappController.text.trim(),
        'peso_do_usuario_para_acessar': int.tryParse(_pesoUsuarioAcessarController.text) ?? 1,
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
        await _firestore
            .collection('turmas')
            .doc(widget.turmaId)
            .update(data);
      } else {
        data['criado_em'] = FieldValue.serverTimestamp();
        data['alunos_count'] = 0;
        data['alunos_ativos'] = 0;
        data['alunos_inativos'] = 0;

        await _firestore.collection('turmas').add(data);
      }

      await _atualizarContadorTurmas();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing
                  ? 'Turma atualizada com sucesso!'
                  : 'Turma criada com sucesso!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _atualizarContadorTurmas() async {
    try {
      final turmasSnapshot = await _firestore
          .collection('turmas')
          .where('academia_id', isEqualTo: widget.academiaId)
          .get();

      await _firestore
          .collection('academias')
          .doc(widget.academiaId)
          .update({
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

    await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Confirmar Exclusão'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tem certeza que deseja excluir esta turma?\n\nEsta ação não pode ser desfeita.',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Para confirmar, digite o nome da turma:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Center(
                      child: Text(
                        '"$nomeTurma"',
                        style: TextStyle(
                          color: Colors.red.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmacaoController,
                    decoration: InputDecoration(
                      labelText: 'Digite o nome da turma',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.warning),
                      suffixIcon: confirmacaoController.text.isNotEmpty
                          ? Icon(
                        confirmacaoController.text.trim() == nomeTurma
                            ? Icons.check_circle
                            : Icons.error,
                        color: confirmacaoController.text.trim() == nomeTurma
                            ? Colors.green
                            : Colors.red,
                      )
                          : null,
                    ),
                    onChanged: (value) {
                      setState(() {
                        nomeConfere = value.trim() == nomeTurma;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: nomeConfere
                      ? () => Navigator.pop(context, true)
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    backgroundColor: nomeConfere ? Colors.red.shade50 : Colors.grey.shade100,
                  ),
                  child: const Text('Excluir Turma'),
                ),
              ],
            );
          },
        );
      },
    ).then((confirmado) async {
      if (confirmado == true) {
        await _realizarExclusaoTurma();
      }
    });
  }

  Future<void> _realizarExclusaoTurma() async {
    setState(() => _isLoading = true);
    try {
      await _firestore
          .collection('turmas')
          .doc(widget.turmaId)
          .delete();

      await _atualizarContadorTurmas();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Turma excluída com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Widgets premium organizados
  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.red.shade800, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Widget child) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label + (obrigatorio ? ' *' : ''),
          hintText: hintText,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.red.shade700, width: 2),
          ),
          prefixIcon: Icon(icon, color: Colors.grey.shade600),
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        keyboardType: keyboardType,
        maxLines: maxLines ?? 1,
        validator: validator ?? (obrigatorio
            ? (value) {
          if (value == null || value.isEmpty) {
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
    required Function(String?) onChanged,
    String? hintText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.red.shade700, width: 2),
          ),
          prefixIcon: Icon(icon, color: Colors.grey.shade600),
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            icon: Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
            style: const TextStyle(color: Colors.black87, fontSize: 16),
            items: items.map((String item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(item),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildTimeField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required BuildContext context,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.red.shade700, width: 2),
          ),
          prefixIcon: Icon(icon, color: Colors.grey.shade600),
          suffixIcon: IconButton(
            icon: Icon(Icons.access_time, color: Colors.grey.shade600),
            onPressed: () => _selecionarHorario(context, controller),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        readOnly: true,
        onTap: () => _selecionarHorario(context, controller),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Campo obrigatório';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildDiasSemanaComTipoAula() {
    return _buildCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configuração de Dias e Tipos de Aula *',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Selecione os dias da semana e defina o tipo de aula para cada dia:',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 16),
          ..._diasConfiguracao.entries.map((entry) {
            final dia = entry.key;
            final config = entry.value;
            final selecionado = config['selecionado'] as bool;
            final tipoAula = config['tipoAula'] as String;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                elevation: selecionado ? 2 : 0,
                color: selecionado ? Colors.red.shade50 : Colors.grey.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: selecionado ? Colors.red.shade200 : Colors.grey.shade300,
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Checkbox(
                        value: selecionado,
                        onChanged: (value) {
                          setState(() {
                            _diasConfiguracao[dia] = {
                              'selecionado': value ?? false,
                              'tipoAula': tipoAula,
                            };
                          });
                        },
                        activeColor: Colors.red.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _diasDisplay[dia] ?? dia,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: selecionado ? Colors.black87 : Colors.grey.shade600,
                          ),
                        ),
                      ),
                      if (selecionado) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            'Tipo:',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Container(
                          width: 150,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: tipoAula,
                              isExpanded: true,
                              icon: Icon(Icons.arrow_drop_down, size: 20),
                              style: TextStyle(
                                fontSize: 14,
                                color: selecionado ? Colors.black87 : Colors.grey.shade600,
                              ),
                              items: _tiposAula.map((String tipo) {
                                Color tipoColor;
                                switch (tipo) {
                                  case 'OBJETIVA':
                                    tipoColor = Colors.blue;
                                    break;
                                  case 'INSTRUMENTAÇÃO':
                                    tipoColor = Colors.green;
                                    break;
                                  case 'RODA':
                                    tipoColor = Colors.purple;
                                    break;
                                  default:
                                    tipoColor = Colors.grey;
                                }

                                return DropdownMenuItem<String>(
                                  value: tipo,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          color: tipoColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      Expanded(  // ADICIONAR ESSE Expanded
                                        child: Text(
                                          tipo,
                                          overflow: TextOverflow.ellipsis,  // Adicionar overflow também
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: selecionado
                                  ? (String? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    _diasConfiguracao[dia] = {
                                      'selecionado': true,
                                      'tipoAula': newValue,
                                    };
                                  });
                                }
                              }
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
          if (_diasConfiguracao.entries.where((e) => e.value['selecionado']).isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Nenhum dia selecionado',
                style: TextStyle(
                  color: Colors.orange.shade700,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCoresDisponiveis() {
    return _buildCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cor da Turma',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _cores.map((cor) {
              final isSelecionada = _corSelecionada == cor;
              return GestureDetector(
                onTap: () {
                  setState(() => _corSelecionada = cor);
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(int.parse(cor.replaceFirst('#', '0xFF'))),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelecionada ? Colors.black : Colors.transparent,
                      width: isSelecionada ? 3 : 0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: isSelecionada
                      ? const Center(
                    child: Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 20,
                    ),
                  )
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            'Cor selecionada: ${_corSelecionada}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSelecaoProfessores() {
    return _buildCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Professores *',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          if (_professoresDisponiveis.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  'Nenhum professor cadastrado na academia',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            Column(
              children: _professoresDisponiveis.map((professor) {
                final isSelecionado = _professoresSelecionados.contains(professor['id']);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  color: isSelecionado ? Colors.red.shade50 : Colors.grey.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isSelecionado ? Colors.red.shade200 : Colors.grey.shade300,
                    ),
                  ),
                  child: CheckboxListTile(
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          professor['nome'],
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: isSelecionado ? Colors.black87 : Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          professor['email'],
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelecionado ? Colors.grey.shade600 : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    value: isSelecionado,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _professoresSelecionados.add(professor['id']);
                        } else {
                          _professoresSelecionados.remove(professor['id']);
                        }
                      });
                    },
                    secondary: Icon(
                      Icons.person,
                      color: isSelecionado ? Colors.red.shade700 : Colors.grey.shade600,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: Colors.red.shade700,
                  ),
                );
              }).toList(),
            ),
          if (_professoresDisponiveis.isNotEmpty && _professoresSelecionados.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Selecione pelo menos um professor',
                style: TextStyle(
                  color: Colors.orange.shade700,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogoUpload() {
    return _buildCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Logo da Turma',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _isLoading ? null : _escolherLogo,
            child: Container(
              width: double.infinity,
              height: 180,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.grey.shade300,
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _logoFile != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  _logoFile!,
                  fit: BoxFit.cover,
                ),
              )
                  : _logoUrlAtual != null && _logoUrlAtual!.isNotEmpty
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  _logoUrlAtual!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildPlaceholderLogo();
                  },
                ),
              )
                  : _buildPlaceholderLogo(),
            ),
          ),
          if (_logoUrlAtual != null || _logoFile != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _logoFile != null
                        ? 'Nova logo selecionada'
                        : 'Logo atual da turma',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderLogo() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_photo_alternate,
          size: 60,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 12),
        Text(
          'Toque para adicionar uma logo',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Recomendado: 500x500px',
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildDataInicio() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        decoration: InputDecoration(
          labelText: 'Data de Início',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.red.shade700, width: 2),
          ),
          prefixIcon: Icon(Icons.calendar_today, color: Colors.grey.shade600),
          suffixIcon: IconButton(
            icon: Icon(Icons.calendar_month, color: Colors.grey.shade600),
            onPressed: _selecionarDataInicio,
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        readOnly: true,
        onTap: _selecionarDataInicio,
        controller: TextEditingController(
          text: _dataInicioSelecionada != null
              ? DateFormat('dd/MM/yyyy').format(_dataInicioSelecionada!)
              : '',
        ),
      ),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Editar Turma' : 'Nova Turma',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _isLoading ? null : _excluirTurma,
              tooltip: 'Excluir Turma',
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading && !_isEditing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header com informações da academia
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.red.shade900,
                        Colors.red.shade700,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.business, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.academiaNome,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Colors.white,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ID: ${widget.academiaId.substring(0, 8)}...',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Seção: Informações Básicas
              _buildSectionTitle('Informações Básicas', Icons.info_outline),
              _buildCard(
                Column(
                  children: [
                    _buildFormField(
                      controller: _nomeController,
                      label: 'Nome da Turma',
                      icon: Icons.group,
                      obrigatorio: true,
                      hintText: 'Ex: Turma Infantil Iniciante',
                    ),
                    _buildFormField(
                      controller: _nivelController,
                      label: 'Nível',
                      icon: Icons.star,
                      obrigatorio: true,
                      hintText: 'INICIANTE, INTERMEDIÁRIO, AVANÇADO',
                    ),
                    _buildDropdownField(
                      value: _faixaEtariaSelecionada,
                      items: _faixaEtariaOptions,
                      label: 'Faixa Etária',
                      icon: Icons.people,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _faixaEtariaSelecionada = value);
                        }
                      },
                    ),
                    _buildDropdownField(
                      value: _statusSelecionado,
                      items: _statusOptions,
                      label: 'Status',
                      icon: Icons.circle,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _statusSelecionado = value);
                        }
                      },
                    ),
                  ],
                ),
              ),

              // Seção: Professores
              const SizedBox(height: 8),
              _buildSectionTitle('Professores', Icons.person),
              _buildSelecaoProfessores(),

              // Seção: Horários e Dias
              const SizedBox(height: 8),
              _buildSectionTitle('Horários e Dias', Icons.access_time),
              _buildCard(
                Column(
                  children: [
                    _buildTimeField(
                      controller: _horarioInicioController,
                      label: 'Horário de Início',
                      icon: Icons.access_time,
                      context: context,
                    ),
                    _buildTimeField(
                      controller: _horarioFimController,
                      label: 'Horário de Término',
                      icon: Icons.access_time,
                      context: context,
                    ),
                    _buildDataInicio(),
                  ],
                ),
              ),

              // Configuração de Dias e Tipos de Aula
              const SizedBox(height: 8),
              _buildDiasSemanaComTipoAula(),

              // Seção: Personalização
              const SizedBox(height: 8),
              _buildSectionTitle('Personalização', Icons.palette),
              _buildLogoUpload(),
              const SizedBox(height: 8),
              _buildCoresDisponiveis(),

              // Seção: Capacidade e Idades
              const SizedBox(height: 8),
              _buildSectionTitle('Capacidade e Idades', Icons.format_list_numbered),
              _buildCard(
                Column(
                  children: [
                    _buildFormField(
                      controller: _capacidadeController,
                      label: 'Capacidade Máxima de Alunos',
                      icon: Icons.format_list_numbered,
                      keyboardType: TextInputType.number,
                      obrigatorio: true,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _buildFormField(
                            controller: _idadeMinController,
                            label: 'Idade Mínima',
                            icon: Icons.child_care,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildFormField(
                            controller: _idadeMaxController,
                            label: 'Idade Máxima',
                            icon: Icons.person,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    _buildFormField(
                      controller: _duracaoController,
                      label: 'Duração da Aula (minutos)',
                      icon: Icons.timer,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),

              // Seção: Configurações Avançadas
              const SizedBox(height: 8),
              _buildSectionTitle('Configurações Avançadas', Icons.settings),
              _buildCard(
                Column(
                  children: [
                    _buildFormField(
                      controller: _pesoUsuarioAcessarController,
                      label: 'Peso de Acesso do Usuário',
                      icon: Icons.lock,
                      keyboardType: TextInputType.number,
                      obrigatorio: true,
                      hintText: 'Comparar com peso_permissao do usuário',
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Campo obrigatório';
                        }
                        final peso = int.tryParse(value);
                        if (peso == null || peso < 1) {
                          return 'Digite um número válido (≥ 1)';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),

              // Seção: Comunicação
              const SizedBox(height: 8),
              _buildSectionTitle('Comunicação', Icons.chat),
              _buildCard(
                Column(
                  children: [
                    _buildFormField(
                      controller: _whatsappController,
                      label: 'Link do Grupo WhatsApp',
                      icon: Icons.chat,
                      keyboardType: TextInputType.url,
                      hintText: 'https://chat.whatsapp.com/...',
                    ),
                    const SizedBox(height: 16),
                    _buildFormField(
                      controller: _msgConviteWhatsappController,
                      label: 'Mensagem de Convite',
                      icon: Icons.message,
                      maxLines: 4,
                      hintText: 'Digite a mensagem de convite para o grupo...',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Esta mensagem será enviada junto com o link do grupo',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),

              // Seção: Observações
              const SizedBox(height: 8),
              _buildSectionTitle('Observações', Icons.note),
              _buildCard(
                Column(
                  children: [
                    _buildFormField(
                      controller: _observacoesController,
                      label: 'Observações Adicionais',
                      icon: Icons.note,
                      maxLines: 4,
                      hintText: 'Digite observações importantes sobre a turma...',
                    ),
                  ],
                ),
              ),

              // Botão Salvar
              const SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _salvarTurma,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade900,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        icon: _isLoading
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                            : Icon(
                          _isEditing ? Icons.save : Icons.add,
                          color: Colors.white,
                        ),
                        label: Text(
                          _isEditing ? 'ATUALIZAR TURMA' : 'CRIAR NOVA TURMA',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_isEditing)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            side: BorderSide(color: Colors.grey.shade400),
                          ),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text(
                            'CANCELAR',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }}