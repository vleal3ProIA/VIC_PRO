// ============================================================================
// Email templates con i18n + soporte dark/light via @media query
// ----------------------------------------------------------------------------
// Sistema minimal de templates HTML para los 6 tipos de email
// transaccional + un wrapper comun (header + footer + branding).
//
// Decisiones de diseño:
//   - **HTML inline-style only**: los clientes de email (Gmail, Outlook,
//     iOS Mail) no soportan stylesheets externos ni <style> en algunos
//     casos. Todo va inline excepto el bloque @media de dark mode (que
//     los clientes modernos sí respetan).
//   - **Tabla-based layout**: Outlook 2007+ no soporta flex/grid. La
//     unica forma cross-client es <table>.
//   - **600px max width**: standard del sector (Apple Mail, Litmus, etc.)
//   - **Dark mode**: detectamos `prefers-color-scheme: dark` y invertimos
//     colores. Funciona en Gmail Android, Apple Mail, Outlook mobile.
//   - **Locale-aware**: los strings vienen de un diccionario interno
//     por idioma; el HTML estructural es el mismo.
//
// Anyadir un idioma nuevo: añadir entrada al objeto `i18n` para cada
// tipo. Si falta una traduccion, cae a 'en'.
// ============================================================================

import type { EmailType } from "./email.ts";

const SUPPORTED_LOCALES = [
  "en",
  "es",
  "de",
  "fr",
  "it",
  "pt",
  "ru",
  "uk",
] as const;
type Locale = (typeof SUPPORTED_LOCALES)[number];

function normalizeLocale(raw: string | undefined | null): Locale {
  if (!raw) return "en";
  const short = raw.toLowerCase().split(/[-_]/)[0];
  return (SUPPORTED_LOCALES as readonly string[]).includes(short)
    ? (short as Locale)
    : "en";
}

// ─────────────────────── Diccionario por tipo ───────────────────────

// Cada tipo tiene los strings que VARIAN por contenido (titulo, body,
// cta, footer). Los placeholders son `{{var}}` interpolados con `data`.

type TypeI18nEntry = {
  subject: string;
  preheader: string;
  greeting: string;
  bodyHtml: string; // permite HTML basico (links, <strong>, <br>)
  ctaLabel?: string;
  ctaUrl?: string; // si no hay, no se pinta el boton
  footerNote: string;
};

type TypeI18n = Record<Locale, TypeI18nEntry>;

// Soporte parcial: 'en' es obligatorio, resto cae a 'en' si falta.
const STR: Record<EmailType, Partial<TypeI18n> & { en: TypeI18nEntry }> = {
  signup: {
    en: {
      subject: "Confirm your email at {{app_name}}",
      preheader: "Just one click to activate your account.",
      greeting: "Welcome!",
      bodyHtml:
        "Thanks for signing up at <strong>{{app_name}}</strong>. " +
        "Please confirm your email to finish creating your account.",
      ctaLabel: "Confirm email",
      ctaUrl: "{{action_url}}",
      footerNote:
        "If you didn't sign up, you can safely ignore this email.",
    },
    es: {
      subject: "Confirma tu email en {{app_name}}",
      preheader: "Un solo clic para activar tu cuenta.",
      greeting: "¡Bienvenido!",
      bodyHtml:
        "Gracias por registrarte en <strong>{{app_name}}</strong>. " +
        "Confirma tu email para terminar de crear tu cuenta.",
      ctaLabel: "Confirmar email",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Si no te registraste, puedes ignorar este email sin problema.",
    },
    de: {
      subject: "Bestätige deine E-Mail bei {{app_name}}",
      preheader: "Nur ein Klick zur Aktivierung.",
      greeting: "Willkommen!",
      bodyHtml:
        "Danke für deine Registrierung bei <strong>{{app_name}}</strong>. " +
        "Bestätige bitte deine E-Mail, um dein Konto fertigzustellen.",
      ctaLabel: "E-Mail bestätigen",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Wenn du dich nicht registriert hast, ignoriere diese E-Mail einfach.",
    },
    fr: {
      subject: "Confirme ton email sur {{app_name}}",
      preheader: "Un seul clic pour activer ton compte.",
      greeting: "Bienvenue !",
      bodyHtml:
        "Merci de t'être inscrit sur <strong>{{app_name}}</strong>. " +
        "Confirme ton email pour finaliser la création de ton compte.",
      ctaLabel: "Confirmer l'email",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Si tu ne t'es pas inscrit, ignore simplement cet email.",
    },
    it: {
      subject: "Conferma la tua email su {{app_name}}",
      preheader: "Un solo clic per attivare il tuo account.",
      greeting: "Benvenuto!",
      bodyHtml:
        "Grazie per esserti registrato su <strong>{{app_name}}</strong>. " +
        "Conferma la tua email per completare la creazione dell'account.",
      ctaLabel: "Conferma email",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Se non ti sei registrato, puoi ignorare questa email.",
    },
    pt: {
      subject: "Confirma o teu email em {{app_name}}",
      preheader: "Apenas um clique para ativar a tua conta.",
      greeting: "Bem-vindo!",
      bodyHtml:
        "Obrigado por te registares em <strong>{{app_name}}</strong>. " +
        "Confirma o teu email para terminar a criação da tua conta.",
      ctaLabel: "Confirmar email",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Se não te registaste, podes ignorar este email sem problema.",
    },
    ru: {
      subject: "Подтвердите email на {{app_name}}",
      preheader: "Один клик — и ваш аккаунт активен.",
      greeting: "Добро пожаловать!",
      bodyHtml:
        "Спасибо за регистрацию на <strong>{{app_name}}</strong>. " +
        "Подтвердите email, чтобы завершить создание аккаунта.",
      ctaLabel: "Подтвердить email",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Если вы не регистрировались, просто игнорируйте это письмо.",
    },
    uk: {
      subject: "Підтвердіть email на {{app_name}}",
      preheader: "Один клік — і ваш акаунт активний.",
      greeting: "Ласкаво просимо!",
      bodyHtml:
        "Дякуємо за реєстрацію на <strong>{{app_name}}</strong>. " +
        "Підтвердіть email, щоб завершити створення акаунту.",
      ctaLabel: "Підтвердити email",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Якщо ви не реєструвалися, просто проігноруйте цей лист.",
    },
  },
  recovery: {
    en: {
      subject: "Reset your {{app_name}} password",
      preheader: "Use the link below to set a new password.",
      greeting: "Password reset",
      bodyHtml:
        "Someone requested a password reset for your <strong>{{app_name}}</strong> account. " +
        "Click the button below to choose a new password. This link expires in 1 hour.",
      ctaLabel: "Reset password",
      ctaUrl: "{{action_url}}",
      footerNote:
        "If you didn't request this, you can safely ignore this email — your password won't change.",
    },
    es: {
      subject: "Restablece tu contraseña de {{app_name}}",
      preheader: "Usa el enlace de abajo para elegir una nueva contraseña.",
      greeting: "Restablecimiento de contraseña",
      bodyHtml:
        "Alguien pidió restablecer la contraseña de tu cuenta en <strong>{{app_name}}</strong>. " +
        "Pulsa el botón para elegir una nueva. El enlace caduca en 1 hora.",
      ctaLabel: "Restablecer contraseña",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Si no lo pediste tú, ignora este email — tu contraseña no cambiará.",
    },
    de: {
      subject: "Setze dein Passwort bei {{app_name}} zurück",
      preheader: "Wähle ein neues Passwort über den Link unten.",
      greeting: "Passwort zurücksetzen",
      bodyHtml:
        "Jemand hat eine Passwortzurücksetzung für dein <strong>{{app_name}}</strong>-Konto angefordert. " +
        "Klicke auf den Button, um ein neues Passwort zu wählen. Der Link läuft in 1 Stunde ab.",
      ctaLabel: "Passwort zurücksetzen",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Wenn du das nicht angefordert hast, ignoriere diese E-Mail — dein Passwort bleibt unverändert.",
    },
    fr: {
      subject: "Réinitialise ton mot de passe {{app_name}}",
      preheader: "Choisis un nouveau mot de passe via le lien ci-dessous.",
      greeting: "Réinitialisation du mot de passe",
      bodyHtml:
        "Quelqu'un a demandé une réinitialisation pour ton compte <strong>{{app_name}}</strong>. " +
        "Clique sur le bouton pour choisir un nouveau mot de passe. Le lien expire dans 1 heure.",
      ctaLabel: "Réinitialiser le mot de passe",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Si tu n'as pas fait cette demande, ignore cet email — ton mot de passe ne changera pas.",
    },
    it: {
      subject: "Reimposta la password di {{app_name}}",
      preheader: "Usa il link sotto per scegliere una nuova password.",
      greeting: "Reimposta password",
      bodyHtml:
        "Qualcuno ha richiesto il reset della password per il tuo account <strong>{{app_name}}</strong>. " +
        "Clicca il pulsante per sceglierne una nuova. Il link scade in 1 ora.",
      ctaLabel: "Reimposta password",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Se non l'hai richiesto tu, ignora questa email — la tua password non cambierà.",
    },
    pt: {
      subject: "Repõe a tua palavra-passe de {{app_name}}",
      preheader: "Usa o link abaixo para escolher uma nova palavra-passe.",
      greeting: "Reposição de palavra-passe",
      bodyHtml:
        "Alguém pediu uma reposição de palavra-passe para a tua conta <strong>{{app_name}}</strong>. " +
        "Clica no botão para escolher uma nova. O link expira em 1 hora.",
      ctaLabel: "Repor palavra-passe",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Se não foste tu, podes ignorar este email — a palavra-passe não vai mudar.",
    },
    ru: {
      subject: "Сброс пароля {{app_name}}",
      preheader: "По ссылке ниже задайте новый пароль.",
      greeting: "Сброс пароля",
      bodyHtml:
        "Кто-то запросил сброс пароля для вашего аккаунта <strong>{{app_name}}</strong>. " +
        "Нажмите кнопку, чтобы задать новый пароль. Срок ссылки — 1 час.",
      ctaLabel: "Сбросить пароль",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Если это не вы — просто игнорируйте письмо, пароль не изменится.",
    },
    uk: {
      subject: "Скидання пароля {{app_name}}",
      preheader: "За посиланням нижче задайте новий пароль.",
      greeting: "Скидання пароля",
      bodyHtml:
        "Хтось запросив скидання пароля для вашого акаунту <strong>{{app_name}}</strong>. " +
        "Натисніть кнопку, щоб обрати новий пароль. Посилання дійсне 1 годину.",
      ctaLabel: "Скинути пароль",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Якщо це не ви — просто проігноруйте лист, пароль не зміниться.",
    },
  },
  magic_link: {
    en: {
      subject: "Your {{app_name}} sign-in link",
      preheader: "Click the button to sign in.",
      greeting: "Sign in",
      bodyHtml:
        "Click the button below to sign in to <strong>{{app_name}}</strong>. " +
        "This link is single-use and expires in 1 hour.",
      ctaLabel: "Sign in",
      ctaUrl: "{{action_url}}",
      footerNote:
        "If you didn't request this, ignore the email.",
    },
    es: {
      subject: "Tu enlace de acceso a {{app_name}}",
      preheader: "Pulsa el botón para iniciar sesión.",
      greeting: "Iniciar sesión",
      bodyHtml:
        "Pulsa el botón para entrar en <strong>{{app_name}}</strong>. " +
        "Este enlace es de un solo uso y caduca en 1 hora.",
      ctaLabel: "Iniciar sesión",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Si no lo pediste tú, ignora este email.",
    },
    de: {
      subject: "Dein {{app_name}} Anmelde-Link",
      preheader: "Klicke den Button, um dich anzumelden.",
      greeting: "Anmelden",
      bodyHtml:
        "Klicke den Button, um dich bei <strong>{{app_name}}</strong> anzumelden. " +
        "Der Link ist einmalig und läuft in 1 Stunde ab.",
      ctaLabel: "Anmelden",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Wenn du das nicht angefordert hast, ignoriere die E-Mail.",
    },
    fr: {
      subject: "Ton lien de connexion {{app_name}}",
      preheader: "Clique sur le bouton pour te connecter.",
      greeting: "Connexion",
      bodyHtml:
        "Clique sur le bouton pour te connecter à <strong>{{app_name}}</strong>. " +
        "Ce lien est à usage unique et expire dans 1 heure.",
      ctaLabel: "Se connecter",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Si tu n'as pas fait cette demande, ignore cet email.",
    },
    it: {
      subject: "Il tuo link di accesso a {{app_name}}",
      preheader: "Clicca il pulsante per accedere.",
      greeting: "Accedi",
      bodyHtml:
        "Clicca il pulsante per accedere a <strong>{{app_name}}</strong>. " +
        "Questo link è monouso e scade in 1 ora.",
      ctaLabel: "Accedi",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Se non l'hai richiesto tu, ignora questa email.",
    },
    pt: {
      subject: "O teu link de acesso a {{app_name}}",
      preheader: "Clica no botão para iniciar sessão.",
      greeting: "Iniciar sessão",
      bodyHtml:
        "Clica no botão para entrar em <strong>{{app_name}}</strong>. " +
        "Este link é de uso único e expira em 1 hora.",
      ctaLabel: "Iniciar sessão",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Se não foste tu, ignora este email.",
    },
    ru: {
      subject: "Ваша ссылка для входа в {{app_name}}",
      preheader: "Нажмите кнопку, чтобы войти.",
      greeting: "Вход",
      bodyHtml:
        "Нажмите кнопку, чтобы войти в <strong>{{app_name}}</strong>. " +
        "Ссылка одноразовая, действует 1 час.",
      ctaLabel: "Войти",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Если это не вы — просто игнорируйте письмо.",
    },
    uk: {
      subject: "Ваше посилання для входу в {{app_name}}",
      preheader: "Натисніть кнопку, щоб увійти.",
      greeting: "Вхід",
      bodyHtml:
        "Натисніть кнопку, щоб увійти в <strong>{{app_name}}</strong>. " +
        "Посилання одноразове, дійсне 1 годину.",
      ctaLabel: "Увійти",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Якщо це не ви — просто проігноруйте лист.",
    },
  },
  change_email: {
    en: {
      subject: "Confirm your new email at {{app_name}}",
      preheader: "Click to confirm the change.",
      greeting: "Email change",
      bodyHtml:
        "Click below to confirm <strong>{{new_email}}</strong> as the new email of your <strong>{{app_name}}</strong> account.",
      ctaLabel: "Confirm new email",
      ctaUrl: "{{action_url}}",
      footerNote:
        "If you didn't request this change, contact support immediately.",
    },
    es: {
      subject: "Confirma tu nuevo email en {{app_name}}",
      preheader: "Pulsa para confirmar el cambio.",
      greeting: "Cambio de email",
      bodyHtml:
        "Pulsa abajo para confirmar <strong>{{new_email}}</strong> como el nuevo email de tu cuenta de <strong>{{app_name}}</strong>.",
      ctaLabel: "Confirmar email nuevo",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Si no pediste este cambio, contacta con soporte inmediatamente.",
    },
    de: {
      subject: "Bestätige deine neue E-Mail bei {{app_name}}",
      preheader: "Klicke zur Bestätigung.",
      greeting: "E-Mail-Wechsel",
      bodyHtml:
        "Klicke unten, um <strong>{{new_email}}</strong> als neue E-Mail deines <strong>{{app_name}}</strong>-Kontos zu bestätigen.",
      ctaLabel: "Neue E-Mail bestätigen",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Wenn du diese Änderung nicht angefordert hast, kontaktiere sofort den Support.",
    },
    fr: {
      subject: "Confirme ton nouvel email sur {{app_name}}",
      preheader: "Clique pour confirmer le changement.",
      greeting: "Changement d'email",
      bodyHtml:
        "Clique ci-dessous pour confirmer <strong>{{new_email}}</strong> comme nouvel email de ton compte <strong>{{app_name}}</strong>.",
      ctaLabel: "Confirmer le nouvel email",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Si tu n'as pas demandé ce changement, contacte le support immédiatement.",
    },
    it: {
      subject: "Conferma la tua nuova email su {{app_name}}",
      preheader: "Clicca per confermare il cambio.",
      greeting: "Cambio email",
      bodyHtml:
        "Clicca sotto per confermare <strong>{{new_email}}</strong> come nuova email del tuo account <strong>{{app_name}}</strong>.",
      ctaLabel: "Conferma nuova email",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Se non hai richiesto questo cambio, contatta il supporto immediatamente.",
    },
    pt: {
      subject: "Confirma o teu novo email em {{app_name}}",
      preheader: "Clica para confirmar a alteração.",
      greeting: "Alteração de email",
      bodyHtml:
        "Clica abaixo para confirmar <strong>{{new_email}}</strong> como o novo email da tua conta <strong>{{app_name}}</strong>.",
      ctaLabel: "Confirmar novo email",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Se não pediste esta alteração, contacta o suporte imediatamente.",
    },
    ru: {
      subject: "Подтвердите новый email на {{app_name}}",
      preheader: "Нажмите для подтверждения смены.",
      greeting: "Смена email",
      bodyHtml:
        "Нажмите ниже, чтобы подтвердить <strong>{{new_email}}</strong> как новый email вашего аккаунта <strong>{{app_name}}</strong>.",
      ctaLabel: "Подтвердить новый email",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Если вы не запрашивали эту смену, немедленно свяжитесь со службой поддержки.",
    },
    uk: {
      subject: "Підтвердіть новий email на {{app_name}}",
      preheader: "Натисніть для підтвердження зміни.",
      greeting: "Зміна email",
      bodyHtml:
        "Натисніть нижче, щоб підтвердити <strong>{{new_email}}</strong> як новий email вашого акаунту <strong>{{app_name}}</strong>.",
      ctaLabel: "Підтвердити новий email",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Якщо ви не запитували цю зміну, негайно зверніться до підтримки.",
    },
  },
  invite: {
    en: {
      subject: "You're invited to {{tenant_name}} on {{app_name}}",
      preheader: "Accept the invitation to join the team.",
      greeting: "You're invited",
      bodyHtml:
        "<strong>{{inviter_name}}</strong> has invited you to join <strong>{{tenant_name}}</strong> on <strong>{{app_name}}</strong>. " +
        "Click below to accept and get started.",
      ctaLabel: "Accept invitation",
      ctaUrl: "{{action_url}}",
      footerNote:
        "This invitation expires in 7 days.",
    },
    es: {
      subject: "Te han invitado a {{tenant_name}} en {{app_name}}",
      preheader: "Acepta la invitación para unirte al equipo.",
      greeting: "Te han invitado",
      bodyHtml:
        "<strong>{{inviter_name}}</strong> te ha invitado a unirte a <strong>{{tenant_name}}</strong> en <strong>{{app_name}}</strong>. " +
        "Pulsa abajo para aceptar y empezar.",
      ctaLabel: "Aceptar invitación",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Esta invitación caduca en 7 días.",
    },
    de: {
      subject: "Du wurdest zu {{tenant_name}} auf {{app_name}} eingeladen",
      preheader: "Nimm die Einladung an, um dem Team beizutreten.",
      greeting: "Du wurdest eingeladen",
      bodyHtml:
        "<strong>{{inviter_name}}</strong> hat dich eingeladen, <strong>{{tenant_name}}</strong> auf <strong>{{app_name}}</strong> beizutreten. " +
        "Klicke unten, um anzunehmen.",
      ctaLabel: "Einladung annehmen",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Diese Einladung läuft in 7 Tagen ab.",
    },
    fr: {
      subject: "Tu es invité à {{tenant_name}} sur {{app_name}}",
      preheader: "Accepte l'invitation pour rejoindre l'équipe.",
      greeting: "Tu es invité",
      bodyHtml:
        "<strong>{{inviter_name}}</strong> t'a invité à rejoindre <strong>{{tenant_name}}</strong> sur <strong>{{app_name}}</strong>. " +
        "Clique ci-dessous pour accepter.",
      ctaLabel: "Accepter l'invitation",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Cette invitation expire dans 7 jours.",
    },
    it: {
      subject: "Sei invitato a {{tenant_name}} su {{app_name}}",
      preheader: "Accetta l'invito per unirti al team.",
      greeting: "Sei invitato",
      bodyHtml:
        "<strong>{{inviter_name}}</strong> ti ha invitato a unirti a <strong>{{tenant_name}}</strong> su <strong>{{app_name}}</strong>. " +
        "Clicca sotto per accettare.",
      ctaLabel: "Accetta invito",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Questo invito scade in 7 giorni.",
    },
    pt: {
      subject: "Foste convidado para {{tenant_name}} em {{app_name}}",
      preheader: "Aceita o convite para te juntares à equipa.",
      greeting: "Foste convidado",
      bodyHtml:
        "<strong>{{inviter_name}}</strong> convidou-te para te juntares a <strong>{{tenant_name}}</strong> em <strong>{{app_name}}</strong>. " +
        "Clica abaixo para aceitar.",
      ctaLabel: "Aceitar convite",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Este convite expira em 7 dias.",
    },
    ru: {
      subject: "Вас пригласили в {{tenant_name}} на {{app_name}}",
      preheader: "Примите приглашение, чтобы присоединиться к команде.",
      greeting: "Вас пригласили",
      bodyHtml:
        "<strong>{{inviter_name}}</strong> приглашает вас присоединиться к <strong>{{tenant_name}}</strong> на <strong>{{app_name}}</strong>. " +
        "Нажмите ниже, чтобы принять.",
      ctaLabel: "Принять приглашение",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Срок приглашения — 7 дней.",
    },
    uk: {
      subject: "Вас запросили до {{tenant_name}} на {{app_name}}",
      preheader: "Прийміть запрошення, щоб приєднатися до команди.",
      greeting: "Вас запросили",
      bodyHtml:
        "<strong>{{inviter_name}}</strong> запрошує вас приєднатися до <strong>{{tenant_name}}</strong> на <strong>{{app_name}}</strong>. " +
        "Натисніть нижче, щоб прийняти.",
      ctaLabel: "Прийняти запрошення",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Це запрошення дійсне 7 днів.",
    },
  },
  plan_changed: {
    en: {
      subject: "Your {{app_name}} plan has changed to {{plan_name}}",
      preheader: "Here are the details of your new subscription.",
      greeting: "Plan updated",
      bodyHtml:
        "Your subscription on <strong>{{app_name}}</strong> has been updated to <strong>{{plan_name}}</strong>. " +
        "It will renew on <strong>{{period_end}}</strong>. " +
        "Your latest invoice is available in your account area.",
      ctaLabel: "View invoices",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Questions? Reply to this email and our team will help.",
    },
    es: {
      subject: "Tu plan de {{app_name}} ha cambiado a {{plan_name}}",
      preheader: "Aquí tienes los detalles de tu nueva suscripción.",
      greeting: "Plan actualizado",
      bodyHtml:
        "Tu suscripción en <strong>{{app_name}}</strong> se ha actualizado a <strong>{{plan_name}}</strong>. " +
        "Se renovará el <strong>{{period_end}}</strong>. " +
        "Tu última factura está disponible en tu área de cliente.",
      ctaLabel: "Ver facturas",
      ctaUrl: "{{action_url}}",
      footerNote:
        "¿Dudas? Responde a este email y nuestro equipo te ayudará.",
    },
    de: {
      subject: "Dein {{app_name}}-Plan wurde zu {{plan_name}} geändert",
      preheader: "Hier sind die Details deines neuen Abonnements.",
      greeting: "Plan aktualisiert",
      bodyHtml:
        "Dein Abo bei <strong>{{app_name}}</strong> wurde auf <strong>{{plan_name}}</strong> aktualisiert. " +
        "Es verlängert sich am <strong>{{period_end}}</strong>. " +
        "Deine letzte Rechnung findest du in deinem Konto.",
      ctaLabel: "Rechnungen ansehen",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Fragen? Antworte auf diese E-Mail und unser Team hilft dir.",
    },
    fr: {
      subject: "Ton plan {{app_name}} a changé pour {{plan_name}}",
      preheader: "Voici les détails de ton nouvel abonnement.",
      greeting: "Plan mis à jour",
      bodyHtml:
        "Ton abonnement à <strong>{{app_name}}</strong> a été mis à jour vers <strong>{{plan_name}}</strong>. " +
        "Il sera renouvelé le <strong>{{period_end}}</strong>. " +
        "Ta dernière facture est disponible dans ton espace client.",
      ctaLabel: "Voir les factures",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Des questions ? Réponds à cet email et notre équipe t'aidera.",
    },
    it: {
      subject: "Il tuo piano {{app_name}} è cambiato in {{plan_name}}",
      preheader: "Ecco i dettagli del tuo nuovo abbonamento.",
      greeting: "Piano aggiornato",
      bodyHtml:
        "Il tuo abbonamento su <strong>{{app_name}}</strong> è stato aggiornato a <strong>{{plan_name}}</strong>. " +
        "Si rinnoverà il <strong>{{period_end}}</strong>. " +
        "L'ultima fattura è disponibile nella tua area cliente.",
      ctaLabel: "Vedi fatture",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Domande? Rispondi a questa email e il nostro team ti aiuterà.",
    },
    pt: {
      subject: "O teu plano {{app_name}} mudou para {{plan_name}}",
      preheader: "Aqui estão os detalhes da tua nova subscrição.",
      greeting: "Plano atualizado",
      bodyHtml:
        "A tua subscrição em <strong>{{app_name}}</strong> foi atualizada para <strong>{{plan_name}}</strong>. " +
        "Vai renovar a <strong>{{period_end}}</strong>. " +
        "A última fatura está disponível na tua área de cliente.",
      ctaLabel: "Ver faturas",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Dúvidas? Responde a este email e a nossa equipa ajuda.",
    },
    ru: {
      subject: "Ваш план в {{app_name}} изменён на {{plan_name}}",
      preheader: "Подробности о вашей новой подписке.",
      greeting: "План обновлён",
      bodyHtml:
        "Ваша подписка на <strong>{{app_name}}</strong> обновлена до <strong>{{plan_name}}</strong>. " +
        "Продление: <strong>{{period_end}}</strong>. " +
        "Последний счёт доступен в личном кабинете.",
      ctaLabel: "Открыть счета",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Вопросы? Ответьте на это письмо, и наша команда поможет.",
    },
    uk: {
      subject: "Ваш план у {{app_name}} змінено на {{plan_name}}",
      preheader: "Деталі вашої нової підписки.",
      greeting: "План оновлено",
      bodyHtml:
        "Вашу підписку на <strong>{{app_name}}</strong> оновлено до <strong>{{plan_name}}</strong>. " +
        "Поновлення: <strong>{{period_end}}</strong>. " +
        "Останній рахунок доступний у вашому особистому кабінеті.",
      ctaLabel: "Відкрити рахунки",
      ctaUrl: "{{action_url}}",
      footerNote:
        "Питання? Відповідайте на цей лист, і наша команда допоможе.",
    },
  },
  broadcast: {
    en: {
      subject: "{{subject}}",
      preheader: "",
      greeting: "",
      bodyHtml: "{{body}}",
      footerNote: "",
    },
    es: {
      subject: "{{subject}}",
      preheader: "",
      greeting: "",
      bodyHtml: "{{body}}",
      footerNote: "",
    },
    de: {
      subject: "{{subject}}",
      preheader: "",
      greeting: "",
      bodyHtml: "{{body}}",
      footerNote: "",
    },
    fr: {
      subject: "{{subject}}",
      preheader: "",
      greeting: "",
      bodyHtml: "{{body}}",
      footerNote: "",
    },
    it: {
      subject: "{{subject}}",
      preheader: "",
      greeting: "",
      bodyHtml: "{{body}}",
      footerNote: "",
    },
    pt: {
      subject: "{{subject}}",
      preheader: "",
      greeting: "",
      bodyHtml: "{{body}}",
      footerNote: "",
    },
    ru: {
      subject: "{{subject}}",
      preheader: "",
      greeting: "",
      bodyHtml: "{{body}}",
      footerNote: "",
    },
    uk: {
      subject: "{{subject}}",
      preheader: "",
      greeting: "",
      bodyHtml: "{{body}}",
      footerNote: "",
    },
  },
  test: {
    en: {
      subject: "Test email from {{app_name}}",
      preheader: "SMTP test ping",
      greeting: "It works!",
      bodyHtml:
        "If you can read this, your SMTP configuration for <strong>{{app_name}}</strong> is working correctly.",
      footerNote: "Sent at {{sent_at}}.",
    },
    es: {
      subject: "Email de prueba desde {{app_name}}",
      preheader: "Prueba SMTP",
      greeting: "¡Funciona!",
      bodyHtml:
        "Si lees esto, la configuración SMTP de <strong>{{app_name}}</strong> está correcta.",
      footerNote: "Enviado en {{sent_at}}.",
    },
    de: {
      subject: "Test-E-Mail von {{app_name}}",
      preheader: "SMTP-Test",
      greeting: "Es funktioniert!",
      bodyHtml:
        "Wenn du das lesen kannst, ist die SMTP-Konfiguration für <strong>{{app_name}}</strong> korrekt.",
      footerNote: "Gesendet am {{sent_at}}.",
    },
    fr: {
      subject: "Email de test de {{app_name}}",
      preheader: "Test SMTP",
      greeting: "Ça marche !",
      bodyHtml:
        "Si tu peux lire ceci, la configuration SMTP de <strong>{{app_name}}</strong> est correcte.",
      footerNote: "Envoyé le {{sent_at}}.",
    },
    it: {
      subject: "Email di test da {{app_name}}",
      preheader: "Test SMTP",
      greeting: "Funziona!",
      bodyHtml:
        "Se puoi leggere questo, la configurazione SMTP di <strong>{{app_name}}</strong> è corretta.",
      footerNote: "Inviato il {{sent_at}}.",
    },
    pt: {
      subject: "Email de teste de {{app_name}}",
      preheader: "Teste SMTP",
      greeting: "Funciona!",
      bodyHtml:
        "Se consegues ler isto, a configuração SMTP de <strong>{{app_name}}</strong> está correta.",
      footerNote: "Enviado em {{sent_at}}.",
    },
    ru: {
      subject: "Тестовое письмо от {{app_name}}",
      preheader: "Проверка SMTP",
      greeting: "Работает!",
      bodyHtml:
        "Если вы это читаете, конфигурация SMTP для <strong>{{app_name}}</strong> работает корректно.",
      footerNote: "Отправлено {{sent_at}}.",
    },
    uk: {
      subject: "Тестовий лист від {{app_name}}",
      preheader: "Перевірка SMTP",
      greeting: "Працює!",
      bodyHtml:
        "Якщо ви це читаєте, конфігурація SMTP для <strong>{{app_name}}</strong> працює коректно.",
      footerNote: "Надіслано {{sent_at}}.",
    },
  },
};

// ─────────────────────── Renderer ───────────────────────

function interpolate(template: string, data: Record<string, string>): string {
  return template.replace(/\{\{(\w+)\}\}/g, (_, key) => {
    return data[key] ?? "";
  });
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export interface RenderedEmail {
  subject: string;
  htmlBody: string;
  textBody: string;
}

/**
 * Renderiza un email: combina el template del tipo + el wrapper
 * comun + el branding + la data dinamica.
 *
 * @param data Variables a interpolar en el template. Las claves
 *             dependen del tipo:
 *             - signup/recovery/magic_link: { action_url }
 *             - change_email: { action_url, new_email }
 *             - invite: { action_url, inviter_name, tenant_name }
 *             - plan_changed: { action_url, plan_name, period_end }
 *             - broadcast: { subject, body }
 *             - test: { sent_at }
 *             Todos los tipos heredan automaticamente { app_name }
 *             del branding.
 */
/// Modo visual del email. `system` -> el email se adapta al cliente de
/// correo via `@media (prefers-color-scheme)`. `light`/`dark` -> se fuerza
/// ese modo (ignora la preferencia del cliente), segun la preferencia
/// guardada del usuario (`profiles.theme_mode`).
export type EmailMode = "system" | "light" | "dark";

function normalizeMode(raw: string | undefined | null): EmailMode {
  return raw === "light" || raw === "dark" ? raw : "system";
}

export function renderEmail(params: {
  type: EmailType;
  locale: string;
  appName: string;
  data: Record<string, string>;
  mode?: string;
}): RenderedEmail {
  const { type, appName } = params;
  const loc = normalizeLocale(params.locale);
  const mode = normalizeMode(params.mode);
  const allStrings = STR[type];
  const strings = allStrings[loc] ?? allStrings.en;

  // Datos base: app_name siempre disponible.
  const baseData: Record<string, string> = {
    app_name: appName,
    ...params.data,
  };

  const subject = interpolate(strings.subject, baseData);
  const preheader = interpolate(strings.preheader, baseData);
  const greeting = interpolate(strings.greeting, baseData);
  const bodyHtml = interpolate(strings.bodyHtml, baseData);
  const footerNote = interpolate(strings.footerNote, baseData);

  const ctaUrl = strings.ctaUrl
    ? interpolate(strings.ctaUrl, baseData)
    : null;
  const ctaLabel = strings.ctaLabel ?? "";

  // Plain-text fallback: clientes que no muestran HTML.
  // Strip tags muy simple — suficiente para preview.
  const textBody = [
    greeting,
    "",
    bodyHtml.replace(/<[^>]+>/g, ""),
    "",
    ctaUrl ? `${ctaLabel}: ${ctaUrl}` : "",
    "",
    footerNote,
  ].filter(Boolean).join("\n");

  return {
    subject,
    htmlBody: wrapHtml({
      appName,
      preheader,
      greeting,
      bodyHtml,
      ctaLabel,
      ctaUrl,
      footerNote,
      mode,
    }),
    textBody,
  };
}

// ─────────────────────── HTML wrapper ───────────────────────

function wrapHtml(params: {
  appName: string;
  preheader: string;
  greeting: string;
  bodyHtml: string;
  ctaLabel: string;
  ctaUrl: string | null;
  footerNote: string;
  mode: EmailMode;
}): string {
  const {
    appName,
    preheader,
    greeting,
    bodyHtml,
    ctaLabel,
    ctaUrl,
    footerNote,
    mode,
  } = params;

  // Paleta segun el modo PREFERIDO del usuario (profiles.theme_mode):
  //   - dark  -> colores oscuros inline (siempre oscuro, ignora el cliente).
  //   - light -> colores claros inline (siempre claro, ignora el cliente).
  //   - system-> colores claros + bloque @media que invierte si el cliente
  //              de correo esta en dark (comportamiento adaptativo).
  const dark = mode === "dark";
  const c = dark
    ? {
      bg: "#0F172A",
      card: "#1E293B",
      heading: "#F1F5F9",
      body: "#E5E7EB",
      muted: "#94A3B8",
      divider: "#334155",
      brand: "#60A5FA",
      footer: "#94A3B8",
    }
    : {
      bg: "#F3F4F6",
      card: "#FFFFFF",
      heading: "#111827",
      body: "#374151",
      muted: "#6B7280",
      divider: "#E5E7EB",
      brand: "#2563EB",
      footer: "#9CA3AF",
    };

  // El @media solo en `system`: en light/dark el color ya esta forzado
  // inline y no queremos que el cliente lo cambie.
  const darkMediaBlock = mode === "system"
    ? `
      @media (prefers-color-scheme: dark) {
        body, .email-bg { background-color: #0F172A !important; }
        .card { background-color: #1E293B !important; color: #E5E7EB !important; }
        .text-muted { color: #94A3B8 !important; }
        .text-body { color: #E5E7EB !important; }
        .text-heading { color: #F1F5F9 !important; }
        .text-brand { color: #60A5FA !important; }
        .divider { border-top-color: #334155 !important; }
      }`
    : "";

  // Boton CTA: tabla por compat con Outlook. bg azul corporativo +
  // texto blanco. En dark mode mantenemos buen contraste invirtiendo
  // a azul claro / texto oscuro.
  const ctaBlock = ctaUrl
    ? `
      <tr><td style="padding: 24px 0;" align="center">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0">
          <tr><td style="border-radius: 6px; background-color: #2563EB;"
                   class="cta-button">
            <a href="${escapeHtml(ctaUrl)}"
               style="display: inline-block; padding: 12px 28px; color: #ffffff;
                      text-decoration: none; font-weight: 700; font-size: 15px;
                      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;"
               class="cta-button-link">
              ${escapeHtml(ctaLabel)}
            </a>
          </td></tr>
        </table>
      </td></tr>
      <tr><td style="padding: 0 0 8px 0;" align="center">
        <div style="font-size: 12px; color: #6B7280; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;">
          ${escapeHtml(ctaUrl)}
        </div>
      </td></tr>`
    : "";

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="color-scheme" content="${mode === "system" ? "light dark" : mode}" />
    <meta name="supported-color-schemes" content="${mode === "system" ? "light dark" : mode}" />
    <title>${escapeHtml(appName)}</title>
    <style>
      /* En modo `system` el email se adapta al cliente de correo via
         prefers-color-scheme. En light/dark el color ya va forzado inline. */${darkMediaBlock}
    </style>
  </head>
  <body class="email-bg" style="margin: 0; padding: 0; background-color: ${c.bg};
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;">
    <!-- Preheader oculto que muchos clientes muestran como preview. -->
    <div style="display: none; max-height: 0; overflow: hidden;">
      ${escapeHtml(preheader)}
    </div>
    <table role="presentation" cellpadding="0" cellspacing="0" border="0"
           width="100%" class="email-bg"
           style="background-color: ${c.bg};">
      <tr><td align="center" style="padding: 32px 16px;">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0"
               width="600" class="card"
               style="background-color: ${c.card}; border-radius: 12px;
                      max-width: 600px; width: 100%;
                      box-shadow: 0 1px 3px rgba(0,0,0,0.08);">
          <tr><td style="padding: 24px 32px;">
            <!-- Header con nombre comercial. -->
            <div style="font-size: 18px; font-weight: 800; color: ${c.brand};
                        margin-bottom: 24px;"
                 class="text-brand">
              ${escapeHtml(appName)}
            </div>
            ${greeting ? `<h1 style="font-size: 22px; font-weight: 800; color: ${c.heading};
                         margin: 0 0 16px 0; line-height: 1.3;"
                  class="text-heading">
              ${escapeHtml(greeting)}
            </h1>` : ""}
            <div style="font-size: 15px; color: ${c.body}; line-height: 1.6;"
                 class="text-body">
              ${bodyHtml}
            </div>
            <table role="presentation" cellpadding="0" cellspacing="0" border="0"
                   width="100%">
              ${ctaBlock}
            </table>
            ${footerNote ? `<hr class="divider"
                style="border: none; border-top: 1px solid ${c.divider}; margin: 24px 0;" />
            <div style="font-size: 13px; color: ${c.muted}; line-height: 1.5;"
                 class="text-muted">
              ${escapeHtml(footerNote)}
            </div>` : ""}
          </td></tr>
        </table>
        <!-- Footer outside the card -->
        <div style="font-size: 12px; color: ${c.footer}; margin-top: 16px;
                    text-align: center; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;"
             class="text-muted">
          &copy; ${new Date().getFullYear()} ${escapeHtml(appName)}
        </div>
      </td></tr>
    </table>
  </body>
</html>`;
}

/**
 * Lee el branding (commercial_name) del singleton `app_branding`.
 * Util para los Edge Functions que no quieren saber del schema.
 */
export async function fetchAppName(
  admin: { from: (table: string) => { select: (cols: string) => { eq: (col: string, v: unknown) => { maybeSingle: () => Promise<{ data: { commercial_name?: string } | null }> } } } },
): Promise<string> {
  const { data } = await admin
    .from("app_branding")
    .select("commercial_name")
    .eq("id", true)
    .maybeSingle();
  return (data?.commercial_name ?? "myapp");
}
