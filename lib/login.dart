import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:lottie/lottie.dart';
import 'package:rume/components/input_field.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

const String kFontFamily = 'Poppins';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }

      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } on FirebaseAuthException catch (e) {
        String message;
        switch (e.code) {
          case 'user-not-found':
            message = 'No user found with that email.';
            break;
          case 'wrong-password':
            message = 'Wrong password provided for that user.';
            break;
          case 'invalid-email':
            message = 'The email address format is not valid.';
            break;
          default:
            message = 'An error occurred: ${e.message}';
        }
        if (mounted) {
          final snackBar = SnackBar(
            elevation: 0,
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.transparent,
            content: AwesomeSnackbarContent(
              title: 'Login Failed',
              message: message,
              contentType: ContentType.failure,
            ),
          );
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(snackBar);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              elevation: 0,
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.transparent,
              content: AwesomeSnackbarContent(
                title: 'An Unexpected Error',
                message:
                    'Something went wrong. Please try again. Error: $e',
                contentType: ContentType.failure,
              ),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                
                
                ClipRect(
                  clipBehavior: Clip.none,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: 2,
                        left: -10,
                        child: Text(
                          'RuMe.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: kFontFamily,
                            fontSize: 70,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF4C51BF),
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                blurRadius: 3,
                                offset: Offset(0, 0),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Lottie.asset(
                        'assets/farm_House.json',
                        height: 350,
                        fit: BoxFit.contain,
                        repeat: true,
                        animate: true,
                      ),
                      Positioned(
                        top: 310,
                        left: 0,
                        right: 0,
                        child: Text(
                          'Welcome Back',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: kFontFamily,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2C2F4D),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Login to your account to continue',
                  style: TextStyle(
                    fontFamily: kFontFamily,
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),

                
                CustomInputField(
                  controller: _emailController,
                  labelText: 'Email',
                  hintText: 'your_email@example.com',
                  prefixIcon: Iconsax.user,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 15),

             
                CustomInputField(
                  controller: _passwordController,
                  labelText: 'Password',
                  hintText: 'Enter your password',
                  prefixIcon: Iconsax.lock,
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters long';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 5),

                const SizedBox(height: 25),

                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4C51BF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 5,
                      shadowColor: const Color(0xFF4C51BF).withOpacity(0.4),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : const Text(
                            'Login',
                            style: TextStyle(
                              fontFamily: kFontFamily,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 15),

                
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          context.go('/role-selection');
                        },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontFamily: kFontFamily,
                        fontSize: 14,
                        color: Color(0xFF4B5563),
                      ),
                      children: [
                        TextSpan(text: 'Don\'t have an account? '),
                        TextSpan(
                          text: 'Sign Up',
                          style: TextStyle(
                            fontFamily: kFontFamily,
                            color: Color(0xFF6366F1),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
