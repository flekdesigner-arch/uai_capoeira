import 'package:flutter/material.dart';
import '../../gerenciar_graduacoes_screen.dart';
import '../../gerenciar_usuarios_screen.dart';
import '../../migracao_triagem_screen.dart';
import 'gerenciar_academias_screen.dart';
import 'migracao_chamadas_screen.dart';
import 'migracao_eventos_screen.dart';
import 'gerenciar_eventos_screen.dart';
import 'migracao_participacoes_screen.dart';
import 'gerenciar_participacoes_screen.dart';
import 'migracao_graduacoes_screen.dart';
import 'gerenciar_site_screen.dart';
import 'gerenciar_logo_screen.dart'; // 🔥 NOVO IMPORT!

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel Administrativo'),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              switch (value) {
                case 'migrar_alunos':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MigracaoTriagemScreen(),
                    ),
                  );
                  break;
                case 'migrar_graduacoes':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MigracaoGraduacoesScreen(),
                    ),
                  );
                  break;
                case 'migrar_chamadas':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MigracaoChamadasScreen(),
                    ),
                  );
                  break;
                case 'migrar_eventos':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MigracaoEventosScreen(),
                    ),
                  );
                  break;
                case 'migrar_participacoes':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MigracaoParticipacoesScreen(),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (BuildContext context) {
              return <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'migrar_alunos',
                  child: Row(
                    children: [
                      Icon(Icons.people, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Migrar Alunos'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'migrar_graduacoes',
                  child: Row(
                    children: [
                      Icon(Icons.workspace_premium, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Migrar Graduações'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'migrar_chamadas',
                  child: Row(
                    children: [
                      Icon(Icons.history_edu, color: Colors.purple),
                      SizedBox(width: 8),
                      Text('Migrar Chamadas'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'migrar_eventos',
                  child: Row(
                    children: [
                      Icon(Icons.event, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Migrar Eventos'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'migrar_participacoes',
                  child: Row(
                    children: [
                      Icon(Icons.emoji_events, color: Colors.amber),
                      SizedBox(width: 8),
                      Text('Migrar Participações'),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // ========== SEÇÃO: SITE ==========
            const Text(
              '🌐 GERENCIAMENTO DO SITE',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),

            // CARD: GERENCIAR SITE (CONTEÚDO)
            _buildAdminCard(
              context: context,
              icon: Icons.web,
              title: 'Gerenciar Site',
              subtitle: 'Edite Regimento, Biografia, Graduações e Inscrição',
              color: Colors.purple,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GerenciarSiteScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),

            // 🔥 NOVO CARD: GERENCIAR LOGO
            _buildAdminCard(
              context: context,
              icon: Icons.image,
              title: 'Logo do Site',
              subtitle: 'Troque a logo da página inicial',
              color: Colors.teal,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GerenciarLogoScreen(),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),
            const Divider(height: 24, thickness: 1),
            const SizedBox(height: 8),

            // ========== SEÇÃO: APP ==========
            const Text(
              '📱 GERENCIAMENTO DO APP',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),

            // ✅ GERENCIAMENTOS PRINCIPAIS
            _buildAdminCard(
              context: context,
              icon: Icons.manage_accounts,
              title: 'Gerenciar Usuários',
              subtitle: 'Adicione, edite e remova usuários e permissões',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GerenciarUsuariosScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),

            _buildAdminCard(
              context: context,
              icon: Icons.shield,
              title: 'Gerenciar Graduações',
              subtitle: 'Crie, edite e delete as graduações do app',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GerenciarGraduacoesScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),

            _buildAdminCard(
              context: context,
              icon: Icons.business,
              title: 'Gerenciar Academias',
              subtitle: 'Gerencie academias, núcleos e turmas',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GerenciarAcademiasScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),

            _buildAdminCard(
              context: context,
              icon: Icons.event,
              title: 'Gerenciar Eventos',
              subtitle: 'Cadastre, edite e exclua eventos',
              color: Colors.blue,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GerenciarEventosScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),

            _buildAdminCard(
              context: context,
              icon: Icons.emoji_events,
              title: 'Gerenciar Participações',
              subtitle: 'Gerencie participações e certificados de eventos',
              color: Colors.amber,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GerenciarParticipacoesScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color color = Colors.red,
  }) {
    Color getIconColor(Color color) {
      if (color is MaterialColor) {
        return color.shade900;
      }
      return color;
    }

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 28,
            color: getIconColor(color),
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: getIconColor(color),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        onTap: onTap,
      ),
    );
  }
}