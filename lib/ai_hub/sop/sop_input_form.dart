import 'package:flutter/material.dart';

import '../../theme/scholarbird_theme.dart';
import 'scholarship_type.dart';

/// Stateful form collecting the inputs needed to generate an SOP.
///
/// Pass the resolved [userDocuments] / [userReferences] from the screen so
/// the user sees which supporting materials will be included.
class SopInputForm extends StatefulWidget {
  const SopInputForm({
    super.key,
    required this.onSubmit,
    required this.userDocuments,
    required this.userReferences,
    this.isGenerating = false,
  });

  final Future<void> Function(SopFormSubmission submission) onSubmit;
  final int userDocuments;
  final int userReferences;
  final bool isGenerating;

  @override
  State<SopInputForm> createState() => _SopInputFormState();
}

class _SopInputFormState extends State<SopInputForm> {
  final _formKey = GlobalKey<FormState>();
  ScholarshipType _type = ScholarshipType.generic;
  final _programmeController = TextEditingController();
  final _universityController = TextEditingController();
  final _fieldController = TextEditingController();
  final _scholarshipNameController = TextEditingController();
  final _notesController = TextEditingController();
  int _wordTarget = 800;

  @override
  void dispose() {
    _programmeController.dispose();
    _universityController.dispose();
    _fieldController.dispose();
    _scholarshipNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    final submission = SopFormSubmission(
      type: _type,
      targetProgramme: _programmeController.text.trim(),
      targetUniversity: _universityController.text.trim(),
      targetField: _fieldController.text.trim(),
      scholarshipName: _scholarshipNameController.text.trim(),
      wordCountTarget: _wordTarget,
      additionalNotes: _notesController.text.trim(),
    );
    await widget.onSubmit(submission);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
        children: [
          _SectionHeader(
            title: 'What scholarship are you targeting?',
            subtitle:
                'Choose the flavour that best matches your programme. The model uses this to set the right tone and structure.',
          ),
          const SizedBox(height: ScholarBirdSpacing.small),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ScholarshipType.values
                .map(
                  (type) => ChoiceChip(
                    label: Text(type.label),
                    selected: _type == type,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _type = type);
                      }
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: ScholarBirdSpacing.small),
          _TypeDescription(type: _type),
          const SizedBox(height: ScholarBirdSpacing.large),
          _SectionHeader(
            title: 'Programme details',
            subtitle:
                'Fill whichever fields you already know — leave blanks for the AI to handle gracefully.',
          ),
          const SizedBox(height: ScholarBirdSpacing.small),
          TextFormField(
            controller: _programmeController,
            decoration: _decoration(
              label: 'Programme (e.g. MSc Computer Science)',
              icon: Icons.school_outlined,
            ),
          ),
          const SizedBox(height: ScholarBirdSpacing.small),
          TextFormField(
            controller: _universityController,
            decoration: _decoration(
              label: 'University / consortium',
              icon: Icons.account_balance_outlined,
            ),
          ),
          const SizedBox(height: ScholarBirdSpacing.small),
          TextFormField(
            controller: _fieldController,
            decoration: _decoration(
              label: 'Field of study',
              icon: Icons.science_outlined,
            ),
          ),
          if (_type != ScholarshipType.generic) ...[
            const SizedBox(height: ScholarBirdSpacing.small),
            TextFormField(
              controller: _scholarshipNameController,
              decoration: _decoration(
                label: 'Specific scholarship name (optional)',
                icon: Icons.workspace_premium_outlined,
              ),
            ),
          ],
          const SizedBox(height: ScholarBirdSpacing.large),
          _SectionHeader(
            title: 'Length & tone',
            subtitle:
                'Most SOPs sit between 600 and 1,200 words. Pick a target and we will steer the draft within ±10%.',
          ),
          const SizedBox(height: ScholarBirdSpacing.small),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _wordTarget.toDouble(),
                  min: 400,
                  max: 1200,
                  divisions: 8,
                  label: '$_wordTarget words',
                  onChanged: widget.isGenerating
                      ? null
                      : (value) =>
                          setState(() => _wordTarget = value.round()),
                ),
              ),
              SizedBox(
                width: 88,
                child: Text(
                  '$_wordTarget words',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: ScholarBirdColors.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ScholarBirdSpacing.large),
          _SectionHeader(
            title: 'Notes for the AI (optional)',
            subtitle:
                'Add a personal hook, an anecdote, or specific points the SOP must cover.',
          ),
          const SizedBox(height: ScholarBirdSpacing.small),
          TextFormField(
            controller: _notesController,
            maxLines: 5,
            decoration: _decoration(
              label: 'e.g. link my community health project to the programme',
              icon: Icons.edit_note_outlined,
            ),
          ),
          const SizedBox(height: ScholarBirdSpacing.large),
          _SupportingEvidence(
            documents: widget.userDocuments,
            references: widget.userReferences,
          ),
          const SizedBox(height: ScholarBirdSpacing.large),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.isGenerating ? null : _handleSubmit,
              icon: widget.isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                widget.isGenerating
                    ? 'Generating your SOP…'
                    : 'Generate SOP draft',
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
  }) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: ScholarBirdColors.body),
        filled: true,
        fillColor: ScholarBirdColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ScholarBirdColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ScholarBirdColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: ScholarBirdColors.primary, width: 2),
        ),
      );
}

class SopFormSubmission {
  const SopFormSubmission({
    required this.type,
    required this.targetProgramme,
    required this.targetUniversity,
    required this.targetField,
    required this.scholarshipName,
    required this.wordCountTarget,
    required this.additionalNotes,
  });

  final ScholarshipType type;
  final String targetProgramme;
  final String targetUniversity;
  final String targetField;
  final String scholarshipName;
  final int wordCountTarget;
  final String additionalNotes;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13,
            color: ScholarBirdColors.body,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _TypeDescription extends StatelessWidget {
  const _TypeDescription({required this.type});

  final ScholarshipType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
      decoration: BoxDecoration(
        color: ScholarBirdColors.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ScholarBirdColors.primary.withValues(alpha: .15),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            type == ScholarshipType.daad
                ? Icons.school_outlined
                : type == ScholarshipType.erasmus
                    ? Icons.public_outlined
                    : type == ScholarshipType.chevening
                        ? Icons.flag_outlined
                        : type == ScholarshipType.commonwealth
                            ? Icons.groups_outlined
                            : Icons.auto_stories_outlined,
            color: ScholarBirdColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              type.description,
              style: const TextStyle(
                fontSize: 13,
                color: ScholarBirdColors.ink,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportingEvidence extends StatelessWidget {
  const _SupportingEvidence({
    required this.documents,
    required this.references,
  });

  final int documents;
  final int references;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
      decoration: BoxDecoration(
        color: ScholarBirdColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ScholarBirdColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Pill(
              icon: Icons.folder_open_outlined,
              label:
                  '$documents document${documents == 1 ? '' : 's'} will be cited',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Pill(
              icon: Icons.people_outline,
              label:
                  '$references reference${references == 1 ? '' : 's'} available',
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ScholarBirdColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: ScholarBirdColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: ScholarBirdColors.body,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
