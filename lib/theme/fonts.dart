import 'package:flutter/material.dart';
import 'package:flippy/theme/colors.dart';

class AppTextStyles {
  static const TextStyle heading = TextStyle(
    fontFamily: 'Poppins',
    fontWeight: FontWeight.w600,
    fontSize: 32,
    color: AppColors.text, // Text farba
  );

  static const TextStyle chapter = TextStyle(
    fontFamily: 'Poppins',
    fontWeight: FontWeight.w600,
    fontSize: 24,
    color: AppColors.text, // Text farba
  );

  static const TextStyle lesson = TextStyle(
    fontFamily: 'Poppins',
    fontWeight: FontWeight.w500,
    fontSize: 16,
    color: AppColors.text, // Accent farba
  );

  static const TextStyle body = TextStyle(
    fontFamily: 'Poppins',
    fontWeight: FontWeight.normal,
    fontSize: 14,
    color: AppColors.text, // Text farba
  );
}