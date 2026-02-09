import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:ocean_vessel/game_card.dart';
import 'package:ocean_vessel/submarine_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ocean Vessel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  // --- Lifecycle and Animation State ---
  bool _isBooting = false;
  bool _isGameActive = false;
  
  late final AnimationController _idleController;
  late final AnimationController _bootController;
  late final AnimationController _zoomController;
  late final AnimationController _pulseController;

  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  // --- Quiz State & Game Mechanics ---
  String _question = '';
  late String _correctAnswer;
  List<String> _answers = [];
  final Random _random = Random();
  bool _isHardQuestion = false;
  int _distance = 0;
  double _fuel = 1.0;
  bool _isGameOver = false;
  late SharedPreferences _prefs;
  int _highScore = 0;
  int _fuelEfficiencyLevel = 0;
  int _damageReductionLevel = 0;
  int _speedIncreaseLevel = 0;
  int _comboCounter = 0;
  Timer? _comboResetTimer;
  bool _isDashing = false;
  Timer? _dashTimer;
  bool _showDamageEffect = false;
  Timer? _damageEffectTimer;
  bool _showComboEffect = false;
  Timer? _comboEffectTimer;
  bool _showCardOverlay = false;
  int _nextCardDistance = 500;
  double _sessionFuelEfficiencyMult = 1.0;
  double _sessionDamageMult = 1.0;
  double _sessionSpeedMult = 1.0;
  double _sessionCriticalMult = 1.0;
  Timer? _gameLoopTimer;
  late final AnimationController _backgroundAnimationController;
  late final AnimationController _submarineAnimationController;
  DateTime? _sessionStartTime;
  DateTime? _questionStartTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _backgroundAnimationController = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
    _submarineAnimationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..repeat(reverse: true);

    _idleController = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat(reverse: true);
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

    _bootController = AnimationController(vsync: this, duration: const Duration(milliseconds: 3500));
    _bootController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) _zoomController.forward();
      }
    });

    _zoomController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 3.0).animate(CurvedAnimation(parent: _zoomController, curve: Curves.easeIn));
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(parent: _zoomController, curve: Curves.easeIn));
    _zoomController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _beginGame();
      }
    });

    _loadInitialData();
  }
  
  void _triggerBootSequence() {
    if (_bootController.status == AnimationStatus.dismissed) {
      setState(() {
        _isBooting = true;
      });
      _bootController.forward();
    }
  }

  void _beginGame() {
    setState(() {
      _isGameActive = true;
    });
    _zoomController.reverse();
    _generateQuestion();
    _startGameLoop();
  }

  @override
  void dispose() {
    _idleController.dispose();
    _bootController.dispose();
    _zoomController.dispose();
    _pulseController.dispose();
    _backgroundAnimationController.dispose();
    _submarineAnimationController.dispose();
    _gameLoopTimer?.cancel();
    _comboResetTimer?.cancel();
    _dashTimer?.cancel();
    _damageEffectTimer?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    const oceanColor = Color(0xFF010014);
    const screenSize = Size(1920, 1080); // 기준 해상도로 고정

    return Scaffold(
      backgroundColor: oceanColor,
      body: Center( // 화면 중앙 정렬
        child: FittedBox(
          fit: BoxFit.contain, // 비율 유지하면서 화면에 꽉 차게
          child: SizedBox(
            width: screenSize.width, // 기준 해상도 고정
            height: screenSize.height,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: SafeArea(
                  child: Stack(
                    children: [
                      if (_isGameActive)
                        IgnorePointer(
                          child: Column(
                            children: [
                              const Expanded(child: SizedBox.shrink()),
                              Expanded(
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                     if (!_isGameOver)
                                      RepaintBoundary(child: _ParallaxBackground(controller: _backgroundAnimationController, isDashing: _isDashing, vsync: this)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (_isGameOver)
                        ..._buildGameOverUI(context, screenSize)
                      else if (_isGameActive)
                        ..._buildInGameUI(context, screenSize, 150, 160)
                      else
                        _buildBootUI(context),
                        
                      if (_isGameActive) ...[
                        AnimatedOpacity(opacity: _showDamageEffect ? 1.0 : 0.0, duration: const Duration(milliseconds: 200), child: IgnorePointer(child: Stack(children: [_buildVignette(Alignment.centerLeft, Alignment.centerRight, Colors.red), _buildVignette(Alignment.centerRight, Alignment.centerLeft, Colors.red), _buildVignette(Alignment.topCenter, Alignment.bottomCenter, Colors.red), _buildVignette(Alignment.bottomCenter, Alignment.topCenter, Colors.red)]))),
                        AnimatedOpacity(opacity: _showComboEffect ? 1.0 : 0.0, duration: const Duration(milliseconds: 300), child: IgnorePointer(child: Stack(children: [_buildVignette(Alignment.centerLeft, Alignment.centerRight, Colors.cyanAccent, stop: 0.075), _buildVignette(Alignment.centerRight, Alignment.centerLeft, Colors.cyanAccent, stop: 0.075), _buildVignette(Alignment.topCenter, Alignment.bottomCenter, Colors.amberAccent, stop: 0.075), _buildVignette(Alignment.bottomCenter, Alignment.topCenter, Colors.amberAccent, stop: 0.075)]))),
                        if (_showCardOverlay) CardOverlay(onCardSelected: _applyCardEffect),
                        if (!_isGameOver) IgnorePointer(child: CustomPaint(size: Size.infinite, painter: HudPainter())),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBootUI(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: Listenable.merge([_idleController, _bootController]),
          builder: (context, child) {
            return RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: CockpitViewPainter(
                  idleProgress: _idleController.value,
                  bootProgress: _bootController.value,
                ),
              ),
            );
          },
        ),
        if (!_isBooting)
          Center(
            child: GestureDetector(
              onTap: _triggerBootSequence,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final pulseValue = _pulseController.value;
                  return Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Colors.lightBlueAccent, Colors.cyanAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.cyanAccent.withOpacity(0.7 * pulseValue),
                          blurRadius: 20.0 + (10 * pulseValue),
                          spreadRadius: 5.0 + (5 * pulseValue),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        'START',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                          shadows: const [
                            // White shadow above and to the left
                            Shadow(
                              offset: Offset(-1, -1),
                              blurRadius: 1.0,
                              color: Colors.white70,
                            ),
                            // Darker shadow below and to the right
                            Shadow(
                              offset: Offset(1, 1),
                              blurRadius: 1.0,
                              color: Colors.black38,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  void _loadInitialData() async {
    final data = await _initSharedPreferences();
    setState(() {
      _highScore = data['highScore'] as int;
      _fuelEfficiencyLevel = data['fuelEfficiencyLevel'] as int;
      _damageReductionLevel = data['damageReductionLevel'] as int;
      _speedIncreaseLevel = data['speedIncreaseLevel'] as int;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sessionStartTime = DateTime.now();
    else if (state == AppLifecycleState.paused && _sessionStartTime != null) {
      final duration = DateTime.now().difference(_sessionStartTime!);
      final totalSeconds = _prefs.getInt('totalUsageSeconds') ?? 0;
      _prefs.setInt('totalUsageSeconds', totalSeconds + duration.inSeconds);
      _sessionStartTime = null;
    }
  }

  Future<Map<String, dynamic>> _initSharedPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    return {'highScore': _prefs.getInt('highScore') ?? 0, 'fuelEfficiencyLevel': _prefs.getInt('upgrade_fuel_efficiency') ?? 0, 'damageReductionLevel': _prefs.getInt('upgrade_damage_reduction') ?? 0, 'speedIncreaseLevel': _prefs.getInt('upgrade_speed_increase') ?? 0};
  }

  Future<void> _submitScoreToFirestore(String nickname, int score) async {
    if (score <= 0) return;
    try { await FirebaseFirestore.instance.collection('global_rankings').add({'nickname': nickname, 'score': score, 'timestamp': FieldValue.serverTimestamp()}); } 
    catch (e) { debugPrint('Error submitting score: $e'); }
  }

  Future<void> _checkRankingAndShowDialog() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('global_rankings').orderBy('score', descending: true).limit(5).get();
      bool qualifies = snapshot.docs.length < 5 || _distance > (snapshot.docs.last.data()['score'] as int);
      if (qualifies && mounted) _showNicknameDialog();
    } catch (e) { debugPrint('Error checking rankings: $e'); }
  }

  void _showNicknameDialog() {
    final TextEditingController nicknameController = TextEditingController();
    showDialog(context: context, barrierDismissible: false, builder: (context) => AlertDialog(backgroundColor: const Color(0xFF0D47A1), title: const Text('New High Score!', style: TextStyle(color: Colors.amber)), content: Column(mainAxisSize: MainAxisSize.min, children: [Text('Your distance: ${_distance}m', style: const TextStyle(color: Colors.white)), const SizedBox(height: 16), TextField(controller: nicknameController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Nickname', labelStyle: TextStyle(color: Colors.cyanAccent), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.amber))), maxLength: 10)]), actions: [TextButton(onPressed: () { final nickname = nicknameController.text.trim(); if (nickname.isNotEmpty) { _submitScoreToFirestore(nickname, _distance); Navigator.pop(context); }}, child: const Text('Submit', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)))]));
  }
  
  void _generateQuestion() {
    _isHardQuestion = false; _questionStartTime = DateTime.now(); final op = _random.nextInt(4);
    switch (op) {
      case 0: final n1 = _random.nextInt(90) + 10, n2 = _random.nextInt(90) + 10; _correctAnswer = (n1 + n2).toString(); _question = '$n1 + $n2 = ?'; break;
      case 1: int n1 = _random.nextInt(90) + 10, n2 = _random.nextInt(90) + 10; if (n1 < n2) { (n1, n2) = (n2, n1); } _correctAnswer = (n1 - n2).toString(); _question = '$n1 - $n2 = ?'; break;
      case 2: int n1, n2; if (_random.nextDouble() > 0.7) { n1 = _random.nextInt(16) + 10; n2 = _random.nextInt(16) + 10; _isHardQuestion = true; } else { n1 = _random.nextInt(90) + 10; n2 = _random.nextInt(8) + 2; } _correctAnswer = (n1 * n2).toString(); _question = '$n1 × $n2 = ?'; break;
      case 3: final n2 = _random.nextInt(8) + 2, n1 = (_random.nextInt(30) + 10) * n2 + _random.nextInt(n2); _correctAnswer = '${n1 ~/ n2} … ${n1 % n2}'; _question = '$n1 ÷ $n2 = ?'; break;
    }
    _answers = [_correctAnswer];
    while (_answers.length < 3) {
      String wrongAnswer;
      if (op < 3) { int val = int.parse(_correctAnswer), offset = _random.nextInt(20) + 1 - 10; if (offset == 0) offset = 10; wrongAnswer = (val + offset).toString(); } else { final parts = _correctAnswer.split(' … '); int q = int.parse(parts[0]), r = int.parse(parts[1]); wrongAnswer = '${max(0, q + _random.nextInt(5) - 2)} … ${max(0, r + _random.nextInt(3) - 1)}'; }
      if (!_answers.contains(wrongAnswer)) _answers.add(wrongAnswer);
    }
    _answers.shuffle(); _startComboTimer();
  }

  void _startComboTimer() { _comboResetTimer?.cancel(); _comboResetTimer = Timer(const Duration(seconds: 5), () => setState(() => _comboCounter = 0)); }

  void _checkAnswer(String selectedAnswer) {
    if (_isGameOver) return;
    _comboResetTimer?.cancel();
    setState(() {
      if (selectedAnswer == _correctAnswer) {
        _fuel = min(1.0, _fuel + 0.15); _comboCounter = min(_comboCounter + 1, 4); _distance += (50 * max(0.1, _sessionCriticalMult)).toInt();
        bool isFast = _questionStartTime != null && DateTime.now().difference(_questionStartTime!).inSeconds <= 5;
        if (_isHardQuestion || isFast) {
          _distance += 100; _isDashing = true;
          _dashTimer?.cancel(); _dashTimer = Timer(const Duration(seconds: 3), () => setState(() => _isDashing = false));
          _showComboEffect = true; _comboEffectTimer?.cancel(); _comboEffectTimer = Timer(const Duration(milliseconds: 600), () => setState(() => _showComboEffect = false));
        }
        _generateQuestion();
      } else {
        final damage = (0.2 * pow(0.99, _damageReductionLevel)) / max(0.1, _sessionDamageMult);
        _fuel = max(0.0, _fuel - damage); _comboCounter = 0; _showDamageEffect = true;
        _damageEffectTimer?.cancel(); _damageEffectTimer = Timer(const Duration(milliseconds: 500), () => setState(() => _showDamageEffect = false));
        _generateQuestion();
      }
    });
  }

  void _resetSessionModifiers() { _sessionFuelEfficiencyMult = 1.0; _sessionDamageMult = 1.0; _sessionSpeedMult = 1.0; _sessionCriticalMult = 1.0; _nextCardDistance = 500; }

  void _triggerCardSelection() { _gameLoopTimer?.cancel(); _comboResetTimer?.cancel(); _dashTimer?.cancel(); _backgroundAnimationController.stop(); _submarineAnimationController.stop(); setState(() => _showCardOverlay = true); }

  void _applyCardEffect(GameBuff buff) {
    setState(() {
      switch (buff.type) {
        case BuffType.fuelEfficiency: _sessionFuelEfficiencyMult += buff.value; break;
        case BuffType.durability: _sessionDamageMult += buff.value; break;
        case BuffType.speed: _sessionSpeedMult += buff.value; break;
        case BuffType.critical: _sessionCriticalMult += buff.value; break;
      }
      _showCardOverlay = false; _backgroundAnimationController.repeat(); _submarineAnimationController.repeat(reverse: true); _startGameLoop();
      if (_comboCounter > 0) _startComboTimer();
      _nextCardDistance += 500;
    });
  }

  void _startGameLoop() { _gameLoopTimer = Timer.periodic(const Duration(seconds: 1), (timer) => _gameLoop()); }

  void _gameLoop() {
    if (_fuel <= 0 && !_isGameOver) {
      setState(() {
        _isGameOver = true; _fuel = 0; _comboCounter = 0;
        if (_distance > _highScore) { _highScore = _distance; _prefs.setInt('highScore', _highScore); }
        WidgetsBinding.instance.addPostFrameCallback((_) => _checkRankingAndShowDialog());
        final credits = _prefs.getInt('credits') ?? 0; _prefs.setInt('credits', credits + (_distance / 3).toInt());
      });
      _gameLoopTimer?.cancel(); _comboResetTimer?.cancel(); _dashTimer?.cancel(); _backgroundAnimationController.stop(); _submarineAnimationController.stop();
      return;
    }
    if (!_isGameOver) {
      if (_distance >= _nextCardDistance) { _triggerCardSelection(); return; }
      int diffLvl = _distance ~/ 1000;
      double diffMult = (diffLvl<2)?pow(1.15,diffLvl).toDouble():(diffLvl<3)?(pow(1.15,1).toDouble()*pow(1.3,diffLvl-1).toDouble()):(diffLvl<5)?(pow(1.15,1).toDouble()*pow(1.3,1).toDouble()*pow(1.4,diffLvl-2).toDouble()):(pow(1.15,1).toDouble()*pow(1.3,1).toDouble()*pow(1.4,2).toDouble()*pow(2.0,diffLvl-4).toDouble());
      double consumption = (1/50)*diffMult*pow(.99,_fuelEfficiencyLevel)*.56/max(.1,1+(_sessionFuelEfficiencyMult-1));
      double speed = (5*pow(1.01,_speedIncreaseLevel)*max(.1,1+(_sessionSpeedMult-1)));
      setState(() { _fuel = max(0.0, _fuel - consumption); _distance += (speed * (_comboCounter > 1 ? _comboCounter : 1)).toInt(); });
    }
  }

  void _resetGame() {
    _resetSessionModifiers();
    setState(() { _distance = 0; _fuel = 1.0; _isGameOver = false; _isGameActive = true; _comboCounter = 0; });
    _backgroundAnimationController.repeat(); _submarineAnimationController.repeat(reverse: true);
    _generateQuestion(); _startGameLoop();
  }

  List<Widget> _buildGameOverUI(BuildContext context, Size screenSize) => [Align(alignment:Alignment.topCenter,child:Padding(padding:EdgeInsets.only(top:screenSize.height*.15),child:Column(mainAxisSize:MainAxisSize.min,mainAxisAlignment:MainAxisAlignment.center,children:[const Text('GAME OVER', style: TextStyle(fontSize: 48, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),const SizedBox(height: 10),RichText(textAlign:TextAlign.center,text:TextSpan(children:[const TextSpan(text:'이동거리: ',style:TextStyle(fontSize:20,color:Colors.white70)),TextSpan(text:'${_distance}m',style:const TextStyle(fontSize:32,color:Colors.white,fontWeight:FontWeight.bold))])),const SizedBox(height: 30),ElevatedButton(onPressed:_resetGame,style:ElevatedButton.styleFrom(padding:const EdgeInsets.symmetric(horizontal:50,vertical:15),backgroundColor:Colors.deepOrangeAccent,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(30))),child:const Text('Play Again',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:Colors.white)))]))),Align(alignment:Alignment.bottomCenter,child:Container(width:350,height:280,margin:const EdgeInsets.only(bottom:80),padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:Colors.black.withOpacity(0.5),borderRadius:BorderRadius.circular(16),border:Border.all(color:Colors.cyanAccent,width:2)),child:Column(children:[const Text('게시판', style: TextStyle(color: Colors.cyanAccent, fontSize: 22, fontWeight: FontWeight.bold)),const SizedBox(height: 10),Expanded(child:StreamBuilder<QuerySnapshot>(stream:FirebaseFirestore.instance.collection('global_rankings').orderBy('score',descending:true).limit(5).snapshots(),builder:(context,snapshot){if(snapshot.hasError)return const Center(child:Text('Ranking error.',style:TextStyle(color:Colors.red)));if(snapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator(color:Colors.amber));final docs=snapshot.data?.docs??[];if(docs.isEmpty)return const Center(child:Text('No records yet.',style:TextStyle(color:Colors.white54)));return ListView.builder(padding:EdgeInsets.zero,itemCount:docs.length,itemBuilder:(context,index){final data=docs[index].data()as Map<String,dynamic>;final isTop=index==0;return Padding(padding:const EdgeInsets.symmetric(vertical:8.0),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Row(children:[Text('${index+1}. ',style:TextStyle(color:isTop?Colors.cyan:Colors.white70,fontWeight:FontWeight.bold,fontSize:isTop?18:16)),Text(data['nickname']??'Anonymous',style:TextStyle(color:isTop?Colors.cyanAccent:Colors.white70,fontWeight:isTop?FontWeight.bold:FontWeight.normal,fontSize:isTop?18:16))]),Text('${data['score']}m',style:TextStyle(color:isTop?Colors.cyanAccent:Colors.white,fontWeight:isTop?FontWeight.bold:FontWeight.normal,fontSize:isTop?18:16))]));});}))])))];
  List<Widget> _buildInGameUI(BuildContext context, Size screenSize, double buttonWidth, double buttonHeight) {
    return [
      Align(alignment: const Alignment(0.0, -0.8), child: Text(_question, style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold))),
      Positioned(
        bottom: screenSize.height / 2,
        left: 0,
        right: 0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _answers.map((answer) => Padding(padding: const EdgeInsets.symmetric(horizontal: 80.0), child: SizedBox(width: buttonWidth, height: buttonHeight, child: Material(shape: CustomCardBorder(borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)), side: BorderSide(color: Colors.grey.withOpacity(0.5), width: 1.5)), color: Colors.transparent, clipBehavior: Clip.antiAlias, child: InkWell(onTap: () => _checkAnswer(answer), customBorder: CustomCardBorder(borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))), child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black, Colors.black, Colors.black.withOpacity(0.1)], stops: const [0.0, 0.15, 1.0])), child: Center(child: Text(answer, style: const TextStyle(color: Colors.white, fontSize: 36, fontFamily: 'monospace', fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 1)))))))).toList(),
        ),
      ),
      Align(alignment: const Alignment(0.0, 0.65), child: RepaintBoundary(child: Submarine(animation: _submarineAnimationController, isDashing: _isDashing))),
      Align(alignment: const Alignment(0.0, 0.2), child: _buildComboIndicator()),
      Positioned(bottom: 20, left: 0, right: 0, child: _buildHUD()),
    ];
  }
  Widget _buildComboIndicator() => AnimatedOpacity(opacity:_comboCounter > 1?1.0:0.0,duration:const Duration(milliseconds:300),child:Text('Combo x$_comboCounter',textAlign:TextAlign.center,style:TextStyle(fontSize:32,color:Colors.amber,fontWeight:FontWeight.bold,shadows:[const Shadow(blurRadius:10.0,color:Colors.amberAccent)])));
    Widget _buildHUD() {
      bool isComboActive = _comboCounter > 1;
      final valueStyle = isComboActive 
          ? const TextStyle(color: Colors.cyanAccent, fontSize: 36, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 8.0, color: Colors.cyan)])
          : const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 8.0)]);
      final labelStyle = TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.normal, shadows: isComboActive ? [] : [const Shadow(blurRadius: 4.0)]);
  
      return Column(
        children: [
          RichText(
            text: TextSpan(
              children: [
                TextSpan(text: '이동거리: ', style: labelStyle),
                TextSpan(text: '${_distance}m', style: valueStyle),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Column(
              children: [
                const Text('연료', style: TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 3)),
                const SizedBox(height: 8),
                Stack(
                  children: [
                    Container(
                      height: 20,
                      decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2), borderRadius: BorderRadius.circular(10)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: _fuel,
                          backgroundColor: Colors.black.withOpacity(0.3),
                          valueColor: AlwaysStoppedAnimation<Color>(Color.lerp(Colors.red, Colors.greenAccent, _fuel)!),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.center,
                      child: Text('${(_fuel * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }
  Widget _buildVignette(Alignment begin,Alignment end,Color color,{double stop=0.3})=>Positioned.fill(child:DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(colors:[color.withOpacity(0.7),Colors.transparent],begin:begin,end:end,stops:[0.0,stop]))));
}

class CockpitViewPainter extends CustomPainter {
  final double idleProgress;
  final double bootProgress;

  CockpitViewPainter({required this.idleProgress, required this.bootProgress});

  Paint _paint(Color color, double opacity, [PaintingStyle style = PaintingStyle.stroke, double strokeWidth = 1.5]) {
    return Paint()..color = color.withOpacity(opacity.clamp(0.0, 1.0))..style = style..strokeWidth = strokeWidth;
  }
  
  @override
  void paint(Canvas canvas, Size size) {
    final idleOpacity = (sin(idleProgress * 2 * pi) / 4) + 0.25;
    
    final dashboardPaint = _paint(Colors.black, 0.9, PaintingStyle.fill);
    final Path dashboardPath = Path()..moveTo(0,size.height*.8)..cubicTo(size.width*.2,size.height*.75,size.width*.8,size.height*.65,size.width,size.height*.7)..lineTo(size.width,size.height)..lineTo(0,size.height)..close();
    canvas.drawPath(dashboardPath, dashboardPaint);
    
    final perspectivePaint = _paint(Colors.cyan, idleOpacity * 0.6, PaintingStyle.stroke, 2.0);
    final Offset vPoint = Offset(size.width / 2, size.height / 2);
    for (int i=0;i<8;i++) {
      final angle=(i/8)*2*pi;
      final edgePoint=Offset(vPoint.dx+cos(angle)*size.width,vPoint.dy+sin(angle)*size.width);
      canvas.drawLine(vPoint,edgePoint,perspectivePaint);
    }
    
    if (bootProgress <= 0) return;

    final double arcProgress = (bootProgress * 2).clamp(0.0, 1.0);
    final arcPaint = _paint(Colors.cyanAccent, arcProgress, PaintingStyle.stroke, 3.0);
    final arcGlowPaint = _paint(Colors.cyanAccent, arcProgress, PaintingStyle.stroke, 6.0)..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3.0);
    Path arcPath = Path()..moveTo(size.width * .2, size.height * .3)..quadraticBezierTo(size.width / 2, size.height * .1, size.width * .8, size.height * .3);
    canvas.drawPath(arcPath, arcGlowPaint);
    ui.PathMetrics pms = arcPath.computeMetrics();
    for (ui.PathMetric pm in pms) {
      canvas.drawPath(pm.extractPath(0.0, pm.length * arcProgress), arcPaint);
      final double flashTrig = (bootProgress - 0.5).clamp(0.0, 1.0);
      if (flashTrig > 0 && flashTrig < 0.2) {
        final double flashProg = flashTrig / 0.2;
        final double flashOp = sin(flashProg * pi);
        final Offset endOfPath = pm.getTangentForOffset(pm.length)!.position;
        final flashPaint = _paint(Colors.yellowAccent, flashOp, PaintingStyle.fill);
        final flashGlow = _paint(Colors.yellow, flashOp * 0.5, PaintingStyle.fill)..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 20.0);
        canvas.drawCircle(endOfPath, 30 * flashProg, flashGlow);
        canvas.drawCircle(endOfPath, 10 * flashProg, flashPaint);
      }
    }
    
    final double hudProgress = ((bootProgress - 0.55) / 0.45).clamp(0.0, 1.0);
    if (hudProgress > 0) {
      final textSpan = TextSpan(text: 'SYSTEM BOOTING...', style: TextStyle(color: Colors.cyanAccent.withOpacity((hudProgress * 2).clamp(0.0, 1.0)), fontSize: 32, fontWeight: FontWeight.w300, shadows: [Shadow(color: Colors.cyanAccent.withOpacity(.5), blurRadius: 10)]));
      final textPainter = TextPainter(text: textSpan, textAlign: TextAlign.center, textDirection: ui.TextDirection.ltr)..layout();
      textPainter.paint(canvas, Offset((size.width - textPainter.width) / 2, size.height * .4));

      final hudPaint = _paint(Colors.cyanAccent, hudProgress);
      const cornerSize = 20.0;
      final hPad = ui.lerpDouble(size.width/2.5,size.width*.1,hudProgress)!;
      final vPad = ui.lerpDouble(size.height/2.5,size.height*.35,hudProgress)!;

      Path tlPath=Path()..moveTo(hPad+cornerSize,vPad)..lineTo(hPad,vPad)..lineTo(hPad,vPad+cornerSize);
      Path trPath=Path()..moveTo(size.width-hPad-cornerSize,vPad)..lineTo(size.width-hPad,vPad)..lineTo(size.width-hPad,vPad+cornerSize);
      Path blPath=Path()..moveTo(hPad,size.height-vPad-cornerSize)..lineTo(hPad,size.height-vPad)..lineTo(hPad+cornerSize,size.height-vPad);
      Path brPath=Path()..moveTo(size.width-hPad,size.height-vPad-cornerSize)..lineTo(size.width-hPad,size.height-vPad)..lineTo(size.width-hPad-cornerSize,size.height-vPad);
      
      canvas.drawPath(tlPath,hudPaint); canvas.drawPath(trPath,hudPaint); canvas.drawPath(blPath,hudPaint); canvas.drawPath(brPath,hudPaint);

      final bool blink = (hudProgress * 10).floor() % 2 == 0;
      canvas.drawCircle(Offset(size.width*.85,size.height*.72),5.0,_paint(Colors.red,blink?hudProgress:hudProgress*.3,PaintingStyle.fill));
    }
  }

  @override
  bool shouldRepaint(covariant CockpitViewPainter oldDelegate) => idleProgress != oldDelegate.idleProgress || bootProgress != oldDelegate.bootProgress;
}

class HudPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) { final paint = Paint()..color = Colors.cyan.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 2.0; final glowPaint = Paint()..color = Colors.cyan.withOpacity(0.2)..style = PaintingStyle.stroke..strokeWidth = 4.0..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0); const cornerSize = 20.0, padding = 10.0; final path = Path(); path.moveTo(padding+cornerSize,padding);path.lineTo(padding,padding);path.lineTo(padding,padding+cornerSize); path.moveTo(size.width-padding-cornerSize,padding);path.lineTo(size.width-padding,padding);path.lineTo(size.width-padding,padding+cornerSize); path.moveTo(padding,size.height-padding-cornerSize);path.lineTo(padding,size.height-padding);path.lineTo(padding+cornerSize,size.height-padding); path.moveTo(size.width-padding,size.height-padding-cornerSize);path.lineTo(size.width-padding,size.height-padding);path.lineTo(size.width-padding-cornerSize,size.height-padding); canvas.drawPath(path, glowPaint); canvas.drawPath(path, paint); }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CustomCardBorder extends OutlinedBorder {
  const CustomCardBorder({super.side=BorderSide.none, this.borderRadius=BorderRadius.zero});
  final BorderRadius borderRadius;
  @override
  CustomCardBorder copyWith({BorderSide? side, BorderRadius? borderRadius}) => CustomCardBorder(side:side??this.side,borderRadius:borderRadius??this.borderRadius);
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(borderRadius.resolve(textDirection).toRRect(rect).deflate(side.width));
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(borderRadius.resolve(textDirection).toRRect(rect));
  @override
  void paint(Canvas canvas,Rect rect,{TextDirection? textDirection}) { if (rect.isEmpty) return; final RRect rrect = borderRadius.resolve(textDirection).toRRect(rect); final paint = Paint()..style=PaintingStyle.stroke..strokeWidth=side.width; final vPaint = Paint()..style=PaintingStyle.stroke..strokeWidth=side.width..shader=LinearGradient(begin:Alignment.bottomCenter,end:Alignment.topCenter,colors:[Colors.black,Colors.cyan],stops:const[0.0,1.0]).createShader(rect); paint.color=Colors.cyan; final lPath = Path()..moveTo(rrect.left,rrect.bottom)..lineTo(rrect.left,rrect.top+rrect.tlRadiusY); canvas.drawPath(lPath, vPaint); canvas.drawArc(Rect.fromLTWH(rrect.left,rrect.top,rrect.tlRadiusX*2,rrect.tlRadiusY*2),pi,pi/2,false,paint); canvas.drawLine(Offset(rrect.left+rrect.tlRadiusX,rrect.top),Offset(rrect.right-rrect.trRadiusX,rrect.top),paint); canvas.drawArc(Rect.fromLTWH(rrect.right-rrect.trRadiusX*2,rrect.top,rrect.trRadiusX*2,rrect.trRadiusY*2),pi*1.5,pi/2,false,paint); final rPath = Path()..moveTo(rrect.right,rrect.bottom)..lineTo(rrect.right,rrect.top+rrect.trRadiusY); canvas.drawPath(rPath, vPaint); }
  @override
  ShapeBorder scale(double t) => CustomCardBorder(side:side.scale(t),borderRadius:borderRadius*t);
}

class _ParallaxBackground extends StatefulWidget {
  final AnimationController controller;
  final bool isDashing;
  final TickerProvider vsync;
  const _ParallaxBackground({required this.controller, required this.isDashing, required this.vsync});
  @override
  State<_ParallaxBackground> createState() => _ParallaxBackgroundState();
}

class _ParallaxBackgroundState extends State<_ParallaxBackground> {
  late final List<_Particle> _particlesBack, _particlesMiddle, _particlesFront;
  late final AnimationController _speedController;
  late final Animation<double> _speedAnimation;
  double _totalAnimatedDistance = 0;
  double? _lastMainControllerValue;

  @override
  void initState() {
    super.initState();
    final random = Random();
    _particlesBack = List.generate(40, (i) => _Particle(random, layer: 0));
    _particlesMiddle = List.generate(40, (i) => _Particle(random, layer: 1));
    _particlesFront = List.generate(30, (i) => _Particle(random, layer: 2));
    _speedController = AnimationController(vsync: widget.vsync, duration: const Duration(milliseconds: 800));
    _speedAnimation = Tween<double>(begin: 1.0, end: 4.0).animate(CurvedAnimation(parent: _speedController, curve: Curves.easeInOut));
  }

  @override
  void reassemble() { super.reassemble(); _lastMainControllerValue = widget.controller.value; }

  @override
  void didUpdateWidget(covariant _ParallaxBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDashing != oldWidget.isDashing) {
      if (widget.isDashing) _speedController.forward();
      else _speedController.reverse();
    }
  }

  @override
  void dispose() { _speedController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, _speedController]),
      builder: (context, child) {
        final currentControllerValue = widget.controller.value;
        double delta = currentControllerValue - (_lastMainControllerValue ?? currentControllerValue);
        if (delta < 0) delta += 1.0;
        _lastMainControllerValue = currentControllerValue;
        final distanceThisFrame = delta * _speedAnimation.value;
        if (distanceThisFrame.isFinite) _totalAnimatedDistance += distanceThisFrame;
        return CustomPaint(size:Size.infinite, painter:_ParallaxPainter(particlesBack:_particlesBack, particlesMiddle:_particlesMiddle, particlesFront:_particlesFront, totalAnimatedDistance:_totalAnimatedDistance));
      },
    );
  }
}

class _ParallaxPainter extends CustomPainter {
  final List<_Particle> particlesBack, particlesMiddle, particlesFront;
  final double totalAnimatedDistance;
  _ParallaxPainter({required this.particlesBack, required this.particlesMiddle, required this.particlesFront, required this.totalAnimatedDistance});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final gradient = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFF010014), const Color(0xFF04044A), const Color(0xFF001A4D)]);
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
    
    void drawLayer(List<_Particle> particles, double layerSpeedMultiplier) {
      for (var p in particles) {
        final xPos = (p.x * size.width) - (totalAnimatedDistance * p.speed * size.width * 50 * layerSpeedMultiplier);
        if (xPos.isFinite) canvas.drawCircle(Offset(xPos % (size.width + p.size * 2) - p.size, p.y * size.height), p.size, p.paint);
      }
    }
    drawLayer(particlesBack, 1.0);
    drawLayer(particlesMiddle, 1.75);
    drawLayer(particlesFront, 2.5);
  }

  @override
  bool shouldRepaint(covariant _ParallaxPainter oldDelegate) => totalAnimatedDistance != oldDelegate.totalAnimatedDistance;
}

class _Particle {
  late double x, y, size, opacity, speed;
  late Color color;
  late Paint paint;
  final Random _random;
  final int layer;

  _Particle(this._random, {required this.layer}) { _reset(); }

  void _reset() {
    x = _random.nextDouble(); y = _random.nextDouble();
    switch (layer) {
      case 0: size = _random.nextDouble()*1.5+.5; opacity = _random.nextDouble()*.2+.05; speed = _random.nextDouble()*.005+.001; color = Color.lerp(const Color(0xFF4A5299), const Color(0xFF2A3D80), _random.nextDouble())!; break;
      case 1: size = _random.nextDouble()*2.0+1.0; opacity = _random.nextDouble()*.3+.2; speed = _random.nextDouble()*.008+.003; color = _random.nextBool() ? const Color(0xFF00bcd4) : const Color(0xFF2196F3); break;
      case 2: size = _random.nextDouble()*2.5+1.5; opacity = _random.nextDouble()*.4+.3; speed = _random.nextDouble()*.012+.005; color = Color.lerp(Colors.cyanAccent, Colors.lightBlueAccent, _random.nextDouble())!; break;
      default: size=1;opacity=.5;speed=.01;color=Colors.white;
    }
    paint = Paint()..color = color.withOpacity(opacity);
  }
}