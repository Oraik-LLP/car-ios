# Changelog

## 1.0.0 (April 2026)

### Features
- **AI-Powered Diagnostics**: Urgent symptom-based and photo-based vehicle diagnosis powered by Google Gemini 2.0 Flash
- **Gemini Live (Beta)**: Real-time camera-to-AI video diagnosis with conversational follow-ups
- **Health Scoring**: 0–10 overall health score with component breakdown (Engine, Brakes, Transmission, Electrical, Suspension)
- **Radar Chart**: Visual health fingerprint showing all component scores at a glance
- **Report Engine**: Full diagnostic reports with AI summary, possible causes, recommendations, and metadata
- **Report History**: Browse, view details, and delete past diagnostic reports with swipe-to-delete
- **Vehicle Management**: Add, select, and manage multiple vehicles with comprehensive Indian + global market support
- **Dynamic Car Images**: Vehicle hero images fetched from CDN with brand-specific accent colors
- **Subscription Plans**: Free (3/mo), Premium ($4.99/mo, 25/mo), Pro ($9.99/mo, unlimited + Gemini Live)
- **Supabase Integration**: Authentication, database sync, and image storage (works offline with local fallback)
- **Dark Glass UI**: Premium automotive-inspired dark theme with glassmorphism effects and haptic feedback

### Vehicle Database
- 60+ car brands including Indian market (Maruti Suzuki, Tata, Mahindra, Force, MG, BYD, Isuzu, Datsun)
- 500+ models with India-specific variants (Nexon, Creta, XUV700, Swift, Fortuner, etc.)
- Years from 1990 to present

### Technical
- Flutter cross-platform (Android first, iOS-ready)
- Gemini 2.0 Flash for text + vision multimodal AI
- Local heuristic fallback when offline or API unconfigured
- Split-per-ABI release builds (~28–31 MB)
- Zero analyzer warnings, comprehensive widget + unit tests
