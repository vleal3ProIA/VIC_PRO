-- ============================================================================
-- 0064_ai_providers_mistral_deepseek.sql · Más proveedores de IA
-- ----------------------------------------------------------------------------
-- Registra Mistral y DeepSeek (ambos API compatible con OpenAI) en el catálogo
-- de proveedores. Quedan DESACTIVADOS: el superadmin añade su API key en el
-- panel y los activa cuando quiera. El gateway ya tiene sus adaptadores.
--
-- `priority` mayor que los gratuitos (Gemini/Groq) para que el fallback pruebe
-- primero lo gratis y use estos como red de seguridad.
-- ============================================================================

insert into public.ai_providers
  (slug, display_name, tier, enabled, priority, default_model, base_url)
values
  (
    'mistral', 'Mistral', 'paid', false, 50,
    'mistral-large-latest', 'https://api.mistral.ai/v1'
  ),
  (
    'deepseek', 'DeepSeek', 'paid', false, 55,
    'deepseek-chat', 'https://api.deepseek.com'
  )
on conflict (slug) do nothing;
