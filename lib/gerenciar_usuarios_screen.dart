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
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Usuários',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          _buildPendingActionButton(),
          IconButton(
            icon: const Icon(Icons.people_outline_rounded),
            onPressed: () => _showInactiveUsersDialog(context),
            tooltip: 'Inativos/Bloqueados',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_add_usuario',
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text(
          'Novo',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const EditarUsuarioScreen()),
          );
        },
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('usuarios')
            .doc(currentUser!.uid)
            .snapshots(),
        builder: (context, adminSnapshot) {
          if (!adminSnapshot.hasData) {
            return _buildLoadingState('Carregando permissões...');
          }

          final adminData =
              adminSnapshot.data!.data() as Map<String, dynamic>? ?? {};
          final adminPesoPermissao = adminData['peso_permissao'] ?? 0;
          final adminTipo = adminData['tipo'] ?? '';
          final bool isAdmin =
              adminPesoPermissao >= 90 || adminTipo == 'admin' || adminTipo == 'administrador';

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('usuarios')
                .orderBy('nome_completo')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildLoadingState('Carregando usuários...');
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'Nenhum usuário encontrado',
                  subtitle: 'Quando houver usuários cadastrados, eles aparecerão aqui.',
                );
              }

              final usuarios = snapshot.data!.docs;
              _usuariosList = usuarios;

              final pendentes = usuarios.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['status_conta'] == 'pendente' || data['aprovado_em'] == null;
              }).toList();

              _pendentesCount = pendentes.length;

              final aprovados = usuarios.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['status_conta'] == 'ativa' && data['aprovado_em'] != null;
              }).toList();

              final outros = usuarios.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final status = data['status_conta'] ?? '';
                return status != 'ativa' &&
                    status != 'pendente' &&
                    data['aprovado_em'] == null;
              }).toList();

              final bloqueados = usuarios.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final status = data['status_conta']?.toString().toLowerCase() ?? '';
                return status == 'bloqueada' || status == 'inativa';
              }).length;

              return RefreshIndicator(
                color: Colors.red.shade900,
                onRefresh: () async => setState(() {}),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 920;
                    final isCompact = constraints.maxWidth < 520;

                    return ListView(
                      padding: EdgeInsets.fromLTRB(
                        isCompact ? 12 : 18,
                        isCompact ? 12 : 18,
                        isCompact ? 12 : 18,
                        96,
                      ),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1180),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildPremiumHero(
                                  total: usuarios.length,
                                  ativos: aprovados.length,
                                  pendentes: pendentes.length,
                                  bloqueados: bloqueados,
                                  compact: isCompact,
                                ),
                                const SizedBox(height: 14),
                                _buildQuickActionsRow(
                                  pendentes: pendentes,
                                  compact: isCompact,
                                ),
                                const SizedBox(height: 16),
                                if (aprovados.isNotEmpty)
                                  _buildSectionHeaderPremium(
                                    title: 'Usuários ativos',
                                    count: aprovados.length,
                                    icon: Icons.verified_user_rounded,
                                    color: Colors.green,
                                  ),
                                if (aprovados.isNotEmpty)
                                  _buildUserGrid(
                                    usuarios: aprovados,
                                    isWide: isWide,
                                    isAdmin: isAdmin,
                                    adminData: adminData,
                                  ),
                                if (outros.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  _buildSectionHeaderPremium(
                                    title: 'Outros usuários',
                                    count: outros.length,
                                    icon: Icons.manage_accounts_rounded,
                                    color: Colors.orange,
                                  ),
                                  _buildUserGrid(
                                    usuarios: outros,
                                    isWide: isWide,
                                    isAdmin: isAdmin,
                                    adminData: adminData,
                                  ),
                                ],
                                if (aprovados.isEmpty && outros.isEmpty)
                                  _buildEmptyState(
                                    icon: Icons.verified_user_outlined,
                                    title: 'Nenhum usuário aprovado',
                                    subtitle: 'Usuários pendentes ficam no botão de notificações.',
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPendingActionButton() {
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_rounded),
          onPressed: () {
            FirebaseFirestore.instance
                .collection('usuarios')
                .where('status_conta', isEqualTo: 'pendente')
                .get()
                .then((snapshot) {
              if (mounted) _showPendingUsersDialog(context, snapshot.docs);
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
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade500,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                _pendentesCount > 99 ? '99+' : '$_pendentesCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPremiumHero({
    required int total,
    required int ativos,
    required int pendentes,
    required int bloqueados,
    required bool compact,
  }) {
    return Container(
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(compact ? 24 : 30),
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
          final narrow = constraints.maxWidth < 650;

          final icon = Container(
            width: compact ? 58 : 70,
            height: compact ? 58 : 70,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: const Icon(Icons.groups_rounded, color: Colors.white, size: 36),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'Gerenciar Usuários',
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
                'Controle usuários, permissões, status de conta e aprovações do sistema.',
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
                  _buildHeroChip(Icons.people_alt_rounded, '$total usuários'),
                  _buildHeroChip(Icons.verified_rounded, '$ativos ativos'),
                  if (pendentes > 0)
                    _buildHeroChip(Icons.pending_actions_rounded, '$pendentes pendentes'),
                  if (bloqueados > 0)
                    _buildHeroChip(Icons.block_rounded, '$bloqueados bloqueados'),
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
            children: [icon, const SizedBox(width: 16), Expanded(child: text)],
          );
        },
      ),
    );
  }

  Widget _buildHeroChip(IconData icon, String label) {
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
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsRow({
    required List<QueryDocumentSnapshot> pendentes,
    required bool compact,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final actions = [
          _buildActionCard(
            icon: Icons.pending_actions_rounded,
            title: 'Pendentes',
            subtitle: pendentes.isEmpty ? 'Nenhum aguardando' : '${pendentes.length} aguardando aprovação',
            color: Colors.orange,
            onTap: () => _showPendingUsersDialog(context, pendentes),
          ),
          _buildActionCard(
            icon: Icons.people_outline_rounded,
            title: 'Inativos',
            subtitle: 'Bloqueados e inativos',
            color: Colors.red,
            onTap: () => _showInactiveUsersDialog(context),
          ),
          _buildActionCard(
            icon: Icons.person_add_alt_1_rounded,
            title: 'Novo usuário',
            subtitle: 'Cadastrar usuário',
            color: Colors.green,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const EditarUsuarioScreen()),
            ),
          ),
        ];

        if (!wide) {
          return Column(
            children: actions
                .map((w) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: w,
            ))
                .toList(),
          );
        }

        return Row(
          children: [
            Expanded(child: actions[0]),
            const SizedBox(width: 10),
            Expanded(child: actions[1]),
            const SizedBox(width: 10),
            Expanded(child: actions[2]),
          ],
        );
      },
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required MaterialColor color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.025),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.shade50,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: color.shade800, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade900,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color.shade700),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserGrid({
    required List<QueryDocumentSnapshot> usuarios,
    required bool isWide,
    required bool isAdmin,
    required Map<String, dynamic> adminData,
  }) {
    if (!isWide) {
      return Column(
        children: usuarios
            .map(
              (usuario) => _buildUserCard(
            context,
            usuario,
            false,
            isAdmin,
            adminData,
          ),
        )
            .toList(),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: usuarios.map((usuario) {
        return SizedBox(
          width: 370,
          child: _buildUserCard(
            context,
            usuario,
            false,
            isAdmin,
            adminData,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionHeaderPremium({
    required String title,
    required int count,
    required IconData icon,
    required MaterialColor color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
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
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: color.shade50,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: color.shade100),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: color.shade900,
                fontSize: 11,
                fontWeight: FontWeight.w900,
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
    final bool podeExcluir = isAdmin && pesoPermissao < 90;
    final tipoColor = _getTipoColor(tipo);
    final statusColor = _getStatusColor(statusConta);
    final inicial = nome.toString().trim().isNotEmpty
        ? nome.toString().trim().substring(0, 1).toUpperCase()
        : '?';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => UsuarioDetalheScreen(userId: userId)),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.025),
                blurRadius: 7,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              _buildUserAvatar(
                nome: nome.toString(),
                fotoUrl: fotoUrl?.toString(),
                color: tipoColor,
                size: 58,
                inicial: inicial,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade900,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      email.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildMiniBadge(
                          label: tipo.toString().isEmpty ? 'TIPO' : tipo.toString().toUpperCase(),
                          color: tipoColor,
                          icon: Icons.badge_rounded,
                        ),
                        _buildMiniBadge(
                          label: 'PESO $pesoPermissao',
                          color: Colors.blue,
                          icon: Icons.security_rounded,
                        ),
                        if (statusConta != 'ativa')
                          _buildMiniBadge(
                            label: statusConta.toString().toUpperCase(),
                            color: statusColor,
                            icon: Icons.info_rounded,
                          ),
                        if (aprovadoEm != null)
                          _buildMiniBadge(
                            label: 'APROVADO',
                            color: Colors.green,
                            icon: Icons.verified_rounded,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (podeExcluir)
                PopupMenuButton<String>(
                  tooltip: 'Ações',
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onSelected: (value) {
                    if (value == 'editar') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditarUsuarioScreen(userId: userId),
                        ),
                      );
                    } else if (value == 'excluir') {
                      _showDeleteConfirmation(context, userId, nome.toString());
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'editar',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Editar'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'excluir',
                      child: Row(
                        children: [
                          Icon(Icons.delete_forever_rounded, size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Excluir', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserAvatar({
    required String nome,
    required String? fotoUrl,
    required Color color,
    required double size,
    required String inicial,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: fotoUrl != null && fotoUrl.isNotEmpty
          ? ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: CachedNetworkImage(
          imageUrl: fotoUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Padding(
            padding: const EdgeInsets.all(14),
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
          errorWidget: (context, url, error) =>
              Icon(Icons.person_rounded, color: color, size: size * 0.48),
        ),
      )
          : Center(
        child: Text(
          inicial,
          style: TextStyle(
            fontSize: size * 0.36,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildMiniBadge({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(String message) {
    return Center(
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
              message,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          Icon(icon, size: 58, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade900,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.3),
          ),
        ],
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