import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uai_capoeira/core/services/uai_callable_client.dart';
import 'package:flutter/material.dart';
import 'package:uai_capoeira/modules/usuarios/widgets/usuario_action_overlay.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'usuario_admin_access.dart';
import 'usuario_role_catalog.dart';
import '../services/usuario_status_service.dart';
import '../services/usuario_auditoria_service.dart';

class EditarUsuarioScreen extends StatefulWidget {
  final String? userId;

  const EditarUsuarioScreen({super.key, this.userId});

  @override
  _EditarUsuarioScreenState createState() => _EditarUsuarioScreenState();
}

class _EditarUsuarioScreenState extends State<EditarUsuarioScreen> {
  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }



  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _contatoController = TextEditingController();

  // Papéis administrativos centralizados. "Aluno" não é mais um papel da
  // gestão: a Área do Aluno é um acesso independente e pode coexistir com
  // monitor/professor/administrador.
  final List<Map<String, dynamic>> _tiposUsuarios = UsuarioRoleCatalog
      .administrativos
      .map((role) => role.toLegacyMap())
      .toList(growable: false);

  String _selectedTipo = 'monitor';
  String _selectedStatus = 'pendente';
  String _statusOriginal = 'pendente';
  int _pesoPermissao = UsuarioRoleCatalog.monitor.peso;
  bool _carregando = false;
  bool _excluindoIdentidade = false;
  bool _aprovado = false;
  String? _aprovadoPorNome;
  DateTime? _aprovadoEm;
  bool _isAdmin = false;
  bool _alvoAdminMaster = false;
  Map<String, dynamic> _currentUserData = {};
  late Future<UsuarioAdminAccess> _accessFuture;

  @override
  void initState() {
    super.initState();
    _accessFuture = _inicializarAcesso();
  }

  Future<UsuarioAdminAccess> _inicializarAcesso() async {
    final access = await carregarAcessoGestaoUsuarios();
    if (!access.liberado) return access;

    _isAdmin = access.adminMaster;
    await _loadCurrentUserData(access);
    await _loadUserData();
    return access;
  }

  Future<void> _loadCurrentUserData(UsuarioAdminAccess access) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(currentUser.uid)
            .get();

        if (doc.exists) {
          setState(() {
            _currentUserData = doc.data()!;
            _isAdmin = access.adminMaster;
          });
        }
      } catch (e) {
        developer.log('Erro ao carregar dados do usuário atual: $e');
      }
    }
  }

  Future<void> _loadUserData() async {
    if (widget.userId == null) return;

    try {
      setState(() => _carregando = true);

      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(widget.userId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _nameController.text = data['nome_completo'] ?? '';
          _emailController.text = data['email'] ?? '';
          _contatoController.text = data['contato'] ?? '';
          final tipoCarregado = data['tipo']?.toString();
          final role = UsuarioRoleCatalog.byId(tipoCarregado);
          _selectedTipo = role?.administrativo == true
              ? role!.id
              : UsuarioRoleCatalog.monitor.id;
          _pesoPermissao = role?.administrativo == true
              ? role!.peso
              : UsuarioRoleCatalog.monitor.peso;
          _selectedStatus = UsuarioStatusService.normalizar(data['status_conta']);
          _statusOriginal = _selectedStatus;
          _alvoAdminMaster = _usuarioEhAdminMaster(data);
          _aprovado = data['aprovado_em'] != null;
          _aprovadoPorNome = data['aprovado_por_nome'];
          _aprovadoEm = (data['aprovado_em'] as Timestamp?)?.toDate();
        });
      }
    } catch (e) {
      _mostrarErro('Erro ao carregar dados: $e');
    } finally {
      setState(() => _carregando = false);
    }
  }

  bool _usuarioEhAdminMaster(Map<String, dynamic> data) {
    final tipo = (data['tipo'] ?? '').toString().trim().toLowerCase();
    final rawPeso = data['peso_permissao'];
    final peso = rawPeso is int
        ? rawPeso
        : rawPeso is num
        ? rawPeso.toInt()
        : int.tryParse(rawPeso?.toString() ?? '') ?? 0;
    return peso >= 90 || tipo == 'admin' || tipo == 'administrador';
  }

  Future<void> _aprovarUsuario() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Aprovar Usuário'),
        content: Text(
          'Deseja aprovar este usuário e ativar sua conta? '
          'Ele receberá acesso ao sistema conforme o tipo selecionado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.uai.success,
            ),
            child: const Text('Aprovar'),
          ),
        ],
      ),
    );

    if (result != true) return;

    await _salvarUsuario(aprovar: true);
  }

  Future<void> _salvarUsuario({bool aprovar = false}) async {
    final access = await carregarAcessoGestaoUsuarios();
    if (!access.liberado) {
      _mostrarErro('Você não tem permissão para gerenciar usuários.');
      return;
    }

    if (_alvoAdminMaster && !access.adminMaster) {
      _mostrarErro('Apenas admin master pode alterar outro admin master.');
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final agora = FieldValue.serverTimestamp();
    final dadosUpdate = <String, dynamic>{
      'nome_completo': _nameController.text.trim(),
      'contato': _contatoController.text.trim(),
      'ultima_atualizacao': agora,
    };

    // Campos que só admin pode editar
    if (access.adminMaster) {
      if (_selectedTipo.toLowerCase() == 'admin' ||
          _selectedTipo.toLowerCase() == 'administrador' ||
          _pesoPermissao >= 90) {
        // Permitido somente pelo bypass admin master validado acima.
      }

      dadosUpdate['tipo'] = _selectedTipo;
      dadosUpdate['peso_permissao'] = _pesoPermissao;

      if (_selectedStatus != _statusOriginal && widget.userId != null) {
        if (widget.userId == FirebaseAuth.instance.currentUser?.uid &&
            _selectedStatus != 'ativa') {
          _mostrarErro(
            'Você não pode bloquear, inativar ou colocar a própria conta como pendente.',
          );
          return;
        }

        dadosUpdate.addAll(
          UsuarioStatusService.camposParaStatus(
            novoStatus: _selectedStatus,
            statusAnterior: _statusOriginal,
            atorUid: FirebaseAuth.instance.currentUser?.uid,
            atorNome: (_currentUserData['nome_completo'] ?? 'Administrador').toString(),
          ),
        );
      } else {
        dadosUpdate['status_conta'] = _selectedStatus;
      }

      if (widget.userId != FirebaseAuth.instance.currentUser?.uid) {
        dadosUpdate['email'] = _emailController.text.trim();
      }

      // Se estiver aprovando
      if (aprovar) {
        dadosUpdate['aprovado_por'] = FirebaseAuth.instance.currentUser?.uid;
        dadosUpdate['aprovado_por_nome'] =
            _currentUserData['nome_completo'] ?? 'Administrador';
        dadosUpdate['aprovado_em'] = agora;
        dadosUpdate['status_conta'] = 'ativa';
        dadosUpdate['acesso_gestao'] = true;
        dadosUpdate['exibir_na_gestao'] = true;
        dadosUpdate['solicitacao_acesso_gestao'] = false;
      }
    } else {
      // Usuário comum só pode editar seu próprio nome e contato
      dadosUpdate['email'] = _emailController.text.trim();
    }

    setState(() => _carregando = true);
    UsuarioActionOverlay.show(
      context,
      title: aprovar
          ? 'Aprovando usuário...'
          : (widget.userId == null ? 'Criando usuário...' : 'Salvando alterações...'),
      subtitle: aprovar
          ? 'Liberando o acesso administrativo com segurança.'
          : 'Atualizando os dados da conta. Aguarde a confirmação.',
      icon: aprovar ? Icons.verified_user_rounded : Icons.manage_accounts_rounded,
    );

    try {
      final docRef = FirebaseFirestore.instance.collection('usuarios');

      if (widget.userId == null) {
        // Criar novo usuário
        final newUser = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: 'senha123', // Senha padrão
            );

        final newUserId = newUser.user!.uid;
        dadosUpdate['data_cadastro'] = agora;
        dadosUpdate['status_conta'] = 'pendente';
        dadosUpdate['tipo'] = UsuarioRoleCatalog.monitor.id;
        dadosUpdate['peso_permissao'] = UsuarioRoleCatalog.monitor.peso;
        dadosUpdate['acesso_gestao'] = false;
        dadosUpdate['exibir_na_gestao'] = true;

        await docRef.doc(newUserId).set(dadosUpdate);
        await UsuarioAuditoriaService.registrar(
          userId: newUserId,
          tipo: 'criacao',
          titulo: 'Usuário administrativo criado',
          descricao: 'Conta criada manualmente pela gestão e deixada pendente para aprovação.',
          atorUid: FirebaseAuth.instance.currentUser?.uid,
          atorNome: (_currentUserData['nome_completo'] ?? 'Administrador').toString(),
          depois: {
            'status_conta': 'pendente',
            'tipo': UsuarioRoleCatalog.monitor.id,
          },
        );
        _mostrarSucesso('Novo usuário criado com sucesso!');
      } else {
        // Atualizar usuário existente
        await docRef.doc(widget.userId).update(dadosUpdate);

        final alteracoes = <String, dynamic>{};
        if ((_currentUserData['tipo'] ?? '').toString() != _selectedTipo) {
          alteracoes['tipo'] = {'de': _currentUserData['tipo'], 'para': _selectedTipo};
        }
        if ((_currentUserData['peso_permissao'] ?? 0).toString() != _pesoPermissao.toString()) {
          alteracoes['peso_permissao'] = {
            'de': _currentUserData['peso_permissao'],
            'para': _pesoPermissao,
          };
        }
        if (_selectedStatus != _statusOriginal) {
          alteracoes['status_conta'] = {'de': _statusOriginal, 'para': _selectedStatus};
        }
        if ((_currentUserData['nome_completo'] ?? '').toString() != _nameController.text.trim()) {
          alteracoes['nome_completo'] = {
            'de': _currentUserData['nome_completo'],
            'para': _nameController.text.trim(),
          };
        }

        if (alteracoes.isNotEmpty || aprovar) {
          await UsuarioAuditoriaService.registrar(
            userId: widget.userId!,
            tipo: aprovar ? 'aprovacao' : 'perfil',
            titulo: aprovar ? 'Usuário aprovado' : 'Cadastro administrativo atualizado',
            descricao: aprovar
                ? 'Acesso administrativo aprovado pela tela de edição.'
                : '${alteracoes.length} campo(s) administrativo(s) alterado(s).',
            atorUid: FirebaseAuth.instance.currentUser?.uid,
            atorNome: (_currentUserData['nome_completo'] ?? 'Administrador').toString(),
            detalhes: alteracoes,
          );
        }

        if (aprovar) {
          _mostrarSucesso('Usuário aprovado com sucesso!');
          setState(() {
            _aprovado = true;
            _selectedStatus = 'ativa';
          });
        } else {
          setState(() => _statusOriginal = _selectedStatus);
          _mostrarSucesso('Usuário atualizado com sucesso!');
        }

        // Atualiza o e-mail da própria conta no Firebase Auth.
        //
        // firebase_auth 6.x removeu User.updateEmail(). A API atual exige
        // verificação prévia do novo endereço antes de efetivar a troca.
        if (widget.userId == FirebaseAuth.instance.currentUser?.uid &&
            _emailController.text.isNotEmpty) {
          try {
            final user = FirebaseAuth.instance.currentUser;
            final novoEmail = _emailController.text.trim();

            if (user != null &&
                novoEmail.isNotEmpty &&
                novoEmail != user.email) {
              await user.verifyBeforeUpdateEmail(novoEmail);
              _mostrarSucesso(
                'Enviamos uma confirmação para $novoEmail. '
                'O e-mail de acesso será alterado após a verificação.',
              );
            }
          } on FirebaseAuthException catch (e) {
            final mensagem = switch (e.code) {
              'requires-recent-login' =>
                'Por segurança, entre novamente na sua conta antes de alterar o e-mail.',
              'email-already-in-use' =>
                'Este e-mail já está sendo usado por outra conta.',
              'invalid-email' =>
                'Informe um endereço de e-mail válido.',
              _ =>
                'Não foi possível iniciar a alteração do e-mail de acesso agora.',
            };
            _mostrarErro(mensagem);
          } catch (e) {
            _mostrarErro(
              'Não foi possível iniciar a alteração do e-mail de acesso agora.',
            );
          }
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _mostrarErro('Erro ao salvar: $e');
    } finally {
      UsuarioActionOverlay.hide();
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _resetarSenha() async {
    if (!_isAdmin) {
      _mostrarErro('Apenas administradores podem resetar senhas');
      return;
    }

    if (_emailController.text.isEmpty) {
      _mostrarErro('Email não informado');
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Resetar Senha'),
        content: Text(
          'Deseja enviar um email de redefinição de senha para ${_emailController.text}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: context.uai.error),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );

    if (result != true || !mounted) return;

    setState(() => _carregando = true);
    UsuarioActionOverlay.show(
      context,
      title: 'Enviando redefinição...',
      subtitle: 'Solicitando ao Firebase o e-mail de redefinição de senha.',
      icon: Icons.lock_reset_rounded,
    );

    try {
      // Envio real de email de redefinição de senha
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );

      _mostrarSucesso('Email de redefinição enviado com sucesso!');

      // Registrar no Firestore que o email foi enviado (opcional)
      if (widget.userId != null) {
        await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(widget.userId)
            .update({
              'ultimo_reset_senha': FieldValue.serverTimestamp(),
              'reset_solicitado_por': FirebaseAuth.instance.currentUser?.uid,
            });
      }
    } catch (e) {
      String mensagemErro = 'Erro ao enviar email';

      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'invalid-email':
            mensagemErro = 'Email inválido';
            break;
          case 'user-not-found':
            mensagemErro = 'Usuário não encontrado no sistema de autenticação';
            break;
          case 'too-many-requests':
            mensagemErro = 'Muitas tentativas. Tente novamente mais tarde';
            break;
          default:
            mensagemErro = 'Erro: ${e.message}';
        }
      }

      _mostrarErro(mensagemErro);
    } finally {
      UsuarioActionOverlay.hide();
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _mostrarSucesso(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: context.uai.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: context.uai.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _updatePesoFromTipo(String tipo) {
    final tipoObj = _tiposUsuarios.firstWhere(
      (t) => t['tipo'] == tipo,
      orElse: () => _tiposUsuarios[0],
    );
    setState(() {
      _selectedTipo = tipo;
      _pesoPermissao = tipoObj['peso'];
    });
  }

  Color _getTipoColor(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'administrador':
        return context.uai.error;
      case 'professor':
        return context.uai.warning;
      case 'monitor':
        return context.uai.info;
      case 'aluno':
        return context.uai.success;
      default:
        return context.uai.textMuted;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'ativa':
        return context.uai.success;
      case 'pendente':
        return context.uai.warning;
      case 'bloqueada':
        return context.uai.error;
      case 'inativa':
        return context.uai.textMuted;
      default:
        return context.uai.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UsuarioAdminAccess>(
      future: _accessFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return buildLoadingGestaoUsuarios(context);
        }

        final access = snapshot.data;
        if (snapshot.hasError || access == null || !access.liberado) {
          return buildAcessoNegadoGestaoUsuarios(context);
        }

        if (_alvoAdminMaster && !access.adminMaster) {
          return buildAcessoNegadoGestaoUsuarios(context);
        }

        return _buildConteudoAutorizado(context, access);
      },
    );
  }

  Future<void> _confirmarExclusaoDefinitiva() async {
    final uid = widget.userId;
    if (uid == null || !_isAdmin || _carregando || _excluindoIdentidade ||
        uid == FirebaseAuth.instance.currentUser?.uid || _alvoAdminMaster) { return; }

    final nome = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim() : _emailController.text.trim();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir usuário definitivamente?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text('A identidade de $nome será removida do Firebase Auth '
              'e da coleção usuarios. As fichas dos alunos serão preservadas, '
              'mas os vínculos de acesso serão desfeitos.\n\n'
              'Esta ação não pode ser desfeita.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: context.uai.error,
              foregroundColor: _readableOn(context.uai.error)),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Excluir definitivamente'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    setState(() => _excluindoIdentidade = true);
    UsuarioActionOverlay.show(context,
      title: 'Excluindo usuário...',
      subtitle: 'Removendo a conta do Auth e o registro de usuários.',
      icon: Icons.delete_forever_rounded);
    try {
      await UaiCallableClient.instance.call('excluirIdentidadeFirebase', {'uid': uid});
      if (!mounted) return;
      UsuarioActionOverlay.hide();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Usuário excluído definitivamente. As fichas dos alunos foram preservadas.'),
        backgroundColor: context.uai.success,
      ));
      Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (error) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.message ?? 'Não foi possível excluir o usuário.'),
        backgroundColor: context.uai.error,
      )); }
    } catch (_) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Não foi possível concluir a exclusão. Tente novamente.'),
        backgroundColor: context.uai.error,
      )); }
    } finally {
      UsuarioActionOverlay.hide();
      if (mounted) setState(() => _excluindoIdentidade = false);
    }
  }

  Widget _buildDangerZone() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.uai.error.withAlpha(128)),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Zona de perigo', style: TextStyle(fontSize: 16,
              fontWeight: FontWeight.w900, color: context.uai.error)),
            const SizedBox(height: 5),
            Text('Remove o acesso do Auth e o cadastro de usuários. '
                'As fichas dos alunos permanecem preservadas.',
              style: TextStyle(color: context.uai.textSecondary)),
          ],
        );
        final action = OutlinedButton.icon(
          onPressed: (_carregando || _excluindoIdentidade) ? null : _confirmarExclusaoDefinitiva,
          icon: const Icon(Icons.delete_forever_rounded),
          label: Text(_excluindoIdentidade ? 'Excluindo...' : 'Excluir definitivamente'),
          style: OutlinedButton.styleFrom(foregroundColor: context.uai.error,
            side: BorderSide(color: context.uai.error),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15)),
        );
        if (narrow) { return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [title, const SizedBox(height: 14), action]); }
        return Row(children: [Expanded(child: title), const SizedBox(width: 18), action]);
      }),
    );
  }

  Widget _buildConteudoAutorizado(
    BuildContext context,
    UsuarioAdminAccess access,
  ) {
    if (_carregando) {
      return Scaffold(
        backgroundColor: context.uai.background,
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: context.uai.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: context.uai.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: context.uai.primary),
                SizedBox(height: 14),
                Text(
                  'Carregando usuário...',
                  style: TextStyle(
                    color: context.uai.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isNovo = widget.userId == null;

    return Scaffold(
      backgroundColor: context.uai.background,
      appBar: AppBar(
        title: Text(
          isNovo ? 'Novo Usuário' : 'Editar Usuário',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor:
            context.uai.primary,
        foregroundColor:
            _readableOn(context.uai.primary),
        elevation: 0,
        actions: [
          if (!_aprovado && _isAdmin && widget.userId != null)
            IconButton(
              icon: const Icon(Icons.verified_user_rounded),
              onPressed: _aprovarUsuario,
              tooltip: 'Aprovar usuário',
            ),
          IconButton(
            icon: const Icon(Icons.save_rounded),
            onPressed: _excluindoIdentidade ? null : () => _salvarUsuario(),
            tooltip: 'Salvar alterações',
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomActions(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final wide = constraints.maxWidth >= 900;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 20,
              compact ? 12 : 18,
              compact ? 12 : 20,
              112,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildEditorHero(isNovo: isNovo, compact: compact),
                      if (_aprovado && _aprovadoPorNome != null) ...[
                        const SizedBox(height: 14),
                        _buildApprovedBanner(),
                      ],
                      const SizedBox(height: 14),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: _buildDadosPessoaisCard()),
                            const SizedBox(width: 14),
                            Expanded(
                              flex: 4,
                              child: Column(
                                children: [
                                  if (_isAdmin) _buildTipoUsuarioCard(),
                                  if (_isAdmin && widget.userId != null) ...[
                                    if (_isAdmin) const SizedBox(height: 14),
                                    _buildStatusContaCard(),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _buildDadosPessoaisCard(),
                        if (_isAdmin) ...[
                          SizedBox(height: 14),
                          _buildTipoUsuarioCard(),
                        ],
                        if (_isAdmin && widget.userId != null) ...[
                          SizedBox(height: 14),
                          _buildStatusContaCard(),
                        ],
                      ],
                      if (_isAdmin && widget.userId != null &&
                          widget.userId != FirebaseAuth.instance.currentUser?.uid &&
                          !_alvoAdminMaster) ...[
                        const SizedBox(height: 20),
                        _buildDangerZone(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEditorHero({required bool isNovo, required bool compact}) {
    final cor = _getTipoColor(_selectedTipo);

    return Container(
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        gradient: context.uai.primaryGradient,
        borderRadius: BorderRadius.circular(compact ? 26 : 32),
        boxShadow: [
          BoxShadow(
            color: context.uai.primary.withAlpha(36),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 640;

          final icon = Container(
            width: compact ? 58 : 70,
            height: compact ? 58 : 70,
            decoration: BoxDecoration(
              color: context.uai.card.withAlpha(36),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: context.uai.card.withAlpha(41)),
            ),
            child: Icon(
              isNovo
                  ? Icons.person_add_alt_1_rounded
                  : Icons.manage_accounts_rounded,
              color: _readableOn(context.uai.primary),
              size: 36,
            ),
          );

          final text = Column(
            crossAxisAlignment: narrow
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                isNovo ? 'Cadastrar usuário' : 'Editar usuário',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: _readableOn(context.uai.primary),
                  fontSize: compact ? 25 : 34,
                  fontWeight: FontWeight.w900,
                  height: 1.02,
                ),
              ),
              SizedBox(height: 7),
              Text(
                isNovo
                    ? 'Crie um acesso inicial para o sistema com senha padrão.'
                    : 'Atualize dados, tipo de acesso, status e informações do usuário.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: _readableOn(context.uai.primary).withAlpha(224),
                  fontSize: compact ? 12.8 : 15,
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
                  _heroChip(
                    Icons.badge_rounded,
                    UsuarioRoleCatalog.label(_selectedTipo).toUpperCase(),
                  ),
                  _heroChip(Icons.tune_rounded, 'PERMISSÕES CONFIGURÁVEIS'),
                  _heroChip(Icons.circle, _selectedStatus.toUpperCase()),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(children: [icon, SizedBox(height: 12), text]);
          }

          return Row(
            children: [
              icon,
              SizedBox(width: 16),
              Expanded(child: text),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: cor.withAlpha(51),
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: context.uai.card.withAlpha(36)),
                ),
                child: Icon(
                  Icons.admin_panel_settings_rounded,
                  color: _readableOn(context.uai.primary),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _heroChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: context.uai.card.withAlpha(36),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: context.uai.card.withAlpha(41)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _readableOn(context.uai.primary), size: 14),
          SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: _readableOn(context.uai.primary),
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovedBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.uai.success.withAlpha(26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.uai.success.withAlpha(41)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_rounded, color: context.uai.success, size: 28),
          SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Usuário aprovado',
                  style: TextStyle(
                    color: context.uai.success,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Aprovado por: $_aprovadoPorNome'
                  '${_aprovadoEm != null ? ' • ${_aprovadoEm!.toLocal().toString().substring(0, 16)}' : ''}',
                  style: TextStyle(
                    color: context.uai.success,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDadosPessoaisCard() {
    return _premiumCard(
      title: 'Dados pessoais',
      icon: Icons.person_rounded,
      color: context.uai.info,
      child: Column(
        children: [
          _buildTextField(
            controller: _nameController,
            label: 'Nome completo',
            icon: Icons.person_rounded,
            validator: (value) =>
                value?.trim().isEmpty ?? true ? 'Campo obrigatório' : null,
          ),
          SizedBox(height: 12),
          _buildTextField(
            controller: _emailController,
            label: 'Email',
            icon: Icons.email_rounded,
            keyboardType: TextInputType.emailAddress,
            suffixIcon: _isAdmin && widget.userId != null
                ? IconButton(
                    icon: Icon(
                      Icons.vpn_key_rounded,
                      color: context.uai.primary,
                    ),
                    onPressed: _resetarSenha,
                    tooltip: 'Enviar redefinição de senha',
                  )
                : null,
            validator: (value) =>
                value?.trim().isEmpty ?? true ? 'Campo obrigatório' : null,
          ),
          SizedBox(height: 12),
          _buildTextField(
            controller: _contatoController,
            label: 'Telefone/WhatsApp',
            icon: Icons.phone_rounded,
            hintText: '(99) 99999-9999',
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTipoUsuarioCard() {
    return _premiumCard(
      title: 'Tipo de usuário',
      icon: Icons.admin_panel_settings_rounded,
      color: context.uai.error,
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 380 ? 1 : 2;
              const spacing = 10.0;
              final itemWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: _tiposUsuarios.map((tipo) {
                  return SizedBox(
                    width: itemWidth,
                    child: _buildTipoCard(tipo),
                  );
                }).toList(),
              );
            },
          ),
          SizedBox(height: 14),
          _buildTipoResumo(),
        ],
      ),
    );
  }

  Widget _buildStatusContaCard() {
    return _premiumCard(
      title: 'Status da conta',
      icon: Icons.account_circle_rounded,
      color: context.uai.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _statusDescricao(_selectedStatus),
            style: TextStyle(
              color: context.uai.textSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              _buildStatusChip('ativa', 'Ativa', context.uai.success),
              _buildStatusChip('pendente', 'Pendente', context.uai.warning),
              _buildStatusChip('bloqueada', 'Bloqueada', context.uai.error),
              _buildStatusChip('inativa', 'Inativa', context.uai.textMuted),
            ],
          ),
          if (widget.userId == FirebaseAuth.instance.currentUser?.uid) ...[
            const SizedBox(height: 10),
            Text(
              'Sua própria conta só pode permanecer ativa.',
              style: TextStyle(
                color: context.uai.warning,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _statusDescricao(String status) {
    switch (UsuarioStatusService.normalizar(status)) {
      case 'ativa':
        return 'Acesso administrativo liberado. O vínculo com a Área do Aluno, quando existir, é preservado.';
      case 'pendente':
        return 'Aguardando aprovação administrativa. A Área do Aluno continua independente.';
      case 'bloqueada':
        return 'Acesso à gestão suspenso temporariamente, sem excluir a conta ou seus vínculos.';
      case 'inativa':
        return 'Conta administrativa arquivada. Pode ser reativada depois sem perder histórico.';
      default:
        return 'Status administrativo da conta.';
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: context.uai.cardAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: context.uai.cardAlt),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: context.uai.cardAlt),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: context.uai.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: context.uai.primaryDark, width: 1.4),
        ),
      ),
    );
  }

  Widget _premiumCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: context.uai.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withAlpha(46).withAlpha(191)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withAlpha(26),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withAlpha(46)),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: context.uai.textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(
          color: context.uai.card,
          border: Border(top: BorderSide(color: context.uai.cardAlt)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(11),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tiny = constraints.maxWidth < 340;

            final cancel = OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back_rounded),
              label: Text('CANCELAR'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.uai.textPrimary,
                side: BorderSide(color: context.uai.border),
                padding: const EdgeInsets.symmetric(vertical: 13),
                textStyle: TextStyle(fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            );

            final save = ElevatedButton.icon(
              onPressed: (_carregando || _excluindoIdentidade) ? null : () => _salvarUsuario(),
              icon: _carregando
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : Icon(Icons.save_rounded),
              label: Text(_carregando ? 'SALVANDO...' : 'SALVAR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.uai.primary,
                foregroundColor: _readableOn(context.uai.primary),
                padding: const EdgeInsets.symmetric(vertical: 13),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            );

            if (tiny) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: double.infinity, child: save),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: cancel),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: cancel),
                SizedBox(width: 10),
                Expanded(flex: 2, child: save),
              ],
            );
          },
        ),
      ),
    );
  }

  // Card de tipo CORRIGIDO: com nome completo e centralizado
  Widget _buildTipoCard(Map<String, dynamic> tipo) {
    final String tipoNome = tipo['tipo'];
    final String nomeCompleto = tipo['nomeCompleto'];
    final IconData icone = tipo['icone'];
    final Color cor = _getTipoColor(tipoNome);
    final bool isSelected = _selectedTipo == tipoNome;

    return Material(
      color: isSelected ? cor.withAlpha(23) : context.uai.background,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _updatePesoFromTipo(tipoNome),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? cor.withAlpha(140) : context.uai.cardAlt,
              width: isSelected ? 1.7 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: cor.withAlpha(26),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icone, color: cor, size: 21),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nomeCompleto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: cor,
                        fontSize: 13.5,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Peso ${tipo['peso']}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.uai.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: isSelected ? cor : context.uai.textMuted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTipoResumo() {
    final tipoAtual = _tiposUsuarios.firstWhere(
      (t) => t['tipo'] == _selectedTipo,
      orElse: () => _tiposUsuarios[0],
    );

    final cor = _getTipoColor(_selectedTipo);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cor.withAlpha(20),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cor.withAlpha(46)),
      ),
      child: Row(
        children: [
          Icon(tipoAtual['icone'], color: cor),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '${tipoAtual['nomeCompleto']} • ${tipoAtual['descricao']}',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: cor,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status, String label, Color color) {
    final isSelected = _selectedStatus == status;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: _isAdmin
          ? (selected) {
              if (selected) setState(() => _selectedStatus = status);
            }
          : null,
      selectedColor: color.withAlpha(41),
      backgroundColor: context.uai.border,
      side: BorderSide(
        color: isSelected ? color.withAlpha(107) : context.uai.cardAlt,
      ),
      labelStyle: TextStyle(
        color: isSelected ? color : context.uai.textSecondary,
        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
        fontSize: 12,
      ),
      avatar: Icon(
        isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
        size: 16,
        color: isSelected ? color : context.uai.textMuted,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _contatoController.dispose();
    super.dispose();
  }
}
