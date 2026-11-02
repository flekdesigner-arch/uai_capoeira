import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:uai_capoeira/core/services/app_update_check_service.dart';
import 'package:uai_capoeira/core/services/atualizacao_dialog_service.dart';
import 'package:uai_capoeira/core/services/official_apk_website_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/shared/widgets/update_compact_panel.dart';

/// Bloqueio intransponível quando a release mínima exige atualização.
/// A composição visual é compartilhada com a atualização opcional.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child, this.ignorarWeb = true});
  final Widget child;
  final bool ignorarWeb;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  final _checker = AppUpdateCheckService();
  late Future<AppUpdateStatus> _pending;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _pending = _checker.verificarStatus();
  }

  Future<void> _verify() async {
    if (!mounted) return;
    setState(() => _pending = _checker.verificarStatus());
  }

  Future<void> _install(AppUpdateStatus status) async {
    if (_installing) return;
    setState(() => _installing = true);
    try {
      await AtualizacaoDialogService().iniciarAtualizacao(context, status.versaoDestino);
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  List<String> _changes(AppUpdateStatus status) => [
    ...status.implementacoes,
    ...status.melhorias,
    ...status.correcoes,
    ...status.removidos,
  ];

  @override
  Widget build(BuildContext context) {
    if (widget.ignorarWeb && kIsWeb) return widget.child;
    return FutureBuilder<AppUpdateStatus>(
      future: _pending,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return Scaffold(
            backgroundColor: context.uai.background,
            body: const SafeArea(child: Center(child: CircularProgressIndicator())),
          );
        }
        // Mantém o comportamento atual em erro de consulta; não inventa obrigatoriedade.
        final status = snapshot.data;
        if (status == null || !status.deveBloquear) return widget.child;
        return PopScope(
          canPop: false,
          child: Scaffold(
            backgroundColor: context.uai.background,
            body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
              final height = (constraints.maxHeight - 16).clamp(0.0, 620.0).toDouble();
              return Center(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 515),
                  child: SizedBox(height: height, child: UpdateCompactPanel(
                    requiredUpdate: true,
                    installedVersion: status.versaoLocal,
                    targetVersion: status.versaoDestino,
                    title: status.titulo,
                    summary: status.mensagem,
                    changes: _changes(status),
                    busy: _installing,
                    onUpdate: () => _install(status),
                    onOfficialSite: () => OfficialApkWebsiteService.open(context),
                    onVerify: _verify,
                  )),
                ),
              ));
            })),
          ),
        );
      },
    );
  }
}
