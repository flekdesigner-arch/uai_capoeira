import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../main.dart';

class PortalScreen extends StatelessWidget {
  final String userId;
  final Map<String, dynamic> userData;
  final String status;

  const PortalScreen({
    super.key,
    required this.userId,
    required this.userData,
    required this.status,
  });

  String _getStatusMessage(String currentStatus) {
    switch (currentStatus) {
      case 'pendente':
        return 'Sua conta está aguardando aprovação';
      case 'bloqueada':
        return 'Sua conta foi bloqueada';
      case 'inativa':
        return 'Sua conta está inativa';
      default:
        return 'Status desconhecido';
    }
  }

  IconData _getStatusIcon(String currentStatus) {
    switch (currentStatus) {
      case 'pendente':
        return Icons.hourglass_empty;
      case 'bloqueada':
        return Icons.block;
      case 'inativa':
        return Icons.pause_circle_outline;
      default:
        return Icons.help_outline;
    }
  }

  Color _getStatusColor(BuildContext context, String currentStatus) {
    switch (currentStatus) {
      case 'pendente':
        return Colors.orange;
      case 'bloqueada':
        return Colors.red;
      case 'inativa':
        return Colors.grey;
      case 'ativa':
        return Theme.of(context).primaryColor;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(userId)
                  .snapshots(),
              builder: (context, snapshot) {
                // Enquanto carrega
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Se teve erro
                if (snapshot.hasError) {
                  return _buildErrorContent(context);
                }

                // Se documento não existe
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return _buildNotFoundContent(context);
                }

                // Dados atualizados do Firestore
                final data = snapshot.data!.data() as Map<String, dynamic>;
                final currentStatus = data['status_conta'] ?? 'pendente';

                // 🔥 REDIRECIONAMENTO IMEDIATO via Stream!
                if (currentStatus == 'ativa') {
                  print('✅ Status mudou para ativa! Redirecionando...');

                  // Usa Microtask para não bloquear a UI
                  Future.microtask(() {
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => const MainScreen()),
                      );
                    }
                  });

                  // Mostra tela de transição
                  return _buildTransitionContent(context);
                }

                // Portal normal
                return _buildPortalContent(
                  context: context,
                  currentStatus: currentStatus,
                  userData: data,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // Tela de transição rápida (sem delay artificial)
  Widget _buildTransitionContent(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 60),
        const SizedBox(height: 16),
        const Text(
          'Conta ativada!',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('Redirecionando...'),
        const SizedBox(height: 24),
        const CircularProgressIndicator(),
      ],
    );
  }

  Widget _buildErrorContent(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 60, color: Colors.red),
        const SizedBox(height: 16),
        const Text(
          'Erro ao verificar status',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => FirebaseAuth.instance.signOut(),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
          child: const Text('Sair'),
        ),
      ],
    );
  }

  Widget _buildNotFoundContent(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error, size: 60, color: Colors.orange),
        const SizedBox(height: 16),
        const Text(
          'Conta não encontrada',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => FirebaseAuth.instance.signOut(),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
          child: const Text('Sair'),
        ),
      ],
    );
  }

  Widget _buildPortalContent({
    required BuildContext context,
    required String currentStatus,
    required Map<String, dynamic> userData,
  }) {
    final statusColor = _getStatusColor(context, currentStatus);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Logo
        Image.asset(
          'assets/images/logo_uai.png',
          height: 100,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.sports_martial_arts,
              size: 80,
              color: statusColor,
            );
          },
        ),
        const SizedBox(height: 40),

        // Card de Status
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              // Ícone de status
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getStatusIcon(currentStatus),
                  size: 50,
                  color: statusColor,
                ),
              ),
              const SizedBox(height: 24),

              // Nome do usuário
              Text(
                userData['nome_completo'] ?? 'Usuário',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // Email
              Text(
                userData['email'] ?? '',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),

              // Status
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  currentStatus.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Mensagem
              Text(
                _getStatusMessage(currentStatus),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Botão SAIR
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
            icon: const Icon(Icons.logout),
            label: const Text(
              'SAIR',
              style: TextStyle(fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}