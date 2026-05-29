import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uai_capoeira/core/theme/app_theme.dart';

import '../services/graduacao_service.dart';

class EditarGraduacaoModal extends StatefulWidget {
  final String? graduacaoAtualId;
  final String? graduacaoNovaId;
  final String eventoId;
  final Map<String, dynamic>? aluno;

  const EditarGraduacaoModal({
    super.key,
    this.graduacaoAtualId,
    this.graduacaoNovaId,
    required this.eventoId,
    this.aluno,
  });

  @override
  State<EditarGraduacaoModal> createState() => _EditarGraduacaoModalState();
}

class _EditarGraduacaoModalState extends State<EditarGraduacaoModal> {
  final GraduacaoService _graduacaoService = GraduacaoService();

  List<Map<String, dynamic>> _graduacoes = [];
  List<Map<String, dynamic>> _todasGraduacoes = [];
  String? _graduacaoSelecionada;
  bool _isLoading = true;

  int? _nivelAtual;
  String? _tipoPublicoAluno;
  int? _idadeAluno;
  String? _graduacaoAtualTexto;

  final int _ultimoNivelInfantil = 8;

  @override
  void initState() {
    super.initState();
    _carregarGraduacoes();
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.48
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }

  Color _ensureVisible(Color color, Color background) {
    final diff = (color.computeLuminance() - background.computeLuminance()).abs();
    if (diff >= 0.26) return color;

    final bgIsDark = background.computeLuminance() < 0.45;
    final hsl = HSLColor.fromColor(color);

    return hsl
        .withLightness(bgIsDark ? 0.72 : 0.32)
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  int _calcularIdade(DateTime dataNascimento) {
    final hoje = DateTime.now();
    int idade = hoje.year - dataNascimento.year;

    if (hoje.month < dataNascimento.month ||
        (hoje.month == dataNascimento.month && hoje.day < dataNascimento.day)) {
      idade--;
    }

    return idade;
  }

  DateTime? _converterData(dynamic data) {
    if (data == null) return null;

    try {
      if (data is Timestamp) return data.toDate();

      if (data is String) {
        try {
          return DateTime.parse(data);
        } catch (_) {
          return null;
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  String _determinarCategoriaPorIdade() {
    if (widget.aluno != null && widget.aluno!['data_nascimento'] != null) {
      final dataNascimento = _converterData(widget.aluno!['data_nascimento']);

      if (dataNascimento != null) {
        final idade = _calcularIdade(dataNascimento);
        return idade < 13 ? 'INFANTIL' : 'ADULTO';
      }
    }

    return _tipoPublicoAluno ?? 'ADULTO';
  }

  bool _podeMudarParaAdulto(int nivelAtual, int idade) {
    if (nivelAtual >= _ultimoNivelInfantil) return true;
    if (idade >= 13) return true;
    return false;
  }

  Future<void> _carregarGraduacoes() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      _todasGraduacoes = await _graduacaoService.buscarTodasGraduacoes();

      if (widget.aluno != null) {
        _graduacaoAtualTexto = widget.aluno!['graduacao'];

        if (widget.aluno!['data_nascimento'] != null) {
          final dataNascimento = _converterData(widget.aluno!['data_nascimento']);

          if (dataNascimento != null) {
            _idadeAluno = _calcularIdade(dataNascimento);
          }
        }
      }

      if (widget.graduacaoAtualId != null &&
          widget.graduacaoAtualId!.isNotEmpty) {
        final graduacaoAtual = _todasGraduacoes.firstWhere(
              (g) => g['id'] == widget.graduacaoAtualId,
          orElse: () => {},
        );

        if (graduacaoAtual.isNotEmpty) {
          _nivelAtual = graduacaoAtual['nivel_graduacao'] ?? 0;
          _tipoPublicoAluno = graduacaoAtual['tipo_publico'] ?? 'ADULTO';
        }
      } else if (_graduacaoAtualTexto != null &&
          _graduacaoAtualTexto != 'SEM GRADUÇÃO') {
        if (_graduacaoAtualTexto!.contains('INFANTIL')) {
          _tipoPublicoAluno = 'INFANTIL';

          for (final g in _todasGraduacoes) {
            final nome = g['nome_graduacao']?.toString() ?? '';
            final prefixo = nome.split(' ').take(2).join(' ');

            if (prefixo.isNotEmpty && _graduacaoAtualTexto!.contains(prefixo)) {
              _nivelAtual = g['nivel_graduacao'];
              break;
            }
          }
        } else {
          _tipoPublicoAluno = 'ADULTO';
        }
      }

      if (_tipoPublicoAluno == null && _idadeAluno != null) {
        _tipoPublicoAluno = _idadeAluno! < 13 ? 'INFANTIL' : 'ADULTO';
      }

      debugPrint('🎯 Dados do aluno:');
      debugPrint('   - Nível atual: $_nivelAtual');
      debugPrint('   - Tipo: $_tipoPublicoAluno');
      debugPrint('   - Idade: $_idadeAluno');
      debugPrint('   - Graduação: $_graduacaoAtualTexto');

      final eventoDoc = await FirebaseFirestore.instance
          .collection('eventos')
          .doc(widget.eventoId)
          .get();

      final tipoEvento = eventoDoc.data()?['tipo'] ?? '';
      final isBatizado = tipoEvento.toString().toUpperCase().contains('BATIZADO');

      if (!isBatizado) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      if (_nivelAtual == null ||
          _nivelAtual == 0 ||
          _graduacaoAtualTexto == 'SEM GRADUÇÃO') {
        debugPrint('📌 Aluno SEM graduação');

        final categoria = _determinarCategoriaPorIdade();
        debugPrint('📌 Categoria determinada: $categoria');

        _graduacoes = _todasGraduacoes
            .where((g) => g['tipo_publico'] == categoria)
            .toList();

        if (_idadeAluno != null) {
          _graduacoes = _graduacoes.where((g) {
            final idadeMinima = g['idade_minima'] ?? 0;
            return _idadeAluno! >= idadeMinima;
          }).toList();
        }

        debugPrint('📚 Opções disponíveis: ${_graduacoes.length}');
      } else {
        debugPrint('📌 Aluno COM graduação');

        final graduacoesInfantis = _todasGraduacoes
            .where((g) => g['tipo_publico'] == 'INFANTIL')
            .toList()
          ..sort(
                (a, b) => (a['nivel_graduacao'] ?? 0).compareTo(
              b['nivel_graduacao'] ?? 0,
            ),
          );

        final graduacoesAdultas = _todasGraduacoes
            .where((g) => g['tipo_publico'] == 'ADULTO')
            .toList()
          ..sort(
                (a, b) => (a['nivel_graduacao'] ?? 0).compareTo(
              b['nivel_graduacao'] ?? 0,
            ),
          );

        final resultados = <Map<String, dynamic>>[];

        if (_tipoPublicoAluno == 'INFANTIL') {
          debugPrint('📌 Aluno INFANTIL');

          final proximasInfantis = graduacoesInfantis
              .where((g) => (g['nivel_graduacao'] ?? 0) > (_nivelAtual ?? 0))
              .toList();

          resultados.addAll(proximasInfantis);
          debugPrint('   • Próximas INFANTIS: ${proximasInfantis.length}');

          final podeMostrarAdultas = _podeMudarParaAdulto(
            _nivelAtual ?? 0,
            _idadeAluno ?? 0,
          );

          if (podeMostrarAdultas) {
            debugPrint('   ✅ Pode mostrar ADULTAS');
            resultados.addAll(graduacoesAdultas);
          } else {
            debugPrint('   ❌ Não pode mostrar ADULTAS');
          }
        } else {
          debugPrint('📌 Aluno ADULTO');

          final proximasAdultas = graduacoesAdultas
              .where((g) => (g['nivel_graduacao'] ?? 0) > (_nivelAtual ?? 0))
              .toList();

          resultados.addAll(proximasAdultas);
          debugPrint('   • Próximas ADULTAS: ${proximasAdultas.length}');
        }

        _graduacoes = resultados.toSet().toList();
        _graduacoes.sort((a, b) {
          if (a['tipo_publico'] != b['tipo_publico']) {
            return a['tipo_publico'] == 'INFANTIL' ? -1 : 1;
          }

          return (a['nivel_graduacao'] ?? 0).compareTo(
            b['nivel_graduacao'] ?? 0,
          );
        });
      }

      if (widget.graduacaoNovaId != null) {
        _graduacaoSelecionada = widget.graduacaoNovaId;
      }

      debugPrint('📊 TOTAL DE OPÇÕES: ${_graduacoes.length}');
    } catch (e) {
      debugPrint('❌ Erro ao carregar graduações: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getCorGraduacao(Map<String, dynamic> graduacao) {
    try {
      final raw = graduacao['hex_cor1']?.toString() ?? '';
      final cleaned = raw.replaceFirst('#', '');

      if (cleaned.length == 6) {
        return Color(int.parse('FF$cleaned', radix: 16));
      }

      if (cleaned.length == 8) {
        return Color(int.parse(cleaned, radix: 16));
      }
    } catch (_) {}

    return context.uai.textMuted;
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _tituloVazio() {
    if (_nivelAtual != null && _nivelAtual! > 0) {
      return 'Não há graduações disponíveis acima do nível $_nivelAtual';
    }

    return 'Não há graduações disponíveis para este aluno';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    final maxWidth = MediaQuery.of(context).size.width > 620
        ? 620.0
        : MediaQuery.of(context).size.width - 24;
    final maxHeight = MediaQuery.of(context).size.height * 0.86;

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
        child: Material(
          color: t.surface,
          borderRadius: BorderRadius.circular(t.cardRadius + 4),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDialogHeader(),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _buildBody(),
                ),
              ),
              _buildBottomActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDialogHeader() {
    final t = context.uai;
    final accent = _ensureVisible(t.warning, t.surface);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.surface),
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: t.border,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                  border: Border.all(color: accent.withOpacity(0.16)),
                ),
                child: Icon(
                  Icons.workspace_premium_rounded,
                  color: accent,
                  size: 27,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Editar graduação',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Escolha a nova graduação disponível para este aluno.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, color: t.textSecondary),
                tooltip: 'Fechar',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return SizedBox(
        height: 300,
        child: Center(
          child: CircularProgressIndicator(color: context.uai.primary),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_nivelAtual != null && _nivelAtual! > 0) ...[
          _buildInfoBanner(
            icon: Icons.info_rounded,
            color: context.uai.info,
            text: 'Nível atual: $_nivelAtual • Só pode evoluir',
          ),
          const SizedBox(height: 8),
        ],
        if ((_nivelAtual == null || _nivelAtual == 0) && _idadeAluno != null) ...[
          _buildInfoBanner(
            icon: Icons.cake_rounded,
            color: context.uai.success,
            text:
            'Idade: $_idadeAluno anos • Categoria: ${_determinarCategoriaPorIdade()}',
          ),
          const SizedBox(height: 8),
        ],
        if (_graduacoes.isEmpty)
          Expanded(
            child: _buildEmptyState(),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              itemCount: _graduacoes.length,
              itemBuilder: (context, index) {
                final graduacao = _graduacoes[index];
                return _buildGraduacaoTile(graduacao);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildInfoBanner({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.surface);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.card),
        borderRadius: BorderRadius.circular(t.inputRadius),
        border: Border.all(color: accent.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: accent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final t = context.uai;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 52,
              color: t.textMuted,
            ),
            const SizedBox(height: 14),
            Text(
              _tituloVazio(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraduacaoTile(Map<String, dynamic> graduacao) {
    final t = context.uai;
    final id = graduacao['id']?.toString() ?? '';
    final isSelected = _graduacaoSelecionada == id;

    final corOriginal = _getCorGraduacao(graduacao);
    final cor = _ensureVisible(corOriginal, t.card);
    final nome = graduacao['nome_graduacao']?.toString() ?? '';
    final nivel = graduacao['nivel_graduacao']?.toString() ?? '--';
    final titulo = graduacao['titulo_graduacao']?.toString() ?? '';
    final idadeMinima = graduacao['idade_minima'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: isSelected
            ? Color.alphaBlend(cor.withOpacity(0.10), t.card)
            : t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _graduacaoSelecionada = id),
          borderRadius: BorderRadius.circular(t.cardRadius),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius),
              border: Border.all(
                color: isSelected ? cor.withOpacity(0.45) : t.border,
                width: isSelected ? 1.4 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildNivelAvatar(
                  color: cor,
                  nivel: nivel,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: _buildGraduacaoInfo(
                    nome: nome,
                    nivel: nivel,
                    titulo: titulo,
                    idadeMinima: idadeMinima,
                    color: cor,
                  ),
                ),
                const SizedBox(width: 8),
                Radio<String>(
                  value: id,
                  groupValue: _graduacaoSelecionada,
                  activeColor: cor,
                  onChanged: (value) {
                    setState(() => _graduacaoSelecionada = value);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNivelAvatar({
    required Color color,
    required String nivel,
  }) {
    return Container(
      width: 43,
      height: 43,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: _readableOn(color).withOpacity(0.40),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Text(
          nivel,
          style: TextStyle(
            color: _readableOn(color),
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildGraduacaoInfo({
    required String nome,
    required String nivel,
    required String titulo,
    required dynamic idadeMinima,
    required Color color,
  }) {
    final t = context.uai;
    final idade = _asInt(idadeMinima);
    final accent = _ensureVisible(color, t.card);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          nome.isEmpty ? 'Graduação sem nome' : nome,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: t.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 13.8,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _buildMiniChip(
              label: 'Nível $nivel',
              icon: Icons.leaderboard_rounded,
              color: accent,
            ),
            if (titulo.trim().isNotEmpty)
              _buildMiniChip(
                label: titulo,
                icon: Icons.badge_rounded,
                color: context.uai.warning,
              ),
            if (idade > 0)
              _buildMiniChip(
                label: '$idade+ anos',
                icon: Icons.cake_rounded,
                color: context.uai.info,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniChip({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final t = context.uai;
    final accent = _ensureVisible(color, t.card);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withOpacity(0.08), t.cardAlt),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    final t = context.uai;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 390;

            final cancelButton = OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: t.error,
                side: BorderSide(color: t.error.withOpacity(0.28)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
              ),
              child: const Text(
                'CANCELAR',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            );

            final saveButton = ElevatedButton(
              onPressed: _graduacaoSelecionada != null
                  ? () => Navigator.pop(context, _graduacaoSelecionada)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: _readableOn(t.primary),
                disabledBackgroundColor: t.cardAlt,
                disabledForegroundColor: t.textMuted,
                padding: const EdgeInsets.symmetric(vertical: 13),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.buttonRadius),
                ),
              ),
              child: const Text('SALVAR'),
            );

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  saveButton,
                  const SizedBox(height: 8),
                  cancelButton,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: cancelButton),
                const SizedBox(width: 10),
                Expanded(child: saveButton),
              ],
            );
          },
        ),
      ),
    );
  }
}