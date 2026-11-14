import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/godot_project_contract.dart';
import '../../providers/workbench_provider.dart';
import '../../theme/app_theme.dart';

/// Modal editor for per-project Godot 4 Physics Layers, InputMap Actions, Autoloads, and Groups.
Future<void> showGodotContractDialog(
  BuildContext context,
  WorkbenchProvider workbench,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _GodotContractDialog(workbench: workbench),
  );
}

class _GodotContractDialog extends StatefulWidget {
  final WorkbenchProvider workbench;

  const _GodotContractDialog({required this.workbench});

  @override
  State<_GodotContractDialog> createState() => _GodotContractDialogState();
}

class _GodotContractDialogState extends State<_GodotContractDialog> {
  late final GodotProjectContract contract =
      widget.workbench.activeGodotContract;
  late final TextEditingController layersCtrl = TextEditingController(
    text: (contract.physicsLayers.keys.toList()..sort())
        .map((k) => '$k: ${contract.physicsLayers[k]}')
        .join(', '),
  );
  late final TextEditingController inputsCtrl = TextEditingController(
    text: contract.inputActions.join(', '),
  );
  late final TextEditingController autoloadsCtrl = TextEditingController(
    text: contract.autoloads.map((a) => '${a.name}=${a.resPath}').join(', '),
  );
  late final TextEditingController groupsCtrl = TextEditingController(
    text: contract.groups.join(', '),
  );
  late bool is3D = contract.is3D;

  @override
  void dispose() {
    layersCtrl.dispose();
    inputsCtrl.dispose();
    autoloadsCtrl.dispose();
    groupsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext innerCtx) {
    final workbench = widget.workbench;
    void setStateDialog(VoidCallback fn) => setState(fn);

    final isDark = workbench.isDark;
        final bgSurface = AppTheme.bgSurfaceFor(isDark);
        final borderCol = AppTheme.borderSubtleFor(isDark);
        final textPrimary = AppTheme.textPrimaryFor(isDark);
        final textMuted = AppTheme.textMutedFor(isDark);

        GodotProjectContract buildContractFromFields() {
          final parsedLayers = <int, String>{};
          for (final chunk in layersCtrl.text.split(',')) {
            final parts = chunk.split(':');
            if (parts.length < 2) continue;
            final idx = int.tryParse(parts.first.trim());
            final name = parts.sublist(1).join(':').trim();
            if (idx != null && idx >= 1 && idx <= 32 && name.isNotEmpty) {
              parsedLayers[idx] = name;
            }
          }
          final parsedInputs = inputsCtrl.text
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();
          final parsedAutoloads = <GodotAutoloadEntry>[];
          for (final chunk in autoloadsCtrl.text.split(',')) {
            final parts = chunk.split('=');
            if (parts.length < 2) continue;
            final name = parts.first.trim();
            final path = GodotAutoloadEntry.normalizeResPath(
              parts.sublist(1).join('='),
            );
            if (name.isNotEmpty && path.isNotEmpty) {
              parsedAutoloads.add(GodotAutoloadEntry(name: name, resPath: path));
            }
          }
          final parsedGroups = groupsCtrl.text
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();
          return contract.copyWith(
            physicsLayers: parsedLayers,
            inputActions: parsedInputs,
            autoloads: parsedAutoloads,
            groups: parsedGroups,
            is3D: is3D,
          );
        }

        return AlertDialog(
          backgroundColor: bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: borderCol),
          ),
          title: Row(
            children: [
              const Icon(Icons.tune_rounded, size: 17, color: Color(0xFF38BDF8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Godot 4 Project Contract',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(is3D ? '3D Physics' : '2D Physics'),
                selected: is3D,
                onSelected: (v) => setStateDialog(() => is3D = v),
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Shared across prompts, AGENTS.md, and inline Inspector layer toggles.',
                    style: GoogleFonts.inter(fontSize: 12, color: textMuted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('contract_layers_input'),
                    controller: layersCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Physics Layers (e.g. 1: World, 2: Player, 3: Enemy)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('contract_inputs_input'),
                    controller: inputsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'InputMap Actions (comma-separated)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('contract_autoloads_input'),
                    controller: autoloadsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Autoload Singletons (e.g. Events=res://autoloads/events.gd)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('contract_groups_input'),
                    controller: groupsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Node Groups (comma-separated)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                final ini = buildContractFromFields().toProjectGodotIniSnippet();
                Clipboard.setData(ClipboardData(text: ini));
              },
              child: const Text('Copy project.godot INI'),
            ),
            TextButton(
              onPressed: () => Navigator.of(innerCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              key: const ValueKey('contract_save_btn'),
              onPressed: () {
                workbench.updateGodotContract(buildContractFromFields());
                Navigator.of(innerCtx).pop();
              },
              child: const Text('Save Contract'),
            ),
          ],
        );
  }
}
