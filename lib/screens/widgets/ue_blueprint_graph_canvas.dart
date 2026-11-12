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

enum UeNodeKind { event, functionCall, pureMath, branch, variableSet, delay }

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

/// Renders an Unreal Engine 5 Blueprint Event Graph with color-coded Node Cards
/// and cubic Bezier pin-to-pin wires (`CustomPainter`), supporting dimmed prior-task
/// nodes and glowing emerald `+ NEW` nodes for the active task.
class UeBlueprintGraphCanvas extends StatefulWidget {
  final List<UeGraphNode> nodes;
  final List<UeGraphWire> wires;

  const UeBlueprintGraphCanvas({
    super.key,
    required this.nodes,
    required this.wires,
  });

  /// Parses Unreal Blueprint Event Graph text (`[Event] ──► [Branch]`) into
  /// structured `UeGraphNode`s and `UeGraphWire`s for visual rendering.
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

      String? linePrevId;
      for (int mIdx = 0; mIdx < matches.length; mIdx++) {
        final rawLabel = matches[mIdx].group(1)!.trim();
        final nodeId = 'n_${lIdx}_$mIdx';
        if (!seenIds.add(nodeId)) continue;

        final lower = rawLabel.toLowerCase();
        final UeNodeKind kind;
        if (lower.startsWith('event') ||
            lower.startsWith('ia_') ||
            lower.contains('input')) {
          kind = UeNodeKind.event;
        } else if (lower.startsWith('branch') || lower.startsWith('sequence')) {
          kind = UeNodeKind.branch;
        } else if (lower.startsWith('set ')) {
          kind = UeNodeKind.variableSet;
        } else if (lower.contains('delay')) {
          kind = UeNodeKind.delay;
        } else if (lower.startsWith('get ') ||
            lower.contains('multiply') ||
            lower.contains('forward')) {
          kind = UeNodeKind.pureMath;
        } else {
          kind = UeNodeKind.functionCall;
        }

        final parenIdx = rawLabel.indexOf('(');
        final title = parenIdx > 0
            ? rawLabel.substring(0, parenIdx).trim()
            : rawLabel;
        final sub = parenIdx > 0
            ? rawLabel
                .substring(parenIdx + 1)
                .replaceAll(RegExp(r'\)$'), '')
                .trim()
            : '';

        final leftPins = <UeGraphPin>[
          if (kind != UeNodeKind.event && kind != UeNodeKind.pureMath)
            const UeGraphPin(id: 'exec', label: 'Exec', type: UePinType.exec),
          if (kind == UeNodeKind.branch)
            const UeGraphPin(
              id: 'cond',
              label: 'Condition',
              type: UePinType.boolPin,
            ),
          if (kind == UeNodeKind.delay)
            UeGraphPin(
              id: 'dur',
              label: 'Duration',
              type: UePinType.floatPin,
              inlineLiteral: sub.isNotEmpty ? sub : '0.45',
            ),
        ];

        final rightPins = <UeGraphPin>[
          if (kind == UeNodeKind.branch) ...[
            const UeGraphPin(id: 'true', label: 'True', type: UePinType.exec),
            const UeGraphPin(id: 'false', label: 'False', type: UePinType.exec),
          ] else if (kind != UeNodeKind.pureMath) ...[
            UeGraphPin(
              id: 'then',
              label: kind == UeNodeKind.event
                  ? 'Started'
                  : (kind == UeNodeKind.delay ? 'Completed' : 'Then'),
              type: UePinType.exec,
            ),
          ] else ...[
            const UeGraphPin(
              id: 'val',
              label: 'Return',
              type: UePinType.vectorPin,
            ),
          ],
        ];

        nodes.add(
          UeGraphNode(
            id: nodeId,
            title: title,
            subtitle: sub,
            kind: kind,
            isNewInActiveTask: markAllNew,
            leftPins: leftPins,
            rightPins: rightPins,
          ),
        );

        final sourceId = linePrevId ?? (mIdx == 0 ? prevExecNodeId : null);
        if (sourceId != null && kind != UeNodeKind.pureMath) {
          final sourceNode = nodes.firstWhere((n) => n.id == sourceId);
          final fromPin = sourceNode.rightPins.isNotEmpty
              ? sourceNode.rightPins.first.id
              : 'then';
          wires.add(
            UeGraphWire(
              fromNodeId: sourceId,
              fromPinId: fromPin,
              toNodeId: nodeId,
              toPinId: 'exec',
              type: UePinType.exec,
              isNew: markAllNew,
            ),
          );
        }

        if (kind != UeNodeKind.pureMath) {
          linePrevId = nodeId;
          prevExecNodeId = nodeId;
        }
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
      case UeNodeKind.branch:
        return const Color(0xFF334155);
      case UeNodeKind.variableSet:
        return const Color(0xFF881337);
      case UeNodeKind.delay:
        return const Color(0xFF155E75);
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

    const double nodeWidth = 215;
    const double nodeGapX = 48;
    const double padding = 18;
    final execNodes =
        widget.nodes.where((n) => n.kind != UeNodeKind.pureMath).toList();
    final pureNodes =
        widget.nodes.where((n) => n.kind == UeNodeKind.pureMath).toList();

    final cols = execNodes.isNotEmpty ? execNodes.length : widget.nodes.length;
    final canvasWidth =
        padding * 2 + cols * nodeWidth + (cols - 1).clamp(0, 20) * nodeGapX;
    final canvasHeight = pureNodes.isNotEmpty ? 300.0 : 185.0;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF11141B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF24324B)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
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
                  top: 22,
                  width: nodeWidth,
                  child: _buildNodeCard(execNodes[i]),
                ),
              for (int i = 0; i < pureNodes.length; i++)
                Positioned(
                  left: padding + i * (nodeWidth + nodeGapX),
                  top: 175,
                  width: nodeWidth,
                  child: _buildNodeCard(pureNodes[i]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNodeCard(UeGraphNode node) {
    final rowCount = node.leftPins.length > node.rightPins.length
        ? node.leftPins.length
        : node.rightPins.length;

    return Opacity(
      opacity: node.isNewInActiveTask ? 1.0 : 0.58,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF161A23),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: node.isNewInActiveTask
                ? const Color(0xFF34D399)
                : const Color(0xFF334155),
            width: node.isNewInActiveTask ? 1.5 : 1.0,
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        if (node.subtitle.isNotEmpty)
                          Text(
                            node.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              fontStyle: FontStyle.italic,
                              color: Colors.white70,
                            ),
                          ),
                      ],
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
                        '+ NEW',
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
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF090D16),
                                        borderRadius: BorderRadius.circular(3),
                                        border: Border.all(
                                          color: const Color(0xFF334155),
                                        ),
                                      ),
                                      child: Text(
                                        node.leftPins[r].inlineLiteral!,
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 9,
                                          color: const Color(0xFFFDE68A),
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

  Widget _buildPinMarker({required GlobalKey key, required UePinType type}) {
    final color = _pinColor(type);
    return Container(
      key: key,
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: type == UePinType.exec ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: type == UePinType.exec ? BorderRadius.circular(2) : null,
      ),
    );
  }
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
    const double step = 24;
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
          ..strokeWidth = w.type == UePinType.exec ? 2.4 : 1.8
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _UeGraphGridAndWirePainter oldDelegate) =>
      oldDelegate.wires != wires;
}
