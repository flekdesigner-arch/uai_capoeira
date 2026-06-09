// lib/modules/sistema/atualizacoes/services/local_publish_platform_service.dart
//
// =====================================================
// 🖥️ DETECTOR DE PLATAFORMA DA AUTOMAÇÃO LOCAL - UAI
// =====================================================
//
// Este arquivo é seguro para APK, PWA e Windows.
// Não usa dart:io.
// Serve para decidir se a automação completa deve aparecer na tela.
//
// Regra:
// - Windows Desktop: libera o botão "Fazer tudo automaticamente"
// - PWA/Web: bloqueia
// - APK Android: bloqueia
// - demais plataformas: bloqueia por segurança
// =====================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class LocalPublishPlatformInfo {
  final bool isWeb;
  final TargetPlatform targetPlatform;
  final bool isWindowsDesktop;
  final bool canRunLocalAutomation;
  final String platformLabel;
  final String blockedReason;

  const LocalPublishPlatformInfo({
    required this.isWeb,
    required this.targetPlatform,
    required this.isWindowsDesktop,
    required this.canRunLocalAutomation,
    required this.platformLabel,
    required this.blockedReason,
  });

  bool get isBlocked => !canRunLocalAutomation;

  IconData get icon {
    if (canRunLocalAutomation) return Icons.desktop_windows_rounded;
    if (isWeb) return Icons.public_rounded;

    switch (targetPlatform) {
      case TargetPlatform.android:
        return Icons.android_rounded;
      case TargetPlatform.iOS:
        return Icons.phone_iphone_rounded;
      case TargetPlatform.macOS:
        return Icons.laptop_mac_rounded;
      case TargetPlatform.linux:
        return Icons.computer_rounded;
      case TargetPlatform.windows:
        return Icons.desktop_windows_rounded;
      case TargetPlatform.fuchsia:
        return Icons.devices_other_rounded;
    }
  }
}

class LocalPublishPlatformService {
  const LocalPublishPlatformService();

  LocalPublishPlatformInfo getInfo() {
    final platform = defaultTargetPlatform;

    if (kIsWeb) {
      return LocalPublishPlatformInfo(
        isWeb: true,
        targetPlatform: platform,
        isWindowsDesktop: false,
        canRunLocalAutomation: false,
        platformLabel: 'PWA / Web',
        blockedReason:
        'Automação local indisponível no PWA. Navegadores não podem executar PowerShell, Flutter build ou Firebase deploy.',
      );
    }

    if (platform == TargetPlatform.windows) {
      return const LocalPublishPlatformInfo(
        isWeb: false,
        targetPlatform: TargetPlatform.windows,
        isWindowsDesktop: true,
        canRunLocalAutomation: true,
        platformLabel: 'Windows Desktop',
        blockedReason: '',
      );
    }

    if (platform == TargetPlatform.android) {
      return const LocalPublishPlatformInfo(
        isWeb: false,
        targetPlatform: TargetPlatform.android,
        isWindowsDesktop: false,
        canRunLocalAutomation: false,
        platformLabel: 'APK Android',
        blockedReason:
        'Automação local indisponível no APK. O Android não pode executar scripts PowerShell nem gerar builds do próprio app.',
      );
    }

    if (platform == TargetPlatform.iOS) {
      return const LocalPublishPlatformInfo(
        isWeb: false,
        targetPlatform: TargetPlatform.iOS,
        isWindowsDesktop: false,
        canRunLocalAutomation: false,
        platformLabel: 'iOS',
        blockedReason:
        'Automação local liberada apenas no Windows Desktop.',
      );
    }

    if (platform == TargetPlatform.macOS) {
      return const LocalPublishPlatformInfo(
        isWeb: false,
        targetPlatform: TargetPlatform.macOS,
        isWindowsDesktop: false,
        canRunLocalAutomation: false,
        platformLabel: 'macOS',
        blockedReason:
        'Automação local configurada para PowerShell no Windows Desktop.',
      );
    }

    if (platform == TargetPlatform.linux) {
      return const LocalPublishPlatformInfo(
        isWeb: false,
        targetPlatform: TargetPlatform.linux,
        isWindowsDesktop: false,
        canRunLocalAutomation: false,
        platformLabel: 'Linux',
        blockedReason:
        'Automação local configurada para PowerShell no Windows Desktop.',
      );
    }

    return LocalPublishPlatformInfo(
      isWeb: false,
      targetPlatform: platform,
      isWindowsDesktop: false,
      canRunLocalAutomation: false,
      platformLabel: platform.name,
      blockedReason: 'Automação local liberada apenas no Windows Desktop.',
    );
  }
}
