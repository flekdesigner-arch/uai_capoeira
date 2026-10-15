import 'package:flutter/material.dart';
import 'package:uai_capoeira/modules/site/portfolio_v3/widgets/portfolio_feed_widget.dart';

/// Compatibilidade com chamadas antigas. O feed agora usa o motor V3, com
/// prefetch por viewport, deduplicação e suporte ao índice `portfolio_feed`.
class TimelineMistaWidget extends StatelessWidget {
  final int limitePorPagina;
  const TimelineMistaWidget({super.key, this.limitePorPagina = 20});

  @override
  Widget build(BuildContext context) => PortfolioFeedWidget(pageSize: limitePorPagina);
}
