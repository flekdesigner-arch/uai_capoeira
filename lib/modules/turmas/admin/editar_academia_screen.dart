import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class EditarAcademiaScreen extends StatefulWidget {
  final String? academiaId;

  const EditarAcademiaScreen({super.key, this.academiaId});

  @override
  State<EditarAcademiaScreen> createState() => _EditarAcademiaScreenState();
}

class _EditarAcademiaScreenState extends State<EditarAcademiaScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool get _isEditing => widget.academiaId != null;
  bool _isLoading = false;
  bool _usuariosCarregando = false;

  String? _academiaId;

  List<Map<String, dynamic>> _todosUsuarios = [];
  List<Map<String, dynamic>> _usuariosDisponiveis = [];
  List<Map<String, dynamic>> _professoresDisponiveis = [];

  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _cidadeController = TextEditingController();
  final TextEditingController _enderecoController = TextEditingController();
  final TextEditingController _telefoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _whatsappController = TextEditingController();
  final TextEditingController _logoUrlController = TextEditingController();
  final TextEditingController _observacoesController = TextEditingController();

  String _modalidadeSelecionada = 'CAPOEIRA';
  String _statusSelecionado = 'ativa';
  String? _responsavelSelecionadoId;
  String _responsavelNome = '';
  List<String> _professoresSelecionadosIds = [];
  List<String> _professoresSelecionadosNomes = [];

  List<String> _professoresAnterioresIds = [];
  String? _responsavelAnteriorId;

  final List<String> _modalidades = const [
    'CAPOEIRA',
    'JIU-JITSU',
    'MUAY THAI',
    'KARATÊ',
    'JUDÔ',
    'TAEKWONDO',
    'BOXING',
    'MMA',
    'OUTROS',
  ];

  final List<String> _statusOptions = const ['ativa', 'inativa'];

  @override
  void initState() {
    super.initState();
    _academiaId = widget.academiaId;
    _carregarUsuarios();

    if (_isEditing) {
      _carregarAcademia();
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _cidadeController.dispose();
    _enderecoController.dispose();
    _telefoneController.dispose();
    _emailController.dispose();
    _whatsappController.dispose();
    _logoUrlController.dispose();
    _observacoesController.dispose();
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

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _carregarUsuarios() async {
    if (mounted) setState(() => _usuariosCarregando = true);

    try {
      final snapshot = await _firestore.collection('usuarios').get();

      final todos = snapshot.docs.map((doc) {
        final data = doc.data();

        return {
          'id': doc.id,
          'nome': data['nome_completo'] ?? data['name'] ?? 'Sem nome',
          'email': data['email'] ?? 'Sem email',
          'tipo': data['tipo'] ?? 'aluno',
          'peso_permissao': data['peso_permissao'] ?? 0,
          'status_conta': data['status_conta'] ?? 'pendente',
          'contato': data['contato'] ?? '',
          'foto_url': data['foto_url'] as String?,
        };
      }).toList();

      final usuariosDisponiveis = todos.where((user) {
        final peso = _toInt(user['peso_permissao']);
        final status = user['status_conta']?.toString().toLowerCase() ?? '';
        return peso >= 50 && status == 'ativa';
      }).toList();

      final professoresDisponiveis = todos.where((user) {
        final tipo = user['tipo']?.toString().toLowerCase() ?? '';
        final peso = _toInt(user['peso_permissao']);
        final status = user['status_conta']?.toString().toLowerCase() ?? '';
        final isProfessorOuAdmin =
            tipo == 'professor' || tipo == 'administrador' || tipo == 'admin';

        return isProfessorOuAdmin && peso >= 50 && status == 'ativa';
      }).toList();

      if (!mounted) return;

      setState(() {
        _todosUsuarios = todos;
        _usuariosDisponiveis = usuariosDisponiveis;
        _professoresDisponiveis = professoresDisponiveis;
      });

      // Quando a academia abre antes da lista de usuários terminar,
      // tenta completar os nomes depois que os usuários chegam.
      if (_responsavelSelecionadoId != null && _responsavelNome.isEmpty) {
        _atualizarNomeResponsavelSelecionado(_responsavelSelecionadoId);
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar usuários: $e');

      if (mounted) {
        _showSnack(
          'Erro ao carregar usuários: $e',
          type: _SnackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _usuariosCarregando = false);
    }
  }

  Future<void> _carregarAcademia() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final doc =
      await _firestore.collection('academias').doc(_academiaId).get();

      if (!doc.exists || doc.data() == null) return;

      final data = doc.data()!;

      _nomeController.text = data['nome']?.toString() ?? '';
      _cidadeController.text = data['cidade']?.toString() ?? '';
      _enderecoController.text = data['endereco']?.toString() ?? '';
      _telefoneController.text = data['telefone']?.toString() ?? '';
      _emailController.text = data['email']?.toString() ?? '';
      _whatsappController.text =
          data['whatsapp']?.toString() ?? data['whatsapp_url']?.toString() ?? '';
      _logoUrlController.text = data['logo_url']?.toString() ?? '';
      _observacoesController.text = data['observacoes']?.toString() ?? '';

      final professoresIds = data['professores_ids'] as List<dynamic>? ?? [];
      final professoresNomes = data['professores_nomes'] as List<dynamic>? ?? [];
      final responsavelId = data['responsavel_id']?.toString();

      if (!mounted) return;

      setState(() {
        _modalidadeSelecionada =
            data['modalidade']?.toString() ?? 'CAPOEIRA';
        _statusSelecionado = data['status']?.toString() ?? 'ativa';

        _responsavelSelecionadoId =
        responsavelId != null && responsavelId.isNotEmpty
            ? responsavelId
            : null;
        _responsavelAnteriorId = _responsavelSelecionadoId;

        _responsavelNome = data['responsavel']?.toString() ??
            data['responsavel_nome']?.toString() ??
            '';

        _professoresSelecionadosIds =
            professoresIds.map((id) => id.toString()).toList();
        _professoresAnterioresIds =
        List<String>.from(_professoresSelecionadosIds);
        _professoresSelecionadosNomes =
            professoresNomes.map((nome) => nome.toString()).toList();
      });

      if (_responsavelSelecionadoId != null &&
          (_responsavelNome.isEmpty ||
              _responsavelNome == 'Erro ao carregar' ||
              _responsavelNome == 'Usuário não encontrado')) {
        await _buscarNomeResponsavelPorId(_responsavelSelecionadoId!);
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar academia: $e');

      if (mounted) {
        _showSnack(
          'Erro ao carregar dados: $e',
          type: _SnackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _atualizarNomeResponsavelSelecionado(String? responsavelId) {
    if (responsavelId == null) return;

    final responsavel = _todosUsuarios.firstWhere(
          (user) => user['id'] == responsavelId,
      orElse: () => {},
    );

    if (responsavel.isEmpty) return;

    setState(() {
      _responsavelNome = responsavel['nome']?.toString() ?? '';
    });
  }

  Future<void> _buscarNomeResponsavelPorId(String responsavelId) async {
    try {
      final responsavelDoc =
      await _firestore.collection('usuarios').doc(responsavelId).get();

      if (!mounted) return;

      if (responsavelDoc.exists && responsavelDoc.data() != null) {
        final responsavelData = responsavelDoc.data()!;

        setState(() {
          _responsavelNome = responsavelData['nome_completo']?.toString() ??
              responsavelData['name']?.toString() ??
              'Responsável';
        });
      } else {
        setState(() => _responsavelNome = 'Usuário não encontrado');
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar responsável: $e');
      if (mounted) setState(() => _responsavelNome = 'Erro ao carregar');
    }
  }

  Future<void> _atualizarVinculoUsuario(
      String usuarioId,
      bool adicionar,
      ) async {
    if (_academiaId == null) {
      debugPrint('❌ _academiaId é null, não é possível vincular');
      return;
    }

    try {
      final userRef = _firestore.collection('usuarios').doc(usuarioId);
      final userDoc = await userRef.get();

      if (!userDoc.exists) {
        debugPrint('❌ Usuário $usuarioId não existe!');
        return;
      }

      if (adicionar) {
        await userRef.update({
          'academias': FieldValue.arrayUnion([_academiaId]),
        });
      } else {
        await userRef.update({
          'academias': FieldValue.arrayRemove([_academiaId]),
        });
      }
    } catch (e) {
      debugPrint('❌ ERRO ao atualizar vínculo: $e');
    }
  }

  Future<void> _mostrarDialogProfessores() async {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.surface);
    final info = _ensureVisible(t.info, t.surface);
    final success = _ensureVisible(t.success, t.surface);

    List<String> selecaoTemporaria = List.from(_professoresSelecionadosIds);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.all(14),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.84,
                  maxWidth: 560,
                ),
                child: Material(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(t.cardRadius + 2),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 18, 8, 14),
                        decoration: BoxDecoration(
                          gradient: t.primaryGradient,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: _readableOn(t.primary).withOpacity(0.14),
                                borderRadius:
                                BorderRadius.circular(t.buttonRadius),
                                border: Border.all(
                                  color:
                                  _readableOn(t.primary).withOpacity(0.16),
                                ),
                              ),
                              child: Icon(
                                Icons.people_rounded,
                                color: _readableOn(t.primary),
                                size: 27,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Gerenciar Professores',
                                    style: TextStyle(
                                      color: _readableOn(t.primary),
                                      fontSize: 19,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Selecione quem terá acesso à academia.',
                                    style: TextStyle(
                                      color: _readableOn(t.primary)
                                          .withOpacity(0.78),
                                      fontSize: 12,
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              icon: Icon(
                                Icons.close_rounded,
                                color: _readableOn(t.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _usuariosCarregando
                            ? Center(
                          child: CircularProgressIndicator(
                            color: t.primary,
                          ),
                        )
                            : _professoresDisponiveis.isEmpty
                            ? _dialogEmptyProfessores()
                            : ListView.builder(
                          padding: const EdgeInsets.all(14),
                          itemCount: _professoresDisponiveis.length,
                          itemBuilder: (context, index) {
                            final professor =
                            _professoresDisponiveis[index];
                            final id = professor['id']?.toString() ?? '';
                            final isSelecionado =
                            selecaoTemporaria.contains(id);

                            return Padding(
                              padding:
                              const EdgeInsets.only(bottom: 10),
                              child: Material(
                                color: isSelecionado
                                    ? Color.alphaBlend(
                                  primary.withOpacity(0.10),
                                  t.cardAlt,
                                )
                                    : t.cardAlt,
                                borderRadius: BorderRadius.circular(
                                  t.inputRadius,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () {
                                    setDialogState(() {
                                      if (isSelecionado) {
                                        selecaoTemporaria.remove(id);
                                      } else if (id.isNotEmpty) {
                                        selecaoTemporaria.add(id);
                                      }
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      borderRadius:
                                      BorderRadius.circular(
                                        t.inputRadius,
                                      ),
                                      border: Border.all(
                                        color: isSelecionado
                                            ? primary.withOpacity(0.34)
                                            : t.border,
                                        width: isSelecionado ? 1.3 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        _professorAvatar(
                                          professor: professor,
                                          selected: isSelecionado,
                                          accent: primary,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                professor['nome']
                                                    ?.toString() ??
                                                    'Sem nome',
                                                maxLines: 1,
                                                overflow:
                                                TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: isSelecionado
                                                      ? primary
                                                      : t.textPrimary,
                                                  fontSize: 15,
                                                  fontWeight:
                                                  FontWeight.w900,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                professor['email']
                                                    ?.toString() ??
                                                    'Sem email',
                                                maxLines: 1,
                                                overflow:
                                                TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color:
                                                  t.textSecondary,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 7),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: [
                                                  _miniBadge(
                                                    label: professor[
                                                    'tipo']
                                                        ?.toString()
                                                        .toUpperCase() ??
                                                        'PROFESSOR',
                                                    color: info,
                                                    icon: Icons
                                                        .badge_rounded,
                                                  ),
                                                  _miniBadge(
                                                    label:
                                                    'Peso ${professor['peso_permissao'] ?? 0}',
                                                    color: success,
                                                    icon: Icons
                                                        .security_rounded,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isSelecionado
                                                ? primary
                                                : Colors.transparent,
                                            border: Border.all(
                                              color: isSelecionado
                                                  ? primary
                                                  : t.border,
                                              width: 2,
                                            ),
                                          ),
                                          child: isSelecionado
                                              ? Icon(
                                            Icons.check_rounded,
                                            color:
                                            _readableOn(primary),
                                            size: 18,
                                          )
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: t.card,
                          border: Border(top: BorderSide(color: t.border)),
                        ),
                        child: Column(
                          children: [
                            _infoBox(
                              icon: Icons.info_outline_rounded,
                              color: t.info,
                              text:
                              '${selecaoTemporaria.length} professor(es) selecionado(s)',
                            ),
                            const SizedBox(height: 12),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final narrow = constraints.maxWidth < 380;

                                final cancel = OutlinedButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: t.textPrimary,
                                    side: BorderSide(color: t.border),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        t.buttonRadius,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    'CANCELAR',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                );

                                final confirm = ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _professoresSelecionadosIds =
                                      List<String>.from(selecaoTemporaria);
                                    });
                                    Navigator.pop(dialogContext);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: t.primary,
                                    foregroundColor: _readableOn(t.primary),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        t.buttonRadius,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    'CONFIRMAR',
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
                                      confirm,
                                    ],
                                  );
                                }

                                return Row(
                                  children: [
                                    Expanded(child: cancel),
                                    const SizedBox(width: 10),
                                    Expanded(child: confirm),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _dialogEmptyProfessores() {
    final t = context.uai;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_rounded, size: 58, color: t.textMuted),
            const SizedBox(height: 14),
            Text(
              'Nenhum professor disponível',
              style: TextStyle(
                fontSize: 16,
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Não há professores com peso_permissao ≥ 50 e conta ativa.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: t.textSecondary,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _professorAvatar({
    required Map<String, dynamic> professor,
    required bool selected,
    required Color accent,
  }) {
    final t = context.uai;
    final fotoUrl = professor['foto_url']?.toString();

    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? accent : t.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: ClipOval(
        child: fotoUrl != null && fotoUrl.isNotEmpty
            ? Image.network(
          fotoUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _avatarFallback(selected: selected, accent: accent);
          },
        )
            : _avatarFallback(selected: selected, accent: accent),
      ),
    );
  }

  Widget _avatarFallback({
    required bool selected,
    required Color accent,
  }) {
    final t = context.uai;

    return Container(
      color: selected
          ? Color.alphaBlend(accent.withOpacity(0.14), t.cardAlt)
          : t.cardAlt,
      child: Icon(
        Icons.person_rounded,
        color: selected ? accent : t.textMuted,
        size: 28,
      ),
    );
  }

  Widget _miniBadge({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.10), t.cardAlt),
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

  Future<void> _salvarAcademia() async {
    if (!_formKey.currentState!.validate()) return;

    if (_responsavelSelecionadoId == null) {
      _showSnack(
        'Selecione um responsável para a academia',
        type: _SnackType.error,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String responsavelNome = _responsavelNome;

      if (responsavelNome.isEmpty ||
          responsavelNome == 'Erro ao carregar' ||
          responsavelNome == 'Usuário não encontrado') {
        final responsavel = _usuariosDisponiveis.firstWhere(
              (user) => user['id'] == _responsavelSelecionadoId,
          orElse: () => {'nome': 'Responsável não encontrado'},
        );
        responsavelNome = responsavel['nome']?.toString() ?? '';
      }

      final professoresNomes = _professoresSelecionadosIds.map((id) {
        final professor = _professoresDisponiveis.firstWhere(
              (p) => p['id'] == id,
          orElse: () => _usuariosDisponiveis.firstWhere(
                (u) => u['id'] == id,
            orElse: () => {'nome': 'Professor não encontrado'},
          ),
        );

        return professor['nome'];
      }).toList();

      final data = {
        'nome': _nomeController.text.trim().toUpperCase(),
        'cidade': _cidadeController.text.trim().toUpperCase(),
        'endereco': _enderecoController.text.trim(),
        'responsavel_id': _responsavelSelecionadoId,
        'responsavel': responsavelNome,
        'responsavel_nome': responsavelNome,
        'telefone': _telefoneController.text.trim(),
        'email': _emailController.text.trim(),
        'whatsapp': _whatsappController.text.trim(),
        'whatsapp_url': _whatsappController.text.trim(),
        'logo_url': _logoUrlController.text.trim(),
        'observacoes': _observacoesController.text.trim(),
        'modalidade': _modalidadeSelecionada,
        'status': _statusSelecionado,
        'professores_ids': _professoresSelecionadosIds,
        'professores_nomes': professoresNomes,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      };

      if (_isEditing) {
        await _firestore.collection('academias').doc(_academiaId).update(data);

        if (_responsavelAnteriorId != null &&
            _responsavelAnteriorId != _responsavelSelecionadoId) {
          await _atualizarVinculoUsuario(_responsavelAnteriorId!, false);
        }

        if (_responsavelSelecionadoId != null) {
          await _atualizarVinculoUsuario(_responsavelSelecionadoId!, true);
        }

        final todosProfessores = _professoresSelecionadosIds.toSet();

        if (_responsavelSelecionadoId != null) {
          todosProfessores.add(_responsavelSelecionadoId!);
        }

        for (final professorId in todosProfessores) {
          await _atualizarVinculoUsuario(professorId, true);
        }

        final todosProfessoresAnteriores = _professoresAnterioresIds.toSet();

        if (_responsavelAnteriorId != null) {
          todosProfessoresAnteriores.add(_responsavelAnteriorId!);
        }

        final removidos = todosProfessoresAnteriores.difference(
          todosProfessores,
        );

        for (final id in removidos) {
          await _atualizarVinculoUsuario(id, false);
        }

        if (mounted) {
          _showSnack(
            'Academia atualizada com sucesso!',
            type: _SnackType.success,
          );
        }
      } else {
        data['data_cadastro'] = FieldValue.serverTimestamp();
        data['turmas_count'] = 0;

        final docRef = await _firestore.collection('academias').add(data);
        _academiaId = docRef.id;

        final todosParaVincular = <String>{};

        if (_responsavelSelecionadoId != null) {
          todosParaVincular.add(_responsavelSelecionadoId!);
        }

        todosParaVincular.addAll(_professoresSelecionadosIds);

        for (final usuarioId in todosParaVincular) {
          await _atualizarVinculoUsuario(usuarioId, true);
        }

        if (mounted) {
          _showSnack(
            'Academia criada com sucesso!',
            type: _SnackType.success,
          );
        }
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('❌ Erro ao salvar: $e');

      if (mounted) {
        _showSnack(
          'Erro ao salvar: $e',
          type: _SnackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _excluirAcademia() async {
    if (_academiaId == null) return;

    setState(() => _isLoading = true);

    QuerySnapshot<Map<String, dynamic>> turmasSnapshot;

    try {
      turmasSnapshot = await _firestore
          .collection('turmas')
          .where('academia_id', isEqualTo: _academiaId)
          .get();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnack(
          'Erro ao verificar turmas: $e',
          type: _SnackType.error,
        );
      }
      return;
    }

    if (mounted) setState(() => _isLoading = false);

    final temTurmasAtivas = turmasSnapshot.docs.isNotEmpty;
    final nomeAcademia = _nomeController.text.trim().toUpperCase();

    final confirmar = await _confirmarExclusaoAcademia(
      nomeAcademia: nomeAcademia,
      totalTurmas: turmasSnapshot.docs.length,
      temTurmasAtivas: temTurmasAtivas,
    );

    if (confirmar == true) {
      await _realizarExclusaoAcademia(turmasSnapshot);
    }
  }

  Future<bool?> _confirmarExclusaoAcademia({
    required String nomeAcademia,
    required int totalTurmas,
    required bool temTurmasAtivas,
  }) async {
    final t = context.uai;
    final confirmacaoController = TextEditingController();
    bool nomeConfere = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final currentConfere =
                confirmacaoController.text.trim().toUpperCase() ==
                    nomeAcademia;

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
                                  color: t.error.withOpacity(0.12),
                                  borderRadius:
                                  BorderRadius.circular(t.buttonRadius),
                                ),
                                child: Icon(
                                  Icons.warning_rounded,
                                  color: _ensureVisible(t.error, t.surface),
                                ),
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
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            temTurmasAtivas
                                ? 'Esta academia possui $totalTurmas turma(s). Todas as turmas também serão excluídas.'
                                : 'Tem certeza que deseja excluir esta academia? Esta ação não pode ser desfeita.',
                            style: TextStyle(
                              color: t.textSecondary,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Para confirmar, digite o nome da academia:',
                            style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _dangerNameBox(nomeAcademia),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: confirmacaoController,
                            style: TextStyle(color: t.textPrimary),
                            decoration: _inputDecoration(
                              label: 'Digite o nome da academia',
                              icon: Icons.warning_rounded,
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
                                nomeConfere =
                                    value.trim().toUpperCase() == nomeAcademia;
                              });
                            },
                            textCapitalization: TextCapitalization.characters,
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
                                  'EXCLUIR',
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
    return result;
  }

  Widget _dangerNameBox(String nomeAcademia) {
    final t = context.uai;
    final error = _ensureVisible(t.error, t.cardAlt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(error.withOpacity(0.10), t.cardAlt),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: error.withOpacity(0.18)),
      ),
      child: Text(
        '"$nomeAcademia"',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: error,
          fontWeight: FontWeight.w900,
          fontSize: 15,
        ),
      ),
    );
  }

  Future<void> _realizarExclusaoAcademia(
      QuerySnapshot<Map<String, dynamic>> turmasSnapshot,
      ) async {
    setState(() => _isLoading = true);

    try {
      final todosUsuarios = <String>{};

      if (_responsavelSelecionadoId != null) {
        todosUsuarios.add(_responsavelSelecionadoId!);
      }

      todosUsuarios.addAll(_professoresSelecionadosIds);

      for (final usuarioId in todosUsuarios) {
        await _atualizarVinculoUsuario(usuarioId, false);
      }

      for (final turma in turmasSnapshot.docs) {
        await turma.reference.delete();
      }

      await _firestore.collection('academias').doc(_academiaId).delete();

      if (mounted) {
        _showSnack(
          'Academia excluída com sucesso!',
          type: _SnackType.success,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('❌ Erro ao excluir: $e');

      if (mounted) {
        _showSnack(
          'Erro ao excluir: $e',
          type: _SnackType.error,
        );
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
      prefixIcon: icon == null ? null : Icon(icon, color: primary),
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

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obrigatorio = false,
    TextInputType? keyboardType,
    int? maxLines,
    String? Function(String?)? validator,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        style: TextStyle(color: context.uai.textPrimary),
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
        decoration: _inputDecoration(
          label: label + (obrigatorio ? ' *' : ''),
          icon: icon,
          hint: hint,
        ).copyWith(
          alignLabelWithHint: (maxLines ?? 1) > 1,
        ),
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
        items: normalizedItems.map((String item) {
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

  Widget _buildSelecaoResponsavel() {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);
    final success = _ensureVisible(t.success, t.cardAlt);
    final warning = _ensureVisible(t.warning, t.cardAlt);

    return _sectionCard(
      icon: Icons.admin_panel_settings_rounded,
      title: 'Responsável',
      subtitle: 'Somente usuários com peso_permissao ≥ 50 e conta ativa.',
      color: t.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_usuariosCarregando)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(color: t.primary)),
            )
          else if (_usuariosDisponiveis.isEmpty)
            _infoBox(
              icon: Icons.warning_amber_rounded,
              color: t.warning,
              text: 'Nenhum usuário disponível como responsável.',
            )
          else
            DropdownButtonFormField<String>(
              value: _responsavelSelecionadoId,
              isExpanded: true,
              dropdownColor: t.surface,
              decoration: _inputDecoration(
                label: 'Responsável *',
                icon: Icons.person_rounded,
              ),
              hint: Text(
                'Selecione um responsável',
                style: TextStyle(color: t.textMuted),
              ),
              style: TextStyle(color: t.textPrimary),
              items: _usuariosDisponiveis.map((usuario) {
                final nome = usuario['nome']?.toString() ?? '';
                final email = usuario['email']?.toString() ?? '';

                return DropdownMenuItem<String>(
                  value: usuario['id']?.toString(),
                  child: Text(
                    nome.isEmpty ? email : '$nome • $email',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textPrimary),
                  ),
                );
              }).toList(),
              onChanged: (String? novoId) {
                if (novoId == null) return;

                final usuario = _usuariosDisponiveis.firstWhere(
                      (u) => u['id'] == novoId,
                  orElse: () => {'nome': '', 'email': ''},
                );

                setState(() {
                  _responsavelSelecionadoId = novoId;
                  _responsavelNome = usuario['nome']?.toString() ?? '';
                });
              },
            ),
          if (_responsavelSelecionadoId != null &&
              _responsavelNome.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Color.alphaBlend(success.withOpacity(0.10), t.cardAlt),
                borderRadius: BorderRadius.circular(t.inputRadius),
                border: Border.all(color: success.withOpacity(0.18)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: success, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Responsável: $_responsavelNome',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: success,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (!_usuariosCarregando) ...[
            const SizedBox(height: 10),
            _infoBox(
              icon: Icons.info_outline_rounded,
              color: warning,
              text: 'Escolha um responsável antes de salvar.',
              compact: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelecaoProfessores() {
    final t = context.uai;
    final info = _ensureVisible(t.info, t.card);

    return _sectionCard(
      icon: Icons.people_alt_rounded,
      title: 'Professores com Acesso',
      subtitle: 'Gerencie os professores que podem acessar esta academia.',
      color: t.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(t.buttonRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _usuariosCarregando ? null : _mostrarDialogProfessores,
              child: Ink(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _ensureVisible(t.info, t.card),
                      _ensureVisible(t.primary, t.card),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _readableOn(info).withOpacity(0.16),
                        borderRadius: BorderRadius.circular(t.buttonRadius),
                        border: Border.all(
                          color: _readableOn(info).withOpacity(0.18),
                        ),
                      ),
                      child: Icon(
                        Icons.people_rounded,
                        color: _readableOn(info),
                        size: 27,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GERENCIAR PROFESSORES',
                            style: TextStyle(
                              color: _readableOn(info),
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _professoresSelecionadosIds.isEmpty
                                ? 'Nenhum professor selecionado'
                                : '${_professoresSelecionadosIds.length} professor(es) selecionado(s)',
                            style: TextStyle(
                              color: _readableOn(info).withOpacity(0.86),
                              fontSize: 12,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: _readableOn(info),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_professoresSelecionadosIds.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.cardAlt,
                borderRadius: BorderRadius.circular(t.inputRadius),
                border: Border.all(color: t.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.school_rounded, size: 16, color: t.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        'Professores vinculados:',
                        style: TextStyle(
                          fontSize: 12,
                          color: t.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _professoresSelecionadosIds.map((id) {
                      final professor = _professoresDisponiveis.firstWhere(
                            (p) => p['id'] == id,
                        orElse: () => {'nome': 'Professor', 'email': ''},
                      );

                      return _miniBadge(
                        label: professor['nome']?.toString() ?? 'Professor',
                        color: t.info,
                        icon: Icons.person_rounded,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
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

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: accent.withOpacity(0.14)),
          boxShadow: t.softShadow,
        ),
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
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(t.buttonRadius),
            border: Border.all(color: color.withOpacity(0.16)),
          ),
          child: Icon(icon, color: color, size: 23),
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
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 11.8,
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
    bool compact = false,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.09), t.cardAlt),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: compact ? 18 : 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w800,
                fontSize: compact ? 12 : 13,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final iconBox = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              _isEditing ? Icons.edit_location_alt_rounded : Icons.add_business_rounded,
              color: onPrimary,
              size: 33,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                _isEditing ? 'Editar Academia' : 'Nova Academia',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 22 : 27,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Configure dados do núcleo, responsável, professores e canais de contato.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.82),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment:
                narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _heroChip(
                    icon: Icons.sports_martial_arts_rounded,
                    label: _modalidadeSelecionada,
                  ),
                  _heroChip(
                    icon: _statusSelecionado == 'ativa'
                        ? Icons.check_circle_rounded
                        : Icons.block_rounded,
                    label: _statusSelecionado.toUpperCase(),
                  ),
                  _heroChip(
                    icon: Icons.people_rounded,
                    label:
                    '${_professoresSelecionadosIds.length} professores',
                  ),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [
                iconBox,
                const SizedBox(height: 14),
                text,
              ],
            );
          }

          return Row(
            children: [
              iconBox,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _heroChip({
    required IconData icon,
    required String label,
  }) {
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
              fontWeight: FontWeight.bold,
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
          _isEditing ? 'Editar Academia' : 'Nova Academia',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _isLoading ? null : _excluirAcademia,
              tooltip: 'Excluir Academia',
            ),
          IconButton(
            icon: _isLoading || _usuariosCarregando
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _readableOn(t.primary),
              ),
            )
                : const Icon(Icons.save_rounded),
            onPressed:
            _isLoading || _usuariosCarregando ? null : _salvarAcademia,
            tooltip: 'Salvar',
          ),
        ],
      ),
      body: _isLoading
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHero(),
                    const SizedBox(height: 14),
                    _sectionCard(
                      icon: Icons.business_rounded,
                      title: 'Dados da Academia',
                      subtitle:
                      'Nome, modalidade, status, cidade e endereço.',
                      color: t.primary,
                      child: Column(
                        children: [
                          _buildFormField(
                            controller: _nomeController,
                            label: 'Nome da Academia/Núcleo',
                            icon: Icons.business_rounded,
                            obrigatorio: true,
                          ),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 560;

                              final modalidade = _buildDropdownField(
                                value: _modalidadeSelecionada,
                                items: _modalidades,
                                label: 'Modalidade',
                                icon:
                                Icons.sports_martial_arts_rounded,
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(
                                        () => _modalidadeSelecionada = value,
                                  );
                                },
                              );

                              final status = _buildDropdownField(
                                value: _statusSelecionado,
                                items: _statusOptions,
                                label: 'Status',
                                icon: Icons.circle_rounded,
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(
                                        () => _statusSelecionado = value,
                                  );
                                },
                              );

                              if (narrow) {
                                return Column(
                                  children: [
                                    modalidade,
                                    status,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: modalidade),
                                  const SizedBox(width: 12),
                                  Expanded(child: status),
                                ],
                              );
                            },
                          ),
                          _buildFormField(
                            controller: _cidadeController,
                            label: 'Cidade',
                            icon: Icons.location_city_rounded,
                            obrigatorio: true,
                          ),
                          _buildFormField(
                            controller: _enderecoController,
                            label: 'Endereço Completo',
                            icon: Icons.location_on_rounded,
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildSelecaoResponsavel(),
                    const SizedBox(height: 14),
                    _buildSelecaoProfessores(),
                    const SizedBox(height: 14),
                    _sectionCard(
                      icon: Icons.contact_phone_rounded,
                      title: 'Contato e Mídia',
                      subtitle:
                      'Telefone, email, WhatsApp, logo e observações.',
                      color: t.associacao,
                      child: Column(
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow = constraints.maxWidth < 560;

                              final telefone = _buildFormField(
                                controller: _telefoneController,
                                label: 'Telefone de Contato',
                                icon: Icons.phone_rounded,
                                keyboardType: TextInputType.phone,
                              );

                              final email = _buildFormField(
                                controller: _emailController,
                                label: 'Email',
                                icon: Icons.email_rounded,
                                keyboardType: TextInputType.emailAddress,
                              );

                              if (narrow) {
                                return Column(
                                  children: [
                                    telefone,
                                    email,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: telefone),
                                  const SizedBox(width: 12),
                                  Expanded(child: email),
                                ],
                              );
                            },
                          ),
                          _buildFormField(
                            controller: _whatsappController,
                            label: 'Link do Grupo WhatsApp',
                            icon: Icons.chat_rounded,
                            keyboardType: TextInputType.url,
                          ),
                          _buildFormField(
                            controller: _logoUrlController,
                            label: 'URL da Logo',
                            icon: Icons.image_rounded,
                            keyboardType: TextInputType.url,
                          ),
                          _buildFormField(
                            controller: _observacoesController,
                            label: 'Observações',
                            icon: Icons.note_alt_rounded,
                            maxLines: 4,
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
            onPressed:
            _isLoading || _usuariosCarregando ? null : _salvarAcademia,
            icon: _isLoading || _usuariosCarregando
                ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: _readableOn(t.primary),
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.save_rounded),
            label: Text(
              _isLoading || _usuariosCarregando
                  ? 'AGUARDE...'
                  : _isEditing
                  ? 'ATUALIZAR ACADEMIA'
                  : 'CRIAR ACADEMIA',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: _readableOn(t.primary),
              minimumSize: const Size.fromHeight(50),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
            ),
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
