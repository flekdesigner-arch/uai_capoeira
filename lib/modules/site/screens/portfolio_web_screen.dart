import 'package:flutter/material.dart';
import 'package:uai_capoeira/modules/site/portfolio_v3/screens/portfolio_screen_v3.dart';

/// Compatibilidade com as rotas existentes. A implementação visual e de dados
/// foi migrada para o Portfólio V3.
class PortfolioWebScreen extends StatelessWidget {
  const PortfolioWebScreen({super.key});

  @override
  Widget build(BuildContext context) => const PortfolioScreenV3();
}
