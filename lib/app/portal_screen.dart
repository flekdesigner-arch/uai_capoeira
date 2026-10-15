import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/app/bootstrap/uai_native_bootstrap.dart' show MainScreen;
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/minha_uai/screens/minha_uai_home_screen.dart';
import 'package:uai_capoeira/modules/usuarios/services/usuario_identidade_service.dart';

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

  String _statusLabel(String currentStatus) => switch (currentStatus) {
        'pendente' => 'EM ANÁLISE',
        'bloqueada' => 'BLOQUEADA',
        'inativa' => 'INATIVA',
        'rejeitada' => 'NÃO APROVADA',
        _ => currentStatus.toUpperCase(),
      };

  String _titulo(String currentStatus) => switch (currentStatus) {
        'pendente' => 'Acesso à gestão em análise',
        'bloqueada' => 'Acesso à gestão bloqueado',
        'inativa' => 'Acesso à gestão inativo',
        'rejeitada' => 'Solicitação de gestão não aprovada',
        _ => 'Status da sua conta',
      };

  String _mensagem(String currentStatus) => switch (currentStatus) {
        'pendente' =>
          'Recebemos sua solicitação para acessar as ferramentas internas da UAI Capoeira. A administração ainda precisa revisar e liberar seu perfil.',
        'bloqueada' =>
          'Este acesso administrativo foi bloqueado. Entre em contato com a administração se precisar revisar a situação.',
        'inativa' =>
          'Este acesso administrativo está inativo no momento. Entre em contato com a administração para reativação.',
        'rejeitada' =>
          'Sua solicitação de acesso à gestão não foi aprovada. Isso não interfere em uma Conta UAI ou Área do Aluno que você possua.',
        _ => 'A administração ainda precisa revisar o status desta conta.',
      };

  IconData _icon(String currentStatus) => switch (currentStatus) {
        'pendente' => Icons.schedule_rounded,
        'bloqueada' => Icons.lock_rounded,
        'inativa' => Icons.pause_circle_rounded,
        'rejeitada' => Icons.cancel_rounded,
        _ => Icons.info_rounded,
      };

  Color _statusColor(BuildContext context, String currentStatus) =>
      switch (currentStatus) {
        'pendente' => context.uai.warning,
        'bloqueada' => context.uai.error,
        'inativa' => context.uai.textSecondary,
        'rejeitada' => context.uai.error,
        _ => context.uai.info,
      };

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('usuarios')
              .doc(userId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _loading(context, 'Verificando seu acesso...');
            }
            if (snapshot.hasError) return _erro(context);
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return _naoEncontrada(context);
            }

            final data = snapshot.data!.data() ?? <String, dynamic>{};
            final currentStatus = (data['status_conta'] ?? 'pendente').toString();

            // Proteção final: Conta UAI/inscrição nunca deve ficar presa no
            // portal administrativo por causa do status_conta legado.
            if (UsuarioIdentidadeService.ehContextoMinhaUai(data)) {
              Future.microtask(() async {
                try {
                  await UsuarioIdentidadeService().reconciliarContaInscricao(
                    userId: userId,
                    data: data,
                  );
                } catch (_) {}
                if (context.mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const MinhaUaiHomeScreen()),
                  );
                }
              });
              return _loading(context, 'Abrindo sua Conta UAI...');
            }

            if (currentStatus == 'ativa') {
              Future.microtask(() {
                if (context.mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const MainScreen()),
                  );
                }
              });
              return _loading(context, 'Acesso liberado. Abrindo gestão...');
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth > 760 ? 680.0 : constraints.maxWidth;
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [t.primary, t.primaryDark],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(38),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: const Icon(Icons.admin_panel_settings_rounded,
                                      color: Colors.white, size: 34),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Portal de acesso à gestão',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 22,
                                              fontWeight: FontWeight.w900)),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Acompanhe aqui somente sua solicitação para ferramentas internas.',
                                        style: TextStyle(
                                          color: Colors.white.withAlpha(224),
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          _statusCard(context, currentStatus, data),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: t.surface,
                              border: Border.all(color: t.border),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.shield_outlined, color: t.info),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Este portal não é a Minha UAI. Contas criadas para inscrição ou Área do Aluno são encaminhadas automaticamente para o ambiente correto.',
                                    style: TextStyle(
                                      color: t.textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: OutlinedButton.icon(
                              onPressed: () => FirebaseAuth.instance.signOut(),
                              icon: const Icon(Icons.logout_rounded),
                              label: const Text('SAIR DA CONTA'),
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
        ),
      ),
    );
  }

  Widget _statusCard(
    BuildContext context,
    String currentStatus,
    Map<String, dynamic> data,
  ) {
    final t = context.uai;
    final color = _statusColor(context, currentStatus);
    final nome = (data['nome_completo'] ?? data['nome'] ?? 'Usuário').toString();
    final email = (data['email'] ?? '').toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withAlpha(64)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: color.withAlpha(26),
              shape: BoxShape.circle,
            ),
            child: Icon(_icon(currentStatus), color: color, size: 42),
          ),
          const SizedBox(height: 16),
          Text(_titulo(currentStatus),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              )),
          const SizedBox(height: 8),
          Text(nome,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              )),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(email,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textSecondary)),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: color.withAlpha(26),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(_statusLabel(currentStatus),
                style: TextStyle(color: color, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 14),
          Text(
            _mensagem(currentStatus),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 14.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _loading(BuildContext context, String text) {
    final t = context.uai;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: t.primary),
          const SizedBox(height: 16),
          Text(text, style: TextStyle(color: t.textSecondary)),
        ],
      ),
    );
  }

  Widget _erro(BuildContext context) => _messageState(
        context,
        Icons.cloud_off_rounded,
        'Não foi possível verificar seu acesso',
        'Confira sua conexão e tente novamente.',
      );

  Widget _naoEncontrada(BuildContext context) => _messageState(
        context,
        Icons.person_off_rounded,
        'Conta sem perfil administrativo',
        'Saia e entre novamente. Se esta conta for da Minha UAI, ela será encaminhada automaticamente.',
      );

  Widget _messageState(
    BuildContext context,
    IconData icon,
    String title,
    String message,
  ) {
    final t = context.uai;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: t.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 52, color: t.error),
                const SizedBox(height: 14),
                Text(title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    )),
                const SizedBox(height: 8),
                Text(message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.textSecondary, height: 1.4)),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sair'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
