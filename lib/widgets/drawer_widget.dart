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
import 'package:uai_capoeira/screens/admin/gerenciar_inscricoes_screen.dart';

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
      backgroundColor: Colors.white,
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.white,
          child: Column(
            children: [
              _buildDrawerHeader(context, displayName, photoUrl),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                  children: [
                    _buildAcessosEspeciaisSection(context),
                    if (pesoPermissao == 100 && statusConta == 'ativa')
                      _buildAdministracaoSection(context),
                  ],
                ),
              ),
              _buildFooter(context),
            ],
          ),
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
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 18,
        left: 16,
        right: 16,
        bottom: 18,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withOpacity(0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
            borderRadius: BorderRadius.circular(26),
            child: Container(
              width: 68,
              height: 68,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(21),
                child: _buildAvatarImage(
                  photoUrl: photoUrl,
                  displayName: displayName,
                  isDrawer: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  currentUser?.email ?? 'Email não encontrado',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 9),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: Colors.white.withOpacity(0.16)),
                  ),
                  child: const Text(
                    'UAI CAPOEIRA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
        permissaoService.temPermissao('podeAcessarInscricoes'),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingSection();
        }

        if (snapshot.hasError) {
          debugPrint('Erro ao carregar permissões do drawer: ${snapshot.error}');
          return const SizedBox.shrink();
        }

        if (!snapshot.hasData) return const SizedBox.shrink();

        final temEventos = snapshot.data![0];
        final temAssociacao = snapshot.data![1];
        final temRifas = snapshot.data![2];
        final temUniformes = snapshot.data![3];
        final temInscricoes = snapshot.data![4];

        final temAlgumAcesso =
            temEventos || temAssociacao || temRifas || temUniformes || temInscricoes;

        if (!temAlgumAcesso) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSecaoTitulo(context, 'ACESSOS ESPECIAIS'),
            if (temEventos)
              _buildMenuItem(
                context: context,
                icone: Icons.event_rounded,
                cor: Colors.blue,
                titulo: 'EVENTOS',
                subtitulo: 'Calendário de eventos',
                tela: const EventosScreen(),
              ),
            if (temAssociacao)
              _buildMenuItem(
                context: context,
                icone: Icons.people_outline_rounded,
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
                icone: Icons.confirmation_number_rounded,
                cor: Colors.amber.shade700,
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
                icone: Icons.shopping_bag_rounded,
                cor: Colors.green,
                titulo: 'UNIFORMES',
                subtitulo: 'Gestão de estoque e vendas',
                tela: const UniformesScreen(),
              ),
            if (temInscricoes)
              _buildMenuItem(
                context: context,
                icone: Icons.app_registration_rounded,
                cor: Colors.teal,
                titulo: 'INSCRIÇÕES',
                subtitulo: 'Gerenciar inscrições pendentes',
                tela: const GerenciarInscricoesScreen(),
              ),
            _buildDivider(),
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
          icone: Icons.people_rounded,
          cor: Colors.red,
          titulo: 'ALUNOS',
          subtitulo: 'Gerenciar alunos',
          tela: const AlunosScreen(),
        ),
        _buildMenuItem(
          context: context,
          icone: Icons.admin_panel_settings_rounded,
          cor: Colors.orange,
          titulo: 'ADMIN APP',
          subtitulo: 'Configurações do sistema',
          tela: const AdminScreen(),
        ),
        _buildDivider(),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BotaoAtualizarMelhorado(),
            const SizedBox(height: 8),
            _buildLogoutButton(context),
          ],
        ),
      ),
    );
  }

  // ========== BOTÃO SAIR ==========
  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onLogout,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade700,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
          elevation: 0,
        ),
        icon: const Icon(Icons.logout_rounded, size: 20),
        label: const Text('SAIR DO APP'),
      ),
    );
  }

  // ========== WIDGETS AUXILIARES ==========
  Widget _buildSecaoTitulo(BuildContext context, String titulo) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 7),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.red.shade900,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              titulo,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Colors.grey.shade700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
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
    // O Material aqui é o ponto principal da correção:
    // evita o aviso "ListTile background color or ink splashes may be invisible".
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => tela),
            );
          },
          borderRadius: BorderRadius.circular(18),
          splashColor: cor.withOpacity(0.12),
          highlightColor: cor.withOpacity(0.06),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: cor.withOpacity(0.09),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icone, color: cor, size: 22),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Colors.grey.shade900,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.2,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade500,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.red.shade900,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Carregando permissões...',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
    );
  }

  Widget _buildAvatarImage({
    required String? photoUrl,
    required String displayName,
    bool isDrawer = false,
  }) {
    if (photoUrl == null || photoUrl.isEmpty) {
      return Container(
        color: Colors.red.shade50,
        alignment: Alignment.center,
        child: Icon(
          Icons.person_rounded,
          size: isDrawer ? 36 : 60,
          color: Colors.red.shade900,
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: photoUrl,
      fit: BoxFit.cover,
      width: isDrawer ? 68 : 120,
      height: isDrawer ? 68 : 120,
      placeholder: (context, url) => Container(
        color: Colors.red.shade50,
        alignment: Alignment.center,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.red.shade900,
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: Colors.red.shade50,
        alignment: Alignment.center,
        child: Icon(
          Icons.person_rounded,
          size: isDrawer ? 36 : 60,
          color: Colors.red.shade900,
        ),
      ),
    );
  }
}
