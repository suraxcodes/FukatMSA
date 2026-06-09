import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/supabase_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthPopup extends StatefulWidget {
  @override
  _AuthPopupState createState() => _AuthPopupState();
}

class _AuthPopupState extends State<AuthPopup> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isLogin = true;
  bool _useOtp = false;
  bool _otpSent = false;
  OtpType _currentOtpType = OtpType.magiclink;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final otp = _otpController.text.trim();

    if (email.isEmpty) {
      _showError('Email is required');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_useOtp) {
        if (!_otpSent) {
          // Send Magic Link / OTP
          await SupabaseAuthService.signInWithOtp(email: email);
          setState(() {
            _otpSent = true;
            _currentOtpType = OtpType.magiclink;
          });
          _showSuccess('Verification code sent to email!');
        } else {
          // Verify OTP
          if (otp.isEmpty) throw Exception('Please enter the verification code');
          await SupabaseAuthService.verifyOTP(email: email, token: otp, type: _currentOtpType);
          if (mounted) Navigator.pop(context); // Close popup on success
        }
      } else {
        if (password.isEmpty) {
          throw Exception('Password is required');
        }
        if (_isLogin) {
          await SupabaseAuthService.signIn(email: email, password: password);
          if (mounted) Navigator.pop(context); // Close popup on success
        } else {
          await SupabaseAuthService.signUp(email: email, password: password);
          setState(() {
            _useOtp = true;
            _otpSent = true;
            _currentOtpType = OtpType.signup;
          });
          _showSuccess('Account created! Please check your email for the verification code.');
        }
      }
    } on AuthException catch (e) {
      String msg = e.message;
      if (msg.contains('weak_password')) {
        msg = 'Password is too weak. Please use at least 6 characters.';
      } else if (msg.contains('Invalid login credentials')) {
        msg = 'Incorrect email or password. Please try again.';
      } else if (msg.contains('already registered')) {
        msg = 'An account with this email already exists.';
      } else if (msg.contains('Token has expired')) {
        msg = 'The verification code has expired or is invalid.';
      }
      _showError(msg);
    } catch (e) {
      _showError('Something went wrong. Please try again later.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background Image with Blur
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 400,
              height: _useOtp && _otpSent ? 380 : 450,
              decoration: BoxDecoration(
                image: const DecorationImage(
                  image: AssetImage('assets/app_icon.png'),
                  fit: BoxFit.cover,
                ),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  color: Colors.black.withOpacity(0.6), // Dark overlay
                ),
              ),
            ),
          ),
          
          // Content
          Container(
            width: 400,
            height: _useOtp && _otpSent ? 380 : 450,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _useOtp 
                      ? (_otpSent ? 'Enter Code' : 'Magic Link / OTP') 
                      : (_isLogin ? 'Welcome Back' : 'Create Account'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _useOtp && _otpSent 
                      ? 'Check your email for the verification code or magic link.'
                      : 'Log in to sync your Watchlist & History',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 24),
                
                // Fields
                TextField(
                  controller: _emailController,
                  enabled: !_otpSent,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Email',
                    labelStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.email, color: Colors.white54),
                    filled: true,
                    fillColor: Colors.black45,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                if (_useOtp && _otpSent) ...[
                  TextField(
                    controller: _otpController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: '6-Digit Code',
                      labelStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.lock_clock, color: Colors.white54),
                      filled: true,
                      fillColor: Colors.black45,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ] else if (!_useOtp) ...[
                  TextField(
                    controller: _passwordController,
                    style: const TextStyle(color: Colors.white),
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.lock, color: Colors.white54),
                      filled: true,
                      fillColor: Colors.black45,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
                
                const SizedBox(height: 24),
                
                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            _useOtp 
                                ? (_otpSent ? 'Verify & Login' : 'Send Code') 
                                : (_isLogin ? 'Login' : 'Sign Up'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Toggles
                if (!_otpSent) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _useOtp = !_useOtp),
                        child: Text(
                          _useOtp ? 'Use Password' : 'Use Magic Link/OTP',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      if (!_useOtp) ...[
                        const Text('|', style: TextStyle(color: Colors.white30)),
                        TextButton(
                          onPressed: () => setState(() => _isLogin = !_isLogin),
                          child: Text(
                            _isLogin ? 'Sign Up' : 'Log In',
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ]
                    ],
                  ),
                ],
              ],
            ),
          ),
          
          // Close button
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
