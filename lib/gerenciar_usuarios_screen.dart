import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'screens/admin/editar_usuario_screen.dart';
import 'screens/admin/usuario_detalhe_screen.dart';
import 'screens/auth/aprovar_usuario_screen.dart';

class GerenciarUsuariosScreen extends StatefulWidget {
  const GerenciarUsuariosScreen({super.key});

  @override
  State<GerenciarUsuariosScreen> createState() => _GerenciarUsuariosScreenState();
}

class _GerenciarUsuariosScreenState extends State<GerenciarUsuariosScreen> {
  List<QueryDocumentSnapshot> _usuariosList = [];
  int _pendentesCount = 0;

  void _showDeleteConfirmation(BuildContext context, String docId, String nome) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar Exclusão'),
          content: Text("Você tem certeza que deseja excluir o usuário \"$nome\"?\n\nEsta ação é permanente e não pode ser desfeita."),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Excluir'),
              onPressed: () {
                FirebaseFirestore.instance.collection('usuarios').doc(docId).delete();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // Função para mostrar usuários pendentes
  void _showPendingUsersDialog(BuildContext context, List<QueryDocumentSnapshot> pendentes) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white,
            ),
            child: Column(
              children: [
                // Header do diálogo
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.pending_actions, color: Colors.white),
                      const SizedBox(width: 12),
                      const Text(
                        'Usuários Pendentes',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${pendentes.length}',
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Lista de usuários pendentes
                Expanded(
                  child: pendentes.isEmpty
                      ? const Center(
                    child: Text('Nenhum usuário pendente'),
                  )
                      : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: pendentes.length,
                    itemBuilder: (context, index) {
                      final usuario = pendentes[index];
                      final data = usuario.data() as Map<String, dynamic>;
                      final nome = data['nome_completo'] ?? data['name'] ?? 'Nome não informado';
                      final email = data['email'] ?? 'Email não informado';
                      final tipo = data['tipo'] ?? 'não definido';
                      final fotoUrl = data['foto_url'] ?? data['foto_perfil_aluno'];

                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: fotoUrl != null && fotoUrl.toString().isNotEmpty
                                ? ClipRRect(
                              borderRadius: BorderRadius.circular(25),
                              child: CachedNetworkImage(
                                imageUrl: fotoUrl.toString(),
                                fit: BoxFit.cover,
                                placeholder: (context, url) => const CircularProgressIndicator(),
                                errorWidget: (context, url, error) =>
                                const Icon(Icons.person, color: Colors.orange),
                              ),
                            )
                                : Center(
                              child: Text(
                                nome.substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            nome,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(email, style: const TextStyle(fontSize: 12)),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  tipo.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check_circle, color: Colors.green),
                                onPressed: () {
                                  Navigator.of(context).pop(); // Fecha o diálogo
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => AprovarUsuarioScreen(
                                        userId: usuario.id,
                                        userData: data,
                                        adminData: {}, // Você precisará passar os dados do admin
                                      ),
                                    ),
                                  );
                                },
                                tooltip: 'Aprovar',
                              ),
                              IconButton(
                                icon: const Icon(Icons.cancel, color: Colors.red),
                                onPressed: () {
                                  _showRejectConfirmation(context, usuario.id, nome);
                                },
                                tooltip: 'Rejeitar',
                              ),

                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Botão fechar
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.grey, width: 0.5)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Fechar'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Função para confirmar rejeição
  void _showRejectConfirmation(BuildContext context, String userId, String nome) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Rejeitar Usuário'),
          content: Text("Deseja realmente rejeitar o usuário \"$nome\"?\n\nO usuário será removido do sistema."),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Rejeitar'),
              onPressed: () async {
                // Fecha o diálogo de confirmação
                Navigator.of(context).pop();

                try {
                  // Excluir o usuário do Firestore
                  await FirebaseFirestore.instance.collection('usuarios').doc(userId).delete();

                  // Mostrar mensagem de sucesso
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Usuário "$nome" rejeitado com sucesso!'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }

                  // Fecha o diálogo de pendentes se ainda estiver aberto
                  if (mounted) {
                    Navigator.of(context).pop();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao rejeitar usuário: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showInactiveUsersDialog(BuildContext context) {
    final inactiveUsers = _usuariosList.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status_conta']?.toString().toLowerCase() ?? '';
      return status == 'inativa' || status == 'bloqueada';
    }).toList();

    if (inactiveUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Nenhum usuário inativo/bloqueado encontrado'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Usuários Inativos/Bloqueados'),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.6,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: inactiveUsers.length,
              itemBuilder: (context, index) {
                final usuario = inactiveUsers[index];
                final data = usuario.data() as Map<String, dynamic>;
                final nome = data['nome_completo'] ?? data['name'] ?? 'Nome não informado';
                final email = data['email'] ?? 'Email não informado';
                final statusConta = data['status_conta'] ?? '';
                final fotoUrl = data['foto_url'] ?? data['foto_perfil_aluno'];

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _getStatusColor(statusConta).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: fotoUrl != null && fotoUrl.toString().isNotEmpty
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: CachedNetworkImage(
                          imageUrl: fotoUrl.toString(),
                          fit: BoxFit.cover,
                          placeholder: (context, url) => const CircularProgressIndicator(),
                          errorWidget: (context, url, error) =>
                          const Icon(Icons.person, color: Colors.white),
                        ),
                      )
                          : Center(
                        child: Text(
                          nome.substring(0, 1).toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _getStatusColor(statusConta),
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      nome,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(email),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(statusConta).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusConta.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _getStatusColor(statusConta),
                        ),
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => UsuarioDetalheScreen(userId: usuario.id),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Fechar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'ativa':
        return Colors.green;
      case 'pendente':
        return Colors.orange;
      case 'bloqueada':
      case 'inativa':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Usuários'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          // Botão vermelho com badge para usuários pendentes
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () {
                  // Buscar usuários pendentes novamente para garantir dados atualizados
                  FirebaseFirestore.instance
                      .collection('usuarios')
                      .where('status_conta', isEqualTo: 'pendente')
                      .get()
                      .then((snapshot) {
                    if (mounted) {
                      _showPendingUsersDialog(context, snapshot.docs);
                    }
                  }).catchError((error) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Erro ao carregar pendentes: $error'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  });
                },
                tooltip: 'Usuários pendentes',
              ),
              if (_pendentesCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '$_pendentesCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          // Botão para mostrar usuários inativos/bloqueados
          IconButton(
            icon: const Icon(Icons.people_outline),
            onPressed: () {
              _showInactiveUsersDialog(context);
            },
            tooltip: 'Ver usuários inativos/bloqueados',
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('usuarios').doc(currentUser!.uid).snapshots(),
        builder: (context, adminSnapshot) {
          if (!adminSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final adminData = adminSnapshot.data!.data() as Map<String, dynamic>? ?? {};
          final adminPesoPermissao = adminData['peso_permissao'] ?? 0;
          final adminTipo = adminData['tipo'] ?? '';
          final bool isAdmin = adminPesoPermissao >= 90 || adminTipo == 'admin';

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('usuarios')
                .orderBy('nome_completo')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text("Nenhum usuário encontrado."));
              }

              final usuarios = snapshot.data!.docs;

              // Armazenar a lista de usuários no estado
              _usuariosList = usuarios;

              // Separa usuários pendentes e aprovados
              final pendentes = usuarios.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['status_conta'] == 'pendente' || data['aprovado_em'] == null;
              }).toList();

              // Atualizar contador de pendentes
              _pendentesCount = pendentes.length;

              // Filtrar APENAS usuários aprovados/ativos para a lista principal
              final aprovados = usuarios.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['status_conta'] == 'ativa' && data['aprovado_em'] != null;
              }).toList();

              // Outros usuários (inativos, bloqueados, etc) - também não mostrar pendentes
              final outros = usuarios.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final status = data['status_conta'] ?? '';
                return status != 'ativa' &&
                    status != 'pendente' &&
                    data['aprovado_em'] == null;
              }).toList();

              return Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(12.0),
                    children: [
                      // Seção de Usuários Aprovados (APENAS APROVADOS)
                      if (aprovados.isNotEmpty)
                        _buildSectionHeader('Usuários Aprovados', aprovados.length),
                      if (aprovados.isNotEmpty)
                        ...aprovados.map((usuario) =>
                            _buildUserCard(
                              context,
                              usuario,
                              false, // não é pendente
                              isAdmin,
                              adminData,
                            )
                        ).toList(),

                      // Seção de Outros Usuários (inativos/bloqueados)
                      if (outros.isNotEmpty)
                        _buildSectionHeader('Outros Usuários', outros.length),
                      if (outros.isNotEmpty)
                        ...outros.map((usuario) =>
                            _buildUserCard(
                              context,
                              usuario,
                              false, // não é pendente
                              isAdmin,
                              adminData,
                            )
                        ).toList(),

                      // Se não houver nenhum usuário aprovado
                      if (aprovados.isEmpty && outros.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32.0),
                            child: Text(
                              'Nenhum usuário aprovado encontrado',
                              style: TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Floating Action Button
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: FloatingActionButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const EditarUsuarioScreen(),
                          ),
                        );
                      },
                      backgroundColor: Colors.red.shade900,
                      child: const Icon(Icons.add, color: Colors.white),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(
      BuildContext context,
      QueryDocumentSnapshot usuario,
      bool isPendente,
      bool isAdmin,
      Map<String, dynamic> adminData,
      ) {
    final data = usuario.data() as Map<String, dynamic>;
    final userId = usuario.id;
    final nome = data['nome_completo'] ?? data['name'] ?? 'Nome não informado';
    final email = data['email'] ?? 'Email não informado';
    final fotoUrl = data['foto_url'] ?? data['foto_perfil_aluno'];
    final statusConta = data['status_conta'] ?? '';
    final aprovadoEm = data['aprovado_em'];
    final pesoPermissao = data['peso_permissao'] ?? 0;
    final tipo = data['tipo'] ?? '';

    // Verifica se pode editar/excluir
    final bool podeExcluir = isAdmin && pesoPermissao < 90;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => UsuarioDetalheScreen(userId: userId),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Avatar do usuário
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(30),
                ),
                child: fotoUrl != null && fotoUrl.toString().isNotEmpty
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: CachedNetworkImage(
                    imageUrl: fotoUrl.toString(),
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const CircularProgressIndicator(),
                    errorWidget: (context, url, error) =>
                    const Icon(Icons.person, color: Colors.white),
                  ),
                )
                    : Center(
                  child: Text(
                    nome.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Informações do usuário
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            nome,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Mostrar badge de status se não for ativo
                        if (statusConta != 'ativa')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getStatusColor(statusConta).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              statusConta.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _getStatusColor(statusConta),
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    Text(
                      email,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 4),

                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getTipoColor(tipo).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tipo.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _getTipoColor(tipo),
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        Text(
                          'Peso: $pesoPermissao',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),

                    if (aprovadoEm != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Aprovado',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green[600],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Menu de ações
              if (podeExcluir)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'editar') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditarUsuarioScreen(userId: userId),
                        ),
                      );
                    } else if (value == 'excluir') {
                      _showDeleteConfirmation(context, userId, nome);
                    }
                  },
                  itemBuilder: (context) {
                    final items = <PopupMenuEntry<String>>[];

                    items.add(const PopupMenuItem(
                      value: 'editar',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 18),
                          SizedBox(width: 8),
                          Text('Editar'),
                        ],
                      ),
                    ));

                    if (podeExcluir) {
                      items.add(const PopupMenuItem(
                        value: 'excluir',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Excluir', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ));
                    }

                    return items;
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getTipoColor(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'admin':
      case 'administrador':
        return Colors.red;
      case 'professor':
        return Colors.orange;
      case 'monitor':
        return Colors.blue;
      case 'aluno':
        return Colors.green;
      case 'visitante':
        return Colors.purple;
      case 'pendente':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}