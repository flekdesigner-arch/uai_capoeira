import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditarUsuarioScreen extends StatefulWidget {
  final String? userId;

  const EditarUsuarioScreen({
    super.key,
    this.userId,
  });

  @override
  _EditarUsuarioScreenState createState() => _EditarUsuarioScreenState();
}

class _EditarUsuarioScreenState extends State<EditarUsuarioScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _contatoController = TextEditingController();

  // Tipos de usuário com nome completo
  final List<Map<String, dynamic>> _tiposUsuarios = [
    {
      'tipo': 'aluno',
      'nomeCompleto': 'Aluno',
      'peso': 10,
      'descricao': 'Acesso básico ao conteúdo',
      'icone': Icons.person
    },
    {
      'tipo': 'monitor',
      'nomeCompleto': 'Monitor',
      'peso': 30,
      'descricao': 'Pode auxiliar alunos',
      'icone': Icons.supervised_user_circle
    },
    {
      'tipo': 'professor',
      'nomeCompleto': 'Professor',
      'peso': 50,
      'descricao': 'Cadastra alunos e agenda aulas',
      'icone': Icons.school
    },
    {
      'tipo': 'administrador',
      'nomeCompleto': 'Administrador',
      'peso': 100,
      'descricao': 'Acesso total ao sistema',
      'icone': Icons.admin_panel_settings
    },
  ];

  String _selectedTipo = 'aluno';
  String _selectedStatus = 'pendente';
  int _pesoPermissao = 10;
  bool _carregando = false;
  bool _aprovado = false;
  String? _aprovadoPorNome;
  DateTime? _aprovadoEm;
  bool _isAdmin = false;
  Map<String, dynamic> _currentUserData = {};

  @override
  void initState() {
    super.initState();
    _loadCurrentUserData();
    _loadUserData();
  }

  Future<void> _loadCurrentUserData() async {
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
            _isAdmin = (_currentUserData['peso_permissao'] ?? 0) >= 90 ||
                (_currentUserData['tipo'] ?? '') == 'admin' ||
                (_currentUserData['tipo'] ?? '') == 'administrador';
          });
        }
      } catch (e) {
        print('Erro ao carregar dados do usuário atual: $e');
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
          _selectedTipo = data['tipo'] ?? 'aluno';
          _pesoPermissao = data['peso_permissao'] ?? 10;
          _selectedStatus = data['status_conta'] ?? 'pendente';
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

  Future<void> _aprovarUsuario() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aprovar Usuário'),
        content: const Text(
          'Deseja aprovar este usuário e ativar sua conta? '
              'Ele receberá acesso ao sistema conforme o tipo selecionado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Aprovar'),
          ),
        ],
      ),
    );

    if (result != true) return;

    await _salvarUsuario(aprovar: true);
  }

  Future<void> _salvarUsuario({bool aprovar = false}) async {
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
    if (_isAdmin) {
      dadosUpdate['tipo'] = _selectedTipo;
      dadosUpdate['peso_permissao'] = _pesoPermissao;
      dadosUpdate['status_conta'] = _selectedStatus;

      if (widget.userId != FirebaseAuth.instance.currentUser?.uid) {
        dadosUpdate['email'] = _emailController.text.trim();
      }

      // Se estiver aprovando
      if (aprovar) {
        dadosUpdate['aprovado_por'] = FirebaseAuth.instance.currentUser?.uid;
        dadosUpdate['aprovado_por_nome'] = _currentUserData['nome_completo'] ?? 'Administrador';
        dadosUpdate['aprovado_em'] = agora;
        dadosUpdate['status_conta'] = 'ativa';
      }
    } else {
      // Usuário comum só pode editar seu próprio nome e contato
      dadosUpdate['email'] = _emailController.text.trim();
    }

    setState(() => _carregando = true);

    try {
      final docRef = FirebaseFirestore.instance.collection('usuarios');

      if (widget.userId == null) {
        // Criar novo usuário
        final newUser = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: 'senha123', // Senha padrão
        );

        final newUserId = newUser.user!.uid;
        dadosUpdate['data_cadastro'] = agora;
        dadosUpdate['status_conta'] = 'pendente';
        dadosUpdate['tipo'] = 'aluno';
        dadosUpdate['peso_permissao'] = 10;

        await docRef.doc(newUserId).set(dadosUpdate);
        _mostrarSucesso('Novo usuário criado com sucesso!');
      } else {
        // Atualizar usuário existente
        await docRef.doc(widget.userId).update(dadosUpdate);

        if (aprovar) {
          _mostrarSucesso('Usuário aprovado com sucesso!');
          setState(() {
            _aprovado = true;
            _selectedStatus = 'ativa';
          });
        } else {
          _mostrarSucesso('Usuário atualizado com sucesso!');
        }

        // Atualiza email no Auth se necessário
        if (widget.userId == FirebaseAuth.instance.currentUser?.uid &&
            _emailController.text.isNotEmpty) {
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              await user.updateEmail(_emailController.text.trim());
            }
          } catch (e) {
            print('Erro ao atualizar email no Auth: $e');
          }
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _mostrarErro('Erro ao salvar: $e');
    } finally {
      setState(() => _carregando = false);
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
        title: const Text('Resetar Senha'),
        content: Text(
          'Deseja enviar um email de redefinição de senha para ${_emailController.text}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );

    if (result != true) return;

    setState(() => _carregando = true);

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
      setState(() => _carregando = false);
    }
  }

  void _mostrarSucesso(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: Colors.red,
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
        return Colors.red;
      case 'professor':
        return Colors.orange;
      case 'monitor':
        return Colors.blue;
      case 'aluno':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'ativa':
        return Colors.green;
      case 'pendente':
        return Colors.orange;
      case 'bloqueada':
        return Colors.red;
      case 'inativa':
        return Colors.grey;
      default:
        return Colors.grey;
    }
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
                  'Carregando usuário...',
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

    final isNovo = widget.userId == null;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          isNovo ? 'Novo Usuário' : 'Editar Usuário',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
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
            onPressed: () => _salvarUsuario(),
            tooltip: 'Salvar alterações',
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomActions(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final wide = constraints.maxWidth >= 980;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 20,
              compact ? 12 : 18,
              compact ? 12 : 20,
              112,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
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
                            Expanded(
                              flex: 5,
                              child: _buildDadosPessoaisCard(),
                            ),
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
                          const SizedBox(height: 14),
                          _buildTipoUsuarioCard(),
                        ],
                        if (_isAdmin && widget.userId != null) ...[
                          const SizedBox(height: 14),
                          _buildStatusContaCard(),
                        ],
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

  Widget _buildEditorHero({
    required bool isNovo,
    required bool compact,
  }) {
    final cor = _getTipoColor(_selectedTipo);

    return Container(
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(compact ? 26 : 32),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withOpacity(0.14),
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
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: Icon(
              isNovo ? Icons.person_add_alt_1_rounded : Icons.manage_accounts_rounded,
              color: Colors.white,
              size: 36,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                isNovo ? 'Cadastrar usuário' : 'Editar usuário',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 25 : 34,
                  fontWeight: FontWeight.w900,
                  height: 1.02,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                isNovo
                    ? 'Crie um acesso inicial para o sistema com senha padrão.'
                    : 'Atualize dados, tipo de acesso, status e informações do usuário.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.84),
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
                  _heroChip(Icons.badge_rounded, _selectedTipo.toUpperCase()),
                  _heroChip(Icons.security_rounded, 'PESO $_pesoPermissao'),
                  _heroChip(Icons.circle, _selectedStatus.toUpperCase()),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [icon, const SizedBox(height: 12), text],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: text),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: Colors.white.withOpacity(0.14)),
                ),
                child: Icon(Icons.admin_panel_settings_rounded, color: Colors.white),
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
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
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
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_rounded, color: Colors.green.shade700, size: 28),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Usuário aprovado',
                  style: TextStyle(
                    color: Colors.green.shade900,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Aprovado por: $_aprovadoPorNome'
                      '${_aprovadoEm != null ? ' • ${_aprovadoEm!.toLocal().toString().substring(0, 16)}' : ''}',
                  style: TextStyle(
                    color: Colors.green.shade800,
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
      color: Colors.blue,
      child: Column(
        children: [
          _buildTextField(
            controller: _nameController,
            label: 'Nome completo',
            icon: Icons.person_rounded,
            validator: (value) =>
            value?.trim().isEmpty ?? true ? 'Campo obrigatório' : null,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _emailController,
            label: 'Email',
            icon: Icons.email_rounded,
            keyboardType: TextInputType.emailAddress,
            suffixIcon: _isAdmin && widget.userId != null
                ? IconButton(
              icon: Icon(Icons.vpn_key_rounded, color: Colors.red.shade900),
              onPressed: _resetarSenha,
              tooltip: 'Enviar redefinição de senha',
            )
                : null,
            validator: (value) =>
            value?.trim().isEmpty ?? true ? 'Campo obrigatório' : null,
          ),
          const SizedBox(height: 12),
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
      color: Colors.red,
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
          const SizedBox(height: 14),
          _buildTipoResumo(),
        ],
      ),
    );
  }

  Widget _buildStatusContaCard() {
    return _premiumCard(
      title: 'Status da conta',
      icon: Icons.account_circle_rounded,
      color: Colors.orange,
      child: Wrap(
        spacing: 9,
        runSpacing: 9,
        alignment: WrapAlignment.center,
        children: [
          _buildStatusChip('ativa', 'Ativa', Colors.green),
          _buildStatusChip('pendente', 'Pendente', Colors.orange),
          _buildStatusChip('bloqueada', 'Bloqueada', Colors.red),
          _buildStatusChip('inativa', 'Inativa', Colors.grey),
        ],
      ),
    );
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
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.red.shade900, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.red.shade700, width: 1.4),
        ),
      ),
    );
  }

  Widget _premiumCard({
    required String title,
    required IconData icon,
    required MaterialColor color,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.shade100.withOpacity(0.75)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.032),
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
                  color: color.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.shade100),
                ),
                child: Icon(icon, color: color.shade800, size: 21),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade900,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tiny = constraints.maxWidth < 340;

            final cancel = OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('CANCELAR'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey.shade800,
                side: BorderSide(color: Colors.grey.shade300),
                padding: const EdgeInsets.symmetric(vertical: 13),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            );

            final save = ElevatedButton.icon(
              onPressed: _carregando ? null : () => _salvarUsuario(),
              icon: _carregando
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.save_rounded),
              label: Text(_carregando ? 'SALVANDO...' : 'SALVAR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                const SizedBox(width: 10),
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
      color: isSelected ? cor.withOpacity(0.09) : Colors.grey.shade50,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _updatePesoFromTipo(tipoNome),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? cor.withOpacity(0.55) : Colors.grey.shade200,
              width: isSelected ? 1.7 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icone, color: cor, size: 21),
              ),
              const SizedBox(width: 10),
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
                    const SizedBox(height: 2),
                    Text(
                      'Peso ${tipo['peso']}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: isSelected ? cor : Colors.grey.shade400,
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
        color: cor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cor.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(tipoAtual['icone'], color: cor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${tipoAtual['nomeCompleto']} • Peso $_pesoPermissao',
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
      selectedColor: color.withOpacity(0.16),
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(
        color: isSelected ? color.withOpacity(0.42) : Colors.grey.shade200,
      ),
      labelStyle: TextStyle(
        color: isSelected ? color : Colors.grey.shade700,
        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
        fontSize: 12,
      ),
      avatar: Icon(
        isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
        size: 16,
        color: isSelected ? color : Colors.grey.shade400,
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