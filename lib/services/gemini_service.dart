/// Compatibility facade for the legacy import path.
///
/// The Gemini service has been moved into the AI Hub package. Existing
/// imports (`import '../services/gemini_service.dart';`) continue to work
/// without changes by re-exporting the canonical implementation.
export '../ai_hub/services/gemini_service.dart';

// The legacy GeminiService and its exceptions have been moved into the
// AI Hub package. The export at the top of this file re-exports the
// canonical implementation, so all existing call sites continue to work
// without any changes to their imports.
