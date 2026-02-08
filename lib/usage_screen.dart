import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  Duration _totalUsageTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadUsageTime();
  }

  Future<void> _loadUsageTime() async {
    final prefs = await SharedPreferences.getInstance();
    final totalSeconds = prefs.getInt('totalUsageSeconds') ?? 0;
    setState(() {
      _totalUsageTime = Duration(seconds: totalSeconds);
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours시간 $minutes분 $seconds초";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('총 사용 시간'),
        backgroundColor: Colors.blueGrey,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '이 앱을 교육 목적으로 사용한 총 시간입니다.',
              style: TextStyle(fontSize: 18, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              _formatDuration(_totalUsageTime),
              style: const TextStyle(fontSize: 42, color: Colors.cyanAccent, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('돌아가기'),
            ),
          ],
        ),
      ),
      backgroundColor: const Color(0xFF020024),
    );
  }
}
