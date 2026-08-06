/// Compatibility facade for the legacy import path.
///
/// The recommendation model has been moved into the AI Hub package. Existing
/// imports (`import '../models/scholarship_recommendation.dart';`) continue
/// to work without changes by re-exporting the canonical model.
export '../ai_hub/models/scholarship_recommendation.dart';

// The legacy ScholarshipRecommendation model has been moved into the
// AI Hub package. The export at the top of this file re-exports the
// canonical model, so all existing call sites continue to work without
// any changes to their imports.
