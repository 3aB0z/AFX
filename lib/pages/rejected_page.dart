import 'package:flutter/material.dart';
import '../config.dart';
import '../services/firebase_service.dart';
import 'dart:async';

class RejectedPage extends StatefulWidget {
  final DateTime? rejectedAt;

  const RejectedPage({super.key, this.rejectedAt});

  @override
  State<RejectedPage> createState() => _RejectedPageState();
}

class _RejectedPageState extends State<RejectedPage> {
  Duration _timeLeft = Duration.zero;
  Timer? _cooldownTimer;
  DateTime? _deviceRejectionTime;

  @override
  void initState() {
    super.initState();
    _initRejectionTimer();
  }

  Future<void> _initRejectionTimer() async {
    // Save rejection time if not already set (or refresh if needed)
    final existingTime = await FirebaseService.getDeviceRejectionTime();
    if (existingTime == null) {
      final uid = FirebaseService.getCurrentUserId();
      if (uid != null) {
        await FirebaseService.saveDeviceRejection(uid);
      }
      _deviceRejectionTime = DateTime.now();
    } else {
      _deviceRejectionTime = existingTime;
    }

    if (mounted) {
      _calculateTimeLeft();
      _startCooldownTimer();
    }
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _calculateTimeLeft();
    });
  }

  void _calculateTimeLeft() {
    if (_deviceRejectionTime == null) return;

    final now = DateTime.now();
    final unlockTime = _deviceRejectionTime!.add(const Duration(hours: 24));
    final difference = unlockTime.difference(now);

    if (mounted) {
      setState(() {
        _timeLeft = difference.isNegative ? Duration.zero : difference;
        if (_timeLeft == Duration.zero) {
          _cooldownTimer?.cancel();
        }
      });
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.block_flipped, color: Colors.red, size: 80),
              const SizedBox(height: 20),
              Text(
                'Account Permanently Rejected',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              Text(
                'This account has been permanently rejected by the administrator.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Config.getTextColor(context, level: 2),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You can no longer access chat with this account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Config.getTextColor(context, level: 3),
                  fontSize: 14,
                ),
              ),
              if (_timeLeft > Duration.zero) ...[
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.withAlpha(40)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Registration Cooldown',
                        style: TextStyle(
                          color: Colors.red[700],
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatDuration(_timeLeft),
                        style: TextStyle(
                          color: Colors.red[400],
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Time remaining until you can request access again.',
                        style: TextStyle(color: Colors.red[300], fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: () => FirebaseService.logout(),
                style: ElevatedButton.styleFrom(
                  alignment: Alignment.center,
                  backgroundColor: Config.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.logout, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'LOGOUT',
                      style: TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
