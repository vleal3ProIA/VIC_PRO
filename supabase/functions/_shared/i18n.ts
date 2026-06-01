// ============================================================================
// _shared/i18n.ts — minimal locale-aware string lookup
// ----------------------------------------------------------------------------
// Centraliza las traducciones que necesitan las Edge Functions y que NO
// pueden vivir en `_shared/email_templates.ts` (esos diccionarios son
// para los emails). Aqui guardamos las que se reusan tanto en email
// (super_admin_alert) como en la notificacion in-app (title/body de
// `public.notifications`).
//
// API:
//
//   import { t } from "./i18n.ts";
//   t('es', 'super_admin_alert.user_registered.title',
//     { username: 'foo', email: 'a@b.com', total_users: '42' });
//
// Convenciones:
//   - Locale = string corto 'es' | 'en' | 'de' | 'fr' | 'it' | 'pt' | 'ru' | 'uk'.
//     Cualquier otro -> fallback a 'en'.
//   - Las claves usan dot-notation libre. Si la clave no existe en el
//     locale ni en 'en' -> devolvemos la propia clave (asi se ve facil
//     el problema en produccion sin romper).
//   - Interpolacion: `{{var}}` -> `params[var]` o cadena vacia.
// ============================================================================

const SUPPORTED = ["en", "es", "de", "fr", "it", "pt", "ru", "uk"] as const;
export type Locale = (typeof SUPPORTED)[number];

export function normalizeLocale(raw: string | undefined | null): Locale {
  if (!raw) return "en";
  const short = raw.toLowerCase().split(/[-_]/)[0];
  return (SUPPORTED as readonly string[]).includes(short)
    ? (short as Locale)
    : "en";
}

// Las strings se organizan por locale. Solo `en` es OBLIGATORIO; el
// resto cae a `en` si falta la clave. Asi anyadir un idioma no rompe
// nada si te dejas alguna clave (degrada con gracia).
type Strings = Record<string, string>;
type Catalog = Record<Locale, Strings>;

// Helper: rellena las 8 claves de un objeto comodo de leer.
function pack(values: Record<Locale, string>): Record<Locale, string> {
  return values;
}

const CATALOG: Catalog = {
  en: {
    // ─── Super-admin alert: in-app notification (title + body) ───
    "super_admin_alert.user_registered.title": "New signup",
    "super_admin_alert.user_registered.body":
      "{{username}} ({{email}}) just signed up. Total users: {{total_users}}.",

    "super_admin_alert.user_role_changed.title": "Role changed: {{username}}",
    "super_admin_alert.user_role_changed.body":
      "{{username}} ({{email}}) role changed: {{prev_role}} -> {{new_role}}. Current distribution: {{roles_breakdown}}.",

    "super_admin_alert.user_deleted.title": "User deleted: {{username}}",
    "super_admin_alert.user_deleted.body":
      "{{username}} ({{email}}) deleted their account. {{total_users}} users left.",

    "super_admin_alert.plan_changed.title": "Plan changed: {{username}}",
    "super_admin_alert.plan_changed.body":
      "{{username}} ({{email}}) {{action}}: {{prev_plan}} -> {{new_plan}}.",

    // ─── Super-admin alert: email (subject + intro + footer) ───
    "super_admin_alert.email.preheader":
      "Super-admin alert from {{app_name}}.",
    "super_admin_alert.email.footer":
      "You are receiving this because you are a super-admin of {{app_name}}.",

    // ─── Audit digest (PR 0080) ───
    "audit_digest.title": "Daily audit report ({{count}} findings)",
    "audit_digest.body":
      "Summary: {{critical}} critical, {{high}} high, {{medium}} medium, {{low}} low, {{info}} info.",
    "audit_digest.subject":
      "Daily audit report from {{app_name}} ({{count}} findings)",
    "audit_digest.no_issues": "All clear. No issues detected.",
    "audit_digest.top_findings": "Top findings",
  },
  es: {
    "super_admin_alert.user_registered.title": "Nuevo registro",
    "super_admin_alert.user_registered.body":
      "{{username}} ({{email}}) acaba de registrarse. Total de usuarios: {{total_users}}.",

    "super_admin_alert.user_role_changed.title": "Cambio de rol: {{username}}",
    "super_admin_alert.user_role_changed.body":
      "{{username}} ({{email}}) cambio de rol: {{prev_role}} -> {{new_role}}. Distribucion actual: {{roles_breakdown}}.",

    "super_admin_alert.user_deleted.title": "Usuario eliminado: {{username}}",
    "super_admin_alert.user_deleted.body":
      "{{username}} ({{email}}) elimino su cuenta. Quedan {{total_users}} usuarios.",

    "super_admin_alert.plan_changed.title": "Cambio de plan: {{username}}",
    "super_admin_alert.plan_changed.body":
      "{{username}} ({{email}}) {{action}}: {{prev_plan}} -> {{new_plan}}.",

    "super_admin_alert.email.preheader":
      "Alerta de super-admin de {{app_name}}.",
    "super_admin_alert.email.footer":
      "Recibes este aviso porque eres super-admin de {{app_name}}.",

    "audit_digest.title": "Informe de auditoria diaria ({{count}} hallazgos)",
    "audit_digest.body":
      "Resumen: {{critical}} criticos, {{high}} altos, {{medium}} medios, {{low}} bajos, {{info}} info.",
    "audit_digest.subject":
      "Informe de auditoria diaria de {{app_name}} ({{count}} hallazgos)",
    "audit_digest.no_issues": "Todo en orden. Sin problemas detectados.",
    "audit_digest.top_findings": "Principales hallazgos",
  },
  de: {
    "super_admin_alert.user_registered.title": "Neue Anmeldung",
    "super_admin_alert.user_registered.body":
      "{{username}} ({{email}}) hat sich gerade registriert. Nutzer insgesamt: {{total_users}}.",

    "super_admin_alert.user_role_changed.title": "Rolle geaendert: {{username}}",
    "super_admin_alert.user_role_changed.body":
      "Die Rolle von {{username}} ({{email}}) wurde geaendert: {{prev_role}} -> {{new_role}}. Aktuelle Verteilung: {{roles_breakdown}}.",

    "super_admin_alert.user_deleted.title": "Nutzer geloescht: {{username}}",
    "super_admin_alert.user_deleted.body":
      "{{username}} ({{email}}) hat das Konto geloescht. Es bleiben {{total_users}} Nutzer.",

    "super_admin_alert.plan_changed.title": "Plan geaendert: {{username}}",
    "super_admin_alert.plan_changed.body":
      "{{username}} ({{email}}) {{action}}: {{prev_plan}} -> {{new_plan}}.",

    "super_admin_alert.email.preheader":
      "Super-Admin-Benachrichtigung von {{app_name}}.",
    "super_admin_alert.email.footer":
      "Du erhaeltst diese Nachricht, weil du Super-Admin von {{app_name}} bist.",

    "audit_digest.title": "Taeglicher Audit-Bericht ({{count}} Findings)",
    "audit_digest.body":
      "Zusammenfassung: {{critical}} kritisch, {{high}} hoch, {{medium}} mittel, {{low}} niedrig, {{info}} info.",
    "audit_digest.subject":
      "Taeglicher Audit-Bericht von {{app_name}} ({{count}} Findings)",
    "audit_digest.no_issues": "Alles in Ordnung. Keine Probleme erkannt.",
    "audit_digest.top_findings": "Wichtigste Findings",
  },
  fr: {
    "super_admin_alert.user_registered.title": "Nouvelle inscription",
    "super_admin_alert.user_registered.body":
      "{{username}} ({{email}}) vient de s'inscrire. Total d'utilisateurs : {{total_users}}.",

    "super_admin_alert.user_role_changed.title": "Role modifie : {{username}}",
    "super_admin_alert.user_role_changed.body":
      "{{username}} ({{email}}) a change de role : {{prev_role}} -> {{new_role}}. Repartition actuelle : {{roles_breakdown}}.",

    "super_admin_alert.user_deleted.title":
      "Utilisateur supprime : {{username}}",
    "super_admin_alert.user_deleted.body":
      "{{username}} ({{email}}) a supprime son compte. Il reste {{total_users}} utilisateurs.",

    "super_admin_alert.plan_changed.title": "Plan modifie : {{username}}",
    "super_admin_alert.plan_changed.body":
      "{{username}} ({{email}}) {{action}} : {{prev_plan}} -> {{new_plan}}.",

    "super_admin_alert.email.preheader":
      "Alerte super-admin de {{app_name}}.",
    "super_admin_alert.email.footer":
      "Tu recois cet email parce que tu es super-admin de {{app_name}}.",

    "audit_digest.title": "Rapport d'audit quotidien ({{count}} resultats)",
    "audit_digest.body":
      "Resume : {{critical}} critiques, {{high}} eleves, {{medium}} moyens, {{low}} faibles, {{info}} info.",
    "audit_digest.subject":
      "Rapport d'audit quotidien de {{app_name}} ({{count}} resultats)",
    "audit_digest.no_issues": "Tout va bien. Aucun probleme detecte.",
    "audit_digest.top_findings": "Principaux resultats",
  },
  it: {
    "super_admin_alert.user_registered.title": "Nuova registrazione",
    "super_admin_alert.user_registered.body":
      "{{username}} ({{email}}) si e appena registrato. Totale utenti: {{total_users}}.",

    "super_admin_alert.user_role_changed.title":
      "Ruolo cambiato: {{username}}",
    "super_admin_alert.user_role_changed.body":
      "{{username}} ({{email}}) ha cambiato ruolo: {{prev_role}} -> {{new_role}}. Distribuzione attuale: {{roles_breakdown}}.",

    "super_admin_alert.user_deleted.title": "Utente eliminato: {{username}}",
    "super_admin_alert.user_deleted.body":
      "{{username}} ({{email}}) ha eliminato il suo account. Restano {{total_users}} utenti.",

    "super_admin_alert.plan_changed.title": "Piano cambiato: {{username}}",
    "super_admin_alert.plan_changed.body":
      "{{username}} ({{email}}) {{action}}: {{prev_plan}} -> {{new_plan}}.",

    "super_admin_alert.email.preheader":
      "Avviso super-admin da {{app_name}}.",
    "super_admin_alert.email.footer":
      "Ricevi questo messaggio perche sei super-admin di {{app_name}}.",

    "audit_digest.title": "Report audit giornaliero ({{count}} risultati)",
    "audit_digest.body":
      "Riepilogo: {{critical}} critici, {{high}} alti, {{medium}} medi, {{low}} bassi, {{info}} info.",
    "audit_digest.subject":
      "Report audit giornaliero di {{app_name}} ({{count}} risultati)",
    "audit_digest.no_issues": "Tutto a posto. Nessun problema rilevato.",
    "audit_digest.top_findings": "Risultati principali",
  },
  pt: {
    "super_admin_alert.user_registered.title": "Novo registo",
    "super_admin_alert.user_registered.body":
      "{{username}} ({{email}}) acabou de se registar. Total de utilizadores: {{total_users}}.",

    "super_admin_alert.user_role_changed.title":
      "Papel alterado: {{username}}",
    "super_admin_alert.user_role_changed.body":
      "{{username}} ({{email}}) mudou de papel: {{prev_role}} -> {{new_role}}. Distribuicao atual: {{roles_breakdown}}.",

    "super_admin_alert.user_deleted.title":
      "Utilizador eliminado: {{username}}",
    "super_admin_alert.user_deleted.body":
      "{{username}} ({{email}}) eliminou a conta. Restam {{total_users}} utilizadores.",

    "super_admin_alert.plan_changed.title":
      "Plano alterado: {{username}}",
    "super_admin_alert.plan_changed.body":
      "{{username}} ({{email}}) {{action}}: {{prev_plan}} -> {{new_plan}}.",

    "super_admin_alert.email.preheader":
      "Alerta de super-admin de {{app_name}}.",
    "super_admin_alert.email.footer":
      "Recebes esta mensagem porque es super-admin de {{app_name}}.",

    "audit_digest.title": "Relatorio de auditoria diaria ({{count}} achados)",
    "audit_digest.body":
      "Resumo: {{critical}} criticos, {{high}} altos, {{medium}} medios, {{low}} baixos, {{info}} info.",
    "audit_digest.subject":
      "Relatorio de auditoria diaria de {{app_name}} ({{count}} achados)",
    "audit_digest.no_issues": "Tudo bem. Nenhum problema detetado.",
    "audit_digest.top_findings": "Principais achados",
  },
  ru: {
    "super_admin_alert.user_registered.title": "Новая регистрация",
    "super_admin_alert.user_registered.body":
      "{{username}} ({{email}}) только что зарегистрировался. Всего пользователей: {{total_users}}.",

    "super_admin_alert.user_role_changed.title":
      "Роль изменена: {{username}}",
    "super_admin_alert.user_role_changed.body":
      "У {{username}} ({{email}}) изменена роль: {{prev_role}} -> {{new_role}}. Текущее распределение: {{roles_breakdown}}.",

    "super_admin_alert.user_deleted.title": "Пользователь удалён: {{username}}",
    "super_admin_alert.user_deleted.body":
      "{{username}} ({{email}}) удалил аккаунт. Осталось {{total_users}} пользователей.",

    "super_admin_alert.plan_changed.title": "Смена плана: {{username}}",
    "super_admin_alert.plan_changed.body":
      "{{username}} ({{email}}) {{action}}: {{prev_plan}} -> {{new_plan}}.",

    "super_admin_alert.email.preheader":
      "Оповещение для супер-админа от {{app_name}}.",
    "super_admin_alert.email.footer":
      "Вы получили это письмо, так как являетесь супер-админом {{app_name}}.",

    "audit_digest.title": "Ежедневный отчёт аудита ({{count}} находок)",
    "audit_digest.body":
      "Сводка: {{critical}} критических, {{high}} высоких, {{medium}} средних, {{low}} низких, {{info}} информационных.",
    "audit_digest.subject":
      "Ежедневный отчёт аудита от {{app_name}} ({{count}} находок)",
    "audit_digest.no_issues": "Всё в порядке. Проблем не обнаружено.",
    "audit_digest.top_findings": "Главные находки",
  },
  uk: {
    "super_admin_alert.user_registered.title": "Нова реєстрація",
    "super_admin_alert.user_registered.body":
      "{{username}} ({{email}}) щойно зареєструвався. Усього користувачів: {{total_users}}.",

    "super_admin_alert.user_role_changed.title": "Роль змінено: {{username}}",
    "super_admin_alert.user_role_changed.body":
      "У {{username}} ({{email}}) змінено роль: {{prev_role}} -> {{new_role}}. Поточний розподіл: {{roles_breakdown}}.",

    "super_admin_alert.user_deleted.title":
      "Користувача видалено: {{username}}",
    "super_admin_alert.user_deleted.body":
      "{{username}} ({{email}}) видалив акаунт. Залишилось {{total_users}} користувачів.",

    "super_admin_alert.plan_changed.title": "Зміна плану: {{username}}",
    "super_admin_alert.plan_changed.body":
      "{{username}} ({{email}}) {{action}}: {{prev_plan}} -> {{new_plan}}.",

    "super_admin_alert.email.preheader":
      "Сповіщення для супер-адміна від {{app_name}}.",
    "super_admin_alert.email.footer":
      "Ви отримали цей лист, бо ви супер-адмін {{app_name}}.",

    "audit_digest.title": "Щоденний звіт аудиту ({{count}} знахідок)",
    "audit_digest.body":
      "Підсумок: {{critical}} критичних, {{high}} високих, {{medium}} середніх, {{low}} низьких, {{info}} інформаційних.",
    "audit_digest.subject":
      "Щоденний звіт аудиту від {{app_name}} ({{count}} знахідок)",
    "audit_digest.no_issues": "Усе гаразд. Проблем не виявлено.",
    "audit_digest.top_findings": "Головні знахідки",
  },
};

function interpolate(tpl: string, params: Record<string, string>): string {
  return tpl.replace(/\{\{(\w+)\}\}/g, (_, k) => params[k] ?? "");
}

/// Devuelve la string para `key` en `locale`. Si la clave no esta en el
/// locale, cae a `en`. Si tampoco esta en `en`, devuelve la clave (asi
/// los huecos en el catalogo se ven en produccion pero no rompen).
export function t(
  locale: string | undefined | null,
  key: string,
  params: Record<string, string> = {},
): string {
  const loc = normalizeLocale(locale);
  const tpl = CATALOG[loc][key] ?? CATALOG.en[key] ?? key;
  return interpolate(tpl, params);
}

// ─── Plan-change action dictionary ──────────────────────────────────────────
// El EF `notify-super-admins` (event `plan.changed`) recibe un `action`
// canonico ('subscribed' | 'canceled' | 'upgrade' | 'downgrade' |
// 'plan_changed') y lo traduce con `tAction(locale, action)` antes de
// pasarlo a `t()` como placeholder {{action}}. Asi el body del email
// queda 100% en el idioma del super-admin.
const ACTION_CATALOG: Record<Locale, Record<string, string>> = {
  en: {
    subscribed: "subscribed",
    canceled: "canceled their subscription",
    upgrade: "upgraded",
    downgrade: "downgraded",
    plan_changed: "changed plan",
  },
  es: {
    subscribed: "se ha suscrito",
    canceled: "ha cancelado la suscripcion",
    upgrade: "ha subido de plan",
    downgrade: "ha bajado de plan",
    plan_changed: "cambio de plan",
  },
  de: {
    subscribed: "hat ein Abo abgeschlossen",
    canceled: "hat das Abo gekuendigt",
    upgrade: "hat ein Upgrade durchgefuehrt",
    downgrade: "hat ein Downgrade durchgefuehrt",
    plan_changed: "hat den Plan gewechselt",
  },
  fr: {
    subscribed: "s'est abonne",
    canceled: "a annule son abonnement",
    upgrade: "a effectue une mise a niveau",
    downgrade: "a retrograde son plan",
    plan_changed: "a change de plan",
  },
  it: {
    subscribed: "si e abbonato",
    canceled: "ha annullato l'abbonamento",
    upgrade: "ha effettuato l'upgrade",
    downgrade: "ha effettuato il downgrade",
    plan_changed: "ha cambiato piano",
  },
  pt: {
    subscribed: "subscreveu",
    canceled: "cancelou a subscricao",
    upgrade: "fez upgrade",
    downgrade: "fez downgrade",
    plan_changed: "mudou de plano",
  },
  ru: {
    subscribed: "оформил подписку",
    canceled: "отменил подписку",
    upgrade: "повысил план",
    downgrade: "понизил план",
    plan_changed: "сменил план",
  },
  uk: {
    subscribed: "оформив підписку",
    canceled: "скасував підписку",
    upgrade: "підвищив план",
    downgrade: "понизив план",
    plan_changed: "змінив план",
  },
};

/// Traduce un `action` canonico al idioma del recipient. Si el action
/// no existe en el diccionario (caso futuro), devuelve la cadena cruda
/// para que al menos quede legible en ingles.
export function tAction(
  locale: string | undefined | null,
  action: string,
): string {
  const loc = normalizeLocale(locale);
  return ACTION_CATALOG[loc][action]
    ?? ACTION_CATALOG.en[action]
    ?? action;
}
