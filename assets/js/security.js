export const EMAIL_MAX = 254;

export function safeText(value, maxLength = 500) {
  return String(value ?? "").replace(/[\u0000-\u001F\u007F]/g, "").trim().slice(0, maxLength);
}

export function validEmail(value) {
  const email = String(value ?? "").trim();
  return email.length <= EMAIL_MAX && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

export function validUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value));
}

export function node(tag, text, className) {
  const el = document.createElement(tag);
  if (text !== undefined) el.textContent = safeText(text, 2000);
  if (className) el.className = className;
  return el;
}

export function statusClass(value) {
  return safeText(value, 30).toLowerCase().replace(/[^a-z0-9_-]/g, "");
}
