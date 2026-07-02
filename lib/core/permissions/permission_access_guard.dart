import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

class PermissionAccessGuard {
  PermissionAccessGuard({PermissaoService? service})
    : _service = service ?? PermissaoService();

  final PermissaoService _service;

  Future<bool> canAccess({String? permission, bool adminOnly = false}) async {
    if (await _service.usuarioAtualEhAdmin()) return true;
    if (adminOnly || permission == null) return false;
    return _service.temPermissao(permission);
  }

  Future<bool> canAny(
    List<String> permissions, {
    bool adminOnly = false,
  }) async {
    if (await _service.usuarioAtualEhAdmin()) return true;
    if (adminOnly || permissions.isEmpty) return false;
    return _service.temQualquerPermissao(permissions);
  }

  Future<bool> canAnyDirect(List<String> permissions) async {
    if (await _service.usuarioAtualEhAdmin()) return true;
    if (permissions.isEmpty) return false;
    return _service.temQualquerPermissaoDireta(permissions);
  }

  Future<bool> revalidate(
    BuildContext context, {
    String? permission,
    bool adminOnly = false,
    required String message,
  }) async {
    final allowed = await canAccess(
      permission: permission,
      adminOnly: adminOnly,
    );
    if (!context.mounted) return false;

    if (!allowed) {
      final t = context.uai;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: _readableOn(t.error),
              fontWeight: FontWeight.w800,
            ),
          ),
          backgroundColor: t.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return allowed;
  }

  Future<bool> revalidateAny(
    BuildContext context, {
    required List<String> permissions,
    bool adminOnly = false,
    required String message,
  }) async {
    final allowed = await canAny(permissions, adminOnly: adminOnly);
    if (!context.mounted) return false;

    if (!allowed) {
      final t = context.uai;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: _readableOn(t.error),
              fontWeight: FontWeight.w800,
            ),
          ),
          backgroundColor: t.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return allowed;
  }

  Future<bool> revalidateAnyDirect(
    BuildContext context, {
    required List<String> permissions,
    required String message,
  }) async {
    final allowed = await canAnyDirect(permissions);
    if (!context.mounted) return false;

    if (!allowed) {
      final t = context.uai;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: _readableOn(t.error),
              fontWeight: FontWeight.w800,
            ),
          ),
          backgroundColor: t.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return allowed;
  }

  static Widget loadingScaffold(BuildContext context, {required String title}) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Center(child: CircularProgressIndicator(color: t.primary)),
    );
  }

  static Widget deniedScaffold(
    BuildContext context, {
    required String title,
    required String message,
    String? subtitle,
  }) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
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
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: t.textSecondary,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: Navigator.of(context).canPop()
                      ? () => Navigator.of(context).pop()
                      : null,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Voltar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : Colors.white;
  }
}
