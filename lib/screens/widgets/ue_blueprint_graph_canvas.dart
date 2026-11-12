import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Pin data types matching Unreal Engine 5 Blueprint pin colors.
enum UePinType { exec, boolPin, floatPin, vectorPin, objectPin }

class UeGraphPin {
  final String id;
  final String label;
  final UePinType type;
  final String? inlineLiteral;

  const UeGraphPin({
    required this.id,
    required this.label,
    this.type = UePinType.exec,
    this.inlineLiteral,
  });
}

enum UeNodeKind {
  event,
  functionCall,
  pureMath,
  variableGet,
  branch,
  variableSet,
  delay,
}

class UeGraphNode {
  final String id;
  final String title;
  final String subtitle;
  final UeNodeKind kind;
  final bool isNewInActiveTask;
  final String originLabel;
  final List<UeGraphPin> leftPins;
  final List<UeGraphPin> rightPins;

  const UeGraphNode({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.kind = UeNodeKind.functionCall,
    this.isNewInActiveTask = true,
    this.originLabel = '',
    this.leftPins = const [],
    this.rightPins = const [],
  });
}

class UeGraphWire {
  final String fromNodeId;
  final String fromPinId;
  final String toNodeId;
  final String toPinId;
  final UePinType type;
  final bool isNew;

  const UeGraphWire({
    required this.fromNodeId,
    required this.fromPinId,
    required this.toNodeId,
    required this.toPinId,
    this.type = UePinType.exec,
    this.isNew = true,
  });
}

/// Renders an Unreal Engine 5 Blueprint Event Graph with authentic UE5 Exec
/// chevron pins, colored Data pins, separated Getter pills, inline parameter
/// value boxes, cubic Bezier wires, and a responsive `Fit` / `1:1` view toggle.
class UeBlueprintGraphCanvas extends StatefulWidget {
  final List<UeGraphNode> nodes;
  final List<UeGraphWire> wires;

  const UeBlueprintGraphCanvas({
    super.key,
    required this.nodes,
    required this.wires,
  });

  static bool _isPureComponentOrVariableGetter(String rawLabel) {
    final trimmed = rawLabel.trim();
    final lower = trimmed.toLowerCase();
    // Skip labels that contain pin arguments (`Foo (Pin: Val)`) unless pure math
    final parenIdx = lower.indexOf('(');
    final head = (parenIdx > 0 ? lower.substring(0, parenIdx) : lower).trim();
    if (head.startsWith('event ') ||
        head.startsWith('ia_') ||
        head.contains('input') ||
        head.startsWith('branch') ||
        head.startsWith('sequence') ||
        head.startsWith('set ') ||
        head.contains('delay') ||
        head.startsWith('add ') ||
        head.startsWith('spawn ') ||
        head.startsWith('apply ') ||
        head.startsWith('cast ') ||
        head.startsWith('bind ') ||
        head.startsWith('print ') ||
        head.startsWith('play ')) {
      return false;
    }
    if (head == 'self' || head.startsWith('get ')) {
      return true;
    }
    const knownComponentGetters = <String>{
      'firstpersoncamera',
      'followcamera',
      'cameraboom',
      'springarm',
      'charmove',
      'charactermovement',
      'capsulecomponent',
      'mesh',
      'skeletalmesh',
      'staticmesh',
      'weaponmesh',
      'widgetcomponent',
      'hudwidget',
      'interactbox',
      'hitbox',
      'overlapbox',
    };
    final normalizedHead = head.replaceAll(RegExp(r'[\s_]+'), '');
    if (knownComponentGetters.contains(normalizedHead)) return true;
    if (!head.contains(' ') &&
        (normalizedHead.endsWith('component') ||
            normalizedHead.endsWith('camera') ||
            normalizedHead.endsWith('mesh') ||
            normalizedHead.endsWith('collider') ||
            normalizedHead.endsWith('arm'))) {
      return true;
    }
    return false;
  }

  static List<String> _splitTopLevelArgs(String raw) {
    final parts = <String>[];
    final buf = StringBuffer();
    int depth = 0;
    for (int i = 0; i < raw.length; i++) {
      final ch = raw[i];
      if (ch == '(') depth++;
      if (ch == ')' && depth > 0) depth--;
      if ((ch == ',' || ch == '|') && depth == 0) {
        final item = buf.toString().trim();
        if (item.isNotEmpty) parts.add(item);
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    final tail = buf.toString().trim();
    if (tail.isNotEmpty) parts.add(tail);
    return parts;
  }

  static UePinType _inferPinType(String name, String val) {
    final lowerName = name.toLowerCase();
    final lowerVal = val.toLowerCase();
    if (lowerName.contains('cond') ||
        lowerName.contains('force') ||
        lowerName.startsWith('is') ||
        lowerName.startsWith('buse') ||
        lowerName.startsWith('can') ||
        lowerVal == 'true' ||
        lowerVal == 'false') {
      return UePinType.boolPin;
    }
    if (lowerName.contains('loc') ||
        lowerName.contains('rot') ||
        lowerName.contains('scale') ||
        lowerName.contains('dir') ||
        lowerName.contains('vel') ||
        lowerName.contains('vec') ||
        RegExp(r'(?:^|\()\s*x\s*=|\([^)]*,[^)]*,[^)]*\)', caseSensitive: false)
            .hasMatch(val)) {
      return UePinType.vectorPin;
    }
    if (lowerName == 'target' ||
        lowerName.contains('object') ||
        lowerName.contains('class') ||
        lowerName.contains('comp') ||
        lowerName.contains('actor') ||
        lowerName.contains('context') ||
        lowerVal.startsWith('bp_') ||
        lowerVal.startsWith('imc_') ||
        lowerVal.startsWith('ia_')) {
      return UePinType.objectPin;
    }
    if (RegExp(r'^-?\d+(?:\.\d+)?\s*(?:s|cm|uu|ms)?$').hasMatch(lowerVal) ||
        lowerName.contains('speed') ||
        lowerName.contains('time') ||
        lowerName.contains('duration') ||
        lowerName.contains('amount') ||
        lowerName.contains('distance')) {
      return UePinType.floatPin;
    }
    return UePinType.floatPin;
  }

  /// Parses Unreal Blueprint Event Graph text (`[Event] ──► [Branch]`) into
  /// structured `UeGraphNode`s and `UeGraphWire`s, keeping component/variable
  /// getters off the white `Exec` spine and wired cleanly to `Target`/data pins.
  static ({List<UeGraphNode> nodes, List<UeGraphWire> wires}) parseFromFormula(
    String rawFormula, {
    bool markAllNew = true,
  }) {
    final lines = rawFormula
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final nodes = <UeGraphNode>[];
    final wires = <UeGraphWire>[];
    final seenIds = <String>{};

    final nodeRegex = RegExp(r'\[([^\]]+)\]');
    String? prevExecNodeId;

    for (int lIdx = 0; lIdx < lines.length; lIdx++) {
      final line = lines[lIdx];
      final matches = nodeRegex.allMatches(line).toList();
      if (matches.isEmpty) continue;

      String? linePrevExecId;
      ({String id, UePinType type})? pendingGetter;

      for (int mIdx = 0; mIdx < matches.length; mIdx++) {
        final rawLabel = matches[mIdx].group(1)!.trim();
        final nodeId = 'n_${lIdx}_$mIdx';
        if (!seenIds.add(nodeId)) continue;

        final lower = rawLabel.toLowerCase();
        final parenIdx = rawLabel.indexOf('(');
        final rawTitle = parenIdx > 0
            ? rawLabel.substring(0, parenIdx).trim()
            : rawLabel;
        final rawArgBlock = parenIdx > 0
            ? rawLabel
                .substring(parenIdx + 1)
                .replaceAll(RegExp(r'\)$'), '')
                .trim()
            : '';

        final UeNodeKind kind;
        if (lower.startsWith('event') ||
            lower.startsWith('ia_') ||
            lower.startsWith('enhancedinputaction') ||
            lower.contains('inputaction')) {
          kind = UeNodeKind.event;
        } else if (lower.startsWith('branch') || lower.startsWith('sequence')) {
          kind = UeNodeKind.branch;
        } else if (lower.startsWith('delay')) {
          kind = UeNodeKind.delay;
        } else if (_isPureComponentOrVariableGetter(rawLabel)) {
          kind = (lower.contains('forward') ||
                  lower.contains('multiply') ||
                  lower.contains('make ') ||
                  lower.contains('clamp') ||
                  lower.contains('controller'))
              ? UeNodeKind.pureMath
              : UeNodeKind.variableGet;
        } else if (lower.startsWith('set ') &&
            !lower.startsWith('set timer') &&
            !lower.startsWith('set relative') &&
            !lower.startsWith('set max ') &&
            !lower.startsWith('set actor')) {
          kind = UeNodeKind.variableSet;
        } else {
          kind = UeNodeKind.functionCall;
        }

        final displayTitle = (kind == UeNodeKind.variableGet &&
                !rawTitle.toLowerCase().startsWith('get ') &&
                rawTitle.toLowerCase() != 'self')
            ? 'Get $rawTitle'
            : rawTitle;

        final isPureNode =
            kind == UeNodeKind.pureMath || kind == UeNodeKind.variableGet;

        final leftPins = <UeGraphPin>[
          if (kind != UeNodeKind.event && !isPureNode)
            const UeGraphPin(id: 'exec', label: 'Exec', type: UePinType.exec),
          if (kind == UeNodeKind.branch)
            const UeGraphPin(
              id: 'cond',
              label: 'Condition',
              type: UePinType.boolPin,
            ),
        ];

        // Parse `(Pin: Value, Pin2: Value2)` into clean UE5 left pin rows
        if (rawArgBlock.isNotEmpty) {
          final args = _splitTopLevelArgs(rawArgBlock);
          for (int aIdx = 0; aIdx < args.length; aIdx++) {
            final arg = args[aIdx];
            final colonIdx = arg.indexOf(':');
            final eqIdx = colonIdx < 0 ? arg.indexOf('=') : -1;
            final splitIdx = colonIdx > 0 ? colonIdx : eqIdx;
            if (splitIdx > 0) {
              final pinName = arg.substring(0, splitIdx).trim();
              final pinVal = arg.substring(splitIdx + 1).trim();
              final pinId = pinName.toLowerCase() == 'target'
                  ? 'target'
                  : 'arg_$aIdx';
              leftPins.add(
                UeGraphPin(
                  id: pinId,
                  label: pinName,
                  type: _inferPinType(pinName, pinVal),
                  inlineLiteral: pinVal.isNotEmpty ? pinVal : null,
                ),
              );
            } else if (kind == UeNodeKind.delay) {
              leftPins.add(
                UeGraphPin(
                  id: 'dur',
                  label: 'Duration',
                  type: UePinType.floatPin,
                  inlineLiteral: arg,
                ),
              );
            } else {
              leftPins.add(
                UeGraphPin(
                  id: 'arg_$aIdx',
                  label: 'Value',
                  type: _inferPinType('value', arg),
                  inlineLiteral: arg,
                ),
              );
            }
          }
        }

        // If a preceding getter pill feeds this node and no explicit `target` pin exists yet, add it
        if (pendingGetter != null &&
            !isPureNode &&
            !leftPins.any((p) => p.id == 'target')) {
          leftPins.insert(
            kind == UeNodeKind.event ? 0 : 1,
            UeGraphPin(
              id: 'target',
              label: 'Target',
              type: pendingGetter.type,
            ),
          );
        }

        final rightPins = <UeGraphPin>[
          if (kind == UeNodeKind.branch) ...[
            const UeGraphPin(id: 'true', label: 'True', type: UePinType.exec),
            const UeGraphPin(id: 'false', label: 'False', type: UePinType.exec),
          ] else if (!isPureNode) ...[
            UeGraphPin(
              id: 'then',
              label: kind == UeNodeKind.event
                  ? 'Triggered'
                  : (kind == UeNodeKind.delay ? 'Completed' : 'Then'),
              type: UePinType.exec,
            ),
          ] else ...[
            UeGraphPin(
              id: 'val',
              label: kind == UeNodeKind.variableGet ? '' : 'Return',
              type: kind == UeNodeKind.variableGet
                  ? UePinType.objectPin
                  : UePinType.vectorPin,
            ),
          ],
        ];

        nodes.add(
          UeGraphNode(
            id: nodeId,
            title: displayTitle,
            kind: kind,
            isNewInActiveTask: markAllNew,
            leftPins: leftPins,
            rightPins: rightPins,
          ),
        );

        if (isPureNode) {
          pendingGetter = (
            id: nodeId,
            type: kind == UeNodeKind.variableGet
                ? UePinType.objectPin
                : UePinType.vectorPin,
          );
          continue;
        }

        // Wire preceding Getter pill via Data pin (`Target`) instead of Exec!
        if (pendingGetter != null) {
          final targetPin = leftPins.any((p) => p.id == 'target')
              ? 'target'
              : (kind == UeNodeKind.branch ? 'cond' : leftPins.last.id);
          wires.add(
            UeGraphWire(
              fromNodeId: pendingGetter.id,
              fromPinId: 'val',
              toNodeId: nodeId,
              toPinId: targetPin,
              type: pendingGetter.type,
              isNew: markAllNew,
            ),
          );
          pendingGetter = null;
        }

        // Connect Exec spine strictly between executable nodes
        final execSourceId = linePrevExecId ?? (mIdx == 0 ? prevExecNodeId : null);
        if (execSourceId != null) {
          final sourceNode = nodes.firstWhere((n) => n.id == execSourceId);
          final fromPin = sourceNode.rightPins.isNotEmpty
              ? sourceNode.rightPins.first.id
              : 'then';
          wires.add(
            UeGraphWire(
              fromNodeId: execSourceId,
              fromPinId: fromPin,
              toNodeId: nodeId,
              toPinId: 'exec',
              type: UePinType.exec,
              isNew: markAllNew,
            ),
          );
        }

        linePrevExecId = nodeId;
        prevExecNodeId = nodeId;
      }
    }

    return (nodes: nodes, wires: wires);
  }

  @override
  State<UeBlueprintGraphCanvas> createState() => _UeBlueprintGraphCanvasState();
}

class _UeBlueprintGraphCanvasState extends State<UeBlueprintGraphCanvas> {
  final GlobalKey _stackKey = GlobalKey();
  final Map<String, GlobalKey> _pinKeys = {};
  bool _fitToWidth = true;
  List<({Offset from, Offset to, UePinType type, bool isNew})> _resolvedWires =
      const [];

  @override
  void initState() {
    super.initState();
    _scheduleWireMeasure();
  }

  @override
  void didUpdateWidget(covariant UeBlueprintGraphCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleWireMeasure();
  }

  GlobalKey _keyForPin(String nodeId, String dir, String pinId) {
    final k = '${nodeId}_${dir}_$pinId';
    return _pinKeys.putIfAbsent(k, () => GlobalKey());
  }

  bool _isPinWired(String nodeId, String dir, String pinId) {
    if (dir == 'out') {
      return widget.wires
          .any((w) => w.fromNodeId == nodeId && w.fromPinId == pinId);
    }
    return widget.wires.any((w) => w.toNodeId == nodeId && w.toPinId == pinId);
  }

  void _scheduleWireMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final stackBox =
          _stackKey.currentContext?.findRenderObject() as RenderBox?;
      if (stackBox == null || !stackBox.hasSize) return;

      final nextWires =
          <({Offset from, Offset to, UePinType type, bool isNew})>[];
      for (final w in widget.wires) {
        final fromBox = _pinKeys['${w.fromNodeId}_out_${w.fromPinId}']
            ?.currentContext
            ?.findRenderObject() as RenderBox?;
        final toBox = _pinKeys['${w.toNodeId}_in_${w.toPinId}']
            ?.currentContext
            ?.findRenderObject() as RenderBox?;
        if (fromBox == null ||
            toBox == null ||
            !fromBox.hasSize ||
            !toBox.hasSize) {
          continue;
        }
        final fromGlobal =
            fromBox.localToGlobal(fromBox.size.center(Offset.zero));
        final toGlobal = toBox.localToGlobal(toBox.size.center(Offset.zero));
        nextWires.add((
          from: stackBox.globalToLocal(fromGlobal),
          to: stackBox.globalToLocal(toGlobal),
          type: w.type,
          isNew: w.isNew,
        ));
      }
      if (mounted) {
        setState(() => _resolvedWires = nextWires);
      }
    });
  }

  Color _headerColor(UeNodeKind kind) {
    switch (kind) {
      case UeNodeKind.event:
        return const Color(0xFF991B1B);
      case UeNodeKind.functionCall:
        return const Color(0xFF075985);
      case UeNodeKind.pureMath:
        return const Color(0xFF166534);
      case UeNodeKind.variableGet:
        return const Color(0xFF1E3A5F);
      case UeNodeKind.branch:
        return const Color(0xFF334155);
      case UeNodeKind.variableSet:
        return const Color(0xFF881337);
      case UeNodeKind.delay:
        return const Color(0xFF155E75);
    }
  }

  String _headerGlyph(UeNodeKind kind) {
    switch (kind) {
      case UeNodeKind.event:
        return '⚡';
      case UeNodeKind.functionCall:
        return 'ƒ';
      case UeNodeKind.pureMath:
        return '●';
      case UeNodeKind.variableGet:
        return '◆';
      case UeNodeKind.branch:
        return '⑂';
      case UeNodeKind.variableSet:
        return 'SET';
      case UeNodeKind.delay:
        return '⏱';
    }
  }

  Color _pinColor(UePinType type) {
    switch (type) {
      case UePinType.exec:
        return const Color(0xFFF8FAFC);
      case UePinType.boolPin:
        return const Color(0xFFEF4444);
      case UePinType.floatPin:
        return const Color(0xFF22C55E);
      case UePinType.vectorPin:
        return const Color(0xFFEAB308);
      case UePinType.objectPin:
        return const Color(0xFF38BDF8);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.nodes.isEmpty) return const SizedBox.shrink();

    const double nodeWidth = 236;
    const double nodeGapX = 48;
    const double padding = 16;
    final execNodes = widget.nodes
        .where(
          (n) =>
              n.kind != UeNodeKind.pureMath && n.kind != UeNodeKind.variableGet,
        )
        .toList();
    final pureNodes = widget.nodes
        .where(
          (n) =>
              n.kind == UeNodeKind.pureMath || n.kind == UeNodeKind.variableGet,
        )
        .toList();

    final cols = execNodes.isNotEmpty ? execNodes.length : widget.nodes.length;
    final canvasWidth =
        padding * 2 + cols * nodeWidth + (cols - 1).clamp(0, 20) * nodeGapX;
    final maxExecPins = execNodes.fold<int>(
      1,
      (m, n) => [m, n.leftPins.length, n.rightPins.length]
          .reduce((a, b) => a > b ? a : b),
    );
    final execRowHeight = 56.0 + maxExecPins * 26.0;
    final canvasHeight =
        pureNodes.isNotEmpty ? (execRowHeight + 110.0) : (execRowHeight + 36.0);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF24324B)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // UE5 EventGraph Tab Header + Pin Legend + Fit/1:1 Toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF0C0F16),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: LayoutBuilder(
              builder: (context, hdrCons) {
                final showLegend = hdrCons.maxWidth >= 430;
                return Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF182030),
                        borderRadius: BorderRadius.circular(4),
                        border: const Border(
                          top: BorderSide(color: Color(0xFF38BDF8), width: 2),
                        ),
                      ),
                      child: Text(
                        '⑂ EventGraph',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF7DD3FC),
                        ),
                      ),
                    ),
                    if (showLegend) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          children: [
                            _legendDot('▷ Exec', const Color(0xFFF8FAFC)),
                            _legendDot('● Obj', const Color(0xFF38BDF8)),
                            _legendDot('● Vec', const Color(0xFFEAB308)),
                            _legendDot('● Flt', const Color(0xFF22C55E)),
                            _legendDot('● Bool', const Color(0xFFEF4444)),
                          ],
                        ),
                      ),
                    ] else
                      const Spacer(),
                    InkWell(
                      key: const ValueKey('ue_graph_fit_toggle'),
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        setState(() => _fitToWidth = !_fitToWidth);
                        _scheduleWireMeasure();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: _fitToWidth
                              ? const Color(0xFF0E293D)
                              : const Color(0xFF161E2E),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _fitToWidth
                                ? const Color(0xFF38BDF8).withValues(alpha: 0.5)
                                : const Color(0xFF334155),
                          ),
                        ),
                        child: Text(
                          _fitToWidth ? 'Fit' : '1:1',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _fitToWidth
                                ? const Color(0xFF7DD3FC)
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Graph Surface
          LayoutBuilder(
            builder: (context, vpCons) {
              final stage = SizedBox(
                width: canvasWidth,
                height: canvasHeight,
                child: Stack(
                  key: _stackKey,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _UeGraphGridAndWirePainter(
                          wires: _resolvedWires,
                          pinColor: _pinColor,
                        ),
                      ),
                    ),
                    for (int i = 0; i < execNodes.length; i++)
                      Positioned(
                        left: padding + i * (nodeWidth + nodeGapX),
                        top: 18,
                        width: nodeWidth,
                        child: _buildNodeCard(execNodes[i]),
                      ),
                    for (int i = 0; i < pureNodes.length; i++)
                      Positioned(
                        left: padding + i * (nodeWidth + nodeGapX),
                        top: execRowHeight + 24,
                        child: pureNodes[i].kind == UeNodeKind.variableGet
                            ? _buildGetterPill(pureNodes[i])
                            : SizedBox(
                                width: nodeWidth,
                                child: _buildNodeCard(pureNodes[i]),
                              ),
                      ),
                  ],
                ),
              );

              if (_fitToWidth &&
                  vpCons.maxWidth.isFinite &&
                  canvasWidth > vpCons.maxWidth) {
                final scale = (vpCons.maxWidth / canvasWidth).clamp(0.45, 1.0);
                return SizedBox(
                  width: vpCons.maxWidth,
                  height: canvasHeight * scale,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: stage,
                  ),
                );
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: stage,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _legendDot(String text, Color color) {
    return Text(
      text,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 9.5,
        fontWeight: FontWeight.w500,
        color: color.withValues(alpha: 0.85),
      ),
    );
  }

  Widget _buildGetterPill(UeGraphNode node) {
    final outPin = node.rightPins.isNotEmpty
        ? node.rightPins.first
        : const UeGraphPin(id: 'val', label: '', type: UePinType.objectPin);
    final isWired = _isPinWired(node.id, 'out', outPin.id);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF233044), Color(0xFF151923)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            node.title,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFE0F2FE),
            ),
          ),
          const SizedBox(width: 8),
          _buildPinMarker(
            key: _keyForPin(node.id, 'out', outPin.id),
            type: outPin.type,
            isWired: isWired,
          ),
        ],
      ),
    );
  }

  Widget _buildNodeCard(UeGraphNode node) {
    final rowCount = node.leftPins.length > node.rightPins.length
        ? node.leftPins.length
        : node.rightPins.length;

    return Opacity(
      opacity: node.isNewInActiveTask ? 1.0 : 0.62,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF161A23),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: node.isNewInActiveTask
                ? const Color(0xFF34D399)
                : const Color(0xFF334155),
            width: node.isNewInActiveTask ? 1.4 : 1.0,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: _headerColor(node.kind),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(6)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      _headerGlyph(node.kind),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      node.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (node.isNewInActiveTask)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34D399),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'NEW',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF05101A),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                children: [
                  for (int r = 0; r < rowCount; r++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.5),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (r < node.leftPins.length)
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildPinMarker(
                                    key: _keyForPin(
                                      node.id,
                                      'in',
                                      node.leftPins[r].id,
                                    ),
                                    type: node.leftPins[r].type,
                                    isWired: _isPinWired(
                                      node.id,
                                      'in',
                                      node.leftPins[r].id,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      node.leftPins[r].label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 10.5,
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                  ),
                                  if (node.leftPins[r].inlineLiteral != null) ...[
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF090D16),
                                          borderRadius:
                                              BorderRadius.circular(3),
                                          border: Border.all(
                                            color: const Color(0xFF334155),
                                          ),
                                        ),
                                        child: Text(
                                          node.leftPins[r].inlineLiteral!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 9,
                                            color: const Color(0xFFFDE68A),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            )
                          else
                            const SizedBox.shrink(),
                          if (r < node.rightPins.length)
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      node.rightPins[r].label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 10.5,
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  _buildPinMarker(
                                    key: _keyForPin(
                                      node.id,
                                      'out',
                                      node.rightPins[r].id,
                                    ),
                                    type: node.rightPins[r].type,
                                    isWired: _isPinWired(
                                      node.id,
                                      'out',
                                      node.rightPins[r].id,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            const SizedBox.shrink(),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinMarker({
    required GlobalKey key,
    required UePinType type,
    required bool isWired,
  }) {
    return SizedBox(
      key: key,
      width: type == UePinType.exec ? 12 : 13,
      height: 11,
      child: CustomPaint(
        painter: _UePinIconPainter(
          type: type,
          color: _pinColor(type),
          isWired: isWired,
        ),
      ),
    );
  }
}

class _UePinIconPainter extends CustomPainter {
  final UePinType type;
  final Color color;
  final bool isWired;

  _UePinIconPainter({
    required this.type,
    required this.color,
    required this.isWired,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()
      ..color = isWired ? color : const Color(0xFF11141B)
      ..style = PaintingStyle.fill;

    if (type == UePinType.exec) {
      // Authentic UE5 white directional pentagon chevron (`▷` / `►`)
      final path = Path()
        ..moveTo(1.2, 1.2)
        ..lineTo(size.width * 0.56, 1.2)
        ..lineTo(size.width - 1.0, size.height / 2)
        ..lineTo(size.width * 0.56, size.height - 1.2)
        ..lineTo(1.2, size.height - 1.2)
        ..close();
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
      return;
    }

    // UE5 Data pin: circle + small right-pointing arrow pointer (`●▸`)
    final cy = size.height / 2;
    final center = Offset(size.height * 0.42, cy);
    final radius = size.height * 0.34;
    canvas.drawCircle(center, radius, fillPaint);
    canvas.drawCircle(center, radius, strokePaint);

    final arrow = Path()
      ..moveTo(center.dx + radius + 1.4, cy - 2.0)
      ..lineTo(size.width - 0.6, cy)
      ..lineTo(center.dx + radius + 1.4, cy + 2.0)
      ..close();
    canvas.drawPath(arrow, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _UePinIconPainter oldDelegate) =>
      oldDelegate.type != type ||
      oldDelegate.color != color ||
      oldDelegate.isWired != isWired;
}

class _UeGraphGridAndWirePainter extends CustomPainter {
  final List<({Offset from, Offset to, UePinType type, bool isNew})> wires;
  final Color Function(UePinType) pinColor;

  _UeGraphGridAndWirePainter({
    required this.wires,
    required this.pinColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0x0DFFFFFF)
      ..strokeWidth = 1.0;
    const double step = 20;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (final w in wires) {
      final dx = ((w.to.dx - w.from.dx).abs() * 0.5).clamp(36.0, 140.0);
      final path = Path()
        ..moveTo(w.from.dx, w.from.dy)
        ..cubicTo(
          w.from.dx + dx,
          w.from.dy,
          w.to.dx - dx,
          w.to.dy,
          w.to.dx,
          w.to.dy,
        );
      if (w.isNew && w.type == UePinType.exec) {
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0x3310B981)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5.5
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = pinColor(w.type)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w.type == UePinType.exec ? 2.4 : 1.9
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _UeGraphGridAndWirePainter oldDelegate) =>
      oldDelegate.wires != wires;
}
