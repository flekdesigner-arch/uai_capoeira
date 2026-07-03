import 'package:flutter/material.dart';

@immutable
class UaiThemeTokens extends ThemeExtension<UaiThemeTokens> {
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color accent;

  final Color background;
  final Color surface;
  final Color card;
  final Color cardAlt;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;

  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  final Color eventos;
  final Color associacao;
  final Color rifas;
  final Color uniformes;
  final Color inscricoes;

  final Gradient primaryGradient;
  final Gradient softGradient;

  final double cardRadius;
  final double buttonRadius;
  final double inputRadius;

  final List<BoxShadow> cardShadow;
  final List<BoxShadow> softShadow;

  final String? fontFamily;

  const UaiThemeTokens({
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.accent,
    required this.background,
    required this.surface,
    required this.card,
    required this.cardAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.eventos,
    required this.associacao,
    required this.rifas,
    required this.uniformes,
    required this.inscricoes,
    required this.primaryGradient,
    required this.softGradient,
    required this.cardRadius,
    required this.buttonRadius,
    required this.inputRadius,
    required this.cardShadow,
    required this.softShadow,
    this.fontFamily,
  });

  static UaiThemeTokens of(BuildContext context) {
    return Theme.of(context).extension<UaiThemeTokens>() ??
        UaiThemeTokens.uaiClassico;
  }

  Color getModuleColor(String moduleName) {
    switch (moduleName.toLowerCase().trim()) {
      case 'eventos':
        return eventos;
      case 'associacao':
      case 'associação':
        return associacao;
      case 'rifas':
        return rifas;
      case 'uniformes':
        return uniformes;
      case 'inscricoes':
      case 'inscrições':
        return inscricoes;
      default:
        return primary;
    }
  }

  Color readableTextOn(Color background) {
    final luminance = background.computeLuminance();
    return luminance > 0.48 ? const Color(0xFF111827) : const Color(0xFFFFFFFF);
  }

  static Color lighten(Color color, [double amount = 0.12]) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  static Color darken(Color color, [double amount = 0.12]) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  static bool isDarkBackground(Color color) {
    return color.computeLuminance() < 0.35;
  }

  factory UaiThemeTokens.custom({
    required Color primary,
    required Color background,
    required Color surface,
    required Color card,
    required Color textPrimary,
    Color? accent,
    Color? cardAlt,
    Color? textSecondary,
    Color? textMuted,
    Color? border,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    double cardRadius = 20,
    double buttonRadius = 15,
    double inputRadius = 15,
    String? fontFamily,
  }) {
    final isDark = isDarkBackground(background);
    final safeAccent = accent ?? lighten(primary, 0.18);
    final safeCardAlt =
        cardAlt ?? (isDark ? lighten(card, 0.06) : darken(card, 0.04));
    final safeTextSecondary =
        textSecondary ??
        (isDark ? const Color(0xFFD5DAEA) : const Color(0xFF4B5563));
    final safeTextMuted =
        textMuted ??
        (isDark ? const Color(0xFFAEB6CA) : const Color(0xFF9CA3AF));
    final safeBorder =
        border ?? (isDark ? lighten(card, 0.11) : const Color(0xFFE5E7EB));

    return UaiThemeTokens(
      primary: primary,
      primaryLight: lighten(primary, 0.14),
      primaryDark: darken(primary, 0.18),
      accent: safeAccent,
      background: background,
      surface: surface,
      card: card,
      cardAlt: safeCardAlt,
      textPrimary: textPrimary,
      textSecondary: safeTextSecondary,
      textMuted: safeTextMuted,
      border: safeBorder,
      success: success ?? const Color(0xFF35D07F),
      warning: warning ?? const Color(0xFFE8B451),
      error: error ?? const Color(0xFFFF4D5E),
      info: info ?? const Color(0xFF64D7FF),
      eventos: info ?? const Color(0xFF64D7FF),
      associacao: const Color(0xFFBDA0FF),
      rifas: warning ?? const Color(0xFFE8B451),
      uniformes: success ?? const Color(0xFF35D07F),
      inscricoes: info ?? const Color(0xFF64D7FF),
      primaryGradient: LinearGradient(
        colors: [darken(primary, 0.20), primary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      softGradient: LinearGradient(
        colors: [surface, safeCardAlt],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      cardRadius: cardRadius,
      buttonRadius: buttonRadius,
      inputRadius: inputRadius,
      cardShadow: [
        BoxShadow(
          color: isDark ? const Color(0x88000000) : const Color(0x18000000),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
      softShadow: [
        BoxShadow(
          color: isDark ? const Color(0x55000000) : const Color(0x0D000000),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
      fontFamily: fontFamily,
    );
  }

  static const UaiThemeTokens setembroAmarelo = UaiThemeTokens(
    primary: Color(0xFFF0C93A),
    primaryLight: Color(0xFFFFE36A),
    primaryDark: Color(0xFFB58A00),
    accent: Color(0xFFFFF07C),
    background: Color(0xFF161412),
    surface: Color(0xFF221D15),
    card: Color(0xFF2B241A),
    cardAlt: Color(0xFF362D21),
    textPrimary: Color(0xFFFFF8E8),
    textSecondary: Color(0xFFE8D8A6),
    textMuted: Color(0xFFC8BA80),
    border: Color(0xFF5A4B2A),
    success: Color(0xFF7AC77A),
    warning: Color(0xFFF0C93A),
    error: Color(0xFFE15F4F),
    info: Color(0xFF9FB6FF),
    eventos: Color(0xFF9FB6FF),
    associacao: Color(0xFFE8A3FF),
    rifas: Color(0xFFF0C93A),
    uniformes: Color(0xFF7AC77A),
    inscricoes: Color(0xFF9FB6FF),
    primaryGradient: LinearGradient(
      colors: [Color(0xFFB58A00), Color(0xFFF0C93A)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    softGradient: LinearGradient(
      colors: [Color(0xFF221D15), Color(0xFF362D21)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardRadius: 20,
    buttonRadius: 15,
    inputRadius: 15,
    cardShadow: [
      BoxShadow(
        color: Color(0xA0000000),
        blurRadius: 22,
        offset: Offset(0, 10),
      ),
    ],
    softShadow: [
      BoxShadow(color: Color(0x5A000000), blurRadius: 12, offset: Offset(0, 5)),
    ],
  );

  static const UaiThemeTokens outubroRosa = UaiThemeTokens(
    primary: Color(0xFFE83E8C),
    primaryLight: Color(0xFFFF75B2),
    primaryDark: Color(0xFF9D1F57),
    accent: Color(0xFFFFA6C8),
    background: Color(0xFF160B10),
    surface: Color(0xFF22131A),
    card: Color(0xFF2E1926),
    cardAlt: Color(0xFF3A2131),
    textPrimary: Color(0xFFFFF4F8),
    textSecondary: Color(0xFFF0CCDB),
    textMuted: Color(0xFFC79AAA),
    border: Color(0xFF5F314B),
    success: Color(0xFF3CCB7F),
    warning: Color(0xFFF0B44C),
    error: Color(0xFFFF5D73),
    info: Color(0xFF8BC4FF),
    eventos: Color(0xFF8BC4FF),
    associacao: Color(0xFFE8A3FF),
    rifas: Color(0xFFF0B44C),
    uniformes: Color(0xFF3CCB7F),
    inscricoes: Color(0xFF8BC4FF),
    primaryGradient: LinearGradient(
      colors: [Color(0xFF9D1F57), Color(0xFFE83E8C)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    softGradient: LinearGradient(
      colors: [Color(0xFF22131A), Color(0xFF3A2131)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardRadius: 20,
    buttonRadius: 15,
    inputRadius: 15,
    cardShadow: [
      BoxShadow(
        color: Color(0xA0000000),
        blurRadius: 22,
        offset: Offset(0, 10),
      ),
    ],
    softShadow: [
      BoxShadow(color: Color(0x5A000000), blurRadius: 12, offset: Offset(0, 5)),
    ],
  );

  static const UaiThemeTokens novembroAzul = UaiThemeTokens(
    primary: Color(0xFF1976D2),
    primaryLight: Color(0xFF59A7FF),
    primaryDark: Color(0xFF0E4B88),
    accent: Color(0xFF7CC8FF),
    background: Color(0xFF08111C),
    surface: Color(0xFF0F1825),
    card: Color(0xFF162133),
    cardAlt: Color(0xFF1D2D45),
    textPrimary: Color(0xFFF3F8FF),
    textSecondary: Color(0xFFC9DBF0),
    textMuted: Color(0xFF93ACC5),
    border: Color(0xFF314B6A),
    success: Color(0xFF34D399),
    warning: Color(0xFFF5C451),
    error: Color(0xFFFF5D73),
    info: Color(0xFF7CC8FF),
    eventos: Color(0xFF7CC8FF),
    associacao: Color(0xFFC29BFF),
    rifas: Color(0xFFF5C451),
    uniformes: Color(0xFF34D399),
    inscricoes: Color(0xFF7CC8FF),
    primaryGradient: LinearGradient(
      colors: [Color(0xFF0E4B88), Color(0xFF1976D2)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    softGradient: LinearGradient(
      colors: [Color(0xFF0F1825), Color(0xFF1D2D45)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardRadius: 20,
    buttonRadius: 15,
    inputRadius: 15,
    cardShadow: [
      BoxShadow(
        color: Color(0xA0000000),
        blurRadius: 22,
        offset: Offset(0, 10),
      ),
    ],
    softShadow: [
      BoxShadow(color: Color(0x5A000000), blurRadius: 12, offset: Offset(0, 5)),
    ],
  );

  static const UaiThemeTokens copaBrasil = UaiThemeTokens(
    primary: Color(0xFF1B8F3A),
    primaryLight: Color(0xFF4CC96C),
    primaryDark: Color(0xFF0F5F24),
    accent: Color(0xFFF4D63C),
    background: Color(0xFF06110B),
    surface: Color(0xFF101C12),
    card: Color(0xFF15261A),
    cardAlt: Color(0xFF1D3322),
    textPrimary: Color(0xFFF3FFF5),
    textSecondary: Color(0xFFCDE7D2),
    textMuted: Color(0xFF8FB596),
    border: Color(0xFF31563A),
    success: Color(0xFF34D399),
    warning: Color(0xFFF4D63C),
    error: Color(0xFFFF5D73),
    info: Color(0xFF57B5FF),
    eventos: Color(0xFF57B5FF),
    associacao: Color(0xFFF4D63C),
    rifas: Color(0xFFF4D63C),
    uniformes: Color(0xFF34D399),
    inscricoes: Color(0xFF57B5FF),
    primaryGradient: LinearGradient(
      colors: [Color(0xFF0F5F24), Color(0xFF1B8F3A)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    softGradient: LinearGradient(
      colors: [Color(0xFF101C12), Color(0xFF1D3322)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardRadius: 18,
    buttonRadius: 14,
    inputRadius: 14,
    cardShadow: [
      BoxShadow(
        color: Color(0xB0000000),
        blurRadius: 22,
        offset: Offset(0, 10),
      ),
    ],
    softShadow: [
      BoxShadow(color: Color(0x60000000), blurRadius: 12, offset: Offset(0, 5)),
    ],
  );

  static const UaiThemeTokens natal = UaiThemeTokens(
    primary: Color(0xFFB71C1C),
    primaryLight: Color(0xFFF04B48),
    primaryDark: Color(0xFF7A0F0F),
    accent: Color(0xFFE8C65A),
    background: Color(0xFF0C1310),
    surface: Color(0xFF121C18),
    card: Color(0xFF17241F),
    cardAlt: Color(0xFF20302A),
    textPrimary: Color(0xFFF1FFF7),
    textSecondary: Color(0xFFD1E7DA),
    textMuted: Color(0xFF9DB6A9),
    border: Color(0xFF355247),
    success: Color(0xFF2E7D32),
    warning: Color(0xFFE8C65A),
    error: Color(0xFFF04B48),
    info: Color(0xFF7DB7D8),
    eventos: Color(0xFF7DB7D8),
    associacao: Color(0xFFE8C65A),
    rifas: Color(0xFFE8C65A),
    uniformes: Color(0xFF2E7D32),
    inscricoes: Color(0xFF7DB7D8),
    primaryGradient: LinearGradient(
      colors: [Color(0xFF7A0F0F), Color(0xFFB71C1C)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    softGradient: LinearGradient(
      colors: [Color(0xFF121C18), Color(0xFF20302A)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardRadius: 20,
    buttonRadius: 15,
    inputRadius: 15,
    cardShadow: [
      BoxShadow(
        color: Color(0x9A000000),
        blurRadius: 22,
        offset: Offset(0, 10),
      ),
    ],
    softShadow: [
      BoxShadow(color: Color(0x55000000), blurRadius: 12, offset: Offset(0, 5)),
    ],
  );

  static const UaiThemeTokens batizadoUai = UaiThemeTokens(
    primary: Color(0xFF3B82F6),
    primaryLight: Color(0xFF7CB6FF),
    primaryDark: Color(0xFF1E4B88),
    accent: Color(0xFF8B5CF6),
    background: Color(0xFFF7F7FC),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFF8FAFF),
    cardAlt: Color(0xFFEFF4FF),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF64748B),
    border: Color(0xFFDBE2F0),
    success: Color(0xFF14B8A6),
    warning: Color(0xFFF59E0B),
    error: Color(0xFFEF4444),
    info: Color(0xFF06B6D4),
    eventos: Color(0xFF06B6D4),
    associacao: Color(0xFF8B5CF6),
    rifas: Color(0xFFF59E0B),
    uniformes: Color(0xFF14B8A6),
    inscricoes: Color(0xFF06B6D4),
    primaryGradient: LinearGradient(
      colors: [Color(0xFF1E4B88), Color(0xFF3B82F6)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    softGradient: LinearGradient(
      colors: [Color(0xFFF8FAFF), Color(0xFFEFF4FF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardRadius: 20,
    buttonRadius: 15,
    inputRadius: 15,
    cardShadow: [
      BoxShadow(color: Color(0x15000000), blurRadius: 18, offset: Offset(0, 8)),
    ],
    softShadow: [
      BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 4)),
    ],
  );
  static const UaiThemeTokens uaiClassico = UaiThemeTokens(
    primary: Color(0xFFB71C1C),
    primaryLight: Color(0xFFD32F2F),
    primaryDark: Color(0xFF7F0000),
    accent: Color(0xFFFFB300),
    background: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardAlt: Color(0xFFFFF5F5),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF4B5563),
    textMuted: Color(0xFF9CA3AF),
    border: Color(0xFFE5E7EB),
    success: Color(0xFF2E7D32),
    warning: Color(0xFFF59E0B),
    error: Color(0xFFD32F2F),
    info: Color(0xFF1976D2),
    eventos: Color(0xFF1976D2),
    associacao: Color(0xFF8E24AA),
    rifas: Color(0xFFFFA000),
    uniformes: Color(0xFF388E3C),
    inscricoes: Color(0xFF009688),
    primaryGradient: LinearGradient(
      colors: [Color(0xFFB71C1C), Color(0xFFD32F2F)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    softGradient: LinearGradient(
      colors: [Color(0xFFFFFFFF), Color(0xFFFFF5F5)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardRadius: 24,
    buttonRadius: 16,
    inputRadius: 16,
    cardShadow: [
      BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8)),
    ],
    softShadow: [
      BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4)),
    ],
  );

  static const UaiThemeTokens draculaVermelho = UaiThemeTokens(
    primary: Color(0xFFD21F35),
    primaryLight: Color(0xFFFF4D63),
    primaryDark: Color(0xFF7A1020),
    accent: Color(0xFFFF6B7A),
    background: Color(0xFF101018),
    surface: Color(0xFF171722),
    card: Color(0xFF202232),
    cardAlt: Color(0xFF2B2E43),
    textPrimary: Color(0xFFF8F8F2),
    textSecondary: Color(0xFFE2E4F2),
    textMuted: Color(0xFFB8BDD4),
    border: Color(0xFF3A4056),
    success: Color(0xFF35D07F),
    warning: Color(0xFFE8B451),
    error: Color(0xFFFF4D5E),
    info: Color(0xFF64D7FF),
    eventos: Color(0xFF64D7FF),
    associacao: Color(0xFFBDA0FF),
    rifas: Color(0xFFE8B451),
    uniformes: Color(0xFF35D07F),
    inscricoes: Color(0xFF64D7FF),
    primaryGradient: LinearGradient(
      colors: [Color(0xFF7A1020), Color(0xFFD21F35)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    softGradient: LinearGradient(
      colors: [Color(0xFF171722), Color(0xFF202232)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardRadius: 18,
    buttonRadius: 14,
    inputRadius: 14,
    cardShadow: [
      BoxShadow(
        color: Color(0x88000000),
        blurRadius: 24,
        offset: Offset(0, 12),
      ),
    ],
    softShadow: [
      BoxShadow(color: Color(0x55000000), blurRadius: 14, offset: Offset(0, 6)),
    ],
  );

  static const UaiThemeTokens cafeTerra = UaiThemeTokens(
    primary: Color(0xFF8B4A24),
    primaryLight: Color(0xFFC47A3D),
    primaryDark: Color(0xFF4A2413),
    accent: Color(0xFFD9A45F),
    background: Color(0xFF17110D),
    surface: Color(0xFF201713),
    card: Color(0xFF2A1D17),
    cardAlt: Color(0xFF36251D),
    textPrimary: Color(0xFFFFF4E6),
    textSecondary: Color(0xFFE8D2B8),
    textMuted: Color(0xFFC0A58B),
    border: Color(0xFF4A3529),
    success: Color(0xFF7AC77A),
    warning: Color(0xFFD9A45F),
    error: Color(0xFFE15F4F),
    info: Color(0xFF7DB7D8),
    eventos: Color(0xFF7DB7D8),
    associacao: Color(0xFFC896D8),
    rifas: Color(0xFFD9A45F),
    uniformes: Color(0xFF7AC77A),
    inscricoes: Color(0xFF7DB7D8),
    primaryGradient: LinearGradient(
      colors: [Color(0xFF4A2413), Color(0xFF8B4A24)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    softGradient: LinearGradient(
      colors: [Color(0xFF201713), Color(0xFF36251D)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardRadius: 20,
    buttonRadius: 15,
    inputRadius: 15,
    cardShadow: [
      BoxShadow(
        color: Color(0x90000000),
        blurRadius: 24,
        offset: Offset(0, 12),
      ),
    ],
    softShadow: [
      BoxShadow(color: Color(0x60000000), blurRadius: 14, offset: Offset(0, 6)),
    ],
  );

  static const UaiThemeTokens verdeNeon = UaiThemeTokens(
    primary: Color(0xFF39FF14),
    primaryLight: Color(0xFF8BFF6A),
    primaryDark: Color(0xFF138A20),
    accent: Color(0xFF00FFD1),
    background: Color(0xFF050806),
    surface: Color(0xFF0B120E),
    card: Color(0xFF101A14),
    cardAlt: Color(0xFF17251C),
    textPrimary: Color(0xFFEFFFF0),
    textSecondary: Color(0xFFCBE8D0),
    textMuted: Color(0xFF8FAC96),
    border: Color(0xFF23402A),
    success: Color(0xFF39FF14),
    warning: Color(0xFFE8FF5A),
    error: Color(0xFFFF3B5C),
    info: Color(0xFF00FFD1),
    eventos: Color(0xFF00FFD1),
    associacao: Color(0xFFA56BFF),
    rifas: Color(0xFFE8FF5A),
    uniformes: Color(0xFF39FF14),
    inscricoes: Color(0xFF00FFD1),
    primaryGradient: LinearGradient(
      colors: [Color(0xFF0F5F1A), Color(0xFF39FF14)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    softGradient: LinearGradient(
      colors: [Color(0xFF0B120E), Color(0xFF17251C)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardRadius: 14,
    buttonRadius: 12,
    inputRadius: 12,
    cardShadow: [
      BoxShadow(
        color: Color(0xAA000000),
        blurRadius: 24,
        offset: Offset(0, 12),
      ),
      BoxShadow(color: Color(0x4039FF14), blurRadius: 18, offset: Offset(0, 0)),
    ],
    softShadow: [
      BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 6)),
    ],
    fontFamily: 'monospace',
  );

  get infoGrey => null;

  @override
  UaiThemeTokens copyWith({
    Color? primary,
    Color? primaryLight,
    Color? primaryDark,
    Color? accent,
    Color? background,
    Color? surface,
    Color? card,
    Color? cardAlt,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? border,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? eventos,
    Color? associacao,
    Color? rifas,
    Color? uniformes,
    Color? inscricoes,
    Gradient? primaryGradient,
    Gradient? softGradient,
    double? cardRadius,
    double? buttonRadius,
    double? inputRadius,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? softShadow,
    String? fontFamily,
  }) {
    return UaiThemeTokens(
      primary: primary ?? this.primary,
      primaryLight: primaryLight ?? this.primaryLight,
      primaryDark: primaryDark ?? this.primaryDark,
      accent: accent ?? this.accent,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      cardAlt: cardAlt ?? this.cardAlt,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      eventos: eventos ?? this.eventos,
      associacao: associacao ?? this.associacao,
      rifas: rifas ?? this.rifas,
      uniformes: uniformes ?? this.uniformes,
      inscricoes: inscricoes ?? this.inscricoes,
      primaryGradient: primaryGradient ?? this.primaryGradient,
      softGradient: softGradient ?? this.softGradient,
      cardRadius: cardRadius ?? this.cardRadius,
      buttonRadius: buttonRadius ?? this.buttonRadius,
      inputRadius: inputRadius ?? this.inputRadius,
      cardShadow: cardShadow ?? this.cardShadow,
      softShadow: softShadow ?? this.softShadow,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }

  @override
  UaiThemeTokens lerp(ThemeExtension<UaiThemeTokens>? other, double t) {
    if (other is! UaiThemeTokens) return this;

    return UaiThemeTokens(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardAlt: Color.lerp(cardAlt, other.cardAlt, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      eventos: Color.lerp(eventos, other.eventos, t)!,
      associacao: Color.lerp(associacao, other.associacao, t)!,
      rifas: Color.lerp(rifas, other.rifas, t)!,
      uniformes: Color.lerp(uniformes, other.uniformes, t)!,
      inscricoes: Color.lerp(inscricoes, other.inscricoes, t)!,
      primaryGradient: t < 0.5 ? primaryGradient : other.primaryGradient,
      softGradient: t < 0.5 ? softGradient : other.softGradient,
      cardRadius: _lerpDouble(cardRadius, other.cardRadius, t),
      buttonRadius: _lerpDouble(buttonRadius, other.buttonRadius, t),
      inputRadius: _lerpDouble(inputRadius, other.inputRadius, t),
      cardShadow: t < 0.5 ? cardShadow : other.cardShadow,
      softShadow: t < 0.5 ? softShadow : other.softShadow,
      fontFamily: t < 0.5 ? fontFamily : other.fontFamily,
    );
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
}
