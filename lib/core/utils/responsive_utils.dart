// lib/core/utils/responsive_utils.dart
//
// Compatibilidade da versão 2.0.67.
//
// Antes este arquivo tinha regras simples de responsividade.
// Agora o cérebro responsivo oficial fica em:
//
// lib/core/responsive/uai_responsive.dart
//
// Mantemos este arquivo como "ponte" para não quebrar telas antigas
// que ainda importam:
// package:uai_capoeira/core/utils/responsive_utils.dart
//
// Assim você pode migrar o app aos poucos, uma tela por vez.

export '../responsive/uai_responsive.dart';
