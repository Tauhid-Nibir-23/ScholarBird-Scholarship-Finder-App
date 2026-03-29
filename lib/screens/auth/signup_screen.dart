import 'package:flutter/material.dart';
import 'login_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  late TextEditingController _confirmPasswordController;
  
  String? _selectedDepartment;
  String? _selectedDegree;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  final List<String> departments = ['CSE', 'EEE', 'BBA', 'Mechanical', 'Civil', 'Textile'];
  final List<String> degrees = ['Undergraduate', 'Postgraduate'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F7FB),
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.arrow_back_rounded, color: Color(0xFF1A1A2E), size: 28),
          ),
        ),
        title: const Text(
          'Create Account',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A2E),
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),

                // Welcome Text
                const Text(
                  'Join ScholarBird Today',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Start your journey towards your dream scholarship',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF6B7A95),
                  ),
                ),

                SizedBox(height: size.height * 0.04),

                // Full Name TextField
                CustomTextField(
                  controller: _nameController,
                  hintText: 'Full Name',
                  prefixIcon: Icons.person_outline,
                ),

                const SizedBox(height: 16),

                // Email TextField
                CustomTextField(
                  controller: _emailController,
                  hintText: 'Email Address',
                  prefixIcon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                ),

                const SizedBox(height: 16),

                // Password TextField
                CustomTextField(
                  controller: _passwordController,
                  hintText: 'Password',
                  prefixIcon: Icons.lock_outline,
                  obscureText: _obscurePassword,
                  suffixIcon: GestureDetector(
                    onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                    child: Icon(
                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: const Color(0xFF5B7AE8),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Confirm Password TextField
                CustomTextField(
                  controller: _confirmPasswordController,
                  hintText: 'Confirm Password',
                  prefixIcon: Icons.lock_outline,
                  obscureText: _obscureConfirmPassword,
                  suffixIcon: GestureDetector(
                    onTap: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    child: Icon(
                      _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: const Color(0xFF5B7AE8),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Department Dropdown
                CustomDropdownField(
                  label: 'Department',
                  hint: 'Select your department',
                  value: _selectedDepartment,
                  items: departments,
                  prefixIcon: Icons.school_outlined,
                  onChanged: (value) => setState(() => _selectedDepartment = value),
                ),

                const SizedBox(height: 16),

                // Degree Dropdown
                CustomDropdownField(
                  label: 'Degree',
                  hint: 'Select your degree',
                  value: _selectedDegree,
                  items: degrees,
                  prefixIcon: Icons.book_outlined,
                  onChanged: (value) => setState(() => _selectedDegree = value),
                ),

                SizedBox(height: size.height * 0.04),

                // Create Account Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleSignUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5B7AE8),
                    disabledBackgroundColor: const Color(0xFF5B7AE8).withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 3,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Create Account',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),

                SizedBox(height: size.height * 0.04),

                // Login Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF6B7A95),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF5B7AE8),
                          decoration: TextDecoration.underline,
                          decorationColor: Color(0xFF5B7AE8),
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: size.height * 0.04),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleSignUp() {
    // TODO: Implement signup logic
    setState(() => _isLoading = true);
    
    Future.delayed(const Duration(seconds: 2), () {
      setState(() => _isLoading = false);
      // Navigation logic here
    });
  }
}

// Reusable Custom Dropdown Field Widget
class CustomDropdownField extends StatelessWidget {

  const CustomDropdownField({
    required this.items,
    required this.label,
    required this.onChanged,
    required this.prefixIcon,
    this.hint = '',
    this.value,
    super.key,
  });
  final String label;
  final String hint;
  final String? value;
  final List<String> items;
  final IconData prefixIcon;
  final Function(String?) onChanged;

  @override
  Widget build(BuildContext context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A2E),
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
          ),
          child: DropdownButtonFormField<String>(
            initialValue: value,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Color(0xFFB4BAC4),
              ),
              prefixIcon: Icon(
                prefixIcon,
                color: const Color(0xFF5B7AE8),
                size: 22,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            items: items.map((item) => DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            )).toList(),
            onChanged: onChanged,
            isExpanded: true,
            icon: const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(
                Icons.expand_more,
                color: Color(0xFF5B7AE8),
                size: 24,
              ),
            ),
            dropdownColor: Colors.white,
          ),
        ),
      ],
    );
}


