import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Telas
import 'package:uai_capoeira/screens/eventos/eventos_screen.dart';
import 'package:uai_capoeira/screens/em_desenvolvimento_screen.dart';
import 'package:uai_capoeira/screens/uniformes/uniformes_screen.dart';
import 'package:uai_capoeira/screens/alunos/alunos_screen.dart';
import 'package:uai_capoeira/screens/admin/admin_screen.dart';
import 'package:uai_capoeira/profile_screen.dart';
import 'package:uai_capoeira/widgets/botao_atualizar_melhorado.dart';
import 'package:uai_capoeira/screens/admin/gerenciar_inscricoes_screen.dart'; // 🔥 NOVA TELA DE INSCRIÇÕES

// Services
import 'package:uai_capoeira/services/permissao_service.dart';

class AppDrawer extends StatelessWidget {
  final Map<String, dynamic> userData;
  final User? currentUser;
  final VoidCallback onLogout;
  final PermissaoService permissaoService;

  const AppDrawer({
    super.key,
    required this.userData,
    required this.currentUser,
    required this.onLogout,
    required this.permissaoService,
  });

  @override
  Widget build(BuildContext context) {
    final String displayName = userData['nome_completo'] ?? 'Usuário';
    final String? photoUrl = userData['foto_url'] as String?;
    final int? pesoPermissao = userData['peso_permissao'] as int?;
    final String? statusConta = userData['status_conta'] as String?;

    return Drawer(
      child: Container(
        color: Colors.white,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      // ========== HEADER DO DRAWER ==========
                      _buildDrawerHeader(context, displayName, photoUrl),

                      const SizedBox(height: 8),

                      // ========== ACESSOS ESPECIAIS ==========
                      _buildAcessosEspeciaisSection(context),

                      // ========== ADMINISTRAÇÃO ==========
                      if (pesoPermissao == 100 && statusConta == 'ativa')
                        _buildAdministracaoSection(context),

                      const Spacer(), // Isso vai empurrar o conteúdo para baixo

                      // ========== BOTÃO DE ATUALIZAÇÃO ==========
                      const BotaoAtualizarMelhorado(),

                      // ========== BOTÃO SAIR ==========
                      _buildLogoutButton(context),

                      const SizedBox(height: 8), // Espaçamento extra no final
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ========== HEADER DO DRAWER ==========
  Widget _buildDrawerHeader(
      BuildContext context,
      String displayName,
      String? photoUrl,
      ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade900,
      ),
      child: UserAccountsDrawerHeader(
        decoration: const BoxDecoration(
          color: Colors.transparent,
        ),
        accountName: Text(
          displayName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        accountEmail: Text(currentUser?.email ?? 'Email não encontrado'),
        currentAccountPicture: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ProfileScreen()),
          ),
          child: CircleAvatar(
            backgroundColor: Colors.white,
            child: ClipOval(
              child: _buildAvatarImage(
                photoUrl: photoUrl,
                displayName: displayName,
                isDrawer: true,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ========== SEÇÃO: ACESSOS ESPECIAIS ==========
  Widget _buildAcessosEspeciaisSection(BuildContext context) {
    return FutureBuilder<List<bool>>(
      future: Future.wait([
        permissaoService.temPermissao('podeAcessarEventos'),
        permissaoService.temPermissao('podeAcessarAssociacao'),
        permissaoService.temPermissao('podeAcessarRifas'),
        permissaoService.temPermissao('podeAcessarUniformes'),
        permissaoService.temPermissao('podeAcessarInscricoes'), // 🔥 NOVA PERMISSÃO
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final temEventos = snapshot.data![0];
        final temAssociacao = snapshot.data![1];
        final temRifas = snapshot.data![2];
        final temUniformes = snapshot.data![3];
        final temInscricoes = snapshot.data![4]; // 🔥 NOVA PERMISSÃO

        final temAlgumAcesso = temEventos || temAssociacao || temRifas || temUniformes || temInscricoes;

        if (!temAlgumAcesso) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSecaoTitulo(context, 'ACESSOS ESPECIAIS'),

            if (temEventos)
              _buildMenuItem(
                context: context,
                icone: Icons.event,
                cor: Colors.blue,
                titulo: 'EVENTOS',
                subtitulo: 'Calendário de eventos',
                tela: const EventosScreen(),
              ),

            if (temAssociacao)
              _buildMenuItem(
                context: context,
                icone: Icons.people_outline,
                cor: Colors.purple,
                titulo: 'ASSOCIAÇÃO',
                subtitulo: 'Gerencie associações',
                tela: const EmDesenvolvimentoScreen(
                  titulo: 'ASSOCIAÇÃO',
                  icone: Icons.people_outline,
                ),
              ),

            if (temRifas)
              _buildMenuItem(
                context: context,
                icone: Icons.confirmation_number,
                cor: Colors.amber,
                titulo: 'RIFAS',
                subtitulo: 'Gerencie rifas e sorteios',
                tela: const EmDesenvolvimentoScreen(
                  titulo: 'RIFAS',
                  icone: Icons.confirmation_number,
                ),
              ),

            if (temUniformes)
              _buildMenuItem(
                context: context,
                icone: Icons.shopping_bag,
                cor: Colors.green,
                titulo: 'UNIFORMES',
                subtitulo: 'Gestão de estoque e vendas',
                tela: const UniformesScreen(),
              ),

            // 🔥 NOVO BOTÃO DE INSCRIÇÕES
            if (temInscricoes)
              _buildMenuItem(
                context: context,
                icone: Icons.app_registration,
                cor: Colors.teal,
                titulo: 'INSCRIÇÕES',
                subtitulo: 'Gerenciar inscrições pendentes',
                tela: const GerenciarInscricoesScreen(),
              ),

            const Divider(height: 24, thickness: 1),
          ],
        );
      },
    );
  }

  // ========== SEÇÃO: ADMINISTRAÇÃO ==========
  Widget _buildAdministracaoSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSecaoTitulo(context, 'ADMINISTRAÇÃO'),

        _buildMenuItem(
          context: context,
          icone: Icons.people,
          cor: Colors.red,
          titulo: 'ALUNOS',
          subtitulo: 'Gerenciar alunos',
          tela: const AlunosScreen(),
        ),

        _buildMenuItem(
          context: context,
          icone: Icons.admin_panel_settings,
          cor: Colors.orange,
          titulo: 'ADMIN APP',
          subtitulo: 'Configurações do sistema',
          tela: const AdminScreen(),
        ),

        const Divider(height: 24, thickness: 1),
      ],
    );
  }

  // ========== BOTÃO SAIR ==========
  Widget _buildLogoutButton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onLogout,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: const Icon(Icons.logout, size: 20),
          label: const Text(
            'SAIR DO APP',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  // ========== WIDGETS AUXILIARES ==========

  Widget _buildSecaoTitulo(BuildContext context, String titulo) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      alignment: Alignment.centerLeft,
      child: Text(
        titulo,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade700,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icone,
    required Color cor,
    required String titulo,
    required String subtitulo,
    required Widget tela,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icone, color: cor, size: 20),
        ),
        title: Text(
          titulo,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(subtitulo, style: const TextStyle(fontSize: 11)),
        dense: true,
        onTap: () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (context) => tela));
        },
      ),
    );
  }

  Widget _buildAvatarImage({
    required String? photoUrl,
    required String displayName,
    bool isDrawer = false,
  }) {
    if (photoUrl == null || photoUrl.isEmpty) {
      return Icon(
        Icons.person,
        size: isDrawer ? 40 : 60,
        color: Colors.red.shade900,
      );
    }

    return CachedNetworkImage(
      imageUrl: photoUrl,
      fit: BoxFit.cover,
      width: isDrawer ? 90 : 120,
      height: isDrawer ? 90 : 120,
      placeholder: (context, url) => const CircularProgressIndicator(),
      errorWidget: (context, url, error) => Icon(
        Icons.person,
        size: isDrawer ? 40 : 60,
        color: Colors.red.shade900,
      ),
    );
  }
}