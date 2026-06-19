import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class UsuarioAdminAccess {
  final bool adminMaster;
  final bool podeGerenciarUsuarios;

  const UsuarioAdminAccess({
    required this.adminMaster,
    required this.podeGerenciarUsuarios,
  });

  bool get liberado => adminMaster || podeGerenciarUsuarios;
}

Future<UsuarioAdminAccess> carregarAcessoGestaoUsuarios() async {
  final service = PermissaoService();
  final results = await Future.wait<bool>([
    service.usuarioAtualEhAdmin(),
    service.temPermissao('pode_gerenciar_usuarios'),
  ]);

  return UsuarioAdminAccess(
    adminMaster: results[0],
    podeGerenciarUsuarios: results[1],
  );
}

Widget buildAcessoNegadoGestaoUsuarios(BuildContext context) {
  final t = context.uai;
  return Scaffold(
    backgroundColor: t.background,
    appBar: AppBar(
      title: const Text(
        'Gerenciar Usuários',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border.all(color: t.border),
            boxShadow: t.softShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, color: t.error, size: 52),
              const SizedBox(height: 12),
              Text(
                'Você não tem permissão para gerenciar usuários.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Solicite ao administrador a permissão pode_gerenciar_usuarios.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textSecondary,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget buildLoadingGestaoUsuarios(BuildContext context) {
  final t = context.uai;
  return Scaffold(
    backgroundColor: t.background,
    appBar: AppBar(
      title: const Text(
        'Gerenciar Usuários',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body: Center(child: CircularProgressIndicator(color: t.primary)),
  );
}
