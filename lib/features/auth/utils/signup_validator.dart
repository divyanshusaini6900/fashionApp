import 'package:flutter/foundation.dart';

/// Utility class for validating and processing signup data
/// Specifically for Full Name handling and Firebase integration
class SignupValidator {
  
  /// Validates and processes Full Name from UI input
  static Map<String, dynamic> validateAndProcessFullName(String input) {
    final trimmedName = input.trim();
    
    // Log the validation process
    if (kDebugMode) {
      print('🔍 Validating Full Name: "$input" -> "$trimmedName"');
    }
    
    final result = <String, dynamic>{
      'isValid': false,
      'processedName': trimmedName,
      'errorMessage': null,
    };
    
    // Check if empty
    if (trimmedName.isEmpty) {
      result['errorMessage'] = 'Full name cannot be empty';
      if (kDebugMode) print('❌ Validation failed: Empty name');
      return result;
    }
    
    // Check minimum length
    if (trimmedName.length < 2) {
      result['errorMessage'] = 'Full name must be at least 2 characters';
      if (kDebugMode) print('❌ Validation failed: Too short');
      return result;
    }
    
    // Check for valid characters (letters and spaces only)
    if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(trimmedName)) {
      result['errorMessage'] = 'Full name can only contain letters and spaces';
      if (kDebugMode) print('❌ Validation failed: Invalid characters');
      return result;
    }
    
    // Check that it's not just spaces
    if (trimmedName.replaceAll(' ', '').isEmpty) {
      result['errorMessage'] = 'Please enter a valid full name';
      if (kDebugMode) print('❌ Validation failed: Only spaces');
      return result;
    }
    
    // Check for reasonable length (not too long)
    if (trimmedName.length > 50) {
      result['errorMessage'] = 'Full name cannot exceed 50 characters';
      if (kDebugMode) print('❌ Validation failed: Too long');
      return result;
    }
    
    // All validations passed
    result['isValid'] = true;
    if (kDebugMode) {
      print('✅ Full Name validation passed: "$trimmedName"');
    }
    
    return result;
  }
  
  /// Formats Full Name for consistent Firebase storage
  static String formatFullNameForFirebase(String fullName) {
    // Trim and normalize spacing
    String formatted = fullName.trim().replaceAll(RegExp(r'\s+'), ' ');
    
    // Capitalize first letter of each word for consistency
    formatted = formatted.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
    
    if (kDebugMode) {
      print('📝 Formatted Full Name for Firebase: "$fullName" -> "$formatted"');
    }
    
    return formatted;
  }
  
  /// Comprehensive validation for all signup data
  static Map<String, dynamic> validateSignupData({
    required String fullName,
    required String email,
    required String phoneNumber,
    required String city,
  }) {
    final result = <String, dynamic>{
      'isValid': false,
      'errors': <String>[],
      'processedData': <String, String>{},
    };
    
    if (kDebugMode) {
      print('🔍 Validating complete signup data...');
      print('Full Name: "$fullName"');
      print('Email: "$email"');
      print('Phone: "$phoneNumber"');  
      print('City: "$city"');
    }
    
    // Validate Full Name
    final nameValidation = validateAndProcessFullName(fullName);
    if (!nameValidation['isValid']) {
      result['errors'].add(nameValidation['errorMessage']);
    } else {
      result['processedData']['fullName'] = formatFullNameForFirebase(fullName);
    }
    
    // Basic email validation
    final trimmedEmail = email.trim().toLowerCase();
    if (trimmedEmail.isEmpty || !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(trimmedEmail)) {
      result['errors'].add('Please enter a valid email address');
    } else {
      result['processedData']['email'] = trimmedEmail;
    }
    
    // Basic phone validation
    final trimmedPhone = phoneNumber.trim();
    if (trimmedPhone.isEmpty) {
      result['errors'].add('Please enter a phone number');
    } else {
      result['processedData']['phoneNumber'] = trimmedPhone;
    }
    
    // Basic city validation
    final trimmedCity = city.trim();
    if (trimmedCity.isEmpty) {
      result['errors'].add('Please enter your city');
    } else {
      result['processedData']['city'] = trimmedCity;
    }
    
    result['isValid'] = (result['errors'] as List).isEmpty;
    
    if (kDebugMode) {
      if (result['isValid']) {
        print('✅ All signup data validation passed');
      } else {
        print('❌ Signup validation failed: ${result['errors']}');
      }
    }
    
    return result;
  }
}
