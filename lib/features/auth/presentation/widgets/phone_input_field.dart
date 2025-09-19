import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';

class PhoneInputField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String hintText;
  final String? Function(String?)? validator;
  final bool enabled;
  final VoidCallback? onChanged;

  const PhoneInputField({
    super.key,
    required this.controller,
    required this.labelText,
    required this.hintText,
    this.validator,
    this.enabled = true,
    this.onChanged,
  });

  @override
  State<PhoneInputField> createState() => _PhoneInputFieldState();
}

class _PhoneInputFieldState extends State<PhoneInputField> {
  String _selectedCountryCode = '+91';
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.labelText,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.lightGrey,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.borderColor,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Country Code Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                  border: Border(
                    right: BorderSide(
                      color: AppColors.borderColor,
                      width: 1,
                    ),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCountryCode,
                    isDense: true,
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: '+91',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🇮🇳'),
                            const SizedBox(width: 8),
                            Text('+91'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: '+1',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🇺🇸'),
                            const SizedBox(width: 8),
                            Text('+1'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: '+44',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🇬🇧'),
                            const SizedBox(width: 8),
                            Text('+44'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: widget.enabled ? (value) {
                      setState(() {
                        _selectedCountryCode = value!;
                      });
                      if (widget.onChanged != null) {
                        widget.onChanged!();
                      }
                    } : null,
                  ),
                ),
              ),
              
              // Phone Number Input
              Expanded(
                child: TextFormField(
                  controller: widget.controller,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: widget.enabled ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: GoogleFonts.poppins(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  validator: widget.validator,
                  onChanged: (_) {
                    if (widget.onChanged != null) {
                      widget.onChanged!();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String get fullPhoneNumber {
    return '$_selectedCountryCode${widget.controller.text}';
  }
}