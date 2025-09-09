import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../pages/login_page.dart';

class AuthStatusWidget extends StatefulWidget {
  final VoidCallback? onAuthChanged;
  
  const AuthStatusWidget({super.key, this.onAuthChanged});

  @override
  State<AuthStatusWidget> createState() => _AuthStatusWidgetState();
}

class _AuthStatusWidgetState extends State<AuthStatusWidget> {
  bool _isAuthenticated = false;
  bool _isLoading = true;
  String _username = '';

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    setState(() => _isLoading = true);
    
    try {
      final isAuth = await AuthService.instance.isAuthenticated();
      final username = await AuthService.instance.getCurrentUsername();
      
      setState(() {
        _isAuthenticated = isAuth;
        _username = username;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isAuthenticated = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _showLoginDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const LoginPage(),
    );

    if (result == true) {
      await _checkAuthStatus();
      widget.onAuthChanged?.call();
    }
  }

  Future<void> _logout() async {
    await AuthService.instance.logout();
    await _checkAuthStatus();
    widget.onAuthChanged?.call();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logout realizado com sucesso'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _isAuthenticated 
            ? const Color.fromRGBO(76, 175, 80, 0.2)
                : const Color.fromRGBO(255, 165, 0, 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isAuthenticated 
              ? const Color.fromRGBO(76, 175, 80, 0.5)
                : const Color.fromRGBO(255, 165, 0, 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isAuthenticated ? Icons.verified_user : Icons.person,
            size: 16,
            color: _isAuthenticated ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 6),
          Text(
            _isAuthenticated ? _username : 'Visitante',
            style: TextStyle(
              color: _isAuthenticated ? Colors.green : Colors.orange,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _isAuthenticated ? _logout : _showLoginDialog,
            child: Icon(
              _isAuthenticated ? Icons.logout : Icons.login,
              size: 16,
              color: _isAuthenticated ? Colors.green : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }
}

// Widget para mostrar funcionalidades restritas
class RestrictedFeatureWidget extends StatelessWidget {
  final String featureName;
  final Widget child;
  final String? customMessage;
  final bool viewOnlyWhenRestricted;
  final bool showOverlayWhenRestricted;
  
  const RestrictedFeatureWidget({
    super.key,
    required this.featureName,
    required this.child,
    this.customMessage,
    this.viewOnlyWhenRestricted = false,
    this.showOverlayWhenRestricted = true,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AuthService.instance.isAuthenticated(),
      builder: (context, snapshot) {
        final isAuthenticated = snapshot.data ?? false;
        final requiresAuth = AuthService.instance.requiresAuthentication(featureName);
        
        if (requiresAuth && !isAuthenticated) {
          if (viewOnlyWhenRestricted) {
            return Stack(
              children: [
                AbsorbPointer(
                  absorbing: true,
                  child: child,
                ),
                if (showOverlayWhenRestricted)
                  _buildRestrictedOverlay(context),
              ],
            );
          }
          return _buildRestrictedView(context);
        }
        
        return child;
      },
    );
  }
  
  Widget _buildRestrictedView(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color.fromRGBO(255, 165, 0, 0.3),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock,
            size: 48,
            color: const Color.fromRGBO(255, 165, 0, 0.7),
          ),
          const SizedBox(height: 16),
          Text(
            customMessage ?? 'Funcionalidade Restrita',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Faça login para acessar esta funcionalidade',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              final result = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (context) => const LoginPage(),
              );
              
              if (result == true) {
                // Força rebuild do widget pai
                if (context.mounted) {
                  (context as Element).markNeedsBuild();
                }
              }
            },
            icon: const Icon(Icons.login),
            label: const Text('Fazer Login'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRestrictedOverlay(BuildContext context) {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock,
                size: 44,
                color: const Color.fromRGBO(255, 165, 0, 0.9),
              ),
              const SizedBox(height: 12),
              Text(
                customMessage ?? 'Acesso limitado no modo visitante',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () async {
                  await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => const LoginPage(),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.login),
                label: const Text('Fazer Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}