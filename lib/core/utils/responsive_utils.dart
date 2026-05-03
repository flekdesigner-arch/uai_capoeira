import 'package:flutter/material.dart';

class ResponsiveUtils {
  // Breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;

  // Altura mínima segura
  static const double minHeight = 500;

  // Verificar se é mobile
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < mobileBreakpoint;
  }

  // Verificar se é tablet
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mobileBreakpoint && width < tabletBreakpoint;
  }

  // Verificar se é desktop
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= tabletBreakpoint;
  }

  // Obter padding responsivo
  static EdgeInsets getResponsivePadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width < 600) {
      return const EdgeInsets.all(16);
    } else if (width < 900) {
      return const EdgeInsets.all(24);
    } else {
      return const EdgeInsets.all(32);
    }
  }

  // Obter tamanho de fonte responsivo
  static double getResponsiveFontSize(BuildContext context, {required double baseSize}) {
    final width = MediaQuery.of(context).size.width;

    if (width < 600) {
      return baseSize;
    } else if (width < 900) {
      return baseSize * 1.1;
    } else {
      return baseSize * 1.2;
    }
  }

  // Obter quantidade de colunas em grid
  static int getGridCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width < 600) {
      return 1;
    } else if (width < 900) {
      return 2;
    } else if (width < 1200) {
      return 3;
    } else {
      return 4;
    }
  }

  // Obter altura mínima segura (para evitar espremer na vertical)
  static double getMinHeight(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return height < minHeight ? minHeight : height;
  }
}