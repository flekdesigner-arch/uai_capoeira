import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:uai_capoeira/core/theme/app_theme.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/gabarito_estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/models/pergunta_estudo_model.dart';
import 'package:uai_capoeira/modules/estudos_fundamentos/repositories/gabaritos_estudos_repository.dart';

class GerenciarGabaritoPerguntaScreen extends StatefulWidget {
  const GerenciarGabaritoPerguntaScreen({super.key, required this.pergunta});

  final PerguntaEstudoModel pergunta;

  @override
  State<GerenciarGabaritoPerguntaScreen> createState() =>
      _GerenciarGabaritoPerguntaScreenState();
}

class _GerenciarGabaritoPerguntaScreenState
    extends State<GerenciarGabaritoPerguntaScreen> {
  final GabaritosEstudosRepository _repository = GabaritosEstudosRepository();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _respostaTexto = TextEditingController();
  final TextEditingController _justificativa = TextEditingController();
  final TextEditingController _peso = TextEditingController(text: '1');

  GabaritoEstudoModel? _gabarito;
  String? _alternativaCorretaId;
  bool _ativo = true;
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _peso.text = widget.pergunta.peso > 0
        ? widget.pergunta.peso.toString()
        : '1';
    _carregar();
  }

  @override
  void dispose() {
    _respostaTexto.dispose();
    _justificativa.dispose();
    _peso.dispose();
    super.dispose();
  }

  bool get _usaAlternativas =>
      widget.pergunta.tipo == PerguntaEstudoTipo.multiplaEscolha ||
      widget.pergunta.tipo == PerguntaEstudoTipo.verdadeiroFalso;

  Future<void> _carregar() async {
    final erro = _validarPergunta();
    if (erro != null) {
      setState(() => _carregando = false);
      _mostrarMensagem(erro);
      return;
    }
    try {
      final gabarito = await _repository.buscarGabaritoPorPergunta(
        widget.pergunta.id,
      );
      if (!mounted) return;
      setState(() {
        _gabarito = gabarito;
        _alternativaCorretaId = gabarito?.alternativaCorretaId;
        if ((_alternativaCorretaId ?? '').isEmpty &&
            (gabarito?.alternativasCorretasIds.isNotEmpty ?? false)) {
          _alternativaCorretaId = gabarito!.alternativasCorretasIds.first;
        }
        _respostaTexto.text = gabarito?.respostaEsperadaTexto ?? '';
        _justificativa.text = gabarito?.justificativaCorreta ?? '';
        _peso.text = (gabarito?.peso ?? widget.pergunta.peso).toString();
        _ativo = gabarito?.ativo ?? true;
        _carregando = false;
      });
    } catch (e, stack) {
      _logErro(e, stack);
      if (!mounted) return;
      setState(() => _carregando = false);
      _mostrarMensagem('Não foi possível carregar o gabarito.');
    }
  }

  String? _validarPergunta() {
    if (widget.pergunta.id.trim().isEmpty) {
      return 'Pergunta sem id. Salve a pergunta antes de cadastrar gabarito.';
    }
    if (widget.pergunta.estudoId.trim().isEmpty ||
        widget.pergunta.cicloId.trim().isEmpty) {
      return 'Pergunta sem ciclo ou estudo. Corrija a pergunta antes.';
    }
    return null;
  }

  Future<void> _salvar({bool? ativoForcado}) async {
    final erroPergunta = _validarPergunta();
    if (erroPergunta != null) {
      _mostrarMensagem(erroPergunta);
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final peso = int.tryParse(_peso.text.trim()) ?? 0;
    if (peso <= 0) {
      _mostrarMensagem('Peso precisa ser maior que zero.');
      return;
    }

    final respostaTexto = _respostaTexto.text.trim();
    final alternativaId = _alternativaCorretaId?.trim() ?? '';
    if (_usaAlternativas && alternativaId.isEmpty) {
      _mostrarMensagem('Marque a alternativa correta.');
      return;
    }
    if (!_usaAlternativas && respostaTexto.isEmpty) {
      _mostrarMensagem('Informe a resposta esperada.');
      return;
    }
    if (alternativaId.isEmpty && respostaTexto.isEmpty) {
      _mostrarMensagem('Informe pelo menos uma resposta correta.');
      return;
    }

    final gabarito = GabaritoEstudoModel(
      id: widget.pergunta.id,
      perguntaId: widget.pergunta.id,
      estudoId: widget.pergunta.estudoId,
      cicloId: widget.pergunta.cicloId,
      tipoPergunta: widget.pergunta.tipo,
      alternativaCorretaId: alternativaId.isEmpty ? null : alternativaId,
      alternativasCorretasIds: alternativaId.isEmpty
          ? const []
          : [alternativaId],
      respostaEsperadaTexto: respostaTexto.isEmpty ? null : respostaTexto,
      justificativaCorreta: _justificativa.text.trim().isEmpty
          ? null
          : _justificativa.text.trim(),
      peso: peso,
      ativo: ativoForcado ?? _ativo,
      criadoEm: _gabarito?.criadoEm,
      criadoPor: _gabarito?.criadoPor,
    );

    setState(() => _salvando = true);
    try {
      await _repository.salvarGabarito(gabarito);
      if (!mounted) return;
      setState(() {
        _gabarito = gabarito;
        _ativo = gabarito.ativo;
      });
      _mostrarMensagem('Gabarito salvo em estudos_gabaritos.');
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível salvar o gabarito.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _excluir() async {
    final ok = await _confirmar(
      titulo: 'Excluir gabarito?',
      mensagem: 'O gabarito protegido desta pergunta será removido.',
      acao: 'Excluir',
    );
    if (ok != true) return;
    setState(() => _salvando = true);
    try {
      await _repository.excluirGabarito(widget.pergunta.id);
      if (!mounted) return;
      setState(() {
        _gabarito = null;
        _alternativaCorretaId = null;
        _respostaTexto.clear();
        _justificativa.clear();
        _ativo = true;
      });
      _mostrarMensagem('Gabarito excluído.');
    } catch (e, stack) {
      _logErro(e, stack);
      if (mounted) _mostrarMensagem('Não foi possível excluir o gabarito.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<bool> _confirmarAlteracaoAtivo(bool novoValor) async {
    final ok = await _confirmar(
      titulo: novoValor ? 'Ativar gabarito?' : 'Desativar gabarito?',
      mensagem: novoValor
          ? 'O gabarito ficará ativo para correções futuras protegidas.'
          : 'O gabarito continuará salvo, mas ficará inativo para correções futuras.',
      acao: 'Confirmar',
    );
    return ok == true;
  }

  Future<void> _confirmarAtivarOuDesativar() async {
    final novoValor = !_ativo;
    if (await _confirmarAlteracaoAtivo(novoValor)) {
      await _salvar(ativoForcado: novoValor);
    }
  }

  Future<void> _confirmarSwitchAtivo(bool novoValor) async {
    if (novoValor == _ativo) return;
    if (await _confirmarAlteracaoAtivo(novoValor) && mounted) {
      setState(() => _ativo = novoValor);
    }
  }

  Future<bool?> _confirmar({
    required String titulo,
    required String mensagem,
    required String acao,
  }) {
    final t = context.uai;
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: t.surface,
        title: Text(titulo, style: TextStyle(color: t.textPrimary)),
        content: Text(mensagem, style: TextStyle(color: t.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(acao),
          ),
        ],
      ),
    );
  }

  void _mostrarMensagem(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), behavior: SnackBarBehavior.floating),
    );
  }

  void _logErro(Object error, StackTrace stackTrace) {
    if (!kDebugMode) return;
    debugPrint('Erro em gabarito de pergunta: $error');
    debugPrint(stackTrace.toString());
  }

  Color _readableOn(Color background) => background.computeLuminance() > 0.48
      ? const Color(0xFF111827)
      : Colors.white;

  @override
  Widget build(BuildContext context) {
    final t = context.uai;
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text(
          'Gabarito protegido',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor:
            Theme.of(context).appBarTheme.backgroundColor ?? t.primary,
        foregroundColor: _readableOn(
          Theme.of(context).appBarTheme.backgroundColor ?? t.primary,
        ),
      ),
      body: _carregando
          ? Center(child: CircularProgressIndicator(color: t.primary))
          : ListView(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width >= 900 ? 22 : 14,
                16,
                MediaQuery.sizeOf(context).width >= 900 ? 22 : 14,
                96,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _perguntaCard(),
                          const SizedBox(height: 12),
                          _avisoSeguranca(),
                          const SizedBox(height: 12),
                          _section('Resposta correta', [
                            if (_usaAlternativas) _alternativas(),
                            if (!_usaAlternativas)
                              _textField(
                                _respostaTexto,
                                'Resposta esperada',
                                requiredField: true,
                                maxLines: 4,
                              ),
                            if (_usaAlternativas) ...[
                              const SizedBox(height: 10),
                              _textField(
                                _respostaTexto,
                                'Resposta esperada textual futura',
                                maxLines: 3,
                              ),
                            ],
                            const SizedBox(height: 10),
                            _textField(
                              _justificativa,
                              'Justificativa correta',
                              maxLines: 4,
                            ),
                          ]),
                          const SizedBox(height: 12),
                          _section('Configuração', [
                            Row(
                              children: [
                                Expanded(child: _numberField(_peso, 'Peso')),
                                const SizedBox(width: 10),
                                Expanded(child: _ativoSwitch()),
                              ],
                            ),
                          ]),
                          const SizedBox(height: 16),
                          _actions(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _perguntaCard() {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
        boxShadow: t.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.pergunta.enunciado.isEmpty
                ? 'Pergunta sem enunciado'
                : widget.pergunta.enunciado,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 18,
              height: 1.2,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _chip(
                Icons.category_rounded,
                PerguntaEstudoTipo.label(widget.pergunta.tipo),
              ),
              _chip(
                Icons.account_tree_rounded,
                widget.pergunta.cicloTituloSnapshot,
              ),
              _chip(
                Icons.menu_book_rounded,
                'Estudo ${widget.pergunta.estudoNumeroSnapshot.toString().padLeft(3, '0')} - ${widget.pergunta.estudoTituloSnapshot}',
              ),
              _chip(
                Icons.signal_cellular_alt_rounded,
                PerguntaEstudoDificuldade.label(widget.pergunta.dificuldade),
              ),
              _chip(Icons.score_rounded, 'Peso ${widget.pergunta.peso}'),
              _chip(
                Icons.flag_rounded,
                PerguntaEstudoStatus.label(widget.pergunta.status),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avisoSeguranca() {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.warning.withValues(alpha: 0.10), t.card),
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.warning.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_rounded, color: t.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Gabarito protegido. Não aparece para alunos. Não é salvo na pergunta pública.',
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _alternativas() {
    final alternativas = widget.pergunta.alternativasPublicas
        .where((a) => a.id.trim().isNotEmpty && a.texto.trim().isNotEmpty)
        .toList();
    if (alternativas.isEmpty) {
      return const Text('Esta pergunta não possui alternativas públicas.');
    }
    return Column(children: alternativas.map(_alternativaTile).toList());
  }

  Widget _alternativaTile(AlternativaPerguntaModel alternativa) {
    final t = context.uai;
    final selected = _alternativaCorretaId == alternativa.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? Color.alphaBlend(t.primary.withValues(alpha: 0.10), t.card)
            : t.surface,
        borderRadius: BorderRadius.circular(t.cardRadius - 4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _salvando
              ? null
              : () => setState(() => _alternativaCorretaId = alternativa.id),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.cardRadius - 4),
              border: Border.all(color: selected ? t.primary : t.border),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? t.primary : t.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alternativa.texto,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ID público: ${alternativa.id}',
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
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
  }

  Widget _actions() {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _salvando ? null : _confirmarAtivarOuDesativar,
          icon: Icon(
            _ativo ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          ),
          label: Text(_ativo ? 'Desativar' : 'Ativar'),
        ),
        OutlinedButton.icon(
          onPressed: _salvando || _gabarito == null ? null : _excluir,
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Excluir gabarito'),
        ),
        FilledButton.icon(
          onPressed: _salvando ? null : _salvar,
          icon: const Icon(Icons.save_rounded),
          label: Text(_salvando ? 'Salvando...' : 'Salvar'),
        ),
      ],
    );
  }

  Widget _section(String title, List<Widget> children) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    final t = context.uai;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: t.cardAlt,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: t.primary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final n = int.tryParse(value?.trim() ?? '');
        if (n == null || n <= 0) return 'Informe numero positivo';
        return null;
      },
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    bool requiredField = false,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        if (requiredField && (value?.trim().isEmpty ?? true)) {
          return 'Campo obrigatorio';
        }
        return null;
      },
    );
  }

  Widget _ativoSwitch() {
    final t = context.uai;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        value: _ativo,
        activeThumbColor: t.primary,
        onChanged: _salvando ? null : _confirmarSwitchAtivo,
        title: const Text('Ativo'),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}
