import 'package:flutter/material.dart';
import '../../../../core/utils/validators.dart';

enum FieldKind { text, email, phone, date, dropdown, amount, id, postal }

class FieldSpec {
  const FieldSpec(this.key, this.label, this.icon, this.kind, {this.options = const [], this.optional = false});
  final String key, label;
  final IconData icon;
  final FieldKind kind;
  final List<String> options;
  final bool optional;
}

class StepInfo {
  const StepInfo(this.title, this.subtitle, [this.fields = const []]);
  final String title, subtitle;
  final List<FieldSpec> fields;
}

const _provinces = [
  'Western', 'Central', 'Southern', 'Northern', 'Eastern',
  'North Western', 'North Central', 'Uva', 'Sabaragamuwa',
];

/// The five registration steps. Steps 3 and 4 (identity, review) render custom UI.
const registrationSteps = [
  StepInfo('Personal information', 'Tell us who you are, exactly as on your ID.', [
    FieldSpec('fullName', 'Full legal name', Icons.person_rounded, FieldKind.text),
    FieldSpec('dob', 'Date of birth', Icons.cake_rounded, FieldKind.date),
    FieldSpec('nationality', 'Nationality', Icons.flag_rounded, FieldKind.dropdown,
        options: ['Sri Lankan', 'Indian', 'British', 'American', 'Australian', 'Other']),
    FieldSpec('idNumber', 'NIC / Passport number', Icons.badge_rounded, FieldKind.id),
    FieldSpec('gender', 'Gender (optional)', Icons.wc_rounded, FieldKind.dropdown,
        options: ['Male', 'Female', 'Prefer not to say'], optional: true),
    FieldSpec('occupation', 'Occupation', Icons.work_rounded, FieldKind.text),
  ]),
  StepInfo('Contact information', 'How we can reach you and where you live.', [
    FieldSpec('mobile', 'Mobile number', Icons.phone_rounded, FieldKind.phone),
    FieldSpec('email', 'Email address', Icons.mail_rounded, FieldKind.email),
    FieldSpec('address', 'Residential address', Icons.home_rounded, FieldKind.text),
    FieldSpec('city', 'City', Icons.location_city_rounded, FieldKind.text),
    FieldSpec('province', 'Province', Icons.map_rounded, FieldKind.dropdown, options: _provinces),
    FieldSpec('postalCode', 'Postal code', Icons.markunread_mailbox_rounded, FieldKind.postal),
    FieldSpec('country', 'Country', Icons.public_rounded, FieldKind.dropdown,
        options: ['Sri Lanka', 'India', 'United Kingdom', 'United States', 'Australia', 'Other']),
  ]),
  StepInfo('Banking information', 'Choose your account and tell us how you will use it.', [
    FieldSpec('accountType', 'Account type', Icons.layers_rounded, FieldKind.dropdown,
        options: ['Savings', 'Current']),
    FieldSpec('initialDeposit', 'Initial deposit (LKR)', Icons.account_balance_wallet_rounded, FieldKind.amount),
    FieldSpec('sourceOfFunds', 'Source of funds', Icons.payments_rounded, FieldKind.dropdown,
        options: ['Salary', 'Business income', 'Savings', 'Investments', 'Family support', 'Other']),
    FieldSpec('employmentStatus', 'Employment status', Icons.business_center_rounded, FieldKind.dropdown,
        options: ['Employed', 'Self-employed', 'Student', 'Retired', 'Unemployed']),
    FieldSpec('monthlyIncome', 'Estimated monthly income', Icons.bar_chart_rounded, FieldKind.dropdown,
        options: ['Below LKR 50,000', 'LKR 50,000 – 100,000', 'LKR 100,000 – 250,000', 'Above LKR 250,000']),
    FieldSpec('purpose', 'Purpose of account', Icons.flag_circle_rounded, FieldKind.dropdown,
        options: ['Personal banking', 'Savings', 'Salary account', 'Business use', 'Education']),
  ]),
  StepInfo('Verify your identity', 'We need to confirm it is really you.'),
  StepInfo('Review & secure', 'Check your details and create your sign-in.'),
];

const identityStep = 3;
const reviewStep = 4;

String? validateField(FieldSpec f, String? value, DateTime now) {
  if (f.optional && (value ?? '').trim().isEmpty) return null;
  return switch (f.kind) {
    FieldKind.email => Validators.email(value),
    FieldKind.phone => Validators.phone(value),
    FieldKind.date => Validators.adultDateOfBirth(value, now),
    FieldKind.id => Validators.idDocument(value),
    FieldKind.postal => Validators.postalCode(value),
    FieldKind.amount => Validators.initialDeposit(value),
    FieldKind.dropdown => Validators.required(value, f.label),
    FieldKind.text => f.key == 'fullName' ? Validators.fullName(value) : Validators.required(value, f.label),
  };
}
