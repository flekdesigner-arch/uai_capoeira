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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userId == null ? 'Novo Usuário' : 'Editar Usuário'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          if (!_aprovado && _isAdmin && widget.userId != null)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _aprovarUsuario,
              tooltip: 'Aprovar Usuário',
            ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () => _salvarUsuario(),
            tooltip: 'Salvar Alterações',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status atual e informações de aprovação
              if (_aprovado && _aprovadoPorNome != null)
                Card(
                  color: Colors.green[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        const Icon(Icons.verified, color: Colors.green),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'USUÁRIO APROVADO',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              Text(
                                'Aprovado por: $_aprovadoPorNome',
                                style: const TextStyle(fontSize: 12),
                              ),
                              if (_aprovadoEm != null)
                                Text(
                                  'Data: ${_aprovadoEm!.toLocal().toString().substring(0, 16)}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Formulário de dados pessoais
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dados Pessoais',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nome Completo',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (value) =>
                        value?.isEmpty ?? true ? 'Campo obrigatório' : null,
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.email),
                          suffixIcon: _isAdmin && widget.userId != null
                              ? IconButton(
                            icon: const Icon(Icons.vpn_key, color: Colors.red),
                            onPressed: _resetarSenha,
                            tooltip: 'Enviar redefinição de senha',
                          )
                              : null,
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) =>
                        value?.isEmpty ?? true ? 'Campo obrigatório' : null,
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _contatoController,
                        decoration: const InputDecoration(
                          labelText: 'Telefone/WhatsApp',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone),
                          hintText: '(99) 99999-9999',
                        ),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Seletor de Tipo (só admin) - CORRIGIDO: layout 2 em 2 e centralizado
              if (_isAdmin)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tipo de Usuário',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // GridView para layout 2 em 2
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 1.2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: _tiposUsuarios.length,
                          itemBuilder: (context, index) {
                            final tipo = _tiposUsuarios[index];
                            return _buildTipoCard(tipo);
                          },
                        ),

                        const SizedBox(height: 16),
                        _buildTipoResumo(),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // Status da Conta (só admin)
// Status da Conta (só admin) - CORRIGIDO: centralizado
              if (_isAdmin && widget.userId != null)
                Center( // Adicionado Center widget
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center, // Alterado para center
                        children: [
                          const Text(
                            'Status da Conta',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center, // Adicionado textAlign
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8, // Adicionado espaçamento vertical
                            alignment: WrapAlignment.center, // Adicionado para centralizar os chips
                            children: [
                              _buildStatusChip('ativa', 'Ativa', Colors.green),
                              _buildStatusChip('pendente', 'Pendente', Colors.orange),
                              _buildStatusChip('bloqueada', 'Bloqueada', Colors.red),
                              _buildStatusChip('inativa', 'Inativa', Colors.grey),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 32),

              // Botões de ação
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('CANCELAR'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _carregando ? null : () => _salvarUsuario(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade900,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: _carregando
                          ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.save),
                      label: Text(_carregando ? 'SALVANDO...' : 'SALVAR'),
                    ),
                  ),
                ],
              ),
            ],
          ),
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

    return InkWell(
      onTap: () => _updatePesoFromTipo(tipoNome),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? cor.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? cor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icone, color: cor, size: 28),
            const SizedBox(height: 8),
            Text(
              nomeCompleto,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: cor,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Peso: ${tipo['peso']}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipoResumo() {
    final tipoAtual = _tiposUsuarios.firstWhere(
          (t) => t['tipo'] == _selectedTipo,
      orElse: () => _tiposUsuarios[0],
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _getTipoColor(_selectedTipo).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _getTipoColor(_selectedTipo)),
      ),
      child: Row(
        children: [
          Icon(
            tipoAtual['icone'],
            color: _getTipoColor(_selectedTipo),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tipoAtual['nomeCompleto'],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _getTipoColor(_selectedTipo),
                  ),
                ),
                Text(
                  'Peso de permissão: $_pesoPermissao',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
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
      onSelected: _isAdmin ? (selected) {
        if (selected) {
          setState(() => _selectedStatus = status);
        }
      } : null,
      selectedColor: color.withOpacity(0.2),
      backgroundColor: Colors.grey[200],
      labelStyle: TextStyle(
        color: isSelected ? color : Colors.grey[600],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      avatar: isSelected ? Icon(Icons.check, size: 16, color: color) : null,
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