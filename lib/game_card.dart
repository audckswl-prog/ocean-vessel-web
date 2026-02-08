import 'dart:math';
import 'package:flutter/material.dart';

enum BuffType {
  fuelEfficiency, // 연료 효율 (소모 속도)
  durability,     // 내구도 (피격 시 소모량)
  speed,          // 속도 (거리 증가량)
  critical,       // 크리티컬 (정답 시 거리 보너스)
}

class GameBuff {
  final BuffType type;
  final double value; // -30 (-0.3) to +40 (+0.4)

  GameBuff({required this.type, required this.value});

  String get title {
    switch (type) {
      case BuffType.fuelEfficiency:
        return '연료 효율';
      case BuffType.durability:
        return '내구도';
      case BuffType.speed:
        return '항해 속도';
      case BuffType.critical:
        return '크리티컬';
    }
  }

  String get description {
    final percent = (value * 100).round();
    final sign = value >= 0 ? '+' : '';
    return '$sign$percent%'; 
  }

  String get effectDescription {
    switch (type) {
      case BuffType.fuelEfficiency:
        return '연료 소모 속도가 변화합니다.';
      case BuffType.durability:
        return '오답 시 연료 피해량이 변화합니다.';
      case BuffType.speed:
        return '기본 항해 속도가 변화합니다.';
      case BuffType.critical:
        return '정답 시 획득 거리가 변화합니다.';
    }
  }

  Color get color {
    switch (type) {
      case BuffType.fuelEfficiency:
        return Colors.greenAccent;
      case BuffType.durability:
        return Colors.blueAccent;
      case BuffType.speed:
        return Colors.orangeAccent;
      case BuffType.critical:
        return Colors.purpleAccent;
    }
  }

  IconData get icon {
    switch (type) {
      case BuffType.fuelEfficiency:
        return Icons.local_gas_station;
      case BuffType.durability:
        return Icons.shield;
      case BuffType.speed:
        return Icons.speed;
      case BuffType.critical:
        return Icons.auto_awesome;
    }
  }
}

class CardOverlay extends StatefulWidget {
  final Function(GameBuff) onCardSelected;

  const CardOverlay({super.key, required this.onCardSelected});

  @override
  State<CardOverlay> createState() => _CardOverlayState();
}

class _CardOverlayState extends State<CardOverlay> with TickerProviderStateMixin {
  late List<GameBuff> _buffs;
  int? _selectedIndex;
  bool _isFlipping = false;
  late AnimationController _entranceController;
  late List<Animation<double>> _cardAnimations;

  @override
  void initState() {
    super.initState();
    _generateBuffs();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _cardAnimations = List.generate(3, (index) {
      // Staggered entrance for each card
      final start = index * 0.15;
      final end = start + 0.6;
      return CurvedAnimation(
        parent: _entranceController,
        curve: Interval(
          start,
          end > 1.0 ? 1.0 : end,
          curve: Curves.elasticOut,
        ),
      );
    });

    // Start the entrance animation immediately
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  void _generateBuffs() {
    final random = Random();
    // Weighted selection logic
    // Fuel Efficiency: 30%, Durability: 30%, Critical: 30%, Speed: 10%
    final types = [
      ...List.filled(3, BuffType.fuelEfficiency),
      ...List.filled(3, BuffType.durability),
      ...List.filled(3, BuffType.critical),
      BuffType.speed,
    ];
    
    // -30% to +40% in 10% steps: -30, -20, -10, 10, 20, 30, 40
    final values = [-0.3, -0.2, -0.1, 0.1, 0.2, 0.3, 0.4];

    _buffs = List.generate(3, (index) {
      final type = types[random.nextInt(types.length)];
      final value = values[random.nextInt(values.length)];
      return GameBuff(type: type, value: value);
    });
  }

  void _handleCardTap(int index) {
    if (_isFlipping || _selectedIndex != null) return;

    setState(() {
      _selectedIndex = index;
      _isFlipping = true;
    });

    // 애니메이션 및 확인 시간을 위해 잠시 대기 후 콜백 실행
    Future.delayed(const Duration(seconds: 2), () {
      widget.onCardSelected(_buffs[index]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(3, (index) {
                return AnimatedBuilder(
                  animation: _entranceController,
                  builder: (context, child) {
                    final value = _cardAnimations[index].value;
                    return Opacity(
                      opacity: value.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: value,
                        child: child,
                      ),
                    );
                  },
                  child: _FlipCard(
                    buff: _buffs[index],
                    isSelected: _selectedIndex == index,
                    isOtherSelected: _selectedIndex != null && _selectedIndex != index,
                    onTap: () => _handleCardTap(index),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlipCard extends StatefulWidget {
  final GameBuff buff;
  final bool isSelected;
  final bool isOtherSelected;
  final VoidCallback onTap;

  const _FlipCard({
    required this.buff,
    required this.isSelected,
    required this.isOtherSelected,
    required this.onTap,
  });

  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutBack),
    );
  }

  @override
  void didUpdateWidget(_FlipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final cardWidth = (screenSize.width / 3) - 15;
    // Ensure card height doesn't exceed screen height significantly
    final cardHeight = min(cardWidth * 1.7, screenSize.height * 0.75);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: widget.isOtherSelected ? 0.3 : 1.0,
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            final angle = _animation.value * pi;
            final isBack = angle >= pi / 2;
            
            return Transform(
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(angle),
              alignment: Alignment.center,
              child: isBack
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(pi),
                      child: _buildFront(cardWidth, cardHeight), 
                    )
                  : _buildBack(cardWidth, cardHeight), 
            );
          },
        ),
      ),
    );
  }

  Widget _buildBack(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF1A237E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyanAccent, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.cyan, blurRadius: 10),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.question_mark,
          size: width * 0.5,
          color: Colors.grey.withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _buildFront(double width, double height) {
    // Special Effects Logic
    BoxDecoration decoration = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: widget.buff.color, width: 5),
      boxShadow: [BoxShadow(color: widget.buff.color, blurRadius: 15)],
    );

    // Speed Card Effect (Rare)
    if (widget.buff.type == BuffType.speed) {
      decoration = decoration.copyWith(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFFFF9C4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: Colors.orangeAccent.withOpacity(0.8), blurRadius: 25, spreadRadius: 5),
        ],
        border: Border.all(color: Colors.amber, width: 6),
      );
    }

    // High Value Effect (+40%)
    if (widget.buff.value >= 0.4) {
      decoration = decoration.copyWith(
        boxShadow: [
          const BoxShadow(color: Colors.amber, blurRadius: 30, spreadRadius: 5),
        ],
        border: Border.all(color: Colors.amberAccent, width: 8),
      );
    }

    // Bad Value Effect (-30%)
    if (widget.buff.value <= -0.3) {
      decoration = decoration.copyWith(
        color: const Color(0xFFE0E0E0), // Slightly greyed out
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.8), blurRadius: 20, spreadRadius: 2),
        ],
        border: Border.all(color: Colors.grey, width: 6),
      );
    }

    return Container(
      width: width,
      height: height,
      decoration: decoration,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final iconSize = min(constraints.maxHeight * 0.3, 50.0);
          final titleSize = min(constraints.maxHeight * 0.1, 18.0);
          final descSize = min(constraints.maxHeight * 0.15, 28.0);
          // Increased font size slightly
          final effectDescSize = min(constraints.maxHeight * 0.06, 13.0); 

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Speed Card "RARE" Label
              if (widget.buff.type == BuffType.speed)
                const Padding(
                  padding: EdgeInsets.only(bottom: 5),
                  child: Text('RARE', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, letterSpacing: 2)),
                ),
              
              Icon(widget.buff.icon, size: iconSize, color: Colors.black87),
              SizedBox(height: constraints.maxHeight * 0.03),
              Text(
                widget.buff.title,
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: titleSize,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: constraints.maxHeight * 0.02),
              Text(
                widget.buff.description,
                style: TextStyle(
                  color: widget.buff.value >= 0 ? Colors.green[700] : Colors.red[700],
                  fontWeight: FontWeight.bold,
                  fontSize: descSize,
                ),
              ),
              SizedBox(height: constraints.maxHeight * 0.05),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  widget.buff.effectDescription,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: effectDescSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          );
        }
      ),
    );
  }
}
