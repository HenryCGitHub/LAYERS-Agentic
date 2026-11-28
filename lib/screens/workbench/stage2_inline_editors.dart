import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/epic_spec.dart';
import '../../theme/app_theme.dart';

/// Shared inline editor box for Epic `§01` and Feature `§01` Scope contracts.
class InlineScopeEditorBox extends StatefulWidget {
  final bool isDark;
  final String initialGoal;
  final List<String> initialInScope;
  final List<String> initialDoneWhen;
  final String initialDelta;
  final bool showDeltaField;
  final Key? goalInputKey;
  final Key? inScopeInputKey;
  final Key? doneWhenInputKey;
  final Key? deltaInputKey;
  final Key? saveBtnKey;
  final void Function({
    required String goal,
    required List<String> inScope,
    required List<String> doneWhen,
    required String delta,
  }) onSave;
  final VoidCallback onCancel;

  const InlineScopeEditorBox({
    super.key,
    required this.isDark,
    required this.initialGoal,
    required this.initialInScope,
    required this.initialDoneWhen,
    this.initialDelta = '',
    this.showDeltaField = false,
    this.goalInputKey,
    this.inScopeInputKey,
    this.doneWhenInputKey,
    this.deltaInputKey,
    this.saveBtnKey,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<InlineScopeEditorBox> createState() => _InlineScopeEditorBoxState();
}

class _InlineScopeEditorBoxState extends State<InlineScopeEditorBox> {
  late final TextEditingController _goalCtrl;
  late final TextEditingController _inScopeCtrl;
  late final TextEditingController _doneWhenCtrl;
  late final TextEditingController _deltaCtrl;

  @override
  void initState() {
    super.initState();
    _goalCtrl = TextEditingController(text: widget.initialGoal);
    _inScopeCtrl = TextEditingController(text: widget.initialInScope.join('\n'));
    _doneWhenCtrl =
        TextEditingController(text: widget.initialDoneWhen.join('\n'));
    _deltaCtrl = TextEditingController(text: widget.initialDelta);
  }

  @override
  void didUpdateWidget(covariant InlineScopeEditorBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialGoal != widget.initialGoal &&
        _goalCtrl.text != widget.initialGoal) {
      _goalCtrl.text = widget.initialGoal;
    }
    final oldInScope = oldWidget.initialInScope.join('\n');
    final nextInScope = widget.initialInScope.join('\n');
    if (oldInScope != nextInScope && _inScopeCtrl.text != nextInScope) {
      _inScopeCtrl.text = nextInScope;
    }
    final oldDoneWhen = oldWidget.initialDoneWhen.join('\n');
    final nextDoneWhen = widget.initialDoneWhen.join('\n');
    if (oldDoneWhen != nextDoneWhen && _doneWhenCtrl.text != nextDoneWhen) {
      _doneWhenCtrl.text = nextDoneWhen;
    }
    if (oldWidget.initialDelta != widget.initialDelta &&
        _deltaCtrl.text != widget.initialDelta) {
      _deltaCtrl.text = widget.initialDelta;
    }
  }

  @override
  void dispose() {
    _goalCtrl.dispose();
    _inScopeCtrl.dispose();
    _doneWhenCtrl.dispose();
    _deltaCtrl.dispose();
    super.dispose();
  }

  static List<String> _splitLines(String raw) => raw
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.textPrimaryFor(widget.isDark);
    final muted = AppTheme.textMutedFor(widget.isDark);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          left: BorderSide(color: AppTheme.focalAccentFor(widget.isDark), width: 2),
          bottom: BorderSide(color: AppTheme.borderFor(widget.isDark), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showDeltaField) ...[
            TextField(
              key: widget.deltaInputKey,
              controller: _deltaCtrl,
              style: TextStyle(fontSize: 13, color: primary),
              decoration: InputDecoration(
                labelText: 'Upgrade Delta (+5–10 words)',
                hintStyle: TextStyle(fontSize: 12, color: muted),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            key: widget.goalInputKey,
            controller: _goalCtrl,
            minLines: 1,
            maxLines: 3,
            style: TextStyle(fontSize: 13, color: primary),
            decoration: InputDecoration(
              labelText: 'Goal (1 plain-English sentence)',
              hintStyle: TextStyle(fontSize: 12, color: muted),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: widget.inScopeInputKey,
            controller: _inScopeCtrl,
            minLines: 2,
            maxLines: 5,
            style: TextStyle(fontSize: 12.5, color: primary),
            decoration: InputDecoration(
              labelText: 'In Scope (one item per line)',
              hintStyle: TextStyle(fontSize: 12, color: muted),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: widget.doneWhenInputKey,
            controller: _doneWhenCtrl,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(fontSize: 12.5, color: primary),
            decoration: InputDecoration(
              labelText: 'Done When (one condition per line)',
              hintStyle: TextStyle(fontSize: 12, color: muted),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                key: widget.saveBtnKey,
                onPressed: () => widget.onSave(
                  goal: _goalCtrl.text.trim(),
                  inScope: _splitLines(_inScopeCtrl.text),
                  doneWhen: _splitLines(_doneWhenCtrl.text),
                  delta: _deltaCtrl.text.trim(),
                ),
                child: const Text('Save Scope', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Inline editor box for Feature `§02` Enhanced Input (`IA_*`) rows.
class InlineControlEditorBox extends StatefulWidget {
  final bool isDark;
  final String initialAction;
  final String initialTrigger;
  final String initialRule;
  final Key? actionInputKey;
  final Key? triggerInputKey;
  final Key? ruleInputKey;
  final Key? saveBtnKey;
  final void Function(String action, String trigger, String rule) onSave;
  final VoidCallback onCancel;

  const InlineControlEditorBox({
    super.key,
    required this.isDark,
    this.initialAction = '',
    this.initialTrigger = 'Pressed',
    this.initialRule = '',
    this.actionInputKey,
    this.triggerInputKey,
    this.ruleInputKey,
    this.saveBtnKey,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<InlineControlEditorBox> createState() => _InlineControlEditorBoxState();
}

class _InlineControlEditorBoxState extends State<InlineControlEditorBox> {
  late final TextEditingController _actionCtrl;
  late final TextEditingController _triggerCtrl;
  late final TextEditingController _ruleCtrl;

  @override
  void initState() {
    super.initState();
    _actionCtrl = TextEditingController(text: widget.initialAction);
    _triggerCtrl = TextEditingController(text: widget.initialTrigger);
    _ruleCtrl = TextEditingController(text: widget.initialRule);
  }

  @override
  void dispose() {
    _actionCtrl.dispose();
    _triggerCtrl.dispose();
    _ruleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.textPrimaryFor(widget.isDark);
    final muted = AppTheme.textMutedFor(widget.isDark);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          left: BorderSide(color: AppTheme.focalAccentFor(widget.isDark), width: 2),
          bottom: BorderSide(color: AppTheme.borderFor(widget.isDark), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: widget.actionInputKey,
                  controller: _actionCtrl,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12.5,
                    color: AppTheme.focalAccentFor(widget.isDark),
                  ),
                  decoration: InputDecoration(
                    labelText: 'Action (IA_*)',
                    hintText: 'IA_ClawDash',
                    hintStyle: TextStyle(fontSize: 11.5, color: muted),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  key: widget.triggerInputKey,
                  controller: _triggerCtrl,
                  style: GoogleFonts.jetBrainsMono(fontSize: 12.5, color: primary),
                  decoration: InputDecoration(
                    labelText: 'Trigger',
                    hintText: 'Pressed',
                    hintStyle: TextStyle(fontSize: 11.5, color: muted),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: widget.ruleInputKey,
            controller: _ruleCtrl,
            style: TextStyle(fontSize: 12.5, color: primary),
            decoration: InputDecoration(
              labelText: 'Input Behavior Rule',
              hintText: 'Launch dash burst along camera facing',
              hintStyle: TextStyle(fontSize: 12, color: muted),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                key: widget.saveBtnKey,
                onPressed: () {
                  final action = _actionCtrl.text.trim();
                  final trigger = _triggerCtrl.text.trim();
                  final rule = _ruleCtrl.text.trim();
                  if (action.isEmpty || rule.isEmpty) return;
                  widget.onSave(action, trigger, rule);
                },
                child: const Text('Save Input', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Plain direct Key | Value | Unit add form for Feature `§03` Exposed Tuning (zero sliders).
class InlineTuningAddBox extends StatefulWidget {
  final bool isDark;
  final Key? keyInputKey;
  final Key? valueInputKey;
  final Key? unitInputKey;
  final Key? saveBtnKey;
  final void Function(String key, String value, String unit) onAdd;
  final VoidCallback onCancel;

  const InlineTuningAddBox({
    super.key,
    required this.isDark,
    this.keyInputKey,
    this.valueInputKey,
    this.unitInputKey,
    this.saveBtnKey,
    required this.onAdd,
    required this.onCancel,
  });

  @override
  State<InlineTuningAddBox> createState() => _InlineTuningAddBoxState();
}

class _InlineTuningAddBoxState extends State<InlineTuningAddBox> {
  final TextEditingController _keyCtrl = TextEditingController();
  final TextEditingController _valCtrl = TextEditingController();
  final TextEditingController _unitCtrl = TextEditingController();

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valCtrl.dispose();
    _unitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.textPrimaryFor(widget.isDark);
    final muted = AppTheme.textMutedFor(widget.isDark);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          left: BorderSide(color: AppTheme.focalAccentFor(widget.isDark), width: 2),
          bottom: BorderSide(color: AppTheme.borderFor(widget.isDark), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: widget.keyInputKey,
                  controller: _keyCtrl,
                  style: GoogleFonts.jetBrainsMono(fontSize: 12.5, color: primary),
                  decoration: InputDecoration(
                    labelText: 'Key (PascalCase)',
                    hintText: 'DashDistance',
                    hintStyle: TextStyle(fontSize: 11.5, color: muted),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  key: widget.valueInputKey,
                  controller: _valCtrl,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12.5,
                    color: AppTheme.focalAccentFor(widget.isDark),
                  ),
                  decoration: InputDecoration(
                    labelText: 'Value',
                    hintText: '500',
                    hintStyle: TextStyle(fontSize: 11.5, color: muted),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  key: widget.unitInputKey,
                  controller: _unitCtrl,
                  style: GoogleFonts.jetBrainsMono(fontSize: 12.5, color: primary),
                  decoration: InputDecoration(
                    labelText: 'Unit',
                    hintText: 'cm / cm/s / s',
                    hintStyle: TextStyle(fontSize: 11.5, color: muted),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                key: widget.saveBtnKey,
                onPressed: () {
                  final k = _keyCtrl.text.trim();
                  final v = _valCtrl.text.trim();
                  if (k.isEmpty || v.isEmpty) return;
                  widget.onAdd(k, v, _unitCtrl.text.trim());
                },
                child: const Text('Add Variable', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Reusable single-line inline adder box for Scope Cuts, Cues, and PIE Checks.
class InlineSingleLineAdderBox extends StatefulWidget {
  final bool isDark;
  final String labelText;
  final String hintText;
  final String submitLabel;
  final Key? inputKey;
  final Key? saveBtnKey;
  final void Function(String value) onSubmit;
  final VoidCallback onCancel;

  const InlineSingleLineAdderBox({
    super.key,
    required this.isDark,
    required this.labelText,
    required this.hintText,
    this.submitLabel = 'Add',
    this.inputKey,
    this.saveBtnKey,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  State<InlineSingleLineAdderBox> createState() =>
      _InlineSingleLineAdderBoxState();
}

class _InlineSingleLineAdderBoxState extends State<InlineSingleLineAdderBox> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.textPrimaryFor(widget.isDark);
    final muted = AppTheme.textMutedFor(widget.isDark);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          left: BorderSide(color: AppTheme.focalAccentFor(widget.isDark), width: 2),
          bottom: BorderSide(color: AppTheme.borderFor(widget.isDark), width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: widget.inputKey,
              controller: _ctrl,
              style: TextStyle(fontSize: 13, color: primary),
              decoration: InputDecoration(
                labelText: widget.labelText,
                hintText: widget.hintText,
                hintStyle: TextStyle(fontSize: 12, color: muted),
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: widget.onCancel,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 4),
          ElevatedButton(
            key: widget.saveBtnKey,
            onPressed: _submit,
            child: Text(widget.submitLabel, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// Renders open `[FIX]` notes and optional pasted UE5 error logs on Stage 2 Feature sheets.
class FeatureOpenFixesList extends StatelessWidget {
  final List<EpicPieFix> openFixes;
  final bool isLockedBaseline;
  final bool isDark;
  final void Function(String fixId) onResolve;
  final void Function(String fixId) onDelete;

  const FeatureOpenFixesList({
    super.key,
    required this.openFixes,
    required this.isLockedBaseline,
    required this.isDark,
    required this.onResolve,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.borderFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final secondary = AppTheme.textSecondaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final red = AppTheme.accentRedFor(isDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < openFixes.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border, width: 1)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '[FIX]',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: red,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        openFixes[i].text,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: primary,
                          height: 1.4,
                        ),
                      ),
                      if (openFixes[i].errorLog.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: red.withValues(alpha: 0.6),
                                width: 2,
                              ),
                            ),
                          ),
                          child: Text(
                            openFixes[i].errorLog.trim(),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11.5,
                              color: secondary,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!isLockedBaseline) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    key: ValueKey('resolve_fix_${openFixes[i].id}'),
                    onTap: () => onResolve(openFixes[i].id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        'Resolve',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: green,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => onDelete(openFixes[i].id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        '×',
                        style: TextStyle(fontSize: 15, color: muted),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
