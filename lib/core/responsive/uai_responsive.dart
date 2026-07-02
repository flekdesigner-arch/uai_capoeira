import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Cérebro responsivo/adaptativo do UAI Capoeira.
///
/// Use este arquivo como base para as telas novas/refatoradas.
/// Ele não depende de pacote externo e funciona em Android, Web, PWA e Windows.
///
/// Ideia principal:
/// - Não decidir layout apenas por "é Android" ou "é Windows".
/// - Decidir pela largura REAL disponível no LayoutBuilder.
/// - No Windows/Web, uma janela pequena deve se comportar como celular.
/// - Uma janela grande deve virar layout administrativo.
enum UaiDeviceClass { phone, tablet, desktop, wide }

enum UaiLayoutMode { compact, comfortable, admin, ultraWide }

@immutable
class UaiResponsive {
  final double width;
  final double height;
  final Orientation orientation;
  final TargetPlatform platform;
  final double textScaleFactor;

  const UaiResponsive({
    required this.width,
    required this.height,
    required this.orientation,
    required this.platform,
    required this.textScaleFactor,
  });

  factory UaiResponsive.of(BuildContext context) {
    final media = MediaQuery.of(context);

    return UaiResponsive(
      width: media.size.width,
      height: media.size.height,
      orientation: media.orientation,
      platform: defaultTargetPlatform,
      textScaleFactor: media.textScaler.scale(1),
    );
  }

  /// Use dentro de LayoutBuilder quando a tela estiver dentro de painéis,
  /// AdminShell, abas ou áreas laterais.
  ///
  /// Assim o layout considera a largura real disponível no painel,
  /// não a largura total do monitor.
  factory UaiResponsive.fromConstraints(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final media = MediaQuery.of(context);
    final resolvedWidth = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : media.size.width;
    final resolvedHeight = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : media.size.height;

    return UaiResponsive(
      width: resolvedWidth,
      height: resolvedHeight,
      orientation: media.orientation,
      platform: defaultTargetPlatform,
      textScaleFactor: media.textScaler.scale(1),
    );
  }

  // Breakpoints do projeto.
  static const double phoneMax = 599;
  static const double tabletMax = 899;
  static const double desktopMax = 1399;
  static const double wideMin = 1400;

  UaiDeviceClass get deviceClass {
    if (width <= phoneMax) return UaiDeviceClass.phone;
    if (width <= tabletMax) return UaiDeviceClass.tablet;
    if (width < wideMin) return UaiDeviceClass.desktop;
    return UaiDeviceClass.wide;
  }

  UaiLayoutMode get layoutMode {
    switch (deviceClass) {
      case UaiDeviceClass.phone:
        return UaiLayoutMode.compact;
      case UaiDeviceClass.tablet:
        return UaiLayoutMode.comfortable;
      case UaiDeviceClass.desktop:
        return UaiLayoutMode.admin;
      case UaiDeviceClass.wide:
        return UaiLayoutMode.ultraWide;
    }
  }

  bool get isPhone => deviceClass == UaiDeviceClass.phone;
  bool get isTablet => deviceClass == UaiDeviceClass.tablet;
  bool get isDesktop => deviceClass == UaiDeviceClass.desktop;
  bool get isWide => deviceClass == UaiDeviceClass.wide;

  bool get isLandscape => orientation == Orientation.landscape;
  bool get isPortrait => orientation == Orientation.portrait;

  bool get isWindows => !kIsWeb && platform == TargetPlatform.windows;
  bool get isDesktopPlatform =>
      !kIsWeb &&
      (platform == TargetPlatform.windows ||
          platform == TargetPlatform.macOS ||
          platform == TargetPlatform.linux);

  bool get isMobilePlatform =>
      !kIsWeb &&
      (platform == TargetPlatform.android || platform == TargetPlatform.iOS);

  /// Desktop real ou web grande.
  bool get wantsAdminLayout => width >= 1000;

  /// Tela pode usar duas colunas principais.
  bool get canUseTwoPanes => width >= 980;

  /// Tela pode usar layout de dashboard amplo.
  bool get canUseWideDashboard => width >= 1180;

  /// Evita que tela gigante estique conteúdo demais.
  double get maxContentWidth {
    if (width < 600) return double.infinity;
    if (width < 900) return 860;
    if (width < 1200) return 1060;
    if (width < 1600) return 1180;
    return 1360;
  }

  /// Para telas administrativas que precisam aproveitar melhor o desktop.
  double get maxAdminContentWidth {
    if (width < 600) return double.infinity;
    if (width < 900) return 900;
    if (width < 1200) return 1120;
    if (width < 1600) return 1360;
    return 1560;
  }

  double get pagePadding {
    if (width < 360) return 10;
    if (isPhone) return 12;
    if (isTablet) return 16;
    if (isDesktop) return 20;
    return 24;
  }

  EdgeInsets get pageInsets {
    final p = pagePadding;
    return EdgeInsets.fromLTRB(p, p, p, p + 12);
  }

  EdgeInsets get listInsets {
    final horizontal = pagePadding;
    final top = isPhone ? 12.0 : 14.0;
    final bottom = isPhone ? 24.0 : 30.0;

    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  double get sectionSpacing {
    if (isPhone) return 12;
    if (isTablet) return 14;
    return 16;
  }

  double get cardPadding {
    if (width < 360) return 12;
    if (isPhone) return 14;
    if (isTablet) return 16;
    return 18;
  }

  double get smallCardPadding {
    if (isPhone) return 10;
    if (isTablet) return 12;
    return 14;
  }

  double get iconBoxSize {
    if (isPhone) return 42;
    if (isTablet) return 44;
    return 46;
  }

  double font(double base) {
    if (textScaleFactor > 1.15) return base;

    if (isPhone) return base;
    if (isTablet) return base + 0.5;
    if (isDesktop) return base + 0.8;
    return base + 1;
  }

  /// Colunas para cards de resumo pequenos: total, pagos, pendentes, taxa etc.
  int get metricColumns {
    if (width < 360) return 1;
    if (width < 720) return 2;
    return 4;
  }

  /// Colunas para ações de menu em cards.
  int get actionColumns {
    if (width < 720) return 1;
    if (width < 1180) return 2;
    return 3;
  }

  /// Em participantes, evita card gigante.
  ///
  /// Use com SliverGridDelegateWithMaxCrossAxisExtent.
  double get participantCardMaxExtent {
    if (width < 380) return 176;
    if (width < 600) return 190;
    if (width < 900) return 210;
    if (width < 1400) return 230;
    return 250;
  }

  /// Altura do card de participante na grade.
  double get participantCardMainExtent {
    if (width < 380) return 188;
    if (width < 600) return 202;
    if (width < 900) return 214;
    if (width < 1400) return 222;
    return 230;
  }

  /// Decide o modo inicial recomendado para lista de participantes.
  ///
  /// 0 = grade
  /// 1 = lista
  /// 2 = planilha
  int get recommendedParticipantsViewMode {
    if (width >= 1180) return 2;
    if (width >= 760) return 1;
    return 0;
  }

  /// Dashboard em participantes:
  /// em phone mantém 2x2; em tablet/desktop usa 4 colunas.
  bool get participantDashboardUseFourColumns => width >= 560;

  /// Altura do banner do evento.
  /// O segredo é controlar no tablet/desktop para o banner não comer a tela.
  double eventBannerHeight({double? imageAspectRatio}) {
    if (isPhone) {
      return width < 380 ? 245 : 275;
    }

    if (isTablet) {
      return 315;
    }

    if (isDesktop) {
      return 350;
    }

    return 380;
  }

  /// Largura máxima do banner.
  double get eventBannerMaxWidth {
    if (isPhone) return double.infinity;
    if (isTablet) return 860;
    if (isDesktop) return 1000;
    return 1060;
  }

  /// Em desktop a tela de evento pode virar duas colunas.
  bool get eventDetailUseSidePanel => width >= 1180;

  /// Altura de header fixo/pinned em listas.
  double get stickyFilterHeight {
    if (isPhone) return 74;
    if (isTablet) return 76;
    return 78;
  }

  /// Largura máxima para cards de lista, evitando que linhas fiquem enormes.
  double get listCardMaxWidth {
    if (isPhone) return double.infinity;
    if (isTablet) return 900;
    if (isDesktop) return 1040;
    return 1180;
  }

  @override
  String toString() {
    return 'UaiResponsive(width: $width, height: $height, class: $deviceClass, mode: $layoutMode)';
  }
}

extension UaiResponsiveContextX on BuildContext {
  UaiResponsive get uaiResponsive => UaiResponsive.of(this);
}

/// Container padrão para páginas.
/// Centraliza e limita largura em tablet/desktop, sem atrapalhar celular.
class UaiPageContainer extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  final bool useAdminWidth;
  final Alignment alignment;

  const UaiPageContainer({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.useAdminWidth = false,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final r = UaiResponsive.fromConstraints(context, constraints);
        final resolvedMaxWidth =
            maxWidth ??
            (useAdminWidth ? r.maxAdminContentWidth : r.maxContentWidth);

        final content = Padding(
          padding: padding ?? r.listInsets,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: resolvedMaxWidth),
            child: child,
          ),
        );

        return Align(alignment: alignment, child: content);
      },
    );
  }
}

/// Ajuda para montar Wrap com largura calculada sem repetir conta em toda tela.
class UaiAdaptiveWrap extends StatelessWidget {
  final int columns;
  final double spacing;
  final double runSpacing;
  final List<Widget> children;

  const UaiAdaptiveWrap({
    super.key,
    required this.columns,
    required this.children,
    this.spacing = 10,
    this.runSpacing = 10,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final safeColumns = columns <= 0 ? 1 : columns;
        final available = constraints.maxWidth;
        final itemWidth =
            (available - (spacing * (safeColumns - 1))) / safeColumns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }
}

/// Grid que limita a largura máxima do card.
/// Excelente para desktop: cria mais colunas sem transformar cada card em outdoor.
class UaiMaxExtentGrid extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double maxCrossAxisExtent;
  final double mainAxisExtent;
  final double spacing;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? physics;
  final bool shrinkWrap;

  const UaiMaxExtentGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.maxCrossAxisExtent,
    required this.mainAxisExtent,
    this.spacing = 10,
    this.padding = EdgeInsets.zero,
    this.physics,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      physics: physics,
      shrinkWrap: shrinkWrap,
      itemCount: itemCount,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCrossAxisExtent,
        mainAxisExtent: mainAxisExtent,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
      ),
      itemBuilder: itemBuilder,
    );
  }
}

/// Sliver equivalente ao UaiMaxExtentGrid.
class UaiSliverMaxExtentGrid extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double maxCrossAxisExtent;
  final double mainAxisExtent;
  final double spacing;

  const UaiSliverMaxExtentGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.maxCrossAxisExtent,
    required this.mainAxisExtent,
    this.spacing = 10,
  });

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCrossAxisExtent,
        mainAxisExtent: mainAxisExtent,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
      ),
      delegate: SliverChildBuilderDelegate(itemBuilder, childCount: itemCount),
    );
  }
}

/// Compatibilidade com o arquivo antigo ResponsiveUtils.
/// Pode ir migrando as telas aos poucos sem quebrar imports antigos.
class ResponsiveUtils {
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;
  static const double minHeight = 500;

  static bool isMobile(BuildContext context) {
    return UaiResponsive.of(context).isPhone;
  }

  static bool isTablet(BuildContext context) {
    return UaiResponsive.of(context).isTablet;
  }

  static bool isDesktop(BuildContext context) {
    final r = UaiResponsive.of(context);
    return r.isDesktop || r.isWide;
  }

  static EdgeInsets getResponsivePadding(BuildContext context) {
    final r = UaiResponsive.of(context);
    return EdgeInsets.all(r.pagePadding);
  }

  static double getResponsiveFontSize(
    BuildContext context, {
    required double baseSize,
  }) {
    return UaiResponsive.of(context).font(baseSize);
  }

  static int getGridCrossAxisCount(BuildContext context) {
    return UaiResponsive.of(context).metricColumns;
  }

  static double getMinHeight(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return height < minHeight ? minHeight : height;
  }
}
