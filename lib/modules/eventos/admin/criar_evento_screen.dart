import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:uai_capoeira/core/permissions/permissao_service.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/eventos/models/evento_model.dart';
import 'package:uai_capoeira/modules/eventos/services/evento_service.dart';

class CriarEventoScreen extends StatefulWidget {
  final EventoModel? evento;

  const CriarEventoScreen({super.key, this.evento});

  @override
  State<CriarEventoScreen> createState() => _CriarEventoScreenState();
}

class _CriarEventoScreenState extends State<CriarEventoScreen> {
  final _formKey = GlobalKey<FormState>();
  final EventoService _eventoService = EventoService();
  final PermissaoService _permissaoService = PermissaoService();

  bool _carregandoPermissoes = true;
  bool _podeCriarEvento = false;
  bool _podeEditarEvento = false;
  bool _podeFinalizarEvento = false;

  final _nomeController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _tipoController = TextEditingController();
  final _dataController = TextEditingController();
  final _horarioController = TextEditingController();
  final _localController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _organizadoresController = TextEditingController();
  final _linkFotosController = TextEditingController();
  final _linkPreviaController = TextEditingController();
  final _linkPlaylistController = TextEditingController();

  File? _bannerFile;
  String? _bannerUrl;
  bool _isUploadingBanner = false;

  double _valorInscricao = 0;
  int _maxParcelas = 1;
  int _descontoAVista = 0;
  bool _permiteParcelamento = false;
  DateTime? _dataLimitePrimeiraParcela;

  bool _temCamisa = false;
  double _valorCamisa = 0;
  bool _camisaObrigatoria = false;
  final List<String> _todosTamanhos = [
    '4A',
    '6A',
    '8A',
    '10A',
    '12A',
    '14A',
    'PP',
    'P',
    'M',
    'G',
    'GG',
    'EGG',
  ];
  List<String> _tamanhosSelecionados = [];

  bool _temCertificado = false;
  bool _mostrarNoPortfolioWeb = false;

  String _status = 'andamento';
  bool _isLoading = false;

  final List<String> _tiposEvento = [
    'BATIZADO & TROCA DE CORDAS',
    'ALUNO DESTAQUE',
    'EVENTO EM OUTRA CIDADE',
    'CONFRATERNIZAÇÃO',
    'RODAS',
    'AULÃO',
    'CAMPEONATO',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.evento != null) {
      _preencherFormulario();
    }
    _verificarPermissoes();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _tipoController.dispose();
    _dataController.dispose();
    _horarioController.dispose();
    _localController.dispose();
    _cidadeController.dispose();
    _organizadoresController.dispose();
    _linkFotosController.dispose();
    _linkPreviaController.dispose();
    _linkPlaylistController.dispose();
    super.dispose();
  }

  bool get _modoEdicao => widget.evento != null;

  bool get _podeSalvarEvento {
    if (_modoEdicao) return _podeEditarEvento;
    return _podeCriarEvento;
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff =
    (color.computeLuminance() - background.computeLuminance()).abs();

    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Future<void> _verificarPermissoes() async {
    if (mounted) {
      setState(() => _carregandoPermissoes = true);
    }

    try {
      final permissoes = await Future.wait<bool>([
        _permissaoService.temQualquerPermissao(['pode_criar_evento']),
        _permissaoService.temQualquerPermissao(['pode_editar_evento']),
        _permissaoService.temQualquerPermissao(['pode_finalizar_evento']),
      ]);

      if (!mounted) return;

      setState(() {
        _podeCriarEvento = permissoes[0];
        _podeEditarEvento = permissoes[1];
        _podeFinalizarEvento = permissoes[2];
        _carregandoPermissoes = false;
      });
    } catch (e) {
      debugPrint('Erro ao verificar permissões de criação/edição de evento: $e');
      if (!mounted) return;
      setState(() => _carregandoPermissoes = false);
    }
  }

  void _showSnack(String message, {required _SnackType type}) {
    final t = context.uai;

    final color = switch (type) {
      _SnackType.success => t.success,
      _SnackType.error => t.error,
      _SnackType.warning => t.warning,
      _SnackType.info => t.info,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _mostrarSemPermissao([
    String mensagem = 'Você não tem permissão para criar ou editar eventos.',
  ]) {
    if (!mounted) return;
    _showSnack(mensagem, type: _SnackType.error);
  }

  void _preencherFormulario() {
    final e = widget.evento!;

    _nomeController.text = e.nome;
    _descricaoController.text = e.descricao;
    _tipoController.text = e.tipo;
    _dataController.text = e.dataFormatada;
    _horarioController.text = e.horario;
    _localController.text = e.local;
    _cidadeController.text = e.cidade;
    _organizadoresController.text = e.organizadores.join(', ');
    _bannerUrl = e.linkBanner;
    _linkFotosController.text = e.linkFotosVideos ?? '';
    _linkPreviaController.text = e.previaVideo ?? '';
    _linkPlaylistController.text = e.linkPlaylist ?? '';

    _valorInscricao = e.valorInscricao;
    _permiteParcelamento = e.permiteParcelamento;
    _maxParcelas = e.maxParcelas;
    _descontoAVista = e.descontoAVista;
    _dataLimitePrimeiraParcela = e.dataLimitePrimeiraParcela;

    _temCamisa = e.temCamisa;
    _valorCamisa = e.valorCamisa ?? 0;
    _tamanhosSelecionados = List.from(e.tamanhosDisponiveis);
    _camisaObrigatoria = e.camisaObrigatoria;

    _temCertificado = e.temCertificado;
    _mostrarNoPortfolioWeb = e.mostrarNoPortfolioWeb;
    _status = e.status;
  }

  Future<void> _selecionarData() async {
    final DateTime? data = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2030),
    );

    if (data != null) {
      setState(() {
        _dataController.text = '${data.day.toString().padLeft(2, '0')}/'
            '${data.month.toString().padLeft(2, '0')}/'
            '${data.year}';
      });
    }
  }

  Future<void> _selecionarDataLimite() async {
    final DateTime? data = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );

    if (data != null) {
      setState(() => _dataLimitePrimeiraParcela = data);
    }
  }

  Future<void> _selecionarImagem() async {
    if (!_podeSalvarEvento) {
      _mostrarSemPermissao('Você não tem permissão para alterar o banner.');
      return;
    }

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _bannerFile = File(image.path);
          _bannerUrl = null;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Erro ao selecionar imagem: $e', type: _SnackType.error);
      }
    }
  }

  Future<void> _tirarFoto() async {
    if (!_podeSalvarEvento) {
      _mostrarSemPermissao('Você não tem permissão para alterar o banner.');
      return;
    }

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _bannerFile = File(image.path);
          _bannerUrl = null;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Erro ao tirar foto: $e', type: _SnackType.error);
      }
    }
  }

  Future<String?> _uploadBanner(File imageFile, String eventoId) async {
    try {
      setState(() => _isUploadingBanner = true);

      final fileName = '${eventoId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('eventos')
          .child('banners')
          .child(fileName);

      await storageRef.putFile(
        imageFile,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'uploaded_at': DateTime.now().toIso8601String(),
            'evento_id': eventoId,
          },
        ),
      );

      final downloadUrl = await storageRef.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('Erro no upload: $e');
      return null;
    } finally {
      if (mounted) setState(() => _isUploadingBanner = false);
    }
  }

  void _removerBanner() {
    if (!_podeSalvarEvento) {
      _mostrarSemPermissao('Você não tem permissão para remover o banner.');
      return;
    }

    if (widget.evento?.linkBanner != null && _bannerUrl != null) {
      _showConfirmDialog(
        title: 'Remover Banner',
        message: 'Deseja remover o banner permanentemente?',
        icon: Icons.delete_outline_rounded,
        color: context.uai.error,
        confirmLabel: 'REMOVER',
        onConfirm: () {
          setState(() {
            _bannerFile = null;
            _bannerUrl = null;
          });
          _showSnack('Banner será removido ao salvar', type: _SnackType.warning);
        },
      );
    } else {
      setState(() {
        _bannerFile = null;
        _bannerUrl = null;
      });
    }
  }

  void _mostrarOpcoesImagem() {
    if (!_podeSalvarEvento) {
      _mostrarSemPermissao('Você não tem permissão para alterar o banner.');
      return;
    }

    final t = context.uai;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 4),
              boxShadow: t.cardShadow,
              border: Border.all(color: t.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                _dialogHandle(),
                const SizedBox(height: 8),
                _bottomOption(
                  icon: Icons.photo_library_rounded,
                  color: t.info,
                  title: 'Escolher da Galeria',
                  onTap: () {
                    Navigator.pop(context);
                    _selecionarImagem();
                  },
                ),
                _bottomOption(
                  icon: Icons.camera_alt_rounded,
                  color: t.success,
                  title: 'Tirar Foto',
                  onTap: () {
                    Navigator.pop(context);
                    _tirarFoto();
                  },
                ),
                if (_bannerFile != null || _bannerUrl != null)
                  _bottomOption(
                    icon: Icons.delete_rounded,
                    color: t.error,
                    title: 'Remover Banner',
                    onTap: () {
                      Navigator.pop(context);
                      _removerBanner();
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bottomOption({
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selecionarTamanhos() async {
    if (!_podeSalvarEvento) {
      _mostrarSemPermissao('Você não tem permissão para alterar tamanhos.');
      return;
    }

    List<String> tamanhosTemp = List.from(_tamanhosSelecionados);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final t = context.uai;
        final primary = _ensureVisible(t.primary, t.surface);

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              insetPadding: const EdgeInsets.all(18),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Material(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(t.cardRadius + 2),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(t.cardRadius + 2),
                      border: Border.all(color: t.border),
                      boxShadow: t.cardShadow,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 8, 10),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: primary.withOpacity(0.12),
                                  borderRadius:
                                  BorderRadius.circular(t.buttonRadius),
                                ),
                                child: Icon(Icons.checkroom_rounded, color: primary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Tamanhos Disponíveis',
                                  style: TextStyle(
                                    color: t.textPrimary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                icon: Icon(Icons.close_rounded, color: t.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            itemCount: _todosTamanhos.length,
                            itemBuilder: (context, index) {
                              final tamanho = _todosTamanhos[index];
                              final isSelected = tamanhosTemp.contains(tamanho);

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Material(
                                  color: isSelected
                                      ? Color.alphaBlend(
                                    primary.withOpacity(0.10),
                                    t.cardAlt,
                                  )
                                      : t.cardAlt,
                                  borderRadius: BorderRadius.circular(t.inputRadius),
                                  clipBehavior: Clip.antiAlias,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius:
                                      BorderRadius.circular(t.inputRadius),
                                      border: Border.all(
                                        color: isSelected
                                            ? primary.withOpacity(0.28)
                                            : t.border,
                                      ),
                                    ),
                                    child: CheckboxListTile(
                                      value: isSelected,
                                      activeColor: primary,
                                      title: Text(
                                        tamanho,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: isSelected
                                              ? primary
                                              : t.textPrimary,
                                        ),
                                      ),
                                      onChanged: (selected) {
                                        setStateDialog(() {
                                          if (selected == true) {
                                            tamanhosTemp.add(tamanho);
                                          } else {
                                            tamanhosTemp.remove(tamanho);
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: t.card,
                            border: Border(top: BorderSide(color: t.border)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: t.textPrimary,
                                    side: BorderSide(color: t.border),
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                      BorderRadius.circular(t.buttonRadius),
                                    ),
                                  ),
                                  child: const Text('CANCELAR'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _tamanhosSelecionados = tamanhosTemp;
                                    });
                                    Navigator.pop(dialogContext);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: t.primary,
                                    foregroundColor: _readableOn(t.primary),
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                      BorderRadius.circular(t.buttonRadius),
                                    ),
                                  ),
                                  child: const Text(
                                    'OK',
                                    style: TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showConfirmDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
    required String confirmLabel,
    required VoidCallback onConfirm,
  }) async {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Material(
              color: t.surface,
              borderRadius: BorderRadius.circular(t.cardRadius + 2),
              clipBehavior: Clip.antiAlias,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(t.cardRadius + 2),
                  border: Border.all(color: t.border),
                  boxShadow: t.cardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(t.buttonRadius),
                          ),
                          child: Icon(icon, color: accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      message,
                      style: TextStyle(
                        color: t.textSecondary,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: t.textPrimary,
                              side: BorderSide(color: t.border),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(t.buttonRadius),
                              ),
                            ),
                            child: const Text('CANCELAR'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(dialogContext);
                              onConfirm();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: color,
                              foregroundColor: _readableOn(color),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(t.buttonRadius),
                              ),
                            ),
                            child: Text(
                              confirmLabel,
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPermissaoEventoCard() {
    final t = context.uai;

    if (_carregandoPermissoes) {
      return _sectionCard(
        icon: Icons.security_rounded,
        title: 'Permissões',
        subtitle: 'Conferindo permissões do evento...',
        color: t.info,
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: t.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Conferindo permissões do evento...',
                style: TextStyle(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final liberado = _podeSalvarEvento;
    final color = liberado ? t.success : t.warning;

    return _sectionCard(
      icon: liberado ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
      title: 'Permissões',
      subtitle: liberado
          ? (_modoEdicao
          ? 'Permissão liberada para editar este evento.'
          : 'Permissão liberada para criar evento.')
          : (_modoEdicao
          ? 'Você pode visualizar, mas não tem permissão para editar este evento.'
          : 'Você não tem permissão para criar eventos.'),
      color: color,
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _verificarPermissoes,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Recarregar'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _ensureVisible(t.primary, t.card),
            side: BorderSide(color: t.border),
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(t.buttonRadius),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSemAcessoEvento() {
    final t = context.uai;
    final warning = _ensureVisible(t.warning, t.card);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Material(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            clipBehavior: Clip.antiAlias,
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(t.cardRadius),
                border: Border.all(color: warning.withOpacity(0.18)),
                boxShadow: t.softShadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 64, color: warning),
                  const SizedBox(height: 12),
                  Text(
                    _modoEdicao ? 'Edição bloqueada' : 'Criação bloqueada',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _modoEdicao
                        ? 'Peça para o administrador liberar “Editar evento” nas suas permissões.'
                        : 'Peça para o administrador liberar “Criar evento” nas suas permissões.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: t.textSecondary,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _verificarPermissoes,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Recarregar permissões'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ensureVisible(t.primary, t.card),
                      side: BorderSide(color: t.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(t.buttonRadius),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleCard({
    required bool value,
    required IconData icon,
    required String title,
    required String activeText,
    required String inactiveText,
    required Color activeColor,
    required ValueChanged<bool> onChanged,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(value ? activeColor : t.textSecondary, t.card);

    return Material(
      color: value
          ? Color.alphaBlend(accent.withOpacity(0.08), t.card)
          : t.card,
      borderRadius: BorderRadius.circular(t.inputRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.inputRadius),
          border: Border.all(
            color: value ? accent.withOpacity(0.26) : t.border,
            width: value ? 1.4 : 1,
          ),
        ),
        child: SwitchListTile(
          value: value,
          activeColor: accent,
          onChanged: onChanged,
          secondary: Icon(icon, color: accent),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: value ? accent : t.textPrimary,
            ),
          ),
          subtitle: Text(
            value ? activeText : inactiveText,
            style: TextStyle(
              fontSize: 12,
              color: value ? accent : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCertificadoSimples() {
    return _buildToggleCard(
      value: _temCertificado,
      icon: Icons.card_membership_rounded,
      title: 'Certificados',
      activeText: 'Este evento terá certificados',
      inactiveText: 'Este evento NÃO terá certificados',
      activeColor: context.uai.success,
      onChanged: (value) {
        setState(() => _temCertificado = value);
      },
    );
  }

  Widget _buildPortfolioWebSimples() {
    return _buildToggleCard(
      value: _mostrarNoPortfolioWeb,
      icon: Icons.web_rounded,
      title: 'Mostrar no Portfólio Web',
      activeText: 'Este evento aparecerá no site',
      inactiveText: 'Este evento NÃO aparecerá no site',
      activeColor: context.uai.info,
      onChanged: (value) {
        setState(() => _mostrarNoPortfolioWeb = value);
      },
    );
  }

  Future<void> _salvar() async {
    if (!_podeSalvarEvento) {
      _mostrarSemPermissao(
        _modoEdicao
            ? 'Você não tem permissão para editar eventos.'
            : 'Você não tem permissão para criar eventos.',
      );
      return;
    }

    if (!_podeFinalizarEvento && _status == 'finalizado') {
      _mostrarSemPermissao('Você não tem permissão para finalizar eventos.');
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final partesData = _dataController.text.split('/');
      final data = DateTime(
        int.parse(partesData[2]),
        int.parse(partesData[1]),
        int.parse(partesData[0]),
      );

      final organizadores = _organizadoresController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final tipo = _tipoController.text;
      final alteraGraduacao =
          tipo.contains('BATIZADO') || tipo.contains('CAMPEONATO');
      final geraCertificado = tipo.contains('BATIZADO') ||
          tipo.contains('CAMPEONATO') ||
          tipo.contains('AULÃO') ||
          _temCertificado;

      final bool bannerFoiRemovido =
          widget.evento?.linkBanner != null && _bannerUrl == null && _bannerFile == null;

      if (bannerFoiRemovido && widget.evento?.linkBanner != null) {
        try {
          final oldBannerRef =
          FirebaseStorage.instance.refFromURL(widget.evento!.linkBanner!);
          await oldBannerRef.delete();
          debugPrint('Banner antigo removido do Storage');
        } catch (e) {
          debugPrint('Erro ao remover banner antigo: $e');
        }
      }

      String? novaBannerUrl = _bannerUrl;

      if (_bannerFile != null) {
        if (widget.evento?.linkBanner != null &&
            widget.evento!.linkBanner != _bannerUrl) {
          try {
            final oldBannerRef =
            FirebaseStorage.instance.refFromURL(widget.evento!.linkBanner!);
            await oldBannerRef.delete();
            debugPrint('Banner antigo removido antes do upload');
          } catch (e) {
            debugPrint('Erro ao remover banner antigo: $e');
          }
        }

        final tempEventoId =
            widget.evento?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
        novaBannerUrl = await _uploadBanner(_bannerFile!, tempEventoId);

        if (novaBannerUrl == null) {
          throw Exception('Erro ao fazer upload do banner');
        }
      } else if (bannerFoiRemovido) {
        novaBannerUrl = null;
      }

      final evento = EventoModel(
        id: widget.evento?.id,
        nome: _nomeController.text.trim(),
        descricao: _descricaoController.text.trim(),
        tipo: tipo,
        data: data,
        horario: _horarioController.text.trim(),
        local: _localController.text.trim(),
        cidade: _cidadeController.text.trim(),
        organizadores: organizadores,
        status: _status,
        valorInscricao: _valorInscricao,
        permiteParcelamento: _permiteParcelamento,
        maxParcelas: _maxParcelas,
        descontoAVista: _descontoAVista,
        dataLimitePrimeiraParcela: _dataLimitePrimeiraParcela,
        temCamisa: _temCamisa,
        valorCamisa: _temCamisa ? _valorCamisa : null,
        tamanhosDisponiveis: _temCamisa ? _tamanhosSelecionados : [],
        camisaObrigatoria: _temCamisa ? _camisaObrigatoria : false,
        alteraGraduacao: alteraGraduacao,
        geraCertificado: geraCertificado,
        tipoPublico: 'todos',
        linkBanner: novaBannerUrl,
        linkFotosVideos: _linkFotosController.text.isNotEmpty
            ? _linkFotosController.text.trim()
            : null,
        previaVideo: _linkPreviaController.text.isNotEmpty
            ? _linkPreviaController.text.trim()
            : null,
        linkPlaylist: _linkPlaylistController.text.isNotEmpty
            ? _linkPlaylistController.text.trim()
            : null,
        temCertificado: _temCertificado,
        configuracoesCertificado: null,
        modeloCertificadoId: null,
        modeloCertificadoPath: null,
        criadoEm: null,
        atualizadoEm: null,
        mostrarNoPortfolioWeb: _mostrarNoPortfolioWeb,
      );

      final eventoId = await _eventoService.salvarEvento(evento);

      if (eventoId == null) {
        throw Exception('Erro ao salvar evento: ID não gerado');
      }

      if (_bannerFile != null && novaBannerUrl != null && widget.evento?.id == null) {
        try {
          final storageRef = FirebaseStorage.instance.refFromURL(novaBannerUrl);
          final newPath =
              'eventos/banners/$eventoId-${DateTime.now().millisecondsSinceEpoch}.jpg';
          final newRef = FirebaseStorage.instance.ref().child(newPath);

          await newRef.putFile(_bannerFile!);
          final finalUrl = await newRef.getDownloadURL();

          await _eventoService.atualizarBanner(eventoId, finalUrl);
          await storageRef.delete();
        } catch (e) {
          debugPrint('Erro ao renomear banner: $e');
        }
      }

      if (mounted) {
        _showSnack(
          widget.evento == null
              ? 'Evento criado com sucesso!'
              : 'Evento atualizado com sucesso!',
          type: _SnackType.success,
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Erro: $e', type: _SnackType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    IconData? icon,
    String? hint,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: t.textSecondary),
      hintStyle: TextStyle(color: t.textMuted),
      prefixIcon: icon == null ? null : Icon(icon, color: primary),
      filled: true,
      fillColor: t.cardAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.inputRadius),
        borderSide: BorderSide(color: t.error, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _formField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obrigatorio = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? hint,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      style: TextStyle(color: context.uai.textPrimary),
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: _inputDecoration(
        label: label + (obrigatorio ? ' *' : ''),
        icon: icon,
        hint: hint,
      ).copyWith(alignLabelWithHint: maxLines > 1),
      validator: validator ??
          (obrigatorio
              ? (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Campo obrigatório';
            }
            return null;
          }
              : null),
    );
  }

  Widget _numberField({
    required String label,
    required IconData icon,
    required num initialValue,
    required ValueChanged<String> onChanged,
    bool obrigatorio = false,
    String? suffixText,
  }) {
    final t = context.uai;

    return TextFormField(
      initialValue: initialValue.toString(),
      keyboardType: TextInputType.number,
      style: TextStyle(color: t.textPrimary),
      decoration: _inputDecoration(label: label + (obrigatorio ? ' *' : ''), icon: icon)
          .copyWith(suffixText: suffixText),
      onChanged: onChanged,
      validator: obrigatorio
          ? (value) {
        if (value == null || value.isEmpty) return 'Campo obrigatório';
        if (double.tryParse(value) == null) return 'Valor inválido';
        return null;
      }
          : null,
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Widget child,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: accent.withOpacity(0.14)),
          boxShadow: t.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              icon: icon,
              title: title,
              subtitle: subtitle,
              color: accent,
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final t = context.uai;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(t.buttonRadius),
            border: Border.all(color: color.withOpacity(0.16)),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 11.8,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHero() {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

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
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: onPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: onPrimary.withOpacity(0.16)),
            ),
            child: Icon(
              _modoEdicao ? Icons.edit_calendar_rounded : Icons.event_available_rounded,
              color: onPrimary,
              size: 33,
            ),
          );

          final text = Column(
            crossAxisAlignment:
            narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                _modoEdicao ? 'Editar Evento' : 'Criar Evento',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary,
                  fontSize: narrow ? 22 : 27,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Configure dados, banner, taxas, camisa, certificados e portfólio web.',
                textAlign: narrow ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: onPrimary.withOpacity(0.82),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment:
                narrow ? WrapAlignment.center : WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _heroChip(Icons.event_rounded, _status.toUpperCase()),
                  if (_temCamisa) _heroChip(Icons.checkroom_rounded, 'Camisa'),
                  if (_temCertificado)
                    _heroChip(Icons.card_membership_rounded, 'Certificado'),
                  if (_mostrarNoPortfolioWeb)
                    _heroChip(Icons.public_rounded, 'Site'),
                ],
              ),
            ],
          );

          if (narrow) {
            return Column(
              children: [
                iconBox,
                const SizedBox(height: 14),
                text,
              ],
            );
          }

          return Row(
            children: [
              iconBox,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }

  Widget _heroChip(IconData icon, String label) {
    final t = context.uai;
    final onPrimary = _readableOn(t.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: onPrimary.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onPrimary, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: onPrimary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBannerPreview() {
    final t = context.uai;

    return Material(
      color: t.cardAlt,
      borderRadius: BorderRadius.circular(t.inputRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _mostrarOpcoesImagem,
        child: Container(
          height: 158,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.inputRadius),
            border: Border.all(color: t.border),
          ),
          child: _bannerFile != null
              ? Image.file(
            _bannerFile!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => _bannerFallback(
              icon: Icons.broken_image_rounded,
              text: 'Erro ao carregar imagem',
            ),
          )
              : _bannerUrl != null
              ? Image.network(
            _bannerUrl!,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  color: t.primary,
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                      progress.expectedTotalBytes!
                      : null,
                ),
              );
            },
            errorBuilder: (context, error, stack) => _bannerFallback(
              icon: Icons.broken_image_rounded,
              text: 'Erro ao carregar imagem',
            ),
          )
              : _bannerFallback(
            icon: Icons.add_photo_alternate_rounded,
            text: 'Clique para adicionar um banner',
          ),
        ),
      ),
    );
  }

  Widget _bannerFallback({
    required IconData icon,
    required String text,
  }) {
    final t = context.uai;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 50, color: t.textMuted),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(color: t.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildBannerActions() {
    final hasBanner = _bannerFile != null || _bannerUrl != null;
    final t = context.uai;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 430;

        final alterar = OutlinedButton.icon(
          onPressed: _mostrarOpcoesImagem,
          icon: Icon(hasBanner ? Icons.edit_rounded : Icons.add_rounded),
          label: Text(hasBanner ? 'Alterar' : 'Adicionar Banner'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _ensureVisible(t.info, t.card),
            side: BorderSide(color: t.border),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(t.buttonRadius),
            ),
          ),
        );

        final remover = OutlinedButton.icon(
          onPressed: _removerBanner,
          icon: const Icon(Icons.delete_rounded),
          label: const Text('Remover'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _ensureVisible(t.error, t.card),
            side: BorderSide(color: t.border),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(t.buttonRadius),
            ),
          ),
        );

        if (!hasBanner) {
          return SizedBox(width: double.infinity, child: alterar);
        }

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              alterar,
              const SizedBox(height: 10),
              remover,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: alterar),
            const SizedBox(width: 12),
            Expanded(child: remover),
          ],
        );
      },
    );
  }

  Widget _buildDateField({
    required String label,
    required String emptyText,
    required String value,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    final t = context.uai;
    final primary = _ensureVisible(t.primary, t.cardAlt);

    return Material(
      color: enabled ? t.cardAlt : t.card,
      borderRadius: BorderRadius.circular(t.inputRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.inputRadius),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today_rounded, color: primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value.isEmpty ? emptyText : value,
                  style: TextStyle(
                    color: value.isEmpty ? t.textSecondary : t.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: t.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoBox({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.cardAlt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.09), t.cardAlt),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dialogHandle() {
    final t = context.uai;

    return Center(
      child: Container(
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: t.border,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Text(
          widget.evento == null ? 'Criar Evento' : 'Editar Evento',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
      ),
      body: _carregandoPermissoes
          ? Center(child: CircularProgressIndicator(color: t.primary))
          : (!_podeSalvarEvento)
          ? _buildSemAcessoEvento()
          : _isLoading
          ? Center(child: CircularProgressIndicator(color: t.primary))
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 112),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHero(),
                    const SizedBox(height: 14),
                    _buildPermissaoEventoCard(),
                    const SizedBox(height: 14),
                    _sectionCard(
                      icon: Icons.event_rounded,
                      title: 'Dados Básicos',
                      subtitle:
                      'Nome, descrição, tipo, data, local e organizadores.',
                      color: t.primary,
                      child: Column(
                        children: [
                          _formField(
                            controller: _nomeController,
                            label: 'Nome do Evento',
                            icon: Icons.event_rounded,
                            obrigatorio: true,
                          ),
                          const SizedBox(height: 12),
                          _formField(
                            controller: _descricaoController,
                            label: 'Descrição do Evento',
                            icon: Icons.description_rounded,
                            hint: 'Descreva os detalhes do evento...',
                            maxLines: 3,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _tipoController.text.isNotEmpty
                                ? _tipoController.text
                                : null,
                            isExpanded: true,
                            dropdownColor: t.surface,
                            style: TextStyle(color: t.textPrimary),
                            decoration: _inputDecoration(
                              label: 'Tipo do Evento *',
                              icon: Icons.category_rounded,
                            ),
                            items: _tiposEvento.map((tipo) {
                              return DropdownMenuItem<String>(
                                value: tipo,
                                child: Text(
                                  tipo,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: t.textPrimary,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _tipoController.text = value ?? '';
                              });
                            },
                            validator: (value) {
                              return value == null
                                  ? 'Campo obrigatório'
                                  : null;
                            },
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow =
                                  constraints.maxWidth < 560;

                              final data = _buildDateField(
                                label: 'Data *',
                                emptyText: 'Selecione a data',
                                value: _dataController.text,
                                onTap: _selecionarData,
                              );

                              final horario = _formField(
                                controller: _horarioController,
                                label: 'Horário',
                                icon: Icons.access_time_rounded,
                                hint: 'HH:MM',
                                obrigatorio: true,
                              );

                              if (narrow) {
                                return Column(
                                  children: [
                                    data,
                                    const SizedBox(height: 12),
                                    horario,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: data),
                                  const SizedBox(width: 12),
                                  Expanded(child: horario),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final narrow =
                                  constraints.maxWidth < 560;

                              final local = _formField(
                                controller: _localController,
                                label: 'Local',
                                icon: Icons.location_on_rounded,
                                obrigatorio: true,
                              );

                              final cidade = _formField(
                                controller: _cidadeController,
                                label: 'Cidade',
                                icon: Icons.location_city_rounded,
                                obrigatorio: true,
                              );

                              if (narrow) {
                                return Column(
                                  children: [
                                    local,
                                    const SizedBox(height: 12),
                                    cidade,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: local),
                                  const SizedBox(width: 12),
                                  Expanded(child: cidade),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _formField(
                            controller: _organizadoresController,
                            label:
                            'Organizadores separados por vírgula',
                            icon: Icons.people_rounded,
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _sectionCard(
                      icon: Icons.image_rounded,
                      title: 'Banner do Evento',
                      subtitle:
                      'Adicione, troque ou remova a imagem do evento.',
                      color: t.info,
                      child: Column(
                        children: [
                          _buildBannerPreview(),
                          if (_isUploadingBanner) ...[
                            const SizedBox(height: 12),
                            LinearProgressIndicator(color: t.primary),
                            const SizedBox(height: 8),
                            Text(
                              'Enviando banner...',
                              style: TextStyle(
                                color: t.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _buildBannerActions(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _sectionCard(
                      icon: Icons.payments_rounded,
                      title: 'Configurações de Taxa',
                      subtitle:
                      'Valor, parcelamento e desconto à vista.',
                      color: t.success,
                      child: Column(
                        children: [
                          _numberField(
                            label: 'Valor da inscrição (R\$)',
                            icon: Icons.attach_money_rounded,
                            initialValue: _valorInscricao,
                            obrigatorio: true,
                            onChanged: (value) {
                              _valorInscricao =
                                  double.tryParse(value) ?? 0;
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildToggleCard(
                            value: _permiteParcelamento,
                            icon: Icons.receipt_long_rounded,
                            title: 'Permite parcelamento?',
                            activeText:
                            'O evento permite parcelamento.',
                            inactiveText:
                            'O evento não permite parcelamento.',
                            activeColor: t.success,
                            onChanged: (value) {
                              setState(() {
                                _permiteParcelamento = value;
                              });
                            },
                          ),
                          if (_permiteParcelamento) ...[
                            const SizedBox(height: 8),
                            _numberField(
                              label: 'Máximo de parcelas',
                              icon: Icons.format_list_numbered_rounded,
                              initialValue: _maxParcelas,
                              onChanged: (value) {
                                _maxParcelas =
                                    int.tryParse(value) ?? 1;
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                          _numberField(
                            label: 'Desconto à vista',
                            icon: Icons.percent_rounded,
                            suffixText: '%',
                            initialValue: _descontoAVista,
                            onChanged: (value) {
                              _descontoAVista =
                                  int.tryParse(value) ?? 0;
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildDateField(
                            label: 'Data limite 1ª parcela',
                            emptyText: 'Não definido',
                            value: _dataLimitePrimeiraParcela == null
                                ? ''
                                : '${_dataLimitePrimeiraParcela!.day}/${_dataLimitePrimeiraParcela!.month}/${_dataLimitePrimeiraParcela!.year}',
                            enabled: _permiteParcelamento,
                            onTap: _selecionarDataLimite,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _sectionCard(
                      icon: Icons.checkroom_rounded,
                      title: 'Configurações de Camisa',
                      subtitle:
                      'Defina se o evento terá camisa, valor e tamanhos.',
                      color: t.warning,
                      child: Column(
                        children: [
                          _buildToggleCard(
                            value: _temCamisa,
                            icon: Icons.checkroom_rounded,
                            title: 'Evento terá camisa?',
                            activeText:
                            'Este evento terá camisa disponível.',
                            inactiveText:
                            'Este evento não terá camisa.',
                            activeColor: t.warning,
                            onChanged: (value) {
                              setState(() {
                                _temCamisa = value;
                                if (!value) {
                                  _tamanhosSelecionados = [];
                                  _camisaObrigatoria = false;
                                  _valorCamisa = 0;
                                }
                              });
                            },
                          ),
                          if (_temCamisa) ...[
                            const SizedBox(height: 12),
                            _numberField(
                              label: 'Valor da camisa (R\$)',
                              icon: Icons.attach_money_rounded,
                              initialValue: _valorCamisa,
                              onChanged: (value) {
                                _valorCamisa =
                                    double.tryParse(value) ?? 0;
                              },
                            ),
                            const SizedBox(height: 12),
                            Material(
                              color: t.cardAlt,
                              borderRadius:
                              BorderRadius.circular(t.inputRadius),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: _selecionarTamanhos,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius:
                                    BorderRadius.circular(
                                      t.inputRadius,
                                    ),
                                    border: Border.all(
                                      color: t.border,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.checkroom_rounded,
                                        color: _ensureVisible(
                                          t.primary,
                                          t.cardAlt,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _tamanhosSelecionados.isEmpty
                                              ? 'Nenhum tamanho selecionado'
                                              : _tamanhosSelecionados
                                              .join(', '),
                                          style: TextStyle(
                                            color:
                                            _tamanhosSelecionados
                                                .isEmpty
                                                ? t.textSecondary
                                                : t.textPrimary,
                                            fontWeight:
                                            FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: t.textSecondary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildToggleCard(
                              value: _camisaObrigatoria,
                              icon: Icons.priority_high_rounded,
                              title: 'Camisa obrigatória?',
                              activeText:
                              'A camisa será obrigatória neste evento.',
                              inactiveText:
                              'A camisa será opcional neste evento.',
                              activeColor: t.error,
                              onChanged: (value) {
                                setState(() {
                                  _camisaObrigatoria = value;
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _sectionCard(
                      icon: Icons.card_membership_rounded,
                      title: 'Certificados',
                      subtitle:
                      'Defina se este evento terá certificados.',
                      color: t.success,
                      child: Column(
                        children: [
                          _buildCertificadoSimples(),
                          if (_temCertificado) ...[
                            const SizedBox(height: 10),
                            _infoBox(
                              icon: Icons.info_rounded,
                              color: t.success,
                              text:
                              'Os certificados serão gerados com base nas graduações dos alunos.',
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _sectionCard(
                      icon: Icons.public_rounded,
                      title: 'Portfólio Web',
                      subtitle:
                      'Controle se este evento será exibido no site institucional.',
                      color: t.info,
                      child: Column(
                        children: [
                          _buildPortfolioWebSimples(),
                          if (_mostrarNoPortfolioWeb) ...[
                            const SizedBox(height: 10),
                            _infoBox(
                              icon: Icons.language_rounded,
                              color: t.info,
                              text:
                              'Este evento aparecerá na página de portfólio do site.',
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _sectionCard(
                      icon: Icons.link_rounded,
                      title: 'Links',
                      subtitle:
                      'Fotos, vídeos, prévia e playlist do evento.',
                      color: t.associacao,
                      child: Column(
                        children: [
                          _formField(
                            controller: _linkFotosController,
                            label: 'Link de Fotos/Vídeos',
                            icon: Icons.photo_library_rounded,
                            keyboardType: TextInputType.url,
                          ),
                          const SizedBox(height: 12),
                          _formField(
                            controller: _linkPreviaController,
                            label: 'Link da Prévia',
                            icon: Icons.play_circle_rounded,
                            keyboardType: TextInputType.url,
                          ),
                          const SizedBox(height: 12),
                          _formField(
                            controller: _linkPlaylistController,
                            label: 'Link da Playlist',
                            icon: Icons.playlist_play_rounded,
                            keyboardType: TextInputType.url,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: (!_podeSalvarEvento || _carregandoPermissoes)
          ? null
          : SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border(top: BorderSide(color: t.border)),
            boxShadow: t.softShadow,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: t.textPrimary,
                    side: BorderSide(color: t.border),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(t.buttonRadius),
                    ),
                  ),
                  child: const Text(
                    'CANCELAR',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                  (_isLoading || _isUploadingBanner || !_podeSalvarEvento)
                      ? null
                      : _salvar,
                  icon: _isLoading || _isUploadingBanner
                      ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _readableOn(t.primary),
                    ),
                  )
                      : const Icon(Icons.save_rounded),
                  label: Text(
                    widget.evento == null ? 'CRIAR EVENTO' : 'ATUALIZAR',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.primary,
                    foregroundColor: _readableOn(t.primary),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(t.buttonRadius),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SnackType {
  success,
  error,
  warning,
  info,
}
