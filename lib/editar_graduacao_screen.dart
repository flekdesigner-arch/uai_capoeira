import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:xml/xml.dart' as xml;

class EditarGraduacaoScreen extends StatefulWidget {
  final String? graduacaoId;

  const EditarGraduacaoScreen({super.key, this.graduacaoId});

  @override
  State<EditarGraduacaoScreen> createState() => _EditarGraduacaoScreenState();
}

class _EditarGraduacaoScreenState extends State<EditarGraduacaoScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nomeController = TextEditingController();
  final _tituloController = TextEditingController();
  final _nivelController = TextEditingController();
  final _idadeMinimaController = TextEditingController();
  final _fraseController = TextEditingController();
  final _descricaoSiteController = TextEditingController();
  final _cordaController = TextEditingController();

  String? _tipoPublico = 'ADULTO';
  String? _tipoDocumento = 'CERTIFICADO';

  Color _cor1 = Colors.grey;
  Color _cor2 = Colors.grey;
  Color _corPonta1 = Colors.grey;
  Color _corPonta2 = Colors.grey;

  String? _svgContent;
  bool _isLoading = false;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _loadSvg();

    if (widget.graduacaoId != null) {
      _loadGraduacaoData();
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _tituloController.dispose();
    _nivelController.dispose();
    _idadeMinimaController.dispose();
    _fraseController.dispose();
    _descricaoSiteController.dispose();
    _cordaController.dispose();
    super.dispose();
  }

  Future<void> _loadSvg() async {
    try {
      final content = await DefaultAssetBundle.of(context)
          .loadString('assets/images/corda.svg');

      if (mounted) {
        setState(() => _svgContent = content);
      }
    } catch (e) {
      debugPrint('Erro ao carregar corda.svg: $e');
    }
  }

  Future<void> _loadGraduacaoData() async {
    setState(() => _isLoading = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('graduacoes')
          .doc(widget.graduacaoId)
          .get();

      final data = doc.data();

      if (data != null) {
        _nomeController.text = data['nome_graduacao']?.toString() ?? '';
        _tituloController.text = data['titulo_graduacao']?.toString() ?? '';
        _nivelController.text = data['nivel_graduacao']?.toString() ?? '';
        _idadeMinimaController.text = data['idade_minima']?.toString() ?? '';
        _fraseController.text = data['frase']?.toString() ?? '';
        _descricaoSiteController.text =
            data['descricao_site']?.toString() ??
                data['descricao_graduacao']?.toString() ??
                data['descricao']?.toString() ??
                '';
        _cordaController.text = data['corda']?.toString() ?? '';

        setState(() {
          _tipoPublico = data['tipo_publico']?.toString() ?? 'ADULTO';
          _tipoDocumento =
              data['certificado_ou_diploma']?.toString() ?? 'CERTIFICADO';
          _cor1 = _colorFromHex(data['hex_cor1']);
          _cor2 = _colorFromHex(data['hex_cor2']);
          _corPonta1 = _colorFromHex(data['hex_ponta1']);
          _corPonta2 = _colorFromHex(data['hex_ponta2']);
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Erro ao carregar graduação: $e', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _colorFromHex(String? hexColor) {
    if (hexColor == null || hexColor.trim().isEmpty) return Colors.grey;

    try {
      final cleaned = hexColor.replaceAll('#', '').trim();

      if (cleaned.length == 6) {
        return Color(int.parse('FF$cleaned', radix: 16));
      }

      if (cleaned.length == 8) {
        return Color(int.parse(cleaned, radix: 16));
      }
    } catch (_) {}

    return Colors.grey;
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  Future<void> _pickColor({
    required String titulo,
    required Color corAtual,
    required ValueChanged<Color> onColorChanged,
  }) async {
    Color pickedColor = corAtual;
    final hexController = TextEditingController(text: _colorToHex(corAtual));

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.all(14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Text(titulo),
          content: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: hexController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Código HEX',
                        hintText: '#RRGGBB',
                        prefixIcon: Icon(
                          Icons.tag_rounded,
                          color: Colors.red.shade900,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onChanged: (value) {
                        if (value.trim().length >= 7) {
                          final color = _colorFromHex(value);
                          setDialogState(() => pickedColor = color);
                          setState(() => onColorChanged(color));
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    ColorPicker(
                      pickerColor: pickedColor,
                      onColorChanged: (color) {
                        setDialogState(() {
                          pickedColor = color;
                          hexController.text = _colorToHex(color);
                        });
                        setState(() => onColorChanged(color));
                      },
                      pickerAreaHeightPercent: 0.75,
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              child: const Text('CANCELAR'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
              ),
              child: const Text('OK'),
              onPressed: () {
                setState(() => onColorChanged(pickedColor));
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );

    hexController.dispose();
  }

  Future<void> _saveGraduacao() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _salvando = true);

    try {
      final nome = _nomeController.text.trim();
      final corda = _cordaController.text.trim();
      final descricaoSite = _descricaoSiteController.text.trim();

      final data = {
        'nome_graduacao': nome,
        'titulo_graduacao': _tituloController.text.trim(),
        'nivel_graduacao': int.tryParse(_nivelController.text.trim()) ?? 0,
        'idade_minima': int.tryParse(_idadeMinimaController.text.trim()) ?? 0,
        'tipo_publico': _tipoPublico,
        'certificado_ou_diploma': _tipoDocumento,
        'frase': _fraseController.text.trim(),
        'descricao_site': descricaoSite,
        'descricao_graduacao': descricaoSite,
        'corda': corda,
        'hex_cor1': _colorToHex(_cor1),
        'hex_cor2': _colorToHex(_cor2),
        'hex_ponta1': _colorToHex(_corPonta1),
        'hex_ponta2': _colorToHex(_corPonta2),
        'searchableName': nome.toLowerCase(),
        'descricaoCompleta': '$nome - $corda',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.graduacaoId == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('graduacoes').add(data);
      } else {
        await FirebaseFirestore.instance
            .collection('graduacoes')
            .doc(widget.graduacaoId)
            .set(data, SetOptions(merge: true));
      }

      if (mounted) {
        _showSnack('Graduação salva com sucesso!', Colors.green);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) _showSnack('Erro ao salvar graduação: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  String? get _modifiedSvgContent {
    if (_svgContent == null) return null;

    try {
      final document = xml.XmlDocument.parse(_svgContent!);

      xml.XmlElement? findElementById(String id) {
        try {
          return document.rootElement.descendants
              .whereType<xml.XmlElement>()
              .firstWhere((e) => e.getAttribute('id') == id);
        } catch (_) {
          return null;
        }
      }

      void changeColor(String id, Color color) {
        final element = findElementById(id);
        if (element == null) return;

        final style = element.getAttribute('style') ?? '';
        final hex = _colorToHex(color).toLowerCase();
        final newStyle =
        style.replaceAll(RegExp(r'fill:#[0-9a-fA-F]{6}'), '');

        element.setAttribute('style', 'fill:$hex;$newStyle');
      }

      changeColor('cor1', _cor1);
      changeColor('cor2', _cor2);
      changeColor('corponta1', _corPonta1);
      changeColor('corponta2', _corPonta2);

      return document.toXmlString();
    } catch (e) {
      debugPrint('Erro ao modificar SVG: $e');
      return _svgContent;
    }
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  String get _previewNome {
    final text = _nomeController.text.trim();
    return text.isEmpty ? 'Nome da graduação' : text;
  }

  String get _previewCorda {
    final text = _cordaController.text.trim();
    return text.isEmpty ? 'Nome da corda' : text;
  }

  String get _previewDescricao {
    return _descricaoSiteController.text.trim();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.graduacaoId != null;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          isEdit ? 'Editar Graduação' : 'Nova Graduação',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: _salvando
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: Colors.white),
            )
                : const Icon(Icons.save_rounded),
            onPressed: _salvando || _isLoading ? null : _saveGraduacao,
            tooltip: 'Salvar',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Colors.red.shade900))
          : Form(
        key: _formKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 980;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: isWide
                    ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 410,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                          18,
                          18,
                          8,
                          100,
                        ),
                        children: [
                          _buildPreviewCard(isWide: true),
                          const SizedBox(height: 14),
                          _buildColorsCard(),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                          8,
                          18,
                          18,
                          100,
                        ),
                        children: [
                          _buildFormCard(),
                        ],
                      ),
                    ),
                  ],
                )
                    : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
                  children: [
                    _buildPreviewCard(isWide: false),
                    const SizedBox(height: 14),
                    _buildColorsCard(),
                    const SizedBox(height: 14),
                    _buildFormCard(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: _salvando || _isLoading ? null : _saveGraduacao,
            icon: _salvando
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(color: Colors.white),
            )
                : const Icon(Icons.save_rounded),
            label: Text(_salvando ? 'SALVANDO...' : 'SALVAR GRADUAÇÃO'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade900,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard({required bool isWide}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade900, Colors.red.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.red.shade900.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.13),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.14)),
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: Colors.white,
              size: 31,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Preview da graduação',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 19,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Veja como a corda e a descrição vão aparecer.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: isWide ? 155 : 138,
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: _modifiedSvgContent != null
                ? SvgPicture.string(_modifiedSvgContent!, fit: BoxFit.contain)
                : Center(
              child: CircularProgressIndicator(color: Colors.red.shade900),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.14)),
            ),
            child: Column(
              children: [
                Text(
                  _previewNome,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _previewCorda,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                if (_previewDescricao.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      _previewDescricao,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        fontSize: 12.5,
                        height: 1.34,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorsCard() {
    return _cardShell(
      child: Column(
        children: [
          _sectionTitle(
            icon: Icons.palette_rounded,
            title: 'Cores da corda',
            subtitle: 'Toque em uma cor para editar. O preview muda na hora.',
            centered: true,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth < 390
                  ? (constraints.maxWidth - 10) / 2
                  : (constraints.maxWidth - 30) / 4;

              return Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _buildColorButton('Cor 1', _cor1, (c) => _cor1 = c),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildColorButton('Cor 2', _cor2, (c) => _cor2 = c),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildColorButton(
                      'Ponta 1',
                      _corPonta1,
                          (c) => _corPonta1 = c,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildColorButton(
                      'Ponta 2',
                      _corPonta2,
                          (c) => _corPonta2 = c,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return _cardShell(
      child: Column(
        children: [
          _sectionTitle(
            icon: Icons.edit_note_rounded,
            title: 'Dados principais',
            subtitle: 'Informações usadas no sistema, site e certificados.',
            centered: false,
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _nomeController,
            label: 'Nome da Graduação *',
            hint: 'Ex: 1° INFANTIL - CRUA / CINZA',
            icon: Icons.workspace_premium_rounded,
            validator: _requiredValidator,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _cordaController,
            label: 'Nome da Corda *',
            hint: 'Ex: CRUA, AZUL / ROXO',
            icon: Icons.linear_scale_rounded,
            validator: _requiredValidator,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _tituloController,
            label: 'Título *',
            hint: 'Ex: ALUNO INFANTIL, MONITOR',
            icon: Icons.badge_rounded,
            validator: _requiredValidator,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 560;

              final fields = [
                _buildTextField(
                  controller: _nivelController,
                  label: 'Nível *',
                  hint: 'Ex: 1',
                  icon: Icons.format_list_numbered_rounded,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: _requiredValidator,
                ),
                _buildTextField(
                  controller: _idadeMinimaController,
                  label: 'Idade mínima *',
                  hint: 'Ex: 13',
                  icon: Icons.cake_rounded,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: _requiredValidator,
                ),
              ];

              if (narrow) {
                return Column(
                  children: [
                    fields[0],
                    const SizedBox(height: 12),
                    fields[1],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 12),
                  Expanded(child: fields[1]),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 560;

              final fields = [
                _buildDropdown(
                  label: 'Público *',
                  icon: Icons.groups_rounded,
                  value: _tipoPublico,
                  items: const ['ADULTO', 'INFANTIL'],
                  onChanged: (value) => setState(() => _tipoPublico = value),
                ),
                _buildDropdown(
                  label: 'Tipo documento *',
                  icon: Icons.description_rounded,
                  value: _tipoDocumento,
                  items: const ['CERTIFICADO', 'CERTIFICADOCOMCPF', 'DIPLOMA'],
                  onChanged: (value) => setState(() => _tipoDocumento = value),
                ),
              ];

              if (narrow) {
                return Column(
                  children: [
                    fields[0],
                    const SizedBox(height: 12),
                    fields[1],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 12),
                  Expanded(child: fields[1]),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          _sectionTitle(
            icon: Icons.auto_stories_rounded,
            title: 'Textos da graduação',
            subtitle:
            'A descrição aparece no site. A frase continua sendo usada no certificado.',
            centered: false,
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _descricaoSiteController,
            label: 'Descrição da graduação no site',
            hint:
            'Ex: O cinza carrega o peso das correntes pelos escravizados...',
            icon: Icons.public_rounded,
            maxLines: 5,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _fraseController,
            label: 'Frase do Certificado *',
            hint: 'Texto que aparecerá no certificado...',
            icon: Icons.text_snippet_rounded,
            maxLines: 4,
            validator: _requiredValidator,
          ),
        ],
      ),
    );
  }

  Widget _cardShell({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 7,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool centered,
  }) {
    return Row(
      mainAxisAlignment: centered ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.red.shade900.withOpacity(0.08),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: Colors.red.shade900),
        ),
        const SizedBox(width: 11),
        Flexible(
          child: Column(
            crossAxisAlignment:
            centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                title,
                textAlign: centered ? TextAlign.center : TextAlign.left,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: centered ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11.5,
                  height: 1.22,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: maxLines > 1,
        prefixIcon: Padding(
          padding: EdgeInsets.only(bottom: maxLines > 1 ? 72 : 0),
          child: Icon(icon, color: Colors.red.shade900),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.red.shade900, width: 1.4),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final normalizedItems = <String>[
      ...items,
      if (value != null && value.trim().isNotEmpty && !items.contains(value))
        value,
    ].toSet().toList();

    final safeValue = value != null && normalizedItems.contains(value)
        ? value
        : normalizedItems.isNotEmpty
        ? normalizedItems.first
        : null;

    String labelItem(String item) {
      switch (item) {
        case 'CERTIFICADO':
          return 'CERTIFICADO';
        case 'CERTIFICADOCOMCPF':
          return 'CERTIFICADO COM CPF';
        case 'DIPLOMA':
          return 'DIPLOMA';
        case 'ADULTO':
          return 'ADULTO';
        case 'INFANTIL':
          return 'INFANTIL';
        default:
          return item;
      }
    }

    return DropdownButtonFormField<String>(
      value: safeValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.red.shade900),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.red.shade900, width: 1.4),
        ),
      ),
      items: normalizedItems.map((item) {
        return DropdownMenuItem<String>(
          value: item,
          child: Text(labelItem(item)),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  String? _requiredValidator(String? value) {
    return value == null || value.trim().isEmpty ? 'Campo obrigatório' : null;
  }

  Widget _buildColorButton(
      String label,
      Color color,
      ValueChanged<Color> onColorChanged,
      ) {
    return InkWell(
      onTap: () => _pickColor(
        titulo: label,
        corAtual: color,
        onColorChanged: onColorChanged,
      ),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 10.8,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _colorToHex(color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
