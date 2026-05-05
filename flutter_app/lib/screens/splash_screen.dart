import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    _init();
  }

  Future<void> _init() async {
    final auth = context.read<AuthService>();
    await auth.init();
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    if (auth.isLoggedIn) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d1117),
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF1B96FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Text('U', style: TextStyle(
                    fontSize: 42, fontWeight: FontWeight.w800,
                    color: Colors.white,
                  )),
                ),
              ),
              const SizedBox(height: 20),
              const Text('U2DIA AI', style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700,
                color: Color(0xFFe6edf3), letterSpacing: 1.5,
              )),
              const SizedBox(height: 6),
              const Text('칸반보드', style: TextStyle(
                fontSize: 13, color: Color(0xFF8b949e),
              )),
              const SizedBox(height: 40),
              const SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1B96FF)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
