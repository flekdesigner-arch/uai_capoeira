import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';

/// Widgets visuais inspirados no Painel Administrativo.
/// Use estes widgets nas próximas telas para padronizar cards, headers e seções.
class UaiGradientHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> chips;

  const UaiGradientHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.chips = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: t.primaryGradient,
        borderRadius: BorderRadius.circular(t.cardRadius + 2),
        boxShadow: t.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;

          final iconBox = Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(t.cardRadius - 2),
              border: Border.all(color: Colors.white.withOpacity(0.16)),
            ),
            child: Icon(icon, color: Colors.white, size: 34),
          );

          final text = Column(
            crossAxisAlignment:
                narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                title,
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: narrow ? 23 : 28,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.84),
                  fontSize: 13,
                  height: 1.32,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
                  spacing: 8,
                  runSpacing: 8,
                  children: chips,
                ),
              ],
            ],
          );

          if (narrow) {
            return Column(children: [iconBox, const SizedBox(height: 14), text]);
          }

          return Row(children: [iconBox, const SizedBox(width: 16), Expanded(child: text)]);
        },
      ),
    );
  }
}

class UaiWhiteChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const UaiWhiteChip({
    super.key,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class UaiSectionContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const UaiSectionContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(15),
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: child,
    );
  }
}

class UaiSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const UaiSectionTitle({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: t.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(t.buttonRadius),
          ),
          child: Icon(icon, color: t.primary),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: t.textPrimary)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textSecondary, fontSize: 11.5, height: 1.25),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class UaiPremiumActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const UaiPremiumActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius - 6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(t.cardRadius - 6),
          splashColor: color.withOpacity(0.12),
          highlightColor: color.withOpacity(0.06),
          child: Container(
            constraints: const BoxConstraints(minHeight: 82),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius - 6),
              border: Border.all(color: color.withOpacity(0.14)),
              boxShadow: t.softShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                  ),
                  child: Icon(icon, size: 25, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 14.5)),
                      const SizedBox(height: 3),
                      Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.textSecondary, fontSize: 11.5, height: 1.24)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
